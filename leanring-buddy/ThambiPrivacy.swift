//
//  ThambiPrivacy.swift
//  leanring-buddy
//
//  The promises in the Privacy Policy that code has to keep:
//  • The policy and terms ship inside the app and must be agreed to before first use; a new
//    version asks again.
//  • The data folder and every file in it are readable only by this macOS user.
//

import Foundation
import SwiftUI

enum ThambiPrivacy {
    /// Raise this whenever Legal/PRIVACY.md or Legal/TERMS.md changes in a way people must see.
    static let currentVersion = 1
    private static let acceptedVersionKey = "acceptedLegalVersion"

    static var hasAcceptedCurrentVersion: Bool {
        UserDefaults.standard.integer(forKey: acceptedVersionKey) >= currentVersion
    }

    static func acceptCurrentVersion() {
        UserDefaults.standard.set(currentVersion, forKey: acceptedVersionKey)
    }

    enum Document: String, Identifiable {
        case privacy = "PRIVACY"
        case terms = "TERMS"
        var id: String { rawValue }
        var title: String { self == .privacy ? "Privacy Policy" : "Terms of Use" }

        var text: String {
            guard let url = Bundle.main.url(forResource: rawValue, withExtension: "md"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                return "This document is missing from the app. Read it in the project's Legal folder."
            }
            return text
        }
    }

    /// Owner-only permissions on the data folder (700) and everything in it (600 for files), so
    /// another account on the same Mac cannot read notes, messages or study history.
    nonisolated static func secureDataDirectory() {
        let fileManager = FileManager.default
        let base = StudyLibraryStore.baseDirectory
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        guard let walker = fileManager.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let url as URL in walker {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            try? fileManager.setAttributes([.posixPermissions: isDirectory ? 0o700 : 0o600], ofItemAtPath: url.path)
        }
    }
}

/// Shown before first use and whenever the policy version rises.
struct ConsentSheet: View {
    let onAgree: () -> Void
    @State private var openDocument: ThambiPrivacy.Document?

    private let points: [(icon: String, text: String)] = [
        ("internaldrive", "Your materials, notes, flashcards and messages stay on this Mac. Thambi has no accounts, no analytics and no server of its own."),
        ("text.bubble", "When you ask something, your question and the few passages it needs go to the AI service, with your own key."),
        ("mic", "A spoken question sends its audio to the speech service and one picture of your screen to the AI service. You can switch speech to on-device."),
        ("person.2", "Friends is off until you turn it on, and then works directly between Macs on the same network."),
        ("exclamationmark.triangle", "Answers come from an AI model and can be wrong. Check what matters, and follow your college's rules on your own work."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before you start")
                .font(DS.font(20, .semibold))
                .foregroundColor(DS.Colors.textPrimary)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: point.icon)
                            .font(.system(size: 14))
                            .foregroundColor(DS.Colors.cool)
                            .frame(width: 22)
                        Text(point.text)
                            .font(DS.font(13))
                            .foregroundColor(DS.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 8) {
                WindowButton(title: "Privacy Policy") { openDocument = .privacy }
                WindowButton(title: "Terms of Use") { openDocument = .terms }
            }
            Rectangle().fill(DS.Colors.borderSubtle).frame(height: 1)
            HStack {
                Text("By continuing you agree to both.")
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textTertiary)
                Spacer()
                WindowButton(title: "Quit") { NSApp.terminate(nil) }
                WindowButton(title: "Agree and continue", prominence: .primary) {
                    ThambiPrivacy.acceptCurrentVersion()
                    onAgree()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(DS.Colors.surface1)
        .interactiveDismissDisabled()
        .sheet(item: $openDocument) { document in
            LegalDocumentSheet(document: document) { openDocument = nil }
        }
    }
}

struct LegalDocumentSheet: View {
    let document: ThambiPrivacy.Document
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document.title)
                    .font(DS.font(15, .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Spacer()
                WindowButton(title: "Done", prominence: .primary, action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            Rectangle().fill(DS.Colors.borderSubtle).frame(height: 1)
            ScrollView {
                AnswerTextView(text: document.text)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 680, height: 620)
        .background(DS.Colors.background)
    }
}
