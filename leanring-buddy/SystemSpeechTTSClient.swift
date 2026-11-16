//
//  SystemSpeechTTSClient.swift
//  leanring-buddy
//
//  LOCAL PATCH: replaces the ElevenLabs text-to-speech client. Speech now comes from a
//  free, on-device neural voice (Qwen3-TTS via a local server on 127.0.0.1:8789, see
//  ~/clicky/tts), played sentence by sentence with a short natural gap between them.
//  If that server isn't running or fails, it falls back to the built-in macOS voice, so
//  Clicky never goes silent.
//
//  Voice/cursor sync: the answer is passed in as segments. Each segment can carry a callback
//  that fires at the exact moment the voice starts saying that segment, which is how the
//  cursor points at an element just as the voice names it.
//

import AVFoundation
import Foundation

/// A piece of the spoken answer, with an optional callback fired when the voice starts saying it.
struct SpokenSegment {
    let text: String
    let onSegmentStartedSpeaking: (@MainActor () -> Void)?
}

@MainActor
final class SystemSpeechTTSClient: NSObject, AVSpeechSynthesizerDelegate {

    // MARK: - Local neural voice

    private static let localNeuralVoiceServerURL = URL(string: "http://127.0.0.1:8789/speak")!
    /// LOCAL: spoken answers must never be cached on disk (the default session did exactly that).
    private static let voiceServerSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
    private static let localNeuralVoiceWarmUpURL = URL(string: "http://127.0.0.1:8789/warm")!

