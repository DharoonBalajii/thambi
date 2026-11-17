// Tests for the pure rules: memory, dictionary, dictation text, computer-control safety,
// notes, speech helpers, settings and model routing. Run with scripts/run-tests.sh.
import Foundation

var failures = 0, passes = 0
func check(_ ok: Bool, _ name: String) { if ok { passes += 1 } else { failures += 1; print("FAIL:", name) } }

// MARK: Memory
check(ThambiMemory.userAskedToRemember("remember that I'm in second year CSE"), "remember gate")
check(!ThambiMemory.userAskedToRemember("what is a memory leak"), "memory word is not remember")
check(ThambiMemory.userAskedToForget("forget that I like short answers"), "forget gate")
let memoryTags = ThambiMemory.extractTags(from: "sure. [REMEMBER: keep answers short] done [FORGET: old thing]")
check(memoryTags.remember == ["keep answers short"] && memoryTags.forget == ["old thing"] && !memoryTags.text.contains("["), "memory tags extracted and removed")
check(ThambiMemory.sanitizedEntry("my password is hunter22") == nil, "password refused")
check(ThambiMemory.sanitizedEntry("my number is 98765 43210") == nil, "phone number refused")
check(ThambiMemory.sanitizedEntry("key sk-or-v1-abcdef123456") == nil, "API key refused")
check(ThambiMemory.sanitizedEntry("- keep answers short") == "keep answers short", "bullet stripped")
var memoryFile = ThambiMemory.adding(["keep answers short", "keep answers short", "I study DBMS"], to: "")
check(ThambiMemory.entries(in: memoryFile) == ["keep answers short", "I study DBMS"], "no duplicate memory entries")
memoryFile = ThambiMemory.removing(matching: ["DBMS"], from: memoryFile)
check(ThambiMemory.entries(in: memoryFile) == ["keep answers short"], "forget removes matching line")
check(ThambiMemory.promptSection(for: "").isEmpty, "empty memory sends nothing")
let many = ThambiMemory.adding((1...40).map { "preference number \($0) here" }, to: "")
check(ThambiMemory.entries(in: many).count == ThambiMemory.maximumEntries, "memory capped")

// MARK: Dictionary and dictation
let dictionaryFile = "# header\nKerberos\ncare boss -> Kerberos\nIPsec\n"
check(ThambiDictionary.entries(in: dictionaryFile).terms.contains("Kerberos"), "dictionary term read")
check(ThambiDictionary.applying(dictionaryFile, to: "the care boss protocol and ipsec") == "the Kerberos protocol and IPsec", "corrections and casing applied")
check(ThambiDictionary.applying(dictionaryFile, to: "carebossing") == "carebossing", "corrections only on whole words")
let learned = ThambiDictionary.adding(["Diffie Hellman", "dif e -> Diffie"], to: "", allowCorrections: false)
check(ThambiDictionary.entries(in: learned).corrections.isEmpty && ThambiDictionary.entries(in: learned).terms == ["Diffie Hellman"], "corrections need the user's words")
check(ThambiDictionary.sanitizedTerm("this is far too many words to be one term") == nil, "long phrase refused")
check(DictationText.prepared("hello world new line second line", dictionaryFileContents: "") == "Hello world\nSecond line ", "new line command")
check(DictationText.prepared("   ", dictionaryFileContents: "") == nil, "empty dictation types nothing")

// MARK: Computer control
check(ComputerControl.userAskedToOperate("open calculator"), "open is a task")
check(ComputerControl.userAskedToOperate("Hey Thambi. Could you please open Notes."), "polite lead-in")
check(!ComputerControl.userAskedToOperate("what does open source mean"), "question is not a task")
check(!ComputerControl.userAskedToOperate("explain how to open a file in C"), "explain is not a task")
check(ComputerControl.userAskedToOperate("the save button, click it for me"), "for me with action word")
check(!ComputerControl.userAskedToOperate("draft a reply to this email"), "draft is not a task")
check(ComputerControl.appNameToOpenDirectly("open calculator please") == "calculator", "direct open")
check(ComputerControl.appNameToOpenDirectly("open the notes app") == "notes", "direct open strips the/app")
check(ComputerControl.appNameToOpenDirectly("open safari and search for cats") == nil, "compound task needs AI")
check(ComputerControl.appNameToOpenDirectly("open the file on my desktop") == nil, "file needs AI")
check(ComputerControl.taskNeedsResultRead("work out 45*19 in calculator"), "sum needs a look")
check(!ComputerControl.taskNeedsResultRead("open notes"), "open needs no second look")
check(ComputerControl.isBlockedApp(bundleIdentifier: nil, name: "Terminal"), "terminal blocked")
check(ComputerControl.isBlockedApp(bundleIdentifier: nil, name: "1Password.app"), "password manager blocked")
check(!ComputerControl.isBlockedApp(bundleIdentifier: nil, name: "TextEdit"), "textedit allowed")
var target = ComputerControl.TargetContext(appName: "Safari", elementRole: "text field")
target.isSecureField = true
check(ComputerControl.blockReason(for: .type(text: "x"), target: target) != nil, "secure field blocked")
let ownApp = ComputerControl.TargetContext(appName: "Thambi", isOwnApp: true)
check(ComputerControl.blockReason(for: .click(x: 1, y: 1, target: "x", isDoubleClick: false), target: ownApp) != nil, "own window blocked")
let plain = ComputerControl.TargetContext(appName: "TextEdit")
check(ComputerControl.blockReason(for: .type(text: String(repeating: "a", count: 601)), target: plain) != nil, "too much typing blocked")
check(ComputerControl.blockReason(for: .key(combo: "cmd+q"), target: plain) == nil || ComputerControl.isRisky(.key(combo: "cmd+q"), target: plain), "quit is blocked or risky")
check(ComputerControl.blockReason(for: .key(combo: "banana"), target: plain) != nil, "unknown key blocked")
check(ComputerControl.blockReason(for: .openApp(name: "Terminal"), target: plain) != nil, "won't open terminal")
let sendClick = ControlAction.click(x: 1, y: 1, target: "Send", isDoubleClick: false)
check(ComputerControl.needsApproval(mode: .never, stepNumber: 3, hasApprovedThisTask: true, action: sendClick, target: plain), "risky step asks even in Never mode")
let safeClick = ControlAction.click(x: 1, y: 1, target: "Bold", isDoubleClick: false)
check(!ComputerControl.needsApproval(mode: .never, stepNumber: 1, hasApprovedThisTask: false, action: safeClick, target: plain), "Never mode skips safe steps")
check(!ComputerControl.needsApproval(mode: .oncePerTask, stepNumber: 2, hasApprovedThisTask: true, action: safeClick, target: plain), "Once mode asks once")
check(ComputerControl.needsApproval(mode: .everyStep, stepNumber: 2, hasApprovedThisTask: true, action: safeClick, target: plain), "Every step asks")
check(!ComputerControl.needsApproval(mode: .everyStep, stepNumber: 2, hasApprovedThisTask: false, action: .done(say: "ok"), target: plain), "finishing needs no approval")
check(ControlKeyCombo.parse("cmd+shift+4") != nil && ControlKeyCombo.parse("command+s")?.command == true, "key combos parse")

