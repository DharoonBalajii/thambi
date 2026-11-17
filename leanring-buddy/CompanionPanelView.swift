//
//  CompanionPanelView.swift
//  leanring-buddy
//
//  The menu bar panel. One job first: ask Thambi something. Everything else is a setting,
//  grouped into three sections that fold away.
//
//  Colour has meaning here. Amber is you: the one primary button, the choice you made, the thing
//  waiting for your go-ahead. Cool blue is Thambi: its face and what it is doing right now.
//  Numbers and keys that are read off the machine are set in the monospaced face.
//

import AVFoundation
import SwiftUI

extension Notification.Name {
    /// The panel's content changed height (a section opened, a row appeared): resize the window.
    static let thambiPanelContentHeightChanged = Notification.Name("thambiPanelContentHeightChanged")
}

struct CompanionPanelView: View {
    @ObservedObject var companionManager: CompanionManager

    @State private var typedQuestion = ""
    @FocusState private var isQuestionFieldFocused: Bool
    @AppStorage("panelSectionAnswersExpanded") private var isAnswersSectionExpanded = true
    @AppStorage("panelSectionVoiceExpanded") private var isVoiceSectionExpanded = false
    @AppStorage("panelSectionControlExpanded") private var isControlSectionExpanded = false
    @State private var dictationLocaleIdentifiers: [String] = []
    @State private var appearance = ThambiSettings.appearance
    @State private var studyMode: StudyMode = ThambiSettings.studyMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isReadyForEverydayUse: Bool {
        companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader

            permissionsCopySection
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            if isReadyForEverydayUse {
                askQuestionRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

                PanelSection(title: "Answers", summary: answersSummary, isExpanded: $isAnswersSectionExpanded) {
                    modelPickerRow
                    studyModeRow
                    appearanceRow
                    voiceSpeedRow
                    captionsRow
                    bargeInRow
                    memoryRow
                }
                PanelSection(title: "Voice", summary: companionManager.pushToTalkShortcut.menuTitle, isExpanded: $isVoiceSectionExpanded) {
                    shortcutPickerRow
                    questionSpeechRow
                    dictationShortcutRow
                    dictationLanguageRow
                    microphoneRow
                    dictionaryRow
                }
                PanelSection(
                    title: "Do it for me",
                    summary: controlSummary,
                    isExpanded: $isControlSectionExpanded
                ) {
                    computerControlRows
                }
            }

            if !companionManager.allPermissionsGranted {
                settingsSection
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            if !companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
                startButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }

            hairline

            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 320)
        .background(panelBackground)
        .background(
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.height) { _, _ in
                    NotificationCenter.default.post(name: .thambiPanelContentHeightChanged, object: nil)
                }
            }
        )
        .onAppear {
            if companionManager.typeQuestionFocusRequestCount > 0 { focusQuestionField() }
            if dictationLocaleIdentifiers.isEmpty {
                dictationLocaleIdentifiers = AppleSpeechTranscriptionProvider.selectableDictationLocaleIdentifiers()
            }
        }
        .onChange(of: companionManager.typeQuestionFocusRequestCount) { _, _ in
            focusQuestionField()
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(DS.Colors.borderSubtle)
            .frame(height: 1)
    }

    /// Puts the keyboard in the typing box (after the panel has had a moment to become key).
    private func focusQuestionField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isQuestionFieldFocused = true
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 10) {
            ThambiMascot(mood: mascotMood, size: 28, audioLevel: companionManager.currentAudioPowerLevel)

            VStack(alignment: .leading, spacing: 1) {
                Text("Thambi")
                    .font(DS.font(14, .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Text(statusText)
                    .font(DS.font(11, .medium))
                    .foregroundColor(isThambiBusy ? DS.Colors.cool : DS.Colors.textTertiary)
            }

            Spacer()

            Button(action: {
                NotificationCenter.default.post(name: .clickyDismissPanel, object: nil)
                NotificationCenter.default.post(name: .thambiShowMainWindow, object: nil)
            }) {
                Text("Study window")
                    .font(DS.font(12, .medium))
                    .foregroundColor(DS.Colors.textPrimary)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.surface2))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Open the Thambi window: ask from your materials, library and notes (⌘0)")

            Button(action: {
                NotificationCenter.default.post(name: .clickyDismissPanel, object: nil)
            }) {
                Image(systemName: "xmark")
                    .font(DS.font(10, .semibold))
                    .foregroundColor(DS.Colors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.surface2))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Close")
            .accessibilityLabel("Close panel")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var isThambiBusy: Bool {
        guard isReadyForEverydayUse else { return false }
        return companionManager.isAnswerInProgress || companionManager.isControlTaskRunning
            || companionManager.isTypingByVoice || companionManager.voiceState != .idle
    }

    private var mascotMood: ThambiMascot.Mood {
        guard isReadyForEverydayUse else { return .idle }
        if companionManager.isControlTaskRunning { return .acting }
        if companionManager.isTypingByVoice { return .listening }
        switch companionManager.voiceState {
        case .listening: return .listening
        case .processing: return .thinking
        case .responding: return .speaking
        case .idle: return companionManager.isAnswerInProgress ? .thinking : .idle
        }
    }

    private var statusText: String {
        if !companionManager.hasCompletedOnboarding || !companionManager.allPermissionsGranted {
            return "Setup"
        }
        if companionManager.isControlTaskRunning {
            return "Working on your Mac"
        }
        if companionManager.isTypingByVoice {
            return "Typing what you say"
        }
        if companionManager.isAnswerInProgress {
            return "Answering"
        }
        if !companionManager.isOverlayVisible {
            return "Ready"
        }
        switch companionManager.voiceState {
        case .idle:
            return "Active"
        case .listening:
            return "Listening"
        case .processing:
            return "Processing"
        case .responding:
            return "Responding"
        }
    }

    // MARK: - Intro copy

    @ViewBuilder
    private var permissionsCopySection: some View {
        if isReadyForEverydayUse {
            Text("Hold \(companionManager.pushToTalkShortcut.menuTitle) to talk, or type below (\(BuddyPushToTalkShortcut.typeQuestionShortcutDisplayText)).")
                .fixedSize(horizontal: false, vertical: true)
                .font(DS.font(12))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.allPermissionsGranted {
            Text("You're all set. Hit Start to meet Thambi.")
                .font(DS.font(12))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.hasCompletedOnboarding {
            // Permissions were revoked after onboarding — tell user to re-grant
            VStack(alignment: .leading, spacing: 4) {
                Text("Permissions needed")
                    .font(DS.font(13, .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Text("Some permissions were revoked. Grant all four below to keep using Thambi.")
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hi, this is Thambi.")
                    .font(DS.font(13, .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Text("An AI study buddy that lives next to your cursor and helps you learn as you use your computer.")
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Nothing runs in the background. Thambi only takes a screenshot when you press the hotkey.")
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Ask by typing, and Stop

    private var askQuestionRow: some View {
        HStack(spacing: 8) {
            TextField("", text: $typedQuestion, prompt: Text("Type a question").foregroundColor(DS.Colors.textTertiary))
                .textFieldStyle(.plain)
                .font(DS.font(13))
                .foregroundColor(DS.Colors.textPrimary)
                .focused($isQuestionFieldFocused)
                .onSubmit { submitTypedQuestion() }
                .onChange(of: typedQuestion) { _, newValue in
                    if newValue.count > ThambiSettings.maximumTypedQuestionLength {
                        typedQuestion = String(newValue.prefix(ThambiSettings.maximumTypedQuestionLength))
                    }
                }

            if companionManager.isAnswerInProgress {
                Button(action: { companionManager.stopAnswer() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill").font(DS.font(9, .bold))
                        Text("Stop").font(DS.font(12, .semibold))
                    }
                    .foregroundColor(DS.Colors.destructiveText)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.destructiveSubtle))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Stop the answer (or press Escape)")
            } else {
                let canSend = ThambiSettings.preparedTypedQuestion(typedQuestion) != nil
                Button(action: { submitTypedQuestion() }) {
                    Image(systemName: "arrow.up")
                        .font(DS.font(12, .bold))
                        .foregroundColor(canSend ? DS.Colors.textOnAccent : DS.Colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                                .fill(canSend ? DS.Colors.accent : DS.Colors.surface2)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .pointerCursor(isEnabled: canSend)
                .help("Ask (Return)")
                .accessibilityLabel("Ask")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(DS.Colors.well)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .strokeBorder(isQuestionFieldFocused ? DS.Colors.accent : DS.Colors.borderStrong, lineWidth: 1)
        )
    }

    private func submitTypedQuestion() {
        if companionManager.askTypedQuestion(typedQuestion) {
            typedQuestion = ""
        }
    }

    // MARK: - Shared row pieces

    private func settingRow<Control: View>(_ title: String, help: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(DS.font(13))
                .foregroundColor(DS.Colors.textPrimary)
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 32)
        .help(help ?? "")
    }

    private func noteText(_ text: String) -> some View {
        Text(text)
            .font(DS.font(11))
            .foregroundColor(DS.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
    }

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(DS.font(12, .medium))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(DS.font(8, .semibold))
                .foregroundColor(DS.Colors.textTertiary)
        }
        .foregroundColor(DS.Colors.textPrimary)
    }

    private func smallToggle(_ isOn: Binding<Bool>, label: String) -> some View {
        Toggle(label, isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(DS.Colors.accent)
    }

    private func outlinedButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DS.font(12, .medium))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.surface2))
                .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).strokeBorder(DS.Colors.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(help)
    }

    private func measuredValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(DS.Colors.textSecondary)
    }

    /// A row of choices where exactly one is current (marked in amber: it is your choice).
    private func segmentedChoice<Value: Equatable>(_ options: [(label: String, value: Value)], selection: Value, onSelect: @escaping (Value) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.value == selection
                Button(action: { onSelect(option.value) }) {
                    Text(option.label)
                        .font(DS.font(12, isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? DS.Colors.accentText : DS.Colors.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isSelected ? DS.Colors.accentSubtle : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.well))
        .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).strokeBorder(DS.Colors.borderSubtle, lineWidth: 1))
    }

    // MARK: - Answers

    private var answersSummary: String {
        let model: String
        switch companionManager.selectedModel {
        case ClickyModelRouter.haikuModelID: model = "Haiku"
        case ClickyModelRouter.sonnetModelID: model = "Sonnet"
        default: model = "Auto"
        }
        // Write is the everyday mode; only the limiting modes are worth showing when folded.
        return studyMode == .write ? model : "\(model), \(studyMode.title)"
    }

    private var modelPickerRow: some View {
        settingRow("Model", help: "Auto uses the cheaper model and steps up only when a question needs it") {
            segmentedChoice(
                [("Auto", ClickyModelRouter.autoModeIdentifier), ("Haiku", ClickyModelRouter.haikuModelID), ("Sonnet", ClickyModelRouter.sonnetModelID)],
                selection: companionManager.selectedModel,
                onSelect: { companionManager.setSelectedModel($0) }
            )
        }
    }

    /// The same study mode as the window's sidebar: it decides what voice answers may do too.
    private var studyModeRow: some View {
        settingRow("Study mode", help: studyMode.explanation) {
            segmentedChoice(
                StudyMode.allCases.map { ($0.title, $0) },
                selection: studyMode,
                onSelect: { ThambiSettings.studyMode = $0 }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: ThambiSettings.studyModeChangedNotification)) { _ in
            studyMode = ThambiSettings.studyMode
        }
    }

    private var appearanceRow: some View {
        settingRow("Appearance", help: "Auto follows your Mac. What Thambi draws over your screen stays dark.") {
            segmentedChoice(
                ThambiSettings.Appearance.allCases.map { ($0.title, $0) },
                selection: appearance,
                onSelect: {
                    ThambiSettings.appearance = $0
                    appearance = $0
                    ThambiSettings.applyAppearance()
                }
            )
        }
    }

    private var voiceSpeedRow: some View {
        settingRow("Voice speed") {
            Slider(
                value: Binding(
                    get: { companionManager.voiceSpeed },
                    set: { companionManager.setVoiceSpeed($0) }
                ),
                in: ThambiSettings.minimumVoiceSpeed...ThambiSettings.maximumVoiceSpeed,
                step: ThambiSettings.voiceSpeedStep
            )
            .controlSize(.small)
            .tint(DS.Colors.accent)
            .frame(width: 120)
            .accessibilityLabel("Voice speed")
            measuredValue(ThambiSettings.voiceSpeedLabel(companionManager.voiceSpeed))
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var captionsRow: some View {
        settingRow("Captions", help: "Show what Thambi is saying at the bottom of the screen") {
            smallToggle(Binding(
                get: { companionManager.areCaptionsEnabled },
                set: { companionManager.setCaptionsEnabled($0) }
            ), label: "Captions")
        }
    }

    private var bargeInRow: some View {
        settingRow("Interrupt by talking", help: "Thambi stops speaking when you start. The microphone opens only while it speaks, and the sound is measured on this Mac and thrown away.") {
            smallToggle(Binding(
                get: { companionManager.isBargeInEnabled },
                set: { companionManager.setBargeInEnabled($0) }
            ), label: "Interrupt by talking")
        }
    }

    private var memoryRow: some View {
        settingRow("Memory") {
            measuredValue(companionManager.memoryEntryCount == 0 ? "Nothing saved" : "\(companionManager.memoryEntryCount) saved")
            outlinedButton("Edit", help: "Say \"remember...\" to save a preference. This opens the file so you can read, change or empty it.") {
                companionManager.openMemoryFile()
            }
        }
    }

    // MARK: - Voice

    private var shortcutPickerRow: some View {
        settingRow("Talk to Thambi", help: "The keys you hold to talk") {
            Menu {
                ForEach(BuddyPushToTalkShortcut.ShortcutOption.menuOrder) { shortcutOption in
                    Button(action: { companionManager.setPushToTalkShortcut(shortcutOption) }) {
                        if shortcutOption == companionManager.pushToTalkShortcut {
                            Label(shortcutOption.menuTitle, systemImage: "checkmark")
                        } else {
                            Text(shortcutOption.menuTitle)
                        }
                    }
                }
            } label: {
                menuLabel(companionManager.pushToTalkShortcut.menuTitle)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var questionSpeechRow: some View {
        settingRow("Hear questions", help: "Cloud is more accurate and is billed by the minute. On this Mac is free and private, and a little less accurate with unusual words.") {
            segmentedChoice(
                [("Cloud", false), ("On this Mac", true)],
                selection: companionManager.isQuestionSpeechOnDevice,
                onSelect: { companionManager.setQuestionSpeechOnDevice($0) }
            )
        }
    }

    private var dictationShortcutRow: some View {
        VStack(spacing: 0) {
            settingRow("Type by voice", help: "Hold these keys in any app and speak: the words are typed where your cursor is. Speech is turned into text on this Mac.") {
                Menu {
                    ForEach(Array(BuddyPushToTalkShortcut.DictationShortcutOption.allCases), id: \.self) { shortcutOption in
                        Button(action: { companionManager.setDictationShortcut(shortcutOption) }) {
                            if shortcutOption == companionManager.dictationShortcut {
                                Label(shortcutOption.menuTitle, systemImage: "checkmark")
                            } else {
                                Text(shortcutOption.menuTitle)
                            }
                        }
                    }
                } label: {
                    menuLabel(companionManager.dictationShortcut.menuTitle)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if let dictationStatusText = companionManager.dictationStatusText {
                noteText(dictationStatusText)
            }
        }
    }

    private var dictationLanguageRow: some View {
        settingRow("Language", help: "The language you speak when typing by voice") {
            Menu {
                Button(action: { companionManager.setDictationLanguageIdentifier("") }) {
                    if companionManager.dictationLanguageIdentifier.isEmpty {
                        Label("Same as this Mac", systemImage: "checkmark")
                    } else {
                        Text("Same as this Mac")
                    }
                }
                ForEach(dictationLocaleIdentifiers, id: \.self) { localeIdentifier in
                    Button(action: { companionManager.setDictationLanguageIdentifier(localeIdentifier) }) {
                        if localeIdentifier == companionManager.dictationLanguageIdentifier {
                            Label(AppleSpeechTranscriptionProvider.dictationLanguageName(for: localeIdentifier), systemImage: "checkmark")
                        } else {
                            Text(AppleSpeechTranscriptionProvider.dictationLanguageName(for: localeIdentifier))
                        }
                    }
                }
            } label: {
                menuLabel(companionManager.dictationLanguageIdentifier.isEmpty
                          ? "Same as this Mac"
                          : AppleSpeechTranscriptionProvider.dictationLanguageName(for: companionManager.dictationLanguageIdentifier))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var microphoneRow: some View {
        VStack(spacing: 0) {
            settingRow("Microphone", help: "Automatic uses the Mac's own microphone when the system one is a Bluetooth headset, so music keeps its quality") {
                segmentedChoice(
                    MicrophoneChoice.allCases.map { ($0.menuTitle, $0) },
                    selection: companionManager.microphoneChoice,
                    onSelect: { companionManager.setMicrophoneChoice($0) }
                )
            }
            if let microphoneNotice = companionManager.buddyDictationManager.microphoneNotice {
                noteText(microphoneNotice)
            }
        }
    }

    private var dictionaryRow: some View {
        settingRow("Dictionary") {
            measuredValue(companionManager.dictionaryEntryCount == 0 ? "No words yet" : "\(companionManager.dictionaryEntryCount) words")
            outlinedButton("Edit", help: "Names and terms Thambi should spell right. It learns them as you talk; this opens the file so you can change it.") {
                companionManager.openDictionaryFile()
            }
        }
    }

    // MARK: - Do it for me (computer control)

    private var controlSummary: String {
        guard companionManager.isComputerControlEnabled else { return "Off" }
        switch companionManager.controlApprovalMode {
        case .everyStep: return "On, asks every step"
        case .oncePerTask: return "On, asks once"
        case .never: return "On, never asks"
        }
    }

    @ViewBuilder
    private var computerControlRows: some View {
        settingRow("Let Thambi click and type", help: "Ask for something like \"open TextEdit and type my name\" and Thambi does it one step at a time") {
            smallToggle(Binding(
                get: { companionManager.isComputerControlEnabled },
                set: { companionManager.setComputerControlEnabled($0) }
            ), label: "Let Thambi click and type")
        }
        if companionManager.isComputerControlEnabled {
            settingRow("Ask me", help: "Risky steps such as Send or Delete always ask, whichever you choose") {
                segmentedChoice(
                    ControlApprovalMode.allCases.map { ($0.menuTitle, $0) },
                    selection: companionManager.controlApprovalMode,
                    onSelect: { companionManager.setControlApprovalMode($0) }
                )
            }
            settingRow("Show each step", help: "A card at the top of the screen says what Thambi is doing. Turn it off to let it work quietly: the card then appears only when a step needs your go-ahead.") {
                smallToggle(Binding(
                    get: { companionManager.areControlStepsVisible },
                    set: { companionManager.setControlStepsVisible($0) }
                ), label: "Show each step")
            }
            if companionManager.controlApprovalMode == .never {
                noteText("Thambi acts without asking. Send, Delete, Pay and similar steps still wait for you.")
            }
            HStack(spacing: 6) {
                keyCap("return")
                Text("allows a step")
                keyCap("esc")
                Text("stops everything")
                Spacer(minLength: 0)
            }
            .font(DS.font(11))
            .foregroundColor(DS.Colors.textTertiary)
            .padding(.top, 2)
            .padding(.bottom, 4)
        } else {
            noteText("Off. Thambi only looks and explains.")
        }
    }

    private func keyCap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(DS.Colors.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(DS.Colors.surface2))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(DS.Colors.borderSubtle, lineWidth: 1))
    }

    // MARK: - Start Button

    @ViewBuilder
    private var startButton: some View {
        if !companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            Button(action: {
                companionManager.triggerOnboarding()
            }) {
                Text("Start")
                    .font(DS.font(14, .semibold))
                    .foregroundColor(DS.Colors.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                            .fill(DS.Colors.accent)
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
    }

    // MARK: - Permissions

    private var settingsSection: some View {
        VStack(spacing: 0) {
            Text("Permissions")
                .font(DS.font(12, .semibold))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

            microphonePermissionRow

            accessibilityPermissionRow

            screenRecordingPermissionRow

            if companionManager.hasScreenRecordingPermission {
                screenContentPermissionRow
            }
        }
    }

    private func grantButton(_ title: String = "Grant", isPrimary: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DS.font(12, .semibold))
                .foregroundColor(isPrimary ? DS.Colors.textOnAccent : DS.Colors.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                        .fill(isPrimary ? DS.Colors.accent : DS.Colors.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                        .strokeBorder(isPrimary ? Color.clear : DS.Colors.borderStrong, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func permissionRow<Actions: View>(
        iconName: String, title: String, subtitle: String? = nil, isGranted: Bool, @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(DS.font(12, .medium))
                .foregroundColor(isGranted ? DS.Colors.textTertiary : DS.Colors.accentText)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.font(13))
                    .foregroundColor(DS.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.font(11))
                        .foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 6)

            if isGranted {
                Label("Granted", systemImage: "checkmark")
                    .font(DS.font(11, .medium))
                    .foregroundColor(DS.Colors.success)
            } else {
                actions()
            }
        }
        .frame(minHeight: 36)
    }

    private var accessibilityPermissionRow: some View {
        permissionRow(iconName: "hand.raised", title: "Accessibility", isGranted: companionManager.hasAccessibilityPermission) {
            HStack(spacing: 6) {
                grantButton {
                    // Triggers the system accessibility prompt (AXIsProcessTrustedWithOptions)
                    // on first attempt, then opens System Settings on subsequent attempts.
                    WindowPositionManager.requestAccessibilityPermission()
                }
                grantButton("Find App", isPrimary: false) {
                    // Reveals the app in Finder so the user can drag it into
                    // the Accessibility list if it doesn't appear automatically
                    // (common with unsigned dev builds).
                    WindowPositionManager.revealAppInFinder()
                    WindowPositionManager.openAccessibilitySettings()
                }
            }
        }
    }

    private var screenRecordingPermissionRow: some View {
        let isGranted = companionManager.hasScreenRecordingPermission
        return permissionRow(
            iconName: "rectangle.dashed.badge.record",
            title: "Screen Recording",
            subtitle: isGranted ? "Only takes a screenshot when you use the hotkey" : "Quit and reopen after granting",
            isGranted: isGranted
        ) {
            grantButton {
                // Triggers the native macOS screen recording prompt on first
                // attempt (auto-adds app to the list), then opens System Settings
                // on subsequent attempts.
                WindowPositionManager.requestScreenRecordingPermission()
            }
        }
    }

    private var screenContentPermissionRow: some View {
        permissionRow(iconName: "eye", title: "Screen Content", isGranted: companionManager.hasScreenContentPermission) {
            grantButton {
                companionManager.requestScreenContentPermission()
            }
        }
    }

    private var microphonePermissionRow: some View {
        permissionRow(iconName: "mic", title: "Microphone", isGranted: companionManager.hasMicrophonePermission) {
            grantButton {
                // Triggers the native macOS microphone permission dialog on
                // first attempt. If already denied, opens System Settings.
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                if status == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                } else {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button(action: {
                NSApp.terminate(nil)
            }) {
                Text("Quit Thambi")
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textSecondary)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Spacer()

            // LOCAL ADDITION: one click to stop everything and remove Thambi's permissions.
            Button(action: {
                confirmAndShutDownCompletely()
            }) {
                Text("Shut down and remove access")
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.destructiveText)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
    }

    /// Asks for confirmation, then stops Clicky's helpers, removes its permissions and quits.
    private func confirmAndShutDownCompletely() {
        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = "Shut down Thambi completely?"
        confirmation.informativeText = "This will:\n• stop Thambi's voice server\n• remove Thambi's Screen Recording, Accessibility, Microphone and Input Monitoring permissions\n• quit Thambi\n\nNothing of Thambi will be running or able to see or hear anything. Next time you open it, you'll grant the permissions again."
        confirmation.addButton(withTitle: "Shut down")
        confirmation.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if confirmation.runModal() == .alertFirstButtonReturn {
            companionManager.shutDownCompletelyAndRemovePermissions()
        }
    }

    // MARK: - Visual Helpers

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous)
            .fill(DS.Colors.background)
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous)
                    .strokeBorder(DS.Colors.borderStrong, lineWidth: 1)
            )
    }
}

// MARK: - A section that folds away

/// A titled group of settings. Closed, it shows its current value on the right so you can read
/// the state without opening it.
private struct PanelSection<Content: View>: View {
    let title: String
    let summary: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.Colors.borderSubtle)
                .frame(height: 1)

            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(DS.font(12, .semibold))
                        .foregroundColor(DS.Colors.textPrimary)
                    Spacer(minLength: 8)
                    if !isExpanded {
                        Text(summary)
                            .font(DS.font(12))
                            .foregroundColor(DS.Colors.textTertiary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(DS.font(9, .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(isHovered ? DS.Colors.surface1 : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .pointerCursor()
            .accessibilityLabel("\(title), \(isExpanded ? "expanded" : "collapsed, \(summary)")")

            if isExpanded {
                VStack(spacing: 0) {
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}
