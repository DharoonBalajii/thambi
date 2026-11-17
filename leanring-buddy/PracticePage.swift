//
//  PracticePage.swift
//  leanring-buddy
//
//  Practice: review flashcards that are due (free), take a quiz made from your own materials,
//  and make new cards. Keyboard first: Space shows the answer, 1 to 4 rate it.
//

import SwiftUI

struct PracticePage: View {
    @ObservedObject var practice: StudyPracticeStore
    @ObservedObject var library: StudyLibraryStore
    @ObservedObject var chat: StudyChatModel
    @ObservedObject var progress: StudyProgressStore

    @State private var isReviewing = false
    @State private var cardPendingRemoval: StudyCard?

    private var scope: String? { chat.subjectScope == StudyLibraryStore.notesSubject ? nil : chat.subjectScope }
    private var scopeName: String { scope ?? "all subjects" }
    private var due: [StudyCard] { practice.dueCards(subject: scope) }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Practice", subtitle: subtitle) {
                if isReviewing || practice.quiz != nil {
                    WindowButton(title: "Done") {
                        isReviewing = false
                        practice.endQuiz()
                    }
                }
            }
            if practice.quiz != nil {
                QuizView(practice: practice, library: library)
            } else if isReviewing {
                ReviewView(practice: practice, subject: scope) { isReviewing = false }
            } else {
                overview
            }
        }
        .onAppear { practice.loadIfNeeded() }
        .confirmationDialog("Delete this flashcard?", isPresented: Binding(get: { cardPendingRemoval != nil }, set: { if !$0 { cardPendingRemoval = nil } }), titleVisibility: .visible) {
            Button("Delete card", role: .destructive) {
                if let card = cardPendingRemoval { practice.delete(card.id) }
                cardPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { cardPendingRemoval = nil }
        }
    }

    private var subtitle: String {
        let streak = progress.streak.current
        let streakPart = streak > 0 ? "\(streak) day streak. " : ""
        if due.isEmpty { return "\(streakPart)Nothing due in \(scopeName). Reviewing is free." }
        return "\(streakPart)\(due.count) \(due.count == 1 ? "card" : "cards") due in \(scopeName). Reviewing is free."
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    ActionCard(icon: "rectangle.on.rectangle.angled", title: due.isEmpty ? "No cards due" : "Review \(due.count) due",
                               detail: "Flashcards come back just before you would forget them.", buttonTitle: "Start review",
                               isPrimary: !due.isEmpty, isEnabled: !due.isEmpty) { isReviewing = true }
                    ActionCard(icon: "questionmark.bubble", title: "Quiz me on \(scopeName)",
                               detail: "Five questions from your own materials. What you miss becomes a flashcard. About ₹0.05.", buttonTitle: "Start quiz",
                               isPrimary: due.isEmpty, isEnabled: !practice.isWorking && !library.materials.isEmpty) { practice.startQuiz(subject: scope) }
                    ActionCard(icon: "plus.rectangle.on.rectangle", title: "Make flashcards",
                               detail: "Thambi reads \(scopeName) and writes cards for the ideas worth remembering. About ₹0.05.", buttonTitle: "Make cards",
                               isPrimary: false, isEnabled: !practice.isWorking && !library.materials.isEmpty) { practice.makeCards(subject: scope) }
                }
                if practice.isWorking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(practice.workStatus).font(DS.font(13)).foregroundColor(DS.Colors.cool)
                    }
                } else if let error = practice.errorText {
                    Text(error).font(DS.font(13)).foregroundColor(DS.Colors.destructiveText)
                } else if let summary = practice.lastMadeSummary {
                    Text(summary).font(DS.font(13)).foregroundColor(DS.Colors.success)
                } else if library.materials.isEmpty {
                    Text("Add notes or a textbook in Library first; quizzes and cards are made from them.")
                        .font(DS.font(13)).foregroundColor(DS.Colors.textTertiary)
                }

                let cards = practice.cards(subject: scope)
                if !cards.isEmpty {
                    Text("\(cards.count) \(cards.count == 1 ? "flashcard" : "flashcards")")
                        .font(DS.font(12, .medium))
                        .foregroundColor(DS.Colors.textTertiary)
                        .padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(cards.sorted { $0.due < $1.due }) { card in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(card.front).font(DS.font(13, .medium)).foregroundColor(DS.Colors.textPrimary).lineLimit(1)
                                    Text(card.back).font(DS.font(12)).foregroundColor(DS.Colors.textTertiary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(card.subject).font(DS.font(12)).foregroundColor(DS.Colors.textSecondary).lineLimit(1)
                                Text(dueLabel(card))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(card.due <= Date() ? DS.Colors.accentText : DS.Colors.textTertiary)
                                    .frame(width: 84, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                            .contextMenu { Button("Delete card", role: .destructive) { cardPendingRemoval = card } }
                            Rectangle().fill(DS.Colors.borderSubtle).frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
    }

    private func dueLabel(_ card: StudyCard) -> String {
        if card.due <= Date() { return "due now" }
        let days = StudyDay.daysBetween(Date(), card.due)
        if days == 0 { return "today" }
        return days == 1 ? "tomorrow" : "in \(days) days"
    }
}

private struct ActionCard: View {
    let icon: String
    let title: String
    let detail: String
    let buttonTitle: String
    let isPrimary: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(DS.Colors.cool)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous).fill(DS.Colors.coolSubtle))
            Text(title)
                .font(DS.font(15, .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(DS.font(12))
                .foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            WindowButton(title: buttonTitle, prominence: isPrimary ? .primary : .secondary, isEnabled: isEnabled, action: action)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous).fill(DS.Colors.surface1))
        .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous).strokeBorder(DS.Colors.borderSubtle, lineWidth: 1))
    }
}

