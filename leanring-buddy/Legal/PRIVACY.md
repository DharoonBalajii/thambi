# Thambi Privacy Policy

Version 1, 17 November 2026. Draft: have a lawyer review this before public release, and fill in the items in [square brackets].

## The short version

- Thambi has no accounts, no analytics, no advertising and no server of its own. The people who make Thambi receive nothing from your Mac.
- Your study materials, notes, flashcards, messages and settings are stored only on your Mac.
- To answer a question, Thambi sends that question and the few passages it needs to the AI service, using your own key. To understand your voice, it sends the audio of your question to the speech service, unless you choose on-device speech.
- Friends is off until you turn it on. It works directly between Macs on the same network.

## Who is responsible

Thambi is published by [name of person or company], [address]. Contact: [contact email].

## What stays on your Mac

| What | Where | How to delete it |
|---|---|---|
| Text of the materials you add, and your notes | `~/Library/Application Support/Thambi` | Remove the material or note in the app, or delete the folder |
| Flashcards, quiz results, study minutes and streak | Same folder and the app's preferences | Delete the card, or delete the folder |
| Friends, their last status, and your conversations | Same folder | Remove the friend, or delete the folder |
| What you asked Thambi to remember about how you like answers | `memory.txt` in the same folder | Edit it from the menu bar panel |
| Your API keys | The macOS Keychain, readable only on this Mac while it is unlocked | "Shut down and remove access" in the panel, or Keychain Access |

Original files are never moved, copied elsewhere or uploaded. The folder and its files are readable only by your macOS user account. Thambi does not encrypt them itself; turn on FileVault in macOS so that everything on your disk is encrypted.

## What leaves your Mac, and when

**1. Questions, to the AI service (OpenRouter).** Sent only when you ask something, make a quiz or cards, or have an answer checked:

- your question, and the last few questions and answers of that conversation;
- the passages from your materials that match the question (a few paragraphs), or, for a subject you chose to "Keep in memory", the text of that subject;
- for a spoken question, one picture of your screen, because the question is about what you are looking at. Typed questions in the study window send no picture;
- the lines in your memory file.

These go to `openrouter.ai` over an encrypted connection, with the key you added. OpenRouter passes the request to the model provider (Anthropic). Their handling of it is covered by their own privacy policies, and depends on the settings of your OpenRouter account. Thambi sends no name, email address or device identifier with a request.

**2. Your voice, to the speech service (AssemblyAI).** Only while you hold the talk keys, the audio of your question is streamed to `assemblyai.com` to be turned into text, using the key you added. Choose "on this Mac" in the panel to use Apple's on-device speech recognition instead; then no audio leaves your Mac.

**3. Friends, to the friends you accepted.** Only if you turn Friends on:

- your chosen name is visible to other Thambi users on the same local network who also turned it on;
- friends you accepted receive your study status (activity, subject name, how long, minutes today, streak), your messages, and anything you choose to share (a note, flashcards, a drawing or 3D model);
- this travels directly between the two Macs, encrypted, without passing through any server.

A status never includes your screen, your materials, your questions or Thambi's answers.

**4. "Do it for me".** If you turn on computer control, Thambi sends a picture of your screen with each step to the AI service so it can decide what to click. It is off by default, and steps like Send, Delete and Pay always wait for you.

Nothing else is sent. Thambi does not contact its makers, check for updates, or report usage or crashes.

## What we do not do

- We do not sell, rent or share your data, because we do not receive it.
- We do not use your materials to train any model.
- We do not track you across apps or websites.

## Permissions Thambi asks for

Microphone (to hear a spoken question), Screen Recording (to see what a spoken question is about), Accessibility (to point at things and, if you allow it, to click and type), Local Network (only for Friends). Each can be withdrawn in System Settings, Privacy and Security. "Shut down and remove access" in the panel withdraws them all.

## Your choices and rights

You can see, correct, export and delete everything Thambi holds, because it is all on your Mac in ordinary files. Deleting the app's folder and removing the app erases it. For what the AI and speech services hold, use the rights those services offer under their policies. If the law where you live gives you further rights (for example India's Digital Personal Data Protection Act or the EU's GDPR), you can contact us at [contact email].

## Age

Thambi is meant for students aged 18 and over. If you are younger, use it only with a parent's or guardian's consent.

## Security

Keys are kept in the Keychain, never in files. Connections to the services use TLS. The voice engine listens only on this Mac. Messages from friends are size-limited and treated as text, never as instructions or code. No software is perfectly secure; report a problem to [security contact email] and we will respond.

## Changes

If Thambi ever starts collecting anything (for example, optional anonymous usage counts), this policy will change first, the app will show you the new version, and collection will be off until you agree. The version number and date at the top tell you which policy applies.
