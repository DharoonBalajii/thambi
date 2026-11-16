//
//  ThambiDictionary.swift
//  leanring-buddy
//
//  Thambi's learned dictionary: course terms, names and spellings the speech recogniser should
//  get right ("Kerberos", "IPsec", "Dr. Venkataraman").
//
//  • It is one text file on this Mac: ~/Library/Application Support/Thambi/dictionary.txt.
//    One entry per line. Open it from the panel and edit it freely.
//      Kerberos                  a term: the recogniser is told to expect it, and its casing is fixed
//      care boss -> Kerberos     a correction: whenever "care boss" is heard, "Kerberos" is written
//  • Terms are learned in two ways: you say "add Kerberos to my dictionary", or Thambi notices
//    that a term on your screen was misheard in your question. Corrections ("a -> b") are only
//    ever added when your own words ask for one, so nothing on the screen can rewrite what you
//    dictate.
//  • The dictionary never leaves the Mac except as hint words sent to the speech recogniser
//    you already use.
//
//  Also holds the small text clean-up used when typing by voice ("new line", "new paragraph").
//
//  Pure Foundation, no UI, so it can be unit-tested on its own.
//

import Foundation

enum ThambiDictionary {

    static let maximumEntries = 300
    static let maximumTermLength = 40
    static let maximumWordsPerTerm = 5

    static let fileHeader = """
    # Thambi dictionary: words and names to get right when you speak. One per line.
    #   Kerberos                 expect this word and fix its capital letters
    #   care boss -> Kerberos    when "care boss" is heard, write "Kerberos"
    # Edit freely. Lines starting with # are ignored.
    """

    struct Correction: Equatable {
        let heard: String
        let written: String
    }

    struct Entries: Equatable {
        var terms: [String] = []
        var corrections: [Correction] = []
        var count: Int { terms.count + corrections.count }
    }

    // MARK: - Reading

