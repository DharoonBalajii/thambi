//
//  leanring_buddyApp.swift
//  leanring-buddy
//
//  Thambi is a full Mac app: a study window (Ask, Library, Notes) with a Dock icon, plus the
//  always-available buddy in the menu bar that you talk to while you work.
//

import SwiftUI

@main
struct leanring_buddyApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) var appDelegate

    var body: some Scene {
        // The study window is an AppKit window managed by the AppDelegate. Settings (⌘,) shows
        // the same controls as the menu bar panel.
        Settings {
            CompanionPanelView(companionManager: appDelegate.companionManager)
                .frame(width: 340)
                .preferredColorScheme(.dark)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Thambi Window") { appDelegate.showMainWindow() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

/// Manages the companion lifecycle: creates the menu bar panel and starts
/// the companion voice pipeline on launch.
@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarPanelManager: MenuBarPanelManager?
    let companionManager = CompanionManager()
    private let mainWindowController = MainWindowController()
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
        StudyLibraryStore.shared.loadIfNeeded()
        NotificationCenter.default.addObserver(forName: .thambiShowMainWindow, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showMainWindow() }
        }
        showMainWindow()
        #if DEBUG
        MainWindowDebug.runIfAsked(mainWindowController)
        #endif
    }

    func showMainWindow() {
        mainWindowController.show()
    }

    /// Clicking the Dock icon brings the study window back after it was closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    /// Closing the window keeps Thambi in the menu bar, ready to talk.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        companionManager.stop()
        voiceServerLauncher.stop()
    }
}

extension Notification.Name {
    static let thambiShowMainWindow = Notification.Name("ThambiShowMainWindow")
}
