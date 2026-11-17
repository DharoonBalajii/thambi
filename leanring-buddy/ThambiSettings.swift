//
//  ThambiSettings.swift
//  leanring-buddy
//
//  Small everyday settings chosen in the menu bar panel: how fast the voice talks and whether
//  captions are shown. Stored in UserDefaults on this Mac only.
//
//  Pure Foundation, no UI, so it can be unit-tested on its own.
//

import Foundation

enum ThambiSettings {

    // MARK: - Voice speed

    static let minimumVoiceSpeed = 0.5
    static let maximumVoiceSpeed = 1.5
    static let voiceSpeedStep = 0.1
    static let defaultVoiceSpeed = 1.0
    private static let voiceSpeedKey = "voiceSpeedMultiplier"

    /// Keeps a speed inside 0.5x–1.5x and snaps it to one decimal place (0.1 steps).
    static func clampedVoiceSpeed(_ speed: Double) -> Double {
        guard speed.isFinite else { return defaultVoiceSpeed }
        let snapped = (speed / voiceSpeedStep).rounded() * voiceSpeedStep
        return min(maximumVoiceSpeed, max(minimumVoiceSpeed, (snapped * 10).rounded() / 10))
    }

    /// "1.0x", "0.8x", "1.5x"
    static func voiceSpeedLabel(_ speed: Double) -> String {
        String(format: "%.1fx", clampedVoiceSpeed(speed))
    }

    /// 1.0 = Thambi's normal pace. Applied to the voice as it plays (pitch stays the same).
    static var voiceSpeed: Double {
        get {
            guard UserDefaults.standard.object(forKey: voiceSpeedKey) != nil else { return defaultVoiceSpeed }
            return clampedVoiceSpeed(UserDefaults.standard.double(forKey: voiceSpeedKey))
        }
        set { UserDefaults.standard.set(clampedVoiceSpeed(newValue), forKey: voiceSpeedKey) }
    }

    // MARK: - Study mode

    private static let studyModeKey = "studyMode"
    static let studyModeChangedNotification = Notification.Name("ThambiStudyModeChanged")

    /// Read, Write or Restricted. Write by default, which keeps every feature on.
    static var studyMode: StudyMode {
        get { UserDefaults.standard.string(forKey: studyModeKey).flatMap(StudyMode.init(rawValue:)) ?? .write }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: studyModeKey)
            NotificationCenter.default.post(name: studyModeChangedNotification, object: nil)
        }
    }

    // MARK: - Appearance

    enum Appearance: String, CaseIterable {
        case system, light, dark
        var title: String {
            switch self {
            case .system: return "Auto"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    private static let appearanceKey = "appAppearance"

    /// Light, dark, or whatever the Mac is set to. The things Thambi draws over your screen
    /// (pointer, captions, drawings) stay dark either way so they read on any background.
    static var appearance: Appearance {
        get { UserDefaults.standard.string(forKey: appearanceKey).flatMap(Appearance.init(rawValue:)) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: appearanceKey) }
    }

    // MARK: - Captions

    private static let captionsKey = "captionsEnabled"

    /// Show what Thambi is saying as text at the bottom of the screen. Off by default.
    static var captionsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: captionsKey) }
        set { UserDefaults.standard.set(newValue, forKey: captionsKey) }
    }

    // MARK: - Interrupt by talking

    private static let bargeInKey = "bargeInEnabled"

    /// Stop the voice when you start talking over it. Off by default: it opens the microphone
    /// while Thambi speaks (the sound is only measured for loudness on this Mac, never kept or sent).
    static var bargeInEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: bargeInKey) }
        set { UserDefaults.standard.set(newValue, forKey: bargeInKey) }
    }

    // MARK: - Typing by voice

    private static let dictationLanguageKey = "dictationLanguageIdentifier"

    /// The language used when typing by voice, for example "en-IN". Empty follows the Mac's language.
    static var dictationLanguageIdentifier: String {
        get { UserDefaults.standard.string(forKey: dictationLanguageKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: dictationLanguageKey) }
    }

    // MARK: - Computer control

    private static let computerControlKey = "computerControlEnabled"
    private static let controlApprovalModeKey = "computerControlApprovalMode"

    /// Let Thambi click and type for you when you ask it to do something. Off by default.
    static var computerControlEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: computerControlKey) }
        set { UserDefaults.standard.set(newValue, forKey: computerControlKey) }
    }

    /// How often Thambi asks before acting. Every step unless you choose otherwise.
    static var controlApprovalMode: ControlApprovalMode {
        get { UserDefaults.standard.string(forKey: controlApprovalModeKey).flatMap(ControlApprovalMode.init(rawValue:)) ?? .everyStep }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: controlApprovalModeKey) }
    }

    private static let controlStepsVisibleKey = "computerControlStepsVisible"

    /// Show the card with each step while Thambi works. On by default; when off the card only
    /// appears for a step that needs your go-ahead.
    static var controlStepsVisible: Bool {
        get { UserDefaults.standard.object(forKey: controlStepsVisibleKey) == nil ? true : UserDefaults.standard.bool(forKey: controlStepsVisibleKey) }
        set { UserDefaults.standard.set(newValue, forKey: controlStepsVisibleKey) }
    }

    // MARK: - Cost

    /// Longer side of the screenshot sent with a question. An image is billed by its area:
    /// 1280 wide costs about 1,400 tokens, 1152 about 1,150. Measured on a real screen: small grey
    /// text and pointing stayed right at 1152 and 1024, pointing broke at 896.
    static let questionScreenshotMaxDimension = 1152
    /// Computer control steps name what they click and are corrected by accessibility, so they can
    /// use a smaller picture still.
    static let controlScreenshotMaxDimension = 1024
    /// Earlier answers are re-sent with every question. Long ones (notes, drafts) are shortened
    /// in that history so one big answer does not make every later question dearer.
    static let maximumHistoryAnswerCharacters = 600

    static func shortenedForHistory(_ answer: String) -> String {
        guard answer.count > maximumHistoryAnswerCharacters else { return answer }
        return String(answer.prefix(maximumHistoryAnswerCharacters)) + " ... (shortened)"
    }

    private static let questionSpeechOnDeviceKey = "questionSpeechOnDevice"

    /// Turn spoken questions into text on this Mac (free) instead of the cloud service (billed by
    /// the minute, more accurate). Off by default.
    static var questionSpeechOnDevice: Bool {
        get { UserDefaults.standard.bool(forKey: questionSpeechOnDeviceKey) }
        set { UserDefaults.standard.set(newValue, forKey: questionSpeechOnDeviceKey) }
    }

    // MARK: - Typed questions

    /// A typed question is capped so one paste can't run up cost.
    static let maximumTypedQuestionLength = 2000

    /// Trims a typed question and caps its length. Nil when there is nothing to ask.
    static func preparedTypedQuestion(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumTypedQuestionLength))
    }
}
