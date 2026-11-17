# Releasing Thambi to the public: architecture, privacy and threats

Written 17 November 2026. This is the plan; the "Status" columns say what is already true in the code.

## 1. The one decision everything hangs on

Today each person brings their own AI key. That keeps Thambi serverless and private, but most students will not create an OpenRouter account. There are three ways to give the public AI answers:

| Option | How it works | Privacy | Cost to you | Effort |
|---|---|---|---|---|
| A. Bring your own key (today) | Student pastes an OpenRouter key | Best: you receive nothing | None | Done |
| B. Thambi Cloud | Students sign in; your server holds the provider key and forwards requests | You become a data processor; needs strict no-logging | You pay for every answer (about ₹0.03 each) plus hosting | Large |
| C. On-device model | A local model answers, free and offline | Best: nothing leaves the Mac | None | Medium; weaker answers on 8 GB Macs |

**Recommendation:** release with A and C. Add B later as an opt-in, with a free daily allowance and the design in section 4. Do not make B the only way in: it makes privacy a promise instead of a fact.

## 2. Getting it onto anyone's Mac

1. **Apple Developer Program** (paid, yearly). Needed for a Developer ID certificate. Without it every user sees "cannot be opened".
2. **Sign with Developer ID, hardened runtime on, then notarize** with `notarytool` and staple the ticket. Notarization is Apple scanning the build for malware; it is what lets Gatekeeper open it.
3. **Ship a signed DMG** from a GitHub Release, with a SHA-256 checksum on the release page.
4. **Not the Mac App Store** for now: it requires the App Sandbox, and pointing, typing for you and screen reading do not work well inside it.
5. **Updates:** Sparkle with EdDSA-signed updates served over HTTPS from GitHub Releases. This is a new network call ("is there a new version?"), so the privacy policy must say so first. It sends no personal data.
6. **The voice engine:** the Python voice server and its model must be bundled or replaced by Apple's built-in voices for the public build. Downloading a model on first run needs a pinned checksum and the user's go-ahead.
7. **First run:** the consent screen (built), then a three-step setup: add materials, choose how answers are made (key or on-device), try one question.

## 3. Threat model

What could go wrong, what stops it, and whether that is in place.

| # | Threat | Protection | Status |
|---|---|---|---|
| 1 | API keys stolen from disk | Keys only in the Keychain, this-device-only, never in files or logs | Done |
| 2 | Another macOS account reads notes or messages | Data folder 700, files 600, set at every launch | Done (today) |
| 3 | Stolen or lost Mac | FileVault encrypts the disk; policy tells users to turn it on | Advice only. To do: encrypt friends' messages with a Keychain-held key |
| 4 | Traffic read on public Wi-Fi | TLS to OpenRouter and AssemblyAI; friends' sessions encrypted | Done. To do: certificate pinning for the two hosts |
| 5 | A web page talks to the local voice server | Bound to 127.0.0.1 and needs a header pages cannot send | Done |
| 6 | Poisoned PDF tells the AI what to do (prompt injection) | Sources are marked as reading material, never instructions; citations are checked against the list | Done. To do: strip hidden text and tiny fonts on import |
| 7 | Poisoned material makes "Do it for me" act | Control is off by default, asks before each step, and always asks for Send, Delete and Pay | Done |
| 8 | A stranger on the Wi-Fi pretends to be a friend | Friends must show a shared secret agreed at pairing; unknown peers can only send a request | Done. To do: per-device key pairs and a verification code both friends compare, to stop interception at first pairing |
| 9 | A friend's Mac floods or sends huge data | 600 KB packet cap, text and card caps, 40 messages a minute, 10 pending requests | Done (today) |
| 10 | A shared drawing or note runs code | Drawings are parsed by a fixed grammar and drawn locally; notes are text; nothing is executed | Done |
| 11 | Malicious archive in a .pptx (zip bomb) | Entry size capped at 8 MB, file size at 30 MB, page and passage caps | Done |
| 12 | Screenshot captures a password or bank page | Screenshot only on a spoken question, one display | Partly. To do: skip capture when a password field or a private window is in front; a "never capture these apps" list |
| 13 | Tampered download or update | Developer ID signature, notarization, signed updates | To do (section 2) |
| 14 | Compromised dependency | Only Apple frameworks in the app; Python voice server pinned by hash | Partly. To do: lock file with hashes, a software bill of materials in each release |
| 15 | Debug hooks left in a release | Release audit checks no debug strings and no keys in the binary | Done (run before every install) |
| 16 | Runaway cost on the user's key | Output caps, history shortened, cost shown per answer | Done. To do: a daily spend limit the user sets |
| 17 | The AI provider keeps the data | User's own account and its retention settings; policy says so | Disclosed. To do: recommend zero-retention settings in setup |
| 18 | Whole-app compromise through a bug | Hardened runtime | Partly. To do: turn on the App Sandbox with only the entitlements needed |
| 19 | Someone finds a hole and has nowhere to report it | — | To do: SECURITY.md with a contact and a response time |
| 20 | Data left behind after uninstall | "Shut down and remove access" clears keys and permissions | Partly. To do: one "Erase everything" button that also deletes the data folder |

