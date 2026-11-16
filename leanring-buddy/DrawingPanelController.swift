//
//  DrawingPanelController.swift
//  leanring-buddy
//
//  The drawing box: shows the picture Thambi described (see ThambiDrawing.swift), drawn here on
//  the Mac. Flow charts, message sequences and plots are drawn with SwiftUI; 3D pictures are
//  built from simple shapes with SceneKit and can be turned with the mouse.
//
//  Copy puts the picture on the clipboard as an image; Save writes a PNG.
//

import AppKit
import Combine
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DrawingPanelController: ObservableObject {
    @Published private(set) var drawing: ThambiDrawing.Drawing?
    @Published private(set) var justCopied = false
    /// How many parts of the drawing are showing. Nil means all of it (the usual case);
    /// a number means it is being built up in step with the voice.
    @Published private(set) var visibleSteps: Int?

    private var panel: DrawingPanel?
    private var copiedResetTask: Task<Void, Never>?

    private static let defaultSize = CGSize(width: 520, height: 440)
    private static let frameAutosaveName = "ThambiDrawingPanelFrame"

    /// `buildsUp` starts the drawing empty; each `revealNextStep()` then adds its next part.
    func show(_ newDrawing: ThambiDrawing.Drawing, buildsUp: Bool = false) {
        drawing = newDrawing
        visibleSteps = (buildsUp && newDrawing.stepCount > 1) ? 0 : nil
        justCopied = false
        if panel == nil {
            let newPanel = makePanel()
            if !newPanel.setFrameUsingName(Self.frameAutosaveName) {
                newPanel.setFrame(Self.defaultFrameTopRightOfCursorScreen(), display: false)
            }
            panel = newPanel
        }
        panel?.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }

    /// The voice reached the sentence about the next part.
    func revealNextStep() {
        guard let drawing, let shown = visibleSteps else { return }
        let next = shown + 1
        let change = { self.visibleSteps = next >= drawing.stepCount ? nil : next }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            change()
        } else {
            withAnimation(.easeOut(duration: 0.3), change)
        }
    }

    /// Speech ended, was stopped, or had fewer [STEP] tags than the drawing has parts.
    func revealAll() {
        guard visibleSteps != nil else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            visibleSteps = nil
        } else {
            withAnimation(.easeOut(duration: 0.3)) { visibleSteps = nil }
        }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func copyToPasteboard() {
        guard let image = renderedImage() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        justCopied = true
        copiedResetTask?.cancel()
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            self?.justCopied = false
        }
    }

    func saveAsPNG() {
        guard let image = renderedImage(), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        let name = (drawing?.title.isEmpty == false ? drawing!.title : "Thambi drawing")
            .replacingOccurrences(of: #"[/:\\]"#, with: " ", options: .regularExpression)
        savePanel.nameFieldStringValue = name + ".png"
        NSApp.activate(ignoringOtherApps: true)
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? png.write(to: url)
        }
    }

    /// The picture as an image, for Copy, Save and tests.
    /// `partsShown` draws only that many parts (for tests of the build-up); nil draws everything.
    func renderedImage(partsShown: Int? = nil) -> NSImage? {
        guard let drawing else { return nil }
        switch drawing.content {
        case .scene, .model:
            return DrawingSceneBuilder.snapshot(of: drawing.content, size: CGSize(width: 1200, height: 900), partsShown: partsShown)
        default:
            let size = Drawing2DView.naturalSize(of: drawing)
            let renderer = ImageRenderer(content:
                Drawing2DCanvas(drawing: drawing, stepsEnd: partsShown ?? Int.max)
                    .frame(width: size.width, height: size.height)
                    .padding(16)
                    .background(DS.Colors.background)
            )
            renderer.scale = 2
            return renderer.nsImage
        }
    }

    private func makePanel() -> DrawingPanel {
        let drawingPanel = DrawingPanel(
            contentRect: CGRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        drawingPanel.titleVisibility = .hidden
        drawingPanel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            drawingPanel.standardWindowButton(button)?.isHidden = true
        }
        drawingPanel.isOpaque = false
        drawingPanel.backgroundColor = .clear
        drawingPanel.hasShadow = true
        drawingPanel.isMovableByWindowBackground = true
        drawingPanel.level = .floating
        drawingPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        drawingPanel.hidesOnDeactivate = false
        drawingPanel.becomesKeyOnlyIfNeeded = true
        drawingPanel.isReleasedWhenClosed = false
        drawingPanel.minSize = CGSize(width: 300, height: 240)
        drawingPanel.setFrameAutosaveName(Self.frameAutosaveName)

        let hostingView = DrawingHostingView(rootView: DrawingPanelView(controller: self))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        drawingPanel.contentView = hostingView
        return drawingPanel
    }

    /// Top-right corner of the screen the mouse is on, so it sits clear of the notes box (top-left).
    private static func defaultFrameTopRightOfCursorScreen() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let area = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        return CGRect(
            x: area.maxX - defaultSize.width - 24, y: area.maxY - defaultSize.height - 24,
            width: defaultSize.width, height: defaultSize.height
        )
    }
}

final class DrawingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// (Deliberately not generic: a generic NSHostingView subclass crashes the Swift 6.3 optimizer in Release.)
final class DrawingHostingView: NSHostingView<DrawingPanelView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - The box