    /// The voice server frees its model after a while without use, to save memory and battery.
    /// This asks it to load the model again, in the background, as soon as a question starts,
    /// so the voice is ready by the time the answer arrives. Sends nothing but the request itself.
    static func warmUpNeuralVoice() {
        var request = URLRequest(url: localNeuralVoiceWarmUpURL, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("1", forHTTPHeaderField: "x-thambi-client")
        voiceServerSession.dataTask(with: request).resume()
    }

    /// Pause after a finished sentence, and after a comma-split phrase (shorter, as in real speech).
    private static let gapAfterSentenceSeconds: TimeInterval = 0.28
    private static let gapAfterPhraseSeconds: TimeInterval = 0.12
    /// A long first sentence is split at a comma so the first audio starts sooner.
    private static let longFirstSentenceCharacterThreshold = 80
    private static let earliestFirstSentenceSplitCharacterOffset = 28

    private struct SpeechChunk {
        /// What the voice says (abbreviations spelled out: "E S P").
        let text: String
        /// What captions show for this chunk (the sentence as written: "ESP").
        let displayText: String
        let gapAfterSeconds: TimeInterval
        /// Fired the moment this chunk starts being spoken (only set on the first chunk of a segment).
        let onStartedSpeaking: (@MainActor () -> Void)?
    }

    private var neuralPlaybackTask: Task<Void, Never>?
    private var activeAudioPlayer: AVAudioPlayer?
    private var isNeuralPlaybackActive = false
    /// Bumped on every stop, so an older playback task that is still winding down can never
    /// clear the "playing" flag or swap the audio player of a newer one.
    private var neuralPlaybackGeneration = 0
    /// Called once when the whole answer has been spoken (not when it is interrupted).
    private var speechFinishedHandler: (@MainActor () -> Void)?

    /// Captions: called with the sentence the voice has just started saying, and with nil when
    /// speech ends or is stopped.
    var onCaptionChanged: (@MainActor (String?) -> Void)?

    /// The speed chosen in the panel (0.5x–1.5x), read live so a change applies mid-answer.
    private var playbackSpeed: Double { ThambiSettings.voiceSpeed }

    // MARK: - macOS voice (fallback)

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var utteranceStartCallbacks: [ObjectIdentifier: @MainActor () -> Void] = [:]

    /// Identity of the LAST utterance queued on the macOS voice, so a late "cancelled"
    /// callback from an interrupted older utterance can't clear the new one.
    private var activeUtteranceIdentifier: ObjectIdentifier?

    /// Best installed English voice: Premium > Enhanced > default quality.
    private let selectedVoice: AVSpeechSynthesisVoice? = {
        let preferredVoiceNamesInOrder = ["Ava", "Zoe", "Evan", "Nicky", "Samantha", "Daniel", "Tara", "Rishi"]
        let installedEnglishVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return installedEnglishVoices.max { firstVoice, secondVoice in
            if firstVoice.quality.rawValue != secondVoice.quality.rawValue {
                return firstVoice.quality.rawValue < secondVoice.quality.rawValue
            }
            let firstVoiceRank = preferredVoiceNamesInOrder.firstIndex(of: firstVoice.name) ?? Int.max
            let secondVoiceRank = preferredVoiceNamesInOrder.firstIndex(of: secondVoice.name) ?? Int.max
            return firstVoiceRank > secondVoiceRank
        }
    }()

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    // MARK: - Public interface

    /// Starts speaking the segments in order and returns once audio has begun (or the fallback
    /// voice has started); callers poll `isPlaying` to know when speech has finished.
    /// Each segment's callback fires at the moment the voice starts saying it.
    func speakSegments(
        _ segments: [SpokenSegment],
        onSpeechFinished: (@MainActor () -> Void)? = nil
    ) async throws {
        try Task.checkCancellation()
        stopPlayback()
        speechFinishedHandler = onSpeechFinished

        let speechChunks = Self.makeSpeechChunks(from: segments)
        guard let firstChunk = speechChunks.first else {
            speechFinishedHandler = nil
            onSpeechFinished?()
            return
        }

        do {
            let firstChunkAudioData = try await fetchNeuralVoiceAudio(for: firstChunk.text)
            try Task.checkCancellation()

            isNeuralPlaybackActive = true
            let remainingChunks = Array(speechChunks.dropFirst())
            let playbackGeneration = neuralPlaybackGeneration
            neuralPlaybackTask = Task { [weak self] in
                await self?.playNeuralVoiceChunks(
                    playbackGeneration: playbackGeneration,
                    firstChunk: firstChunk,
                    firstChunkAudioData: firstChunkAudioData,
                    remainingChunks: remainingChunks
                )
            }
            print("🔊 Neural voice: speaking \(speechChunks.count) chunk(s)")
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            print("⚠️ Neural voice unavailable (\(error.localizedDescription)); using the macOS voice instead")
            speakWithMacOSVoice(chunks: speechChunks)
        }
    }

    /// Whether anything is currently being spoken.
    var isPlaying: Bool {
        isNeuralPlaybackActive || activeUtteranceIdentifier != nil || speechSynthesizer.isSpeaking
    }

    /// Stops any in-progress speech immediately (an interrupted answer does not fire the finished handler).
    func stopPlayback() {
        neuralPlaybackGeneration += 1
        neuralPlaybackTask?.cancel()
        neuralPlaybackTask = nil
        activeAudioPlayer?.stop()
        activeAudioPlayer = nil
        isNeuralPlaybackActive = false
        speechFinishedHandler = nil

        activeUtteranceIdentifier = nil
        utteranceStartCallbacks.removeAll()
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        onCaptionChanged?(nil)
    }

    // MARK: - Neural voice playback

    /// Plays the first chunk right away, and meanwhile generates the next one, so speech flows
    /// with only the intended gap between chunks instead of waiting on the model each time.
    private func playNeuralVoiceChunks(
        playbackGeneration: Int,
        firstChunk: SpeechChunk,
        firstChunkAudioData: Data,
        remainingChunks: [SpeechChunk]
    ) async {
        defer {
            if neuralPlaybackGeneration == playbackGeneration { isNeuralPlaybackActive = false }
        }

        var currentChunk = firstChunk
        var currentAudioData = firstChunkAudioData
        var nextChunkIndex = 0
        var pendingNextAudioFetch = fetchInBackground(remainingChunks, index: nextChunkIndex)

        while !Task.isCancelled && neuralPlaybackGeneration == playbackGeneration {
            guard let audioPlayer = try? AVAudioPlayer(data: currentAudioData) else { return }
            activeAudioPlayer = audioPlayer
            // Speed is applied here, as the audio plays, so the pitch stays natural and a change
            // in the panel takes effect straight away.
            audioPlayer.enableRate = true
            audioPlayer.rate = Float(playbackSpeed)
            audioPlayer.play()
            // The voice has just started this chunk: this is the moment the cursor should move.
            currentChunk.onStartedSpeaking?()
            onCaptionChanged?(currentChunk.displayText)

            while audioPlayer.isPlaying && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 40_000_000)
                let wantedRate = Float(playbackSpeed)
                if audioPlayer.rate != wantedRate { audioPlayer.rate = wantedRate }
            }
            guard !Task.isCancelled, neuralPlaybackGeneration == playbackGeneration else { return }

            guard let upcomingAudioFetch = pendingNextAudioFetch else {
                // That was the last chunk: the whole answer has been spoken.
                let finishedHandler = speechFinishedHandler
                speechFinishedHandler = nil
                onCaptionChanged?(nil)
                finishedHandler?()
                return
            }

            // Pauses shrink or stretch with the speed, like the speech itself.
            try? await Task.sleep(nanoseconds: UInt64(currentChunk.gapAfterSeconds / playbackSpeed * 1_000_000_000))
            guard !Task.isCancelled, neuralPlaybackGeneration == playbackGeneration else { return }

            guard let upcomingAudioData = await upcomingAudioFetch.value else {
                // The server failed mid-answer: finish the rest with the macOS voice rather than going quiet.
                print("⚠️ Neural voice failed mid-answer; finishing with the macOS voice")
                speakWithMacOSVoice(chunks: Array(remainingChunks[nextChunkIndex...]))
                return
            }

            currentChunk = remainingChunks[nextChunkIndex]
            currentAudioData = upcomingAudioData
            nextChunkIndex += 1
            pendingNextAudioFetch = fetchInBackground(remainingChunks, index: nextChunkIndex)
        }
    }

    private func fetchInBackground(_ chunks: [SpeechChunk], index: Int) -> Task<Data?, Never>? {
        guard index < chunks.count else { return nil }
        let chunkText = chunks[index].text
        return Task { [weak self] in
            guard let self else { return nil }
            return try? await self.fetchNeuralVoiceAudio(for: chunkText)
        }
    }

    private func fetchNeuralVoiceAudio(for text: String) async throws -> Data {
        var request = URLRequest(url: Self.localNeuralVoiceServerURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("1", forHTTPHeaderField: "x-thambi-client") // local voice server guard
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])

        let (audioData, response) = try await Self.voiceServerSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !audioData.isEmpty else {
            throw NSError(domain: "NeuralVoice", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "voice server returned an error"])
        }
        return audioData
    }

    // MARK: - Text splitting

    /// Turns segments into speakable chunks. Each segment's callback rides on its first chunk;
    /// a segment with no text carries its callback over to the next chunk so it still fires.
    private static func makeSpeechChunks(from segments: [SpokenSegment]) -> [SpeechChunk] {
        var speechChunks: [SpeechChunk] = []
        var carriedStartCallbacks: [@MainActor () -> Void] = []

        for (segmentIndex, segment) in segments.enumerated() {
            if let segmentCallback = segment.onSegmentStartedSpeaking {
                carriedStartCallbacks.append(segmentCallback)
            }

            let isFirstSegment = segmentIndex == 0
            var segmentChunks = splitIntoSpeechChunks(segment.text, splitLongFirstSentence: isFirstSegment)
            guard !segmentChunks.isEmpty else { continue }

            // The first chunk of this segment fires every callback waiting to be fired.
            let callbacksToFire = carriedStartCallbacks
            carriedStartCallbacks.removeAll()
            if !callbacksToFire.isEmpty {
                let firstSegmentChunk = segmentChunks[0]
                segmentChunks[0] = SpeechChunk(
                    text: firstSegmentChunk.text,
                    displayText: firstSegmentChunk.displayText,
                    gapAfterSeconds: firstSegmentChunk.gapAfterSeconds,
                    onStartedSpeaking: { callbacksToFire.forEach { $0() } }
                )
            }
            speechChunks.append(contentsOf: segmentChunks)
        }

        // Pause between segments like between sentences; nothing after the very last chunk.
        for chunkIndex in speechChunks.indices {
            let chunk = speechChunks[chunkIndex]
            let isLastChunk = chunkIndex == speechChunks.count - 1
            if isLastChunk {
                speechChunks[chunkIndex] = SpeechChunk(text: chunk.text, displayText: chunk.displayText, gapAfterSeconds: 0, onStartedSpeaking: chunk.onStartedSpeaking)
            } else if chunk.gapAfterSeconds == 0 {
                speechChunks[chunkIndex] = SpeechChunk(text: chunk.text, displayText: chunk.displayText, gapAfterSeconds: gapAfterSentenceSeconds, onStartedSpeaking: chunk.onStartedSpeaking)
            }
        }
        return speechChunks
    }

    /// Splits text into sentences (even lowercase ones). If asked, a long first sentence is cut at
    /// its first comma so audio can start sooner; commas are natural pause points, so it doesn't
    /// sound chopped.
    private static func splitIntoSpeechChunks(_ text: String, splitLongFirstSentence: Bool) -> [SpeechChunk] {
        // LOCAL: abbreviations are spoken letter by letter ("ESP" -> "E S P"); only the audio text changes.
        // Captions keep the sentence as written.
        func chunk(_ writtenText: String, gap: TimeInterval) -> SpeechChunk {
            SpeechChunk(text: SpeechAcronymSpeller.spelledOut(writtenText), displayText: writtenText, gapAfterSeconds: gap, onStartedSpeaking: nil)
        }
        let sentences = SpeechSentenceSplitter.sentences(in: text)
        var speechChunks: [SpeechChunk] = []

        for (sentenceIndex, sentence) in sentences.enumerated() {
            let gapAfterThisSentence = gapAfterSentenceSeconds

            if splitLongFirstSentence,
               sentenceIndex == 0,
               sentence.count > longFirstSentenceCharacterThreshold,
               let splitRange = commaSplitRange(in: sentence) {
                let leadingPhrase = String(sentence[..<splitRange.upperBound])
                    .trimmingCharacters(in: .whitespaces)
                let trailingPhrase = String(sentence[splitRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                if !leadingPhrase.isEmpty && !trailingPhrase.isEmpty {
                    speechChunks.append(chunk(leadingPhrase, gap: gapAfterPhraseSeconds))
                    speechChunks.append(chunk(trailingPhrase, gap: gapAfterThisSentence))
                    continue
                }
            }
            speechChunks.append(chunk(sentence, gap: gapAfterThisSentence))
        }
        return speechChunks
    }

    private static func commaSplitRange(in sentence: String) -> Range<String.Index>? {
        guard sentence.count > earliestFirstSentenceSplitCharacterOffset else { return nil }
        let searchStart = sentence.index(sentence.startIndex, offsetBy: earliestFirstSentenceSplitCharacterOffset)
        return sentence.range(of: ",", range: searchStart..<sentence.endIndex)
    }

    // MARK: - macOS voice fallback

    private func speakWithMacOSVoice(chunks: [SpeechChunk]) {
        var lastQueuedUtterance: AVSpeechUtterance?
        for chunk in chunks {
            let utterance = AVSpeechUtterance(string: chunk.text)
            utterance.voice = selectedVoice
            let speed = playbackSpeed
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                                 max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speed)))
            utterance.postUtteranceDelay = chunk.gapAfterSeconds / speed
            let chunkStartCallback = chunk.onStartedSpeaking
            let captionText = chunk.displayText
            utteranceStartCallbacks[ObjectIdentifier(utterance)] = { [weak self] in
                chunkStartCallback?()
                self?.onCaptionChanged?(captionText)
            }
            speechSynthesizer.speak(utterance)
            lastQueuedUtterance = utterance
        }
        activeUtteranceIdentifier = lastQueuedUtterance.map { ObjectIdentifier($0) }
        print("🔊 macOS speech fallback: speaking \(chunks.count) chunk(s) with \(selectedVoice?.name ?? "default voice")")
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let startedUtteranceIdentifier = ObjectIdentifier(utterance)
        Task { @MainActor in
            if let startCallback = self.utteranceStartCallbacks.removeValue(forKey: startedUtteranceIdentifier) {
                startCallback()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finishedUtteranceIdentifier = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.activeUtteranceIdentifier == finishedUtteranceIdentifier else { return }
            self.activeUtteranceIdentifier = nil
            let finishedHandler = self.speechFinishedHandler
            self.speechFinishedHandler = nil
            self.onCaptionChanged?(nil)
            finishedHandler?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let cancelledUtteranceIdentifier = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.utteranceStartCallbacks.removeValue(forKey: cancelledUtteranceIdentifier)
            if self.activeUtteranceIdentifier == cancelledUtteranceIdentifier {
                self.activeUtteranceIdentifier = nil
            }
        }
    }
}
