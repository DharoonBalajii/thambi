//
//  StudyPlanner.swift
//  leanring-buddy
//
//  Planning to an exam date: what previous-year papers ask again and again, a day-by-day plan
//  that learns each unit and comes back to it on a spaced schedule, and the study streak.
//
//  • Previous-year papers are split into questions and repeated questions are found on this Mac,
//    by the words they share (free). Mapping each question to a unit is an optional AI step.
//  • The plan learns units in order across the first part of the time left, revisits each one
//    1, 3 and 7 days later, and keeps the last days for full revision and papers.
//
//  Pure Foundation, no UI, so it can be unit-tested on its own.
//

import Foundation

// MARK: - Days

nonisolated enum StudyDay {
    /// "2026-11-17" in the Mac's own time zone: one key per calendar day.
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }
}

// MARK: - Streak

nonisolated enum StudyStreak {
    /// Days in a row with some study, counting back from today (or from yesterday, so a streak
    /// isn't lost before today's study is done), and the longest run ever.
    static func compute(activeDays: Set<String>, today: Date, calendar: Calendar = .current) -> (current: Int, longest: Int) {
        func key(_ offset: Int) -> String {
            StudyDay.key(for: calendar.date(byAdding: .day, value: -offset, to: today)!, calendar: calendar)
        }
        var current = 0
        var offset = activeDays.contains(key(0)) ? 0 : 1
        while activeDays.contains(key(offset)) { current += 1; offset += 1 }

        let sorted = activeDays.compactMap { StudyDay.date(fromKey: $0, calendar: calendar) }.sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in sorted {
            if let previous, StudyDay.daysBetween(previous, day, calendar: calendar) == 1 { run += 1 } else { run = 1 }
            longest = max(longest, run)
            previous = day
        }
        return (current, max(longest, current))
    }
}

// MARK: - Focus timer

