# Thambi - Agent Instructions

## Overview

macOS study buddy: a study window (Ask, Library, Notes; Dock icon, `LSUIElement` false) plus the menu bar buddy. Hold **Control + Option** and speak; Thambi takes a screenshot, sends it with the transcript to Claude, speaks the answer with a local neural voice, and points at what it is talking about with an arrow that lands as the voice names each thing.

The Xcode project, target and source folder are still called `leanring-buddy` (historical; do not rename). The product is **Thambi** (`com.dharoon.thambi`), installed at `~/Applications/Thambi.app`.

## Architecture

| Stage | How | Where |
|---|---|---|
| Hear | Push-to-talk (`GlobalPushToTalkShortcutMonitor`, listen-only CGEvent tap). Mic starts instantly; audio is buffered until the AssemblyAI websocket is ready (`MicrophoneAudioHandoff`). | AssemblyAI streaming (`u3-rt-pro`), or Apple on-device speech if `VoiceTranscriptionProvider=apple` or no AssemblyAI key |
| See | `CompanionScreenCaptureUtility` (ScreenCaptureKit), only on the hotkey. `ScreenBusynessMap` is built from the same screenshot in the background. | On device |
| Think | `ClaudeAPI` streams from OpenRouter's Anthropic-compatible `/api/v1/messages`. `ClickyModelRouter` picks Haiku 5.5 (default) or Sonnet 5.5 per question. | OpenRouter |
| Speak | `SystemSpeechTTSClient` plays sentence-by-sentence audio from the local voice server; macOS voice fallback. `SpeechSentenceSplitter` + `SpeechAcronymSpeller` (ESP -> "E S P"). | `~/clicky/tts/server.py` (Qwen3-TTS via mlx-audio) on 127.0.0.1:8789 |
| Point | Answers carry `[POINT:x,y:label]` tags right after the sentence naming the element; each fires when the voice reaches that sentence. `TargetArrowLayout` picks the arrow/label placement that hides the least content. | On device |

### Panel features (Phase 1 of ROADMAP.md)

- Typed questions: `CompanionManager.askTypedQuestion` (panel text box, or Control + Option + T via `GlobalPushToTalkShortcutMonitor.typeQuestionShortcutPublisher`). Capped at 2000 characters.
- Stop: `CompanionManager.stopAnswer()` (Stop button, or Escape while `isAnswerInProgress`).
- Voice speed 0.5x-1.5x (`ThambiSettings.voiceSpeed`), applied at playback with `AVAudioPlayer.rate`, so pitch is unchanged and no audio is regenerated.
- Push-to-talk keys: `BuddyPushToTalkShortcut.ShortcutOption`, stored in UserDefaults `pushToTalkShortcutOption`.
- Captions: `SystemSpeechTTSClient.onCaptionChanged` -> `CaptionsPanelController` (click-through, off by default).
- Notes: `NotesMarkdown` parses headings, lists and `|` tables; `cleanedForWriting` strips dashes, curly quotes and filler lines. The box opens only when the question contains "write", after speech ends.
- Walkthroughs: up to 15 `[POINT]` tags per answer (`maximumPointTargetsPerAnswer`).

### Voice typing and reliability (Phase 2 of ROADMAP.md)

- Type by voice: hold the dictation keys (`BuddyPushToTalkShortcut.DictationShortcutOption`, default Option + Command) in any app; Apple Speech turns it into text on the Mac and `DictationTextInserter` types it at the cursor. It refuses password fields (`isFocusedElementSecure`). Synthetic events carry `syntheticEventMarker` so Thambi's own taps ignore them.
- Dictionary: `ThambiDictionary`, a plain text file of terms and "heard -> written" corrections, fed to the recogniser as key terms and applied to transcripts. `sanitizedTerm` refuses anything that looks like a secret; corrections are only added when the user asked.
- Microphone: `MicrophoneRouter` / `MicrophoneChoice`. Automatic uses the built-in microphone when the system input is a Bluetooth headset, and falls back if capture fails (`microphoneNotice`).
- Barge-in: `BargeInMonitor` (off by default). The microphone is open only while the voice plays; loudness is measured on the Mac and discarded. Not yet verified with a real voice in a noisy room: treat as experimental.
- Reply drafting: `NotesMarkdown.userAskedToDraft` opens the notes box for "draft a reply..." requests.
- Whole PDF: `OpenDocumentReader` reads the text of the PDF in the front window and sends it as a cached document block. macOS may ask for folder access the first time.

