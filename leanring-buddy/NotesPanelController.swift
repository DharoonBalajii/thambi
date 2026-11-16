//
//  NotesPanelController.swift
//  leanring-buddy
//
//  The notes box: a solid, movable, resizable floating window (top-left by default) that
//  shows the summary / key points Thambi wrote, so you can copy them into your own notes.
//
//  • Solid box, no window chrome: white text on black, or black text on white.
//  • Movable: drag it anywhere. Resizable: drag any edge. Position and size are remembered.
//  • Colours: Auto (white-on-black over dark slides, black-on-white over light ones, judged from
//    Thambi's screenshot), or forced White / Black with the toggle button.
//  • Floats above your slides without taking keyboard focus; never appears in Thambi's own
//    screenshots (the capture excludes Thambi's windows).
//

import AppKit
import Combine
import SwiftUI

enum NotesTextStyle: String, CaseIterable {
    case automatic, white, black

    var label: String {
        switch self {
        case .automatic: return "Auto"
        case .white: return "White"
        case .black: return "Black"
        }
    }
}

@MainActor
final class NotesPanelController: ObservableObject {
    @Published private(set) var markdown: String = ""
    @Published private(set) var textStyle: NotesTextStyle =
        NotesTextStyle(rawValue: UserDefaults.standard.string(forKey: "notesTextStyle") ?? "") ?? .automatic
    /// What Auto picked from the screenshot (true = white text over a dark background).
    @Published private(set) var automaticPrefersWhiteText = true
    @Published private(set) var justCopied = false

    var usesWhiteText: Bool {
        switch textStyle {
        case .automatic: return automaticPrefersWhiteText
        case .white: return true
        case .black: return false
        }
    }

    private var panel: NotesPanel?
    private static let defaultSize = CGSize(width: 380, height: 440)
    private static let frameAutosaveName = "ThambiNotesPanel"

    // MARK: - Showing

    /// Shows (or updates) the notes box with new notes. The screenshots are used only to choose
    /// a readable text colour for the area behind the box.
    func show(markdown newMarkdown: String, screenCaptures: [CompanionScreenCapture]) {
        markdown = newMarkdown
        let notesPanel = panel ?? makePanel()
        panel = notesPanel

        if !notesPanel.isVisible && !notesPanel.setFrameUsingName(Self.frameAutosaveName) {
            notesPanel.setFrame(Self.defaultFrameTopLeftOfCursorScreen(), display: false)
        }
        if let brightness = Self.averageBrightness(behind: notesPanel.frame, in: screenCaptures) {
            automaticPrefersWhiteText = brightness < 0.55
        }
        notesPanel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }

    func cycleTextStyle() {
        let allStyles = NotesTextStyle.allCases
        let nextIndex = ((allStyles.firstIndex(of: textStyle) ?? 0) + 1) % allStyles.count
        textStyle = allStyles[nextIndex]
        UserDefaults.standard.set(textStyle.rawValue, forKey: "notesTextStyle")
    }

