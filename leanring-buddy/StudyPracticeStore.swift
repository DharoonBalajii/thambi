//
//  StudyPracticeStore.swift
//  leanring-buddy
//
//  Keeps the flashcards (a JSON file on this Mac) and runs quizzes and teach-back.
//
//  • A quiz is one small AI call (about ₹0.05): a handful of passages spread across the chosen
//    subject go up, questions come back with the passage each came from.
//  • Checking an answer is about ₹0.01. "I'll mark it myself" shows the expected answer for free.
//  • Wrong and half-right answers become flashcards, so what you missed comes back.
//  • Reviewing flashcards is free: the schedule runs on this Mac.
//

import Combine
import Foundation

/// One small AI request outside the chat: the study features each send one and read its text.
@MainActor
enum StudyAI {
    private static let api = ClaudeAPI(proxyURL: CompanionManager.openRouterMessagesURL, model: ClickyModelRouter.haikuModelID)

    static func complete(system: String, document: String?, prompt: String, maximumOutputTokens: Int = 1_200,
                         onText: @MainActor @Sendable (String) -> Void = { _ in }) async throws -> (text: String, rupees: Double) {
        api.model = ClickyModelRouter.haikuModelID
        let (text, _) = try await api.analyzeImageStreaming(
            images: [], systemPrompt: system, documentText: document, cachesDocumentText: false,
            maximumOutputTokens: maximumOutputTokens, userPrompt: prompt, onTextChunk: onText
        )
        print("📚 Study AI: tokens \(api.lastTokenUsage.summary)")
        return (SpeechTimedTags.withoutLeakedReasoning(text), api.lastTokenUsage.rupees)
    }

    static func friendlyError(_ error: Error) -> String {
        (error as NSError).code == 401
            ? "No AI key is set up yet. Add your OpenRouter key from the menu bar panel."
            : "Couldn't reach the AI service. Check your internet and try again."
    }
}

@MainActor
final class StudyPracticeStore: ObservableObject {

    static let shared = StudyPracticeStore()

    struct QuizResult: Equatable {
        var verdict: StudyAnswerVerdict
        var feedback: String
        var addedCard: Bool
        var markedByStudent: Bool
    }

    struct QuizSession: Equatable {
        var title: String
        var questions: [StudyQuizQuestion]
        var sources: [StudySource]
        var answers: [UUID: String] = [:]
        var results: [UUID: QuizResult] = [:]
        var currentIndex = 0
        var costRupees: Double = 0

        var isFinished: Bool { currentIndex >= questions.count }
        var score: (right: Int, half: Int, total: Int) {
            (results.values.filter { $0.verdict == .correct }.count, results.values.filter { $0.verdict == .partly }.count, questions.count)
        }
        func source(for question: StudyQuizQuestion) -> StudySource? {
            question.sourceNumber.flatMap { number in sources.first { $0.number == number } }
        }
    }

    @Published private(set) var cards: [StudyCard] = []
    @Published var quiz: QuizSession?
    @Published private(set) var isWorking = false
    @Published private(set) var workStatus = ""
    @Published var errorText: String?
    /// Quiz questions answered and cards reviewed, for the study streak.
    @Published private(set) var reviewedToday = 0

    private let library: StudyLibraryStore
    private var isLoaded = false

    init(library: StudyLibraryStore = .shared) {
        self.library = library
    }

    // MARK: Storage

    nonisolated private static var cardsFile: URL {
        StudyLibraryStore.baseDirectory.appendingPathComponent("Practice", isDirectory: true).appendingPathComponent("cards.json")
    }

