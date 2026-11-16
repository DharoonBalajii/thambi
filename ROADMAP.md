# Thambi roadmap

Thambi's goal: a study buddy that is **cheap, private and fast** enough for a college student to use every day.

Every feature below is judged against three rules:

1. **Cost.** A normal question should stay around ₹0.02–0.04. Anything that bills per minute or runs in the background needs a clear reason.
2. **Privacy.** Nothing leaves the Mac except the question, the screenshot and (optionally) the audio for transcription. No accounts, no Thambi server.
3. **Safety.** Thambi reads the screen. It does not act on it unless the user turns that on and approves each action.

## Already in Thambi

- [x] Hold a shortcut (Control + Option), ask out loud; it sees the screen and answers out loud
- [x] Points at things on screen, in time with the voice, without covering content
- [x] Follow-up questions (remembers the last 10 exchanges)
- [x] Notes box for "write down..." requests, with Copy
- [x] Haiku by default, Sonnet only for hard questions; prompt caching
- [x] Local neural voice (free, offline), macOS voice fallback
- [x] Acronyms spelled out ("E S P")
- [x] API keys in the macOS Keychain
- [x] On-device transcription option (Apple Speech)
- [x] Shut down & remove access button
- [x] Full Mac app: study window (Ask, Library, Notes) beside the menu bar buddy
- [x] Study library: PDFs, Word, slides, photos of notes, text; searched on the Mac by words and meaning; answers cite their sources
- [x] Study modes: Read, Write, Restricted (answers only from your materials, no finished work)
- [x] Keep a subject in memory: whole subject in an hour-long cached block

## Phase 1: everyday basics (free to run, small changes)

- [x] Voice speed control (0.5x–1.5x) in the panel
- [x] Stop button and Escape to stop the voice
- [x] Type a question instead of speaking (text box + shortcut)
- [x] Custom push-to-talk shortcut
- [x] Captions: show what Thambi is saying
- [x] Step-by-step walkthroughs (up to 15 steps, one arrow per step)
- [x] Tables in the notes box
- [x] Remove em dashes and other AI tells from written notes
- [x] Memory file: reply preferences Thambi keeps between sessions (plain text, on the Mac)
- [x] Lower idle CPU (hidden animations paused; voice model unloads after 10 idle minutes)

## Phase 2: dictation and reliability (free to run, medium changes)

- [x] Type anywhere by voice (dictation), using on-device speech by default
- [ ] Optional cleanup pass with Haiku (about ₹0.01 per paragraph)
- [x] Learned dictionary for course terms and names
- [x] Dictation languages (whatever Apple Speech supports on the Mac)
- [x] Barge-in: start talking to interrupt the voice (off by default; experimental until tested in noisy rooms)
- [x] Bluetooth audio switching and mic failover
- [x] Screen-aware reply drafting ("draft a reply to this email")
- [x] Whole-document understanding (read the open PDF's text instead of one screenshot)

## Phase 3: opt-in power features (cost money or need new permissions)

Each of these is off by default and needs the user's explicit OK.

- [ ] Skills library (saved prompts such as "quiz me on this slide")
- [ ] Routines created by asking ("every evening, summarise today's notes"); pause after three failures
- [ ] Integrations: Google Workspace, Notion (needs sign-in to those services)
- [x] Computer control: "open TextEdit and type..." done one approved step at a time, Escape to stop (off by default)
- [x] Drawings: flow charts, trees, sequences, plots and turnable 3D shapes, described by the AI in a few lines and drawn on the Mac (about ₹0.01 each)
- [x] Drawings that build up in step with the voice; marks drawn over your own screen; six code-drawn 3D models (heart, cell, engine, DNA, atom, solar system)
- [ ] More 3D models, and anatomically accurate ones from openly licensed sources
- [ ] Computer control in web browsers and long tasks (needs a stronger model per step, so it costs more)
- [ ] Long-running agent jobs

## Not planned

| Feature | Why |
|---|---|
| Realtime voice | Billed per minute; many times the cost of the current setup |
| Named agents, multi-agent, "always approve" | High cost and risk for little study value |
| Accounts, multiple accounts, account deletion | Thambi has no server and no accounts, by design |
| Windows version | A separate app (the code is AppKit/SwiftUI); possible later as its own project |
| Chrome extension, Spotify | Outside the study-buddy goal |
| Notch UI | Cosmetic; revisit after Phase 2 |
