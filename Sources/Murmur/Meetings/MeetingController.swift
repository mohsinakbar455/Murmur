import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class MeetingController {
    static let shared = MeetingController()
    enum State: String { case idle, preparing, recording, finishing }
    private(set) var state: State = .idle
    private(set) var activeMeetingID: UUID?
    private(set) var elapsed: TimeInterval = 0
    private(set) var errorMessage: String?
    private(set) var summarizingIDs: Set<UUID> = []
    private(set) var retryingIDs: Set<UUID> = []
    let store: MeetingStore
    var isRecording: Bool { state == .recording }
    var isBusy: Bool { state != .idle }

    private let microphone = AudioCapture()
    private var systemAudio: MeetingSystemAudio?
    private var microphoneSegments: MeetingSegmenter?
    private var remoteSegments: MeetingSegmenter?
    private var continuation: AsyncStream<MeetingAudioPacket>.Continuation?
    private var transcriptionTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var captureStarted: Date?
    // Audio is never persisted. A bounded retry cache survives only this app session.
    private var failedAudio: [UUID: (meetingID: UUID, packet: MeetingAudioPacket)] = [:]
    private var failedOrder: [UUID] = []
    private let maximumRetryChunks = 4
    @ObservationIgnored private var isTerminating = false
    @ObservationIgnored private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(store: MeetingStore? = nil) { self.store = store ?? MeetingStore() }

    func dismissError() { errorMessage = nil }

    func start(source: MeetingCaptureSource = .microphone, title: String = "", modelID: String? = nil) async {
        guard !isBusy, !isTerminating else { return }
        state = .preparing
        errorMessage = nil
        let settings = Settings.shared
        let selectedModel = modelID ?? settings.selectedModelID
        let language = settings.selectedLanguage
        let microphoneID = settings.selectedMicrophoneID
        do {
            let permitted = switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: true
            case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
            default: false
            }
            // Termination must not wait for a system permission dialog. A late answer
            // belongs to the abandoned start and must not change state or open capture.
            guard !isTerminating else { return }
            guard permitted else { throw MeetingCaptureError.message("Allow Murmur to use the microphone in System Settings → Privacy & Security → Microphone, then try again.") }
            try await SpeechRecognitionService.shared.prepare(modelID: selectedModel)
            guard !isTerminating else { return }
            try Task.checkCancellation()
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) else {
                throw MeetingCaptureError.message("Could not prepare meeting audio.")
            }
            let date = Date()
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let record = MeetingRecord(title: trimmedTitle.isEmpty ? "Meeting · \(date.formatted(date: .abbreviated, time: .shortened))" : trimmedTitle,
                                       startedAt: date, source: source.label, modelID: selectedModel, language: language)
            try store.save(record)
            activeMeetingID = record.id
            let (stream, sink) = AsyncStream<MeetingAudioPacket>.makeStream(bufferingPolicy: .bufferingOldest(12))
            continuation = sink
            let emit: @Sendable (MeetingAudioPacket) -> Void = { [weak self] packet in
                if case .dropped = sink.yield(packet) {
                    Task { @MainActor in self?.handleOverflow(packet, meetingID: record.id) }
                }
            }
            let micSegments = MeetingSegmenter(speaker: .you, emit: emit)
            let remote = MeetingSegmenter(speaker: .remote, emit: emit)
            microphoneSegments = micSegments
            remoteSegments = remote
            if source.includesSystemAudio {
                let tap = MeetingSystemAudio()
                try tap.start(source: source) { remote.push($0) }
                systemAudio = tap
            }
            try microphone.start(outputFormat: format, selectedMicrophoneID: microphoneID, onBuffer: { chunk in
                guard let pointer = chunk.buffer.floatChannelData?[0] else { return }
                micSegments.push(Array(UnsafeBufferPointer(start: pointer, count: Int(chunk.buffer.frameLength))))
            }, onLevel: { _ in })
            captureStarted = date
            elapsed = 0
            state = .recording
            transcriptionTask = Task { [weak self] in
                for await packet in stream {
                    guard let self else { break }
                    await self.transcribe(packet, meetingID: record.id, modelID: selectedModel, language: language)
                }
            }
            timerTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { break }
                    guard let self, self.isRecording else { break }
                    self.elapsed = Date().timeIntervalSince(date)
                    if let tap = self.systemAudio, let output = try? MeetingSystemAudio.defaultOutput(), output != tap.outputDevice {
                        self.errorMessage = "The Mac audio output changed. Recording stopped to avoid losing the remote side. Check your output device, then start a new meeting."
                        await self.stop()
                        break
                    }
                }
            }
        } catch {
            // An outstanding prepare call can throw after termination already abandoned
            // this start. Do not publish that stale error or mutate the settled state.
            guard !isTerminating else { return }
            microphone.stop()
            systemAudio?.stop()
            systemAudio = nil
            microphoneSegments = nil
            remoteSegments = nil
            continuation?.finish()
            continuation = nil
            captureStarted = nil
            elapsed = 0
            if let id = activeMeetingID { try? store.update(id) { $0.endedAt = Date(); $0.interrupted = true } }
            activeMeetingID = nil
            state = .idle
            errorMessage = error.localizedDescription
        }
    }

    /// Stop producers first, flush both segmenters, close the queue, then await every queued decode.
    func stop() async {
        guard state == .recording else { return }
        state = .finishing
        let captureEndedAt = Date()
        timerTask?.cancel()
        timerTask = nil
        microphone.stop()
        systemAudio?.stop()
        systemAudio = nil
        microphoneSegments?.finish()
        remoteSegments?.finish()
        microphoneSegments = nil
        remoteSegments = nil
        continuation?.finish()
        continuation = nil
        let pending = transcriptionTask
        transcriptionTask = nil
        await pending?.value
        if let id = activeMeetingID {
            do { try store.update(id) { $0.endedAt = captureEndedAt } }
            catch { errorMessage = "Could not finish saving the meeting: \(error.localizedDescription)" }
        }
        if let captureStarted { elapsed = captureEndedAt.timeIntervalSince(captureStarted) }
        captureStarted = nil
        activeMeetingID = nil
        state = .idle
        let waiting = drainWaiters
        drainWaiters.removeAll()
        for continuation in waiting { continuation.resume() }
    }

    /// Permanently closes the start gate, then waits for any accepted audio to finish.
    /// Preparing does not own capture yet and is abandoned without awaiting permissions.
    func prepareForTermination() async {
        isTerminating = true
        switch state {
        case .preparing:
            state = .idle
        case .recording:
            await stop()
        case .finishing:
            // stop() may already have moved its worker reference into a local before
            // awaiting it. Wait for the full stop transaction, including persistence.
            await withCheckedContinuation { continuation in
                drainWaiters.append(continuation)
            }
        case .idle:
            break
        }
    }

    private func handleOverflow(_ packet: MeetingAudioPacket, meetingID: UUID) {
        let gap = MeetingSegment(id: packet.id, start: packet.start, end: packet.end, speaker: packet.speaker, text: "",
                                 issue: "The speech engine could not keep up. This interval was not transcribed.")
        do { try store.update(meetingID) { $0.segments.append(gap); $0.interrupted = true } }
        catch { errorMessage = error.localizedDescription }
        errorMessage = "The speech engine could not keep up, so recording stopped. A gap is marked in the transcript. Choose a faster speech model before starting again."
        Task { [weak self] in
            guard let self, self.activeMeetingID == meetingID else { return }
            await self.stop()
        }
    }

    private func transcribe(_ packet: MeetingAudioPacket, meetingID: UUID, modelID: String, language: String) async {
        do {
            let text = try await SpeechRecognitionService.shared.transcribe(samples: packet.samples, modelID: modelID,
                                                                           language: language == "auto" ? nil : language)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let segment = MeetingSegment(id: packet.id, start: packet.start, end: packet.end, speaker: packet.speaker, text: text)
            try store.update(meetingID) { meeting in
                if let index = meeting.segments.firstIndex(where: { $0.id == packet.id }) { meeting.segments[index] = segment }
                else { meeting.segments.append(segment) }
            }
            failedAudio[packet.id] = nil
            failedOrder.removeAll { $0 == packet.id }
        } catch {
            errorMessage = "A meeting segment could not be transcribed: \(error.localizedDescription)"
            failedAudio[packet.id] = (meetingID, packet)
            failedOrder.removeAll { $0 == packet.id }
            failedOrder.append(packet.id)
            while failedOrder.count > maximumRetryChunks { failedAudio[failedOrder.removeFirst()] = nil }
            let segment = MeetingSegment(id: packet.id, start: packet.start, end: packet.end, speaker: packet.speaker, text: "", issue: error.localizedDescription)
            do {
                try store.update(meetingID) { meeting in
                    if let index = meeting.segments.firstIndex(where: { $0.id == packet.id }) { meeting.segments[index] = segment }
                    else { meeting.segments.append(segment) }
                }
            } catch { errorMessage = "Meeting storage failed: \(error.localizedDescription). Recording stopped."
                Task { await stop() }
            }
        }
    }

    func hasRetryAudio(for segmentID: UUID) -> Bool { failedAudio[segmentID] != nil }

    func retry(segmentID: UUID) async {
        guard !isBusy, !retryingIDs.contains(segmentID), let failed = failedAudio[segmentID], let meeting = store.meeting(failed.meetingID) else { return }
        retryingIDs.insert(segmentID)
        defer { retryingIDs.remove(segmentID) }
        await transcribe(failed.packet, meetingID: meeting.id, modelID: meeting.modelID, language: meeting.language)
    }

    func generateNotes(for id: UUID) async {
        guard !isBusy, !summarizingIDs.contains(id), let meeting = store.meeting(id), meeting.segments.contains(where: { !$0.text.isEmpty }) else { return }
        summarizingIDs.insert(id)
        defer { summarizingIDs.remove(id) }
        do {
            let summary = try await TextProcessingService.shared.summarizeMeeting(meeting.summaryInput)
            guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MeetingCaptureError.message("The writing model returned no notes. Try again or select another writing model.")
            }
            try MeetingSummaryValidator.validate(summary, against: meeting)
            try store.update(id) { $0.acceptDraftSummary(summary) }
        } catch { errorMessage = "Notes could not be generated: \(error.localizedDescription). Your transcript is saved; you can retry." }
    }

    func setActionDone(meetingID: UUID, actionID: UUID, done: Bool) {
        do {
            try store.update(meetingID) { meeting in
                if let index = meeting.actionItems.firstIndex(where: { $0.id == actionID }) { meeting.actionItems[index].isDone = done }
            }
        } catch { errorMessage = "Could not save the action: \(error.localizedDescription)" }
    }

    func updateDetails(id: UUID, title: String? = nil, notes: String? = nil) {
        do { try store.update(id) { if let title { $0.title = title }; if let notes { $0.notes = notes } } }
        catch { errorMessage = "Could not save changes: \(error.localizedDescription)" }
    }

    func delete(_ id: UUID) {
        guard id != activeMeetingID, !summarizingIDs.contains(id) else { return }
        do {
            try store.delete(id)
            let removed = failedAudio.filter { $0.value.meetingID == id }.map(\.key)
            for key in removed { failedAudio[key] = nil }
            failedOrder.removeAll { removed.contains($0) }
        } catch { errorMessage = "Could not delete the meeting: \(error.localizedDescription)" }
    }
}
