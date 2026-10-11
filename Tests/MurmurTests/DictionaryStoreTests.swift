import MurmurDictionary
import Testing

@testable import Murmur

@MainActor
struct DictionaryStoreTests {
    @Test("personalization file parses terms, corrections, and snippets")
    func parsesEveryEntryKind() {
        let entries = DictionaryStore.parse(
            """
            Anthropic
            cloud code -> Claude Code
            slash intro => Hi, I would love to connect.
            """
        )

        #expect(entries.count == 3)
        #expect(entries[0].kind == .term)
        #expect(entries[1].kind == .correction)
        #expect(entries[2].kind == .snippet)
        #expect(entries[2].hear == "slash intro")
        #expect(entries[2].write == "Hi, I would love to connect.")
    }

    @Test("snippet file syntax survives serialization")
    func snippetFileLine() {
        let entry = DictionaryEntry.snippet(
            hear: "slash intro",
            write: "Hi, I would love to connect."
        )

        #expect(entry.fileLine == "slash intro => Hi, I would love to connect.")
    }
}
