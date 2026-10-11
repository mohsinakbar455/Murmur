import Foundation
import Testing
import MurmurDictionary
@testable import Murmur

@Suite("Spoken emoji and list intent")
struct DictationIntentTests {
    @Test(arguments: [
        ("amazing bro fire emoji", "amazing bro 🔥"),
        ("amazing bro add fire emoji", "amazing bro 🔥"),
        ("Okay, this fire emoji, add fire emoji", "Okay, this 🔥, 🔥"),
        ("Fire emoji", "🔥"),
        ("great add a fire emoji", "great 🔥"),
        ("nice thumbs-up emoji", "nice 👍"),
        ("fire emoji fire emoji", "🔥 🔥"),
        ("well done red heart emoji", "well done ❤️"),
        ("wow 🔥 thumbs up emoji", "wow 🔥 👍"),
        ("great fire emoji new line thanks", "great 🔥 new line thanks"),
        ("The fire emoji means excitement.", "The fire emoji means excitement."),
        ("What does fire emoji mean?", "What does fire emoji mean?"),
        ("Don't add a fire emoji.", "Don't add a fire emoji."),
        ("Write the words fire emoji.", "Write the words fire emoji."),
        ("say \"fire emoji\"", "say \"fire emoji\""),
        ("Use `fire emoji` here.", "Use `fire emoji` here."),
        ("amazing bro fire", "amazing bro fire"),
        ("quokka emoji", "quokka emoji"),
        ("not bad fire emoji", "not bad 🔥"),
        ("I want to add a fire emoji to the button", "I want to add a fire emoji to the button")
    ])
    func emoji(input: String, expected: String) {
        #expect(DictationIntent.emoji(input) == expected)
        #expect(DictationIntent.emoji(expected) == expected)
    }

    @Test(arguments: [
        ("I want to buy MacBook, headphones, fish food, and PC bear.", "I want to buy:\n- MacBook\n- headphones\n- fish food\n- PC bear"),
        ("I need to buy milk, eggs and bread", "I need to buy:\n- milk\n- eggs\n- bread"),
        ("Shopping list: milk, eggs, and bread", "Shopping list:\n- milk\n- eggs\n- bread"),
        ("I want to buy bread, milk, and fish and chips", "I want to buy:\n- bread\n- milk\n- fish and chips"),
        ("I need to buy 2 apples, 3 pears, and 4 bananas", "I need to buy:\n- 2 apples\n- 3 pears\n- 4 bananas"),
        ("number one open the app number two choose a model", "1. open the app\n2. choose a model"),
        ("firstly open the app secondly choose a model", "1. open the app\n2. choose a model"),
        ("first, open the app second, choose a model", "1. open the app\n2. choose a model"),
        ("Tasks: bullet point send the draft bullet point book the room", "Tasks:\n- send the draft\n- book the room"),
        ("I like tea, coffee, and juice.", "I like tea, coffee, and juice."),
        ("I want to buy a MacBook and headphones.", "I want to buy a MacBook and headphones."),
        ("I want to buy milk, but I forgot my wallet, and went home.", "I want to buy milk, but I forgot my wallet, and went home."),
        ("I want to buy milk, eggs, and bread. See you soon.", "I want to buy milk, eggs, and bread. See you soon."),
        ("I need to buy 1,000 screws, 2,000 bolts, and 300 nuts", "I need to buy 1,000 screws, 2,000 bolts, and 300 nuts"),
        ("first time here second time there", "first time here second time there"),
        ("number one chair number three desk", "number one chair number three desk"),
        ("I want to buy \"red, green\", milk, and bread", "I want to buy \"red, green\", milk, and bread")
    ])
    func lists(input: String, expected: String) {
        #expect(DictationIntent.lists(input) == expected)
        #expect(DictationIntent.lists(expected) == expected)
    }

    @Test
    func multilineLiterals() {
        for text in ["```\nI want to buy milk, eggs, and bread\nfire emoji\n```",
                     "\"shopping list:\nI want to buy milk, eggs, and bread\""] {
            #expect(DictationIntent.apply(text) == text)
        }
    }

