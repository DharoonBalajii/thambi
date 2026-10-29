//
//  ThambiKeychain.swift
//  leanring-buddy
//
//  LOCAL ADDITION: API keys live in the macOS Keychain (encrypted, readable only by this app's
//  signature, only on this Mac, only while you are logged in) instead of a plain text file read by
//  a local proxy server. Keys are never printed or logged.
//
//  To add or change a key: put a file at ~/clicky/thambi-keys.env with lines like
//      OPENROUTER_API_KEY=...
//      ASSEMBLYAI_API_KEY=...
//  and open Thambi. It copies the keys into the Keychain and then DELETES that file, so keys never
//  stay on disk in plain text.
//

import Foundation
import Security

enum ThambiKeychain {
    enum KeyName: String, CaseIterable {
        case openRouter = "OPENROUTER_API_KEY"
        case assemblyAI = "ASSEMBLYAI_API_KEY"
    }

    private static let serviceName = "com.dharoon.thambi.api-keys"
    static let keyImportFilePath = NSHomeDirectory() + "/clicky/thambi-keys.env"

    /// Reads a key from the Keychain (nil if not stored).
    static func read(_ keyName: KeyName) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyName.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    /// Stores (or replaces) a key. Items are this-device-only and never synced to iCloud.
    @discardableResult
    static func save(_ value: String, for keyName: KeyName) -> Bool {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyName.rawValue
        ]
        SecItemDelete(identity as CFDictionary)
        var item = identity
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        item[kSecAttrLabel as String] = "Thambi \(keyName.rawValue)"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Imports keys from ~/clicky/thambi-keys.env (if present) into the Keychain, replacing any stored
    /// value, then deletes the file. Returns how many keys were imported.
    @discardableResult
    static func importFromKeyFileIfPresent() -> Int {
        guard let fileContents = try? String(contentsOfFile: keyImportFilePath, encoding: .utf8) else { return 0 }

        var importedCount = 0
        for line in fileContents.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[1].isEmpty, let keyName = KeyName(rawValue: parts[0]) else { continue }
            if save(parts[1], for: keyName) { importedCount += 1 }
        }
        // Only remove the file once every key in it is safely in the Keychain.
        if importedCount > 0 {
            try? FileManager.default.removeItem(atPath: keyImportFilePath)
        }
        return importedCount
    }
}
