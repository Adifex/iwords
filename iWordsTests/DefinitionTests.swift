import Foundation
import Testing
@testable import iWords

struct DefinitionTests {
    @Test func `Pearse records preserve forms meanings and addons`() throws {
        let output = "01 am.o V 1 1 PRES ACTIVE IND 1 S\n02 amo, amare, amavi, amatus\n03 love; like;\n05 -que = and\n06 spelling variant"
        let results = try DictionaryParser.parse(output, direction: .latinToEnglish)
        #expect(results.count == 3)
        guard case .word(let word) = results.first else {
            Issue.record("Expected a word record")
            return
        }
        #expect(word.forms.count == 1)
        #expect(word.forms.first?.dictionaryForms == ["amo, amare, amavi, amatus"])
        #expect(word.meaning.contains("love"))
        #expect(results[1].raw == "-que = and")
    }

    @Test func `English results remain readable`() throws {
        let output = "amo love\ncaritas affection"
        let results = try DictionaryParser.parse(output, direction: .englishToLatin)
        #expect(results.map(\.raw) == ["amo love", "caritas affection"])
    }

    @Test func `Unexpected output reports a parsing error`() {
        #expect(throws: DWError.self) {
            try DictionaryParser.parse("99 unexpected", direction: .latinToEnglish)
        }
    }
}

@MainActor
struct EngineIntegrationTests {
    private func lookup(_ word: String, direction: Dictionary.Direction,
                        engine: Dictionary) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            engine.getDefinition(word, direction: direction, options: []) { result in
                continuation.resume(with: result.map { $0 ?? "" }.mapError { $0 as Error })
            }
        }
    }

    @Test func `Bundled engine supports both directions and repeated requests`() async throws {
        let engine = Dictionary()
        for _ in 0..<3 {
            let latin = try await lookup("amo", direction: .latinToEnglish, engine: engine)
            #expect(latin.contains("03 love"))
            let parsed = try DictionaryParser.parse(latin, direction: .latinToEnglish)
            #expect(!parsed.isEmpty)
            let english = try await lookup("love", direction: .englishToLatin, engine: engine)
            #expect(english.contains("amo, amare"))
        }
    }

    @Test(arguments: ["a", "e", "sum", "multusque", "xyzzy"])
    func `Single letters irregular forms enclitics and unknowns complete`(word: String) async throws {
        let engine = Dictionary()
        let result = try await lookup(word, direction: .latinToEnglish, engine: engine)
        #expect(!result.isEmpty)
        if word == "xyzzy" {
            #expect(result.contains("UNKNOWN") || result.contains("No Match"))
        } else {
            #expect(result.contains("03 "))
        }
    }

    @Test func `Restarted engine still answers`() async throws {
        let engine = Dictionary()
        _ = try await lookup("amo", direction: .latinToEnglish, engine: engine)
        engine.setNeedsRestart()
        let result = try await lookup("sum", direction: .latinToEnglish, engine: engine)
        #expect(result.contains("03 "))
    }
}
