//
//  StudyProgressStore.swift
//  leanring-buddy
//
//  Study days, reviews and focus minutes, kept in UserDefaults on this Mac only.
//  The streak counts days in a row with any study.
//

import AppKit
import Combine
import Foundation

@MainActor
final class StudyProgressStore: ObservableObject {
    static let shared = StudyProgressStore()

    private static let activeDaysKey = "studyActiveDays"
    private static let reviewsKey = "studyReviewsByDay"
    private static let minutesKey = "studyMinutesByDay"

    @Published private(set) var activeDays: Set<String> = Set(UserDefaults.standard.stringArray(forKey: activeDaysKey) ?? [])
    @Published private(set) var reviewsByDay: [String: Int] = (UserDefaults.standard.dictionary(forKey: reviewsKey) as? [String: Int]) ?? [:]
    @Published private(set) var minutesByDay: [String: Int] = (UserDefaults.standard.dictionary(forKey: minutesKey) as? [String: Int]) ?? [:]

    var streak: (current: Int, longest: Int) { StudyStreak.compute(activeDays: activeDays, today: Date()) }
    var reviewsToday: Int { reviewsByDay[StudyDay.key(for: Date())] ?? 0 }
    var minutesToday: Int { minutesByDay[StudyDay.key(for: Date())] ?? 0 }

    func recordReview() {
        let today = StudyDay.key(for: Date())
        reviewsByDay[today, default: 0] += 1
        markActive(today)
        UserDefaults.standard.set(reviewsByDay, forKey: Self.reviewsKey)
    }

    func recordFocus(minutes: Int) {
        guard minutes > 0 else { return }
        let today = StudyDay.key(for: Date())
        minutesByDay[today, default: 0] += minutes
        markActive(today)
        UserDefaults.standard.set(minutesByDay, forKey: Self.minutesKey)
    }

    private func markActive(_ day: String) {
        guard !activeDays.contains(day) else { return }
        activeDays.insert(day)
        UserDefaults.standard.set(Array(activeDays).sorted(), forKey: Self.activeDaysKey)
    }
}

/// One focus session at a time: a countdown that, when it ends, adds its minutes to today.
@MainActor
final class StudyFocusTimer: ObservableObject {
    static let shared = StudyFocusTimer()
    static let changedNotification = Notification.Name("ThambiFocusTimerChanged")

    @Published private(set) var endsAt: Date?
    @Published private(set) var startedAt: Date?
    @Published private(set) var subject: String?
    @Published private(set) var minutes = StudyTimerRules.defaultFocusMinutes
    /// Ticks once a second while running so views redraw.
    @Published private(set) var now = Date()
    /// Set when a session has just finished, for the "well done" line.
    @Published var lastFinishedMinutes: Int?

    private var ticker: Timer?

    var isRunning: Bool { endsAt != nil }
    var remainingSeconds: Int { endsAt.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) } ?? 0 }
    var progress: Double {
        guard let startedAt, let endsAt else { return 0 }
        return min(1, max(0, now.timeIntervalSince(startedAt) / endsAt.timeIntervalSince(startedAt)))
    }

    func start(minutes: Int, subject: String?) {
        let start = Date()
        self.minutes = minutes
        self.subject = subject
        startedAt = start
        endsAt = start.addingTimeInterval(Double(minutes) * 60)
        now = start
        lastFinishedMinutes = nil
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    /// Stopping early still counts the whole minutes studied.
    func stop() {
        guard let startedAt else { return }
        finish(minutesStudied: Int(Date().timeIntervalSince(startedAt) / 60), completed: false)
    }

    private func tick() {
        now = Date()
        if let endsAt, now >= endsAt { finish(minutesStudied: minutes, completed: true) }
    }

    private func finish(minutesStudied: Int, completed: Bool) {
        ticker?.invalidate()
        ticker = nil
        endsAt = nil
        startedAt = nil
        StudyProgressStore.shared.recordFocus(minutes: minutesStudied)
        if completed {
            lastFinishedMinutes = minutesStudied
            NSSound(named: "Glass")?.play()
        }
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }
}
