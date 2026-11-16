//
//  DictationTextInserter.swift
//  leanring-buddy
//
//  Types text into whatever app is in front, as if it came from the keyboard. Used for
//  "type anywhere by voice" and, when you turn it on, for computer control.
//
//  The text is sent as keyboard events, not through the clipboard, so whatever you last copied
//  is left alone and clipboard managers never see what you dictated.
//  Needs the Accessibility permission Thambi already asks for.
//

import AppKit
import ApplicationServices
import Foundation

@MainActor
enum DictationTextInserter {

    /// Every event Thambi posts carries this mark, so its own key listener can ignore them.
    nonisolated static let syntheticEventMarker: Int64 = 0x5448_414D

    /// Keyboard events carry at most this many UTF-16 units reliably.
    private static let unitsPerEvent = 16

    /// True when the text field that has the keyboard is a password field. Thambi never types into those.
    static var isFocusedElementSecure: Bool {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return false }
        let focusedElement = focusedValue as! AXUIElement
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(focusedElement, kAXSubroleAttribute as CFString, &subroleValue)
        return (subroleValue as? String) == (kAXSecureTextFieldSubrole as String)
    }

    /// Splits text into pieces small enough for one keyboard event, never cutting a character in half.
    nonisolated static func chunks(of text: String, unitsPerChunk: Int = 16) -> [String] {
        var chunks: [String] = []
        var current = ""
        var currentUnits = 0
        for character in text {
            let characterUnits = character.utf16.count
            if currentUnits + characterUnits > unitsPerChunk, !current.isEmpty {
                chunks.append(current)
                current = ""
                currentUnits = 0
            }
            current.append(character)
            currentUnits += characterUnits
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Types the text into the app in front. Returns false if it could not be typed.
    @discardableResult
    /// `oneCharacterPerKeyPress` sends each character as its own key press. Slower, but apps that
    /// treat every press as one key (Calculator, games, some web fields) only see the first
    /// character of a longer burst. Computer control uses it; dictation keeps the fast bursts.
    static func type(_ text: String, oneCharacterPerKeyPress: Bool = false) async -> Bool {
        guard AXIsProcessTrusted(), !text.isEmpty else { return false }
        guard !isFocusedElementSecure else {
            print("⌨️ Not typing: a password field has the keyboard")
            return false
        }
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else { return false }

        // Line breaks go as real Return key presses; everything else as text.
        let lines = text.components(separatedBy: "\n")
        for (lineIndex, line) in lines.enumerated() {
            let pieces = oneCharacterPerKeyPress ? line.map(String.init) : chunks(of: line, unitsPerChunk: unitsPerEvent)
            for chunk in pieces {
                let utf16Units = Array(chunk.utf16)
                guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else { return false }
                // No modifiers, even if a shortcut key is still physically down.
                keyDown.flags = []
                keyUp.flags = []
                keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
                keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
                keyDown.keyboardSetUnicodeString(stringLength: utf16Units.count, unicodeString: utf16Units)
                keyUp.keyboardSetUnicodeString(stringLength: utf16Units.count, unicodeString: utf16Units)
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: oneCharacterPerKeyPress ? 14_000_000 : 6_000_000)
            }
            if lineIndex < lines.count - 1 {
                pressKey(virtualKey: 36, flags: [], eventSource: eventSource)
                try? await Task.sleep(nanoseconds: 12_000_000)
            }
        }
        return true
    }

    /// Presses one key, with optional modifiers (for example Return, or Command + A).
    static func pressKey(virtualKey: CGKeyCode, flags: CGEventFlags, eventSource: CGEventSource? = CGEventSource(stateID: .combinedSessionState)) {
        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: virtualKey, keyDown: false) else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
