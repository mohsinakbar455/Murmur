import Foundation
import Testing
@testable import Murmur

@Suite("Meeting capture and persistence")
struct MeetingTests {
    @Test("Termination blocks a late recording start without touching audio or models")
    @MainActor
    func terminationClosesStartGate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = MeetingController(store: MeetingStore(directory: directory))
        await controller.prepareForTermination()
        await controller.start(modelID: "must-never-prepare")
        #expect(controller.state == .idle)
        #expect(controller.activeMeetingID == nil)
        #expect(controller.store.meetings.isEmpty)
        #expect(controller.errorMessage == nil)
    }

    @Test("Silence does not create invented transcript segments")
    func silence() {
        let packets = PacketCollector()
        let segmenter = MeetingSegmenter(speaker: .you) { packets.append($0) }
        for _ in 0..<1000 { segmenter.push([Float](repeating: 0, count: 320)) }
        segmenter.finish()
        #expect(packets.snapshot.isEmpty)
        #expect(segmenter.bufferedSamples <= 3200)
    }

    @Test("A pause emits speech with channel and monotonically increasing timestamps")
    func pauseSegmentation() {
        let packets = PacketCollector()
        let segmenter = MeetingSegmenter(speaker: .remote, offset: 0.25) { packets.append($0) }
        for _ in 0..<25 { segmenter.push([Float](repeating: 0.03, count: 320)) }
        for _ in 0..<35 { segmenter.push([Float](repeating: 0, count: 320)) }
        #expect(packets.snapshot.count == 1)
        #expect(packets.snapshot.first?.speaker == .remote)
        #expect(packets.snapshot.first?.start == 0.25)
        #expect((packets.snapshot.first?.end ?? 0) > 1.0)
    }

    @Test("Continuous speech is bounded and stop flushes the final utterance exactly once")
    func boundedCapture() {
        let packets = PacketCollector()
        let segmenter = MeetingSegmenter(speaker: .you) { packets.append($0) }
        for _ in 0..<1300 {
            segmenter.push([Float](repeating: 0.02, count: 320))
            #expect(segmenter.bufferedSamples <= MeetingSegmenter.sampleRate * MeetingSegmenter.maximumSeconds + 3200)
        }
        segmenter.finish()
        segmenter.finish()
        segmenter.push([Float](repeating: 0.1, count: 32_000))
        let result = packets.snapshot
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.samples.count <= MeetingSegmenter.maximumSeconds * MeetingSegmenter.sampleRate })
        #expect(result.last?.end == 26)
        #expect(result[1].start == result[0].end)
    }

    @Test("Very short clicks are discarded")
    func shortNoise() {
        let packets = PacketCollector()
        let segmenter = MeetingSegmenter(speaker: .you) { packets.append($0) }
        segmenter.push([Float](repeating: 0.2, count: 640))
        segmenter.finish()
        #expect(packets.snapshot.isEmpty)
    }

    @Test("Meeting transcript includes evidence timestamps and explicit gap markers")
    func noteInput() {
        var meeting = fixture()
        meeting.segments = [
            MeetingSegment(start: 65, end: 68, speaker: .remote, text: "I will send the draft on Friday."),
            MeetingSegment(start: 0, end: 2, speaker: .you, text: "Let's discuss the design."),
            MeetingSegment(start: 12, end: 14, speaker: .remote, text: "", issue: "Engine unavailable")
        ]
        #expect(meeting.transcript.hasPrefix("[00:00:00–00:00:02] You:"))
        #expect(meeting.summaryInput.contains("[00:01:05–00:01:08] Remote: I will send the draft on Friday."))
        #expect(meeting.summaryInput.contains("Transcription gap: Engine unavailable"))
        #expect(meeting.summaryInput.contains("not individual remote participants"))
    }

    @Test("SRT uses numbered cues, millisecond timestamps, and positive durations")
    func subtitles() throws {
        var meeting = fixture()
        meeting.segments = [
            MeetingSegment(start: 3601.25, end: 3602.5, speaker: .remote, text: "Confirmed."),
            MeetingSegment(start: 1.125, end: 1.125, speaker: .you, text: "First line.\n\n\nSecond line.")
        ]
        let text = String(decoding: try MeetingExport.srt.data(for: meeting), as: UTF8.self)
        #expect(text.hasPrefix("1\n00:00:01,125 --> 00:00:01,126\nYou:"))
        #expect(text.contains("2\n01:00:01,250 --> 01:00:02,500\nRemote: Confirmed."))
        #expect(!text.contains("First line.\n\n"))
        #expect(MeetingExport.subtitleTime(-1) == "00:00:00,000")
    }

    @Test("All exports preserve transcript and JSON round trips")
    func exports() throws {
        var meeting = fixture()
        meeting.segments = [MeetingSegment(start: 0, end: 2, speaker: .you, text: "Murmur design review.")]
        meeting.notes = "My note"
        meeting.draftSummary = "## Actions\n- Review the design [00:00:00]."
        let restored = try JSONDecoder().decode(MeetingRecord.self, from: MeetingExport.json.data(for: meeting))
        #expect(restored == meeting)
        for format in [MeetingExport.markdown, .text, .srt] {
            #expect(String(decoding: try format.data(for: meeting), as: UTF8.self).contains("Murmur design review."))
        }
    }

    @Test("Action checkboxes retain completion when notes are regenerated")
    func actionChecklist() {
        var meeting = fixture()
        let summary = "## Summary\n- Discussed designs [00:00:00].\n## Action items\n- Alex: send draft [00:01:05].\n- None recorded."
        meeting.acceptDraftSummary(summary)
        #expect(meeting.actionItems.count == 1)
        meeting.actionItems[0].isDone = true
        let id = meeting.actionItems[0].id
        meeting.acceptDraftSummary(summary)
        #expect(meeting.actionItems[0].id == id)
        #expect(meeting.actionItems[0].isDone)
        #expect(meeting.actionChecklist.hasPrefix("- [x] Alex"))
    }

    @Test("Meeting drafts accept real citations and owners named in their source")
    func groundedSummary() throws {
        var meeting = fixture()
        meeting.segments = [MeetingSegment(start: 65, end: 68, speaker: .remote, text: "Alex will send the draft on Friday.")]
        try MeetingSummaryValidator.validate("## Summary\n- A draft is due [00:01:05–00:01:08].\n## Action items\n- Alex: send the draft on Friday [00:01:05].", against: meeting)
        try MeetingSummaryValidator.validate("## Action items\n- Unassigned: review the draft [00:01:05].", against: meeting)
    }

    @Test("Invented timestamps, uncited claims and unsupported owners are rejected")
    func rejectsUngroundedSummary() {
        var meeting = fixture()
        meeting.segments = [MeetingSegment(start: 65, end: 68, speaker: .remote, text: "Alex will send the draft on Friday.")]
        for draft in [
            "## Summary\n- We agreed [00:01:06].",
            "## Summary\n- We agreed [00:01:05–00:01:10].",
            "## Summary\n- A claim without evidence.",
            "## Action items\n- Morgan: send the draft [00:01:05].",
            "## Action items\n- You: send the draft [00:01:05].",
            "## Action items\n- Send the draft [00:01:05]."
        ] {
            #expect(throws: (any Error).self) { try MeetingSummaryValidator.validate(draft, against: meeting) }
        }
    }

    @Test("A transcription gap cannot be cited as evidence")
    func gapsAreNotEvidence() {
        var meeting = fixture()
        meeting.segments = [MeetingSegment(start: 5, end: 8, speaker: .you, text: "", issue: "Model unavailable")]
        #expect(throws: (any Error).self) {
            try MeetingSummaryValidator.validate("## Decisions\n- Approved [00:00:05].", against: meeting)
        }
    }

    @Test("Search covers title, personal notes, draft notes and spoken text")
    func searching() {
        var meeting = fixture()
        meeting.notes = "Roadmap"
        meeting.draftSummary = "DECISIONS"
        meeting.segments = [MeetingSegment(start: 0, end: 1, speaker: .you, text: "Launch on Friday")]
        #expect(meeting.matches("review"))
        #expect(meeting.matches("roadmap"))
        #expect(meeting.matches("decisions"))
        #expect(meeting.matches("friday"))
        #expect(!meeting.matches("unrelated"))
    }

    @Test("Saved segments survive relaunch and interrupted sessions recover")
    @MainActor
    func persistenceAndRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = MeetingStore(directory: directory)
        var meeting = fixture()
        meeting.segments = [MeetingSegment(start: 4, end: 7, speaker: .you, text: "Saved incrementally")]
        try first.save(meeting)
        let second = MeetingStore(directory: directory)
        let restored = try #require(second.meeting(meeting.id))
        #expect(restored.interrupted)
        #expect(restored.segments == meeting.segments)
        #expect(restored.endedAt == meeting.startedAt.addingTimeInterval(7))
        #expect(second.meetings.count == 1)
        try second.delete(meeting.id)
        #expect(MeetingStore(directory: directory).meetings.isEmpty)
    }

    @Test("Documents missing new fields migrate without losing their transcript")
    func migration() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","title":"Old meeting","startedAt":0,"segments":[]}
        """
        let meeting = try JSONDecoder().decode(MeetingRecord.self, from: Data(json.utf8))
        #expect(meeting.id == id)
        #expect(meeting.notes.isEmpty)
        #expect(meeting.draftSummary.isEmpty)
        #expect(meeting.source == "Microphone only")
        #expect(meeting.schemaVersion == 1)
    }

    @Test("Unreadable and future-version documents are preserved, with visible warnings")
    @MainActor
    func corruptDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("broken.json")
        let original = Data("{broken".utf8)
        try original.write(to: file)
        let store = MeetingStore(directory: directory)
        #expect(store.meetings.isEmpty)
        #expect(store.loadWarnings.count == 1)
        #expect(try Data(contentsOf: file) == original)
        var future = fixture()
        future.schemaVersion = 999
        let futureData = try JSONEncoder().encode(future)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(MeetingRecord.self, from: futureData) }
    }

    private func fixture() -> MeetingRecord {
        MeetingRecord(title: "Design review", startedAt: Date(timeIntervalSince1970: 1_700_000_000), source: "Microphone only", modelID: "parakeet-v3", language: "auto")
    }
}

private final class PacketCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var packets: [MeetingAudioPacket] = []
    var snapshot: [MeetingAudioPacket] { lock.lock(); defer { lock.unlock() }; return packets }
    func append(_ packet: MeetingAudioPacket) { lock.lock(); packets.append(packet); lock.unlock() }
}
