//
//  NotesMarkdown.swift
//  leanring-buddy
//
//  The notes box: when you ask Thambi to write something down ("summarize this slide", "give me
//  the key points", "make notes"), the answer carries a [NOTES]...[/NOTES] block. This file pulls
//  that block out of the answer and turns its markdown into clean display lines, so the box shows
//  real bullets, headings and bold text and never raw `*`, `**` or `#` characters.
//
//  Pure Foundation, no UI, so it can be unit-tested on its own.
//

import Foundation

enum NotesMarkdown {

    // MARK: - When to show notes

    /// The notes box only opens when the user's own words include "write" (write, writes,
    /// writing, written, wrote), e.g. "write down the key points".
    static func userAskedToWrite(_ transcript: String) -> Bool {
        transcript.range(of: #"\b(write|writes|writing|written|wrote)\b"#,
                         options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Extracting the notes block

    /// Splits an answer into the part to speak and the notes block (nil when there is none).
    /// Tolerates a missing closing tag (everything after [NOTES] is notes).
    static func extractNotes(from responseText: String) -> (spokenText: String, notes: String?) {
        guard let openingTag = responseText.range(of: "[NOTES]", options: .caseInsensitive) else {
            return (responseText, nil)
        }
        let afterOpeningTag = responseText[openingTag.upperBound...]
        let closingTag = afterOpeningTag.range(of: "[/NOTES]", options: .caseInsensitive)
        let notesBody = closingTag.map { String(afterOpeningTag[..<$0.lowerBound]) } ?? String(afterOpeningTag)
        let textAfterNotes = closingTag.map { String(afterOpeningTag[$0.upperBound...]) } ?? ""

        let spokenText = (String(responseText[..<openingTag.lowerBound]) + " " + textAfterNotes)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Pointing tags belong to speech, never to the written notes.
        let trimmedNotes = notesBody
            .replacingOccurrences(of: #"\[POINT:[^\]]*\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (spokenText, trimmedNotes.isEmpty ? nil : trimmedNotes)
    }

    // MARK: - Rendering

    enum LineKind: Equatable {
        case heading
        case bullet(level: Int)
        case numbered(number: String, level: Int)
        case paragraph
        case spacer
    }

    struct Line {
        let kind: LineKind
        /// Inline markdown (bold, italic, code) already applied; no markup characters remain.
        let text: AttributedString
        var plainText: String { String(text.characters) }
    }

    /// Turns notes markdown into display lines.
    static func lines(from markdown: String) -> [Line] {
        var lines: [Line] = []
        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let indentation = rawLine.prefix(while: { $0 == " " || $0 == "\t" })
            let indentLevel = min(3, indentation.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2)
            let content = rawLine.trimmingCharacters(in: .whitespaces)

            if content.isEmpty {
                if let last = lines.last, last.kind != .spacer { lines.append(Line(kind: .spacer, text: AttributedString(""))) }
                continue
            }
            // Horizontal rules (---, ***) carry no content.
            if content.range(of: #"^([-*_]\s*){3,}$"#, options: .regularExpression) != nil { continue }

            if let heading = content.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                lines.append(Line(kind: .heading, text: inline(String(content[heading.upperBound...]))))
            } else if let bullet = content.range(of: #"^[-*+•]\s+"#, options: .regularExpression) {
                lines.append(Line(kind: .bullet(level: indentLevel), text: inline(String(content[bullet.upperBound...]))))
            } else if let numbered = content.range(of: #"^\d{1,3}[.)]\s+"#, options: .regularExpression) {
                let number = String(content[numbered].filter(\.isNumber))
                lines.append(Line(kind: .numbered(number: number, level: indentLevel), text: inline(String(content[numbered.upperBound...]))))
            } else {
                lines.append(Line(kind: .paragraph, text: inline(content)))
            }
        }
        while lines.last?.kind == .spacer { lines.removeLast() }
        while lines.first?.kind == .spacer { lines.removeFirst() }
        return lines
    }

    /// Plain text for the Copy button: real bullets, no markdown characters.
    static func plainText(from markdown: String) -> String {
        lines(from: markdown).map { line in
            switch line.kind {
            case .heading: return line.plainText.uppercased()
            case .bullet(let level): return String(repeating: "  ", count: level) + "• " + line.plainText
            case .numbered(let number, let level): return String(repeating: "  ", count: level) + "\(number). " + line.plainText
            case .paragraph: return line.plainText
            case .spacer: return ""
            }
        }.joined(separator: "\n")
    }

    /// Applies inline markdown (**bold**, *italic*, `code`). Anything that still looks like a
    /// leftover emphasis marker is removed so stray stars never reach the screen.
    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        let leftover = String(attributed.characters)
        if leftover.contains("**") || leftover.contains("__") || leftover.range(of: #"(^|\s)\*(\S)|(\S)\*(\s|$)"#, options: .regularExpression) != nil {
            let cleaned = leftover
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: #"(^|\s)\*(?=\S)"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"(?<=\S)\*(?=\s|$)"#, with: "", options: .regularExpression)
            attributed = AttributedString(cleaned)
        }
        return attributed
    }
}