## 4. If you add a backend (Thambi Cloud)

Design it so that a leak of the whole database reveals almost nothing.

- **Accounts:** Sign in with Apple or an email magic link. No passwords to leak. Store a user id, a hashed email, plan and counters. Nothing else.
- **AI proxy:** a stateless service that checks the session, checks the allowance, forwards the request to the provider with zero-retention turned on, streams the answer back, and writes one row: user id, time, model, token counts, cost. **Never the question, the passages, the screenshot or the answer.** Request bodies are excluded from logs, traces and error reports at the framework level.
- **Friends relay:** each device makes a key pair; the public key is the identity. Messages and shared notes are encrypted on the sender's Mac for the friend's key (end to end). The server routes sealed envelopes and deletes them on delivery. Presence ("studying DBMS, 12 min left") is also sent sealed to friends only; the server sees "online" at most.
- **The app's seam is ready:** `StudySocialTransport` is the only piece that changes; `NearbyTransport` stays as the offline path.
- **Hosting basics:** managed Postgres with encryption at rest, row-level security per user, secrets in a secret manager, least-privilege service roles, rate limits per account and per IP, a web application firewall, dependency scanning in CI, backups encrypted and tested, an India or EU region stated in the policy.
- **Admin access:** single sign-on with a hardware key or passkey, no shared admin password, every admin action written to an append-only audit log, and no admin screen that can show a user's content, because the server never has it.
- **Deletion:** "Delete my account" removes the row and counters within the stated period, automatically.

## 5. Admin statistics without breaking the privacy promise

"Stats of everyone and everything" and "your data never leaves your Mac" cannot both be literally true. What an admin legitimately needs is the shape of usage, not the contents. Three levels, in order of how much they ask of the user:

1. **Nothing collected (today).** Use GitHub release download counts and stars. No policy change.
2. **Opt-in anonymous counts.** Off by default. Once a day the app sends a few numbers: app version, macOS major version, and how many times each feature was used (questions, quizzes, cards reviewed, focus minutes rounded to 15). No account, no device id, no IP stored, no subject names, no text. The server adds them into daily totals and discards the rows. The dashboard shows only totals, and hides any group smaller than 20 people.
3. **With accounts (Thambi Cloud).** The proxy's counter rows give per-account usage and cost exactly, which you need for billing and abuse control: active users, answers per day, tokens, cost, error rates, retention by signup week. Still no content.

The admin dashboard under level 2 or 3 would show: installs and active users by day and week, feature adoption, answers and cost per day, error and latency rates, retention curves, version spread. It would never show: questions, notes, materials, messages, screenshots, subject names, friend lists.

**The rule:** the policy changes first, the app shows the new version, and collection stays off until the person agrees. The current policy already commits to this.

## 6. Legal checklist before going public

- Fill in the publisher name, address and contact in `leanring-buddy/Legal/PRIVACY.md` and `TERMS.md`, and have a lawyer review both. They are drafts.
- India's Digital Personal Data Protection Act: with no backend you process almost nothing. With a backend you are a data fiduciary: notice, consent, a grievance contact, breach notification, and verifiable parental consent under 18. Decide the minimum age.
- Keep the upstream MIT notice in LICENSE; add the Plus Jakarta Sans licence (OFL) to an "Acknowledgements" screen.
- Make the GitHub repository public before calling the app open source.
- Publish the policy and terms on a web page too; app stores and universities ask for a link.
