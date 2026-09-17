//
//  ClickyModelRouter.swift
//  leanring-buddy
//
//  LOCAL ADDITION: decides per question whether to use Haiku (cheap, default) or
//  Sonnet (stronger on multi-step reasoning, roughly 20-40x the cost per question).
//  Pure Swift with no app dependencies so it can be unit-tested on its own.
//
//  Rules for "auto" mode (cheap, instant, no extra API call):
//    1. The user is correcting or retrying ("that's wrong", "try again") -> Sonnet,
//       because Haiku's answer was apparently not good enough.
//    2. The question asks for deep reasoning ("step by step", "derive", "solve",
//       "in detail", "walk me through") -> Sonnet.
//    3. A long, multi-part question (over 40 words) -> Sonnet.
//    4. Everything else, including "explain this slide", "where is X", "what does
//       this mean" -> Haiku.
//

import Foundation

enum ClickyModelRouter {
    static let haikuModelID = "anthropic/claude-haiku-5.5"
    static let sonnetModelID = "anthropic/claude-sonnet-5.5"
    /// Stored in the "selected model" setting when the user wants automatic routing.
    static let autoModeIdentifier = "auto"

    struct Decision {
        let modelID: String
        let reason: String
    }

    private static let correctionOrRetryPhrases = [
        "that's wrong", "that is wrong", "you're wrong", "you are wrong", "not right",
        "incorrect", "are you sure", "try again", "doesn't make sense", "does not make sense",
        "still confused", "i still don't", "i don't understand", "i do not understand",
        "explain again", "that's not what", "that is not what", "not what i asked"
    ]

    private static let deepReasoningPhrases = [
        "step by step", "step-by-step", "in detail", "in depth", "in-depth", "detailed",
        "derive", "derivation", "prove", "proof", "solve", "calculate", "compute",
        "work through", "walk me through", "go deeper", "elaborate", "more detail",
        "thoroughly", "compare and contrast", "pros and cons", "trade-off", "tradeoff",
        "analyze", "analyse", "evaluate", "critique"
    ]

    private static let longQuestionWordCountThreshold = 40

    /// - Parameters:
    ///   - transcript: what the user just said.
    ///   - selectedMode: `autoModeIdentifier`, `haikuModelID` or `sonnetModelID`.
    static func chooseModel(forTranscript transcript: String, selectedMode: String) -> Decision {
        if selectedMode == haikuModelID {
            return Decision(modelID: haikuModelID, reason: "fixed by user: Haiku")
        }
        if selectedMode == sonnetModelID {
            return Decision(modelID: sonnetModelID, reason: "fixed by user: Sonnet")
        }

        let normalizedTranscript = transcript
            .lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")

        if let matchedPhrase = firstWholeWordMatch(in: normalizedTranscript, of: correctionOrRetryPhrases) {
            return Decision(modelID: sonnetModelID, reason: "correction/retry (\"\(matchedPhrase)\")")
        }
        if let matchedPhrase = firstWholeWordMatch(in: normalizedTranscript, of: deepReasoningPhrases) {
            return Decision(modelID: sonnetModelID, reason: "deep reasoning (\"\(matchedPhrase)\")")
        }

        let wordCount = normalizedTranscript.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount > longQuestionWordCountThreshold {
            return Decision(modelID: sonnetModelID, reason: "long multi-part question (\(wordCount) words)")
        }

        return Decision(modelID: haikuModelID, reason: "everyday question")
    }

    /// Whole-word/phrase match so "prove" doesn't fire on "improve" and "solve" not on "resolved".
    private static func firstWholeWordMatch(in text: String, of phrases: [String]) -> String? {
        for phrase in phrases {
            let escapedPhrase = NSRegularExpression.escapedPattern(for: phrase)
            let pattern = "(?<![a-z0-9'])" + escapedPhrase + "(?![a-z0-9'])"
            if text.range(of: pattern, options: .regularExpression) != nil {
                return phrase
            }
        }
        return nil
    }
}
