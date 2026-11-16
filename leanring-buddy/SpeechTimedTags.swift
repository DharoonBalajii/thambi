//
//  SpeechTimedTags.swift
//  leanring-buddy
//
//  Things that happen at a moment in the spoken answer, besides pointing:
//
//    [STEP]                          the next part of the drawing appears
//    [MARK:box:x1,y1,x2,y2:label]    a box is drawn around a region of the screen
//    [MARK:underline:x1,y1,x2,y2:label]
//    [MARK:circle:x,y,r:label]
//
//  A tag is written right after the sentence it belongs to, and takes effect when the voice
//  starts that sentence, exactly like [POINT]. This file finds the tags and cuts the text at
//  them. Pure Foundation, unit-tested.
//

import Foundation

nonisolated enum SpeechTimedTags {

    enum MarkKind: String, Equatable, Sendable { case box, underline, circle }

    /// A mark as the model wrote it, in screenshot pixels (top-left origin).
    struct MarkTag: Equatable, Sendable {
        var kind: MarkKind
        /// box and underline: x1, y1, x2, y2. circle: centre x, centre y, radius.
        var numbers: [Double]
        var label: String
        /// Which screen (1-based), or nil for the screen the cursor is on.
        var screenNumber: Int?
    }

    enum Event: Equatable, Sendable {
        case revealStep
        case mark(MarkTag)
    }

    static let maximumMarksPerAnswer = 6
    static let maximumStepsPerAnswer = 12

    /// Stand-ins left in the text where a tag was, so the tag's place survives the other parsing
    /// (pointing tags, sentence splitting). Never spoken: `split` and `stripped` remove them.
    private static let open: Character = "\u{27E6}"   // ⟦
    private static let close: Character = "\u{27E7}"  // ⟧

    /// Replaces every [STEP] and [MARK:...] tag with a numbered stand-in and returns what each one means.
    static func extract(from text: String) -> (text: String, events: [Event]) {
        let pattern = #"\[STEP(?::?\s*\d*)?\]|\[MARK:(box|underline|circle):([0-9.,\s-]+?)(?::([^\]:]*?))?(?::screen(\d+))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return (text, []) }
        var events: [Event] = []
        var result = ""
        var position = text.startIndex
        var markCount = 0, stepCount = 0
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[position..<range.lowerBound]
            position = range.upperBound

            var event: Event?
            if let kindRange = Range(match.range(at: 1), in: text), let kind = MarkKind(rawValue: text[kindRange].lowercased()) {
                let numbers = Range(match.range(at: 2), in: text).map { text[$0].components(separatedBy: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) } } ?? []
                let label = Range(match.range(at: 3), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
                let screenNumber = Range(match.range(at: 4), in: text).flatMap { Int(text[$0]) }
                let isWellFormed = (kind == .circle ? numbers.count == 3 : numbers.count == 4)
                    && numbers.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 20000 }
                if isWellFormed, markCount < maximumMarksPerAnswer {
                    markCount += 1
                    event = .mark(MarkTag(kind: kind, numbers: numbers, label: String(label.prefix(40)), screenNumber: screenNumber))
                }
            } else if stepCount < maximumStepsPerAnswer {
                stepCount += 1
                event = .revealStep
            }
            // A tag that is dropped (malformed, or over the limit) simply disappears from the text.
            if let event {
                result += " \(open)\(events.count)\(close) "
                events.append(event)
            }
        }
        result += text[position...]
        return (result, events)
    }

    /// The text with all stand-ins removed.
    static func stripped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s*\(open)\\d+\(close)\\s*", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" ([.,!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cuts text at its stand-ins. Each piece carries the events whose tags followed it, to fire
    /// when the voice starts that piece. Events with no sentence before them ride on the next piece.
    static func split(_ text: String) -> [(text: String, eventIndexes: [Int])] {
        var pieces: [(text: String, eventIndexes: [Int])] = []
        var current = ""
        var carriedForward: [Int] = []
        var characters = text.makeIterator()
        while let character = characters.next() {
            guard character == open else {
                current.append(character)
                continue
            }
            var digits = ""
            while let next = characters.next(), next != close { digits.append(next) }
            guard let index = Int(digits) else { continue }
            let pieceText = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if pieceText.isEmpty {
                // Stacked tags, or a tag before any words.
                if pieces.isEmpty || !carriedForward.isEmpty {
                    carriedForward.append(index)
                } else {
                    pieces[pieces.count - 1].eventIndexes.append(index)
                }
            } else {
                pieces.append((pieceText, carriedForward + [index]))
                carriedForward = []
            }
            current = ""
        }
        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty || !carriedForward.isEmpty {
            pieces.append((trailing, carriedForward))
        }
        return pieces
    }

    /// Removes reasoning the model was meant to keep to itself ("<reasoning>...", "<thinking>...").
    /// An unclosed block runs to the end of the text. Never spoken, never shown.
    static func withoutLeakedReasoning(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"<(reasoning|thinking|scratchpad)>[\s\S]*?(</\1>|$)"#, with: " ", options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the user's own words ask for something on the screen to be marked.
    static func userAskedToMark(_ transcript: String) -> Bool {
        transcript.range(of: #"\b(mark|highlight|circle|underline|outline|annotate|box|put a box)\b"#,
                         options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Sent only when the user asked for marks, so the model uses them instead of the pointer.
    static let markRequestSection = """
    marking request:
    the user asked you to mark things on their screen. for every region you mention, use a [MARK:...] tag (box, underline or circle) right after its sentence, and do not use [POINT] in this answer. boxes must cover the whole region you mean.
    """

    /// Instructions for marking, added to the long instructions.
    static let markPromptSection = """


    marking the screen:
    when a whole region matters rather than one spot (a paragraph, a line of code, a row of a table, one part of a diagram), draw on the screen instead of pointing. put the tag right after the sentence about that region, same coordinates as [POINT]:
    [MARK:box:x1,y1,x2,y2:label] a box around a region, from its top-left corner to its bottom-right corner.
    [MARK:underline:x1,y1,x2,y2:label] a line under a piece of text, from its left end to its right end.
    [MARK:circle:x,y,r:label] a circle around something small, centre and radius.
    the label is one to three words and may be left out. at most five marks in an answer, only around things visible in the screenshot, and never mark and point at the same thing. append :screenN as with [POINT] for another screen.
    """
}