    func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        if let data = try? Data(contentsOf: Self.cardsFile), let decoded = try? JSONDecoder().decode([StudyCard].self, from: data) {
            cards = decoded
        }
    }

    private func save() {
        let snapshot = cards
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: Self.cardsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: Self.cardsFile, options: .atomic) }
        }
    }

    // MARK: Cards

    func cards(subject: String?) -> [StudyCard] {
        cards.filter { subject == nil || $0.subject == subject }
    }

    func dueCards(subject: String?, at now: Date = Date()) -> [StudyCard] {
        cards(subject: subject).filter { $0.due <= now }.sorted { $0.due < $1.due }
    }

    func review(_ cardID: UUID, rating: StudyRating, at now: Date = Date()) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        cards[index] = FSRS.review(cards[index], rating: rating, at: now)
        save()
        StudyProgressStore.shared.recordReview()
    }

    func addCard(_ card: StudyCard) {
        // The same front in the same subject is one card.
        guard !cards.contains(where: { $0.subject == card.subject && $0.front.caseInsensitiveCompare(card.front) == .orderedSame }) else { return }
        cards.append(card)
        save()
    }

    func delete(_ cardID: UUID) {
        cards.removeAll { $0.id == cardID }
        save()
    }

    func update(_ cardID: UUID, front: String, back: String) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        cards[index].front = front
        cards[index].back = back
        save()
    }

    // MARK: Passages to practise from

    /// Up to `count` passages spread across the subject (or one material), skipping contents pages.
    func practiceSources(subject: String?, materialID: UUID?, count: Int) -> [StudySource] {
        let all = library.passages(subject: subject, materialID: materialID).filter { StudyPractice.isQuizWorthy($0.passage.text) }
        let picked = StudyPractice.spreadSample(all, count: count, seed: UInt64.random(in: 0...UInt64.max))
        return picked.enumerated().map { offset, item in
            StudySource(number: offset + 1, materialID: item.material.id, materialTitle: item.material.title,
                        subject: item.material.subject, page: item.passage.page, text: item.passage.text, score: 0)
        }
    }

    // MARK: Quiz

    func startQuiz(subject: String?, materialID: UUID? = nil, count: Int = 5) {
        guard !isWorking else { return }
        let sources = practiceSources(subject: subject, materialID: materialID, count: min(8, count + 2))
        guard !sources.isEmpty else {
            errorText = "There is nothing to quiz you on yet. Add notes or a textbook to \(subject ?? "your library") first."
            return
        }
        let title = materialID.flatMap { id in library.materials.first { $0.id == id }?.title } ?? subject ?? "All subjects"
        isWorking = true
        workStatus = "Writing \(count) questions from \(sources.count) passages of \(title)"
        errorText = nil
        Task {
            defer { isWorking = false }
            do {
                let result = try await StudyAI.complete(
                    system: StudyPractice.quizSystemPrompt + StudyLanguage.current.instruction(answeringStudent: false),
                    document: StudyPractice.sourcesBlock(sources),
                    prompt: StudyPractice.quizPrompt(count: count), maximumOutputTokens: 1_000)
                let questions = Array(StudyPractice.parseQuiz(result.text, sourceCount: sources.count).prefix(count))
                guard !questions.isEmpty else {
                    errorText = "Thambi couldn't make questions from these passages. Try another subject or material."
                    return
                }
                quiz = QuizSession(title: title, questions: questions, sources: sources, costRupees: result.rupees)
            } catch {
                errorText = StudyAI.friendlyError(error)
            }
        }
    }

    func setAnswer(_ text: String, for questionID: UUID) {
        quiz?.answers[questionID] = text
    }

    /// The AI compares the answer with the expected one and the passage (about ₹0.01).
    func checkAnswer(_ questionID: UUID) {
        guard let session = quiz, !isWorking, let question = session.questions.first(where: { $0.id == questionID }) else { return }
        let studentAnswer = (session.answers[questionID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !studentAnswer.isEmpty else {
            record(.wrong, feedback: "You left this one blank. Here is the answer to learn.", for: question, markedByStudent: false)
            return
        }
        isWorking = true
        workStatus = "Checking your answer"
        Task {
            defer { isWorking = false }
            do {
                let result = try await StudyAI.complete(
                    system: StudyPractice.gradingSystemPrompt + StudyLanguage.current.instruction(answeringStudent: false),
                    document: nil,
                    prompt: StudyPractice.gradingPrompt(question: question.question, modelAnswer: question.answer,
                                                         passage: session.source(for: question)?.text, studentAnswer: studentAnswer),
                    maximumOutputTokens: 220)
                quiz?.costRupees += result.rupees
                if let parsed = StudyPractice.parseVerdict(result.text) {
                    record(parsed.verdict, feedback: parsed.feedback, for: question, markedByStudent: false)
                } else {
                    errorText = "Thambi's reply couldn't be read. Mark this one yourself."
                }
            } catch {
                errorText = StudyAI.friendlyError(error)
            }
        }
    }

    /// Free: the student sees the expected answer and says how they did.
    func markMyself(_ questionID: UUID, verdict: StudyAnswerVerdict) {
        guard let question = quiz?.questions.first(where: { $0.id == questionID }) else { return }
        record(verdict, feedback: "", for: question, markedByStudent: true)
    }

    private func record(_ verdict: StudyAnswerVerdict, feedback: String, for question: StudyQuizQuestion, markedByStudent: Bool) {
        guard let session = quiz else { return }
        var added = false
        if verdict != .correct {
            let source = session.source(for: question)
            let before = cards.count
            addCard(StudyCard(front: question.question, back: question.answer, subject: source?.subject ?? session.title,
                              materialID: source?.materialID, sourceLabel: source?.placeLabel, page: source?.page, origin: .quiz))
            added = cards.count > before
        }
        quiz?.results[question.id] = QuizResult(verdict: verdict, feedback: feedback, addedCard: added, markedByStudent: markedByStudent)
        StudyProgressStore.shared.recordReview()
    }

    func nextQuestion() {
        quiz?.currentIndex += 1
    }

    func endQuiz() {
        quiz = nil
    }

    // MARK: Making cards

    /// One AI call turns passages (or a note) into flashcards. Returns how many were added.
    func makeCards(subject: String?, materialID: UUID? = nil, count: Int = 12) {
        guard !isWorking else { return }
        let sources = practiceSources(subject: subject, materialID: materialID, count: 8)
        guard !sources.isEmpty else {
            errorText = "There is nothing to make cards from yet. Add notes or a textbook to \(subject ?? "your library") first."
            return
        }
        isWorking = true
        errorText = nil
        workStatus = "Making flashcards from \(sources.count) passages"
        Task {
            defer { isWorking = false }
            do {
                let result = try await StudyAI.complete(
                    system: StudyPractice.cardsSystemPrompt + StudyLanguage.current.instruction(answeringStudent: false),
                    document: StudyPractice.sourcesBlock(sources),
                    prompt: StudyPractice.cardsPrompt(count: count), maximumOutputTokens: 1_200)
                let parsed = StudyPractice.parseCards(result.text, sourceCount: sources.count)
                let before = cards.count
                for card in parsed.prefix(count) {
                    let source = card.sourceNumber.flatMap { number in sources.first { $0.number == number } }
                    addCard(StudyCard(front: card.front, back: card.back, subject: source?.subject ?? subject ?? sources[0].subject,
                                      materialID: source?.materialID, sourceLabel: source?.placeLabel, page: source?.page,
                                      origin: materialID.flatMap { id in library.materials.first { $0.id == id } }?.kind == .note ? .note : .material))
                }
                let added = cards.count - before
                workStatus = ""
                lastMadeSummary = added == 0
                    ? "No new cards: these passages are already covered."
                    : "Added \(added) \(added == 1 ? "card" : "cards") (\(StudyCost.label(rupees: result.rupees)))."
            } catch {
                errorText = StudyAI.friendlyError(error)
            }
        }
    }

    @Published var lastMadeSummary: String?
}
