import Foundation
import Testing
@testable import Murmur

@Suite("Streaming speech session ownership")
struct StreamingSpeechEngineTests {
    @Test("Finalization bounds every decode and retains a sub-100ms voiced tail")
    func boundedFinalWindows() async throws {
        let recognizer = RecordingRecognizer()
        let engine = makeEngine(recognizer, preview: false)
        let stream = try await engine.start()
        let samples = Array(repeating: Float(0.1), count: 192_000 * 2 + 400)
        await engine.feedSamples(samples)
        await engine.finish()
        let chunks = try await collect(stream)
        let calls = await recognizer.calls
        #expect(calls.map(\.count) == [192_000, 192_000, 1_600])
        #expect(calls.flatMap { $0 }.filter { $0 != 0 } == samples)
        #expect(chunks.last?.text == "part1 part2 part3")
        #expect(chunks.filter(\.isFinal).count == 1)
    }

    @Test("A preview is reused on release and is not appended twice")
    func previewReuse() async throws {
        let recognizer = RecordingRecognizer()
        let engine = makeEngine(recognizer)
        let stream = try await engine.start()
        var iterator = stream.makeAsyncIterator()
        await engine.feedSamples(Array(repeating: 0.1, count: 12_800))
        let preview = try await iterator.next()
        #expect(preview?.text == "part1")
        #expect(preview?.isFinal == false)
        await engine.feedSamples(Array(repeating: 0, count: 8_000))
        await engine.finish()
        var chunks: [TranscriptionChunk] = []
        while let chunk = try await iterator.next() { chunks.append(chunk) }
        #expect(await recognizer.calls.count == 1)
        #expect(chunks.last?.text == "part1")
        #expect(chunks.last?.isFinal == true)
    }

    @Test("Audio arriving during a commit remains in the next window")
    func samplesDuringInference() async throws {
        let recognizer = RecordingRecognizer(holdFirst: true)
        let engine = makeEngine(recognizer, preview: false)
        let stream = try await engine.start()
        let first = Array(repeating: Float(0.1), count: 24_000) + Array(repeating: Float(0), count: 8_000)
        let second = Array(repeating: Float(0.2), count: 4_000)
        await engine.feedSamples(first)
        await recognizer.waitForFirstCall()
        await engine.feedSamples(second)
        await recognizer.releaseFirst()
        await engine.finish()
        let chunks = try await collect(stream)
        #expect(await recognizer.calls == [first, second])
        #expect(chunks.last?.text == "part1 part2")
    }

    @Test("Cancelling model preparation prevents a stale start")
    func cancelDuringPreparation() async throws {
        let gate = PreparationGate()
        let engine = StreamingSpeechEngine(modelID: "fake", prepare: { await gate.prepare() }, recognize: { _ in "text" })
        let start = Task { try await engine.start() }
        await gate.waitUntilEntered()
        await engine.cancel()
        await gate.release()
        do { _ = try await start.value; Issue.record("Cancelled preparation started a stream") }
        catch { #expect(error is CancellationError) }
        let next = try await engine.start()
        await engine.finish()
        #expect(try await collect(next).last?.isFinal == true)
    }

    @Test("A late cancelled inference cannot publish into a replacement session")
    func cancelDuringInference() async throws {
        let recognizer = RecordingRecognizer(holdFirst: true)
        let engine = makeEngine(recognizer)
        let cancelledStream = try await engine.start()
        await engine.feedSamples(Array(repeating: 0.1, count: 12_800))
        await recognizer.waitForFirstCall()
        await engine.cancel()
        do { _ = try await collect(cancelledStream); Issue.record("Cancelled stream finished successfully") }
        catch { #expect(error is CancellationError) }

        let next = try await engine.start()
        await engine.feedSamples(Array(repeating: 0.2, count: 2_000))
        await recognizer.releaseFirst()
        await engine.finish()
        let chunks = try await collect(next)
        #expect(chunks.last?.text == "part2")
        #expect(chunks.allSatisfy { !$0.text.contains("part1") })
    }

    @Test("Terminal inference errors stop the timer instead of retrying forever")
    func terminalError() async throws {
        let recognizer = RecordingRecognizer(failFirst: true)
        let engine = makeEngine(recognizer)
        let stream = try await engine.start()
        await engine.feedSamples(Array(repeating: 0.1, count: 12_800))
        do { _ = try await collect(stream); Issue.record("Expected recognition failure") }
        catch { #expect(error is RecordingRecognizer.Failure) }
        try await Task.sleep(for: .milliseconds(30))
        #expect(await recognizer.calls.count == 1)
        let next = try await engine.start()
        await engine.feedSamples(Array(repeating: 0.2, count: 2_000))
        await engine.finish()
        #expect(try await collect(next).last?.text == "part2")
    }

    @Test("An oversized incoming buffer fails explicitly before samples are lost")
    func backlogOverflow() async throws {
        let recognizer = RecordingRecognizer()
        let engine = makeEngine(recognizer, preview: false)
        let stream = try await engine.start()
        await engine.feedSamples(Array(repeating: 0.1, count: 16_000 * 120 + 1))
        do { _ = try await collect(stream); Issue.record("Expected backlog overflow") }
        catch { #expect(error is TranscriptionError) }
        #expect(await recognizer.calls.isEmpty)
    }

    private func makeEngine(_ recognizer: RecordingRecognizer, preview: Bool = true) -> StreamingSpeechEngine {
        StreamingSpeechEngine(
            modelID: "fake", previewEnabled: preview, prepare: {},
            recognize: { try await recognizer.run($0) }, pollInterval: .milliseconds(1)
        )
    }

    private func collect(_ stream: AsyncThrowingStream<TranscriptionChunk, Error>) async throws -> [TranscriptionChunk] {
        var chunks: [TranscriptionChunk] = []
        for try await chunk in stream { chunks.append(chunk) }
        return chunks
    }
}

private actor RecordingRecognizer {
    enum Failure: Error { case expected }
    private(set) var calls: [[Float]] = []
    private let holdFirst: Bool
    private let failFirst: Bool
    private var held: CheckedContinuation<Void, Never>?
    private var firstCallWaiter: CheckedContinuation<Void, Never>?

    init(holdFirst: Bool = false, failFirst: Bool = false) {
        self.holdFirst = holdFirst
        self.failFirst = failFirst
    }

    func run(_ samples: [Float]) async throws -> String {
        calls.append(samples)
        let call = calls.count
        if call == 1 {
            if holdFirst {
                await withCheckedContinuation { continuation in
                    held = continuation
                    firstCallWaiter?.resume()
                    firstCallWaiter = nil
                }
            } else {
                firstCallWaiter?.resume()
                firstCallWaiter = nil
            }
            if failFirst { throw Failure.expected }
        }
        return "part\(call)"
    }

    func waitForFirstCall() async {
        if !calls.isEmpty { return }
        await withCheckedContinuation { firstCallWaiter = $0 }
    }

    func releaseFirst() {
        held?.resume()
        held = nil
    }
}

private actor PreparationGate {
    private var entered = false
    private var held: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    func prepare() async {
        if entered { return }
        entered = true
        await withCheckedContinuation { continuation in
            held = continuation
            waiter?.resume()
            waiter = nil
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release() {
        held?.resume()
        held = nil
    }
}
