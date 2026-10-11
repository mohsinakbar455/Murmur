import Testing
@testable import Murmur

@Suite("Text formatter responsibilities")
struct TextFormatterTests {
    @Test("basic formatting preserves filler words for the personalization filter")
    func basicFormattingPreservesFillers() async {
        let output = await RuleBasedFormatter().format("um this still has uh filler words")

        #expect(output == "Um this still has uh filler words.")
    }
}
