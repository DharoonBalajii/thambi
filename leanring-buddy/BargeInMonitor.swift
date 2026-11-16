//
//  BargeInMonitor.swift
//  leanring-buddy
//
//  Barge-in: start talking while Thambi is speaking and it stops.
//
//  • Off unless you turn on "Interrupt by talking" in the panel.
//  • While it is on, the microphone is open only while Thambi's voice is playing. The sound is
//    measured for loudness on this Mac and thrown away: it is never recorded, transcribed or sent
//    anywhere.
//  • macOS echo cancellation is used so Thambi's own voice coming out of the speakers does not
//    count as you talking.
//

import AVFoundation
import Foundation

/// The pure decision: has someone been talking for long enough? Unit-tested on its own.
nonisolated struct BargeInDetector {
    /// Loudness (0...1, root mean square) above which a buffer counts as speech.
    var speechLevelThreshold: Float = 0.035
    /// Speech has to continue this long, so a cough or a key press doesn't stop the answer.
    var requiredSpeechSeconds: Double = 0.35
    /// Short dips between syllables are forgiven for this long.
    var allowedGapSeconds: Double = 0.18
    /// Nothing counts during the first moment of playback, while echo cancellation settles.
    var settleSeconds: Double = 0.5

    private var elapsedSeconds: Double = 0
    private var speechSeconds: Double = 0
    private var gapSeconds: Double = 0

    /// Feed one buffer's loudness and length. Returns true when playback should stop.
    mutating func process(level: Float, bufferSeconds: Double) -> Bool {
        elapsedSeconds += bufferSeconds
        guard elapsedSeconds >= settleSeconds else { return false }
        if level >= speechLevelThreshold {
            speechSeconds += bufferSeconds
            gapSeconds = 0
        } else {
            gapSeconds += bufferSeconds
            if gapSeconds > allowedGapSeconds { speechSeconds = 0 }
        }
        return speechSeconds >= requiredSpeechSeconds
    }

    static func rootMeanSquare(of samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sumOfSquares: Float = 0
        for sample in samples { sumOfSquares += sample * sample }
        return (sumOfSquares / Float(samples.count)).squareRoot()
    }
}

@MainActor
final class BargeInMonitor {

    private var audioEngine: AVAudioEngine?
    private var onUserStartedTalking: (() -> Void)?
    /// Loudest level heard during the current answer (for the log, to help tune the threshold).
    private let peakLevel = PeakLevelBox()

    var isRunning: Bool { audioEngine != nil }

    /// Opens the microphone and calls back (once) when the user talks over the voice.
    func start(onUserStartedTalking: @escaping () -> Void) {
        guard audioEngine == nil, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        do {
            // Echo cancellation: removes what the Mac itself is playing from what the microphone hears.
            try inputNode.setVoiceProcessingEnabled(true)
            // Don't let voice processing turn Thambi's own voice (or your music) down.
            inputNode.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        } catch {
            print("🎤 Barge-in: echo cancellation unavailable (\(error.localizedDescription)); not listening")
            return
        }
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { return }

        let detectorBox = DetectorBox()
        let peakLevel = self.peakLevel
        peakLevel.reset()
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let level = BargeInDetector.rootMeanSquare(of: UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
            peakLevel.record(level)
            let bufferSeconds = Double(buffer.frameLength) / inputFormat.sampleRate
            guard detectorBox.process(level: level, bufferSeconds: bufferSeconds) else { return }
            Task { @MainActor in self?.userStartedTalking() }
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            print("🎤 Barge-in: microphone would not start (\(error.localizedDescription))")
            return
        }
        self.audioEngine = audioEngine
        self.onUserStartedTalking = onUserStartedTalking
    }

    func stop() {
        guard let audioEngine else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try? audioEngine.inputNode.setVoiceProcessingEnabled(false)
        self.audioEngine = nil
        onUserStartedTalking = nil
        print("🎤 Barge-in: stopped listening (loudest level heard \(String(format: "%.3f", peakLevel.value)))")
    }

    private func userStartedTalking() {
        guard let callback = onUserStartedTalking else { return }
        stop()
        callback()
    }
}

/// Lets the audio thread use the detector safely.
private final class DetectorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var detector = BargeInDetector()
    private var hasFired = false

    func process(level: Float, bufferSeconds: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasFired else { return false }
        hasFired = detector.process(level: level, bufferSeconds: bufferSeconds)
        return hasFired
    }
}

private final class PeakLevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0
    var value: Float { lock.lock(); defer { lock.unlock() }; return peak }
    func reset() { lock.lock(); peak = 0; lock.unlock() }
    func record(_ level: Float) { lock.lock(); if level > peak { peak = level }; lock.unlock() }
}