    @Test
    func rulesPath() async {
        #expect(await RuleBasedFormatter().format("amazing bro fire emoji") == "Amazing bro 🔥")
        #expect(await RuleBasedFormatter().format("fire emoji") == "🔥")
        #expect(await RuleBasedFormatter().format("I want to buy MacBook, headphones, fish food, and PC bear.")
                == "I want to buy:\n- MacBook\n- Headphones\n- Fish food\n- PC bear")
    }

    @Test
    func fidelity() {
        #expect(TranscriptOutputCheck.accepts(original: "fire emoji", candidate: "🔥"))
        #expect(TranscriptOutputCheck.accepts(original: "amazing bro fire emoji", candidate: "Amazing bro 🔥"))
        #expect(!TranscriptOutputCheck.accepts(original: "amazing bro 🔥", candidate: "Amazing bro"))
        #expect(!TranscriptOutputCheck.accepts(original: "amazing bro", candidate: "Amazing bro 🔥"))
        #expect(!TranscriptOutputCheck.accepts(original: "great 🔥 🔥", candidate: "Great 🔥"))
        #expect(!TranscriptOutputCheck.accepts(original: "What does fire emoji mean?", candidate: "What does 🔥 mean?"))
        let source = "I want to buy MacBook, headphones, fish food, and PC bear"
        let list = "I want to buy:\n- MacBook\n- headphones\n- fish food\n- PC bear"
        #expect(TranscriptOutputCheck.accepts(original: source, candidate: list))
        #expect(!TranscriptOutputCheck.accepts(original: source, candidate: list.replacingOccurrences(of: "PC bear", with: "PC gear")))
        #expect(!TranscriptOutputCheck.accepts(original: source, candidate: "I want to buy:\n- MacBook\n- headphones\n- PC bear"))
        #expect(!TranscriptOutputCheck.accepts(original: source, candidate: "I want to buy:\n- headphones\n- MacBook\n- fish food\n- PC bear"))
        #expect(TranscriptOutputCheck.accepts(original: "number one buy 2 apples number two buy 3 pears", candidate: "1. Buy 2 apples\n2. Buy 3 pears"))
        #expect(!TranscriptOutputCheck.accepts(original: "number one buy 2 apples number two buy 3 pears", candidate: "1. Buy 4 apples\n2. Buy 3 pears"))
        #expect(TranscriptOutputCheck.accepts(original: "Buy 2 apples and buy 3 pears", candidate: "1. Buy 2 apples\n2. Buy 3 pears"))
    }

    @Test @MainActor
    func savedVocabularyWins() async {
        let raw = "fire emoji"
        let snippet = DictionaryEntry.snippet(hear: raw, write: "My saved text")
        let prepared = TextProcessingService.prepareFormatting(raw, entries: [snippet])
        #expect(prepared == raw)
        let fallback = await RuleBasedFormatter(resolvesIntent: false).format(prepared)
        #expect(DictionaryCorrector(entries: [snippet]).apply(to: fallback).0 == "My saved text.")
        #expect(TextProcessingService.prepareFormatting("Fire Emoji", entries: [.term("Fire Emoji")]) == "Fire Emoji")
        #expect(TextProcessingService.prepareFormatting("amazing bro fire emoji", entries: [.term("MacBook")]) == "amazing bro 🔥")
    }

    @Test @MainActor
    func processingModesAndFallback() async {
        let raw = "amazing bro fire emoji"
        let off = await TextProcessingService.shared.process(raw, mode: .off)
        #expect(off.text == raw)
        let basic = await TextProcessingService.shared.process(raw, mode: .basic, writingEngine: .rules)
        #expect(basic.text == "Amazing bro 🔥")
        #expect(basic.raw == raw)
        let list = "I want to buy MacBook, headphones, fish food, and PC bear"
        let missing = URL(fileURLWithPath: "/private/tmp/missing-intent-model-\(UUID().uuidString).gguf")
        let fallback = await TextProcessingService.shared.process(list, mode: .smart, writingEngine: .qwen,
            forceWritingModel: true, writingModelURL: missing)
        #expect(fallback.engine == "Rules fallback")
        #expect(DictationIntent.listItems(fallback.text).count == 4)
        #expect(fallback.text.contains("PC bear"))
    }
}