    func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(NotesMarkdown.plainText(from: markdown), forType: .string)
        justCopied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            justCopied = false
        }
    }

    // MARK: - Window

    private func makePanel() -> NotesPanel {
        let notesPanel = NotesPanel(
            contentRect: CGRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        notesPanel.titleVisibility = .hidden
        notesPanel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            notesPanel.standardWindowButton(button)?.isHidden = true
        }
        notesPanel.isOpaque = false
        notesPanel.backgroundColor = .clear
        notesPanel.hasShadow = true
        notesPanel.isMovableByWindowBackground = true
        notesPanel.level = .floating
        notesPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        notesPanel.hidesOnDeactivate = false
        notesPanel.becomesKeyOnlyIfNeeded = true
        notesPanel.isReleasedWhenClosed = false
        notesPanel.minSize = CGSize(width: 240, height: 160)
        notesPanel.setFrameAutosaveName(Self.frameAutosaveName)

        let hostingView = NotesHostingView(rootView: NotesPanelView(controller: self))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        notesPanel.contentView = hostingView
        return notesPanel
    }

    /// Top-left corner of the screen the mouse is on, below the menu bar.
    private static func defaultFrameTopLeftOfCursorScreen() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGRect(
            x: visible.minX + 20,
            y: visible.maxY - defaultSize.height - 20,
            width: defaultSize.width,
            height: defaultSize.height
        )
    }

    // MARK: - Auto text colour

    /// Average brightness (0 = black, 1 = white) of the part of the screenshot that sits behind
    /// `panelFrame` (global AppKit coordinates). Nil if no screenshot covers it.
    static func averageBrightness(behind panelFrame: CGRect, in screenCaptures: [CompanionScreenCapture]) -> Double? {
        guard let capture = screenCaptures.max(by: {
            $0.displayFrame.intersection(panelFrame).area < $1.displayFrame.intersection(panelFrame).area
        }), capture.displayFrame.intersects(panelFrame),
              let source = CGImageSourceCreateWithData(capture.imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let visiblePart = panelFrame.intersection(capture.displayFrame)
        let pixelsPerPointX = CGFloat(image.width) / capture.displayFrame.width
        let pixelsPerPointY = CGFloat(image.height) / capture.displayFrame.height
        // Screenshot pixels have a top-left origin; AppKit screen coordinates have a bottom-left one.
        let cropRect = CGRect(
            x: (visiblePart.minX - capture.displayFrame.minX) * pixelsPerPointX,
            y: (capture.displayFrame.maxY - visiblePart.maxY) * pixelsPerPointY,
            width: visiblePart.width * pixelsPerPointX,
            height: visiblePart.height * pixelsPerPointY
        ).integral
        guard let cropped = image.cropping(to: cropRect) else { return nil }

        var pixel: [UInt8] = [0]
        let drew = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 1, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drew ? Double(pixel[0]) / 255 : nil
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

/// A floating panel that can take clicks (buttons, scrolling) without activating Thambi.
final class NotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a button work even when the panel isn't focused.
/// (Deliberately not generic: a generic NSHostingView subclass crashes the Swift 6.3 optimizer in Release.)
final class NotesHostingView: NSHostingView<NotesPanelView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - View

struct NotesPanelView: View {
    @ObservedObject var controller: NotesPanelController

    var body: some View {
        let isWhite = controller.usesWhiteText
        let textColor: Color = isWhite ? .white : .black
        // Solid box: white text sits on black, black text sits on white.
        let backgroundColor: Color = isWhite ? .black : .white

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "note.text")
                Text("Notes").font(.system(size: 13, weight: .semibold))
                Spacer()
                NotesHeaderButton(systemImage: "textformat", label: controller.textStyle.label, color: textColor) {
                    controller.cycleTextStyle()
                }
                .help("Text colour: Auto picks white or black from what's behind the box")
                NotesHeaderButton(systemImage: controller.justCopied ? "checkmark" : "doc.on.doc",
                                  label: controller.justCopied ? "Copied" : "Copy", color: textColor) {
                    controller.copyToPasteboard()
                }
                .help("Copy the notes as plain text")
                NotesHeaderButton(systemImage: "xmark", label: nil, color: textColor) {
                    controller.close()
                }
                .help("Close the notes box")
            }
            .foregroundColor(textColor)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Rectangle().fill(textColor.opacity(0.18)).frame(height: 0.5).padding(.horizontal, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(NotesMarkdown.lines(from: controller.markdown).enumerated()), id: \.offset) { _, line in
                        NotesLineView(line: line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .foregroundColor(textColor)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(textColor.opacity(0.22), lineWidth: 0.8)
        )
        .frame(minWidth: 240, minHeight: 160)
    }
}

private struct NotesHeaderButton: View {
    let systemImage: String
    let label: String?
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                if let label { Text(label).font(.system(size: 11, weight: .medium)) }
            }
            .foregroundColor(color.opacity(0.9))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

struct NotesLineView: View {
    let line: NotesMarkdown.Line

    var body: some View {
        switch line.kind {
        case .heading:
            Text(line.text).font(.system(size: 15, weight: .bold)).padding(.top, 2)
        case .bullet(let level):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(level == 0 ? "•" : "◦").font(.system(size: 13, weight: .bold))
                Text(line.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(level) * 16)
        case .numbered(let number, let level):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                Text(line.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(level) * 16)
        case .paragraph:
            Text(line.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        case .table(let hasHeader):
            NotesTableView(rows: line.tableRows, hasHeader: hasHeader)
        case .spacer:
            Spacer().frame(height: 4)
        }
    }
}

/// A small comparison table: bold header row, thin rules between rows, in the box's own text colour.
struct NotesTableView: View {
    let rows: [[AttributedString]]
    let hasHeader: Bool

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                let isHeaderRow = hasHeader && rowIndex == 0
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: 12.5, weight: isHeaderRow ? .bold : .regular))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if rowIndex < rows.count - 1 {
                    Rectangle()
                        .frame(height: isHeaderRow ? 1 : 0.5)
                        .opacity(isHeaderRow ? 0.55 : 0.2)
                        .gridCellUnsizedAxes(.horizontal)
                }
            }
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(lineWidth: 0.8).opacity(0.3))
        .padding(.vertical, 2)
    }
}