    static func entries(in fileContents: String) -> Entries {
        var entries = Entries()
        for rawLine in fileContents.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") { line = String(line.dropFirst(2)) }
            if let arrowRange = line.range(of: "->") {
                guard let heard = sanitizedTerm(String(line[..<arrowRange.lowerBound])),
                      let written = sanitizedTerm(String(line[arrowRange.upperBound...])) else { continue }
                entries.corrections.append(Correction(heard: heard, written: written))
            } else if let term = sanitizedTerm(line) {
                entries.terms.append(term)
            }
            if entries.count >= maximumEntries { break }
        }
        return entries
    }

    /// The words handed to the speech recogniser as "expect these".
    static func keyterms(in fileContents: String) -> [String] {
        let parsed = entries(in: fileContents)
        var seen = Set<String>()
        return (parsed.terms + parsed.corrections.map(\.written)).filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: - Fixing a transcript

    /// Applies the corrections, then fixes the capital letters of every known term.
    static func applying(_ fileContents: String, to transcript: String) -> String {
        let parsed = entries(in: fileContents)
        var text = transcript
        // Longest first, so "open SSL" is handled before "SSL".
        for correction in parsed.corrections.sorted(by: { $0.heard.count > $1.heard.count }) {
            text = replacingWholeWords(correction.heard, with: correction.written, in: text)
        }
        for term in (parsed.terms + parsed.corrections.map(\.written)).sorted(by: { $0.count > $1.count }) {
            text = replacingWholeWords(term, with: term, in: text)
        }
        return text
    }

    private static func replacingWholeWords(_ phrase: String, with replacement: String, in text: String) -> String {
        let escapedPhrase = NSRegularExpression.escapedPattern(for: phrase).replacingOccurrences(of: "\\ ", with: "\\s+").replacingOccurrences(of: " ", with: "\\s+")
        let pattern = "(?<![\\p{L}\\p{N}])" + escapedPhrase + "(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(
            in: text, options: [], range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    // MARK: - Learning

    /// One dictionary word or name: short, plain, and nothing that looks like a secret.
    static func sanitizedTerm(_ rawTerm: String) -> String? {
        let term = rawTerm
            .replacingOccurrences(of: #"[\r\n\t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^[\s"'“”‘’]+|[\s"'“”‘’.,;:!?]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        guard term.count >= 2, term.count <= maximumTermLength else { return nil }
        guard term.split(separator: " ").count <= maximumWordsPerTerm else { return nil }
        // Letters (any language), digits and the few signs real terms use: C++, C#, Wi-Fi, Next.js, O'Brien.
        guard term.range(of: #"^[\p{L}\p{M}\p{N} .+#'/&-]+$"#, options: .regularExpression) != nil else { return nil }
        guard term.range(of: #"\p{L}"#, options: .regularExpression) != nil else { return nil }
        // Never anything that looks like a key, a long number or a password.
        let secretPatterns = [#"sk-[A-Za-z0-9_-]{6,}"#, #"[A-Za-z0-9_-]{24,}"#, #"(\d[ -]?){7,}"#, #"(?i)\b(password|passcode|otp|cvv)\b"#]
        for pattern in secretPatterns where term.range(of: pattern, options: .regularExpression) != nil { return nil }
        return term
    }

    /// True when the user's own words ask for a spelling to be taught ("add ... to my dictionary").
    static func userAskedToTeach(_ transcript: String) -> Bool {
        transcript.range(of: #"\b(dictionary|spell(ed|t|ing)?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Pulls [LEARN: ...] tags out of an answer. The returned text has no tags.
    static func extractTags(from responseText: String) -> (text: String, learn: [String]) {
        guard let regex = try? NSRegularExpression(pattern: #"\[LEARN:\s*([^\]]*)\]"#, options: [.caseInsensitive]) else {
            return (responseText, [])
        }
        let fullRange = NSRange(responseText.startIndex..., in: responseText)
        let learned: [String] = regex.matches(in: responseText, options: [], range: fullRange).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: responseText) else { return nil }
            let value = String(responseText[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        let withoutTags = regex.stringByReplacingMatches(in: responseText, options: [], range: fullRange, withTemplate: "")
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (withoutTags, learned)
    }

    /// File contents with the learned entries added. A "heard -> written" correction is only
    /// accepted when `allowCorrections` is true (the user asked for it out loud).
    static func adding(_ learnedEntries: [String], to fileContents: String, allowCorrections: Bool) -> String {
        var parsed = entries(in: fileContents)
        for learnedEntry in learnedEntries {
            if let arrowRange = learnedEntry.range(of: "->") {
                guard allowCorrections,
                      let heard = sanitizedTerm(String(learnedEntry[..<arrowRange.lowerBound])),
                      let written = sanitizedTerm(String(learnedEntry[arrowRange.upperBound...])),
                      heard.caseInsensitiveCompare(written) != .orderedSame else { continue }
                parsed.corrections.removeAll { $0.heard.caseInsensitiveCompare(heard) == .orderedSame }
                parsed.corrections.append(Correction(heard: heard, written: written))
            } else if let term = sanitizedTerm(learnedEntry) {
                // A newer spelling of the same word replaces the older one.
                parsed.terms.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
                parsed.terms.append(term)
            }
        }
        let overflow = parsed.count - maximumEntries
        if overflow > 0 { parsed.terms.removeFirst(min(overflow, parsed.terms.count)) }
        return self.fileContents(for: parsed)
    }

    static func fileContents(for entries: Entries) -> String {
        let lines = entries.terms + entries.corrections.map { $0.heard + " -> " + $0.written }
        return fileHeader + "\n" + lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    // MARK: - File

    static var defaultFileURL: URL {
        ThambiMemory.defaultFileURL.deletingLastPathComponent().appendingPathComponent("dictionary.txt")
    }

    static func load(from fileURL: URL = defaultFileURL) -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    @discardableResult
    static func save(_ fileContents: String, to fileURL: URL = defaultFileURL) -> Bool {
        ThambiMemory.save(fileContents, to: fileURL)
    }

    static func createFileIfMissing(at fileURL: URL = defaultFileURL) {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        save(fileContents(for: Entries()), to: fileURL)
    }
}

/// Turns a spoken transcript into the text that is typed into the app in front.
enum DictationText {

    /// A paragraph of dictation is capped so a stuck recording can't flood a document.
    static let maximumLength = 4000

    /// Applies the dictionary and the spoken layout commands ("new line", "new paragraph").
    /// Returns nil when there is nothing to type.
    static func prepared(_ transcript: String, dictionaryFileContents: String) -> String? {
        var text = ThambiDictionary.applying(dictionaryFileContents, to: transcript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let layoutCommands: [(pattern: String, replacement: String)] = [
            (#"[\s,.]*\bnew paragraph\b[\s,.]*"#, "\n\n"),
            (#"[\s,.]*\b(new line|next line)\b[\s,.]*"#, "\n")
        ]
        for command in layoutCommands {
            text = text.replacingOccurrences(of: command.pattern, with: command.replacement, options: [.regularExpression, .caseInsensitive])
        }
        // Capital letter at the start and after every line break.
        text = capitalizingLineStarts(text)
        text = String(text.prefix(maximumLength))
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // A trailing space lets the next sentence follow on, unless the text ends a line.
        return text.hasSuffix("\n") ? text : text + " "
    }

    private static func capitalizingLineStarts(_ text: String) -> String {
        var result = ""
        var isAtLineStart = true
        for character in text {
            if isAtLineStart, character.isLetter {
                result += String(character).uppercased()
                isAtLineStart = false
            } else {
                result.append(character)
                if character == "\n" { isAtLineStart = true } else if !character.isWhitespace { isAtLineStart = false }
            }
        }
        return result
    }
}
