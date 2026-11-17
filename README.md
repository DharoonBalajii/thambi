

# Thambi 

*Thambi* (தம்பி) is Tamil for "little brother", the one who sits next to you during exam prep and actually explains the slide instead of just staring at it with you.

It lives in your Mac's menu bar and in its own study window, where it answers from your own notes and textbooks. In the menu bar you hold a key, ask a question out loud, and it:

- 👀 **looks at your screen** (only when you ask, never in the background)
- 🗣️ **answers out loud** in a voice that runs entirely on your Mac
- 👉 **points at stuff** with an arrow, right as it says "...and *this* box here is the security association"

Basically a TA who never sighs when you ask the same question twice.

## Launch video

[![Watch the Thambi launch video](docs/media/launch-video-poster.jpg)](https://github.com/DharoonBalajii/thambi/raw/main/docs/media/thambi-launch.mp4)

Hold Control + Option, and Thambi reads your slide, draws on it and explains it in 3D from your own notes. Click the picture to play the 60 second film.

---

## How it feels

1. Open your lecture slides at 1 a.m.
2. Hold **Control + Option**, say *"explain this slide simply"*.
3. Let go. Thambi reads the slide, starts talking within a couple of seconds, and the arrow hops from the title to the diagram to the takeaway box as it explains each one.

Ask *"show me the ESP box and the IKE box"* and it points at both, in order. And yes, it says "E S P", not "esp". Every abbreviation gets spelled out letter by letter, because "ike" is not a word and we all deserve better.

## Everyday controls

Click the menu bar icon and it's all in one small panel.

| Want to... | Do this |
|---|---|
| Ask without talking (library, class) | Press **Control + Option + T** and type |
| Shut it up | Press **Escape**, or the **Stop** button |
| Slow it down or speed it up | **Voice speed**, 0.5x to 1.5x. Pitch stays the same |
| Read along | Turn on **Captions**. The sentence being spoken shows at the bottom of the screen |
| Change the talk keys | **Talk shortcut** |
| Make spoken questions free | **Voice > Hear questions > On this Mac**. Speech is turned into text on your Mac instead of the cloud service |
| Get notes or a comparison table | Say *"write down..."*. A notes box opens when the voice finishes, with a Copy button. Tables paste straight into Sheets or Excel |
| Be walked through something | Say *"walk me through it step by step"*. Up to 15 steps, one arrow per step |
| Teach it your taste | Say *"remember, keep answers short"*. Say *"forget..."* to undo. **Memory > Edit** opens the file |
| Type in any app by voice | Hold **Option + Command** and speak. The words land where your cursor is. Speech becomes text on your Mac, nothing is uploaded |
| Get names spelled right | Thambi keeps a **Dictionary** of your course terms. **Voice > Dictionary > Edit** opens the file |
| Cut it off mid-sentence | Turn on **Interrupt by talking** and just start speaking (experimental) |
| Reply to an email | Say *"draft a reply to this"*. The draft opens in the notes box |
| Ask about a whole PDF | Open the PDF and say *"summarise this PDF"*. It reads the text of every page, not just what's on screen |
| See it as a picture | Say *"draw..."*, *"plot..."* or *"show me ... in 3D"*. A drawing box opens: flow charts, trees, message sequences, graphs of functions, and 3D shapes you can turn with the mouse. **Copy** or **Save** it as an image |
| Have it do the clicking | Turn on **Do it for me**, then say *"open TextEdit and type my name"*. See below |

## Your study library

Thambi is a full Mac app now: a study window with a Dock icon, plus the buddy in the menu bar. Open the window from the Dock, with **⌘0**, or from the panel's **Study window** button.

- **Library.** Add PDFs, Word files, PowerPoint slides, photos of your notes and text files, sorted by subject. Drop a folder and its name becomes the subject. Scanned pages and photos are read with the Mac's own text recognition. Originals are never moved or uploaded; Thambi keeps their text in `~/Library/Application Support/Thambi/Library`.
- **Ask.** Type a question and the answer comes from your materials, with numbered sources. Open a source to read the exact passage and jump to the file. Pick a subject to search only that one. Voice questions use your library too when it clearly has the answer.
- **Notes.** Your own Markdown notes, plus answers you save. Notes are searched like any other material.
- **Keep a subject in memory.** Switch it on in the subject's Library page (or right-click the subject). Every question about that subject then carries the whole subject, up to about 15,000 tokens, in a block cached for an hour, so answers know all of it, not just the matching passages.

Finding passages is free and stays on your Mac: words are matched with a standard keyword score and meaning with Apple's on-device sentence model. Only the few passages that answer your question are sent with it.

### Study modes

Pick one at the bottom of the window. It applies to the window, the panel and voice.

| Mode | Thambi can |
|---|---|
| **Read** | Read your materials and screen, and explain. Never saves, types or clicks for you. |
| **Write** (default) | Everything: save notes, draft text, type, and operate your Mac if "Do it for me" is on. |
| **Restricted** | Answer only from your materials, with sources. No outside knowledge, no finished assignment answers, no typing or clicking. Good for honest exam prep. |

## Drawings

Ask for a picture and Thambi draws one: "draw a flowchart of binary search", "draw the TCP handshake", "plot sin x and cos x and mark where they cross", "show me a water molecule in 3D", "draw the surface x squared minus y squared".

Longer drawings build up part by part as Thambi explains them. Ask for a heart, a cell, an engine, DNA, an atom or the solar system and you get a ready-made 3D model with its parts labelled (the engine runs). These models are simple teaching sketches drawn in code, not anatomical scans. Say *"highlight..."*, *"circle..."* or *"underline..."* and Thambi draws the mark on your own screen.

The AI never makes an image. It writes a few short lines describing the picture and your Mac draws it, which is why a drawing adds about one paisa (₹0.005 to ₹0.015) to a question. Where curves cross, where they hit zero and where they peak are calculated on your Mac, not guessed by the AI.

## Do it for me

Off until you switch it on. Then ask for something to be done ("open Calculator and work out 12 times 8") and Thambi does it by looking at your screen, one small step at a time.

- A card at the top of the screen shows the next step and why. **Return** allows it, **Escape** stops everything.
- By default it asks before every step. **Ask me** can be changed to **Once** per task, or **Never** to let it work on its own. Anything risky (Send, Delete, Pay, quitting an app) still asks every time, in every mode.
- Don't want to watch? Turn off **Show each step**. The card then appears only when a step needs your go-ahead, and Thambi's face on the cursor shows it is working.
- It will not touch System Settings, terminals, password managers or password fields, and it ignores instructions written on the screen. Only what you asked counts.
- A task ends after 12 steps at most, and a step you don't answer within a minute stops it.
- Each step sends one screenshot to the AI, the same as a question. Simple tasks take two looks at the screen: one to act, one to check the result.

Asking only to open an app ("open Calculator") costs nothing: Thambi does it without calling the AI. For clicks it reads the names and positions of buttons from macOS, so it presses the one it names.

It is steady with apps, shortcuts and typing. With rows of small look-alike buttons it sometimes mis-aims, notices, and corrects itself, which costs extra steps.

What's next is in [ROADMAP.md](ROADMAP.md). Ideas for drawings, 3D models and further cost cuts are in [futureimplementations.md](futureimplementations.md).

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
| A typed question in the study window, answered from your materials | ~₹0.03 |
| First question about a subject kept in memory (whole subject, cached for an hour) | ~₹0.28 |
| Each follow-up on that subject within the hour | ~₹0.03 |
| Adding materials to your library | ₹0 (read on your Mac) |
| The voice | ₹0, forever (it's on your Mac) |

The trick: Thambi's long instructions are **prompt-cached**, so after your first question they're billed at about a tenth of the price. A whole night of revision costs less than the chai you'll drink during it.

## Privacy, because it can see your screen

- No analytics. No tracking. No auto-updater. Doesn't sneak into your login items.
- Your voice goes to AssemblyAI, and your screenshot plus question go to OpenRouter. That's the whole list.
- API keys live in the **macOS Keychain**: encrypted, this Mac only, never synced, readable only by Thambi.
- Screenshots, audio and answers are never saved to disk.
- Your **study library** stays on your Mac. Adding a file reads it locally (text recognition and meaning search use Apple's on-device models). Only the passages that answer a question are sent with it; for a subject you keep in memory, that subject's text is sent with questions about it. Remove a material and its text is deleted; the original file is never touched.
- Questions typed in the study window send no screenshot.
- Typing by voice and "interrupt by talking" run on your Mac. The microphone sound for those never leaves it.
- The mascot and icons are drawn in code for this project. No borrowed artwork.
- **Memory** is one plain text file on your Mac (`~/Library/Application Support/Thambi/memory.txt`), readable only by you. A line is added only when *you* say "remember..."; nothing on your screen can write to it, and anything that looks like a password, key or long number is refused. Those lines are sent along with each question so the answer can follow them. Empty the file and they're gone.
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
  CompanionPanelView.swift       the menu bar panel: typing box, Stop, speed, shortcut, captions
  NotesMarkdown.swift            the notes box's text: lists, tables, no AI-sounding filler
  CaptionsPanelController.swift  captions at the bottom of the screen
  ThambiMemory.swift             the "remember..." file
  ThambiSettings.swift           voice speed and captions settings
  MainWindow.swift               the study window: Ask, Library, Notes, study mode
  StudyLibrary.swift             passages, search, sources, study modes (pure, unit-tested)
  StudyLibraryStore.swift        reading files, on-device text recognition and meaning, the library on disk
  StudyChat.swift                typed questions answered from your materials
  ClickyShutdown.swift           the big red "go away now" button
voice-server/                  the offline voice (Python)
```

## Credits

Thambi grew out of an MIT-licensed open-source project. The original copyright notice lives in [LICENSE](LICENSE), as it should.

## License

MIT. Do cool stuff with it.
