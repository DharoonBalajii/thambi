//
//  AppleSpeechTranscriptionProvider.swift
//  leanring-buddy
//
//  Local fallback transcription provider backed by Apple's Speech framework.
//

import AVFoundation
import Foundation
import Speech

struct AppleSpeechTranscriptionProviderError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

final class AppleSpeechTranscriptionProvider: BuddyTranscriptionProvider {
    let displayName = "Apple Speech"
    let requiresSpeechRecognitionPermission = true
    let isConfigured = true
    let unavailableExplanation: String? = nil

    /// When true the audio must be recognised on this Mac; it is never sent to Apple's servers.
    /// Used for typing by voice, where anything you say in any app could be dictated.
    private let requiresOnDeviceRecognition: Bool
    /// A fixed language (for example "en-IN"); nil follows the Mac's language.
    private let localeIdentifier: String?

    init(requiresOnDeviceRecognition: Bool = false, localeIdentifier: String? = nil) {
        self.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        self.localeIdentifier = localeIdentifier
    }

    func startStreamingSession(
        keyterms: [String],
        onTranscriptUpdate: @escaping (String) -> Void,
        onFinalTranscriptReady: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws -> any BuddyStreamingTranscriptionSession {
        guard let speechRecognizer = Self.makeBestAvailableSpeechRecognizer(
            localeIdentifier: localeIdentifier,
            requiresOnDeviceRecognition: requiresOnDeviceRecognition
        ) else {
            throw AppleSpeechTranscriptionProviderError(message: requiresOnDeviceRecognition
                ? "on-device dictation isn't set up for this language. turn on Dictation in System Settings > Keyboard, or pick another language."
                : "dictation is not available on this mac.")
        }

        return try AppleSpeechTranscriptionSession(
            speechRecognizer: speechRecognizer,
            keyterms: keyterms,
            onTranscriptUpdate: onTranscriptUpdate,
            onFinalTranscriptReady: onFinalTranscriptReady,
            onError: onError
        )
    }

    /// Languages offered in the panel: the Mac's own languages plus English, limited to what Apple Speech supports.
    static func selectableDictationLocaleIdentifiers() -> [String] {
        let supportedIdentifiers = Set(SFSpeechRecognizer.supportedLocales().map { $0.identifier.replacingOccurrences(of: "_", with: "-") })
        var wantedLanguageCodes = Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        wantedLanguageCodes += ["en", "hi"]
        let wanted = Set(wantedLanguageCodes)
        return supportedIdentifiers
            .filter { wanted.contains(Locale(identifier: $0).language.languageCode?.identifier ?? "") }
            .sorted { dictationLanguageName(for: $0) < dictationLanguageName(for: $1) }
    }

    /// "English (India)"
    static func dictationLanguageName(for localeIdentifier: String) -> String {
        Locale.current.localizedString(forIdentifier: localeIdentifier) ?? localeIdentifier
    }

    private static func makeBestAvailableSpeechRecognizer(
        localeIdentifier: String?,
        requiresOnDeviceRecognition: Bool
    ) -> SFSpeechRecognizer? {
        var preferredLocales: [Locale] = []
        if let localeIdentifier { preferredLocales.append(Locale(identifier: localeIdentifier)) }
        preferredLocales += [Locale.autoupdatingCurrent, Locale(identifier: "en-IN"), Locale(identifier: "en-US")]

        let availableRecognizers = preferredLocales.compactMap { SFSpeechRecognizer(locale: $0) }
        if requiresOnDeviceRecognition {
            return availableRecognizers.first(where: { $0.supportsOnDeviceRecognition })
        }
        return availableRecognizers.first ?? SFSpeechRecognizer()
    }
}

private final class AppleSpeechTranscriptionSession: NSObject, BuddyStreamingTranscriptionSession {
    let finalTranscriptFallbackDelaySeconds: TimeInterval = 1.8

    private let recognitionRequest: SFSpeechAudioBufferRecognitionRequest
    private var recognitionTask: SFSpeechRecognitionTask?
    private let onTranscriptUpdate: (String) -> Void
    private let onFinalTranscriptReady: (String) -> Void
    private let onError: (Error) -> Void

    private var latestRecognizedText = ""
    private var hasRequestedFinalTranscript = false
    private var hasDeliveredFinalTranscript = false

    init(
        speechRecognizer: SFSpeechRecognizer,
        keyterms: [String] = [],
        onTranscriptUpdate: @escaping (String) -> Void,
        onFinalTranscriptReady: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        self.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        self.onTranscriptUpdate = onTranscriptUpdate
        self.onFinalTranscriptReady = onFinalTranscriptReady
        self.onError = onError

        super.init()

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        recognitionRequest.addsPunctuation = true
        // Dictionary words and names: "expect to hear these".
        recognitionRequest.contextualStrings = Array(keyterms.prefix(100))

        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.handleRecognitionEvent(result: result, error: error)
        }
    }

    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer) {
        guard !hasRequestedFinalTranscript else { return }
        recognitionRequest.append(audioBuffer)
    }

    func requestFinalTranscript() {
        guard !hasRequestedFinalTranscript else { return }
        hasRequestedFinalTranscript = true
        recognitionRequest.endAudio()
    }

    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func handleRecognitionEvent(
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        if let result {
            latestRecognizedText = result.bestTranscription.formattedString
            onTranscriptUpdate(latestRecognizedText)

            if result.isFinal {
                deliverFinalTranscriptIfNeeded(latestRecognizedText)
                return
            }
        }

        guard let error else { return }

        if hasRequestedFinalTranscript && !latestRecognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deliverFinalTranscriptIfNeeded(latestRecognizedText)
        } else {
            onError(error)
        }
    }

    private func deliverFinalTranscriptIfNeeded(_ transcriptText: String) {
        guard !hasDeliveredFinalTranscript else { return }
        hasDeliveredFinalTranscript = true
        onFinalTranscriptReady(transcriptText)
    }

    deinit {
        cancel()
    }
}