// MARK: Notes
check(NotesMarkdown.userAskedToWrite("write down the key points"), "write gate")
check(!NotesMarkdown.userAskedToWrite("what is write-ahead logging"), "write-ahead is not a write request")
check(!NotesMarkdown.userAskedToWrite("explain read/write locks"), "read/write is not a write request")
check(!NotesMarkdown.userAskedToWrite("what is a write back cache"), "write back is not a write request")
check(NotesMarkdown.userAskedToWrite("write a short note on deadlock"), "write a note")
check(NotesMarkdown.userAskedToWrite("make short notes on paging"), "make notes")
check(NotesMarkdown.userAskedToWrite("Write down the steps"), "write down")
let notes = NotesMarkdown.extractNotes(from: "here you go [NOTES]\n- one\n- two\n[/NOTES]")
check(notes.notes?.contains("- one") == true && !notes.spokenText.contains("one"), "notes extracted")
let table = NotesMarkdown.lines(from: "| a | b |\n|---|---|\n| 1 | 2 |")
if case .table(let hasHeader)? = table.first?.kind { check(hasHeader && table.first?.tableRows.count == 2, "table parsed") } else { check(false, "table parsed") }
check(NotesMarkdown.plainText(from: "- **bold** item").contains("• bold item"), "plain text bullets")

// MARK: Speech helpers
check(SpeechAcronymSpeller.spelledOut("ESP and IKE use TCP") .contains("E S P"), "acronym spelled")
check(!SpeechAcronymSpeller.spelledOut("Hello World").contains("H e"), "normal words untouched")
check(SpeechSentenceSplitter.sentences(in: "First one. Second one? Third!").count == 3, "sentences split")
check(SpeechSentenceSplitter.sentences(in: "Use e.g. this and Dr. Rao's 3.5 rule.").count == 1, "abbreviations and decimals don't split")

// MARK: Settings and routing
check(ThambiSettings.clampedVoiceSpeed(9) == ThambiSettings.maximumVoiceSpeed && ThambiSettings.clampedVoiceSpeed(.nan) == 1, "voice speed clamped")
check(ThambiSettings.voiceSpeedLabel(1.04) == "1.0x", "speed label")
check(ThambiSettings.shortenedForHistory(String(repeating: "a", count: 900)).count < 650, "history shortened")
check(ThambiSettings.preparedTypedQuestion("  ") == nil && ThambiSettings.preparedTypedQuestion(String(repeating: "q", count: 5000))?.count == 2000, "typed question capped")
check(ClickyModelRouter.chooseModel(forTranscript: "what is this", selectedMode: ClickyModelRouter.autoModeIdentifier).modelID == ClickyModelRouter.haikuModelID, "simple question uses Haiku")
check(ClickyModelRouter.chooseModel(forTranscript: "anything", selectedMode: ClickyModelRouter.sonnetModelID).modelID == ClickyModelRouter.sonnetModelID, "fixed Sonnet respected")

// MARK: Whole document
let combined = OpenDocumentReader.combinedText(pageTexts: ["a  b", "", String(repeating: "x", count: 500)], maximumCharacters: 300)
check(combined.text == "[page 1]\na b" && combined.pagesRead == 2, "pdf: a page that does not fit (under 400 chars left) is left out")
let partial = OpenDocumentReader.combinedText(pageTexts: ["a", String(repeating: "x", count: 2000)], maximumCharacters: 1000)
check(partial.pagesRead == 2 && partial.text.count <= 1000, "pdf: a long page is cut to fit")
check(OpenDocumentReader.userAskedAboutDocument("summarise this whole PDF") && !OpenDocumentReader.userAskedAboutDocument("what is this button"), "document gate")

print(failures == 0 ? "ALL \(passes) PASSED" : "\(failures) FAILED, \(passes) passed")
exit(failures == 0 ? 0 : 1)
