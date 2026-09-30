//
//  SpeechAcronymSpeller.swift
//  leanring-buddy
//
//  LOCAL ADDITION: makes the voice say abbreviations letter by letter.
//
//  The neural voice reads "ESP" like a word ("esp") and "IKE" like "ike". Written with spaces
//  ("E S P", "I K E") it says the letters, which was confirmed by running the generated audio
//  back through a speech recogniser ("IKE" was heard as "a key"; "I K E" as "i k e").
//
//  Rule: any run of 2+ capital letters is an abbreviation and is spelled out. Clicky's answers are
//  otherwise all lowercase, and the prompt asks the model to write every abbreviation in capitals.
//  Ordinary words that are sometimes shouted or used as logic operators (AND, OR, NOT, OK, ...)
//  are left alone so they are still said as words.
//
//  Only the text sent to the voice changes; what is shown on screen is untouched.
//

import Foundation

enum SpeechAcronymSpeller {
    /// Capitalised tokens that are ordinary words, not abbreviations: said as words.
    private static let capitalisedWordsSaidNormally: Set<String> = [
        "OK", "AND", "OR", "NOT", "NAND", "NOR", "THE", "BUT", "YES", "NO", "SO", "DO", "IF", "TO", "ON",
        "IN", "BE", "BY", "GO", "HE", "ME", "MY", "OF", "UP", "WE", "AN", "ALL", "ANY", "ARE", "CAN", "FOR",
        "HOW", "ITS", "MAY", "NEW", "NOW", "ONE", "OUR", "OUT", "WHO", "WHY", "YOU", "ONLY", "JUST", "VERY",
        "ALWAYS", "NEVER", "MUST", "WILL", "THIS", "THAT", "WITH", "ALSO", "ONCE", "EVEN", "SUCH", "EACH",
        "BOTH", "HERE", "THEN", "WHEN"
    ]

    /// Safety net: technical abbreviations that are never ordinary words. If the model writes one in
    /// lowercase anyway ("tcp", "pop3"), it is still spelled out. (Words that are also real words,
    /// like "mime" or "ram", are only spelled when written in capitals.)
    private static let lowercaseAbbreviationsAlwaysSpelledOut: [String] = [
        "tcp", "udp", "ip", "ipv4", "ipv6", "icmp", "arp", "dns", "dhcp", "vpn", "smtp", "imap", "pop3",
        "mta", "mua", "mda", "rfc", "esp", "ike", "http", "https", "ftp", "sftp", "ssh", "ssl", "tls", "api",
        "sdk", "cli", "gui", "url", "uri", "html", "css", "json", "xml", "sql", "cpu", "gpu", "tpu",
        "usb", "ssd", "hdd", "dma", "pcie", "jwt", "csrf", "xss", "cors", "grpc",
        "aes", "rsa", "sha", "md5", "pki", "ocr", "llm", "ide", "os", "ui", "ux", "ai", "ml", "rtt", "mss",
        "cwnd", "aimd", "bgp", "ospf", "mpls", "vlan", "lte", "cdn", "tcp/ip"
    ].sorted { $0.count > $1.count }

    private static let lowercaseAbbreviationPattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9'/])("# + lowercaseAbbreviationsAlwaysSpelledOut.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + #")(s?)(?![A-Za-z0-9'/])"#
    )

    // Group 1: the capital letters. Group 2: an optional plural "s" ("ACKs").
    // Not preceded by a letter (so "iOS" / "macOS" are left alone); not followed by a lowercase
    // letter (so "THEy" isn't touched), except a version tag like "IPv6".
    private static let abbreviationPattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])([A-Z]{2,})(s?)(?:(?![a-z])|(?=v\d))"#
    )

    /// "the ESP header and IKE" -> "the E S P header and I K E".
    static func spelledOut(_ text: String) -> String {
        spelledOutCapitalisedAbbreviations(in: spelledOutLowercaseTechnicalAbbreviations(in: text))
    }

    /// "the tcp and pop3 parts" -> "the T C P and P O P3 parts". Mixed-case words are untouched.
    private static func spelledOutLowercaseTechnicalAbbreviations(in text: String) -> String {
        let fullRange = NSRange(text.startIndex..., in: text)
        let matches = lowercaseAbbreviationPattern.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else { return text }

        var result = ""
        var copiedUpTo = text.startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: text),
                  let abbreviationRange = Range(match.range(at: 1), in: text) else { continue }
            let abbreviation = String(text[abbreviationRange])
            // "tcp/ip" is two abbreviations joined by a slash: spell each part.
            let spelledParts = abbreviation.split(separator: "/", omittingEmptySubsequences: false).map { part -> String in
                var spelled = ""
                for character in part.uppercased() {
                    if character.isLetter && !spelled.isEmpty && spelled.last?.isLetter == true { spelled += " " }
                    spelled.append(character)
                }
                return spelled
            }
            let pluralSuffix = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            result += text[copiedUpTo..<matchRange.lowerBound]
            result += spelledParts.joined(separator: " ") + pluralSuffix
            copiedUpTo = matchRange.upperBound
        }
        result += text[copiedUpTo...]
        return result
    }

    private static func spelledOutCapitalisedAbbreviations(in text: String) -> String {
        let fullRange = NSRange(text.startIndex..., in: text)
        let matches = abbreviationPattern.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else { return text }

        var spokenText = ""
        var copiedUpTo = text.startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: text),
                  let lettersRange = Range(match.range(at: 1), in: text) else { continue }
            let letters = String(text[lettersRange])
            guard !capitalisedWordsSaidNormally.contains(letters) else { continue }

            let pluralSuffix = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            spokenText += text[copiedUpTo..<matchRange.lowerBound]
            spokenText += letters.map(String.init).joined(separator: " ") + pluralSuffix
            // "IPv6": keep the lowercase "v" as its own spoken piece ("I P v6", not "I Pv6").
            if let characterAfterMatch = text[matchRange.upperBound...].first, characterAfterMatch.isLowercase {
                spokenText += " "
            }
            copiedUpTo = matchRange.upperBound
        }
        spokenText += text[copiedUpTo...]
        return spokenText
    }
}
