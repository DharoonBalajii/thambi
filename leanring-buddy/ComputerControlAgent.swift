//
//  ComputerControlAgent.swift
//  leanring-buddy
//
//  Runs one computer-control task: look at the screen, ask the model for ONE action, show it,
//  wait for your Return, do it, look again. The rules it obeys live in ComputerControl.swift.
//
//  • Return approves the step on the card. Escape stops the whole task, at any moment.
//    While a task runs those two keys go to Thambi instead of the app in front; every other key
//    and the mouse stay yours.
//  • Clicks and typing are sent as ordinary mouse and keyboard events (needs the Accessibility
//    permission Thambi already has). Nothing is scripted behind the scenes: you see every move.
//  • The screenshot for each step goes to the same AI service as a normal question, and nowhere else.
//

import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class ComputerControlAgent: ObservableObject {

    enum Phase: Equatable {
        case idle
        case looking(step: Int)
        case waitingForApproval(step: Int, description: String, why: String, isRisky: Bool)
        case acting(step: Int, description: String)
        case finished(message: String, succeeded: Bool)
    }

    enum Outcome: Equatable {
        case finished(say: String)
        case couldNot(say: String)
        case notATask
        case stopped
    }

    /// Asks the model for the next action: (screenshot, its label, the prompt) -> the raw reply.
    typealias DecisionProvider = @MainActor (Data, String, String) async throws -> String

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var task = ""

    /// The buddy cursor flies to the spot that is about to be clicked (AppKit global point, its screen, a label).
    var onPointAtTarget: ((CGPoint, CGRect, String) -> Void)?
    var onClearPointer: (() -> Void)?
    /// Called with the spot (AppKit global point) a click or scroll would land on, before anything
    /// is checked or done, so Thambi's own card can move out of the way.
    var onTargetChosen: ((CGPoint) -> Void)?

    /// What happened, step by step (action names only, never what was typed). For the log and tests.
    private(set) var stepLog: [String] = []

    #if DEBUG
    /// Test builds only: approve every step without waiting, so a contained test can run unattended.
    var approvesEveryStepForTesting = false
    /// Test builds only: each step's screenshot and the model's raw reply.
    var onStepForTesting: ((Int, Data, String) -> Void)?
    /// Test builds only: put the card in a given state so it can be drawn to a picture.
    func showForTesting(task: String, phase: Phase) {
        self.task = task
        self.phase = phase
    }
    #endif

    var isRunning: Bool {
        switch phase {
        case .looking, .waitingForApproval, .acting: return true
        case .idle, .finished: return false
        }
    }

    private var runTask: Task<Void, Never>?
    private var isStopRequested = false
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var approvalTimeoutTask: Task<Void, Never>?
    private var returnToIdleTask: Task<Void, Never>?
    private let keyInterceptor = ControlKeyInterceptor()

    // MARK: - Starting and stopping

    func start(
        task: String,
        approvalMode: ControlApprovalMode,
        decide: @escaping DecisionProvider,
        onFinished: @escaping @MainActor (Outcome) -> Void
    ) {
        guard !isRunning else { return }
        returnToIdleTask?.cancel()
        self.task = task
        stepLog = []
        isStopRequested = false
        phase = .looking(step: 1)

        keyInterceptor.start(
            onReturnKey: { [weak self] in self?.approveFromKeyboard() ?? false },
            onEscapeKey: { [weak self] in
                self?.stop()
                return true
            }
        )
        runTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.run(task: task, approvalMode: approvalMode, decide: decide)
            self.keyInterceptor.stop()
            self.onClearPointer?()
            self.show(outcome)
            onFinished(outcome)
        }
    }

    /// Stops the task right away. Safe to call at any time.
    func stop() {
        guard isRunning else { return }
        isStopRequested = true
        resolveApproval(false)
        runTask?.cancel()
    }

    /// The Allow button on the card.
    func approve() {
        guard case .waitingForApproval = phase else { return }
        resolveApproval(true)
    }

    /// Return was pressed. True when it approved a step (so the key is kept from the app in front).
    private func approveFromKeyboard() -> Bool {
        guard case .waitingForApproval = phase else { return false }
        resolveApproval(true)
        return true
    }

    private func resolveApproval(_ isApproved: Bool) {
        approvalTimeoutTask?.cancel()
        approvalTimeoutTask = nil
        let continuation = approvalContinuation
        approvalContinuation = nil
        continuation?.resume(returning: isApproved)
    }

    private func waitForApproval() async -> Bool {
        #if DEBUG
        if approvesEveryStepForTesting { return true }
        #endif
        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
            approvalTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(ComputerControl.approvalTimeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.resolveApproval(false)
            }
        }
    }

    private func show(_ outcome: Outcome) {
        switch outcome {
        case .finished(let say): phase = .finished(message: say.isEmpty ? "Done." : say, succeeded: true)
        case .couldNot(let say): phase = .finished(message: say.isEmpty ? "Couldn't finish that." : say, succeeded: false)
        case .stopped: phase = .finished(message: "Stopped.", succeeded: false)
        case .notATask: phase = .idle
        }
        guard phase != .idle else { return }
        returnToIdleTask?.cancel()
        returnToIdleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, let self, !self.isRunning else { return }
            self.phase = .idle
        }
    }

    // MARK: - The loop

    private func run(task: String, approvalMode: ControlApprovalMode, decide: DecisionProvider) async -> Outcome {
        guard AXIsProcessTrusted() else { return .couldNot(say: "i need the accessibility permission before i can do that.") }

        // A typed task leaves Thambi's own panel in front: hand the keyboard back to the user's app.
        if NSApp.isActive {
            NSApp.deactivate()
            try? await Task.sleep(nanoseconds: 350_000_000)
        }

        history = []
        hasApprovedThisTask = false
        lastActionSignature = nil
        repeatedActionCount = 0
        var taskDisplayFrame: CGRect?
        var unreadableReplyCount = 0
        var lastNote = ""

        for stepNumber in 1...ComputerControl.maximumSteps {
            guard !isStopRequested, !Task.isCancelled else { return .stopped }
            phase = .looking(step: stepNumber)

            // 1. Look.
            let screenCapture: CompanionScreenCapture
            do {
                let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG(maxDimension: ThambiSettings.controlScreenshotMaxDimension)
                // The whole task stays on the screen it started on.
                guard let chosen = screenCaptures.first(where: { $0.displayFrame == taskDisplayFrame })
                        ?? screenCaptures.first(where: \.isCursorScreen) ?? screenCaptures.first else {
                    return .couldNot(say: "i couldn't see the screen.")
                }
                screenCapture = chosen
                taskDisplayFrame = chosen.displayFrame
            } catch {
                return isStopRequested ? .stopped : .couldNot(say: "i couldn't see the screen.")
            }
            guard !isStopRequested, !Task.isCancelled else { return .stopped }

            // 2. Ask for one action.
            let frontApplication = NSWorkspace.shared.frontmostApplication
            let imageLabel = "the user's screen right now (image dimensions: \(screenCapture.screenshotWidthInPixels)x\(screenCapture.screenshotHeightInPixels) pixels)"
            let prompt = ComputerControl.userPrompt(
                task: task, history: history, frontAppName: frontApplication?.localizedName, stepNumber: stepNumber, lastNote: lastNote,
                controls: ComputerControl.controlsLine(namedControls(for: frontApplication, screenCapture: screenCapture))
            )
            let reply: String
            if stepNumber == 1, let appName = ComputerControl.appNameToOpenDirectly(task),
               let applicationURL = Self.applicationURL(named: appName) {
                // "open calculator" needs no AI: the words already say everything. Free and instant.
                let properName = applicationURL.deletingPathExtension().lastPathComponent
                let payload: [String: Any] = ["action": "open_app", "app": properName, "why": "you asked for it", "finish": "\(properName.lowercased()) is open."]
                reply = (try? JSONSerialization.data(withJSONObject: payload)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("🖱️ Control: opened directly, no AI call")
            } else {
            do {
                reply = try await decide(screenCapture.imageData, imageLabel, prompt)
            } catch {
                if isStopRequested || Task.isCancelled { return .stopped }
                print("🖱️ Control: the request failed (\(error.localizedDescription))")
                return .couldNot(say: "i couldn't reach the ai just now, try again in a moment.")
            }
            }
            guard !isStopRequested, !Task.isCancelled else { return .stopped }
            #if DEBUG
            onStepForTesting?(stepNumber, screenCapture.imageData, reply)
            #endif

            guard let decision = ComputerControl.parseDecision(from: reply) else {
                unreadableReplyCount += 1
                print("🖱️ Control step \(stepNumber): unreadable reply")
                if unreadableReplyCount >= 2 { return .couldNot(say: "i got confused working that out, sorry.") }
                history.append("step \(stepNumber): your reply was not one valid json action -> nothing was done")
                continue
            }

            if !decision.note.isEmpty { lastNote = decision.note }

            // 3. Finished, or not a task at all?
            switch decision.action {
            case .done(let say):
                stepLog.append("done")
                return .finished(say: say)
            case .cannot(let say):
                stepLog.append("cannot")
                return .couldNot(say: say)
            case .notATask:
                // Only believable before anything has been done.
                if history.isEmpty { return .notATask }
                return .finished(say: "")
            default:
                break
            }

            // 4-6. Check it, ask if needed, do it. Then any certain follow-ups, without looking again.
            let followUps = ComputerControl.parseFollowUps(from: reply)
            var didEveryActionWork = true
            let historyCountBeforeReply = history.count
            for (index, action) in ([decision.action] + followUps).enumerated() {
                let currentFrontApplication = index == 0 ? frontApplication : NSWorkspace.shared.frontmostApplication
                let stepResult = await carryOut(
                    action, why: index == 0 ? decision.why : "", stepNumber: stepNumber,
                    screenCapture: screenCapture, frontApplication: currentFrontApplication, approvalMode: approvalMode,
                    isFollowUp: index > 0
                )
                if case .end(let outcome) = stepResult { return outcome }
                if case .lookAgain = stepResult {
                    didEveryActionWork = false
                    break
                }
            }
            // The model writes its note before its actions run, so say plainly what ran since:
            // otherwise it reads "left: click 7" next time and presses 7 again.
            let carriedOut = history[historyCountBeforeReply...].map { $0.replacingOccurrences(of: #"^step \d+: "#, with: "", options: .regularExpression) }
            if !carriedOut.isEmpty {
                lastNote += " || since you wrote that note, these have ALREADY been carried out, do not repeat them: " + carriedOut.joined(separator: "; ")
            }
            // Sure-thing tasks end here, without paying for a second look at the screen.
            if didEveryActionWork, !decision.finish.isEmpty, !ComputerControl.taskNeedsResultRead(task),
               !([decision.action] + followUps).contains(where: \.isClickForFinishCheck) {
                stepLog.append("done (no second look)")
                return .finished(say: decision.finish)
            }
            guard !isStopRequested, !Task.isCancelled else { return .stopped }
        }
        return .couldNot(say: "i ran out of steps before finishing, have a look and tell me what's left.")
    }

    private var history: [String] = []
    private var hasApprovedThisTask = false
    private var lastActionSignature: String?
    private var repeatedActionCount = 0

    private enum StepResult {
        /// Done; a follow-up may run next.
        case carryOn
        /// Nothing more from this reply: take a fresh look.
        case lookAgain
        case end(Outcome)
    }

    /// One action: where it lands, whether it is allowed, your go-ahead if needed, then the act itself.
    private func carryOut(
        _ action: ControlAction, why: String, stepNumber: Int, screenCapture: CompanionScreenCapture,
        frontApplication: NSRunningApplication?, approvalMode: ControlApprovalMode, isFollowUp: Bool = false
    ) async -> StepResult {
        guard !isStopRequested, !Task.isCancelled else { return .end(.stopped) }
        var resolvedTarget = resolveTarget(for: action, screenCapture: screenCapture, frontApplication: frontApplication)
        if case .click(_, _, let modelLabel, _) = action {
            snapToNamedControl(&resolvedTarget, modelLabel: modelLabel)
        }
        if let appKitPoint = resolvedTarget.appKitPoint {
            onTargetChosen?(appKitPoint)
            // The screenshot leaves Thambi's own windows out, so the model can aim at something
            // that is really underneath one of them. Never click through to it blindly.
            let isCoveredByOwnWindow = NSApp.windows.contains {
                $0.isVisible && !$0.ignoresMouseEvents && $0.alphaValue > 0.01 && $0.frame.contains(appKitPoint)
            }
            if isCoveredByOwnWindow { resolvedTarget.context.isOwnApp = true }
        }
        // A click made without a fresh look must land on exactly the control that was named.
        if isFollowUp, case .click(_, _, let modelLabel, _) = action,
           resolvedTarget.context.elementLabel?.lowercased() != ComputerControl.controlName(fromTarget: modelLabel) {
            return .lookAgain
        }
        let description = ComputerControl.describe(action, target: resolvedTarget.context)
        if let blockReason = ComputerControl.blockReason(for: action, target: resolvedTarget.context) {
            stepLog.append("blocked: \(Self.logName(for: action))")
            print("🖱️ Control step \(stepNumber): blocked (\(Self.logName(for: action)))")
            return .end(.couldNot(say: blockReason))
        }
        if case .click = action, resolvedTarget.globalPoint == nil {
            history.append("step \(stepNumber): the coordinates were outside the screenshot -> nothing was done")
            return .lookAgain
        }
        // The same action three times in a row means it is not working.
        // (A click somewhere else is a different action, even with the same name.)
        let actionSignature = description + (resolvedTarget.globalPoint.map { " @\(Int($0.x / 8)),\(Int($0.y / 8))" } ?? "")
        repeatedActionCount = (actionSignature == lastActionSignature) ? repeatedActionCount + 1 : 0
        lastActionSignature = actionSignature
        if repeatedActionCount >= 2 {
            return .end(.couldNot(say: "i kept trying the same thing and it isn't working, have a look."))
        }

        // The buddy flies to the spot, so you can see where Thambi is working even with the card hidden.
        if let appKitPoint = resolvedTarget.appKitPoint, case .click = action {
            onPointAtTarget?(appKitPoint, screenCapture.displayFrame, resolvedTarget.context.elementLabel ?? "")
        }

        // Ask first.
        let isRisky = ComputerControl.isRisky(action, target: resolvedTarget.context)
        let needsApproval = ComputerControl.needsApproval(
            mode: approvalMode, stepNumber: stepNumber, hasApprovedThisTask: hasApprovedThisTask,
            action: action, target: resolvedTarget.context
        )
        if needsApproval {
            phase = .waitingForApproval(step: stepNumber, description: description, why: why, isRisky: isRisky)
            let isApproved = await waitForApproval()
            guard isApproved, !isStopRequested, !Task.isCancelled else { return .end(.stopped) }
            hasApprovedThisTask = true
        }

        // Do it.
        phase = .acting(step: stepNumber, description: description)
        let result = await perform(action, at: resolvedTarget)
        stepLog.append("\(Self.logName(for: action)): \(result)")
        print("🖱️ Control step \(stepNumber): \(Self.logName(for: action)) -> \(result)")
        history.append(ComputerControl.historyLine(
            stepNumber: stepNumber, action: action, target: resolvedTarget.context, result: result
        ))
        // A follow-up only makes sense when this step worked.
        let didWork = !result.hasPrefix("could not") && !result.contains("did not come to the front") && !result.hasPrefix("no app") && result != "unknown key"
        return didWork ? .carryOn : .lookAgain
    }

    /// The action's kind only: the log never holds what was typed or clicked.
    private static func logName(for action: ControlAction) -> String {
        switch action {
        case .click(_, _, _, let isDoubleClick): return isDoubleClick ? "double_click" : "click"
        case .type(let text): return "type (\(text.count) characters)"
        case .key: return "key"
        case .scroll: return "scroll"
        case .openApp: return "open_app"
        case .wait: return "wait"
        case .done: return "done"
        case .cannot: return "cannot"
        case .notATask: return "not_a_task"
        }
    }

    // MARK: - Working out the target

    private struct ResolvedTarget {
        var context = ComputerControl.TargetContext()
        /// Where a click or scroll lands, in Quartz global coordinates (top-left origin).
        var globalPoint: CGPoint?
        /// The same spot in AppKit global coordinates (bottom-left origin), for the buddy cursor.
        var appKitPoint: CGPoint?
        var applicationURL: URL?
    }

    private func resolveTarget(
        for action: ControlAction, screenCapture: CompanionScreenCapture, frontApplication: NSRunningApplication?
    ) -> ResolvedTarget {
        var resolved = ResolvedTarget()
        let ownBundleIdentifier = Bundle.main.bundleIdentifier

        func useFrontApplication() {
            resolved.context.appName = frontApplication?.localizedName
            resolved.context.appBundleIdentifier = frontApplication?.bundleIdentifier
            resolved.context.isOwnApp = frontApplication?.bundleIdentifier == ownBundleIdentifier
        }

        func usePoint(x: Int, y: Int) {
            guard let displayPoint = ComputerControl.displayPoint(
                screenshotX: x, screenshotY: y,
                screenshotWidth: screenCapture.screenshotWidthInPixels, screenshotHeight: screenCapture.screenshotHeightInPixels,
                displayWidth: Double(screenCapture.displayWidthInPoints), displayHeight: Double(screenCapture.displayHeightInPoints)
            ) else { return }
            let displayFrame = screenCapture.displayFrame
            let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? displayFrame.height
            let globalPoint = CGPoint(
                x: displayFrame.minX + displayPoint.x,
                y: (primaryScreenHeight - displayFrame.maxY) + displayPoint.y
            )
            resolved.globalPoint = globalPoint
            resolved.appKitPoint = CGPoint(x: displayFrame.minX + displayPoint.x, y: displayFrame.maxY - displayPoint.y)

            // Which app owns the window under that point, and what is there?
            if let owner = Self.applicationOwningWindow(at: globalPoint) {
                resolved.context.appName = owner.localizedName
                resolved.context.appBundleIdentifier = owner.bundleIdentifier
                resolved.context.isOwnApp = owner.bundleIdentifier == ownBundleIdentifier
                let element = Self.accessibilityElement(at: globalPoint, in: owner)
                resolved.context.elementRole = element.role
                resolved.context.elementLabel = element.label
                resolved.context.isSecureField = element.isSecureField
            } else {
                useFrontApplication()
            }
        }

        switch action {
        case .click(let x, let y, _, _):
            usePoint(x: x, y: y)
        case .scroll(let x, let y, _, _):
            if x >= 0, y >= 0 {
                usePoint(x: x, y: y)
            } else {
                usePoint(x: screenCapture.screenshotWidthInPixels / 2, y: screenCapture.screenshotHeightInPixels / 2)
            }
        case .type, .key:
            useFrontApplication()
            resolved.context.isSecureField = DictationTextInserter.isFocusedElementSecure
        case .openApp(let name):
            resolved.applicationURL = Self.applicationURL(named: name)
            resolved.context.appName = name
            resolved.context.appBundleIdentifier = resolved.applicationURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        case .wait, .done, .cannot, .notATask:
            break
        }
        return resolved
    }

    /// The model names what it clicks ("the 5 button"). When accessibility says something else is
    /// at that spot, and exactly one control in the same app carries that name, aim at that one.
    /// Done on this Mac, costs nothing, and only ever moves a click onto the thing that was named.
    private func snapToNamedControl(_ resolved: inout ResolvedTarget, modelLabel: String) {
        let wantedName = ComputerControl.controlName(fromTarget: modelLabel)
        guard !wantedName.isEmpty, wantedName.count <= 40, let globalPoint = resolved.globalPoint,
              !resolved.context.isOwnApp, resolved.context.elementLabel?.lowercased() != wantedName,
              let owner = Self.applicationOwningWindow(at: globalPoint) else { return }

        let matches = Self.labelledControls(in: owner, maximumCount: 400).filter { $0.label.lowercased() == wantedName }
        guard matches.count == 1, let match = matches.first else { return }
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        resolved.globalPoint = match.center
        resolved.appKitPoint = CGPoint(x: match.center.x, y: primaryScreenHeight - match.center.y)
        resolved.context.elementRole = Self.plainRoleNames[match.role]
        resolved.context.elementLabel = match.label
        print("🖱️ Control: aim corrected onto the named control")
    }

    /// The named, clickable controls in an app's front window: names and places only, never the
    /// contents of text fields. Bounded in count and time so a huge window cannot stall a step.
    private static func labelledControls(
        in application: NSRunningApplication, maximumCount: Int
    ) -> [(center: CGPoint, role: String, label: String)] {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, 0.3)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(applicationElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return [] }

        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        var controls: [(center: CGPoint, role: String, label: String)] = []
        var queue: [AXUIElement] = [windowValue as! AXUIElement]
        var visitedCount = 0
        let deadline = Date().addingTimeInterval(0.6)
        while !queue.isEmpty, visitedCount < 600, Date() < deadline, controls.count < maximumCount {
            let element = queue.removeFirst()
            visitedCount += 1
            let role = attribute(element, kAXRoleAttribute as String) as? String ?? ""
            if plainRoleNames[role] != nil, role != "AXStaticText", role != "AXTextArea", role != "AXImage",
               role != "AXScrollArea", role != "AXWebArea", role != "AXToolbar", role != "AXTabGroup", role != "AXRow", role != "AXCell" {
                let label = ((attribute(element, kAXTitleAttribute as String) as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (attribute(element, kAXDescriptionAttribute as String) as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty,
                   let positionValue = attribute(element, kAXPositionAttribute as String),
                   let sizeValue = attribute(element, kAXSizeAttribute as String),
                   CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                    var position = CGPoint.zero
                    var size = CGSize.zero
                    AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
                    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                    if size.width > 2, size.height > 2 {
                        controls.append((CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2), role, label))
                    }
                }
            }
            if let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(80))
            }
        }
        return controls
    }

    /// The front window's controls as the model should see them: names with screenshot coordinates.
    private func namedControls(for application: NSRunningApplication?, screenCapture: CompanionScreenCapture) -> [ComputerControl.NamedControl] {
        guard let application, application.bundleIdentifier != Bundle.main.bundleIdentifier,
              !ComputerControl.isBlockedApp(bundleIdentifier: application.bundleIdentifier, name: application.localizedName) else { return [] }
        let displayFrame = screenCapture.displayFrame
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? displayFrame.height
        let originX = displayFrame.minX
        let originY = primaryScreenHeight - displayFrame.maxY
        let scaleX = Double(screenCapture.screenshotWidthInPixels) / Double(max(1, screenCapture.displayWidthInPoints))
        let scaleY = Double(screenCapture.screenshotHeightInPixels) / Double(max(1, screenCapture.displayHeightInPoints))
        return Self.labelledControls(in: application, maximumCount: 80).compactMap { control in
            let x = Int(((control.center.x - originX) * scaleX).rounded())
            let y = Int(((control.center.y - originY) * scaleY).rounded())
            guard x >= 0, y >= 0, x <= screenCapture.screenshotWidthInPixels, y <= screenCapture.screenshotHeightInPixels else { return nil }
            return ComputerControl.NamedControl(name: control.label, x: x, y: y)
        }
    }

    /// The app whose window is topmost at a point (Thambi's own click-through overlay is skipped).
    private static func applicationOwningWindow(at globalPoint: CGPoint) -> NSRunningApplication? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        for windowInfo in windowList {
            guard let processIdentifier = windowInfo[kCGWindowOwnerPID as String] as? pid_t, processIdentifier != ownProcessIdentifier,
                  let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary), bounds.contains(globalPoint),
                  (windowInfo[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 else { continue }
            return NSRunningApplication(processIdentifier: processIdentifier)
        }
        return nil
    }

    private static let plainRoleNames: [String: String] = [
        "AXButton": "button", "AXTextField": "text field", "AXTextArea": "text area", "AXMenuItem": "menu item",
        "AXMenuBarItem": "menu", "AXMenuButton": "menu button", "AXPopUpButton": "pop-up menu", "AXCheckBox": "checkbox",
        "AXRadioButton": "option", "AXLink": "link", "AXStaticText": "text", "AXImage": "image", "AXCell": "cell",
        "AXRow": "row", "AXTabGroup": "tabs", "AXSlider": "slider", "AXComboBox": "combo box", "AXSearchField": "search field",
        "AXDockItem": "Dock item", "AXToolbar": "toolbar", "AXWebArea": "web page", "AXScrollArea": "scroll area"
    ]

    private static func accessibilityElement(
        at globalPoint: CGPoint, in application: NSRunningApplication
    ) -> (role: String?, label: String?, isSecureField: Bool) {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, 0.4)
        var elementValue: AXUIElement?
        if AXUIElementCopyElementAtPosition(applicationElement, Float(globalPoint.x), Float(globalPoint.y), &elementValue) != .success || elementValue == nil {
            // Some apps only answer through the system-wide lookup.
            let systemWideElement = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(systemWideElement, 0.4)
            AXUIElementCopyElementAtPosition(systemWideElement, Float(globalPoint.x), Float(globalPoint.y), &elementValue)
        }
        guard let element = elementValue else { return (nil, nil, false) }

        func stringAttribute(_ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let string = value as? String else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(60))
        }
        let role = stringAttribute(kAXRoleAttribute as String)
        let isSecureField = stringAttribute(kAXSubroleAttribute as String) == (kAXSecureTextFieldSubrole as String)
        // A text field's contents are never read: only names and labels.
        var label = stringAttribute(kAXTitleAttribute as String) ?? stringAttribute(kAXDescriptionAttribute as String)
        if label == nil, role == "AXStaticText" { label = stringAttribute(kAXValueAttribute as String) }
        if label == nil { label = stringAttribute(kAXHelpAttribute as String) }
        return (role.flatMap { plainRoleNames[$0] }, label, isSecureField)
    }

    /// Finds an installed app by the name people call it ("TextEdit", "Safari").
    static func applicationURL(named name: String) -> URL? {
        let wantedName = name.lowercased().replacingOccurrences(of: ".app", with: "").trimmingCharacters(in: .whitespaces)
        guard !wantedName.isEmpty, !wantedName.contains("/") else { return nil }
        if let runningApplication = NSWorkspace.shared.runningApplications.first(where: {
            $0.activationPolicy == .regular && $0.localizedName?.lowercased() == wantedName
        }) {
            return runningApplication.bundleURL
        }
        let folders = [
            "/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities",
            NSHomeDirectory() + "/Applications", "/System/Library/CoreServices", "/System/Library/CoreServices/Applications"
        ]
        for folder in folders {
            let candidate = URL(fileURLWithPath: folder)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: candidate.path) else { continue }
            if let match = names.first(where: { $0.lowercased() == wantedName + ".app" }) {
                return candidate.appendingPathComponent(match)
            }
        }
        return nil
    }

    // MARK: - Doing the action

    private func perform(_ action: ControlAction, at target: ResolvedTarget) async -> String {
        func pause(_ seconds: Double) async {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        switch action {
        case .click(_, _, _, let isDoubleClick):
            guard let globalPoint = target.globalPoint else { return "could not find that spot" }
            await Self.click(at: globalPoint, isDoubleClick: isDoubleClick)
            await pause(0.4)
            let landedOn = [target.context.elementRole, target.context.elementLabel.map { "\"\($0)\"" }].compactMap { $0 }.joined(separator: " ")
            return landedOn.isEmpty ? "clicked" : "clicked (what is at that spot: \(landedOn))"

        case .type(let text):
            // A text box takes text in bursts (per-key typing there sets off autocorrect and inline
            // suggestions, which garble it). Anything else, like Calculator, wants one key at a time.
            let didType = await DictationTextInserter.type(text, oneCharacterPerKeyPress: !Self.isKeyboardFocusInTextBox)
            await pause(0.2)
            return didType ? "typed" : "could not type (no text field accepted it)"

        case .key(let combo):
            guard let keyCombo = ControlKeyCombo.parse(combo) else { return "unknown key" }
            var flags: CGEventFlags = []
            if keyCombo.command { flags.insert(.maskCommand) }
            if keyCombo.shift { flags.insert(.maskShift) }
            if keyCombo.option { flags.insert(.maskAlternate) }
            if keyCombo.control { flags.insert(.maskControl) }
            DictationTextInserter.pressKey(virtualKey: CGKeyCode(keyCombo.keyCode), flags: flags)
            await pause(0.4)
            return "pressed"

        case .scroll(_, _, let direction, let amount):
            guard let globalPoint = target.globalPoint else { return "could not find that spot" }
            Self.moveMouse(to: globalPoint)
            await pause(0.08)
            let lines = Int32(amount * 3)
            let (vertical, horizontal): (Int32, Int32) = {
                switch direction {
                case .up: return (lines, 0)
                case .down: return (-lines, 0)
                case .left: return (0, lines)
                case .right: return (0, -lines)
                }
            }()
            if let scrollEvent = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .combinedSessionState), units: .line, wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0) {
                scrollEvent.setIntegerValueField(.eventSourceUserData, value: DictationTextInserter.syntheticEventMarker)
                scrollEvent.post(tap: .cghidEventTap)
            }
            await pause(0.45)
            return "scrolled"

        case .openApp(let name):
            guard let applicationURL = target.applicationURL else { return "no app called \(name) is installed" }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let openedApplication: NSRunningApplication
            do {
                openedApplication = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
            } catch {
                return "could not open \(name)"
            }
            // macOS does not always let a background app bring another one forward, so ask twice
            // more if needed: the ordinary way, then through accessibility.
            for attempt in 0..<3 {
                await pause(attempt == 0 ? 0.6 : 0.5)
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == openedApplication.processIdentifier {
                    await pause(0.45)
                    return "opened, \(name) is now in front"
                }
                if attempt == 0 {
                    openedApplication.activate(options: [.activateAllWindows])
                } else {
                    let applicationElement = AXUIElementCreateApplication(openedApplication.processIdentifier)
                    AXUIElementSetAttributeValue(applicationElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                }
            }
            return "opened \(name), but it did not come to the front"

        case .wait:
            await pause(0.9)
            return "waited"

        case .done, .cannot, .notATask:
            return "nothing to do"
        }
    }

    /// True when the keyboard focus is in something that holds text (a field, a document, a web page).
    private static var isKeyboardFocusInTextBox: Bool {
        let systemWideElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWideElement, 0.3)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return false }
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedValue as! AXUIElement, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String else { return false }
        return ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXWebArea"].contains(role)
    }

    private static func moveMouse(to globalPoint: CGPoint) {
        guard let moveEvent = CGEvent(mouseEventSource: CGEventSource(stateID: .combinedSessionState), mouseType: .mouseMoved, mouseCursorPosition: globalPoint, mouseButton: .left) else { return }
        moveEvent.setIntegerValueField(.eventSourceUserData, value: DictationTextInserter.syntheticEventMarker)
        moveEvent.post(tap: .cghidEventTap)
    }

    private static func click(at globalPoint: CGPoint, isDoubleClick: Bool) async {
        let eventSource = CGEventSource(stateID: .combinedSessionState)
        func post(_ mouseType: CGEventType, clickCount: Int64) {
            guard let event = CGEvent(mouseEventSource: eventSource, mouseType: mouseType, mouseCursorPosition: globalPoint, mouseButton: .left) else { return }
            event.flags = []
            event.setIntegerValueField(.mouseEventClickState, value: clickCount)
            event.setIntegerValueField(.eventSourceUserData, value: DictationTextInserter.syntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
        moveMouse(to: globalPoint)
        // A short settle lets hover states and menus catch up before the press.
        try? await Task.sleep(nanoseconds: 90_000_000)
        post(.leftMouseDown, clickCount: 1)
        try? await Task.sleep(nanoseconds: 45_000_000)
        post(.leftMouseUp, clickCount: 1)
        guard isDoubleClick else { return }
        try? await Task.sleep(nanoseconds: 90_000_000)
        post(.leftMouseDown, clickCount: 2)
        try? await Task.sleep(nanoseconds: 45_000_000)
        post(.leftMouseUp, clickCount: 2)
    }
}

// MARK: - Return and Escape while a task runs

/// While a task runs, Return (approve) and Escape (stop) are taken by Thambi instead of reaching
/// the app in front, so approving a step can never also press Return in your document.
/// Every other key passes straight through. Removed the moment the task ends.
final class ControlKeyInterceptor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onReturnKey: (() -> Bool)?
    private var onEscapeKey: (() -> Bool)?

    deinit {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
    }

    func start(onReturnKey: @escaping () -> Bool, onEscapeKey: @escaping () -> Bool) {
        stop()
        self.onReturnKey = onReturnKey
        self.onEscapeKey = onEscapeKey

        let eventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<ControlKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            return interceptor.handle(eventType: eventType, event: event)
        }
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: eventMask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            print("⚠️ Control: couldn't listen for Return and Escape")
            return
        }
        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil
        eventTap = nil
        onReturnKey = nil
        onEscapeKey = nil
        swallowedKeyCodes.removeAll()
    }

    /// Keys whose press was taken: their release is taken too, so no app sees half a key press.
    private var swallowedKeyCodes = Set<Int64>()

    private func handle(eventType: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Thambi's own key presses always pass.
        if event.getIntegerValueField(.eventSourceUserData) == DictationTextInserter.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if eventType == .keyUp {
            return swallowedKeyCodes.remove(keyCode) != nil ? nil : Unmanaged.passUnretained(event)
        }
        var isTaken = false
        if keyCode == 53 {
            isTaken = onEscapeKey?() ?? false
        } else if keyCode == 36 || keyCode == 76 {
            // Only a plain Return approves: Command + Return and friends stay with the app.
            let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate])
            if modifiers.isEmpty { isTaken = onReturnKey?() ?? false }
        }
        guard isTaken else { return Unmanaged.passUnretained(event) }
        swallowedKeyCodes.insert(keyCode)
        return nil
    }
}
