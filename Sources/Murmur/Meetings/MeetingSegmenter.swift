import Foundation

struct MeetingAudioPacket: Sendable {
    var id = UUID()
    let samples: [Float]
    let start: TimeInterval
    let end: TimeInterval
    let speaker: MeetingSpeaker
}

/// Energy segmentation retains at most one short utterance, not a recording-long array.
/// The lock serializes capture callbacks with the final flush after devices stop.
final class MeetingSegmenter: @unchecked Sendable {
    static let sampleRate = 16_000
    static let maximumSeconds = 12
    private let lock = NSLock()
    private var pending: [Float] = []
    private var speech: [Float] = []
    private var preRoll: [Float] = []
    private var elapsedSamples = 0
    private var startedSample = 0
    private var voicedFrames = 0
    private var quietFrames = 0
    private let frameCount = 320
    private let speaker: MeetingSpeaker
    private let offset: TimeInterval
    private let emit: @Sendable (MeetingAudioPacket) -> Void
    private var closed = false

    init(speaker: MeetingSpeaker, offset: TimeInterval = 0, emit: @escaping @Sendable (MeetingAudioPacket) -> Void) {
        self.speaker = speaker
        self.offset = offset
        self.emit = emit
    }

    var bufferedSamples: Int {
        lock.lock(); defer { lock.unlock() }
        return speech.count + preRoll.count + pending.count
    }

    func push(_ samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        pending.append(contentsOf: samples)
        var cursor = 0
        while cursor + frameCount <= pending.count {
            let frame = Array(pending[cursor..<(cursor + frameCount)])
            consume(frame)
            cursor += frameCount
        }
        pending.removeFirst(cursor)
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        if !pending.isEmpty { consume(pending); pending.removeAll() }
        flush()
        closed = true
    }

    private func consume(_ frame: [Float]) {
        let rms = sqrt(frame.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, frame.count)))
        let voiced = rms >= (speaker == .you ? 0.004 : 0.003)
        if speech.isEmpty && !voiced {
            preRoll.append(contentsOf: frame)
            if preRoll.count > 3200 { preRoll.removeFirst(preRoll.count - 3200) }
            elapsedSamples += frame.count
            return
        }
        if speech.isEmpty {
            startedSample = max(0, elapsedSamples - preRoll.count)
            speech = preRoll
            preRoll.removeAll(keepingCapacity: true)
        }
        speech.append(contentsOf: frame)
        elapsedSamples += frame.count
        if voiced { voicedFrames += 1; quietFrames = 0 } else { quietFrames += 1 }
        if quietFrames >= 30 || speech.count >= Self.maximumSeconds * Self.sampleRate { flush() }
    }

    private func flush() {
        if voicedFrames >= 10 && !speech.isEmpty {
            emit(MeetingAudioPacket(samples: speech, start: offset + Double(startedSample) / Double(Self.sampleRate),
                                    end: offset + Double(elapsedSamples) / Double(Self.sampleRate), speaker: speaker))
        }
        speech.removeAll(keepingCapacity: true)
        voicedFrames = 0
        quietFrames = 0
    }
}
