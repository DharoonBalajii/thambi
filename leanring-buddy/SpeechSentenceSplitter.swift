//
//  SpeechSentenceSplitter.swift
//  leanring-buddy
//
//  LOCAL ADDITION: splits a spoken answer into sentences.
//
//  Why not Foundation's `.bySentences`? Clicky's answers are written entirely in lowercase
//  ("...the title. then the graph."), and Apple's splitter does not treat ". t" as a sentence
//  break, so a whole answer came back as ONE sentence: the voice had to synthesize everything
//  before the first word, and per-sentence pointing could not be matched to speech.
//

import Foundation

enum SpeechSentenceSplitter {
    private static let sentenceEndingCharacters: Set<Character> = [".", "!", "?", "…"]
    private static let closingCharactersThatStayWithSentence: Set<Character> = ["\"", "'", ")", "]", "”", "’"]
    private static let abbreviationsThatDoNotEndASentence: Set<String> = [
        "e.g.", "i.e.", "vs.", "etc.", "dr.", "mr.", "mrs.", "ms.", "fig.", "eq.", "approx.", "no.", "st."
    ]

    /// Splits at ". " / "! " / "? " (and at the end of the text), regardless of capitalisation.
    /// Decimals like "3.5", abbreviations like "e.g." and ellipses ("...") do not split.
    static func sentences(in text: String) -> [String] {
        let characters = Array(text)
        var sentences: [String] = []
        var currentSentence = ""
        var index = 0

        func finishCurrentSentence() {
            let trimmedSentence = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSentence.isEmpty { sentences.append(trimmedSentence) }
            currentSentence = ""
        }

        while index < characters.count {
            let character = characters[index]
            currentSentence.append(character)

            guard sentenceEndingCharacters.contains(character) else {
                index += 1
                continue
            }

            // Keep closing quotes/brackets attached to the sentence they close.
            var nextIndex = index + 1
            while nextIndex < characters.count, closingCharactersThatStayWithSentence.contains(characters[nextIndex]) {
                currentSentence.append(characters[nextIndex])
                nextIndex += 1
            }

            let isEndOfText = nextIndex >= characters.count
            let isFollowedByWhitespace = nextIndex < characters.count && characters[nextIndex].isWhitespace
            if (isEndOfText || isFollowedByWhitespace) && !endsWithAbbreviation(currentSentence) {
                finishCurrentSentence()
                while nextIndex < characters.count, characters[nextIndex].isWhitespace { nextIndex += 1 }
            }
            index = nextIndex
        }
        finishCurrentSentence()
        return sentences
    }

    private static func endsWithAbbreviation(_ sentenceSoFar: String) -> Bool {
        guard let lastWord = sentenceSoFar.split(whereSeparator: { $0.isWhitespace }).last else { return false }
        return abbreviationsThatDoNotEndASentence.contains(lastWord.lowercased())
    }
}
