import Foundation
import Observation

/// Live data source for the native dashboard and history controls.
@MainActor
@Observable
final class RunStore {
    static let shared = RunStore()

    private(set) var runs: [DictationRun] = []

    private init() { reload() }

    func reload() {
        runs = RunLog.load()
    }
}