struct DrawingPanelView: View {
    @ObservedObject var controller: DrawingPanelController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(controller.drawing?.title.isEmpty == false ? controller.drawing!.title : "Drawing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                DrawingHeaderButton(title: controller.justCopied ? "Copied" : "Copy") { controller.copyToPasteboard() }
                    .help("Copy the drawing as an image")
                DrawingHeaderButton(title: "Save") { controller.saveAsPNG() }
                    .help("Save the drawing as a PNG file")
                Button(action: { controller.close() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.Colors.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.surface2))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Close the drawing")
                .accessibilityLabel("Close drawing")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 9)

            Rectangle().fill(DS.Colors.borderSubtle).frame(height: 1)

            Group {
                if let drawing = controller.drawing {
                    switch drawing.content {
                    case .scene, .model:
                        Drawing3DView(content: drawing.content, visibleSteps: controller.visibleSteps, isMoving: !reduceMotion)
                            .accessibilityLabel("3D drawing: \(drawing.title). Drag to turn it.")
                    default:
                        Drawing2DView(drawing: drawing, visibleSteps: controller.visibleSteps)
                            .padding(14)
                            .accessibilityLabel("Drawing: \(drawing.title)")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous).fill(DS.Colors.background))
        .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous).strokeBorder(DS.Colors.borderStrong, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous))
        .frame(minWidth: 300, minHeight: 240)
    }
}

