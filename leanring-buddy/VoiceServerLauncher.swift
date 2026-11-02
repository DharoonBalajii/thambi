//
//  VoiceServerLauncher.swift
//  leanring-buddy
//
//  LOCAL ADDITION: opening Thambi starts its local voice (the Qwen3-TTS server in ~/clicky/tts)
//  and quitting Thambi stops it, so no Terminal is ever needed.
//
//  • Runs a fixed program with fixed arguments (no shell, no user input).
//  • The server listens on 127.0.0.1 only and runs fully offline (HF_HUB_OFFLINE=1).
//  • It is told Thambi's process ID and exits by itself if Thambi ever crashes, so it can't be left
//    running in the background.
//  • If the voice can't start, Thambi still works and speaks with the built-in macOS voice.
//

import Foundation

@MainActor
final class VoiceServerLauncher {
    static let voiceFolderPath = NSHomeDirectory() + "/clicky/tts"
    private static let healthURL = URL(string: "http://127.0.0.1:8789/health")!

    private var voiceServerProcess: Process?

    /// Starts the voice server unless one is already answering on its port.
    func startIfNeeded() {
        Task {
            if await Self.isVoiceServerResponding() {
                print("🔊 Voice server already running")
                return
            }
            launch()
        }
    }

    private func launch() {
        let pythonPath = Self.voiceFolderPath + "/venv/bin/python"
        let serverScriptPath = Self.voiceFolderPath + "/server.py"
        guard FileManager.default.isExecutableFile(atPath: pythonPath),
              FileManager.default.fileExists(atPath: serverScriptPath) else {
            print("⚠️ Voice server not installed at \(Self.voiceFolderPath); using the macOS voice")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-I", serverScriptPath, "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
        process.currentDirectoryURL = URL(fileURLWithPath: Self.voiceFolderPath)
        process.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin",
            "HF_HUB_OFFLINE": "1",
            "HF_HUB_DISABLE_TELEMETRY": "1",
            "TOKENIZERS_PARALLELISM": "false"
        ]
        // The server log holds only timings and text lengths, never what is said.
        let logPath = Self.voiceFolderPath + "/server.log"
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        if let logHandle = FileHandle(forWritingAtPath: logPath) {
            logHandle.seekToEndOfFile()
            process.standardOutput = logHandle
            process.standardError = logHandle
        }

        do {
            try process.run()
            voiceServerProcess = process
            print("🔊 Voice server starting (pid \(process.processIdentifier))")
        } catch {
            print("⚠️ Couldn't start the voice server: \(error.localizedDescription); using the macOS voice")
        }
    }

    /// Stops the voice server this app started (called when Thambi quits).
    func stop() {
        guard let process = voiceServerProcess, process.isRunning else { return }
        process.terminate()
        voiceServerProcess = nil
    }

    private static func isVoiceServerResponding() async -> Bool {
        var request = URLRequest(url: healthURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1.5)
        request.httpMethod = "GET"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        guard let (_, response) = try? await URLSession(configuration: configuration).data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
