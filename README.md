# Thambi 

*Thambi* (தம்பி) is Tamil for "little brother", the one who sits next to you during exam prep and actually explains the slide instead of just staring at it with you.

It lives in your Mac's menu bar. You hold a key, ask a question out loud, and it:

- 👀 **looks at your screen** (only when you ask, never in the background)
- 🗣️ **answers out loud** in a voice that runs entirely on your Mac
- 👉 **points at stuff** with an arrow, right as it says "...and *this* box here is the security association"

Basically a TA who never sighs when you ask the same question twice.

---

## How it feels

1. Open your lecture slides at 1 a.m.
2. Hold **Control + Option**, say *"explain this slide simply"*.
3. Let go. Thambi reads the slide, starts talking within a couple of seconds, and the arrow hops from the title to the diagram to the takeaway box as it explains each one.

Ask *"show me the ESP box and the IKE box"* and it points at both, in order. And yes, it says "E S P", not "esp". Every abbreviation gets spelled out letter by letter, because "ike" is not a word and we all deserve better.

## What's under the hood

| Thambi's job | How it pulls it off |
|---|---|
| Hearing you | Push-to-talk. The mic starts the instant you press the keys, so your first words never get eaten. Transcription by AssemblyAI (or Apple's on-device speech if you'd rather nothing leave your Mac). |
| Seeing | One screenshot per screen, only when you press the hotkey. |
| Thinking | Claude through OpenRouter. **Haiku** for everyday questions, **Sonnet** only when you say things like "step by step", "derive", "solve" or "that's wrong, try again". |
| Talking | A local neural voice (Qwen3-TTS via `mlx-audio`) on your Mac's GPU, sentence by sentence with natural pauses, a bit faster than normal so it doesn't sound like it's reading a will. Falls back to the macOS voice if the local one isn't running. |
| Pointing | Arrows fire exactly when the voice reaches the sentence about that thing. They're placed by scanning the screenshot for empty space, so they don't cover the text you're trying to read. Moving your mouse doesn't interrupt them. |

## Cheap. Like, really cheap.

| What you ask | Roughly costs |
|---|---|
| "Where's the formula?" (Haiku) | ~₹0.02 |
| "Explain this slide" (Haiku) | ~₹0.02–0.04 |
| "Walk me through this step by step" (Sonnet) | ~₹0.7–1.4 |
| The voice | ₹0, forever (it's on your Mac) |

The trick: Thambi's long instructions are **prompt-cached**, so after your first question they're billed at about a tenth of the price. A whole night of revision costs less than the chai you'll drink during it.

## Privacy, because it can see your screen

- No analytics. No tracking. No auto-updater. Doesn't sneak into your login items.
- Your voice goes to AssemblyAI, and your screenshot plus question go to OpenRouter. That's the whole list.
- API keys live in the **macOS Keychain**: encrypted, this Mac only, never synced, readable only by Thambi.
- Nothing gets cached to disk.
- The voice server only listens on `127.0.0.1`, runs offline, and quits on its own if Thambi does.
- Done studying? Hit **Shut down & remove access** in the panel. It stops the voice, takes back Thambi's Screen Recording, Accessibility and Microphone permissions, and quits. Thambi then can't see or hear anything until you say so again.

## Setting it up

You'll need: a Mac with Apple Silicon on macOS 14.2+, Xcode, an [OpenRouter](https://openrouter.ai) key, and an [AssemblyAI](https://www.assemblyai.com) key (it comes with free credit).

**1. Give it your keys.** Make a file at `~/clicky/thambi-keys.env`:

```
OPENROUTER_API_KEY=your-key-here
ASSEMBLYAI_API_KEY=your-key-here
```

The first time Thambi opens, it moves them into the Keychain and **deletes this file**. Same trick if you ever need to change a key.

**2. Set up the voice** (optional, but the robot voice is sad):

```bash
mkdir -p ~/clicky/tts && cp voice-server/server.py voice-server/config.json ~/clicky/tts/
cd ~/clicky/tts && python3 -m venv venv && venv/bin/pip install --only-binary=:all: -r /path/to/this/repo/voice-server/requirements.txt
```

The voice model (~2 GB) downloads on first run, then everything works offline. Want a different voice or speed? Edit `config.json` (try `"voice": "serena"` or `"speed": 1.2`).

**3. Build it.** Open `leanring-buddy.xcodeproj` (yes, "leanring". It's a long story and the folder name stays), pick your own signing team (a free Apple ID works), and build. Copy `Thambi.app` into your Applications folder.

> Use a real signing team. With "Sign to Run Locally", macOS forgets Thambi's permissions every time you rebuild, and you'll be granting Screen Recording until the heat death of the universe.

**4. Open Thambi** and grant Microphone, Accessibility (for the hotkey) and Screen Recording. Then hold Control + Option and ask away.

## Where things live

```
leanring-buddy/                Swift source
  CompanionManager.swift         the brain: hear → look → think → talk → point
  ClaudeAPI.swift                talks to Claude (model allowlist, prompt caching)
  ClickyModelRouter.swift        decides Haiku vs Sonnet
  SystemSpeechTTSClient.swift    plays the voice and fires each arrow on time
  SpeechAcronymSpeller.swift     the "E S P, not esp" department
  OverlayWindow.swift            the cursor buddy and the arrows
  ScreenBusynessMap.swift        finds empty space so arrows don't cover text
  ThambiKeychain.swift           keys in the Keychain
  VoiceServerLauncher.swift      starts/stops the voice with the app
  ClickyShutdown.swift           the big red "go away now" button
voice-server/                  the offline voice (Python)
```

## Credits

Thambi grew out of an MIT-licensed open-source project. The original copyright notice lives in [LICENSE](LICENSE), as it should.

## License

MIT. Do cool stuff with it.
