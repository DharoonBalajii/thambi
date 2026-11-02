//
//  leanring_buddyApp.swift
//  leanring-buddy
//
//  Menu bar-only companion app. No dock icon, no main window — just an
//  always-available status item in the macOS menu bar. Clicking the icon
//  opens a floating panel with companion voice controls.
//

import SwiftUI

@main
struct leanring_buddyApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) var appDelegate

    var body: some Scene {
        // The app lives entirely in the menu bar panel managed by the AppDelegate.
        // This empty Settings scene satisfies SwiftUI's requirement for at least
        // one scene but is never shown (LSUIElement=true removes the app menu).
        Settings {
            EmptyView()
        }
    }
}

/// Manages the companion lifecycle: creates the menu bar panel and starts
/// the companion voice pipeline on launch.
@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarPanelManager: MenuBarPanelManager?
    private let companionManager = CompanionManager()
    private let voiceServerLauncher = VoiceServerLauncher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🎯 Thambi: Starting...")
        print("🎯 Thambi: Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")

        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 0])

        // LOCAL: API keys live in the Keychain. A ~/clicky/thambi-keys.env file, if present, is imported and deleted.
        let importedKeyCount = ThambiKeychain.importFromKeyFileIfPresent()
        if importedKeyCount > 0 { print("🔑 Imported \(importedKeyCount) API key(s) into the Keychain") }

        // LOCAL: opening Thambi also starts its local voice; quitting stops it.
        voiceServerLauncher.startIfNeeded()


        menuBarPanelManager = MenuBarPanelManager(companionManager: companionManager)
        companionManager.start()
        // Auto-open the panel if the user still needs to do something:
        // either they haven't onboarded yet, or permissions were revoked.
        if !companionManager.hasCompletedOnboarding || !companionManager.allPermissionsGranted {
            menuBarPanelManager?.showPanelOnLaunch()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        companionManager.stop()
        voiceServerLauncher.stop()
    }
}
