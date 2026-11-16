//
//  CaptionsPanelController.swift
//  leanring-buddy
//
//  Captions: the sentence Thambi is saying, shown as text at the bottom of the screen while the
//  voice says it. Useful in a library, in class, or with the sound low.
//
//  • Solid black bar with white text, bottom-centre of the screen the mouse is on.
//  • Never takes clicks or keyboard focus: everything underneath stays usable.
//  • Never appears in Thambi's own screenshots (the capture excludes Thambi's windows).
//  • Off by default; switched on in the menu bar panel.
//

import AppKit

@MainActor
final class CaptionsPanelController {
    private var panel: NSPanel?
    private var captionLabel: NSTextField?

    private static let captionFont = NSFont.systemFont(ofSize: 17, weight: .medium)
    private static let maximumCaptionWidth: CGFloat = 760
    private static let horizontalPadding: CGFloat = 18
    private static let verticalPadding: CGFloat = 11
    private static let distanceFromScreenBottom: CGFloat = 56

    /// Shows (or replaces) the caption.
    func show(text: String) {
        let captionText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !captionText.isEmpty else {
            hide()
            return
        }
        let captionsPanel = panel ?? makePanel()
        panel = captionsPanel
        captionLabel?.stringValue = captionText

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        let textSize = Self.captionTextSize(for: captionText, screenWidth: visibleFrame.width)
        let panelSize = CGSize(
            width: textSize.width + Self.horizontalPadding * 2,
            height: textSize.height + Self.verticalPadding * 2
        )
        captionsPanel.setFrame(
            CGRect(
                x: visibleFrame.midX - panelSize.width / 2,
                y: visibleFrame.minY + Self.distanceFromScreenBottom,
                width: panelSize.width,
                height: panelSize.height
            ),
            display: true
        )
        captionLabel?.frame = CGRect(
            x: Self.horizontalPadding, y: Self.verticalPadding,
            width: textSize.width, height: textSize.height
        )
        captionsPanel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// The size the caption text needs, wrapped to at most `maximumCaptionWidth` (or the screen).
    static func captionTextSize(for captionText: String, screenWidth: CGFloat) -> CGSize {
        let widthLimit = max(200, min(maximumCaptionWidth, screenWidth - 120))
        let bounds = NSAttributedString(string: captionText, attributes: [.font: captionFont]).boundingRect(
            with: CGSize(width: widthLimit, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(width: min(widthLimit, ceil(bounds.width) + 4), height: ceil(bounds.height) + 2)
    }

    private func makePanel() -> NSPanel {
        let captionsPanel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        captionsPanel.isOpaque = false
        captionsPanel.backgroundColor = .clear
        captionsPanel.hasShadow = true
        captionsPanel.level = .statusBar
        captionsPanel.ignoresMouseEvents = true
        captionsPanel.hidesOnDeactivate = false
        captionsPanel.isReleasedWhenClosed = false
        captionsPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let backgroundView = NSView()
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.black.cgColor
        backgroundView.layer?.cornerRadius = 10
        backgroundView.layer?.masksToBounds = true

        let label = NSTextField(wrappingLabelWithString: "")
        label.font = Self.captionFont
        label.textColor = .white
        label.alignment = .center
        label.isSelectable = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 0
        backgroundView.addSubview(label)

        captionsPanel.contentView = backgroundView
        captionLabel = label
        return captionsPanel
    }
}