nonisolated enum StudyTimerRules {
    static let focusChoices = [15, 25, 45, 60]
    static let defaultFocusMinutes = 25
    static let breakMinutes = 5

    /// "24:59", "1:00:00".
    static func clockLabel(seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "45 min", "1 h 20 min".
    static func durationLabel(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

// MARK: - Previous-year papers

nonisolated struct PaperQuestion: Equatable, Sendable {
    var text: String
    var marks: Int?
    var year: String?
    var paperTitle: String
}

nonisolated struct RepeatedQuestion: Equatable, Sendable {
    /// The clearest wording (the longest).
    var text: String
    var askedCount: Int
    var years: [String]
    var marks: Int?
    var unit: String?
    var topic: String?

    /// How much it is worth preparing: how often it comes times what it carries.
    var weight: Int { askedCount * max(2, marks ?? 2) }
}

nonisolated enum StudyPapers {

    /// "2023", "Nov/Dec 2022" and similar in a file name or the first lines of a paper.
    static func year(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(19[89]\d|20[0-4]\d)\b"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Splits a paper's text into questions. A question starts at a number like "1.", "Q2",
    /// "11)", "12 (a)" or a sub-part "(b)"; marks like "(16)", "[5 marks]" or "(2 M)" are read off.
    static func questions(inPaperText text: String, paperTitle: String) -> [PaperQuestion] {
        let year = year(in: paperTitle) ?? year(in: String(text.prefix(400)))
        let startPattern = #"^\s*(?:q\.?\s*)?(?:\d{1,2}\s*[\.\)]|\d{1,2}\s*\(?[a-h]\)|\(?[a-h]\)|\(?(?:i|ii|iii|iv|v|vi)\))\s+"#
        guard let startRegex = try? NSRegularExpression(pattern: startPattern, options: [.caseInsensitive]) else { return [] }
        var pieces: [String] = []
        var current = ""
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..., in: line)
            if let match = startRegex.firstMatch(in: line, range: range), let matchRange = Range(match.range, in: line) {
                if !current.isEmpty { pieces.append(current) }
                current = String(line[matchRange.upperBound...])
            } else if !current.isEmpty {
                current += " " + line
            }
        }
        if !current.isEmpty { pieces.append(current) }

        return pieces.compactMap { piece in
            let (cleaned, marks) = removingMarks(from: piece)
            let words = cleaned.split(separator: " ")
            guard words.count >= 2, cleaned.count >= 12, cleaned.count <= 900 else { return nil }
            // "Or", "Part B", instructions to candidates are not questions.
            let lower = cleaned.lowercased()
            if lower.hasPrefix("answer all") || lower.hasPrefix("answer any") || lower.contains("time:") && lower.contains("marks") && words.count < 12 { return nil }
            return PaperQuestion(text: cleaned, marks: marks, year: year, paperTitle: paperTitle)
        }
    }

    static func removingMarks(from text: String) -> (String, Int?) {
        let pattern = #"[\(\[]\s*(\d{1,2})\s*(?:marks?|m)?\s*[\)\]]\s*$|\b(\d{1,2})\s*marks?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return (text, nil) }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range) else { return (trimmed, nil) }
        var marks: Int?
        for group in 1...2 {
            if let r = Range(match.range(at: group), in: trimmed) { marks = Int(trimmed[r]) }
        }
        let withoutMarks = (trimmed as NSString).replacingCharacters(in: match.range, with: "").trimmingCharacters(in: .whitespaces)
        return (withoutMarks.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression), marks)
    }

    /// The words that carry a question's meaning (no "explain", "with neat diagram").
    static func meaningWords(_ text: String) -> Set<String> {
        let taskWords: Set<String> = ["explain", "describe", "discuss", "define", "write", "short", "note", "notes", "brief", "briefly",
                                      "detail", "neat", "diagram", "sketch", "suitable", "example", "examples", "differentiate",
                                      "distinguish", "compare", "list", "state", "give", "derive", "illustrate", "elaborate", "mention", "draw", "with", "help"]
        return Set(StudyLibrary.searchWords(in: text).filter { !taskWords.contains($0) && $0.count > 1 })
    }

    /// Questions asked more than once across papers (or within one), grouped by shared words.
    /// Two questions are the same when most of their meaning words match (Jaccard 0.5 or more).
    static func repeatedQuestions(_ questions: [PaperQuestion], threshold: Double = 0.5) -> [RepeatedQuestion] {
        var groups: [(words: Set<String>, members: [PaperQuestion])] = []
        for question in questions {
            let words = meaningWords(question.text)
            guard words.count >= 2 else { continue }
            if let index = groups.firstIndex(where: { group in
                let shared = Double(group.words.intersection(words).count)
                return shared / Double(group.words.union(words).count) >= threshold
            }) {
                groups[index].members.append(question)
                groups[index].words.formUnion(words)
            } else {
                groups.append((words, [question]))
            }
        }
        return groups.map { group in
            let years = Array(Set(group.members.compactMap(\.year))).sorted()
            let marks = group.members.compactMap(\.marks).max()
            let clearest = group.members.max { $0.text.count < $1.text.count }!.text
            return RepeatedQuestion(text: clearest, askedCount: group.members.count, years: years, marks: marks)
        }
        .sorted { ($0.weight, $0.askedCount, $1.text) > ($1.weight, $1.askedCount, $0.text) }
    }

    // MARK: Units, with the AI

    static let unitMappingSystemPrompt = """
    you sort a college student's previous-year exam questions into the units of their syllabus.

    reply with one line per question, in the same order, nothing else:
    number | unit name exactly as listed (or "other") | a topic of two to five words
    """

    static func unitMappingPrompt(questions: [RepeatedQuestion], units: [String]) -> String {
        var prompt = "units:\n" + units.enumerated().map { "- \($0.element)" }.joined(separator: "\n") + "\n\nquestions:\n"
        for (offset, question) in questions.enumerated() {
            prompt += "\(offset + 1). \(question.text.prefix(300))\n"
        }
        return prompt
    }

    /// Reads "3 | Unit 2 Transactions | deadlock handling" lines back onto the questions.
    static func applyUnitMapping(_ reply: String, to questions: [RepeatedQuestion], units: [String]) -> [RepeatedQuestion] {
        var result = questions
        for line in reply.components(separatedBy: .newlines) {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, let number = Int(parts[0].filter(\.isNumber)), number >= 1, number <= result.count else { continue }
            let unit = units.first { $0.caseInsensitiveCompare(parts[1]) == .orderedSame }
                ?? units.first { parts[1].localizedCaseInsensitiveContains($0) || $0.localizedCaseInsensitiveContains(parts[1]) }
            result[number - 1].unit = unit
            if parts.count >= 3, !parts[2].isEmpty { result[number - 1].topic = parts[2] }
        }
        return result
    }

    /// Marks each unit carries across the papers, highest first. Units no question touched are 0.
    static func unitWeights(_ questions: [RepeatedQuestion], units: [String]) -> [(unit: String, marks: Int)] {
        units.map { unit in
            (unit, questions.filter { $0.unit == unit }.reduce(0) { $0 + $1.askedCount * ($1.marks ?? 2) })
        }
        .sorted { $0.marks > $1.marks }
    }
}

// MARK: - Plan

nonisolated struct StudyPlanTask: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case learn, revise, papers, fullRevision }
    var kind: Kind
    var unit: String?

    var title: String {
        switch kind {
        case .learn: return "Learn \(unit ?? "")"
        case .revise: return "Revise \(unit ?? "")"
        case .papers: return "Previous-year questions"
        case .fullRevision: return "Revise everything"
        }
    }

    /// A stable id per day, so ticks survive a rebuilt plan with the same tasks.
    func id(on dayKey: String) -> String { "\(dayKey)|\(kind.rawValue)|\(unit ?? "")" }
}

