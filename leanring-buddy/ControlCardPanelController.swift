//
//  ControlCardPanelController.swift
//  leanring-buddy
//
//  The small card shown while Thambi operates the Mac for you. It says what the next step is,
//  why, and waits for Return (or the Allow button). Escape, or Stop, ends the task.
//
//  It floats above other apps without taking the keyboard, and moves out of the way when the
//  thing about to be clicked is underneath it.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class ControlCardPanelController {

    private let agent: ComputerControlAgent
    private let onStop: () -> Void
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ControlCardView>?
    private var phaseCancellable: AnyCancellable?
    private var screenFrame: CGRect?
    private var isAtBottom = false
    /// True from show() until the task's card would normally go away.
    private var isSessionActive = false
    /// False = quiet mode: the card stays away unless a step is waiting for your go-ahead.
    var showsEveryStep = true {
        didSet { if isSessionActive { updateVisibility(for: agent.phase) } }
    }

    static let cardWidth: CGFloat = 400

    init(agent: ComputerControlAgent, onStop: @escaping () -> Void) {
        self.agent = agent
        self.onStop = onStop
        phaseCancellable = agent.$phase
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self, self.isSessionActive else { return }
                if phase == .idle {
                    self.hide()
                } else {
                    self.updateVisibility(for: phase)
                }
            }
    }

    func show() {
        if panel == nil { createPanel() }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        screenFrame = screen?.visibleFrame
        isAtBottom = false
        isSessionActive = true
        updateVisibility(for: agent.phase)
    }

    func hide() {
        isSessionActive = false
        panel?.orderOut(nil)
    }

    private func updateVisibility(for phase: ComputerControlAgent.Phase) {
        var isWaitingForYou = false
        if case .waitingForApproval = phase { isWaitingForYou = true }
        if showsEveryStep || isWaitingForYou {
            layout()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    /// Moves the card to the other end of the screen when the spot about to be clicked is under it.
    func keepClear(of appKitPoint: CGPoint) {
        guard let panel, panel.isVisible else { return }
        guard panel.frame.insetBy(dx: -24, dy: -24).contains(appKitPoint) else { return }
        isAtBottom.toggle()
        layout()
    }

    /// The card's frame on screen, for the agent's "is one of my windows in the way" check.
    var frame: CGRect? { panel?.isVisible == true ? panel?.frame : nil }

    private func createPanel() {
        let hostingView = NSHostingView(rootView: ControlCardView(agent: agent, onStop: onStop))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.cardWidth, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel
    }

    private func layout() {
        guard let panel, let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let height = max(72, hostingView.fittingSize.height)
        let area = screenFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let originY = isAtBottom ? area.minY + 28 : area.maxY - height - 10
        panel.setFrame(
            NSRect(x: area.midX - Self.cardWidth / 2, y: originY, width: Self.cardWidth, height: height),
            display: true
        )
    }
}

// MARK: - The card

struct ControlCardView: View {
    @ObservedObject var agent: ComputerControlAgent
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ThambiMascot(mood: mood, size: 34)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Colors.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundColor(DS.Colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isRisky {
                        Text("Check this one before you allow it.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.Colors.destructiveText)
                    }
                }
                Spacer(minLength: 0)
            }

            if agent.isRunning {
                HStack(spacing: 8) {
                    Text(stepText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DS.Colors.textTertiary)
                    Spacer(minLength: 8)
                    ControlCardButton(title: "Stop", keyHint: "esc", isPrimary: false, action: onStop)
                    if isWaiting {
                        ControlCardButton(title: "Allow", keyHint: "return", isPrimary: true) { agent.approve() }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: ControlCardPanelController.cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .fill(DS.Colors.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thambi is working on: \(agent.task)")
    }

    private var isWaiting: Bool {
        if case .waitingForApproval = agent.phase { return true }
        return false
    }

    private var isRisky: Bool {
        if case .waitingForApproval(_, _, _, let isRisky) = agent.phase { return isRisky }
        return false
    }

    private var borderColor: Color {
        if isRisky { return DS.Colors.destructive }
        return isWaiting ? DS.Colors.accent : DS.Colors.borderStrong
    }

    private var mood: ThambiMascot.Mood {
        switch agent.phase {
        case .idle: return .idle
        case .looking: return .thinking
        case .waitingForApproval: return .asking
        case .acting: return .acting
        case .finished(_, let succeeded): return succeeded ? .happy : .sorry
        }
    }

    private var headline: String {
        switch agent.phase {
        case .idle: return "Ready"
        case .looking: return "Looking at your screen"
        case .waitingForApproval(_, let description, _, _): return description + "?"
        case .acting(_, let description): return description
        case .finished(let message, _): return message.prefix(1).uppercased() + message.dropFirst()
        }
    }

    private var detail: String? {
        switch agent.phase {
        case .waitingForApproval(_, _, let why, _):
            return why.isEmpty ? nil : why.prefix(1).uppercased() + why.dropFirst()
        case .looking:
            return agent.task.components(separatedBy: "\n").first
        default:
            return nil
        }
    }

    private var stepText: String {
        let step: Int
        switch agent.phase {
        case .looking(let number), .waitingForApproval(let number, _, _, _), .acting(let number, _): step = number
        default: step = 0
        }
        return "Step \(step) of \(ComputerControl.maximumSteps)"
    }
}

/// A card button with its key written beside it, so the keyboard way is always in view.
private struct ControlCardButton: View {
    let title: String
    let keyHint: String
    let isPrimary: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(keyHint)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isPrimary ? DS.Colors.textOnAccent.opacity(0.14) : DS.Colors.surface3)
                    )
            }
            .foregroundColor(isPrimary ? DS.Colors.textOnAccent : DS.Colors.textPrimary)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                    .strokeBorder(isPrimary ? Color.clear : DS.Colors.borderStrong, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .accessibilityLabel("\(title), \(keyHint) key")
    }

    private var fillColor: Color {
        if isPrimary { return isHovered ? DS.Colors.accentHover : DS.Colors.accent }
        return isHovered ? DS.Colors.surface3 : DS.Colors.surface2
    }
}
