# Future implementations

Ideas that are not built yet, written so they can be picked up later. Two parts:

1. Showing explanations as 2D drawings, 3D drawings and 3D models on screen, cheaply.
2. More ways to cut cost that were considered but not done.

Prices below use Haiku 5.5 on OpenRouter as read on 2026-11-11 (input $0.10, cached input $0.01,
output $0.50 per million tokens) and ₹94 to the dollar. Token counts for things that do not exist
yet are estimates and are marked as such. Everything under "licences" must be re-checked on the
source's own site before any file is shipped: I wrote those from memory, not from a fresh read.

---

## Part 1: drawings and 3D on screen

### The one rule that keeps this cheap

The AI never produces pixels. It writes a short text description of the picture, and Thambi draws
it on the Mac. Text is billed per token; drawing on the Mac is free.

| What the AI sends | Rough size | Cost per picture |
|---|---|---|
| A generated image (any image model) | n/a | ₹1 to ₹8 each, slow, text in it is often wrong |
| Raw SVG for a diagram | 800 to 2,500 output tokens (estimate) | ₹0.04 to ₹0.12 |
| A compact diagram description (below) | 120 to 400 output tokens (estimate) | ₹0.006 to ₹0.02 |
| The name of a ready-made model plus labels | 30 to 80 output tokens (estimate) | under ₹0.005 |

So the plan is: a small description language for drawings, a local library for 3D models, and
image generation never.

### How it plugs into what exists

Thambi already has the pattern: the answer carries tags (`[POINT:x,y:label]`, `[NOTES]...[/NOTES]`)
that are stripped from speech and acted on locally. Drawings are one more tag:

```
[DRAW]
...a few lines describing the picture...
[/DRAW]
```

