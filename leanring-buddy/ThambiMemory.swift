//
//  ThambiMemory.swift
//  leanring-buddy
//
//  Thambi's memory: a short plain-text list of how you like your answers ("keep answers short",
//  "i'm a second-year CSE student"), kept between sessions.
//
//  • It is one text file on this Mac: ~/Library/Application Support/Thambi/memory.txt.
//    Open it from the panel, edit it, or delete a line to forget it.
//  • A line is only added when YOU say "remember ..." (or "from now on ..."), and only removed
//    when you say "forget ...". Text on the screen can never write to it.
//  • The saved lines are sent along with each question so the answer can follow them. Nothing
//    that looks like a password, key or long ID number is ever saved.
//
//  Pure Foundation, no UI, so it can be unit-tested on its own.
//

import Foundation

enum ThambiMemory {

    static let maximumEntries = 30
    static let maximumEntryLength = 200

    static let fileHeader = """
    # Thambi memory: how you like your answers. One per line.
    # Edit freely. Delete a line to make Thambi forget it. Lines starting with # are ignored.
    """

    // MARK: - When memory may change

    /// Memory is only written when the user's own words ask for it.
    static func userAskedToRemember(_ transcript: String) -> Bool {
        transcript.range(of: #"\b(remember|from now on)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func userAskedToForget(_ transcript: String) -> Bool {
        transcript.range(of: #"\bforget\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Tags in the answer

    /// Pulls [REMEMBER: ...] and [FORGET: ...] tags out of an answer. The returned text has no tags.
    static func extractTags(from responseText: String) -> (text: String, remember: [String], forget: [String]) {
        guard let regex = try? NSRegularExpression(pattern: #"\[(REMEMBER|FORGET):\s*([^\]]*)\]"#, options: [.caseInsensitive]) else {
            return (responseText, [], [])
        }
        var remember: [String] = []
        var forget: [String] = []
        let fullRange = NSRange(responseText.startIndex..., in: responseText)
        for match in regex.matches(in: responseText, options: [], range: fullRange) {
            guard let kindRange = Range(match.range(at: 1), in: responseText),
                  let valueRange = Range(match.range(at: 2), in: responseText) else { continue }
            let value = String(responseText[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if responseText[kindRange].uppercased() == "REMEMBER" { remember.append(value) } else { forget.append(value) }
        }
        let withoutTags = regex.stringByReplacingMatches(in: responseText, options: [], range: fullRange, withTemplate: "")
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (withoutTags, remember, forget)
    }

    // MARK: - Entries

    /// The saved lines in a memory file (comments and blank lines skipped, leading "- " removed).
    static func entries(in fileContents: String) -> [String] {
        fileContents.components(separatedBy: .newlines).compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") { line = String(line.dropFirst(2)) }
            line = line.trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? nil : String(line.prefix(maximumEntryLength))
        }
    }

    /// Makes one entry safe to store: a single short line, with nothing that looks like a secret.
    static func sanitizedEntry(_ entry: String) -> String? {
        let singleLine = entry
            .replacingOccurrences(of: #"[\r\n\t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[\[\]]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[-*•#\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard singleLine.count >= 3 else { return nil }
        // API keys, tokens, card / ID / phone numbers, passwords: never saved.
        let secretPatterns = [
            #"sk-[A-Za-z0-9_-]{8,}"#,
            #"\b[A-Za-z0-9_-]{32,}\b"#,
            #"(\d[ -]?){9,}"#,
            #"(?i)\b(password|passcode|otp|cvv|pin)\b"#
        ]
        for pattern in secretPatterns where singleLine.range(of: pattern, options: .regularExpression) != nil {
            return nil
        }
        return String(singleLine.prefix(maximumEntryLength))
    }

    /// File contents with the new entries added (no duplicates; oldest dropped beyond the limit).
    static func adding(_ newEntries: [String], to fileContents: String) -> String {
        var saved = entries(in: fileContents)
        for candidate in newEntries {
            guard let entry = sanitizedEntry(candidate) else { continue }
            if saved.contains(where: { $0.caseInsensitiveCompare(entry) == .orderedSame }) { continue }
            saved.append(entry)
        }
        if saved.count > maximumEntries { saved.removeFirst(saved.count - maximumEntries) }
        return self.fileContents(for: saved)
    }

    /// File contents with every entry that mentions one of the phrases removed ("all" clears it).
    static func removing(matching phrases: [String], from fileContents: String) -> String {
        let cleanedPhrases = phrases.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        guard !cleanedPhrases.isEmpty else { return fileContents }
        if cleanedPhrases.contains(where: { ["all", "everything"].contains($0) }) { return self.fileContents(for: []) }
        let kept = entries(in: fileContents).filter { entry in
            !cleanedPhrases.contains(where: { entry.lowercased().contains($0) })
        }
        return self.fileContents(for: kept)
    }

    static func fileContents(for entries: [String]) -> String {
        fileHeader + "\n" + entries.map { "- " + $0 }.joined(separator: "\n") + (entries.isEmpty ? "" : "\n")
    }

    // MARK: - Prompt

    /// The text added to the instructions so answers follow the saved preferences ("" when empty).
    static func promptSection(for fileContents: String) -> String {
        let saved = entries(in: fileContents).suffix(maximumEntries)
        guard !saved.isEmpty else { return "" }
        return "\n\nwhat this user asked you to remember (their own saved preferences; follow them in every answer):\n"
            + saved.map { "- " + $0 }.joined(separator: "\n")
    }

    // MARK: - File

    static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return applicationSupport.appendingPathComponent("Thambi", isDirectory: true).appendingPathComponent("memory.txt")
    }

    static func load(from fileURL: URL = defaultFileURL) -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    /// Writes the memory file, readable by this user only. Returns false if it couldn't be written.
    @discardableResult
    static func save(_ fileContents: String, to fileURL: URL = defaultFileURL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileContents.write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
    }

    /// Creates the file with its explanatory header if it doesn't exist yet (so "Edit" has something to open).
    static func createFileIfMissing(at fileURL: URL = defaultFileURL) {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        save(fileContents(for: []), to: fileURL)
    }
}