private struct DrawingHeaderButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.surface2))
                .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).strokeBorder(DS.Colors.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

// MARK: - 2D drawings

/// Fits the drawing into whatever space the box has, never enlarging it past its natural size.
struct Drawing2DView: View {
    let drawing: ThambiDrawing.Drawing
    /// Nil shows everything. A number shows that many parts, the newest fading in on top.
    var visibleSteps: Int? = nil

    var body: some View {
        let size = Self.naturalSize(of: drawing)
        GeometryReader { proxy in
            let scale = min(1.4, min(proxy.size.width / max(size.width, 1), proxy.size.height / max(size.height, 1)))
            ZStack {
                if let visibleSteps {
                    // Everything already settled, then the newest part on its own layer so it can fade in.
                    Drawing2DCanvas(drawing: drawing, firstStep: 0, stepsEnd: visibleSteps - 1, drawsScaffold: true)
                    if visibleSteps >= 1 {
                        Drawing2DCanvas(drawing: drawing, firstStep: visibleSteps - 1, stepsEnd: visibleSteps, drawsScaffold: false)
                            .id(visibleSteps)
                            .transition(.opacity)
                    }
                } else {
                    Drawing2DCanvas(drawing: drawing)
                }
            }
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    static func naturalSize(of drawing: ThambiDrawing.Drawing) -> CGSize {
        switch drawing.content {
        case .flow(let flow):
            let layout = ThambiDrawing.layout(flow)
            return CGSize(width: max(layout.width, 120), height: max(layout.height, 80))
        case .sequence(let sequence):
            return SequenceMetrics(sequence: sequence).size
        case .plot:
            return CGSize(width: 480, height: 320)
        case .scene, .model:
            return CGSize(width: 480, height: 360)
        }
    }
}

struct Drawing2DCanvas: View {
    let drawing: ThambiDrawing.Drawing
    /// Only parts numbered from `firstStep` up to (not including) `stepsEnd` are drawn.
    var firstStep = 0
    var stepsEnd = Int.max
    /// The fixed frame of a drawing (plot axes, the parties of a sequence). Drawn once, underneath.
    var drawsScaffold = true

    var body: some View {
        let range = firstStep..<max(firstStep, stepsEnd)
        let lastStep = drawing.stepCount - 1
        Canvas { context, size in
            switch drawing.content {
            case .flow(let flow): Self.draw(flow, in: &context, steps: range)
            case .sequence(let sequence): Self.draw(sequence, in: &context, steps: range, drawsScaffold: drawsScaffold)
            case .plot(let plot): Self.draw(plot, in: &context, size: size, steps: range, lastStep: lastStep, drawsScaffold: drawsScaffold)
            case .scene, .model: break
            }
        }
    }

    // MARK: Shared pieces

    private static func label(_ text: String, size: CGFloat = 12, weight: Font.Weight = .regular, color: Color = DS.Colors.textPrimary, isMeasured: Bool = false) -> Text {
        Text(text)
            .font(.system(size: size, weight: weight, design: isMeasured ? .monospaced : .default))
            .foregroundColor(color)
    }

    private static func arrowHead(at tip: CGPoint, from origin: CGPoint, length: CGFloat = 9) -> Path {
        let angle = atan2(tip.y - origin.y, tip.x - origin.x)
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - length * cos(angle - 0.42), y: tip.y - length * sin(angle - 0.42)))
        path.addLine(to: CGPoint(x: tip.x - length * cos(angle + 0.42), y: tip.y - length * sin(angle + 0.42)))
        path.closeSubpath()
        return path
    }

    /// A small label on a solid chip, so it stays readable where it crosses a line.
    private static func chip(_ text: String, at requestedPoint: CGPoint, in context: inout GraphicsContext, canvasWidth: CGFloat = .infinity) {
        guard !text.isEmpty else { return }
        let resolved = context.resolve(label(text, size: 11, color: DS.Colors.textSecondary))
        let textSize = resolved.measure(in: CGSize(width: 220, height: 60))
        // Keep the whole label inside the picture.
        let halfWidth = textSize.width / 2 + 7
        let point = CGPoint(x: min(max(requestedPoint.x, halfWidth), max(halfWidth, canvasWidth - halfWidth)), y: requestedPoint.y)
        let rect = CGRect(x: point.x - textSize.width / 2 - 5, y: point.y - textSize.height / 2 - 2, width: textSize.width + 10, height: textSize.height + 4)
        context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(DS.Colors.background))
        context.draw(resolved, at: point, anchor: .center)
    }

    // MARK: Flow chart

    /// Where the line from a box's centre toward `target` leaves the box.
    private static func borderPoint(of rect: CGRect, toward target: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - center.x, dy = target.y - center.y
        guard dx != 0 || dy != 0 else { return center }
        let scaleX = dx == 0 ? CGFloat.infinity : (rect.width / 2) / abs(dx)
        let scaleY = dy == 0 ? CGFloat.infinity : (rect.height / 2) / abs(dy)
        let scale = min(scaleX, scaleY)
        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    private static func draw(_ flow: ThambiDrawing.Flow, in context: inout GraphicsContext, steps: Range<Int>) {
        let layout = ThambiDrawing.layout(flow)
        func frame(_ id: String) -> CGRect? {
            layout.frames[id].map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        }
        // Two arrows between the same pair, one each way, are drawn side by side.
        let pairs = Set(flow.edges.map { $0.from + ">" + $0.to })

        for edge in flow.edges where steps.contains(ThambiDrawing.effectiveStep(of: edge, in: flow)) {
            guard let fromRect = frame(edge.from), let toRect = frame(edge.to) else { continue }
            if layout.backwardEdges.contains(edge.from + ">" + edge.to) {
                // Loop back around the nearer outside edge of the chart.
                let goesAroundFarSide: Bool
                let start: CGPoint, end: CGPoint, firstControl: CGPoint, secondControl: CGPoint
                if flow.isHorizontal {
                    goesAroundFarSide = fromRect.midY + toRect.midY > CGFloat(layout.height)
                    let edgeY: CGFloat = goesAroundFarSide ? CGFloat(layout.height) - 10 : 10
                    start = CGPoint(x: fromRect.midX, y: goesAroundFarSide ? fromRect.maxY : fromRect.minY)
                    end = CGPoint(x: toRect.midX, y: goesAroundFarSide ? toRect.maxY : toRect.minY)
                    firstControl = CGPoint(x: start.x, y: edgeY)
                    secondControl = CGPoint(x: end.x, y: edgeY)
                } else {
                    goesAroundFarSide = fromRect.midX + toRect.midX > CGFloat(layout.width)
                    let edgeX: CGFloat = goesAroundFarSide ? CGFloat(layout.width) - 10 : 10
                    start = CGPoint(x: goesAroundFarSide ? fromRect.maxX : fromRect.minX, y: fromRect.midY)
                    end = CGPoint(x: goesAroundFarSide ? toRect.maxX : toRect.minX, y: toRect.midY)
                    firstControl = CGPoint(x: edgeX, y: start.y)
                    secondControl = CGPoint(x: edgeX, y: end.y)
                }
                var curve = Path()
                curve.move(to: start)
                curve.addCurve(to: end, control1: firstControl, control2: secondControl)
                context.stroke(curve, with: .color(DS.Colors.textTertiary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                if edge.hasArrow { context.fill(arrowHead(at: end, from: secondControl), with: .color(DS.Colors.textTertiary)) }
                chip(edge.label, at: CGPoint(x: (firstControl.x + secondControl.x) / 2 * 0.75 + (start.x + end.x) / 2 * 0.25,
                                             y: (firstControl.y + secondControl.y) / 2 * 0.75 + (start.y + end.y) / 2 * 0.25),
                     in: &context, canvasWidth: CGFloat(layout.width))
                continue
            }
            var start = borderPoint(of: fromRect, toward: CGPoint(x: toRect.midX, y: toRect.midY))
            var end = borderPoint(of: toRect, toward: CGPoint(x: fromRect.midX, y: fromRect.midY))
            if pairs.contains(edge.to + ">" + edge.from) {
                let angle = atan2(end.y - start.y, end.x - start.x) + .pi / 2
                let offset = CGPoint(x: 9 * cos(angle), y: 9 * sin(angle))
                start = CGPoint(x: start.x + offset.x, y: start.y + offset.y)
                end = CGPoint(x: end.x + offset.x, y: end.y + offset.y)
            }
            var line = Path()
            line.move(to: start)
            line.addLine(to: end)
            context.stroke(line, with: .color(DS.Colors.textTertiary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            if edge.hasArrow {
                context.fill(arrowHead(at: end, from: start), with: .color(DS.Colors.textTertiary))
            }
            chip(edge.label, at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), in: &context)
        }

        for node in flow.nodes where steps.contains(node.step) {
            guard let rect = frame(node.id) else { continue }
            let path: Path
            switch node.shape {
            case .box: path = Path(roundedRect: rect, cornerRadius: 8, style: .continuous)
            case .round: path = Path(roundedRect: rect, cornerRadius: rect.height / 2)
            case .diamond:
                var diamond = Path()
                diamond.move(to: CGPoint(x: rect.midX, y: rect.minY))
                diamond.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                diamond.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                diamond.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                diamond.closeSubpath()
                path = diamond
            }
            context.fill(path, with: .color(node.isHighlighted ? DS.Colors.accentSubtle : DS.Colors.surface2))
            context.stroke(path, with: .color(node.isHighlighted ? DS.Colors.accent : DS.Colors.borderStrong), lineWidth: 1.5)

            let lines = layout.labelLines[node.id] ?? [node.label]
            let lineHeight = CGFloat(ThambiDrawing.flowLineHeight)
            let firstY = rect.midY - lineHeight * CGFloat(lines.count - 1) / 2
            for (index, line) in lines.enumerated() {
                context.draw(
                    label(line, weight: node.isHighlighted ? .semibold : .regular),
                    at: CGPoint(x: rect.midX, y: firstY + CGFloat(index) * lineHeight), anchor: .center
                )
            }
        }
    }

    // MARK: Sequence

    private static func draw(_ sequence: ThambiDrawing.Sequence, in context: inout GraphicsContext, steps: Range<Int>, drawsScaffold: Bool) {
        let metrics = SequenceMetrics(sequence: sequence)
        var columnX: [String: CGFloat] = [:]
        for (index, actor) in sequence.actors.enumerated() {
            let x = metrics.margin + metrics.actorWidth / 2 + CGFloat(index) * metrics.columnSpacing
            columnX[actor.id] = x
            guard drawsScaffold else { continue }
            // Lifeline.
            var lifeline = Path()
            lifeline.move(to: CGPoint(x: x, y: metrics.headerHeight))
            lifeline.addLine(to: CGPoint(x: x, y: metrics.size.height - 6))
            context.stroke(lifeline, with: .color(DS.Colors.borderStrong), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            // Actor box.
            let rect = CGRect(x: x - metrics.actorWidth / 2, y: 2, width: metrics.actorWidth, height: metrics.headerHeight - 8)
            let box = Path(roundedRect: rect, cornerRadius: 8, style: .continuous)
            context.fill(box, with: .color(DS.Colors.surface2))
            context.stroke(box, with: .color(DS.Colors.borderStrong), lineWidth: 1.5)
            context.draw(label(String(actor.label.prefix(16)), weight: .semibold), at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }

        for (index, event) in sequence.events.enumerated() where steps.contains(index < sequence.eventSteps.count ? sequence.eventSteps[index] : 0) {
            let y = metrics.headerHeight + metrics.rowHeight * (CGFloat(index) + 0.75)
            switch event {
            case .message(let from, let to, let text):
                guard let fromX = columnX[from], let toX = columnX[to] else { continue }
                let start = CGPoint(x: fromX, y: y), end = CGPoint(x: toX, y: y)
                var line = Path()
                line.move(to: start)
                line.addLine(to: end)
                context.stroke(line, with: .color(DS.Colors.cool), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                if fromX != toX { context.fill(arrowHead(at: end, from: start), with: .color(DS.Colors.cool)) }
                context.draw(label(text, size: 11), at: CGPoint(x: (fromX + toX) / 2, y: y - 9), anchor: .center)
            case .note(let text):
                let resolved = context.resolve(label(text, size: 11, color: DS.Colors.accentText))
                let textSize = resolved.measure(in: CGSize(width: metrics.size.width - 40, height: 40))
                let rect = CGRect(x: metrics.size.width / 2 - textSize.width / 2 - 8, y: y - textSize.height / 2 - 4, width: textSize.width + 16, height: textSize.height + 8)
                context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(DS.Colors.accentSubtle))
                context.draw(resolved, at: CGPoint(x: metrics.size.width / 2, y: y), anchor: .center)
            }
        }
    }

    // MARK: Plot

    private static let curveColors: [Color] = [DS.Colors.cool, DS.Colors.accent, DS.Colors.success]

    private static func draw(_ plot: ThambiDrawing.Plot, in context: inout GraphicsContext, size: CGSize, steps: Range<Int>, lastStep: Int, drawsScaffold: Bool) {
        let runsPerCurve = plot.curves.map { ThambiDrawing.samples(of: $0) }
        // Points the app worked out itself (roots, crossings, peaks) join the ones that were given.
        // They belong to the last part: they are about the finished picture.
        var plot = plot
        plot.points += ThambiDrawing.markedPoints(for: plot).map { var point = $0; point.step = lastStep; return point }
        let minX = min(plot.curves.map(\.minX).min() ?? -5, plot.points.map(\.x).min() ?? .infinity)
        let maxX = max(plot.curves.map(\.maxX).max() ?? 5, plot.points.map(\.x).max() ?? -.infinity)
        let range = ThambiDrawing.verticalRange(of: runsPerCurve.flatMap { $0 }, points: plot.points)

        let area = CGRect(x: 46, y: 10, width: size.width - 60, height: size.height - 40)
        func position(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(
                x: area.minX + CGFloat((x - minX) / (maxX - minX)) * area.width,
                y: area.maxY - CGFloat((y - range.low) / (range.high - range.low)) * area.height
            )
        }

        // Grid and the numbers along the edges.
        for tick in drawsScaffold ? ThambiDrawing.ticks(from: minX, to: maxX) : [] {
            let x = position(tick, range.low).x
            var line = Path()
            line.move(to: CGPoint(x: x, y: area.minY))
            line.addLine(to: CGPoint(x: x, y: area.maxY))
            context.stroke(line, with: .color(tick == 0 ? DS.Colors.borderStrong : DS.Colors.borderSubtle), lineWidth: tick == 0 ? 1.5 : 1)
            context.draw(label(ThambiDrawing.tickLabel(tick), size: 10, color: DS.Colors.textTertiary, isMeasured: true), at: CGPoint(x: x, y: area.maxY + 11), anchor: .center)
        }
        for tick in drawsScaffold ? ThambiDrawing.ticks(from: range.low, to: range.high, target: 5) : [] {
            let y = position(minX, tick).y
            var line = Path()
            line.move(to: CGPoint(x: area.minX, y: y))
            line.addLine(to: CGPoint(x: area.maxX, y: y))
            context.stroke(line, with: .color(tick == 0 ? DS.Colors.borderStrong : DS.Colors.borderSubtle), lineWidth: tick == 0 ? 1.5 : 1)
            context.draw(label(ThambiDrawing.tickLabel(tick), size: 10, color: DS.Colors.textTertiary, isMeasured: true), at: CGPoint(x: area.minX - 6, y: y), anchor: .trailing)
        }
        if drawsScaffold { context.stroke(Path(area), with: .color(DS.Colors.borderSubtle), lineWidth: 1) }

        // Curves, clipped to the plot area.
        var clipped = context
        clipped.clip(to: Path(area))
        for (curveIndex, runs) in runsPerCurve.enumerated() where steps.contains(plot.curves[curveIndex].step) {
            var path = Path()
            for run in runs {
                path.move(to: position(run[0].x, run[0].y))
                for sample in run.dropFirst() { path.addLine(to: position(sample.x, sample.y)) }
            }
            clipped.stroke(path, with: .color(curveColors[curveIndex % curveColors.count]), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }

        for point in plot.points where steps.contains(point.step) {
            let center = position(point.x, point.y)
            guard area.insetBy(dx: -2, dy: -2).contains(center) else { continue }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(DS.Colors.accent))
            if !point.label.isEmpty {
                // Near the right edge the label goes to the left of its dot, so it stays inside.
                let isNearRightEdge = center.x > area.maxX - 90
                let position = CGPoint(x: center.x + (isNearRightEdge ? -8 : 8), y: center.y - 9)
                let resolved = context.resolve(label(point.label, size: 11))
                let textSize = resolved.measure(in: CGSize(width: 200, height: 20))
                let origin = CGPoint(x: isNearRightEdge ? position.x - textSize.width : position.x, y: position.y - textSize.height / 2)
                context.fill(Path(roundedRect: CGRect(origin: origin, size: textSize).insetBy(dx: -3, dy: -1), cornerRadius: 3), with: .color(DS.Colors.background))
                context.draw(resolved, at: position, anchor: isNearRightEdge ? .trailing : .leading)
            }
        }

        // Which line is which.
        var legendY = area.minY + 12
        for (curveIndex, curve) in plot.curves.enumerated() where !curve.label.isEmpty {
            // Every line keeps its place in the list, shown or not, so the list never jumps.
            defer { legendY += 17 }
            guard steps.contains(curve.step) else { continue }
            var swatch = Path()
            swatch.move(to: CGPoint(x: area.minX + 10, y: legendY))
            swatch.addLine(to: CGPoint(x: area.minX + 28, y: legendY))
            context.stroke(swatch, with: .color(curveColors[curveIndex % curveColors.count]), lineWidth: 2)
            let resolved = context.resolve(label(curve.label, size: 11))
            let textSize = resolved.measure(in: CGSize(width: 200, height: 20))
            let rect = CGRect(x: area.minX + 32, y: legendY - textSize.height / 2 - 1, width: textSize.width + 6, height: textSize.height + 2)
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(DS.Colors.background))
            context.draw(resolved, at: CGPoint(x: area.minX + 35, y: legendY), anchor: .leading)
        }
    }
}

/// Sizes for a message sequence, shared by drawing and by "how big is it".
struct SequenceMetrics {
    let margin: CGFloat = 14
    let actorWidth: CGFloat = 112
    let columnSpacing: CGFloat = 170
    let headerHeight: CGFloat = 44
    let rowHeight: CGFloat = 40
    let size: CGSize

    init(sequence: ThambiDrawing.Sequence) {
        let width = 14 * 2 + 112 + 170 * CGFloat(max(0, sequence.actors.count - 1))
        let height = 44 + 40 * CGFloat(sequence.events.count) + 22
        size = CGSize(width: width, height: height)
    }
}

// MARK: - 3D drawings

struct Drawing3DView: NSViewRepresentable {
    let content: ThambiDrawing.Content
    /// Nil shows everything; a number shows that many parts.
    let visibleSteps: Int?
    /// Slow turning and the models' own motion. Off for Reduce Motion.
    let isMoving: Bool

    final class Coordinator {
        var shownContent: ThambiDrawing.Content?
        var stepNodes: [(step: Int, node: SCNNode)] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor(DS.Colors.background)
        view.rendersContinuously = false
        view.preferredFramesPerSecond = 30
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.shownContent != content {
            coordinator.shownContent = content
            let built = DrawingSceneBuilder.makeScene(for: content, isMoving: isMoving)
            coordinator.stepNodes = built.stepNodes
            view.scene = built.scene
            view.pointOfView = built.camera
            // Anything that moves needs the view to keep drawing; a still picture does not.
            view.isPlaying = isMoving
            for entry in built.stepNodes {
                entry.node.opacity = (visibleSteps.map { entry.step < $0 } ?? true) ? 1 : 0
            }
            return
        }
        // Same picture, more of it showing: fade the new part in.
        for entry in coordinator.stepNodes {
            let shouldShow = visibleSteps.map { entry.step < $0 } ?? true
            if shouldShow, entry.node.opacity < 1, entry.node.action(forKey: "reveal") == nil {
                if isMoving {
                    entry.node.runAction(.fadeIn(duration: 0.3), forKey: "reveal")
                } else {
                    entry.node.opacity = 1
                }
            }
        }
        if !isMoving { view.setNeedsDisplay(view.bounds) }
    }
}

@MainActor
enum DrawingSceneBuilder {

    struct BuiltScene {
        let scene: SCNScene
        let camera: SCNNode
        /// The nodes that belong to each part of a drawing that builds up.
        var stepNodes: [(step: Int, node: SCNNode)]
    }

    static func color(_ color: ThambiDrawing.SceneColor) -> NSColor {
        switch color {
        case .blue: return NSColor(DS.Colors.cool)
        case .amber: return NSColor(DS.Colors.accent)
        case .red: return NSColor(DS.Colors.destructive)
        case .green: return NSColor(DS.Colors.success)
        case .grey: return NSColor(DS.Colors.drawingGrey)
        case .white: return NSColor(DS.Colors.drawingWhite)
        case .teal: return NSColor(DS.Colors.drawingTeal)
        }
    }

    private static func vector(_ vector: ThambiDrawing.Vector3) -> SCNVector3 {
        SCNVector3(CGFloat(vector.x), CGFloat(vector.y), CGFloat(vector.z))
    }

    static func material(_ color: NSColor, isFlat: Bool = false) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = isFlat ? .constant : .blinn
        material.specular.contents = NSColor(white: 1, alpha: 0.25)
        material.shininess = 0.3
        material.isDoubleSided = true
        return material
    }

    /// A cylinder (or cone) standing on `from`, pointing at `to`.
    private static func orient(_ node: SCNNode, from: SCNVector3, to: SCNVector3) {
        let dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z
        let length = sqrt(dx * dx + dy * dy + dz * dz)
        node.position = SCNVector3((from.x + to.x) / 2, (from.y + to.y) / 2, (from.z + to.z) / 2)
        guard length > 0.0001 else { return }
        // Rotate the shape's own axis (straight up) onto the direction.
        let ux = dx / length, uy = dy / length, uz = dz / length
        let axisX = uz, axisZ = -ux           // cross((0,1,0), u) = (uz, 0, -ux)
        let axisLength = sqrt(axisX * axisX + axisZ * axisZ)
        if axisLength < 0.0001 {
            node.rotation = uy < 0 ? SCNVector4(1, 0, 0, CGFloat.pi) : SCNVector4(0, 1, 0, 0)
        } else {
            node.rotation = SCNVector4(axisX / axisLength, 0, axisZ / axisLength, acos(max(-1, min(1, uy))))
        }
    }

    static func stick(from: SCNVector3, to: SCNVector3, radius: CGFloat, color: NSColor) -> SCNNode {
        let dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z
        let cylinder = SCNCylinder(radius: radius, height: sqrt(dx * dx + dy * dy + dz * dz))
        cylinder.radialSegmentCount = 20
        cylinder.materials = [material(color)]
        let node = SCNNode(geometry: cylinder)
        orient(node, from: from, to: to)
        return node
    }

    private static func arrow(from: SCNVector3, to: SCNVector3, color: NSColor, radius: CGFloat = 0.035) -> SCNNode {
        let dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z
        let length = sqrt(dx * dx + dy * dy + dz * dz)
        let headLength = min(0.28, length * 0.35)
        let fraction = length > 0 ? (length - headLength) / length : 0
        let neck = SCNVector3(from.x + dx * fraction, from.y + dy * fraction, from.z + dz * fraction)
        let group = SCNNode()
        group.addChildNode(stick(from: from, to: neck, radius: radius, color: color))
        let cone = SCNCone(topRadius: 0, bottomRadius: radius * 3, height: headLength)
        cone.materials = [material(color)]
        let head = SCNNode(geometry: cone)
        orient(head, from: neck, to: to)
        group.addChildNode(head)
        return group
    }

    /// Text that always faces the viewer and is never hidden behind a shape.
    private static func label(_ text: String, at position: SCNVector3, scale: CGFloat) -> SCNNode {
        let geometry = SCNText(string: text, extrusionDepth: 0)
        geometry.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        geometry.flatness = 0.15
        let textMaterial = material(NSColor(DS.Colors.textPrimary), isFlat: true)
        textMaterial.readsFromDepthBuffer = false
        geometry.materials = [textMaterial]
        let textNode = SCNNode(geometry: geometry)
        let (minimum, maximum) = textNode.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation((minimum.x + maximum.x) / 2, minimum.y, 0)
        textNode.scale = SCNVector3(scale, scale, scale)
        textNode.renderingOrder = 100
        let holder = SCNNode()
        holder.position = position
        holder.addChildNode(textNode)
        holder.constraints = [SCNBillboardConstraint()]
        return holder
    }

    private static func surfaceNode(_ surface: ThambiDrawing.Surface) -> SCNNode {
        let steps = 44
        let span = surface.maximum - surface.minimum
        // Sample the heights first, to scale them into a pleasant shape.
        var heights = [[Double?]](repeating: [Double?](repeating: nil, count: steps + 1), count: steps + 1)
        var low = Double.infinity, high = -Double.infinity
        for row in 0...steps {
            for column in 0...steps {
                let x = surface.minimum + span * Double(column) / Double(steps)
                let y = surface.minimum + span * Double(row) / Double(steps)
                if let value = surface.formula.value(x: x, y: y), abs(value) < 1e6 {
                    heights[row][column] = value
                    low = min(low, value)
                    high = max(high, value)
                }
            }
        }
        guard low.isFinite, high.isFinite else { return SCNNode() }
        let sceneWidth = 5.0
        // Same scale as the ground plane, but never taller than half its width.
        let heightScale = (high - low) < 1e-9 ? 1 : min(sceneWidth / max(span, 1e-9), (sceneWidth * 0.5) / (high - low))
        let middle = (high + low) / 2

        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        for row in 0...steps {
            for column in 0...steps {
                let value = heights[row][column] ?? middle
                vertices.append(SCNVector3(
                    CGFloat(-sceneWidth / 2 + sceneWidth * Double(column) / Double(steps)),
                    CGFloat((value - middle) * heightScale),
                    CGFloat(-sceneWidth / 2 + sceneWidth * Double(row) / Double(steps))
                ))
            }
        }
        var normals = [SCNVector3](repeating: SCNVector3(0, 1, 0), count: vertices.count)
        for row in 0...steps {
            for column in 0...steps {
                let left = vertices[row * (steps + 1) + max(0, column - 1)], right = vertices[row * (steps + 1) + min(steps, column + 1)]
                let near = vertices[max(0, row - 1) * (steps + 1) + column], far = vertices[min(steps, row + 1) * (steps + 1) + column]
                let ax = right.x - left.x, ay = right.y - left.y
                let bz = far.z - near.z, by = far.y - near.y
                // Normal of the two slopes: (-dy/dx, 1, -dy/dz), then made unit length.
                var nx = -ay / max(ax, 0.0001), nz = -by / max(bz, 0.0001), ny: CGFloat = 1
                let length = sqrt(nx * nx + ny * ny + nz * nz)
                nx /= length; ny /= length; nz /= length
                normals[row * (steps + 1) + column] = SCNVector3(nx, ny, nz)
            }
        }
        for row in 0..<steps {
            for column in 0..<steps where heights[row][column] != nil && heights[row + 1][column + 1] != nil
                && heights[row + 1][column] != nil && heights[row][column + 1] != nil {
                let topLeft = Int32(row * (steps + 1) + column), topRight = topLeft + 1
                let bottomLeft = topLeft + Int32(steps + 1), bottomRight = bottomLeft + 1
                indices += [topLeft, bottomLeft, topRight, topRight, bottomLeft, bottomRight]
            }
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.materials = [material(NSColor(DS.Colors.cool))]
        let node = SCNNode(geometry: geometry)

        // A few grid lines on the surface make its shape readable from any side.
        let lineMaterial = material(NSColor(DS.Colors.well).withAlphaComponent(0.55), isFlat: true)
        var lineIndices: [Int32] = []
        for row in stride(from: 0, through: steps, by: 4) {
            for column in 0..<steps where heights[row][column] != nil && heights[row][column + 1] != nil {
                lineIndices += [Int32(row * (steps + 1) + column), Int32(row * (steps + 1) + column + 1)]
            }
        }
        for column in stride(from: 0, through: steps, by: 4) {
            for row in 0..<steps where heights[row][column] != nil && heights[row + 1][column] != nil {
                lineIndices += [Int32(row * (steps + 1) + column), Int32((row + 1) * (steps + 1) + column)]
            }
        }
        let raised = vertices.map { SCNVector3($0.x, $0.y + 0.006, $0.z) }
        let lines = SCNGeometry(sources: [SCNGeometrySource(vertices: raised)], elements: [SCNGeometryElement(indices: lineIndices, primitiveType: .line)])
        lines.materials = [lineMaterial]
        node.addChildNode(SCNNode(geometry: lines))
        return node
    }

    /// "left ventricle" -> "Left ventricle"
    private static func sentenceCased(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    static func makeScene(for content: ThambiDrawing.Content, isMoving: Bool) -> BuiltScene {
        let scene = SCNScene()
        scene.background.contents = NSColor(DS.Colors.background)
        let contentNode = SCNNode()
        scene.rootNode.addChildNode(contentNode)
        var stepNodes: [(step: Int, node: SCNNode)] = []
        /// Labels wait until the picture's size is known, so their text can be sized to it.
        var pendingLabels: [(text: String, position: SCNVector3, parent: SCNNode, step: Int)] = []
        var showsAxes = false
        var turnsSlowly = isMoving

        switch content {
        case .scene(let description):
            for (index, item) in description.items.enumerated() {
                let step = index < description.itemSteps.count ? description.itemSteps[index] : 0
                let holder = SCNNode()
                contentNode.addChildNode(holder)
                stepNodes.append((step, holder))
                switch item {
                case .sphere(let center, let radius, let itemColor, let text):
                    let sphere = SCNSphere(radius: CGFloat(radius))
                    sphere.segmentCount = 36
                    sphere.materials = [material(color(itemColor))]
                    let node = SCNNode(geometry: sphere)
                    node.position = vector(center)
                    holder.addChildNode(node)
                    if !text.isEmpty { pendingLabels.append((text, SCNVector3(CGFloat(center.x), CGFloat(center.y + radius + 0.12), CGFloat(center.z)), holder, step)) }
                case .box(let center, let size, let itemColor, let text):
                    let box = SCNBox(width: CGFloat(abs(size.x)), height: CGFloat(abs(size.y)), length: CGFloat(abs(size.z)), chamferRadius: 0.03)
                    box.materials = [material(color(itemColor))]
                    let node = SCNNode(geometry: box)
                    node.position = vector(center)
                    holder.addChildNode(node)
                    if !text.isEmpty { pendingLabels.append((text, SCNVector3(CGFloat(center.x), CGFloat(center.y + abs(size.y) / 2 + 0.12), CGFloat(center.z)), holder, step)) }
                case .stick(let from, let to, let radius, let itemColor, let text):
                    holder.addChildNode(stick(from: vector(from), to: vector(to), radius: CGFloat(radius), color: color(itemColor)))
                    if !text.isEmpty { pendingLabels.append((text, SCNVector3(CGFloat((from.x + to.x) / 2), CGFloat((from.y + to.y) / 2 + radius + 0.12), CGFloat((from.z + to.z) / 2)), holder, step)) }
                case .arrow(let from, let to, let itemColor, let text):
                    holder.addChildNode(arrow(from: vector(from), to: vector(to), color: color(itemColor)))
                    if !text.isEmpty { pendingLabels.append((text, SCNVector3(CGFloat(to.x), CGFloat(to.y + 0.14), CGFloat(to.z)), holder, step)) }
                case .label(let position, let text):
                    pendingLabels.append((text, vector(position), holder, step))
                }
            }
            if let surface = description.surface {
                contentNode.addChildNode(surfaceNode(surface))
            }
            showsAxes = description.showsAxes || description.surface != nil

        case .model(let request):
            guard let model = ThambiModels.build(request.id, isMoving: isMoving),
                  let entry = ThambiDrawing.modelEntry(for: request.id) else { break }
            contentNode.addChildNode(model.root)
            // A model with its own motion stays put, so the motion can be followed.
            turnsSlowly = isMoving && !model.isAnimated
            // Name the parts that were asked for; with none asked for, name them all.
            let parts = request.shownParts.isEmpty ? entry.parts.map { ThambiDrawing.ShownPart(name: $0, step: 0) } : request.shownParts
            for part in parts {
                guard let anchor = model.anchors[part.name] else { continue }
                pendingLabels.append((sentenceCased(part.name), anchor.offset, anchor.node, part.step))
            }

        default:
            break
        }

        // Frame everything: how big is it, and where is its middle?
        var (center, radius) = (SCNVector3Zero, CGFloat(1))
        func measure() {
            guard !contentNode.childNodes.isEmpty else { return }
            let sphere = contentNode.boundingSphere
            center = sphere.center
            radius = max(CGFloat(sphere.radius), 0.5)
        }
        measure()

        if showsAxes {
            let reach = radius * 1.05
            let axisColor = NSColor(DS.Colors.textTertiary)
            for (name, direction) in [("x", SCNVector3(1, 0, 0)), ("y", SCNVector3(0, 1, 0)), ("z", SCNVector3(0, 0, 1))] {
                let end = SCNVector3(direction.x * reach, direction.y * reach, direction.z * reach)
                contentNode.addChildNode(arrow(from: SCNVector3Zero, to: end, color: axisColor, radius: 0.015))
                pendingLabels.append((name, SCNVector3(end.x * 1.06, end.y * 1.06 + 0.02, end.z * 1.06), contentNode, 0))
            }
            measure()
        }
        let labelScale = max(0.008, radius * 0.0062)
        for entry in pendingLabels {
            let node = label(String(entry.text.prefix(40)), at: entry.position, scale: labelScale)
            entry.parent.addChildNode(node)
            // A label on a shape that is not itself a step (a model part, an axis) is its own step.
            if !stepNodes.contains(where: { $0.node === entry.parent }) { stepNodes.append((entry.step, node)) }
        }

        // Turn about the middle of the picture, slowly, so its depth can be read.
        contentNode.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
        contentNode.position = center
        if turnsSlowly {
            contentNode.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 50)))
        }

        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.05
        camera.zFar = Double(radius) * 40
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let distance = radius / CGFloat(tan(19.0 * .pi / 180)) * 1.32
        cameraNode.position = SCNVector3(center.x + distance * 0.45, center.y + distance * 0.38, center.z + distance * 0.81)
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)

        // Soft light everywhere, plus one that travels with the camera so the near side is always lit.
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 380
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
        let key = SCNLight()
        key.type = .directional
        key.intensity = 620
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.5, 0.45, 0)
        cameraNode.addChildNode(keyNode)

        return BuiltScene(scene: scene, camera: cameraNode, stepNodes: stepNodes)
    }

    /// A still picture of the whole drawing, for Copy, Save and tests.
    static func snapshot(of content: ThambiDrawing.Content, size: CGSize, partsShown: Int? = nil) -> NSImage? {
        let built = makeScene(for: content, isMoving: false)
        if let partsShown {
            for entry in built.stepNodes where entry.step >= partsShown { entry.node.opacity = 0 }
        }
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = built.scene
        renderer.pointOfView = built.camera
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    /// Every part name the catalogue promises must have a place on its model (checked by a test hook).
    static func missingModelAnchors() -> [String] {
        ThambiDrawing.modelCatalogue.flatMap { entry -> [String] in
            guard let model = ThambiModels.build(entry.id, isMoving: false) else { return ["\(entry.id): no model"] }
            return entry.parts.filter { model.anchors[$0] == nil }.map { "\(entry.id): \($0)" }
        }
    }
}
