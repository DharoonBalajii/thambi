//
//  CompanionManager.swift
//  leanring-buddy
//
//  Central state manager for the companion voice mode. Owns the push-to-talk
//  pipeline (dictation manager + global shortcut monitor + overlay) and
//  exposes observable voice state for the panel UI.
//

import AVFoundation
import Combine
import Foundation
import ScreenCaptureKit
import SwiftUI

enum CompanionVoiceState {
    case idle
    case listening
    case processing
    case responding
}

@MainActor
final class CompanionManager: ObservableObject {
    @Published private(set) var voiceState: CompanionVoiceState = .idle
    @Published private(set) var lastTranscript: String?
    @Published private(set) var currentAudioPowerLevel: CGFloat = 0
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var hasScreenRecordingPermission = false
    @Published private(set) var hasMicrophonePermission = false
    @Published private(set) var hasScreenContentPermission = false

    /// Screen location (global AppKit coords) of a detected UI element the
    /// buddy should fly to and point at. Parsed from Claude's response;
    /// observed by BlueCursorView to trigger the flight animation.
    @Published var detectedElementScreenLocation: CGPoint?
    /// The display frame (global AppKit coords) of the screen the detected
    /// element is on, so BlueCursorView knows which screen overlay should animate.
    @Published var detectedElementDisplayFrame: CGRect?
    /// LOCAL: busy-area map of the screen being pointed at, used to place the arrow and label where they hide the least.
    var detectedElementLayoutMap: ScreenBusynessMap?
    /// Custom speech bubble text for the pointing animation. When set,
    /// BlueCursorView uses this instead of a random pointer phrase.
    @Published var detectedElementBubbleText: String?

    // MARK: - Onboarding Prompt Bubble

    /// Text streamed character-by-character on the cursor after the welcome message.
    @Published var onboardingPromptText: String = ""
    @Published var onboardingPromptOpacity: Double = 0.0
    @Published var showOnboardingPrompt: Bool = false

    let buddyDictationManager = BuddyDictationManager()
    let globalPushToTalkShortcutMonitor = GlobalPushToTalkShortcutMonitor()
    let overlayWindowManager = OverlayWindowManager()
    // Response text is now displayed inline on the cursor overlay via
    // streamingResponseText, so no separate response overlay manager is needed.

    /// Base URL for the Cloudflare Worker proxy. All API requests route
    /// through this so keys never ship in the app binary.
    // LOCAL SETUP: points at `wrangler dev` running on this Mac (keys live in worker/.dev.vars).
    // LOCAL: no local proxy any more — Claude is called directly over HTTPS (key in the Keychain).
    private static let openRouterMessagesURL = "https://openrouter.ai/api/v1/messages"

    private lazy var claudeAPI: ClaudeAPI = {
        return ClaudeAPI(proxyURL: Self.openRouterMessagesURL, model: ClickyModelRouter.haikuModelID)
    }()

    private lazy var systemSpeechTTSClient: SystemSpeechTTSClient = {
        return SystemSpeechTTSClient()
    }()

    /// Conversation history so Claude remembers prior exchanges within a session.
    /// Each entry is the user's transcript and Claude's response.
    private var conversationHistory: [(userTranscript: String, assistantResponse: String)] = []

    /// The currently running AI response task, if any. Cancelled when the user
    /// speaks again so a new response can begin immediately.
    private var currentResponseTask: Task<Void, Never>?

    private var shortcutTransitionCancellable: AnyCancellable?
    private var voiceStateCancellable: AnyCancellable?
    private var audioPowerCancellable: AnyCancellable?
    private var accessibilityCheckTimer: Timer?
    private var pendingKeyboardShortcutStartTask: Task<Void, Never>?
    /// Scheduled hide for transient cursor mode — cancelled if the user
    /// speaks again before the delay elapses.
    private var transientHideTask: Task<Void, Never>?

    /// True when all three required permissions (accessibility, screen recording,
    /// microphone) are granted. Used by the panel to show a single "all good" state.
    var allPermissionsGranted: Bool {
        hasAccessibilityPermission && hasScreenRecordingPermission && hasMicrophonePermission && hasScreenContentPermission
    }

    /// Whether the blue cursor overlay is currently visible on screen.
    /// Used by the panel to show accurate status text ("Active" vs "Ready").
    @Published private(set) var isOverlayVisible: Bool = false

    /// LOCAL: model mode for voice responses. "auto" (default) uses Haiku for everyday
    /// questions and escalates to Sonnet only when needed (see ClickyModelRouter);
    /// or the user pins Haiku / Sonnet in the panel. Persisted to UserDefaults
    /// (new key, so any old pinned choice from before auto mode is ignored).
    @Published var selectedModel: String = UserDefaults.standard.string(forKey: "selectedModelMode") ?? ClickyModelRouter.autoModeIdentifier

