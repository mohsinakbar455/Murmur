import Foundation
import Testing
@testable import Murmur

@Suite("Filler word store")
struct FillerWordStoreTests {
    @Test("starts enabled with conservative defaults")
    @MainActor
    func defaults() {
        withTemporaryStore { store, _ in
            #expect(store.isEnabled)
            #expect(store.words == FillerWordStore.defaultWords)
        }
    }

    @Test("normalizes, rejects duplicates, and persists changes")
    @MainActor
    func persistence() {
        withTemporaryStore { store, fileURL in
            #expect(store.add("  You   Know "))
            #expect(!store.add("you know"))
            store.setEnabled(false)

            let reopened = FillerWordStore(fileURL: fileURL)
            #expect(!reopened.isEnabled)
            #expect(reopened.words.contains("you know"))
            #expect(reopened.apply(to: "You know, this stays.").text == "You know, this stays.")
        }
    }

    @Test("delete and reset only affect the filler list")
    @MainActor
    func deleteAndReset() {
        withTemporaryStore { store, _ in
            store.delete("um")
            #expect(!store.words.contains("um"))

            store.add("like")
            store.resetToDefaults()
            #expect(store.words == FillerWordStore.defaultWords)
            #expect(!store.words.contains("like"))
        }
    }

    @MainActor
    private func withTemporaryStore(
        _ body: (FillerWordStore, URL) -> Void
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-filler-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("filler-words.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        body(FillerWordStore(fileURL: fileURL), fileURL)
    }
}
