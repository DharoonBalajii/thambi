# Thambi - Agent Instructions

## Overview

macOS menu-bar study buddy (no Dock icon). Hold **Control + Option** and speak; Thambi takes a screenshot, sends it with the transcript to Claude, speaks the answer with a local neural voice, and points at what it is talking about with an arrow that lands as the voice names each thing.

The Xcode project, target and source folder are still called `leanring-buddy` (historical; do not rename). The product is **Thambi** (`com.dharoon.thambi`), installed at `~/Applications/Thambi.app`.

## Architecture

| Stage | How | Where |
|---|---|---|
| Hear | Push-to-talk (`GlobalPushToTalkShortcutMonitor`, listen-only CGEvent tap). Mic starts instantly; audio is buffered until the AssemblyAI websocket is ready (`MicrophoneAudioHandoff`). | AssemblyAI streaming (`u3-rt-pro`), or Apple on-device speech if `VoiceTranscriptionProvider=apple` or no AssemblyAI key |
| See | `CompanionScreenCaptureUtility` (ScreenCaptureKit), only on the hotkey. `ScreenBusynessMap` is built from the same screenshot in the background. | On device |
| Think | `ClaudeAPI` streams from OpenRouter's Anthropic-compatible `/api/v1/messages`. `ClickyModelRouter` picks Haiku 5.5 (default) or Sonnet 5.5 per question. | OpenRouter |
| Speak | `SystemSpeechTTSClient` plays sentence-by-sentence audio from the local voice server; macOS voice fallback. `SpeechSentenceSplitter` + `SpeechAcronymSpeller` (ESP -> "E S P"). | `~/clicky/tts/server.py` (Qwen3-TTS via mlx-audio) on 127.0.0.1:8789 |
| Point | Answers carry `[POINT:x,y:label]` tags right after the sentence naming the element; each fires when the voice reaches that sentence. `TargetArrowLayout` picks the arrow/label placement that hides the least content. | On device |

### Security and privacy rules (keep these)

- API keys live only in the macOS Keychain (`ThambiKeychain`, this-device-only, not synced). Never print, log, or write them to disk. `~/clicky/thambi-keys.env`, if present, is imported and then deleted.
- No analytics, no auto-updater, no login item, no local AI proxy. Only OpenRouter, AssemblyAI and the local voice server are contacted.
- Network sessions that carry tokens or audio are ephemeral with no URL cache.
- The voice server binds 127.0.0.1 only, requires header `x-thambi-client: 1`, runs offline (`HF_HUB_OFFLINE=1`), logs lengths not text, and exits when Thambi's process is gone (`--parent-pid`). `VoiceServerLauncher` starts/stops it.
- `ClaudeAPI.makeRequestBody` enforces the model allowlist, the 1500-token output cap, Haiku `thinking: disabled` (Sonnet rejects it), and prompt caching on the system prompt.
- "Shut down & remove access" (`ClickyShutdown`) stops the voice server and runs `tccutil reset` for ScreenCapture, Accessibility, Microphone, ListenEvent and All, scoped to Thambi's bundle id. Never run it against the real bundle id in tests; `tccutil` only accepts apps registered in an indexed folder.
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