    func setSelectedModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "selectedModelMode")
    }

    /// User preference for whether the Clicky cursor should be shown.
    /// When toggled off, the overlay is hidden and push-to-talk is disabled.
    /// Persisted to UserDefaults so the choice survives app restarts.
    @Published var isClickyCursorEnabled: Bool = UserDefaults.standard.object(forKey: "isClickyCursorEnabled") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "isClickyCursorEnabled")

    /// Whether the user has completed onboarding at least once. Persisted
    /// to UserDefaults so the Start button only appears on first launch.
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    func start() {
        refreshAllPermissions()
        print("🔑 Thambi start — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission), onboarded: \(hasCompletedOnboarding)")
        startPermissionPolling()
        bindVoiceStateObservation()
        bindAudioPowerLevel()
        bindShortcutTransitions()
        // Eagerly touch the Claude API so its TLS warmup handshake completes
        // well before the onboarding demo fires at ~40s into the video.
        _ = claudeAPI

        // If the user already completed onboarding AND all permissions are
        // still granted, show the cursor overlay immediately. If permissions
        // were revoked (e.g. signing change), don't show the cursor — the
        // panel will show the permissions UI instead.
        if hasCompletedOnboarding && allPermissionsGranted && isClickyCursorEnabled {
            overlayWindowManager.hasShownOverlayBefore = true
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true
        }
    }

    /// Called by BlueCursorView after the buddy finishes its pointing
    /// animation and returns to cursor-following mode.
    /// Triggers the onboarding sequence — dismisses the panel and restarts
    /// the overlay so the welcome animation plays.
    func triggerOnboarding() {
        // Post notification so the panel manager can dismiss the panel
        NotificationCenter.default.post(name: .clickyDismissPanel, object: nil)

        // Mark onboarding as completed so the Start button won't appear
        // again on future launches — the cursor will auto-show instead
        hasCompletedOnboarding = true


        // Show the overlay for the first time — isFirstAppearance triggers
        // the welcome animation and the onboarding hint
        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
        isOverlayVisible = true
    }

    func clearDetectedElementLocation() {
        detectedElementScreenLocation = nil
        detectedElementDisplayFrame = nil
        detectedElementBubbleText = nil
        detectedElementLayoutMap = nil
    }

    func stop() {
        globalPushToTalkShortcutMonitor.stop()
        buddyDictationManager.cancelCurrentDictation()
        overlayWindowManager.hideOverlay()
        transientHideTask?.cancel()

        currentResponseTask?.cancel()
        currentResponseTask = nil
        shortcutTransitionCancellable?.cancel()
        voiceStateCancellable?.cancel()
        audioPowerCancellable?.cancel()
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
    }

    func refreshAllPermissions() {
        let previouslyHadAccessibility = hasAccessibilityPermission
        let previouslyHadScreenRecording = hasScreenRecordingPermission
        let previouslyHadMicrophone = hasMicrophonePermission
        let previouslyHadAll = allPermissionsGranted

        let currentlyHasAccessibility = WindowPositionManager.hasAccessibilityPermission()
        hasAccessibilityPermission = currentlyHasAccessibility

        if currentlyHasAccessibility {
            globalPushToTalkShortcutMonitor.start()
        } else {
            globalPushToTalkShortcutMonitor.stop()
        }

        hasScreenRecordingPermission = WindowPositionManager.hasScreenRecordingPermission()

        let micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        hasMicrophonePermission = micAuthStatus == .authorized

        // Debug: log permission state on changes
        if previouslyHadAccessibility != hasAccessibilityPermission
            || previouslyHadScreenRecording != hasScreenRecordingPermission
            || previouslyHadMicrophone != hasMicrophonePermission {
            print("🔑 Permissions — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission)")
        }

        // Track individual permission grants as they happen
        if !previouslyHadAccessibility && hasAccessibilityPermission {
        }
        if !previouslyHadScreenRecording && hasScreenRecordingPermission {
        }
        if !previouslyHadMicrophone && hasMicrophonePermission {
        }
        // Screen content permission is persisted — once the user has approved the
        // SCShareableContent picker, we don't need to re-check it.
        if !hasScreenContentPermission {
            hasScreenContentPermission = UserDefaults.standard.bool(forKey: "hasScreenContentPermission")
        }

        if !previouslyHadAll && allPermissionsGranted {
        }
    }

    /// Triggers the macOS screen content picker by performing a dummy
    /// screenshot capture. Once the user approves, we persist the grant
    /// so they're never asked again during onboarding.
    @Published private(set) var isRequestingScreenContent = false

    func requestScreenContentPermission() {
        guard !isRequestingScreenContent else { return }
        isRequestingScreenContent = true
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    await MainActor.run { isRequestingScreenContent = false }
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = 320
                config.height = 240
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                // Verify the capture actually returned real content — a 0x0 or
                // fully-empty image means the user denied the prompt.
                let didCapture = image.width > 0 && image.height > 0
                print("🔑 Screen content capture result — width: \(image.width), height: \(image.height), didCapture: \(didCapture)")
                await MainActor.run {
                    isRequestingScreenContent = false
                    guard didCapture else { return }
                    hasScreenContentPermission = true
                    UserDefaults.standard.set(true, forKey: "hasScreenContentPermission")

                    // If onboarding was already completed, show the cursor overlay now
                    if hasCompletedOnboarding && allPermissionsGranted && !isOverlayVisible && isClickyCursorEnabled {
                        overlayWindowManager.hasShownOverlayBefore = true
                        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                        isOverlayVisible = true
                    }
                }
            } catch {
                print("⚠️ Screen content permission request failed: \(error)")
                await MainActor.run { isRequestingScreenContent = false }
            }
        }
    }

    // MARK: - Private

    /// Triggers the system microphone prompt if the user has never been asked.
    /// Once granted/denied the status sticks and polling picks it up.
    private func promptForMicrophoneIfNotDetermined() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.hasMicrophonePermission = granted
            }
        }
    }

    /// Polls all permissions frequently so the UI updates live after the
    /// user grants them in System Settings. Screen Recording is the exception —
    /// macOS requires an app restart for that one to take effect.
    private func startPermissionPolling() {
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllPermissions()
            }
        }
    }

    private func bindAudioPowerLevel() {
        audioPowerCancellable = buddyDictationManager.$currentAudioPowerLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] powerLevel in
                self?.currentAudioPowerLevel = powerLevel
            }
    }

    private func bindVoiceStateObservation() {
        voiceStateCancellable = buddyDictationManager.$isRecordingFromKeyboardShortcut
            .combineLatest(
                buddyDictationManager.$isFinalizingTranscript,
                buddyDictationManager.$isPreparingToRecord
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording, isFinalizing, isPreparing in
                guard let self else { return }
                // Don't override .responding — the AI response pipeline
                // manages that state directly until streaming finishes.
                guard self.voiceState != .responding else { return }

                if isFinalizing {
                    self.voiceState = .processing
                } else if isRecording {
                    self.voiceState = .listening
                } else if isPreparing {
                    self.voiceState = .processing
                } else {
                    self.voiceState = .idle
                    // If the user pressed and released the hotkey without
                    // saying anything, no response task runs — schedule the
                    // transient hide here so the overlay doesn't get stuck.
                    // Only do this when no response is in flight, otherwise
                    // the brief idle gap between recording and processing
                    // would prematurely hide the overlay.
                    if self.currentResponseTask == nil {
                        self.scheduleTransientHideIfNeeded()
                    }
                }
            }
    }

    private func bindShortcutTransitions() {
        shortcutTransitionCancellable = globalPushToTalkShortcutMonitor
            .shortcutTransitionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transition in
                self?.handleShortcutTransition(transition)
            }
    }

    private func handleShortcutTransition(_ transition: BuddyPushToTalkShortcut.ShortcutTransition) {
        switch transition {
        case .pressed:
            guard !buddyDictationManager.isDictationInProgress else { return }

            // Cancel any pending transient hide so the overlay stays visible
            transientHideTask?.cancel()
            transientHideTask = nil

            // If the cursor is hidden, bring it back transiently for this interaction
            if !isClickyCursorEnabled && !isOverlayVisible {
                overlayWindowManager.hasShownOverlayBefore = true
                overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                isOverlayVisible = true
            }

            // Dismiss the menu bar panel so it doesn't cover the screen
            NotificationCenter.default.post(name: .clickyDismissPanel, object: nil)

            // Cancel any in-progress response and TTS from a previous utterance
            currentResponseTask?.cancel()
            systemSpeechTTSClient.stopPlayback()
            clearDetectedElementLocation()

            // Dismiss the onboarding prompt if it's showing
            if showOnboardingPrompt {
                withAnimation(.easeOut(duration: 0.3)) {
                    onboardingPromptOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.showOnboardingPrompt = false
                    self.onboardingPromptText = ""
                }
            }
    


            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = Task {
                await buddyDictationManager.startPushToTalkFromKeyboardShortcut(
                    currentDraftText: "",
                    updateDraftText: { _ in
                        // Partial transcripts are hidden (waveform-only UI)
                    },
                    submitDraftText: { [weak self] finalTranscript in
                        self?.lastTranscript = finalTranscript
                        print("🗣️ Companion received transcript: \(finalTranscript)")
                        self?.sendTranscriptToClaudeWithScreenshot(transcript: finalTranscript)
                    }
                )
            }
        case .released:
            // Cancel the pending start task in case the user released the shortcut
            // before the async startPushToTalk had a chance to begin recording.
            // Without this, a quick press-and-release drops the release event and
            // leaves the waveform overlay stuck on screen indefinitely.
            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = nil
            buddyDictationManager.stopPushToTalkFromKeyboardShortcut()
        case .none:
            break
        }
    }

    // MARK: - Companion Prompt

    private static let companionVoiceResponseSystemPrompt = """
    you're thambi, a friendly always-on study buddy that lives in the user's menu bar. the user just spoke to you via push-to-talk and you can see their screen(s). your reply will be spoken aloud via text-to-speech, so write the way you'd actually talk. this is an ongoing conversation — you remember everything they've said before.

    rules:
    - default to one or two sentences. be direct and dense. BUT if the user asks you to explain more, go deeper, or elaborate, then go all out — give a thorough, detailed explanation with no length limit.
    - all lowercase, casual, warm. no emojis.
    - the one exception to lowercase: write EVERY acronym and abbreviation in capital letters, like TCP, ESP, IKE, SMTP, RFC, API, RAM, so the voice can spell it out letter by letter. never write an acronym in lowercase, even if the user said it in lowercase or the screen shows it in lowercase (write POP3 and IMAP, not pop3 and imap). don't capitalize anything else. put digits right after the letters, like POP3.
    - write for the ear, not the eye. short sentences. no lists, bullet points, markdown, or formatting — just natural speech.
    - don't use abbreviations or symbols that sound weird read aloud. write "for example" not "e.g.", spell out small numbers.
    - if the user's question relates to what's on their screen, reference specific things you see.
    - if the screenshot doesn't seem relevant to their question, just answer the question directly.
    - you can help with anything — coding, writing, general knowledge, brainstorming.
    - never say "simply" or "just".
    - don't read out code verbatim. describe what the code does or what needs to change conversationally.
    - focus on giving a thorough, useful explanation. don't end with simple yes/no questions like "want me to explain more?" or "should i show you?" — those are dead ends that force the user to just say yes.
    - instead, when it fits naturally, end by planting a seed — mention something bigger or more ambitious they could try, a related concept that goes deeper, or a next-level technique that builds on what you just explained. make it something worth coming back for, not a question they'd just nod to. it's okay to not end with anything extra if the answer is complete on its own.
    - if you receive multiple screen images, the one labeled "primary focus" is where the cursor is — prioritize that one but reference others if relevant.

    element pointing:
    you have a small blue triangle cursor that can fly to and point at things on screen, drawing an arrow at them. pointing is your best feature, so use it every single time you have a chance: whenever your answer refers to anything specific that is visible on screen — a heading, part of a diagram, a label, a number, a formula, a bullet, a button, a menu, a window — point at it. it makes your help far more useful and concrete.

    this includes explanations. when you explain a slide, page, document, diagram or screen, walk through its important parts in order and point at each part right as you talk about it, for the whole answer, however long it gets. do NOT point at one thing near the start and then stop: keep pointing at each new thing you mention until you finish your last sentence. only skip pointing when nothing on screen relates to the question at all (a pure general-knowledge question, or small talk).

    when you point, put a coordinate tag RIGHT AFTER the sentence that talks about that element, so the cursor moves at the exact moment you say it (your voice and the cursor must stay in step). the screenshot images are labeled with their pixel dimensions. use those dimensions as the coordinate space. the origin (0,0) is the top-left corner of the image. x increases rightward, y increases downward.

    format: [POINT:x,y:label] where x,y are integer pixel coordinates in the screenshot's coordinate space, and label is a short 1-3 word description of the element (like "search bar" or "save button"). if the element is on the cursor's screen you can omit the screen number. if the element is on a DIFFERENT screen, append :screenN where N is the screen number from the image label (e.g. :screen2). this is important — without the screen number, the cursor will point at the wrong place.

    if the user asks about two or more things on screen (for example "show me the title and the graph", or "which one is on the left and which is on the right"), point at EACH of them: give each element its own sentence, in the order you mention them, and put that element's tag right after its sentence, like "the first thing is over here. [POINT:200,300:first thing] the second thing is over there. [POINT:900,400:second thing]". use one tag for every distinct thing you refer to, up to eight in one answer. never put several tags together at the end, and never leave out one of the things you mention. if you only point at one thing, put its tag right after the sentence that names it (usually your first sentence), then keep explaining after the tag.

    if pointing wouldn't help, append [POINT:none].

    examples:
    - user asks how to color grade in final cut: "you'll want to open the color inspector — it's right up in the top right area of the toolbar. [POINT:1100,42:color inspector] click that and you'll get all the color wheels and curves."
    - user asks what html is: "html stands for hypertext markup language, it's basically the skeleton of every web page. curious how it connects to the css you're looking at? [POINT:none]"
    - user asks how to commit in xcode: "see that source control menu up top? [POINT:285,11:source control] click that and hit commit, or you can use command option c as a shortcut."
    - element is on screen 2 (not where cursor is): "that's over on your other monitor — see the terminal window? [POINT:400,300:terminal:screen2]"
    - user asks to see two things: "sure. first up top is the title. [POINT:640,45:title] and then down on the right is the graph it describes. [POINT:960,420:graph]"
    - user asks you to explain a slide: "this slide is about how email travels between two people. up top the title says it's one picture of who speaks which protocol. [POINT:640,45:title] in the middle, alice's mail goes through her server to a gateway and then to bob's server. [POINT:700,300:mail path] the box on the left explains what a mail reader does. [POINT:200,560:mail reader box] and the dark bar at the bottom gives the key takeaway, that sending always uses smtp. [POINT:640,720:takeaway]"
    """

    // MARK: - AI Response Pipeline

    /// Captures a screenshot, sends it along with the transcript to Claude,
    /// and plays the response aloud via ElevenLabs TTS. The cursor stays in
    /// the spinner/processing state until TTS audio begins playing.
    /// Claude's response may include a [POINT:x,y:label] tag which triggers
    /// the buddy to fly to that element on screen.
    private func sendTranscriptToClaudeWithScreenshot(transcript: String) {
        currentResponseTask?.cancel()
        systemSpeechTTSClient.stopPlayback()
        pendingSpeechSyncedPointTargetCount = 0

        currentResponseTask = Task {
            // Stay in processing (spinner) state — no streaming text displayed
            voiceState = .processing

            do {
                // Capture all connected screens so the AI has full context
                let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

                // LOCAL: while Claude is thinking, work out where the busy (text-heavy) parts of each
                // screen are, so the pointing arrow and label can sit where they hide the least.
                let busynessMapsTask = Task.detached(priority: .userInitiated) {
                    screenCaptures.map { screenCapture in
                        ScreenBusynessMap(
                            imageData: screenCapture.imageData,
                            screenSizeInPoints: CGSize(width: screenCapture.displayWidthInPoints, height: screenCapture.displayHeightInPoints)
                        )
                    }
                }

                guard !Task.isCancelled else { return }

                // Build image labels with the actual screenshot pixel dimensions
                // so Claude's coordinate space matches the image it sees. We
                // scale from screenshot pixels to display points ourselves.
                let labeledImages = screenCaptures.map { capture in
                    let dimensionInfo = " (image dimensions: \(capture.screenshotWidthInPixels)x\(capture.screenshotHeightInPixels) pixels)"
                    return (data: capture.imageData, label: capture.label + dimensionInfo)
                }

                // Pass conversation history so Claude remembers prior exchanges
                let historyForAPI = conversationHistory.map { entry in
                    (userPlaceholder: entry.userTranscript, assistantResponse: entry.assistantResponse)
                }

                // LOCAL: pick Haiku (cheap) or Sonnet (only when the question needs it) per question.
                let modelDecision = ClickyModelRouter.chooseModel(forTranscript: transcript, selectedMode: selectedModel)
                claudeAPI.model = modelDecision.modelID
                print("🧭 Model routing: \(modelDecision.modelID) — \(modelDecision.reason)")

                let (fullResponseText, _) = try await claudeAPI.analyzeImageStreaming(
                    images: labeledImages,
                    systemPrompt: Self.companionVoiceResponseSystemPrompt,
                    conversationHistory: historyForAPI,
                    userPrompt: transcript,
                    onTextChunk: { _ in
                        // No streaming text display — spinner stays until TTS plays
                    }
                )

                guard !Task.isCancelled else { return }

                // Parse the [POINT:...] tag from Claude's response
                let parseResult = Self.parsePointingCoordinates(from: fullResponseText)
                let spokenText = parseResult.spokenText

                // LOCAL: pointing is now synced to the voice. Targets are resolved here, but the cursor
                // only moves when the voice reaches the sentence that mentions each one (so the arrow
                // lands as you hear "...and the graph is here", not 2 seconds before you hear anything).
                let busynessMaps = await busynessMapsTask.value
                let speechSegmentsToSpeak: [SpokenSegment] = parseResult.speechSegments.map { speechSegment in
                    guard let pointTarget = speechSegment.target,
                          let resolvedTarget = Self.resolvePointTarget(pointTarget, screenCaptures: screenCaptures, busynessMaps: busynessMaps) else {
                        return SpokenSegment(text: speechSegment.text, onSegmentStartedSpeaking: nil)
                    }
                    return SpokenSegment(text: speechSegment.text, onSegmentStartedSpeaking: { [weak self] in
                        self?.pointAtTargetAsVoiceReachesIt(resolvedTarget)
                    })
                }
                let syncedTargetLabels = parseResult.speechSegments.compactMap { $0.target.map { "\"\($0.label ?? "element")\"" } }
                pendingSpeechSyncedPointTargetCount = syncedTargetLabels.count
                print("🎯 Element pointing: \(syncedTargetLabels.count) target(s) synced to the voice \(syncedTargetLabels.joined(separator: " → "))")

                // Save this exchange to conversation history (with the point tag
                // stripped so it doesn't confuse future context)
                conversationHistory.append((
                    userTranscript: transcript,
                    assistantResponse: spokenText
                ))

                // Keep only the last 10 exchanges to avoid unbounded context growth
                if conversationHistory.count > 10 {
                    conversationHistory.removeFirst(conversationHistory.count - 10)
                }

                print("🧠 Conversation history: \(conversationHistory.count) exchanges")


                // Play the response via TTS. Keep the spinner (processing state)
                // until the audio actually starts playing, then switch to responding.
                if spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Nothing to say (tag-only answer): point right away instead of waiting for a voice.
                    speechSegmentsToSpeak.first(where: { $0.onSegmentStartedSpeaking != nil })?.onSegmentStartedSpeaking?()
                } else {
                    do {
                        try await systemSpeechTTSClient.speakSegments(
                            speechSegmentsToSpeak,
                            onSpeechFinished: { [weak self] in self?.pendingSpeechSyncedPointTargetCount = 0 }
                        )
                        // speakText returns after player.play() — audio is now playing
                        voiceState = .responding
                    } catch is CancellationError {
                        // The user spoke again while the voice was starting: an interruption, not an error.
                    } catch {
                        print("⚠️ Voice error: \(error)")
                        speakErrorFallback()
                    }
                }
            } catch is CancellationError {
                // User spoke again — response was interrupted
            } catch let urlError as URLError where urlError.code == .cancelled {
                // The in-flight request was cancelled because the user spoke again; not an error.
            } catch {
                print("⚠️ Companion response error: \(error)")
                speakErrorFallback()
            }

            if !Task.isCancelled {
                voiceState = .idle
                scheduleTransientHideIfNeeded()
            }
        }
    }

    /// If the cursor is in transient mode (user toggled "Show Clicky" off),
    /// waits for TTS playback and any pointing animation to finish, then
    /// fades out the overlay after a 1-second pause. Cancelled automatically
    /// if the user starts another push-to-talk interaction.
    private func scheduleTransientHideIfNeeded() {
        guard !isClickyCursorEnabled && isOverlayVisible else { return }

        transientHideTask?.cancel()
        transientHideTask = Task {
            // Wait for TTS audio to finish playing
            while systemSpeechTTSClient.isPlaying {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            // Wait for pointing animation to finish (location is cleared
            // when the buddy flies back to the cursor)
            while detectedElementScreenLocation != nil {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            // Pause 1s after everything finishes, then fade out
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            overlayWindowManager.fadeOutAndHideOverlay()
            isOverlayVisible = false
        }
    }

    /// Speaks a short, neutral apology with the built-in macOS voice when getting or speaking an
    /// answer fails for a real reason (the actual error is printed to the log).
    private func speakErrorFallback() {
        let utterance = "Sorry, I couldn't get an answer just now. Please try again."
        let synthesizer = NSSpeechSynthesizer()
        synthesizer.startSpeaking(utterance)
        voiceState = .responding
    }

    // MARK: - Shut down completely (LOCAL ADDITION)

    /// The "Shut down & remove access" button: stops Thambi's voice server,
    /// removes Thambi's Screen Recording, Accessibility, Microphone and Input Monitoring permissions,
    /// and quits. Afterwards nothing of Clicky is running or allowed to see or hear anything; the next
    /// launch asks for the permissions again.
    func shutDownCompletelyAndRemovePermissions() {
        currentResponseTask?.cancel()
        systemSpeechTTSClient.stopPlayback()

        let helperResults = ClickyShutdown.stopHelperProcesses(matching: ClickyShutdown.defaultHelperProcessPatterns())
        let permissionResults = ClickyShutdown.removePermissions(forBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.dharoon.thambi")
        for result in helperResults + permissionResults {
            print("🔒 Shutdown: \(result.description) — \(result.succeeded ? "ok" : "FAILED")")
        }

        NSApp.terminate(nil)
    }

    // MARK: - Point Tag Parsing

    /// One element Claude wants to point at (LOCAL: Claude may now return several, in order).
    struct PointTarget {
        let coordinate: CGPoint
        let label: String?
        /// Which screen the coordinate refers to (1-based), or nil to default to cursor screen.
        let screenNumber: Int?
    }

    /// A piece of the spoken answer, optionally carrying a target to point at the moment the
    /// voice starts saying it (LOCAL: this is what keeps the cursor and the voice in sync).
    struct SpeechSegment {
        let text: String
        let target: PointTarget?
    }

    /// Result of parsing the [POINT:...] tag(s) from Claude's response.
    struct PointingParseResult {
        /// The response text with every [POINT:...] tag removed — this is what gets spoken.
        let spokenText: String
        /// The FIRST target's pixel coordinate, or nil if Claude said "none" or no tag was found.
        let coordinate: CGPoint?
        /// The FIRST target's label (e.g. "run button"), or "none".
        let elementLabel: String?
        /// The FIRST target's screen (1-based), or nil to default to cursor screen.
        let screenNumber: Int?
        /// LOCAL: any further targets, in the order Claude mentioned them.
        let additionalTargets: [PointTarget]
        /// LOCAL: the answer cut into voice-ordered pieces; each piece's target fires when the voice reaches it.
        let speechSegments: [SpeechSegment]
    }

    /// Maximum number of elements Clicky will point at for one answer.
    static let maximumPointTargetsPerAnswer = 8

    /// Parses every [POINT:x,y:label:screenN] / [POINT:none] tag in Claude's response, wherever it
    /// appears. Returns the spoken text (all tags removed), the targets, and the answer cut into
    /// segments so each target can be pointed at exactly when the voice reaches its sentence.
    static func parsePointingCoordinates(from responseText: String) -> PointingParseResult {
        func resultWithoutTargets(spokenText: String, elementLabel: String?) -> PointingParseResult {
            PointingParseResult(
                spokenText: spokenText, coordinate: nil, elementLabel: elementLabel, screenNumber: nil,
                additionalTargets: [],
                speechSegments: spokenText.isEmpty ? [] : [SpeechSegment(text: spokenText, target: nil)]
            )
        }

        // Match [POINT:none] or [POINT:123,456:label] or [POINT:123,456:label:screen2].
        // Groups: 2 = x, 3 = y, 4 = label, 5 = screen number (group 1 is the whole alternative).
        let pattern = #"\[POINT:(none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return resultWithoutTargets(spokenText: responseText, elementLabel: nil)
        }
        let fullRange = NSRange(responseText.startIndex..., in: responseText)
        let tagMatches = regex.matches(in: responseText, options: [], range: fullRange)

        guard !tagMatches.isEmpty else {
            // No tag found at all
            return resultWithoutTargets(spokenText: responseText, elementLabel: nil)
        }

        func tidied(_ text: String) -> String {
            text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 1. Walk the tags, cutting the text into (text before the tag, that tag's target) pieces.
        struct RawPiece {
            var text: String
            var target: PointTarget?
        }
        var rawPieces: [RawPiece] = []
        var pieceStart = responseText.startIndex
        var acceptedTargetCount = 0
        for tagMatch in tagMatches {
            guard let tagRange = Range(tagMatch.range, in: responseText) else { continue }
            let textBeforeTag = tidied(String(responseText[pieceStart..<tagRange.lowerBound]))
            pieceStart = tagRange.upperBound

            var target: PointTarget? = nil
            if acceptedTargetCount < maximumPointTargetsPerAnswer,
               let xRange = Range(tagMatch.range(at: 2), in: responseText),
               let yRange = Range(tagMatch.range(at: 3), in: responseText),
               let x = Double(responseText[xRange]),
               let y = Double(responseText[yRange]) {
                var elementLabel: String? = nil
                if let labelRange = Range(tagMatch.range(at: 4), in: responseText) {
                    elementLabel = String(responseText[labelRange]).trimmingCharacters(in: .whitespaces)
                }
                var screenNumber: Int? = nil
                if let screenRange = Range(tagMatch.range(at: 5), in: responseText) {
                    screenNumber = Int(responseText[screenRange])
                }
                target = PointTarget(coordinate: CGPoint(x: x, y: y), label: elementLabel, screenNumber: screenNumber)
                acceptedTargetCount += 1
            }
            rawPieces.append(RawPiece(text: textBeforeTag, target: target))
        }
        let trailingText = tidied(String(responseText[pieceStart...]))
        if !trailingText.isEmpty {
            rawPieces.append(RawPiece(text: trailingText, target: nil))
        }

        // 2. A tag with no sentence of its own (e.g. several tags stacked at the end) joins the
        //    previous piece; those stacked targets are then spread across that piece's sentences
        //    so the cursor still moves as the voice goes.
        struct Block {
            var text: String
            var targets: [PointTarget]
        }
        var blocks: [Block] = []
        for piece in rawPieces {
            if piece.text.isEmpty {
                guard let target = piece.target else { continue }
                if blocks.isEmpty {
                    blocks.append(Block(text: "", targets: [target]))
                } else {
                    blocks[blocks.count - 1].targets.append(target)
                }
            } else {
                blocks.append(Block(text: piece.text, targets: piece.target.map { [$0] } ?? []))
            }
        }

        var speechSegments: [SpeechSegment] = []
        for block in blocks {
            if block.targets.count <= 1 || block.text.isEmpty {
                speechSegments.append(SpeechSegment(text: block.text, target: block.targets.first))
                continue
            }
            var sentences = SpeechSentenceSplitter.sentences(in: block.text)
            if sentences.isEmpty { sentences = [block.text] }

            var targetBySentenceIndex: [Int: PointTarget] = [:]
            var nextFreeSentenceIndex = 0
            for (targetOffset, target) in block.targets.enumerated() {
                let evenlySpreadIndex = targetOffset * sentences.count / block.targets.count
                let chosenIndex = max(evenlySpreadIndex, nextFreeSentenceIndex)
                guard chosenIndex < sentences.count else {
                    print("⚠️ Pointing: more targets than sentences; dropping \"\(target.label ?? "element")\"")
                    continue
                }
                targetBySentenceIndex[chosenIndex] = target
                nextFreeSentenceIndex = chosenIndex + 1
            }
            for (sentenceIndex, sentence) in sentences.enumerated() {
                speechSegments.append(SpeechSegment(text: sentence, target: targetBySentenceIndex[sentenceIndex]))
            }
        }

        let pointTargets = speechSegments.compactMap { $0.target }
        let spokenText = tidied(speechSegments.map(\.text).filter { !$0.isEmpty }.joined(separator: " "))

        guard let firstTarget = pointTargets.first else {
            return PointingParseResult(
                spokenText: spokenText, coordinate: nil, elementLabel: "none", screenNumber: nil,
                additionalTargets: [], speechSegments: spokenText.isEmpty ? [] : [SpeechSegment(text: spokenText, target: nil)]
            )
        }
        return PointingParseResult(
            spokenText: spokenText,
            coordinate: firstTarget.coordinate,
            elementLabel: firstTarget.label,
            screenNumber: firstTarget.screenNumber,
            additionalTargets: Array(pointTargets.dropFirst()),
            speechSegments: speechSegments
        )
    }

    // MARK: - Multi-target pointing (LOCAL ADDITION)

    /// A point target already converted to real screen coordinates, ready for the overlay.
    struct ResolvedPointTarget {
        let globalLocation: CGPoint
        let displayFrame: CGRect
        let label: String?
        /// Where the busy parts of that screen are, for content-aware arrow placement (may be nil).
        let layoutMap: ScreenBusynessMap?
    }

    /// How many targets of the answer being spoken have not been pointed at yet. While this is above
    /// zero the overlay stays on the current target (instead of flying back) until the voice reaches the next one.
    private(set) var pendingSpeechSyncedPointTargetCount = 0

    var hasPendingSpeechSyncedPointTargets: Bool { pendingSpeechSyncedPointTargetCount > 0 }

    /// Called by the voice the moment it starts saying the sentence that mentions this target.
    private func pointAtTargetAsVoiceReachesIt(_ target: ResolvedPointTarget) {
        pendingSpeechSyncedPointTargetCount = max(0, pendingSpeechSyncedPointTargetCount - 1)
        detectedElementBubbleText = target.label
        detectedElementLayoutMap = target.layoutMap
        detectedElementScreenLocation = target.globalLocation
        detectedElementDisplayFrame = target.displayFrame
        print("🎯 Pointing at \"\(target.label ?? "element")\" as the voice reaches it")
    }

    /// Converts a point target (screenshot pixel space, top-left origin) into global AppKit screen
    /// coordinates, picking the screen Claude named or falling back to the cursor's screen.
    private static func resolvePointTarget(
        _ pointTarget: PointTarget,
        screenCaptures: [CompanionScreenCapture],
        busynessMaps: [ScreenBusynessMap?]
    ) -> ResolvedPointTarget? {
        let targetScreenIndex: Int? = {
            if let screenNumber = pointTarget.screenNumber,
               screenNumber >= 1 && screenNumber <= screenCaptures.count {
                return screenNumber - 1
            }
            return screenCaptures.firstIndex(where: { $0.isCursorScreen })
        }()
        guard let targetScreenIndex else { return nil }
        let targetScreenCapture = screenCaptures[targetScreenIndex]
        let layoutMap = targetScreenIndex < busynessMaps.count ? busynessMaps[targetScreenIndex] : nil

        // Claude's coordinates are in the screenshot's pixel space (top-left origin, e.g. 1280x831).
        // Scale to the display's point space (e.g. 1512x982), then convert to AppKit global coords.
        let screenshotWidth = CGFloat(targetScreenCapture.screenshotWidthInPixels)
        let screenshotHeight = CGFloat(targetScreenCapture.screenshotHeightInPixels)
        let displayWidth = CGFloat(targetScreenCapture.displayWidthInPoints)
        let displayHeight = CGFloat(targetScreenCapture.displayHeightInPoints)
        let displayFrame = targetScreenCapture.displayFrame

        // Clamp to screenshot coordinate space
        let clampedX = max(0, min(pointTarget.coordinate.x, screenshotWidth))
        let clampedY = max(0, min(pointTarget.coordinate.y, screenshotHeight))

        // Scale from screenshot pixels to display points
        let displayLocalX = clampedX * (displayWidth / screenshotWidth)
        let displayLocalY = clampedY * (displayHeight / screenshotHeight)

        // Convert from top-left origin (screenshot) to bottom-left origin (AppKit)
        let appKitY = displayHeight - displayLocalY

        return ResolvedPointTarget(
            globalLocation: CGPoint(x: displayLocalX + displayFrame.origin.x, y: appKitY + displayFrame.origin.y),
            displayFrame: displayFrame,
            label: pointTarget.label,
            layoutMap: layoutMap
        )
    }

    // MARK: - Onboarding Hint

    /// LOCAL: shown right after the welcome message (this replaces the intro video):
    /// "press control + option and introduce yourself".
    func showOnboardingHint() {
        startOnboardingPromptStream()
    }

    private func startOnboardingPromptStream() {
        let message = "press control + option and introduce yourself"
        onboardingPromptText = ""
        showOnboardingPrompt = true
        onboardingPromptOpacity = 0.0

        withAnimation(.easeIn(duration: 0.4)) {
            onboardingPromptOpacity = 1.0
        }

        var currentIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            guard currentIndex < message.count else {
                timer.invalidate()
                // Auto-dismiss after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    guard self.showOnboardingPrompt else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.onboardingPromptOpacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.showOnboardingPrompt = false
                        self.onboardingPromptText = ""
                    }
                }
                return
            }
            let index = message.index(message.startIndex, offsetBy: currentIndex)
            self.onboardingPromptText.append(message[index])
            currentIndex += 1
        }
    }
}