// MARK: - Review

private struct ReviewView: View {
    @ObservedObject var practice: StudyPracticeStore
    let subject: String?
    let onFinish: () -> Void

    @State private var showsAnswer = false
    @State private var reviewed = 0

    private var card: StudyCard? { practice.dueCards(subject: subject).first }

    var body: some View {
        VStack(spacing: 18) {
            if let card {
                Text("\(practice.dueCards(subject: subject).count) left")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(DS.Colors.textTertiary)
                VStack(spacing: 16) {
                    Text(card.front)
                        .font(DS.font(22, .semibold))
                        .foregroundColor(DS.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsAnswer {
                        Rectangle().fill(DS.Colors.borderSubtle).frame(height: 1)
                        Text(card.back)
                            .font(DS.font(16))
                            .foregroundColor(DS.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if let sourceLabel = card.sourceLabel {
                            Text(sourceLabel).font(DS.font(12)).foregroundColor(DS.Colors.textTertiary)
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 620, minHeight: 240)
                .background(RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous).fill(DS.Colors.surface1))
                .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous).strokeBorder(DS.Colors.borderSubtle, lineWidth: 1))

                if showsAnswer {
                    HStack(spacing: 8) {
                        ForEach(StudyRating.allCases, id: \.self) { rating in
                            Button(action: { rate(card, rating) }) {
                                VStack(spacing: 2) {
                                    Text(rating.title).font(DS.font(13, .semibold)).foregroundColor(DS.Colors.textPrimary)
                                    Text(FSRS.label(for: card, rating: rating, at: Date()))
                                        .font(.system(size: 11, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)
                                }
                                .frame(width: 104, height: 48)
                                .background(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous).fill(DS.Colors.surface2))
                                .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous).strokeBorder(rating == .good ? DS.Colors.accent : DS.Colors.borderStrong, lineWidth: 1))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointerCursor()
                            .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue)")), modifiers: [])
                            .help("Press \(rating.rawValue)")
                        }
                    }
                } else {
                    WindowButton(title: "Show answer", prominence: .primary) { showsAnswer = true }
                        .keyboardShortcut(.space, modifiers: [])
                        .help("Press Space")
                }
                Text(showsAnswer ? "How well did you remember? Keys 1 to 4." : "Answer in your head first, then press Space.")
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textTertiary)
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 38, weight: .light))
                    .foregroundColor(DS.Colors.success)
                Text(reviewed > 0 ? "Done. \(reviewed) \(reviewed == 1 ? "card" : "cards") reviewed." : "Nothing is due.")
                    .font(DS.font(20, .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                WindowButton(title: "Back to Practice", prominence: .primary, action: onFinish)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
        .padding(.bottom, 40)
    }

    private func rate(_ card: StudyCard, _ rating: StudyRating) {
        practice.review(card.id, rating: rating)
        reviewed += 1
        showsAnswer = false
    }
}

