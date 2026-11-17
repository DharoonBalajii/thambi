//
//  MainWindowDebug.swift
//  leanring-buddy
//
//  Test runs for the study window, Debug builds only (none of this is in the released app).
//  Adds files to a separate test library, asks questions through the real Ask pipeline, writes
//  the answers with their sources and token counts, takes a picture of the window, then quits.
//

#if DEBUG
import AppKit
import Foundation

@MainActor
enum MainWindowDebug {
    static func runIfAsked(_ controller: MainWindowController) {
        let defaults = UserDefaults.standard
        guard let outputDirectory = defaults.string(forKey: "ThambiDebugWindowOutput") else { return }
        let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let library = controller.debugLibrary
        let chat = controller.debugChat

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let modeName = defaults.string(forKey: "ThambiDebugMode"), let mode = StudyMode(rawValue: modeName) { chat.setMode(mode) }
            if let files = defaults.string(forKey: "ThambiDebugLibraryAdd") {
                let subject = defaults.string(forKey: "ThambiDebugLibrarySubject")
                library.add(files.components(separatedBy: "|").map { URL(fileURLWithPath: $0) }, subject: subject)
                while library.importItems.contains(where: { $0.status == .reading }) {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            if let kept = defaults.string(forKey: "ThambiDebugKeepInMemory") { library.setKeptInMemory(kept, true) }
            if let scope = defaults.string(forKey: "ThambiDebugScope") { chat.subjectScope = scope }
            if let rename = defaults.string(forKey: "ThambiDebugRenameNote")?.components(separatedBy: "|"), rename.count == 2,
               let note = library.notes.first(where: { $0.title == rename[0] }) {
                library.saveNote(title: rename[1], markdown: "# \(rename[1])\n\nrenamed", replacing: note.sourcePath)
                while library.importItems.contains(where: { $0.status == .reading }) { try? await Task.sleep(nanoseconds: 200_000_000) }
            }
            if let noteTitle = defaults.string(forKey: "ThambiDebugSaveNote") {
                library.saveNote(title: noteTitle, markdown: "# \(noteTitle)\n\n- Ageing raises priority the longer a process waits.\n- Quantum too small: context switches dominate.")
                while library.importItems.contains(where: { $0.status == .reading }) { try? await Task.sleep(nanoseconds: 200_000_000) }
            }

            var report = "materials: \(library.materials.map { "\($0.title) [\($0.subject), \($0.kind.rawValue), \($0.pageCount)p, \($0.passageCount) passages, \($0.pagesReadFromPictures) from pictures]" })\n"
            report += "import problems: \(library.importItems.map { "\($0.fileName): \($0.status)" })\n\n"
            for question in (defaults.string(forKey: "ThambiDebugAsk") ?? "").components(separatedBy: "|") where !question.isEmpty {
                chat.ask(question)
                while chat.isAnswering { try? await Task.sleep(nanoseconds: 200_000_000) }
                guard let answer = chat.messages.last else { continue }
                report += "Q: \(question)\nmode: \(answer.modeUsed.rawValue), scope: \(answer.subjectScope ?? "all")\n"
                report += "sources found: \(answer.sources.map { "[\($0.number)] \($0.placeLabel) (\(String(format: "%.2f", $0.score)))" })\n"
                report += "tokens: \(chat.lastTokenSummary)\ncited: \(answer.citedNumbers)\nerror: \(answer.errorText ?? "none")\nA: \(answer.text)\n\n"
            }
            // One real quiz: questions made, the first one answered and checked.
            if let quizSubject = defaults.string(forKey: "ThambiDebugQuiz") {
                let practice = StudyPracticeStore.shared
                practice.loadIfNeeded()
                practice.startQuiz(subject: quizSubject.isEmpty ? nil : quizSubject, count: 3)
                while practice.isWorking { try? await Task.sleep(nanoseconds: 200_000_000) }
                report += "quiz error: \(practice.errorText ?? "none")\n"
                if let quiz = practice.quiz {
                    for question in quiz.questions { report += "Q: \(question.question)\nA: \(question.answer)\nS: \(question.sourceNumber.map(String.init) ?? "none")\n" }
                    let first = quiz.questions[0]
                    practice.setAnswer(defaults.string(forKey: "ThambiDebugQuizAnswer") ?? "I don't know", for: first.id)
                    practice.checkAnswer(first.id)
                    while practice.isWorking { try? await Task.sleep(nanoseconds: 200_000_000) }
                    if let result = practice.quiz?.results[first.id] { report += "verdict: \(result.verdict.rawValue), card added: \(result.addedCard)\nfeedback: \(result.feedback)\n" }
                    report += "quiz cost: \(StudyCost.label(rupees: practice.quiz?.costRupees ?? 0)), cards now: \(practice.cards.count)\n"
                }
            }
            // Two test copies on one Mac: the guest asks the host to be friends, then they talk and share.
            if let socialName = defaults.string(forKey: "ThambiDebugSocialName") {
                let social = StudySocialStore.shared
                let role = defaults.string(forKey: "ThambiDebugSocialRole") ?? "guest"
                social.setName(socialName)
                social.setEnabled(true)
                if role == "host" { StudyFocusTimer.shared.start(minutes: 25, subject: "DBMS") }
                var didSend = false
                let deadline = Date().addingTimeInterval(Double(defaults.integer(forKey: "ThambiDebugSocialSeconds")))
                while Date() < deadline {
                    if role == "host" {
                        for request in social.incomingRequests { social.answer(request, accept: true) }
                        if let friend = social.friends.first, !didSend, !social.conversation(with: friend.id).isEmpty {
                            social.send("Got it, thanks. Opening the model now.", to: friend.id)
                            didSend = true
                        }
                    } else {
                        if social.friends.isEmpty, let person = social.nearbyStrangers.first, !social.sentRequests.contains(person.id) {
                            social.sendFriendRequest(to: person)
                        }
                        if let friend = social.friends.first, social.isOnline(friend), !didSend {
                            social.send("Stuck on the cardiac cycle. Does this help?", attachment: .drawing(title: "Human heart", source: StudySocial.modelDrawingSource("heart")), to: friend.id)
                            social.send("", attachment: .note(title: "ACID in one line", markdown: "Atomic, consistent, isolated, durable."), to: friend.id)
                            didSend = true
                        }
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                report += "social \(role) \(social.profile.name): nearby \(social.nearby.map(\.name)), friends \(social.friends.map { "\($0.name) online=\(social.isOnline($0)) status=\($0.status?.line() ?? "none")" })\n"
                for friend in social.friends {
                    for message in social.conversation(with: friend.id) {
                        report += "  \(message.from == social.profile.id ? "me" : friend.name): \(message.text) [\(message.attachment?.kindTitle ?? "text")] delivered=\(message.isDelivered)\n"
                    }
                }
            }
            report += "token log: see console lines starting with 📚\n"
            try? report.write(to: outputURL.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            try? await Task.sleep(nanoseconds: 800_000_000)
            controller.debugSnapshot(to: outputURL.appendingPathComponent("window.png"))
            NSApp.terminate(nil)
        }
    }
}
#endif
