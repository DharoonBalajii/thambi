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
            report += "token log: see console lines starting with 📚\n"
            try? report.write(to: outputURL.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            try? await Task.sleep(nanoseconds: 800_000_000)
            controller.debugSnapshot(to: outputURL.appendingPathComponent("window.png"))
            NSApp.terminate(nil)
        }
    }
}
#endif
