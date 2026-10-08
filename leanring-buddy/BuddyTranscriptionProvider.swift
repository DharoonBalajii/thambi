//
//  BuddyTranscriptionProvider.swift
//  leanring-buddy
//
//  Shared protocol surface for voice transcription backends.
//

import AVFoundation
import Foundation

protocol BuddyStreamingTranscriptionSession: AnyObject {
    var finalTranscriptFallbackDelaySeconds: TimeInterval { get }
    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer)
    func requestFinalTranscript()
    func cancel()
}

protocol BuddyTranscriptionProvider {
    var displayName: String { get }
    var requiresSpeechRecognitionPermission: Bool { get }
    var isConfigured: Bool { get }
    var unavailableExplanation: String? { get }

    func startStreamingSession(
        keyterms: [String],
        onTranscriptUpdate: @escaping (String) -> Void,
        onFinalTranscriptReady: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws -> any BuddyStreamingTranscriptionSession
}

enum BuddyTranscriptionProviderFactory {
    private enum PreferredProvider: String {
        case assemblyAI = "assemblyai"
        case appleSpeech = "apple"
    }

    static func makeDefaultProvider() -> any BuddyTranscriptionProvider {
        let provider = resolveProvider()
        print("🎙️ Transcription: using \(provider.displayName)")
        return provider
    }

    /// AssemblyAI by default. Apple's on-device speech (nothing leaves the Mac) when chosen in
    /// Info.plist, or automatically when no AssemblyAI key is in the Keychain.
    private static func resolveProvider() -> any BuddyTranscriptionProvider {
        let preferredProvider = AppBundleConfiguration
            .stringValue(forKey: "VoiceTranscriptionProvider")
            .flatMap { PreferredProvider(rawValue: $0.lowercased()) }

        if preferredProvider == .appleSpeech || ThambiKeychain.read(.assemblyAI) == nil {
            return AppleSpeechTranscriptionProvider()
        }
        return AssemblyAIStreamingTranscriptionProvider()
    }
}
