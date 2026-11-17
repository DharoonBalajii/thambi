//
//  ThambiAppearance.swift
//  leanring-buddy
//
//  Applies the chosen appearance (Auto, Light, Dark) to the app's windows.
//

import AppKit

extension ThambiSettings {
    @MainActor
    static func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
