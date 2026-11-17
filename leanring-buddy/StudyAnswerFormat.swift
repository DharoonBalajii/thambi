//
//  StudyAnswerFormat.swift
//  leanring-buddy
//
//  How long and in what shape a written answer should be. Indian university exams mark answers
//  by length and structure: a 2-mark answer is a crisp definition, a 10-mark answer has an
//  introduction, headed points, a diagram and a conclusion. The student picks the marks in Ask,
//  or just writes "for 5 marks" in the question.
//
//  Also: what an answer cost, worked out from the token counts (prices of Haiku 5.5 on OpenRouter).
//
//  Pure Foundation, no UI, so it can be unit-tested on its own.
//

import Foundation

nonisolated enum StudyAnswerFormat: Int, CaseIterable, Codable, Sendable {
    case normal = 0
    case twoMarks = 2
    case fiveMarks = 5
    case tenMarks = 10
    case sixteenMarks = 16

    var title: String {
        self == .normal ? "Normal answer" : "\(rawValue) marks"
    }

    var shortTitle: String {
        self == .normal ? "Normal" : "\(rawValue) marks"
    }

    /// What the model is told about the shape of the answer.
    var instruction: String? {
        switch self {
        case .normal:
            return nil
        case .twoMarks:
            return "write this as a 2-mark university exam answer: 40 to 70 words. a precise definition or statement first, then one line of key point or example. no headings."
        case .fiveMarks:
            return "write this as a 5-mark university exam answer: about 150 to 250 words. a one-line definition, then 4 to 6 bullet points with the key terms in bold, one short example, and a one-line diagram description if a diagram would earn marks (\"diagram: ...\")."
        case .tenMarks:
            return "write this as a 10-mark university exam answer: about 400 to 600 words. a short introduction, 3 to 5 headed sections (### headings) each with points, a labelled diagram described in words (\"diagram: ...\") where one earns marks, an example or worked case, advantages or limitations if relevant, and a two-line conclusion."
        case .sixteenMarks:
            return "write this as a 16-mark university exam answer (the long part-c question): about 700 to 1000 words. introduction, 5 to 7 headed sections (### headings) with points and sub-points, one or two labelled diagrams described in words (\"diagram: ...\"), a worked example or case study, a comparison or advantages and limitations, and a conclusion."
        }
    }

    /// Output room for each length, so a long answer is not cut off and a short one stays short.
    var maximumOutputTokens: Int {
        switch self {
        case .normal: return 1_200
        case .twoMarks: return 300
        case .fiveMarks: return 700
        case .tenMarks: return 1_500
        case .sixteenMarks: return 2_300
        }
    }

    /// "for 5 marks", "5-mark answer", "10 marks", "16m". Nil when the question names no marks.
    static func detected(in question: String) -> StudyAnswerFormat? {
        let lowered = question.lowercased()
        let pattern = #"\b(\d{1,2})\s*-?\s*(marks?|m)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
              let numberRange = Range(match.range(at: 1), in: lowered),
              let marks = Int(lowered[numberRange]) else { return nil }
        // "16m" could be sixteen metres; only count bare "m" with words like answer or question nearby.
        if let unitRange = Range(match.range(at: 2), in: lowered), lowered[unitRange] == "m",
           !lowered.contains("answer"), !lowered.contains("question") { return nil }
        return closest(toMarks: marks)
    }

    /// Exams also use 3, 4, 6, 8, 12 and 13 marks; each goes to the nearest shape.
    static func closest(toMarks marks: Int) -> StudyAnswerFormat? {
        guard marks >= 1, marks <= 25 else { return nil }
        switch marks {
        case 1...3: return .twoMarks
        case 4...7: return .fiveMarks
        case 8...13: return .tenMarks
        default: return .sixteenMarks
        }
    }
}

nonisolated enum StudyCost {
    /// US dollars per million tokens for Haiku 5.5 on OpenRouter.
    static let inputPerMillion = 0.10
    static let cachedInputPerMillion = 0.01
    static let cacheWritePerMillion = 0.125
    static let outputPerMillion = 0.50
    static let rupeesPerDollar = 94.0

    static func dollars(input: Int, cached: Int, cacheWrite: Int, output: Int) -> Double {
        (Double(input) * inputPerMillion
         + Double(cached) * cachedInputPerMillion
         + Double(cacheWrite) * cacheWritePerMillion
         + Double(output) * outputPerMillion) / 1_000_000
    }

    static func rupees(input: Int, cached: Int, cacheWrite: Int, output: Int) -> Double {
        dollars(input: input, cached: cached, cacheWrite: cacheWrite, output: output) * rupeesPerDollar
    }

    /// "₹0.03", "under ₹0.01", "₹1.20".
    static func label(rupees: Double) -> String {
        if rupees < 0.01 { return "under ₹0.01" }
        return String(format: "₹%.2f", rupees)
    }
}
