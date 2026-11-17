//
//  MainWindow.swift
//  leanring-buddy
//
//  The Thambi window: a place to study, beside the menu bar buddy.
//
//  • Ask: typed questions answered from your own materials, with sources you can open.
//  • Library: your subjects and materials (PDFs, Word files, slides, photos of notes, text).
//  • Notes: what you or Thambi wrote down, kept as Markdown files and searchable like the rest.
//  • Study mode (Read, Write, Restricted) sits at the bottom of the sidebar and applies everywhere.
//
//  Console system: graphite surfaces, amber marks what you chose or must act on, cool blue is
//  Thambi. Measured values (pages, passages) are monospaced; nothing else is.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Window

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let library = StudyLibraryStore.shared
    private let chat = StudyChatModel()

    func show() {
        library.loadIfNeeded()
        if window == nil { window = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        newWindow.title = "Thambi"
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isReleasedWhenClosed = false
        newWindow.minSize = NSSize(width: 820, height: 560)
        newWindow.backgroundColor = NSColor(DS.Colors.background)
        newWindow.contentView = NSHostingView(rootView: MainWindowView(library: library, chat: chat, page: Self.initialPage))
        newWindow.setFrameAutosaveName("ThambiMainWindow")
        if newWindow.frame.origin == .zero { newWindow.center() }
        newWindow.delegate = self
        return newWindow
    }

    private static var initialPage: MainWindowPage {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "ThambiDebugWindowPage") {
        case "library": return .library
        case "notes": return .notes
        case "practice": return .practice
        case "friends": return .friends
        default: return .ask
        }
        #else
        return .ask
        #endif
    }

    #if DEBUG
    var debugLibrary: StudyLibraryStore { library }
    var debugChat: StudyChatModel { chat }
    /// The window as a picture (AppKit-drawn controls included), for test runs.
    func debugSnapshot(to url: URL) {
        guard let contentView = window?.contentView,
              let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { return }
        contentView.cacheDisplay(in: contentView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif
}

// MARK: - Root

enum MainWindowPage: Hashable {
    case ask, library, notes, practice, friends

    static let ordered: [MainWindowPage] = [.ask, .library, .notes, .practice, .friends]
}

struct MainWindowView: View {
    @ObservedObject var library: StudyLibraryStore
    @ObservedObject var chat: StudyChatModel
    @ObservedObject private var practice = StudyPracticeStore.shared
    @ObservedObject private var social = StudySocialStore.shared
    @ObservedObject private var progress = StudyProgressStore.shared
    @ObservedObject private var focusTimer = StudyFocusTimer.shared

    @State var page: MainWindowPage = .ask
    @State private var pendingAdd: [URL]?
    @State private var needsConsent = !ThambiPrivacy.hasAcceptedCurrentVersion
    @State private var legalDocument: ThambiPrivacy.Document?

    var body: some View {
        HStack(spacing: 0) {
            MainSidebar(library: library, chat: chat, practice: practice, social: social, progress: progress, focusTimer: focusTimer, page: $page, onAdd: chooseFilesToAdd)
                .frame(width: 228)
            Rectangle().fill(DS.Colors.borderSubtle).frame(width: 1)
            Group {
                switch page {
                case .ask: AskPage(library: library, chat: chat, onAdd: chooseFilesToAdd)
                case .library: LibraryPage(library: library, chat: chat, onAdd: chooseFilesToAdd)
                case .notes: NotesPage(library: library, chat: chat)
                case .practice: PracticePage(practice: practice, library: library, chat: chat, progress: progress)
                case .friends: FriendsPage(social: social, library: library, practice: practice)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Colors.background)
        }
        .background(DS.Colors.background)
        .background(pageShortcuts)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { practice.loadIfNeeded() }
        .sheet(isPresented: $needsConsent) { ConsentSheet { needsConsent = false } }
        .sheet(item: $legalDocument) { document in LegalDocumentSheet(document: document) { legalDocument = nil } }
        .onReceive(NotificationCenter.default.publisher(for: .thambiShowLegalDocument)) { note in
            legalDocument = (note.object as? String).flatMap(ThambiPrivacy.Document.init(rawValue:))
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadDroppedURLs(providers)
            return true
        }
        .sheet(isPresented: Binding(get: { pendingAdd != nil }, set: { if !$0 { pendingAdd = nil } })) {
            AddMaterialsSheet(
                urls: pendingAdd ?? [],
                subjects: library.subjects.filter { $0 != StudyLibraryStore.notesSubject },
                suggestedSubject: chat.subjectScope ?? library.subjects.first(where: { $0 != StudyLibraryStore.notesSubject }) ?? "",
                onAdd: { subject in
                    library.add(pendingAdd ?? [], subject: subject)
                    pendingAdd = nil
                    page = .library
                },
                onCancel: { pendingAdd = nil }
            )
        }
    }

    /// Command-1 to Command-5 switch pages.
    private var pageShortcuts: some View {
        ZStack {
            ForEach(Array(MainWindowPage.ordered.enumerated()), id: \.offset) { index, target in
                Button("") { page = target }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func chooseFilesToAdd() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        openPanel.prompt = "Add"
        openPanel.message = "Choose notes, PDFs, Word files, slides or photos of notes. A folder adds everything in it."
        guard openPanel.runModal() == .OK, !openPanel.urls.isEmpty else { return }
        pendingAdd = openPanel.urls
    }

    private func loadDroppedURLs(_ providers: [NSItemProvider]) {
        var collected: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { collected.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            DispatchQueue.main.async { if !collected.isEmpty { pendingAdd = collected } }
        }
    }
}

// MARK: - Sidebar

private struct MainSidebar: View {
    @ObservedObject var library: StudyLibraryStore
    @ObservedObject var chat: StudyChatModel
    @ObservedObject var practice: StudyPracticeStore
    @ObservedObject var social: StudySocialStore
    @ObservedObject var progress: StudyProgressStore
    @ObservedObject var focusTimer: StudyFocusTimer
    @Binding var page: MainWindowPage
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                ThambiMascot(mood: chat.isAnswering ? .thinking : .idle, size: 24)
                Text("Thambi")
                    .font(DS.font(15, .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 50)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                SidebarRow(title: "Ask", systemImage: "text.bubble", isSelected: page == .ask) { page = .ask }
                SidebarRow(title: "Library", systemImage: "books.vertical", count: library.materials.filter { $0.kind != .note }.count, isSelected: page == .library) { page = .library }
                SidebarRow(title: "Notes", systemImage: "note.text", count: library.notes.count, isSelected: page == .notes) { page = .notes }
                SidebarRow(title: "Practice", systemImage: "rectangle.on.rectangle.angled", count: practice.dueCards(subject: nil).count, isSelected: page == .practice) { page = .practice }
                SidebarRow(title: "Friends", systemImage: "person.2", count: social.totalUnread, isSelected: page == .friends) { page = .friends }
            }
            .padding(.horizontal, 8)

            HStack {
                Text("Subjects")
                    .font(DS.font(12, .medium))
                    .foregroundColor(DS.Colors.textTertiary)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(DS.font(11, .semibold))
                        .foregroundColor(DS.Colors.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Add materials")
                .accessibilityLabel("Add materials")
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 2) {
                    SidebarRow(title: "All subjects", systemImage: "square.stack", isSelected: chat.subjectScope == nil, isScope: true) {
                        chat.subjectScope = nil
                    }
                    ForEach(library.subjects, id: \.self) { subject in
                        SidebarRow(
                            title: subject,
                            systemImage: library.isKeptInMemory(subject) ? "memorychip" : (subject == StudyLibraryStore.notesSubject ? "note.text" : "folder"),
                            count: library.materials.filter { $0.subject == subject }.count,
                            isSelected: chat.subjectScope == subject, isScope: true
                        ) {
                            chat.subjectScope = subject
                        }
                        .contextMenu {
                            Toggle("Keep in memory", isOn: Binding(
                                get: { library.isKeptInMemory(subject) },
                                set: { library.setKeptInMemory(subject, $0) }
                            ))
                        }
                        .help(library.isKeptInMemory(subject) ? "\(subject) is kept in memory" : subject)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)
            FocusTimerWidget(timer: focusTimer, progress: progress, subject: chat.subjectScope)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            StudyModePicker(chat: chat)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            HStack(spacing: 12) {
                ForEach([ThambiPrivacy.Document.privacy, .terms]) { document in
                    Button(document == .privacy ? "Privacy" : "Terms") {
                        NotificationCenter.default.post(name: .thambiShowLegalDocument, object: document.rawValue)
                    }
                    .buttonStyle(.plain)
                    .font(DS.font(11))
                    .foregroundColor(DS.Colors.textTertiary)
                    .pointerCursor()
                    .accessibilityLabel(document.title)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .background(DS.Colors.surface1)
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    var count: Int? = nil
    let isSelected: Bool
    /// A subject row changes what Ask searches and what Library shows; a page row changes the page.
    var isScope = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(DS.font(12, .medium))
                    .foregroundColor(isSelected ? DS.Colors.accentText : DS.Colors.textTertiary)
                    .frame(width: 16)
                Text(title)
                    .font(DS.font(13, isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? DS.Colors.textPrimary : DS.Colors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DS.Colors.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                    .fill(isSelected ? (isScope ? DS.Colors.surface3 : DS.Colors.accentSubtle) : (isHovered ? DS.Colors.surface2 : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Read, Write, Restricted. The current one is amber: it is the student's choice.
private struct StudyModePicker: View {
    @ObservedObject var chat: StudyChatModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Study mode")
                .font(DS.font(12, .medium))
                .foregroundColor(DS.Colors.textTertiary)
            HStack(spacing: 2) {
                ForEach(StudyMode.allCases, id: \.self) { mode in
                    let isSelected = chat.mode == mode
                    Button(action: { chat.setMode(mode) }) {
                        Text(mode.title)
                            .font(DS.font(12, isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .foregroundColor(isSelected ? DS.Colors.accentText : DS.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(isSelected ? DS.Colors.accentSubtle : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .help(mode.explanation)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.well))
            .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).strokeBorder(DS.Colors.borderSubtle, lineWidth: 1))
            Text(chat.mode.explanation)
                .font(DS.font(11))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Page header

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.font(20, .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Text(subtitle)
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 28)
        .padding(.top, 46)
        .padding(.bottom, 16)
    }
}

struct WindowButton: View {
    enum Prominence { case primary, secondary }
    let title: String
    var systemImage: String? = nil
    var prominence: Prominence = .secondary
    var isEnabled = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(DS.font(11, .semibold)) }
                Text(title).font(DS.font(13, .medium))
            }
            .foregroundColor(prominence == .primary ? DS.Colors.textOnAccent : DS.Colors.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                    .fill(prominence == .primary ? (isHovered ? DS.Colors.accentHover : DS.Colors.accent) : (isHovered ? DS.Colors.surface3 : DS.Colors.surface2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                    .strokeBorder(prominence == .primary ? Color.clear : DS.Colors.borderStrong, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 && isEnabled }
        .pointerCursor(isEnabled: isEnabled)
    }
}

// MARK: - Ask

private struct AskPage: View {
    @ObservedObject var library: StudyLibraryStore
    @ObservedObject var chat: StudyChatModel
    let onAdd: () -> Void

    @State private var question = ""
    @FocusState private var isComposerFocused: Bool

    private var scopeLabel: String { chat.subjectScope ?? "All subjects" }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Ask", subtitle: subtitle) {
                if !chat.messages.isEmpty {
                    WindowButton(title: "New conversation", action: chat.clear)
                }
            }

            if chat.messages.isEmpty {
                askEmptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(chat.messages) { message in
                                ChatMessageView(message: message, chat: chat, library: library)
                                    .id(message.id)
                            }
                        }
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: chat.messages.last?.text) { _ in
                        if let lastID = chat.messages.last?.id { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }

            composer
                .frame(maxWidth: 760)
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
                .padding(.top, 8)
                .frame(maxWidth: .infinity)
        }
        .onAppear { isComposerFocused = true }
    }

    private var subtitle: String {
        let materialCount = library.materials.filter { chat.subjectScope == nil || $0.subject == chat.subjectScope }.count
        if materialCount == 0 { return "Searching \(scopeLabel.lowercased() == "all subjects" ? "your library" : scopeLabel): nothing added yet" }
        return "Searching \(scopeLabel): \(materialCount) \(materialCount == 1 ? "material" : "materials")"
    }

    private var askEmptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ThambiMascot(mood: .idle, size: 56)
            Text(library.materials.isEmpty ? "Add what you study, then ask" : "Ask about your materials")
                .font(DS.font(22, .semibold))
                .foregroundColor(DS.Colors.textPrimary)
            Text(library.materials.isEmpty
                 ? "Thambi answers from your own notes and textbooks and shows where each answer came from."
                 : "Answers come from \(scopeLabel == "All subjects" ? "your library" : scopeLabel), with the page each one came from.")
                .font(DS.font(14))
                .foregroundColor(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if library.materials.isEmpty {
                WindowButton(title: "Add materials", systemImage: "plus", prominence: .primary, action: onAdd)
                    .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(chat.mode == .restricted ? "Ask about your materials" : "Ask a question", text: $question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DS.font(14))
                    .foregroundColor(DS.Colors.textPrimary)
                    .lineLimit(1...6)
                    .focused($isComposerFocused)
                    .onSubmit(send)
                    .padding(.vertical, 9)
                    .accessibilityLabel("Question")

                if chat.isAnswering {
                    WindowButton(title: "Stop", action: chat.stop)
                        .padding(.bottom, 4)
                } else {
                    WindowButton(title: "Ask", prominence: .primary, isEnabled: !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: send)
                        .padding(.bottom, 4)
                        .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .background(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous).fill(DS.Colors.well))
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .strokeBorder(isComposerFocused ? DS.Colors.accent : DS.Colors.borderStrong, lineWidth: 1)
            )

            HStack(spacing: 6) {
                Menu {
                    Button("All subjects") { chat.subjectScope = nil }
                    Divider()
                    ForEach(library.subjects, id: \.self) { subject in
                        Button(subject) { chat.subjectScope = subject }
                    }
                } label: {
                    Text("In \(chat.subjectScope ?? "all subjects")")
                        .font(DS.font(12, .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Which subject to search")
                Menu {
                    ForEach(StudyAnswerFormat.allCases, id: \.self) { format in
                        Button(format.title) { chat.answerFormat = format }
                    }
                } label: {
                    Text(chat.answerFormat.shortTitle)
                        .font(DS.font(12, .medium))
                        .foregroundColor(chat.answerFormat == .normal ? DS.Colors.textSecondary : DS.Colors.accentText)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Write answers the way an exam marks them. Writing \"for 5 marks\" in a question works too.")
                .accessibilityLabel("Answer length: \(chat.answerFormat.title)")
                Text(modeLine)
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textTertiary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, 4)
        }
    }

    private var modeLine: String {
        switch chat.mode {
        case .restricted: return "Restricted: only your materials, hints not finished work"
        case .read: return "Read: Thambi explains, it doesn't save anything"
        case .write: return "Write: you can save answers as notes"
        }
    }

    private func send() {
        let text = question
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !chat.isAnswering else { return }
        question = ""
        chat.ask(text)
    }
}

private struct ChatMessageView: View {
    let message: StudyChatMessage
    @ObservedObject var chat: StudyChatModel
    @ObservedObject var library: StudyLibraryStore

    @State private var openSourceNumber: Int?
    @State private var pageSource: StudySource?
    @State private var didCopy = false

    var body: some View {
        switch message.role {
        case .student:
            HStack {
                Spacer(minLength: 80)
                Text(message.text)
                    .font(DS.font(14))
                    .foregroundColor(DS.Colors.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous).fill(DS.Colors.surface2))
            }
        case .thambi:
            HStack(alignment: .top, spacing: 12) {
                ThambiMascot(mood: message.isStreaming ? (message.text.isEmpty ? .thinking : .speaking) : .idle, size: 22, isActive: message.isStreaming)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 12) {
                    if message.text.isEmpty && message.isStreaming {
                        Text(message.sources.isEmpty ? "Looking through your materials" : "Reading \(message.sources.count) passages")
                            .font(DS.font(13))
                            .foregroundColor(DS.Colors.cool)
                    } else {
                        AnswerTextView(text: message.text)
                    }
                    if let errorText = message.errorText {
                        Text(errorText)
                            .font(DS.font(13))
                            .foregroundColor(DS.Colors.destructiveText)
                    }
                    if !message.isStreaming && message.errorText == nil {
                        sourcesList
                        actions
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .sheet(item: $pageSource) { source in
                SourcePageSheet(source: source, library: library) { pageSource = nil }
            }
        }
    }

    private var citedSources: [StudySource] {
        message.citedNumbers.compactMap { number in message.sources.first { $0.number == number } }
    }

    @ViewBuilder
    private var sourcesList: some View {
        if !citedSources.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sources")
                    .font(DS.font(12, .medium))
                    .foregroundColor(DS.Colors.textTertiary)
                ForEach(citedSources) { source in
                    SourceRow(source: source, isOpen: openSourceNumber == source.number, library: library, onOpenPage: { pageSource = source }) {
                        openSourceNumber = openSourceNumber == source.number ? nil : source.number
                    }
                }
            }
        } else if !library.materials.isEmpty {
            Text(message.sources.isEmpty ? "Nothing in your materials matched this question." : "This answer didn't use your materials.")
                .font(DS.font(12))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            WindowButton(title: didCopy ? "Copied" : "Copy", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(NotesMarkdown.plainText(from: message.text), forType: .string)
                didCopy = true
            }
            if message.savedNotePath != nil {
                Text("Saved to My notes")
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.success)
            } else if chat.mode.mayWrite {
                WindowButton(title: "Save as note", systemImage: "square.and.arrow.down") { chat.saveAsNote(message.id) }
            } else {
                Text("Switch to Write mode to save answers")
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            if message.id == chat.messages.last?.id, !chat.isAnswering {
                WindowButton(title: "Again", systemImage: "arrow.clockwise") { chat.regenerate(message.id) }
                    .help("Write this answer again\(chat.answerFormat == .normal ? "" : " for \(chat.answerFormat.title)")")
            }
            Spacer()
            if let cost = message.costRupees {
                Text(StudyCost.label(rupees: cost))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(DS.Colors.textTertiary)
                    .help("What this answer cost, worked out from its token counts")
            }
        }
    }
}

/// One cited source: where it is from, and the passage itself when opened.
private struct SourceRow: View {
    let source: StudySource
    let isOpen: Bool
    @ObservedObject var library: StudyLibraryStore
    let onOpenPage: () -> Void
    let toggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Text("\(source.number)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(DS.Colors.cool)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(DS.Colors.coolSubtle))
                    Text(source.placeLabel)
                        .font(DS.font(13))
                        .foregroundColor(DS.Colors.textPrimary)
                        .lineLimit(1)
                    Text(source.subject)
                        .font(DS.font(12))
                        .foregroundColor(DS.Colors.textTertiary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(DS.font(9, .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(isHovered || isOpen ? DS.Colors.surface2 : DS.Colors.surface1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .pointerCursor()
            .accessibilityLabel("Source \(source.number), \(source.placeLabel)")

            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    Text(source.text)
                        .font(DS.font(13))
                        .foregroundColor(DS.Colors.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let material = library.materials.first(where: { $0.id == source.materialID }) {
                        HStack(spacing: 8) {
                            if material.kind == .pdf || material.kind == .image {
                                WindowButton(title: source.page.map { "Show page \($0)" } ?? "Show", systemImage: "doc.viewfinder", action: onOpenPage)
                            }
                            WindowButton(title: "Open \(material.kind == .note ? "note" : "original")", systemImage: "arrow.up.forward.app") {
                                library.openOriginal(material)
                            }
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.well))
                .padding(.top, 4)
            }
        }
    }
}

/// Markdown answer: paragraphs, lists, tables and fenced code blocks.
struct AnswerTextView: View {
    let text: String

    private enum Segment: Hashable {
        case markdown(String)
        case code(String)
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var buffer: [String] = []
        var isInCode = false
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let joined = buffer.joined(separator: "\n")
                if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(isInCode ? .code(joined) : .markdown(joined))
                }
                buffer = []
                isInCode.toggle()
                continue
            }
            buffer.append(line)
        }
        let rest = buffer.joined(separator: "\n")
        if !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(isInCode ? .code(rest) : .markdown(rest)) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .markdown(let markdown):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(NotesMarkdown.lines(from: markdown).enumerated()), id: \.offset) { _, line in
                            NotesLineView(line: line)
                        }
                    }
                    .foregroundColor(DS.Colors.textPrimary)
                case .code(let code):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(code)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundColor(DS.Colors.codeText)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.well))
                }
            }
        }
        .textSelection(.enabled)
    }
}

// MARK: - Library

private struct LibraryPage: View {
    @ObservedObject var library: StudyLibraryStore
    @ObservedObject var chat: StudyChatModel
    let onAdd: () -> Void

    @State private var materialPendingRemoval: StudyMaterial?

    private var shownMaterials: [StudyMaterial] {
        library.materials.filter { $0.kind != .note && (chat.subjectScope == nil || $0.subject == chat.subjectScope) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: chat.subjectScope ?? "Library", subtitle: subtitle) {
                WindowButton(title: "Add materials", systemImage: "plus", prominence: .primary, action: onAdd)
            }

            if let subject = chat.subjectScope, !shownMaterials.isEmpty {
                SubjectMemoryRow(subject: subject, library: library)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 14)
            }

            if !library.importItems.isEmpty {
                VStack(spacing: 4) {
                    ForEach(library.importItems) { item in importRow(item) }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 10)
            }

            if !library.isLoaded {
                Spacer()
                Text("Opening your library")
                    .font(DS.font(13))
                    .foregroundColor(DS.Colors.textTertiary)
                Spacer()
            } else if shownMaterials.isEmpty && library.importItems.isEmpty {
                libraryEmptyState
            } else {
                materialsTable
            }
        }
        .confirmationDialog(
            "Remove \(materialPendingRemoval?.title ?? "this material") from your library?",
            isPresented: Binding(get: { materialPendingRemoval != nil }, set: { if !$0 { materialPendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let material = materialPendingRemoval { library.remove(material) }
                materialPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { materialPendingRemoval = nil }
        } message: {
            Text("Its passages are deleted from Thambi. The original file stays where it is.")
        }
    }

    private var subtitle: String {
        let pages = shownMaterials.reduce(0) { $0 + $1.pageCount }
        guard !shownMaterials.isEmpty else { return "Read and searched on this Mac. Nothing is uploaded." }
        return "\(shownMaterials.count) \(shownMaterials.count == 1 ? "material" : "materials"), \(pages) \(pages == 1 ? "page" : "pages"). Read on this Mac, nothing uploaded."
    }

    private var libraryEmptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray.and.arrow.down")
                .font(DS.font(34, .light))
                .foregroundColor(DS.Colors.textTertiary)
            Text(chat.subjectScope == nil ? "Your library is empty" : "Nothing in \(chat.subjectScope ?? "") yet")
                .font(DS.font(20, .semibold))
                .foregroundColor(DS.Colors.textPrimary)
            Text("Drop PDFs, Word files, slides or photos of your notes here. Thambi reads scans and handwriting too.")
                .font(DS.font(14))
                .foregroundColor(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            WindowButton(title: "Add materials", systemImage: "plus", prominence: .primary, action: onAdd)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var materialsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Subject").frame(width: 150, alignment: .leading)
                Text("Pages").frame(width: 56, alignment: .trailing)
                Text("Passages").frame(width: 70, alignment: .trailing)
                Text("Added").frame(width: 90, alignment: .trailing)
                Color.clear.frame(width: 28)
            }
            .font(DS.font(12, .medium))
            .foregroundColor(DS.Colors.textTertiary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            Rectangle().fill(DS.Colors.borderSubtle).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shownMaterials) { material in
                        MaterialRow(material: material, subjects: library.subjects.filter { $0 != StudyLibraryStore.notesSubject }, library: library) {
                            materialPendingRemoval = material
                        }
                        Rectangle().fill(DS.Colors.borderSubtle).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    private func importRow(_ item: StudyLibraryStore.ImportItem) -> some View {
        HStack(spacing: 10) {
            switch item.status {
            case .reading:
                ProgressView().controlSize(.small)
                Text("Reading \(item.fileName)")
                    .font(DS.font(13))
                    .foregroundColor(DS.Colors.cool)
                    .lineLimit(1)
                Spacer()
            case .failed(let reason):
                Image(systemName: "exclamationmark.triangle")
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.destructiveText)
                Text(reason)
                    .font(DS.font(13))
                    .foregroundColor(DS.Colors.textSecondary)
                    .lineLimit(2)
                Spacer()
                WindowButton(title: "Dismiss") { library.dismissImportItem(item) }
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.surface1))
    }
}

/// "Keep in memory" for one subject: the whole subject rides along with every question about it,
/// cached for an hour, so answers know all of it and follow-ups are cheap.
private struct SubjectMemoryRow: View {
    let subject: String
    @ObservedObject var library: StudyLibraryStore

    private var isKept: Binding<Bool> {
        Binding(get: { library.isKeptInMemory(subject) }, set: { library.setKeptInMemory(subject, $0) })
    }

    private var detail: String {
        guard library.isKeptInMemory(subject) else {
            return "Off: Thambi sends only the few passages that match each question."
        }
        let isComplete = library.subjectMemory(for: subject)?.isComplete ?? true
        return isComplete
            ? "On: every question about \(subject) sees all of it. Kept cached for an hour, so follow-ups cost little."
            : "On: \(subject) is longer than fits, so the start of each material is kept. Cached for an hour."
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "memorychip")
                .font(DS.font(14))
                .foregroundColor(library.isKeptInMemory(subject) ? DS.Colors.cool : DS.Colors.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep \(subject) in memory")
                    .font(DS.font(13, .medium))
                    .foregroundColor(DS.Colors.textPrimary)
                Text(detail)
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("Keep \(subject) in memory", isOn: isKept)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(DS.Colors.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous).fill(DS.Colors.surface1))
        .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous).strokeBorder(DS.Colors.borderSubtle, lineWidth: 1))
    }
}

private struct MaterialRow: View {
    let material: StudyMaterial
    let subjects: [String]
    @ObservedObject var library: StudyLibraryStore
    let onRemove: () -> Void

    @State private var isHovered = false

    private var icon: String {
        switch material.kind {
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        case .slides: return "rectangle.on.rectangle"
        case .image: return "photo"
        case .note: return "note.text"
        case .text: return "doc.plaintext"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(DS.font(13))
                    .foregroundColor(DS.Colors.textTertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(material.title)
                        .font(DS.font(13))
                        .foregroundColor(DS.Colors.textPrimary)
                        .lineLimit(1)
                    if material.pagesReadFromPictures > 0 {
                        Text("\(material.pagesReadFromPictures) \(material.pagesReadFromPictures == 1 ? "page" : "pages") read from pictures")
                            .font(DS.font(11))
                            .foregroundColor(DS.Colors.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(material.subject)
                .font(DS.font(13))
                .foregroundColor(DS.Colors.textSecondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text("\(material.pageCount)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(width: 56, alignment: .trailing)
            Text("\(material.passageCount)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(width: 70, alignment: .trailing)
            Text(material.addedAt.formatted(.dateTime.day().month(.abbreviated)))
                .font(DS.font(12))
                .foregroundColor(DS.Colors.textTertiary)
                .frame(width: 90, alignment: .trailing)
            Menu {
                rowMenu
            } label: {
                Image(systemName: "ellipsis")
                    .font(DS.font(12, .semibold))
                    .foregroundColor(DS.Colors.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
            .opacity(isHovered ? 1 : 0.5)
            .help("More")
            .accessibilityLabel("More for \(material.title)")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(isHovered ? DS.Colors.surface1 : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { library.openOriginal(material) }
        .contextMenu { rowMenu }
    }

    @ViewBuilder
    private var rowMenu: some View {
        Button("Open") { library.openOriginal(material) }
        Button("Show in Finder") { library.revealOriginal(material) }
        Menu("Move to subject") {
            ForEach(subjects.filter { $0 != material.subject }, id: \.self) { subject in
                Button(subject) { library.move(material, toSubject: subject) }
            }
        }
        Divider()
        Button("Remove from library", role: .destructive, action: onRemove)
    }
}

// MARK: - Add materials sheet

private struct AddMaterialsSheet: View {
    let urls: [URL]
    let subjects: [String]
    let suggestedSubject: String
    let onAdd: (String?) -> Void
    let onCancel: () -> Void

    @State private var subject = ""
    @FocusState private var isSubjectFocused: Bool

    private var hasFolders: Bool {
        urls.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(urls.count == 1 ? "Add \(urls[0].lastPathComponent)" : "Add \(urls.count) items")
                .font(DS.font(16, .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 6) {
                Text("Subject")
                    .font(DS.font(12, .medium))
                    .foregroundColor(DS.Colors.textSecondary)
                HStack(spacing: 6) {
                    TextField(hasFolders ? "Use each folder's name" : "For example DBMS or Physics", text: $subject)
                        .textFieldStyle(.plain)
                        .font(DS.font(13))
                        .foregroundColor(DS.Colors.textPrimary)
                        .focused($isSubjectFocused)
                        .onSubmit(add)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.well))
                        .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).strokeBorder(isSubjectFocused ? DS.Colors.accent : DS.Colors.borderStrong, lineWidth: 1))
                    if !subjects.isEmpty {
                        Menu {
                            ForEach(subjects, id: \.self) { existing in Button(existing) { subject = existing } }
                        } label: {
                            Text("Existing").font(DS.font(12, .medium))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                Text("Thambi reads the files on this Mac and keeps their text. The originals stay where they are.")
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                WindowButton(title: "Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                WindowButton(title: "Add", prominence: .primary, action: add)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(DS.Colors.surface1)
        .onAppear {
            subject = hasFolders ? "" : suggestedSubject
            isSubjectFocused = true
        }
    }

    private func add() {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        onAdd(trimmed.isEmpty ? (hasFolders ? nil : "General") : StudyLibrary.cleanedSubjectName(trimmed))
    }
}

// MARK: - Notes

private struct NotesPage: View {
    @ObservedObject var library: StudyLibraryStore
    @ObservedObject var chat: StudyChatModel

    @State private var selectedNoteID: UUID?
    @State private var draftTitle = ""
    @State private var draftText = ""
    @State private var isDirty = false
    @State private var notePendingRemoval: StudyMaterial?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Notes", subtitle: "Markdown files on this Mac, searched along with your materials.") {
                WindowButton(title: "New note", systemImage: "square.and.pencil", action: newNote)
            }
            if library.notes.isEmpty && selectedNoteID == nil && draftText.isEmpty && !isDirty {
                notesEmptyState
            } else {
                HStack(spacing: 0) {
                    notesList.frame(width: 240)
                    Rectangle().fill(DS.Colors.borderSubtle).frame(width: 1)
                    editor
                }
                .overlay(Rectangle().strokeBorder(DS.Colors.borderSubtle, lineWidth: 1))
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
            }
        }
        .onAppear {
            // Open on the newest note rather than an empty editor.
            if selectedNoteID == nil, !isDirty, let newest = library.notes.first { select(newest) }
        }
        .onChange(of: library.notes.first?.id) { _ in
            if selectedNoteID == nil, !isDirty, let newest = library.notes.first { select(newest) }
        }
        .confirmationDialog(
            "Delete \(notePendingRemoval?.title ?? "this note")?",
            isPresented: Binding(get: { notePendingRemoval != nil }, set: { if !$0 { notePendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete note", role: .destructive) {
                if let note = notePendingRemoval {
                    library.remove(note)
                    if selectedNoteID == note.id { selectedNoteID = nil; draftText = ""; draftTitle = ""; isDirty = false }
                }
                notePendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { notePendingRemoval = nil }
        } message: {
            Text("The Markdown file is deleted from this Mac.")
        }
    }

    private var notesEmptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "note.text")
                .font(DS.font(34, .light))
                .foregroundColor(DS.Colors.textTertiary)
            Text("No notes yet")
                .font(DS.font(20, .semibold))
                .foregroundColor(DS.Colors.textPrimary)
            Text(chat.mode.mayWrite
                 ? "Write your own, or ask Thambi to make notes and save the answer."
                 : "Write your own. In Write mode Thambi can save notes for you too.")
                .font(DS.font(14))
                .foregroundColor(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            WindowButton(title: "New note", systemImage: "square.and.pencil", prominence: .primary, action: newNote)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var notesList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(library.notes) { note in
                    Button(action: { select(note) }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .font(DS.font(13, selectedNoteID == note.id ? .semibold : .regular))
                                .foregroundColor(DS.Colors.textPrimary)
                                .lineLimit(1)
                            Text(note.addedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                .font(DS.font(11))
                                .foregroundColor(DS.Colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(selectedNoteID == note.id ? DS.Colors.surface3 : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .contextMenu {
                        Button("Show in Finder") { library.revealOriginal(note) }
                        Button("Delete note", role: .destructive) { notePendingRemoval = note }
                    }
                }
            }
            .padding(6)
        }
        .background(DS.Colors.surface1)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TextField("Title", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(DS.font(16, .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                    .onChange(of: draftTitle) { _ in isDirty = true }
                Spacer()
                if let selected = library.notes.first(where: { $0.id == selectedNoteID }) {
                    WindowButton(title: "Delete") { notePendingRemoval = selected }
                }
                WindowButton(title: isDirty ? "Save" : "Saved", prominence: isDirty ? .primary : .secondary, isEnabled: isDirty, action: save)
                    .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            Rectangle().fill(DS.Colors.borderSubtle).frame(height: 1)
            TextEditor(text: $draftText)
                .font(DS.font(14))
                .foregroundColor(DS.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(12)
                .onChange(of: draftText) { _ in isDirty = true }
        }
        .background(DS.Colors.background)
    }

    private func select(_ note: StudyMaterial) {
        if isDirty { save() }
        selectedNoteID = note.id
        draftTitle = note.title
        let fullText = library.noteText(for: note)
        // The title line is shown in the title field, not twice.
        if fullText.hasPrefix("# ") {
            draftText = fullText.components(separatedBy: "\n").dropFirst().joined(separator: "\n").trimmingCharacters(in: .newlines)
        } else {
            draftText = fullText
        }
        DispatchQueue.main.async { isDirty = false }
    }

    private func newNote() {
        if isDirty { save() }
        selectedNoteID = nil
        draftTitle = "Untitled note"
        draftText = ""
        DispatchQueue.main.async { isDirty = true }
    }

    /// The student's own writing is always theirs to save, whatever the study mode.
    private func save() {
        let title = draftTitle.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled note" : draftTitle
        let existingPath = library.notes.first(where: { $0.id == selectedNoteID })?.sourcePath
        _ = library.saveNote(title: title, markdown: "# \(title)\n\n\(draftText)", replacing: existingPath)
        isDirty = false
        // A new or renamed note gets a new entry once it has been read; pick it then.
        let previousID = selectedNoteID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard selectedNoteID == previousID, previousID == nil || !library.notes.contains(where: { $0.id == previousID }) else { return }
            selectedNoteID = library.notes.first(where: { $0.title == StudyLibrary.displayTitle(forFileName: title + ".md") })?.id ?? library.notes.first?.id
        }
    }
}
