//
//  StudyLibraryStore.swift
//  leanring-buddy
//
//  Your study library on disk: the materials you add (PDFs, Word files, slides, photos of notes,
//  text) and the notes Thambi writes for you, read once and kept as searchable passages.
//
//  • Everything lives in ~/Library/Application Support/Thambi/Library and .../Notes on this Mac.
//    Originals are never moved, changed or uploaded; only their text is kept.
//  • Reading text from pictures (scans, photos of notes) and finding passages by meaning both use
//    Apple's on-device models, so adding a material is free and private.
//  • Remove a material and its passages are deleted with it.
//

import AppKit
import Combine
import Foundation
import NaturalLanguage
import PDFKit
import Vision

// MARK: - Reading files (runs off the main thread)

nonisolated enum StudyMaterialReader {

    struct ReadResult: Sendable {
        var pageTexts: [String]
        var pagesReadFromPictures: Int
    }

    enum ReadError: LocalizedError {
        case unsupported(String)
        case unreadable(String)
        case empty(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let name): return "\(name) can't be read. Export it as PDF or Word first."
            case .unreadable(let name): return "\(name) couldn't be opened. It may be locked or damaged."
            case .empty(let name): return "No text was found in \(name)."
            }
        }
    }

    static let maximumPages = 1_200
    static let maximumPicturePages = 80

    static func read(_ fileURL: URL, kind: StudyMaterial.Kind) throws -> ReadResult {
        let name = fileURL.lastPathComponent
        switch kind {
        case .pdf:
            guard let document = PDFDocument(url: fileURL), !document.isLocked else { throw ReadError.unreadable(name) }
            var pageTexts: [String] = []
            var picturePages = 0
            for pageIndex in 0..<min(document.pageCount, maximumPages) {
                guard let page = document.page(at: pageIndex) else { pageTexts.append(""); continue }
                var text = page.string ?? ""
                // A scanned page has no text layer: read it from its picture instead.
                if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 25, picturePages < maximumPicturePages {
                    let thumbnail = page.thumbnail(of: NSSize(width: 1700, height: 2200), for: .mediaBox)
                    if let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        text = recognizedText(in: image)
                        picturePages += 1
                    }
                }
                pageTexts.append(text)
            }
            return ReadResult(pageTexts: pageTexts, pagesReadFromPictures: picturePages)

        case .image:
            guard let image = NSImage(contentsOf: fileURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw ReadError.unreadable(name)
            }
            return ReadResult(pageTexts: [recognizedText(in: image)], pagesReadFromPictures: 1)

        case .slides:
            guard fileURL.pathExtension.lowercased() == "pptx" else { throw ReadError.unsupported(name) }
            return ReadResult(pageTexts: try slideTexts(ofPowerPoint: fileURL), pagesReadFromPictures: 0)

        case .document:
            if ["pages"].contains(fileURL.pathExtension.lowercased()) { throw ReadError.unsupported(name) }
            guard let attributed = try? NSAttributedString(url: fileURL, options: [:], documentAttributes: nil) else {
                throw ReadError.unreadable(name)
            }
            return ReadResult(pageTexts: [attributed.string], pagesReadFromPictures: 0)

        case .text, .note:
            guard let data = try? Data(contentsOf: fileURL) else { throw ReadError.unreadable(name) }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return ReadResult(pageTexts: [text], pagesReadFromPictures: 0)
        }
    }

    /// Text in a picture, using Apple's on-device text recognition.
    static func recognizedText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let observations = request.results else { return "" }
        // Lines come back top to bottom; join them into paragraphs where the gap is small.
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// A .pptx is a zip of XML files; each slide's words sit in <a:t> elements. Read with the
    /// system's own unzip tool, nothing installed.
    static func slideTexts(ofPowerPoint fileURL: URL) throws -> [String] {
        let listing = runUnzip(["-Z1", fileURL.path])
        let slideNames = listing.components(separatedBy: .newlines)
            .filter { $0.range(of: #"^ppt/slides/slide\d+\.xml$"#, options: .regularExpression) != nil }
            .sorted { slideNumber($0) < slideNumber($1) }
        guard !slideNames.isEmpty else { throw ReadError.unreadable(fileURL.lastPathComponent) }
        return slideNames.map { slideName in
            let xml = runUnzip(["-p", fileURL.path, slideName])
            guard let regex = try? NSRegularExpression(pattern: #"<a:t>([^<]*)</a:t>"#) else { return "" }
            let pieces = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
                Range(match.range(at: 1), in: xml).map { String(xml[$0]) }
            }
            return pieces.joined(separator: "\n")
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
        }
    }

    private static func slideNumber(_ name: String) -> Int {
        Int(name.filter(\.isNumber)) ?? 0
    }

    private static func runUnzip(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Meaning vectors (Apple's on-device sentence model)

nonisolated enum StudyMeaning {
    /// Nil when this Mac has no English sentence model; search then uses words alone.
    static func vectors(for texts: [String]) -> [[Float]] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return texts.map { _ in [] } }
        return texts.map { text in
            // The model reads the start of a passage best; long text adds time, not meaning.
            let input = String(text.prefix(700))
            return embedding.vector(for: input).map { $0.map(Float.init) } ?? []
        }
    }
}

// MARK: - The library

@MainActor
final class StudyLibraryStore: ObservableObject {

    static let shared = StudyLibraryStore()

    struct ImportItem: Identifiable, Equatable {
        let id = UUID()
        let fileName: String
        var status: Status
        enum Status: Equatable { case reading, failed(String) }
    }

    @Published private(set) var materials: [StudyMaterial] = []
    @Published private(set) var importItems: [ImportItem] = []
    @Published private(set) var isLoaded = false

    private var passagesByMaterial: [UUID: [StudyPassage]] = [:]
    private var searchIndex = StudyLibrary.SearchIndex(passages: [])

    static let notesSubject = "My notes"

    var subjects: [String] {
        Array(Set(materials.map(\.subject))).sorted { lhs, rhs in
            if lhs == Self.notesSubject { return false }
            if rhs == Self.notesSubject { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    var totalPassageCount: Int { materials.reduce(0) { $0 + $1.passageCount } }

    // MARK: Places on disk

    nonisolated private static var baseDirectory: URL {
        #if DEBUG
        // Test runs keep their library apart from the real one.
        if let testDirectory = UserDefaults.standard.string(forKey: "ThambiDebugLibraryDirectory") {
            return URL(fileURLWithPath: testDirectory, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Thambi", isDirectory: true)
    }
    nonisolated static var libraryDirectory: URL { baseDirectory.appendingPathComponent("Library", isDirectory: true) }
    nonisolated static var notesDirectory: URL { baseDirectory.appendingPathComponent("Notes", isDirectory: true) }
    nonisolated private static var materialsFile: URL { libraryDirectory.appendingPathComponent("materials.json") }
    nonisolated private static func passagesFile(for materialID: UUID) -> URL {
        libraryDirectory.appendingPathComponent("passages/\(materialID.uuidString).json")
    }

    // MARK: Loading

    func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> ([StudyMaterial], [UUID: [StudyPassage]]) in
                guard let data = try? Data(contentsOf: Self.materialsFile),
                      let materials = try? JSONDecoder().decode([StudyMaterial].self, from: data) else { return ([], [:]) }
                var passages: [UUID: [StudyPassage]] = [:]
                var kept: [StudyMaterial] = []
                for material in materials {
                    guard let passageData = try? Data(contentsOf: Self.passagesFile(for: material.id)),
                          let decoded = try? JSONDecoder().decode([StudyPassage].self, from: passageData) else { continue }
                    passages[material.id] = decoded
                    kept.append(material)
                }
                return (kept, passages)
            }.value
            materials = loaded.0
            passagesByMaterial = loaded.1
            await rebuildIndex()
            print("📚 Library: \(materials.count) materials, \(totalPassageCount) passages")
        }
    }

    private func rebuildIndex() async {
        subjectMemoryCache.removeAll()
        let allPassages = materials.flatMap { passagesByMaterial[$0.id] ?? [] }
        searchIndex = await Task.detached(priority: .userInitiated) { StudyLibrary.SearchIndex(passages: allPassages) }.value
    }

    private func saveMaterialsList() {
        let snapshot = materials
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: Self.libraryDirectory, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: Self.materialsFile, options: .atomic) }
        }
    }

    // MARK: Adding

    /// Adds files (folders are opened, and their name becomes the subject unless one is given).
    func add(_ urls: [URL], subject: String?) {
        loadIfNeeded()
        var work: [(url: URL, subject: String)] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let folderSubject = subject ?? StudyLibrary.cleanedSubjectName(url.lastPathComponent)
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                while let fileURL = enumerator?.nextObject() as? URL {
                    if StudyLibrary.kind(forFileExtension: fileURL.pathExtension) != nil { work.append((fileURL, folderSubject)) }
                }
            } else {
                work.append((url, subject ?? "General"))
            }
        }
        for item in work.prefix(200) {
            addFile(item.url, subject: item.subject, kind: nil)
        }
    }

    @discardableResult
    private func addFile(_ fileURL: URL, subject: String, kind requestedKind: StudyMaterial.Kind?) -> UUID? {
        guard let kind = requestedKind ?? StudyLibrary.kind(forFileExtension: fileURL.pathExtension) else {
            importItems.append(ImportItem(fileName: fileURL.lastPathComponent, status: .failed("This kind of file can't be read.")))
            return nil
        }
        let importItem = ImportItem(fileName: fileURL.lastPathComponent, status: .reading)
        importItems.append(importItem)
        // Adding the same file again replaces it.
        let replacedID = materials.first(where: { $0.sourcePath == fileURL.path })?.id
        let materialID = replacedID ?? UUID()

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<(StudyMaterial, [StudyPassage]), Error> in
                do {
                    let readResult = try StudyMaterialReader.read(fileURL, kind: kind)
                    var passages: [StudyPassage] = []
                    for (pageIndex, pageText) in readResult.pageTexts.enumerated() {
                        let hasPages = readResult.pageTexts.count > 1 || kind == .pdf
                        for passageText in StudyLibrary.passages(fromPageText: pageText) {
                            passages.append(StudyPassage(materialID: materialID, page: hasPages ? pageIndex + 1 : nil, text: passageText))
                            if passages.count >= StudyLibrary.maximumPassagesPerMaterial { break }
                        }
                    }
                    guard !passages.isEmpty else { throw StudyMaterialReader.ReadError.empty(fileURL.lastPathComponent) }
                    let vectors = StudyMeaning.vectors(for: passages.map(\.text))
                    for index in passages.indices { passages[index].meaning = vectors[index] }

                    let material = StudyMaterial(
                        id: materialID,
                        title: StudyLibrary.displayTitle(forFileName: fileURL.lastPathComponent),
                        subject: subject, kind: kind, sourcePath: fileURL.path,
                        pageCount: readResult.pageTexts.count, passageCount: passages.count,
                        characterCount: passages.reduce(0) { $0 + $1.text.count }, addedAt: Date(),
                        pagesReadFromPictures: readResult.pagesReadFromPictures
                    )
                    try FileManager.default.createDirectory(at: Self.passagesFile(for: materialID).deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(passages).write(to: Self.passagesFile(for: materialID), options: .atomic)
                    return .success((material, passages))
                } catch {
                    return .failure(error)
                }
            }.value

            switch outcome {
            case .success(let (material, passages)):
                importItems.removeAll { $0.id == importItem.id }
                materials.removeAll { $0.id == material.id }
                materials.insert(material, at: 0)
                passagesByMaterial[material.id] = passages
                saveMaterialsList()
                await rebuildIndex()
                print("📚 Added \(material.kind.rawValue): \(material.pageCount) pages, \(material.passageCount) passages")
            case .failure(let error):
                if let index = importItems.firstIndex(where: { $0.id == importItem.id }) {
                    importItems[index].status = .failed(error.localizedDescription)
                }
            }
        }
        return materialID
    }

    func dismissImportItem(_ item: ImportItem) {
        importItems.removeAll { $0.id == item.id }
    }

    func remove(_ material: StudyMaterial) {
        materials.removeAll { $0.id == material.id }
        passagesByMaterial[material.id] = nil
        try? FileManager.default.removeItem(at: Self.passagesFile(for: material.id))
        if material.kind == .note { try? FileManager.default.removeItem(atPath: material.sourcePath) }
        saveMaterialsList()
        Task { await rebuildIndex() }
    }

    func move(_ material: StudyMaterial, toSubject subject: String) {
        guard let index = materials.firstIndex(where: { $0.id == material.id }) else { return }
        materials[index].subject = StudyLibrary.cleanedSubjectName(subject)
        saveMaterialsList()
        Task { await rebuildIndex() }
    }

    func revealOriginal(_ material: StudyMaterial) {
        let url = URL(fileURLWithPath: material.sourcePath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func openOriginal(_ material: StudyMaterial) {
        let url = URL(fileURLWithPath: material.sourcePath)
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }

    // MARK: Subjects kept in memory

    /// Subjects the student chose to keep in memory. Questions about one of them carry the whole
    /// subject (up to about 15,000 tokens) in a block cached for an hour.
    @Published private(set) var memorySubjects: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "studyMemorySubjects") ?? [])
    private var subjectMemoryCache: [String: (text: String, isComplete: Bool)] = [:]

    func isKeptInMemory(_ subject: String) -> Bool { memorySubjects.contains(subject) }

    func setKeptInMemory(_ subject: String, _ isKept: Bool) {
        if isKept { memorySubjects.insert(subject) } else { memorySubjects.remove(subject) }
        UserDefaults.standard.set(Array(memorySubjects).sorted(), forKey: "studyMemorySubjects")
    }

    /// The cached block for a subject kept in memory, or nil when it isn't kept.
    func subjectMemory(for subject: String?) -> (text: String, isComplete: Bool)? {
        guard let subject, memorySubjects.contains(subject) else { return nil }
        if let cached = subjectMemoryCache[subject] { return cached }
        guard let built = StudyLibrary.subjectMemory(subject: subject, materials: materials, passages: passagesByMaterial) else { return nil }
        subjectMemoryCache[subject] = built
        return built
    }

    /// Which kept subject a question belongs to: the chosen scope, or else the subject of the
    /// best passage found for it.
    func memorySubject(scope: String?, sources: [StudySource]) -> String? {
        if let scope { return memorySubjects.contains(scope) ? scope : nil }
        guard let best = sources.first, memorySubjects.contains(best.subject) else { return nil }
        return best.subject
    }

    // MARK: Notes

    /// Saves a note as a Markdown file and adds it to the library so later questions can find it.
    /// Only called in Write mode, or when the student saves their own note.
    @discardableResult
    func saveNote(title: String, markdown: String, replacing existingPath: String? = nil) -> URL? {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: Self.notesDirectory, withIntermediateDirectories: true)
        let fileURL: URL
        if let existingPath {
            fileURL = URL(fileURLWithPath: existingPath)
        } else {
            let safeTitle = title.replacingOccurrences(of: #"[/:\\?%*|"<>]"#, with: "-", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces).prefix(60)
            var candidate = Self.notesDirectory.appendingPathComponent("\(safeTitle.isEmpty ? "Note" : String(safeTitle)).md")
            var counter = 2
            while fileManager.fileExists(atPath: candidate.path) {
                candidate = Self.notesDirectory.appendingPathComponent("\(safeTitle) \(counter).md")
                counter += 1
            }
            fileURL = candidate
        }
        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        addFile(fileURL, subject: Self.notesSubject, kind: .note)
        return fileURL
    }

    func noteText(for material: StudyMaterial) -> String {
        (try? String(contentsOfFile: material.sourcePath, encoding: .utf8)) ?? ""
    }

    var notes: [StudyMaterial] { materials.filter { $0.kind == .note } }

    // MARK: Searching

    /// The best passages for a question, numbered as sources. Free: runs on this Mac.
    func sources(for question: String, subject: String? = nil, limit: Int = 6) async -> (sources: [StudySource], isRelevant: Bool) {
        let index = searchIndex
        guard !index.isEmpty else { return ([], false) }
        let allowed: Set<UUID>? = subject.map { chosen in Set(materials.filter { $0.subject == chosen }.map(\.id)) }
        let materialsByID = Dictionary(uniqueKeysWithValues: materials.map { ($0.id, $0) })
        return await Task.detached(priority: .userInitiated) {
            let questionMeaning = StudyMeaning.vectors(for: [question]).first ?? []
            let matches = StudyLibrary.search(question, questionMeaning: questionMeaning, in: index, allowedMaterials: allowed, limit: limit)
            let sources = StudyLibrary.sources(from: matches, in: index, materials: materialsByID)
            return (sources, StudyLibrary.matchesAreRelevant(matches))
        }.value
    }
}
