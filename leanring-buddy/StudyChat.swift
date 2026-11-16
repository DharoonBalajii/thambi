//
//  StudyChat.swift
//  leanring-buddy
//
//  The Ask page of the Thambi window: typed questions answered in writing from your own
//  materials, with numbered sources you can open.
//
//  • Finding the passages is free and happens on this Mac. The question and those few passages
//    (about ₹0.01 of reading) go to the AI service; nothing else in the library is sent.
//  • No screenshot is taken here, which keeps a written question at about ₹0.03.
//  • The conversation lives in memory only; close the window and it is gone. Save an answer as
//    a note (Write mode) to keep it.
//

import Combine
import Foundation

nonisolated struct StudyChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable { case student, thambi }
    let id = UUID()
    var role: Role
    var text: String
    var sources: [StudySource] = []
    var citedNumbers: [Int] = []
    var isStreaming = false
    var errorText: String?
    var savedNotePath: String?
    var modeUsed: StudyMode = .write
    var subjectScope: String?
}

@MainActor
final class StudyChatModel: ObservableObject {

    @Published private(set) var messages: [StudyChatMessage] = []
    @Published private(set) var isAnswering = false
    /// Nil means every subject.
    @Published var subjectScope: String?
    @Published private(set) var mode: StudyMode = ThambiSettings.studyMode
    /// Token counts of the last answer (counts only), for the log and cost checks.
    private(set) var lastTokenSummary = ""

    private let library: StudyLibraryStore
    private let claudeAPI = ClaudeAPI(proxyURL: CompanionManager.openRouterMessagesURL, model: ClickyModelRouter.haikuModelID)
    private var answerTask: Task<Void, Never>?
    private var modeObserver: NSObjectProtocol?