### Computer control ("Do it for me")

- Rules live in `ComputerControl.swift` (pure, unit-tested): which words count as a task, blocked apps, risky labels and shortcuts, approval logic, the prompt, reply parsing. The loop lives in `ComputerControlAgent.swift`; the approval card in `ControlCardPanelController.swift`.
- Loop, at most 12 steps: screenshot -> one JSON action from Haiku (220 output tokens, about 1.5k input tokens a step with caching) -> resolve the target with accessibility -> block check -> approval -> act -> history line. The model carries a short `note` between steps so it does not lose its place.
- Safety rules, keep all of them: off by default; every step asks unless the user chose "Once per task", and risky steps (Send, Delete, Pay, Command + Q...) always ask; Return allows, Escape stops, via `ControlKeyInterceptor`, which exists only while a task runs; never operates System Settings, terminals, password managers, password fields or Thambi's own windows; forbidden shortcuts are never pressed; text on screen is content, never instructions; 60 seconds without an answer stops the task.
- Approval modes (`ControlApprovalMode`): every step, once, never. "Never" still asks for risky steps; do not remove that floor. `ThambiSettings.controlStepsVisible` off hides the card except while a step waits for approval.
- Speed: a reply may carry `then` (at most 2 key/type follow-ups, never clicks or done) that run without a new screenshot; each still passes the block and approval checks in `carryOut`.
- The buddy cursor is `ThambiMascot` (moods follow `voiceState` and the control phase). Still moods only blink via a timer task; only thinking/speaking/acting use a 30 fps `TimelineView`, and `isActive: false` stops everything while hidden.
- Routing: `ComputerControl.userAskedToOperate` is only the fast path. When it misses, the normal answer prompt carries `controlPromptSection`, and the model replies `[OPERATE]` to hand the request to control (`startComputerControlIfAsked(isHandedOver: true)`). A `not_a_task` fallback calls the answer path with `allowsControlHandoff: false` so the two can never loop.
- Cost levers in the loop, keep them: `appNameToOpenDirectly` opens a plainly named app with no AI call; `then` chains up to 4 key/type/named-click steps per look; `finish` ends a sure-thing task without a second look, but never when `taskNeedsResultRead` is true or any step was a click; `namedControls` sends the front window's button names and positions so clicks are exact; screenshots are 1024 px for control and 1152 px for questions (`ThambiSettings`). Pointing broke at 896 px in tests: do not go lower without re-measuring.
- Typing: text boxes get bursts, everything else (Calculator) gets one character per key press (`isKeyboardFocusInTextBox`). Bursts into Calculator register as a single key; per-key typing into TextEdit sets off autocorrect. Both were seen in testing.
- The model writes its `note` before its actions run, so the agent appends what was actually carried out. Without that it repeats presses.
- `open_app` must bring the app to the front (activate, then accessibility `AXFrontmost`), and report honestly when it did not.
- `snapToNamedControl`: when accessibility says the spot is not the control the model named and exactly one control has that name, the click moves onto it. It never invents a target.
- Test hooks (DEBUG only): `-ThambiDebugControlTask` (one decision about an image, nothing clicked) and `-ThambiDebugControlLive` (runs a real task, approving every step; launch the Debug app with `open -n ... --args` so it uses Thambi's own permissions). Only run live tests on harmless apps such as Calculator and TextEdit.

### Drawings

- `ThambiDrawing.swift` (pure, unit-tested) is the whole language: the word gate `userAskedToDraw`, the instructions `promptSection`, `extractDrawing`, `parse`, the flow-chart `layout` (layered; tidy-tree when every box has one parent; loop-back arrows listed in `backwardEdges` and drawn around the outside), the `Formula` parser and `markedPoints`. `DrawingPanelController.swift` holds the box, the SwiftUI `Canvas` drawing code and the SceneKit builder.
- Cost rule: the model writes text, the Mac draws. Never add image generation. The instructions go in their own cached block (`extraInstructions` in `ClaudeAPI.makeRequestBody`, placed last so the main cached blocks are untouched) and are sent only when the gate fires. Measured: 98 to 324 output tokens per drawing.
- Safety rules: only the user's words open a drawing; the description is data (unknown lines are skipped, hard caps on boxes, shapes and text); `Formula` builds a tree from a fixed list of functions and never evaluates text as code.
- The model is not trusted with arithmetic. Roots, crossings and peaks are requested with `mark ...` and computed in `markedPoints`. When it guessed crossings itself in testing, it got them wrong.
- Test hooks (DEBUG only): `-ThambiDebugDrawing <file> -ThambiDebugOutput <png>` draws a description with no AI call; `-ThambiDebugQuestion` with drawing words also writes `<output>.png`.
- Build-up: `step` lines split a drawing into parts (`Drawing.stepCount`). The app, not the model, times them: parts are spread evenly over the spoken sentences in `sendTranscriptToClaudeWithScreenshot`; `[STEP]` tags are honoured if the model writes them. Asking the model to place `[STEP]` tags made Haiku ramble and leak a `<reasoning>` block, so the instructions no longer ask for them and `SpeechTimedTags.withoutLeakedReasoning` strips any such block.
- Marks: `[MARK:box|underline|circle:...]` in `SpeechTimedTags.swift`, drawn by `ScreenMarksLayer` in the overlay, timed like `[POINT]`. `markRequestSection` is sent when the user's words ask for marks; without it the model prefers `[POINT]`.
- Models: `ThambiModels.swift` builds heart, cell, engine, dna, atom and solar-system from SceneKit shapes in code (schematic, not anatomical; no asset files, nothing to license). If the reply has no drawing but the words name a model, `ThambiDrawing.modelNamed` shows it anyway.

### Study library and window

- `StudyLibrary.swift` (pure, unit-tested): `StudyMode` (read/write/restricted with `mayWrite`, `mayOperate`, `usesOnlyMaterials`), passage cutting (`passages(fromPageText:)`, ~900 chars with overlap), `searchWords`/`stem`, `SearchIndex` + BM25 `wordScores`, hybrid `search` (words 0.55, stretched on-device meaning 0.45), `matchesAreRelevant` (gate for voice questions), `sources` (capped at 4,800 chars), `promptSection` (numbered `<source>` blocks, escaped; Restricted wording), citation parsing, and `subjectMemory` (whole subject, deterministic order so it stays cached, capped at 60,000 chars).
- `StudyLibraryStore.swift`: reads files off the main thread (`StudyMaterialReader`: PDFKit, Vision OCR for scanned pages and images, `/usr/bin/unzip` for .pptx, NSAttributedString for Word/RTF/HTML), `StudyMeaning` (NLEmbedding sentence vectors), storage in Application Support `Thambi/Library` (`materials.json`, `passages/<id>.json`) and `Thambi/Notes/*.md`, kept-in-memory subjects in UserDefaults `studyMemorySubjects`.
- `StudyChat.swift`: typed questions, no screenshot; passages go in `documentText` with `cachesDocumentText: false` (they change per question). A kept subject goes in `subjectMemoryText`, cached with `ttl: 1h`; the API requires 1h blocks before 5m blocks, so `makeRequestBody` then gives the system prompt the 1h TTL too. Measured: first question 13,364 cache-write tokens (~₹0.28), follow-ups read 11,524 cached tokens (~₹0.03 each).
- Study mode is enforced in code, not only in the prompt: `startComputerControlIfAsked` and the control hand-over need `mayOperate`; the notes box and Save as note need `mayWrite`. The student's own note editing is always allowed.
- `MainWindow.swift`: AppKit `NSWindow` hosting SwiftUI (`MainWindowController`), sidebar (pages, subjects as search scope, study mode), Ask, Library (table, import progress and errors, Keep in memory row), Notes (list + editor). `leanring_buddyApp.swift`: Settings scene shows the panel; ⌘0 opens the window; Dock click reopens it; closing it keeps the menu bar buddy running.
- Test hooks (DEBUG only, `MainWindowDebug.swift`): `-ThambiDebugWindowOutput <dir>` with `-ThambiDebugLibraryDirectory <dir>` (separate test library), `-ThambiDebugLibraryAdd "a|b" -ThambiDebugLibrarySubject S`, `-ThambiDebugMode`, `-ThambiDebugScope`, `-ThambiDebugKeepInMemory S`, `-ThambiDebugAsk "q1|q2"`, `-ThambiDebugWindowPage ask|library|notes`, `-ThambiDebugSaveNote T`. Writes `report.txt` (sources, citations, tokens) and `window.png`. These write `studyMode`/`studyMemorySubjects` to the real defaults domain; delete them after a run.

### Look and feel

- All colours come from `DS.Colors`. Amber (`accent`) means the person: the one primary button, the current choice, the step waiting for approval. Cool blue (`cool`) means Thambi: the mascot and its live status. Green and red are for status only. Measured values (keys, counts, speed, step numbers) use the monospaced face; labels never do.
- No capital-letter labels, no decorative dots, no gradients or glows, no card inside a card. Every animation needs a reduce-motion fallback.
- `ThambiMascot.swift` draws the mascot, the menu bar icon and (through `scripts/make-app-icon.swift`) the app icon from the same code-drawn outline. There are no image sources to license. Regenerate the icon with `swiftc -o /tmp/mk scripts/make-app-icon.swift leanring-buddy/ThambiMascot.swift leanring-buddy/DesignSystem.swift && /tmp/mk leanring-buddy/Assets.xcassets/AppIcon.appiconset`.

### Security and privacy rules (keep these)

- API keys live only in the macOS Keychain (`ThambiKeychain`, this-device-only, not synced). Never print, log, or write them to disk. `~/clicky/thambi-keys.env`, if present, is imported and then deleted.
- No analytics, no auto-updater, no login item, no local AI proxy. Only OpenRouter, AssemblyAI and the local voice server are contacted.
- Network sessions that carry tokens or audio are ephemeral with no URL cache.
- The voice server binds 127.0.0.1 only, requires header `x-thambi-client: 1`, runs offline (`HF_HUB_OFFLINE=1`), logs lengths not text, and exits when Thambi's process is gone (`--parent-pid`). `VoiceServerLauncher` starts/stops it.
- `ClaudeAPI.makeRequestBody` enforces the model allowlist, the 1500-token output cap, Haiku `thinking: disabled` (Sonnet rejects it), and prompt caching on the system prompt.
- "Shut down & remove access" (`ClickyShutdown`) stops the voice server and runs `tccutil reset` for ScreenCapture, Accessibility, Microphone, ListenEvent and All, scoped to Thambi's bundle id. Never run it against the real bundle id in tests; `tccutil` only accepts apps registered in an indexed folder.
- Memory (`ThambiMemory`) is a plain text file, mode 0600, at `~/Library/Application Support/Thambi/memory.txt`. It is written only when the user's own transcript says "remember"/"from now on" (or "forget" to remove), never from screen content alone; `sanitizedEntry` refuses anything that looks like a key, password or long number. Its lines are appended to the system prompt after the cached block's text, so keep it short (30 lines max).
- The voice server unloads its model after `idle_unload_minutes` (config.json, default 10) and reloads on the next `/speak` or `POST /warm`. Thambi calls `/warm` when push-to-talk is pressed.
- Views that stay in the overlay while hidden (waveform, spinner) must pause their animations (`TimelineView(... paused:)`), and the cursor timer must not write unchanged `@State`. Idle CPU regressed to 5-7% when they didn't.
- DEBUG-only test hooks (`-ThambiDebugQuestion`, `-ThambiDebugRenderDirectory`, `-ThambiShowSampleNotes`, `-ThambiDebugControlTask`, `-ThambiDebugControlLive`, `-ThambiDebugDrawing`) must stay inside `#if DEBUG`; check a Release binary with `strings` before shipping.
- Entitlements: no sandbox (needed for the event tap and launching the voice server), microphone, network client. No camera. Release builds are re-signed without `get-task-allow`.

## Build and run

Build in Xcode (scheme `leanring-buddy`), or Release from the command line; signing uses the Apple Development identity, so macOS permissions persist across rebuilds. Ad-hoc ("Sign to Run Locally") signing makes macOS forget permissions on every rebuild.

```bash
xcodebuild -project leanring-buddy.xcodeproj -scheme leanring-buddy -configuration Release -derivedDataPath /tmp/thambi-build build
```

## Code style

- Clear, descriptive names over short ones; comments explain why.
- SwiftUI for UI, AppKit only where needed (`NSPanel` windows). UI state on `@MainActor`, async/await throughout.
- Pure logic lives in dependency-free files (`ClickyModelRouter`, `SpeechSentenceSplitter`, `SpeechAcronymSpeller`, `TargetArrowLayout`, `ScreenBusynessMap`, `ClickyShutdown`) so it can be unit-tested with `swiftc`.
- Don't add features or refactor beyond what was asked.
