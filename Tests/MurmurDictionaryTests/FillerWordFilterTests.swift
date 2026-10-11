import Testing
@testable import MurmurDictionary

@Suite("Filler word filter")
struct FillerWordFilterTests {
    @Test("removes standalone fillers and repairs punctuation spacing")
    func removesStandaloneFillers() {
        let result = FillerWordFilter(words: ["um", "uh"])
            .apply(to: "Um, I think uh, this works.")

        #expect(result.text == "I think this works.")
        #expect(result.removalCount == 2)
    }

    @Test("never removes a filler from inside another word or possessive")
    func protectsLargerWords() {
        let result = FillerWordFilter(words: ["um"])
            .apply(to: "The album hums, and Um's label is intact.")

        #expect(result.text == "The album hums, and Um's label is intact.")
        #expect(result.removalCount == 0)
    }

    @Test("matches multi-word phrases before overlapping shorter rules")
    func longestPhraseFirst() {
        let filter = FillerWordFilter(words: ["you", "you know"])

        #expect(filter.apply(to: "You know, it works.").text == "it works.")
        #expect(filter.apply(to: "You-know, it works.").text == "it works.")
        #expect(filter.apply(to: "Youknow, it works.").text == "it works.")
    }

    @Test("normalizes whitespace, case, and canonical Unicode")
    func normalizesEntries() {
        #expect(FillerWordFilter.normalize("  You\nKNOW  ") == "you know")
        #expect(FillerWordFilter.normalize("  ") == nil)

        let decomposed = "cafe\u{301}"
        let result = FillerWordFilter(words: ["café"]).apply(to: "\(decomposed), next")
        #expect(result.text == "next")
    }

    @Test("an all-filler utterance becomes empty")
    func allFillerBecomesEmpty() {
        let result = FillerWordFilter(words: ["um", "uh"]).apply(to: "um, uh.")

        #expect(result.text.isEmpty)
        #expect(result.removalCount == 2)
    }

    @Test("preserves paragraph breaks while repairing deleted words")
    func preservesParagraphs() {
        let result = FillerWordFilter(words: ["um"])
            .apply(to: "First paragraph.\n\n um, Second paragraph.")

        #expect(result.text == "First paragraph.\n\nSecond paragraph.")
    }

    @Test("filtering before snippets leaves filler words inside saved expansions intact")
    func doesNotAlterSnippetExpansion() {
        let filtered = FillerWordFilter(words: ["um"]).apply(to: "slash intro").text
        let corrector = DictionaryCorrector(entries: [
            .snippet(hear: "slash intro", write: "Um, thanks for your time."),
        ])

        #expect(corrector.apply(to: filtered).text == "Um, thanks for your time.")
    }
}