    init(library: StudyLibraryStore = .shared) {
        self.library = library
        modeObserver = NotificationCenter.default.addObserver(forName: ThambiSettings.studyModeChangedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.mode = ThambiSettings.studyMode }
        }
    }

    func setMode(_ newMode: StudyMode) {
        ThambiSettings.studyMode = newMode
    }

    static let systemPrompt = """
    you're thambi, a study buddy for college students. the student typed a question in the thambi app and will read your answer on screen.

    rules:
    - answer like a good senior explaining before an exam: clear, correct, no filler. start with the direct answer, then the why.
    - use markdown: short paragraphs, bullet points for steps or lists, **bold** for key terms, `code` for code. headings only for long answers. no tables wider than four columns.
    - keep it as short as the question allows. a definition is two or three sentences; "explain in detail" or "make notes" can be long.
    - if they ask for exam help, show how marks are usually earned: definition, diagram in words if needed, example, key points.
    - write formulas plainly (like v = u + at) unless they ask for LaTeX.
    - never invent page numbers, sources or quotes.
    - if something is ambiguous, answer the most likely meaning and say what you assumed.
    """

    func ask(_ rawQuestion: String) {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else { return }
        let modeForThisQuestion = mode
        let scope = subjectScope
        messages.append(StudyChatMessage(role: .student, text: question, modeUsed: modeForThisQuestion, subjectScope: scope))
        let answer = StudyChatMessage(role: .thambi, text: "", isStreaming: true, modeUsed: modeForThisQuestion, subjectScope: scope)
        messages.append(answer)
        let answerID = answer.id
        isAnswering = true

        // Earlier turns ride along (shortened) so follow-ups like "give an example" work.
        let history: [(userPlaceholder: String, assistantResponse: String)] = messages.dropLast(2).pairsForHistory()

        answerTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isAnswering = false }
            let found = await library.sources(for: question, subject: scope)
            self.update(answerID) { $0.sources = found.sources }

            let modelDecision = ClickyModelRouter.chooseModel(forTranscript: question, selectedMode: UserDefaults.standard.string(forKey: "selectedModelMode") ?? ClickyModelRouter.autoModeIdentifier)
            claudeAPI.model = modelDecision.modelID
            let writeRule = modeForThisQuestion.mayWrite
                ? ""
                : "\n- the student's study mode does not let you write for them: don't produce essays, full assignment answers or code to submit. explain and guide instead."
            let system = Self.systemPrompt + writeRule + ThambiMemory.promptSection(for: ThambiMemory.load())
            // A subject kept in memory rides along whole, in its own block cached for an hour. The
            // passages are then only needed to cite pages, so three are enough.
            let memorySubject = library.memorySubject(scope: scope, sources: found.sources)
            let subjectMemory = library.subjectMemory(for: memorySubject)
            let sources = subjectMemory == nil ? found.sources : Array(found.sources.prefix(3))
            if sources.count != found.sources.count { self.update(answerID) { $0.sources = sources } }
            let sourcesSection = library.materials.isEmpty && !modeForThisQuestion.usesOnlyMaterials
                ? nil
                : StudyLibrary.promptSection(sources: sources, mode: modeForThisQuestion, isSpoken: false)

            do {
                let (fullText, _) = try await claudeAPI.analyzeImageStreaming(
                    images: [],
                    systemPrompt: system,
                    subjectMemoryText: subjectMemory?.text,
                    documentText: sourcesSection,
                    cachesDocumentText: false,
                    maximumOutputTokens: 1_200,
                    conversationHistory: history,
                    userPrompt: question,
                    onTextChunk: { [weak self] partial in
                        self?.update(answerID) { $0.text = partial }
                    }
                )
                let cleaned = StudyLibrary.withoutUnknownCitations(SpeechTimedTags.withoutLeakedReasoning(fullText), sourceCount: sources.count)
                let cited = StudyLibrary.citedSourceNumbers(in: cleaned, sourceCount: sources.count)
                update(answerID) {
                    $0.text = cleaned
                    $0.citedNumbers = cited
                    $0.isStreaming = false
                }
                lastTokenSummary = claudeAPI.lastTokenUsage.summary
                print("📚 Ask: \(sources.count) sources, cited \(cited.count)\(memorySubject == nil ? "" : ", subject kept in memory") — tokens \(claudeAPI.lastTokenUsage.summary)")
                // Write mode and the student asked for notes: keep them without another click.
                if modeForThisQuestion.mayWrite, NotesMarkdown.userAskedToWrite(question) {
                    saveAsNote(answerID)
                }
            } catch is CancellationError {
                update(answerID) { $0.isStreaming = false }
            } catch {
                let isCancelled = (error as NSError).code == NSURLErrorCancelled
                print("📚 Ask failed: \((error as NSError).code)")
                update(answerID) {
                    $0.isStreaming = false
                    if !isCancelled {
                        $0.errorText = (error as NSError).code == 401
                            ? "No AI key is set up yet. Add your OpenRouter key from the menu bar panel."
                            : "Couldn't reach the AI service. Check your internet and try again."
                    }
                }
            }
        }
    }

    func stop() {
        answerTask?.cancel()
        answerTask = nil
        isAnswering = false
        if let index = messages.lastIndex(where: { $0.isStreaming }) { messages[index].isStreaming = false }
    }

    func clear() {
        stop()
        messages.removeAll()
    }

    /// Only Write mode lets Thambi save. The title is the student's question.
    func saveAsNote(_ answerID: UUID) {
        guard mode.mayWrite || messages.first(where: { $0.id == answerID })?.modeUsed.mayWrite == true,
              let answerIndex = messages.firstIndex(where: { $0.id == answerID }), answerIndex > 0 else { return }
        let answer = messages[answerIndex]
        let question = messages[answerIndex - 1].text
        var markdown = "# \(question.prefix(80))\n\n" + answer.text
        let cited = answer.sources.filter { answer.citedNumbers.contains($0.number) }
        if !cited.isEmpty {
            markdown += "\n\n## Sources\n" + cited.map { "- [\($0.number)] \($0.placeLabel)" }.joined(separator: "\n")
        }
        if let url = library.saveNote(title: String(question.prefix(60)), markdown: markdown, replacing: answer.savedNotePath) {
            messages[answerIndex].savedNotePath = url.path
        }
    }

    private func update(_ id: UUID, _ change: (inout StudyChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }
}

private extension ArraySlice where Element == StudyChatMessage {
    /// The last few complete question-and-answer pairs, answers shortened.
    func pairsForHistory(maximumPairs: Int = 4) -> [(userPlaceholder: String, assistantResponse: String)] {
        var pairs: [(userPlaceholder: String, assistantResponse: String)] = []
        var pendingQuestion: String?
        for message in self {
            switch message.role {
            case .student: pendingQuestion = message.text
            case .thambi:
                if let question = pendingQuestion, !message.text.isEmpty, message.errorText == nil {
                    pairs.append((question, ThambiSettings.shortenedForHistory(message.text)))
                }
                pendingQuestion = nil
            }
        }
        return Array(pairs.suffix(maximumPairs))
    }
}
