//
//  SourcePageView.swift
//  leanring-buddy
//
//  Opens a cited source where it is: a PDF at its page with the passage highlighted, a photo of
//  notes beside the text read from it, or the passage itself for notes and documents. Everything
//  is read from the file on this Mac.
//

import AppKit
import PDFKit
import SwiftUI

struct SourcePageSheet: View {
    let source: StudySource
    @ObservedObject var library: StudyLibraryStore
    let onClose: () -> Void

    @State private var foundPassage = true

    private var material: StudyMaterial? { library.materials.first { $0.id == source.materialID } }

    private var fileExists: Bool {
        guard let material else { return false }
        return FileManager.default.fileExists(atPath: material.sourcePath)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(source.number)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.Colors.cool)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(DS.Colors.coolSubtle))
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.placeLabel)
                        .font(DS.font(14, .semibold))
                        .foregroundColor(DS.Colors.textPrimary)
                        .lineLimit(1)
                    Text(statusLine)
                        .font(DS.font(12))
                        .foregroundColor(DS.Colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if let material, fileExists {
                    WindowButton(title: "Open original", systemImage: "arrow.up.forward.app") { library.openOriginal(material) }
                }
                WindowButton(title: "Done", prominence: .primary, action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            Rectangle().fill(DS.Colors.borderSubtle).frame(height: 1)
            content
        }
        .frame(width: 820, height: 640)
        .background(DS.Colors.background)
    }

    private var statusLine: String {
        guard let material else { return "This material was removed from your library." }
        if !fileExists { return "The original file has moved. Showing the passage Thambi kept." }
        if material.kind == .pdf { return foundPassage ? "The passage is highlighted." : "Showing the page. The passage was read from a picture, so it can't be highlighted." }
        return source.subject
    }

    @ViewBuilder
    private var content: some View {
        if let material, fileExists, material.kind == .pdf {
            PDFPageView(fileURL: URL(fileURLWithPath: material.sourcePath), pageNumber: source.page ?? 1, passage: source.text, foundPassage: $foundPassage)
        } else if let material, fileExists, material.kind == .image, let image = NSImage(contentsOfFile: material.sourcePath) {
            HStack(spacing: 0) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.Colors.well)
                    .accessibilityLabel("Photo of \(material.title)")
                Rectangle().fill(DS.Colors.borderSubtle).frame(width: 1)
                passageText.frame(width: 300)
            }
        } else {
            passageText
        }
    }

    private var passageText: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("What Thambi read")
                    .font(DS.font(12, .medium))
                    .foregroundColor(DS.Colors.textTertiary)
                Text(source.text)
                    .font(DS.font(14))
                    .foregroundColor(DS.Colors.textPrimary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.accentSubtle.opacity(0.55)))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(DS.Colors.accent).frame(width: 3)
                    }
            }
            .padding(18)
        }
    }
}

/// A PDF shown at one page, the passage selected in amber.
struct PDFPageView: NSViewRepresentable {
    let fileURL: URL
    let pageNumber: Int
    let passage: String
    @Binding var foundPassage: Bool

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = NSColor(DS.Colors.well)
        load(into: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {}

    private func load(into pdfView: PDFView) {
        guard let document = PDFDocument(url: fileURL) else { return }
        pdfView.document = document
        let pageIndex = max(0, min(document.pageCount - 1, pageNumber - 1))
        guard let page = document.page(at: pageIndex) else { return }
        let found: Bool
        if let pageText = page.string,
           let range = StudyLibrary.passageRange(of: passage, inPageText: pageText),
           let selection = page.selection(for: range) {
            selection.color = NSColor(DS.Colors.accent).withAlphaComponent(0.45)
            pdfView.highlightedSelections = [selection]
            found = true
            DispatchQueue.main.async { pdfView.go(to: selection) }
        } else {
            found = false
            DispatchQueue.main.async { pdfView.go(to: page) }
        }
        DispatchQueue.main.async { foundPassage = found }
    }
}
