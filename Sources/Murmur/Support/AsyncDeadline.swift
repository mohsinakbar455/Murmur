import Foundation

/// A cancelled or expired request returns promptly even when an inference backend
/// is slow to cooperate with cancellation. Its late result can never be delivered.
enum AsyncDeadline {
    struct Expired: LocalizedError {
        var errorDescription: String? { "Writing cleanup took too long; basic cleanup was used." }
    }

    static func run<Value: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let race = DeadlineRace<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.setContinuation(continuation)
                let work = Task {
                    do { race.finish(.success(try await operation())) }
                    catch { race.finish(.failure(error)) }
                }
                let timer = Task {
                    do {
                        try await Task.sleep(for: .seconds(max(0, seconds)))
                        race.finish(.failure(Expired()))
                    } catch { }
                }
                race.setTasks([work, timer])
            }
        } onCancel: { race.finish(.failure(CancellationError())) }
    }
}

private final class DeadlineRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var tasks: [Task<Void, Never>] = []

    func setContinuation(_ continuation: CheckedContinuation<Value, Error>) {
        let completed: Result<Value, Error>? = lock.withLock {
            if let result { return result }
            self.continuation = continuation
            return nil as Result<Value, Error>?
        }
        if let completed { continuation.resume(with: completed) }
    }

    func setTasks(_ tasks: [Task<Void, Never>]) {
        let cancel = lock.withLock {
            if result != nil { return true }
            self.tasks = tasks
            return false
        }
        if cancel { tasks.forEach { $0.cancel() } }
    }

    func finish(_ result: Result<Value, Error>) {
        let delivery = lock.withLock { () -> (CheckedContinuation<Value, Error>?, [Task<Void, Never>]) in
            guard self.result == nil else { return (nil, []) }
            self.result = result
            let delivery = (continuation, tasks)
            continuation = nil
            tasks = []
            return delivery
        }
        delivery.0?.resume(with: result)
        delivery.1.forEach { $0.cancel() }
    }
}