- Parsed by a new pure file (like `NotesMarkdown.swift`), unit-tested without a screen.
- Shown in a new panel next to the notes box (reuse `NotesPanelController`'s window code), with
  Copy as image and Save as PNG/PDF.
- Opened only when the user's own words ask for it ("draw", "sketch", "diagram", "show me in 3D"),
  the same gate the notes box uses for "write". That keeps the long instructions out of ordinary
  answers and stops text on screen from triggering it.
- Synced with the voice the way pointing is: each part of the drawing can appear when the sentence
  about it is spoken. This is the feature that makes it feel like a teacher at a board.

To keep the main instructions short (they ride with every question), the drawing rules should
live in a second cached block that is only sent when the gate fires.

### Status (2026-11-11)

Built and installed: Stage 1 (`flow` including trees and graphs, `sequence`, `plot` with roots,
crossings and peaks calculated on the Mac) and Stage 3 (`scene3d` shapes, bonds, arrows, axes and
`surface`). Measured on six real requests: 98 to 324 output tokens per drawing, which is ₹0.005
to ₹0.015 added to a question. On 2026-11-16 these were added: parts that appear in step with
the voice, marks over the screen (Stage 2), and six code-drawn models (a first Stage 4: heart,
cell, engine, DNA, atom, solar system). The models are schematic. Still to do: the `molecule:`
and `lattice:` shortcuts, PDF export, more models, and accurate ones from open sources.

### Stage 1: 2D diagrams (built)

A line-based description the model can write reliably and Thambi can draw with SwiftUI `Canvas`.

```
[DRAW]
type: flow
title: TCP three-way handshake
box client "Client"
box server "Server"
arrow client -> server "SYN"
arrow server -> client "SYN-ACK"
arrow client -> server "ACK"
[/DRAW]
```

Diagram types worth supporting, in order of usefulness for college work:

1. `flow`: boxes and arrows (protocols, algorithms, state machines). Needs automatic layout:
   a simple layered layout (longest-path layering, then order by barycentre) is enough.
2. `sequence`: lifelines and messages (networking, operating systems).
3. `tree`: binary trees, parse trees, heaps (data structures). Reingold-Tilford layout.
4. `graph`: nodes and weighted edges (Dijkstra, MST). Force-directed layout, fixed seed.
5. `table` and `array`: memory layouts, sorting steps.
6. `plot`: `plot y = sin(x) from -6 to 6`. Evaluate the expression locally with a small parser
   (never `NSExpression` on model text, and never run code the model wrote).
7. `timeline` and `venn`.

Why a custom format and not Mermaid: Mermaid needs a JavaScript engine in a web view, which is a
large dependency and a bigger attack surface. A 200-line Swift parser covers the list above. If
Mermaid is wanted later, render it in a `WKWebView` with JavaScript restricted to the bundled
script and no network.

Steps as animation: `step 2: highlight server`, `step 3: add arrow ...`. The drawing then replays
as the voice reaches each sentence, using the same segment callbacks pointing uses.

Work: about 3 to 5 days. Cost per drawing: about ₹0.01 (estimate).

### Stage 2: drawing on top of the user's screen

Thambi already draws an arrow on the overlay. Extend the overlay tag set so the model can annotate
what is on screen instead of redrawing it:

```
[MARK:box:120,200,460,320:the loop body]
[MARK:underline:500,410,720,410:this term]
[MARK:circle:880,150,40:the bug]
```

Coordinates are screenshot pixels, converted exactly as `[POINT]` is today. This is the cheapest
"drawing" there is (10 to 20 tokens per mark) and it explains the user's own slide or code.
Marks clear when the answer ends or Escape is pressed. Work: 2 to 3 days.

### Stage 3: 3D drawn from simple shapes (built)

For things that are geometry: vectors, planes, coordinate systems, crystal lattices, molecules,
network topologies, simple mechanics. The model sends a small scene list and SceneKit builds it:

```
[DRAW]
type: scene3d
title: Methane
sphere C at 0,0,0 r 0.4 color grey
sphere H1 at 0.63,0.63,0.63 r 0.25 color white
sphere H2 at -0.63,-0.63,0.63 r 0.25 color white
bond C H1
bond C H2
label C "carbon"
[/DRAW]
```

- Shapes: sphere, box, cylinder, cone, plane, line, arrow, text label. All are SceneKit built-ins.
- The panel hosts an `SCNView` with `allowsCameraControl` so the user can rotate and zoom with the
  trackpad. Slow automatic turntable rotation while Thambi talks; stop it for Reduce Motion.
- Cap the scene (say 150 shapes) so one answer cannot run up output cost or stall the Mac.
- For known families, send even less: `molecule: CH4` or `lattice: fcc` and compute positions
  locally from a small table. That is 10 tokens instead of 150.
- 3D function surfaces: `surface z = sin(x) * cos(y)` evaluated locally into a mesh.

Use SceneKit, not RealityKit: SceneKit works on macOS 14 with no extra setup and loads USDZ.
(Apple has said SceneKit is in maintenance; it still works, and the scene description above does
not depend on it, so the renderer can be swapped later.)

Work: about 5 to 7 days. Cost per scene: ₹0.01 to ₹0.02 (estimate).

### Stage 4: ready-made 3D models from a local library

For real objects (a heart, a cell, an engine, a transistor, the solar system) the model must not
try to build geometry. Ship or download a small library of USDZ files with a text index, and the
model only picks one and says what to point at:

```
[DRAW]
type: model
model: human-heart
show: left ventricle, aorta
[/DRAW]
```

- `models/index.json` lists each model: id, title, keywords, named parts with a 3D anchor point,
  source and licence. The index (names and keywords only) is what the model sees; it is small and
  can be cached. If nothing fits, the model falls back to a Stage 1 diagram.
- Named parts make it teachable: the camera flies to "aorta" and a label appears when the voice
  says it. Anchors are set by hand once per model.
- Keep the app small: ship 10 to 20 models for the most common subjects and make the rest an
  optional download pack the user chooses. Never fetch a model silently.
- Convert sources to USDZ with Apple's Reality Converter or `usdzconvert`, and reduce polygon
  counts so they render on any Mac.

Where to get models that are safe to ship (verify each licence on the site before use):

| Source | What it has | Licence to confirm |
|---|---|---|
| Smithsonian Open Access (3d.si.edu) | Scanned museum objects, fossils | CC0 for items marked Open Access |
| NASA 3D Resources | Spacecraft, planets, terrain | Generally free to use, with NASA's media rules |
| Poly Haven | Objects and scenes | CC0 |
| Kenney.nl | Simple low-poly objects | CC0 |
| NIH 3D (3d.nih.gov) | Molecules, anatomy, lab models | Varies per model; filter for CC0 or CC BY |
| RCSB Protein Data Bank | Protein structures (coordinates, not meshes) | Data is free to use; build the mesh locally |
| Sketchfab | Everything | Per model; only CC0 or CC BY, and CC BY needs credit |

Avoid: models from Apple's AR Quick Look gallery, game rips, and anything "free for personal use".
Record the source and licence of every shipped model in the index and in a CREDITS file.

Work: 1 to 2 weeks for the viewer and index, then ongoing curation. Cost per use: under ₹0.005.

### Stage 5 (later, optional): generated 3D

Text-to-3D services exist and cost real money per model, take tens of seconds, and the results
are rarely accurate enough to teach from. Not recommended for a study tool. If it is ever added,
make it opt-in, show the price before generating, and cache every result on disk so the same
request is never paid for twice.

### Making it look professional

- One visual language for every drawing: the existing tokens (graphite ground, hairline strokes,
  cool blue for Thambi's emphasis, amber for the part the user asked about), one type size scale,
  2px strokes, rounded joins. Students should recognise a Thambi diagram at a glance.
- Light and dark versions; export always uses the light one so it prints.
- Every drawing has a text alternative (the description itself, read by VoiceOver).
- Motion only to show order: parts appear as they are spoken. No decoration, and a still version
  for Reduce Motion.
- Export: PNG at 2x, PDF (vector) for reports, and "Copy" for pasting into notes.

### Safety rules to carry over

- The description is data, never code. No scripts, no file paths, no URLs inside it; unknown lines
  are ignored. Models are referenced by id from the local index only.
- Hard caps on shapes, text length and canvas size.
- Only the user's own words open a drawing, never text seen on screen.

### Suggested order

1. Stage 2 (marks on the screen): smallest, reuses the overlay.
2. Stage 1 `flow`, `tree`, `plot`.
3. Voice-synced steps for Stage 1.
4. Stage 3 with the `molecule:` and `surface` shortcuts.
5. Stage 4 with ten hand-picked models.

---

## Part 2: more ways to cut cost (not done yet)

Done already, for reference: prompt caching, Haiku by default, shorter screenshots (1152 px for
questions, 1024 px for control), opening an app with no AI call, chained steps in one look,
finishing sure-thing tasks without a second look, named buttons read from macOS instead of
guessed, shortened history, and an on-device speech option.

| Idea | Expected saving | Risk or cost | Notes |
|---|---|---|---|
| Send no screenshot when the question is not about the screen | About 60% of a question's uncached input | A wrong guess means an answer that ignores the screen | Decide locally from the words ("this", "here", "on screen", "slide" mean send it). Let the model ask for the screen with a tag when it needs it. |
| Crop the screenshot to the front window | 30 to 70% of image tokens when the window is small | Loses context from other windows | `SCContentFilter` can capture one window. Coordinates need an offset. |
| Control steps with no screenshot at all | About 85% of a step | Only works where apps expose good accessibility names | Send the named-controls list and window title as text; fall back to a screenshot when the list is thin. |
| Local shortcuts for more tasks | 100% for those tasks | Each one is a rule to maintain | "new tab", "close window", "volume up", "open <website>" need no AI. Same pattern as `appNameToOpenDirectly`. |
| Remember solved tasks | Close to 100% on repeats | A remembered plan can go stale | Store the action list for a task the user repeats and replay it with the name checks. Ask before replaying. |
| One-hour cache for the instructions | Avoids the cold-start write after 5 idle minutes | A longer cache costs more to write | Check whether OpenRouter passes the longer cache option through for Haiku before relying on it. |
| Shorter instructions | A few percent | Quality regressions | The instructions are already cached at a tenth of the price, so the gain is small. Measure before trimming. |
| Batch or offline model for non-urgent work | About half | Not instant | Only fits things like "summarise today's notes tonight". |
| A cheaper provider key (the "jev" key) | Depends on its prices | Unknown quality and privacy | Compare on the same ten real tasks before switching. Keep the key in the Keychain, never in a file. |
| On-device model for the "is this a task" decision | Removes the hand-off call | Needs a local model download | Only worth it if the hand-off turns out to be common. |

Measure every one of these on real tasks before keeping it: a cheaper step that needs an extra
step to recover is not cheaper. The test hooks (`-ThambiDebugControlTask`, `-ThambiDebugControlLive`,
`-ThambiDebugQuestion`) print token counts for exactly this.

## Part 3: features for studying (researched and planned, 2026-11-16)

Where these come from: a full test pass of the app (below), what the leading study tools do (NotebookLM's flashcards, quizzes, mind maps and audio overviews; Quizlet and Knowt for flashcards; Indian previous-year-paper apps), the "learning modes" ChatGPT, Gemini and Claude added in 2025, and learning research. In that research, practice testing and spaced practice come out as the two most effective study techniques: quizzing improves results by about half a standard deviation (Hedges' g ≈ 0.50), and spaced practice beats cramming by g ≈ 0.5 to 0.74. Most of Thambi today *explains*; the biggest gains are in making students *recall*.

Every idea is held to the same three rules: cost (a normal action stays near ₹0.03), privacy (stays on the Mac unless it must go to the AI service), safety (nothing done without the student's say-so).

### Ranked

| # | Feature | Why it matters | Cost to run | Effort |
|---|---|---|---|---|
| 1 | **Quiz me** on a subject or note | Retrieval practice, the strongest technique. Questions come from the student's own passages, each with its source; answers are checked and the wrong ones explained. Restricted mode friendly. | ~₹0.03 for 5 questions; checking an answer ~₹0.01 | Medium |
| 2 | **Flashcards with spaced review (FSRS)** | Spaced practice. Cards made from materials, notes or a quiz's wrong answers; reviewed daily in the window. FSRS is open source and in published benchmarks predicts forgetting better than Anki's older SM-2. Reviewing never calls the AI. | Making 10 cards ~₹0.03; reviews free | Medium |
| 3 | **Exam planner with previous-year papers** | Indian university exams repeat topics. Add PYQ papers to a subject; Thambi maps each question to a unit, counts what repeats and how many marks it carries, and builds a day-by-day plan to the exam date that spaces revision and puts heavy topics first. | One pass per paper ~₹0.05; plan is computed locally | Medium |
| 4 | **Answer in marks format** | "Answer for 2 / 5 / 10 marks": definition, diagram (the drawing engine), example, points, sized to the marks. Matches how answers are graded here. | Same as a question | Small |
| 5 | **Teach-back (Feynman) mode** | The student explains a topic by voice; Thambi compares it with their materials, says what was right, missing or wrong, and asks one guiding question. Uses the existing voice and library. | ~₹0.03 per attempt | Small |
| 6 | **Concept map of a subject** | NotebookLM's most-used visual. One call outlines the subject's topics; the existing flow/tree drawing engine draws it; clicking a topic asks about it. | ~₹0.02 per map | Small |
| 7 | **Spoken revision of a unit** | Like NotebookLM audio overviews, but the voice is already free and offline. One call writes a 5-minute script from the unit; the local voice reads it. Pause and ask questions mid-way. | ~₹0.04 per script; voice free | Small |
| 8 | **Open the source at the exact page** | Sources already know the page. Show the PDF inside the window, scrolled to the page with the passage highlighted (PDFKit), instead of opening the whole file. | Free | Small |
| 9 | **Indian-language questions and answers** | Thambi is a Tamil name. Apple's newer on-device contextual embeddings cover many scripts, so a Tamil or Hindi question can find English notes; answers can be explained in Tamil, Hindi or a mix, spoken by a matching voice. | Same as a question | Medium |
| 10 | **Lecture to notes** | Record a lecture (with the lecturer's permission), transcribe on the Mac (Apple Speech, free), turn it into notes that join the library. | Transcription free; notes ~₹0.05 per hour | Medium |
| 11 | **Free offline answers (optional)** | A small model run on the Mac (Gemma or Qwen at 4-bit, around 35 words a second on an 8 GB Mac) for Restricted-mode questions over the student's materials. Zero cost and works offline; weaker than Haiku, so opt-in and labelled. Needs a ~4 GB download the student approves. | Free | Large |
| 12 | **Import from iPhone** | Continuity Camera: photograph a page or whiteboard on the iPhone and it lands in the library, read by the Mac's text recognition. | Free | Small |
| 13 | **Study time and streaks, kept on the Mac** | Focus timer (Pomodoro), minutes per subject, cards due. Nothing leaves the Mac. | Free | Small |
| 14 | **Export** | Notes to PDF; flashcards to an Anki deck (`.apkg`) or CSV, so students are never locked in. | Free | Small |

### Smaller improvements found while testing

- Library: "Dismiss all" for failed files; rename a subject; drag a material onto a subject.
- A search box over all materials and notes (⌘K), free and local.
- Ask: a "regenerate" button, and showing the cost of each answer next to it (from the token counts already measured).
- Keep in memory: show how much of a subject fits ("all of it" or "first 60%") and when the cache will expire.
- Retrieval check: a small set of known questions per test subject, run after each change, so search quality is measured, not guessed (dev tool).

### Not recommended

- Downloading other people's notes or shared decks: copyright and quality problems, and it breaks the "your own materials" promise.
- Cloud sync of the library: a server would see students' materials. If ever wanted, iCloud Drive files only, end-to-end, opt-in.
- An exam "lock" that stops the student switching modes: Thambi is the student's tool, not a proctor.

### Suggested order

Build 4 and 8 first (small, immediately useful), then 1 and 2 together (quiz wrong answers become flashcards), then 3. That turns Thambi from an explainer into a revision system, at about the same cost per day.

### Test pass that informed this (2026-11-16)

- Unit tests moved into the repo (`Tests/`, run with `scripts/run-tests.sh`): 106 checks of the pure rules, plus a drawing suite, all passing. The earlier tests had been lost with a temporary folder.
- Bugs found and fixed: "write-ahead log" counted as a request to write (would have auto-saved notes); a stopped answer could re-enable Ask during the next answer; renaming a note was lost; huge text, Word or slide files were read without a size limit; source numbers from earlier answers leaked into the next question's history; the panel did not show the study mode even though it governs voice answers; the reason a file type was refused didn't name the file.
- Library: 400-page PDF read in about 30 seconds; search over 5,000 passages takes 2 ms; meaning vectors now stored as binary (library loads about 7 times faster, half the size; old libraries still open). Empty, damaged, password-locked, Pages and unknown files each get a clear message; folders become subjects; hidden files are skipped; re-adding a file replaces it.
- Voice answers use the library only when it plainly answers (a general-knowledge question sent no passages); Restricted mode treats the screen as the student's own material, now stated in the instructions.
