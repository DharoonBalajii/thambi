//
//  NotesMarkdown.swift
//  leanring-buddy
//
//  The notes box: when you ask Thambi to write something down ("write down the key points"),
//  the answer carries a [NOTES]...[/NOTES] block. This file pulls that block out of the answer
//  and turns its markdown into clean display lines, so the box shows real bullets, headings,
//  bold text and tables, and never raw `*`, `**`, `#` or `|` characters. It also tidies the
//  writing itself: no em dashes, no "Certainly! Here's..." openers, plain quotes.
//
//  Pure Foundation, no UI, so it can be unit-tested on its own.
//

import Foundation

enum NotesMarkdown {

    // MARK: - When to show notes

    /// The notes box only opens when the user's own words include "write" (write, writes,
    /// writing, written, wrote), e.g. "write down the key points".
    /// Technical terms that contain the word ("write-ahead log", "read/write", "write lock") are
    /// not requests.
    static func userAskedToWrite(_ transcript: String) -> Bool {
        let withoutTerms = transcript.replacingOccurrences(
            of: #"(?i)\bread\s*(/|-|and|&)\s*writ\w*"#, with: " ", options: .regularExpression)
        let writeRequest = #"\b(write|writes|writing|written|wrote)\b(?![-/]|\s+(ahead|back|through|lock|locks|operation|operations|access|permission|permissions|protect|protected|once|barrier|buffer|cycle|amplification|skew|latency|speed|policy|miss|hit|head|endurance)\b)"#
        let notesRequest = #"\b(make|take|prepare|create|give me|jot down)\s+(some |short |brief |quick |detailed |exam |revision |my )?notes\b"#
        return withoutTerms.range(of: writeRequest, options: [.regularExpression, .caseInsensitive]) != nil
            || withoutTerms.range(of: notesRequest, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Reply drafting: the box also opens when the user's own words ask for a draft or a reply,
    /// e.g. "draft a reply to this email" or "help me respond to this message".
    static func userAskedToDraft(_ transcript: String) -> Bool {
        transcript.range(of: #"\b(draft|drafts|drafting|reply|replies|replying|respond|responding)\b"#,
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
        let cleanedNotes = cleanedForWriting(trimmedNotes)
        return (spokenText, cleanedNotes.isEmpty ? nil : cleanedNotes)
    }

    // MARK: - Tidy writing

    /// Removes the marks of machine writing from notes: em and en dashes, curly quotes, the
    /// ellipsis character, and filler lines such as "Certainly! Here's a summary:" or
    /// "I hope this helps!". The content itself is left alone.
    static func cleanedForWriting(_ notes: String) -> String {
        var lines = withoutDashes(notes)
            .replacingOccurrences(of: "\u{2018}", with: "'").replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2026}", with: "...")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        func isFiller(_ line: String, patterns: [String]) -> Bool {
            let content = line.trimmingCharacters(in: .whitespaces)
            guard content.count < 120 else { return false }
            return patterns.contains { content.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
        }
        let openerPatterns = [
            #"^(sure|certainly|of course|absolutely|great question|no problem|okay|ok)\b[^|]*$"#,
            #"^here('s| is| are)\b[^|]*:$"#
        ]
        let closerPatterns = [
            #"^(i )?hope (this|that|it) helps\b.*$"#,
            #"^(let me know if|feel free to|if you (need|want|have)|happy (studying|learning))\b.*$"#
        ]
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        if let first = lines.first, isFiller(first, patterns: openerPatterns) { lines.removeFirst() }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        if let last = lines.last, isFiller(last, patterns: closerPatterns) { lines.removeLast() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces em and en dashes with ordinary punctuation. Used for notes and for captions.
    static func withoutDashes(_ text: String) -> String {
        text
            // 10–20 -> 10-20
            .replacingOccurrences(of: #"(?<=\d)\s?[\u2013\u2014]\s?(?=\d)"#, with: "-", options: .regularExpression)
            // **Term** — meaning -> **Term**: meaning
            .replacingOccurrences(of: #"(\*\*[^*\n]+\*\*)[ \t]*[\u2013\u2014][ \t]*"#, with: "$1: ", options: .regularExpression)
            // words — more words -> words, more words
            .replacingOccurrences(of: #"[ \t]*(\u2014|\u2013|(?<=\s)--(?=\s))[ \t]*"#, with: ", ", options: .regularExpression)
            // tidy anything the replacements left behind: ", ." or a comma at the start or end of a line
            .replacingOccurrences(of: #",\s*([.,;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^([ \t]*(?:[-*+•]|\d{1,3}[.)])?[ \t]*), "#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?m),[ \t]*$"#, with: "", options: .regularExpression)
    }

    // MARK: - Rendering

    enum LineKind: Equatable {
        case heading
        case bullet(level: Int)
        case numbered(number: String, level: Int)
        case paragraph
        /// A table; its cells are in `Line.tableRows` (the first row is the header when `hasHeader`).
        case table(hasHeader: Bool)
        case spacer
    }

    struct Line {
        let kind: LineKind
        /// Inline markdown (bold, italic, code) already applied; no markup characters remain.
        let text: AttributedString
        /// Only for `.table`: every row has the same number of cells.
        var tableRows: [[AttributedString]] = []
        var plainText: String { String(text.characters) }
    }

    static let maximumTableColumns = 6

    /// Turns notes markdown into display lines.
    static func lines(from markdown: String) -> [Line] {
        var lines: [Line] = []
        let rawLines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var lineIndex = 0
        while lineIndex < rawLines.count {
            // A run of "| a | b |" lines is one table.
            var tableSourceLines: [String] = []
            while lineIndex < rawLines.count, isTableRow(rawLines[lineIndex]) {
                tableSourceLines.append(rawLines[lineIndex])
                lineIndex += 1
            }
            if !tableSourceLines.isEmpty {
                if let table = tableLine(from: tableSourceLines) { lines.append(table) }
                continue
            }

            let rawLine = rawLines[lineIndex]
            lineIndex += 1
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

    // MARK: - Tables

    private static func isTableRow(_ rawLine: String) -> Bool {
        let content = rawLine.trimmingCharacters(in: .whitespaces)
        return content.hasPrefix("|") && content.count > 1
    }

    /// "| a | b |" -> ["a", "b"]
    private static func tableCells(in rawLine: String) -> [String] {
        var content = rawLine.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        return content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The "|---|:---:|" line under a table's header.
    private static func isTableSeparator(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { $0.range(of: #"^:?-{1,}:?$"#, options: .regularExpression) != nil }
    }

    private static func tableLine(from sourceLines: [String]) -> Line? {
        var rows: [[String]] = []
        var hasHeader = false
        for (sourceIndex, sourceLine) in sourceLines.enumerated() {
            let cells = tableCells(in: sourceLine)
            if isTableSeparator(cells) {
                if sourceIndex == 1 { hasHeader = true }
                continue
            }
            rows.append(Array(cells.prefix(maximumTableColumns)))
        }
        rows.removeAll { row in row.allSatisfy(\.isEmpty) }
        guard let columnCount = rows.map(\.count).max(), columnCount > 0 else { return nil }
        let paddedRows = rows.map { row in
            (row + Array(repeating: "", count: columnCount - row.count)).map { inline($0) }
        }
        return Line(kind: .table(hasHeader: hasHeader && paddedRows.count > 1), text: AttributedString(""), tableRows: paddedRows)
    }

    /// Plain text for the Copy button: real bullets, no markdown characters. Table rows are
    /// tab-separated, so they paste into Word, Docs, Excel or Notes as a table.
    static func plainText(from markdown: String) -> String {
        lines(from: markdown).map { line in
            switch line.kind {
            case .heading: return line.plainText.uppercased()
            case .bullet(let level): return String(repeating: "  ", count: level) + "• " + line.plainText
            case .numbered(let number, let level): return String(repeating: "  ", count: level) + "\(number). " + line.plainText
            case .paragraph: return line.plainText
            case .table:
                return line.tableRows.map { row in row.map { String($0.characters) }.joined(separator: "\t") }.joined(separator: "\n")
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