// MARK: - Quiz

private struct QuizView: View {
    @ObservedObject var practice: StudyPracticeStore
    @ObservedObject var library: StudyLibraryStore

    @State private var answer = ""
    @State private var showsExpected = false
    @State private var pageSource: StudySource?
    @FocusState private var isAnswerFocused: Bool

    var body: some View {
        if let quiz = practice.quiz {
            if quiz.isFinished {
                finished(quiz)
            } else {
                question(quiz, quiz.questions[quiz.currentIndex])
                    .sheet(item: $pageSource) { source in
                        SourcePageSheet(source: source, library: library) { pageSource = nil }
                    }
            }
        }
    }

    private func question(_ quiz: StudyPracticeStore.QuizSession, _ question: StudyQuizQuestion) -> some View {
        let result = quiz.results[question.id]
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Question \(quiz.currentIndex + 1) of \(quiz.questions.count)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(DS.Colors.textTertiary)
                    Spacer()
                    Text(quiz.title).font(DS.font(12)).foregroundColor(DS.Colors.textTertiary)
                }
                Text(question.question)
                    .font(DS.font(20, .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $answer)
                    .font(DS.font(14))
                    .foregroundColor(DS.Colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isAnswerFocused)
                    .padding(8)
                    .frame(height: 110)
                    .background(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous).fill(DS.Colors.well))
                    .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous).strokeBorder(isAnswerFocused ? DS.Colors.accent : DS.Colors.borderStrong, lineWidth: 1))
                    .disabled(result != nil || showsExpected)
                    .accessibilityLabel("Your answer")

                if let result {
                    resultView(result, question: question, quiz: quiz)
                } else if showsExpected {
                    expectedAnswer(question, quiz: quiz)
                    Text("How did you do?").font(DS.font(13, .medium)).foregroundColor(DS.Colors.textPrimary)
                    HStack(spacing: 8) {
                        WindowButton(title: "I got it") { practice.markMyself(question.id, verdict: .correct) }
                        WindowButton(title: "Partly") { practice.markMyself(question.id, verdict: .partly) }
                        WindowButton(title: "I missed it") { practice.markMyself(question.id, verdict: .wrong) }
                    }
                } else {
                    HStack(spacing: 8) {
                        WindowButton(title: practice.isWorking ? "Checking" : "Check my answer", prominence: .primary, isEnabled: !practice.isWorking) {
                            practice.setAnswer(answer, for: question.id)
                            practice.checkAnswer(question.id)
                        }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .help("Thambi checks it, about ₹0.01. Command-Return.")
                        WindowButton(title: "Show the answer, I'll mark it") { showsExpected = true }
                            .help("Free")
                    }
                    if let error = practice.errorText {
                        Text(error).font(DS.font(13)).foregroundColor(DS.Colors.destructiveText)
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
        }
        .onAppear { isAnswerFocused = true }
    }

    private func expectedAnswer(_ question: StudyQuizQuestion, quiz: StudyPracticeStore.QuizSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Expected answer").font(DS.font(12, .medium)).foregroundColor(DS.Colors.textTertiary)
            Text(question.answer)
                .font(DS.font(14))
                .foregroundColor(DS.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let source = quiz.source(for: question) {
                HStack(spacing: 8) {
                    Text("From \(source.placeLabel)").font(DS.font(12)).foregroundColor(DS.Colors.textTertiary)
                    if library.materials.first(where: { $0.id == source.materialID })?.kind == .pdf {
                        WindowButton(title: "Show page", systemImage: "doc.viewfinder") { pageSource = source }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous).fill(DS.Colors.surface1))
    }

    private func resultView(_ result: StudyPracticeStore.QuizResult, question: StudyQuizQuestion, quiz: StudyPracticeStore.QuizSession) -> some View {
        let color = result.verdict == .correct ? DS.Colors.success : (result.verdict == .partly ? DS.Colors.warningText : DS.Colors.destructiveText)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: result.verdict == .correct ? "checkmark.circle.fill" : (result.verdict == .partly ? "circle.lefthalf.filled" : "xmark.circle.fill"))
                    .foregroundColor(color)
                Text(result.verdict.title).font(DS.font(15, .semibold)).foregroundColor(color)
                if result.addedCard {
                    Text("Added to your flashcards").font(DS.font(12)).foregroundColor(DS.Colors.textTertiary)
                }
            }
            if !result.feedback.isEmpty {
                Text(result.feedback)
                    .font(DS.font(14))
                    .foregroundColor(DS.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            expectedAnswer(question, quiz: quiz)
            WindowButton(title: quiz.currentIndex + 1 == quiz.questions.count ? "See my score" : "Next question", prominence: .primary) {
                answer = ""
                showsExpected = false
                practice.nextQuestion()
            }
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func finished(_ quiz: StudyPracticeStore.QuizSession) -> some View {
        let score = quiz.score
        let added = quiz.results.values.filter(\.addedCard).count
        return VStack(spacing: 12) {
            Text("\(score.right) of \(score.total)")
                .font(.system(size: 54, weight: .bold, design: .monospaced))
                .foregroundColor(DS.Colors.textPrimary)
            Text(score.half > 0 ? "right, and \(score.half) partly right" : "right")
                .font(DS.font(16))
                .foregroundColor(DS.Colors.textSecondary)
            if added > 0 {
                Text("\(added) \(added == 1 ? "question you missed is" : "questions you missed are") now in your flashcards and will come back for review.")
                    .font(DS.font(13))
                    .foregroundColor(DS.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Text("This quiz cost \(StudyCost.label(rupees: quiz.costRupees))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.Colors.textTertiary)
            HStack(spacing: 8) {
                WindowButton(title: "Another quiz", prominence: .primary) {
                    practice.endQuiz()
                    practice.startQuiz(subject: quiz.sources.first?.subject)
                }
                WindowButton(title: "Done") { practice.endQuiz() }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
}

// MARK: - Focus timer in the sidebar

struct FocusTimerWidget: View {
    @ObservedObject var timer: StudyFocusTimer
    @ObservedObject var progress: StudyProgressStore
    let subject: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Focus")
                    .font(DS.font(12, .medium))
                    .foregroundColor(DS.Colors.textTertiary)
                Spacer()
                if progress.minutesToday > 0 || progress.streak.current > 0 {
                    Text("\(StudyTimerRules.durationLabel(minutes: progress.minutesToday)) today, \(progress.streak.current) day streak")
                        .font(DS.font(11))
                        .foregroundColor(DS.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            if timer.isRunning {
                HStack(spacing: 10) {
                    Text(StudyTimerRules.clockLabel(seconds: timer.remainingSeconds))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundColor(DS.Colors.textPrimary)
                    Spacer()
                    Button("Stop") { timer.stop() }
                        .buttonStyle(.plain)
                        .font(DS.font(12, .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                        .pointerCursor()
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Colors.surface3)
                        Capsule().fill(DS.Colors.cool).frame(width: proxy.size.width * timer.progress)
                    }
                }
                .frame(height: 4)
                .accessibilityLabel("Focus session, \(timer.remainingSeconds / 60) minutes left")
                if let subject = timer.subject {
                    Text(subject).font(DS.font(11)).foregroundColor(DS.Colors.textTertiary).lineLimit(1)
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(StudyTimerRules.focusChoices, id: \.self) { minutes in
                        Button(action: { timer.start(minutes: minutes, subject: subject) }) {
                            Text("\(minutes)")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(DS.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DS.Colors.surface2))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                        .help("Focus for \(minutes) minutes\(subject.map { " on \($0)" } ?? "")")
                        .accessibilityLabel("Focus for \(minutes) minutes")
                    }
                }
                if let finished = timer.lastFinishedMinutes {
                    Text("\(finished) minutes done. Take a short break.")
                        .font(DS.font(11))
                        .foregroundColor(DS.Colors.success)
                }
            }
        }
    }
}
