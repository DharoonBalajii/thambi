//
//  GlobalPushToTalkShortcutMonitor.swift
//  leanring-buddy
//
//  Captures push-to-talk keyboard shortcuts while Clicky is running in the
//  background. Uses a listen-only CGEvent tap so modifier-only shortcuts like
//  ctrl + option behave more like a real system-wide voice tool.
//

import AppKit
import Combine
import CoreGraphics
import Foundation

final class GlobalPushToTalkShortcutMonitor: ObservableObject {
    let shortcutTransitionPublisher = PassthroughSubject<BuddyPushToTalkShortcut.ShortcutTransition, Never>()
    /// Escape was pressed anywhere (used to stop the voice). The key still reaches the app in front.
    let escapeKeyPublisher = PassthroughSubject<Void, Never>()
    /// Control + Option + T was pressed (opens the box for typing a question).
    let typeQuestionShortcutPublisher = PassthroughSubject<Void, Never>()

    /// Type anywhere by voice: pressed and released like push-to-talk. `.none` is sent when another
    /// key is pressed while the keys are held, meaning it was an ordinary shortcut (Command + Option + V)
    /// and the dictation must be dropped.
    let dictationShortcutTransitionPublisher = PassthroughSubject<BuddyPushToTalkShortcut.ShortcutTransition, Never>()
    private var isDictationShortcutCurrentlyPressed = false

    private var globalEventTap: CFMachPort?
    private var globalEventTapRunLoopSource: CFRunLoopSource?
    /// Mutated exclusively from the CGEvent tap callback, which runs on
    /// `CFRunLoopGetMain()` and therefore always executes on the main thread.
    /// Published so the overlay can hide immediately on key release without
    /// waiting for the async dictation state pipeline to catch up.
    @Published private(set) var isShortcutCurrentlyPressed = false

    deinit {
        stop()
    }

    func start() {
        // If the event tap is already running, don't restart it.
        // Restarting resets isShortcutCurrentlyPressed, which would kill
        // the waveform overlay mid-press when the permission poller calls
        // refreshAllPermissions → start() every few seconds.
        guard globalEventTap == nil else { return }

        let monitoredEventTypes: [CGEventType] = [.flagsChanged, .keyDown, .keyUp]
        let eventMask = monitoredEventTypes.reduce(CGEventMask(0)) { currentMask, eventType in
            currentMask | (CGEventMask(1) << eventType.rawValue)
        }

        let eventTapCallback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let globalPushToTalkShortcutMonitor = Unmanaged<GlobalPushToTalkShortcutMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            return globalPushToTalkShortcutMonitor.handleGlobalEventTap(
                eventType: eventType,
                event: event
            )
        }

        guard let globalEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️ Global push-to-talk: couldn't create CGEvent tap")
            return
        }

        guard let globalEventTapRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            globalEventTap,
            0
        ) else {
            CFMachPortInvalidate(globalEventTap)
            print("⚠️ Global push-to-talk: couldn't create event tap run loop source")
            return
        }

        self.globalEventTap = globalEventTap
        self.globalEventTapRunLoopSource = globalEventTapRunLoopSource

        CFRunLoopAddSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: globalEventTap, enable: true)
    }

    /// Call after the push-to-talk shortcut is changed, so a half-held old shortcut isn't left "pressed".
    func resetPressedState() {
        isShortcutCurrentlyPressed = false
        isDictationShortcutCurrentlyPressed = false
    }

    func stop() {
        isShortcutCurrentlyPressed = false

        if let globalEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
            self.globalEventTapRunLoopSource = nil
        }

        if let globalEventTap {
            CFMachPortInvalidate(globalEventTap)
            self.globalEventTap = nil
        }
    }

    private func handleGlobalEventTap(
        eventType: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let globalEventTap {
                CGEvent.tapEnable(tap: globalEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Thambi's own typing (dictation, computer control) is never treated as the user's keys.
        if event.getIntegerValueField(.eventSourceUserData) == DictationTextInserter.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if eventType == .flagsChanged {
            let isDictationShortcutHeld = BuddyPushToTalkShortcut.isDictationShortcutHeld(modifierFlagsRawValue: event.flags.rawValue)
            if isDictationShortcutHeld && !isDictationShortcutCurrentlyPressed {
                isDictationShortcutCurrentlyPressed = true
                dictationShortcutTransitionPublisher.send(.pressed)
            } else if !isDictationShortcutHeld && isDictationShortcutCurrentlyPressed {
                isDictationShortcutCurrentlyPressed = false
                dictationShortcutTransitionPublisher.send(.released)
            }
        } else if eventType == .keyDown {
            if isDictationShortcutCurrentlyPressed {
                isDictationShortcutCurrentlyPressed = false
                dictationShortcutTransitionPublisher.send(.none)
            }
        }

        if eventType == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            if eventKeyCode == BuddyPushToTalkShortcut.escapeKeyCode {
                escapeKeyPublisher.send()
            } else if BuddyPushToTalkShortcut.isTypeQuestionShortcut(keyCode: eventKeyCode, modifierFlagsRawValue: event.flags.rawValue) {
                typeQuestionShortcutPublisher.send()
                return Unmanaged.passUnretained(event)
            }
        }
        let shortcutTransition = BuddyPushToTalkShortcut.shortcutTransition(
            for: eventType,
            keyCode: eventKeyCode,
            modifierFlagsRawValue: event.flags.rawValue,
            wasShortcutPreviouslyPressed: isShortcutCurrentlyPressed
        )

        switch shortcutTransition {
        case .none:
            break
        case .pressed:
            isShortcutCurrentlyPressed = true
            shortcutTransitionPublisher.send(.pressed)
        case .released:
            isShortcutCurrentlyPressed = false
            shortcutTransitionPublisher.send(.released)
        }

        return Unmanaged.passUnretained(event)
    }
}