nonisolated struct StudyPlanDay: Equatable, Sendable {
    var date: Date
    var dayKey: String
    var tasks: [StudyPlanTask]
}

nonisolated enum StudyPlanBuilder {
    static let revisionGaps = [1, 3, 7]

    /// A plan from today to the day before the exam.
    /// • Units are learned in syllabus order; a heavier unit (more marks in past papers) gets more
    ///   days. Learning takes about 60% of the days, at most one unit a day unless time is short.
    /// • Each unit is revised 1, 3 and 7 days after it is learned, when there is room before the end.
    /// • The last 15% of days (at least one) are full revision with past papers.
    static func plan(units: [(name: String, weight: Int)], today: Date, examDate: Date, calendar: Calendar = .current) -> [StudyPlanDay] {
        let dayCount = StudyDay.daysBetween(today, examDate, calendar: calendar)
        guard dayCount >= 1, !units.isEmpty else { return [] }
        let days = (0..<dayCount).map { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: today))! }
        var tasksByDay = Array(repeating: [StudyPlanTask](), count: dayCount)

        let finalDays = dayCount >= 4 ? max(1, Int((Double(dayCount) * 0.15).rounded())) : (dayCount >= 2 ? 1 : 0)
        let learningDays = max(1, min(dayCount - finalDays, Int((Double(dayCount) * 0.6).rounded(.up))))

        // Days per unit by weight: every unit at least one share, heavier units up to two more.
        let maxWeight = max(1, units.map(\.weight).max() ?? 1)
        let shares = units.map { 1.0 + 2.0 * Double($0.weight) / Double(maxWeight) * (units.contains { $0.weight > 0 } ? 1 : 0) }
        let totalShares = shares.reduce(0, +)
        var cursor = 0.0
        var learnedOn: [(unit: String, day: Int)] = []
        for (index, unit) in units.enumerated() {
            let startDay = Int(cursor / totalShares * Double(learningDays))
            cursor += shares[index]
            let endDay = max(startDay + 1, Int((cursor / totalShares * Double(learningDays)).rounded()))
            for day in startDay..<min(endDay, learningDays) {
                if !tasksByDay[day].contains(StudyPlanTask(kind: .learn, unit: unit.name)) {
                    tasksByDay[day].append(StudyPlanTask(kind: .learn, unit: unit.name))
                }
            }
            learnedOn.append((unit.name, min(endDay, learningDays) - 1))
        }

        let lastRevisionDay = dayCount - finalDays - 1
        for learned in learnedOn {
            for gap in revisionGaps {
                let day = learned.day + gap
                if day <= lastRevisionDay { tasksByDay[day].append(StudyPlanTask(kind: .revise, unit: learned.unit)) }
            }
        }
        for day in (dayCount - finalDays)..<dayCount where day >= 0 {
            tasksByDay[day] = [StudyPlanTask(kind: .fullRevision), StudyPlanTask(kind: .papers)]
        }
        // With one day left there is no final stretch; revise what there is.
        if finalDays == 0, dayCount == 1 { tasksByDay[0].append(StudyPlanTask(kind: .papers)) }

        return days.enumerated().map { offset, date in
            StudyPlanDay(date: date, dayKey: StudyDay.key(for: date, calendar: calendar), tasks: tasksByDay[offset])
        }
    }
}
