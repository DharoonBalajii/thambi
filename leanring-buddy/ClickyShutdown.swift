//
//  ClickyShutdown.swift
//  leanring-buddy
//
//  LOCAL ADDITION: the logic behind the "Shut down & remove permissions" button.
//
//  1. Stops Thambi's local voice server.
//  2. Removes Thambi's macOS permissions (Screen Recording, Accessibility, Microphone, Input
//     Monitoring) with Apple's own `tccutil reset`, scoped to Thambi's bundle identifier only.
//  3. The caller then quits the app.
//
//  Nothing here takes user-supplied input: every command and argument is fixed (or a parameter
//  chosen by the app itself), and nothing is run through a shell.
//

import Foundation

enum ClickyShutdown {
    /// macOS privacy services Clicky uses. "All" is a final sweep for anything else granted to this app.
    static let permissionServicesToRemove = ["ScreenCapture", "Accessibility", "Microphone", "ListenEvent", "All"]

    struct StepResult {
        let description: String
        let succeeded: Bool
    }

    /// Command-line fragment that identifies Thambi's own voice server (started from ~/clicky/tts).
    /// Matching on this path means no other program on the Mac is touched.
    static func defaultHelperProcessPatterns() -> [String] {
        let clickyFolder = NSHomeDirectory() + "/clicky"
        return [clickyFolder + "/tts/venv"]
    }

    /// Asks every process whose command line contains one of the patterns to terminate.
    @discardableResult
    static func stopHelperProcesses(matching patterns: [String]) -> [StepResult] {
        patterns.map { pattern in
            // pkill treats the pattern as a regular expression: escape it so paths match literally.
            let literalPattern = NSRegularExpression.escapedPattern(for: pattern)
            let result = run("/usr/bin/pkill", ["-TERM", "-f", literalPattern])
            // pkill exits 0 if something was stopped, 1 if nothing matched (both are fine).
            return StepResult(description: "stop helper processes matching \(pattern)", succeeded: result.status == 0 || result.status == 1)
        }
    }

    /// Removes Clicky's permissions. Only this bundle identifier is affected.
    @discardableResult
    static func removePermissions(forBundleIdentifier bundleIdentifier: String) -> [StepResult] {
        permissionServicesToRemove.map { service in
            let result = run("/usr/bin/tccutil", ["reset", service, bundleIdentifier])
            return StepResult(description: "remove \(service) permission", succeeded: result.status == 0)
        }
    }

    /// Runs a program directly (no shell) and waits for it to finish.
    private static func run(_ executablePath: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
        } catch {
            return (-1, "failed to start: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
