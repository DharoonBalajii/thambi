import Foundation
var failures = 0, passes = 0
func check(_ ok: Bool, _ name: String) { if ok { passes += 1 } else { failures += 1; print("FAIL:", name) } }

enum ThambiDrawingCheck { static let modelSource = StudySocial.modelDrawingSource("heart") }

// MARK: Marks format
check(StudyAnswerFormat.detected(in: "Explain deadlock for 5 marks") == .fiveMarks, "for 5 marks")
check(StudyAnswerFormat.detected(in: "write a 10-mark answer on paging") == .tenMarks, "10-mark")
check(StudyAnswerFormat.detected(in: "2 marks: define entropy") == .twoMarks, "2 marks")
check(StudyAnswerFormat.detected(in: "16m answer on transformers") == .sixteenMarks, "16m answer")
check(StudyAnswerFormat.detected(in: "a 16m tall tower") == nil, "16m without answer is metres")
check(StudyAnswerFormat.detected(in: "13 marks question on BJT") == .tenMarks, "13 marks closest")
check(StudyAnswerFormat.detected(in: "explain paging in 5 minutes") == nil, "minutes are not marks")
check(StudyAnswerFormat.detected(in: "what is a primary key") == nil, "no marks")
check(StudyAnswerFormat.detected(in: "100 marks exam tips") == nil, "100 marks not an answer length")
check(StudyAnswerFormat.normal.instruction == nil && StudyAnswerFormat.tenMarks.instruction!.contains("10-mark"), "instructions")
check(StudyAnswerFormat.twoMarks.maximumOutputTokens < StudyAnswerFormat.sixteenMarks.maximumOutputTokens, "longer answers get more room")

// MARK: Cost
let cost = StudyCost.rupees(input: 2_000, cached: 1_000, cacheWrite: 0, output: 300)
check(abs(cost - (2_000 * 0.10 + 1_000 * 0.01 + 300 * 0.50) / 1_000_000 * 94) < 1e-9, "cost formula")
check(StudyCost.label(rupees: 0.004) == "under ₹0.01" && StudyCost.label(rupees: 0.034) == "₹0.03", "cost label")

// MARK: Passage on its page
let page = "Unit 3\nTransactions\n\nA transaction is a unit\nof work that is atomic, consistent,\n  isolated and durable. Logs make recovery possible."
let passage = "A transaction is a unit of work that is atomic, consistent, isolated and durable."
if let range = StudyLibrary.passageRange(of: passage, inPageText: page) {
    let found = (page as NSString).substring(with: range)
    check(found.hasPrefix("A transaction") && found.hasSuffix("durable."), "passage found across line breaks (\(found))")
} else { check(false, "passage found across line breaks") }
let joined = "Earlier text joined on. " + passage
check(StudyLibrary.passageRange(of: joined, inPageText: page) != nil, "passage with an unseen start still found")
check(StudyLibrary.passageRange(of: passage, inPageText: "") == nil, "page with no text layer")
check(StudyLibrary.passageRange(of: "short", inPageText: page) == nil, "too short to place")
check(StudyLibrary.passageRange(of: "Kirchhoff current law says the currents into a node add to zero.", inPageText: page) == nil, "other passage not found")
let upper = StudyLibrary.passageRange(of: passage.uppercased(), inPageText: page)
check(upper != nil, "case does not matter")

// MARK: FSRS
let start = Date(timeIntervalSince1970: 1_800_000_000)
let fresh = StudyCard(front: "What is 3NF?", back: "No transitive dependency.", subject: "DBMS")
let good1 = FSRS.review(fresh, rating: .good, at: start)
check(abs(good1.stability - 3.7145) < 1e-6 && good1.state == .review, "new card good stability")
check(Int((good1.due.timeIntervalSince(start) / 86_400).rounded()) == 4, "new card good due in 4 days")
check(FSRS.scheduledDays(for: fresh, rating: .easy, at: start) == 14, "new card easy 14 days")
check(FSRS.scheduledDays(for: fresh, rating: .hard, at: start) == 1, "new card hard 1 day")
let again1 = FSRS.review(fresh, rating: .again, at: start)
check(again1.state == .learning && abs(again1.due.timeIntervalSince(start) - 600) < 1, "again comes back in 10 minutes")
check(abs(FSRS.intervalDays(stability: 7) - 7) < 1e-9, "interval at 90% equals stability")
check(abs(FSRS.retrievability(elapsedDays: 7, stability: 7) - 0.9) < 1e-9, "retrievability 90% at stability")
let later = start.addingTimeInterval(4 * 86_400)
let good2 = FSRS.review(good1, rating: .good, at: later)
check(good2.stability > 14 && good2.stability < 16, "second good review grows stability (\(good2.stability))")
check(abs(good2.difficulty - good1.difficulty) < 1e-9, "good keeps difficulty")
let lapse = FSRS.review(good2, rating: .again, at: later.addingTimeInterval(20 * 86_400))
check(lapse.state == .relearning && lapse.lapseCount == 1 && lapse.stability < good2.stability, "forgetting a review card")
check(lapse.difficulty > good2.difficulty, "forgetting raises difficulty")
let relearned = FSRS.review(lapse, rating: .good, at: later.addingTimeInterval(20 * 86_400 + 600))
check(relearned.state == .review && relearned.due > later.addingTimeInterval(21 * 86_400 - 1), "relearned card goes back to review")
for card in [fresh, good1, good2, lapse] {
    let h = FSRS.scheduledDays(for: card, rating: .hard, at: later), g = FSRS.scheduledDays(for: card, rating: .good, at: later), e = FSRS.scheduledDays(for: card, rating: .easy, at: later)
    check(h <= g && g < e, "hard <= good < easy (\(h) \(g) \(e))")
}
check(FSRS.label(for: fresh, rating: .again, at: start) == "10 min" && FSRS.label(for: fresh, rating: .good, at: start) == "4 days", "labels")
var veteran = good2; veteran.stability = 400
check(FSRS.scheduledDays(for: veteran, rating: .easy, at: later) <= 3 * 365, "interval capped")

// MARK: Quiz and card parsing
let quizText = """
Q: What is a transaction?
A: A unit of work that is atomic, consistent,
isolated and durable.
S: 2

**Q:** Why are logs kept?
**A:** So the database can recover after a crash.
**S:** 9

Q: A question with no answer
"""
let quiz = StudyPractice.parseQuiz(quizText, sourceCount: 4)
check(quiz.count == 2, "two complete questions (\(quiz.count))")
check(quiz.first?.answer == "A unit of work that is atomic, consistent, isolated and durable.", "wrapped answer joined")
check(quiz.first?.sourceNumber == 2 && quiz.last?.sourceNumber == nil, "source numbers checked against the list")
check(quiz.last?.question == "Why are logs kept?", "bold keys read")
let cards = StudyPractice.parseCards("FRONT: Ohm's law\nBACK: V = IR\nS: 1\n\nFRONT: KCL\nBACK: currents into a node sum to zero\nS: [3]", sourceCount: 3)
check(cards.count == 2 && cards[1].sourceNumber == 3 && cards[0].back == "V = IR", "cards parsed")
let verdict = StudyPractice.parseVerdict("VERDICT: Partly\nFEEDBACK: You named atomicity but missed durability.")
check(verdict?.verdict == .partly && verdict?.feedback.hasPrefix("You named") == true, "verdict parsed")
check(StudyPractice.parseVerdict("I think this is fine") == nil, "unreadable verdict")
check(StudyPractice.parseVerdict("VERDICT: incorrect\nFEEDBACK: x")?.verdict == .wrong, "incorrect means wrong")

// MARK: Sampling
let items = Array(0..<100)
let sample = StudyPractice.spreadSample(items, count: 5, seed: 7)
check(sample.count == 5 && sample == StudyPractice.spreadSample(items, count: 5, seed: 7), "same seed same sample")
check(zip(sample, sample.dropFirst()).allSatisfy { $0 < $1 } && sample.last! >= 80, "sample spread across the material")
check(StudyPractice.spreadSample([1, 2], count: 5, seed: 1) == [1, 2], "small list returned whole")
check(StudyPractice.isQuizWorthy(String(repeating: "Normalisation removes redundancy from tables in a database. ", count: 5)), "real text worth a quiz")
check(!StudyPractice.isQuizWorthy("1.1 Intro ........ 3\n1.2 Keys ....... 7\n1.3 Joins ...... 9"), "contents page not worth a quiz")

// MARK: Anki
var tabbed = StudyCard(front: "Tab\there", back: "line one\nline two", subject: "Operating Systems")
tabbed.state = .review
let anki = StudyPractice.ankiText(for: [tabbed])
check(anki.hasPrefix("#separator:tab\n") && anki.contains("Tab here\tline one<br>line two\tthambi::Operating_Systems\n"), "anki export")

// MARK: Friends
let me = StudyProfile(name: "Dharoon"), asha = UUID()
let focusStart = Date(timeIntervalSince1970: 1_800_000_000)
var focus = StudyStatus(activity: .focusing, subject: "DBMS", startedAt: focusStart, endsAt: focusStart.addingTimeInterval(1_500), sentAt: focusStart)
check(focus.line(at: focusStart.addingTimeInterval(780)) == "Focusing on DBMS, 12 min left", "focus status line (\(focus.line(at: focusStart.addingTimeInterval(780))))")
check(StudyStatus(activity: .practising, subject: "Physics", startedAt: focusStart).line(at: focusStart.addingTimeInterval(480)) == "Practising Physics for 8 min", "practising line")
check(StudyStatus().line() == "Online" && !StudyStatus().isStudying && focus.isStudying, "online line")
var ashaFriend = StudyFriend(id: asha, name: "Asha", token: "t", status: focus)
check(ashaFriend.isOnline(at: focusStart.addingTimeInterval(60), connected: true), "fresh status is online")
check(!ashaFriend.isOnline(at: focusStart.addingTimeInterval(600), connected: true), "stale status is offline")
check(!ashaFriend.isOnline(at: focusStart.addingTimeInterval(60), connected: false), "not connected is offline")
let wire = StudyWire.message(StudyMessage(from: me.id, to: asha, text: "hi", attachment: .cards(subject: "DBMS", cards: [.init(front: "f", back: "b")])))
check(StudyWire.decoded(wire.encoded()!) == wire, "message survives the wire")
check(StudyWire.decoded(StudyWire.hello(profile: me, token: "abc").encoded()!) == .hello(profile: me, token: "abc"), "hello survives the wire")
check(StudyWire.decoded(Data("not json".utf8)) == nil && StudyWire.decoded(Data(count: 700_000)) == nil, "bad and oversized packets dropped")
check(StudyWire.message(StudyMessage(from: me.id, to: asha, text: String(repeating: "x", count: 700_000))).encoded() == nil, "oversized message not sent")
var hostile = StudyMessage(from: asha, to: me.id, text: String(repeating: "a", count: 9_000), attachment: .cards(subject: "  Big   deck ", cards: Array(repeating: .init(front: "f", back: "b"), count: 500)))
hostile.isDelivered = true; hostile.isRead = true
let cleanMessage = StudySocial.sanitized(hostile)
check(cleanMessage.text.count == 4_000 && !cleanMessage.isRead && !cleanMessage.isDelivered, "incoming text capped and flags reset")
if case .cards(let subject, let kept)? = cleanMessage.attachment { check(subject == "Big deck" && kept.count == 200, "incoming cards capped") } else { check(false, "incoming cards capped") }
check(StudySocial.cleanedName("  Asha \n  R  ") == "Asha R" && StudySocial.cleanedName(String(repeating: "n", count: 90)).count == 40, "names cleaned")
let thread = [StudyMessage(from: asha, to: me.id, sentAt: focusStart.addingTimeInterval(5), text: "2"), StudyMessage(from: me.id, to: asha, sentAt: focusStart, text: "1"), StudyMessage(from: UUID(), to: me.id, text: "other")]
check(StudySocial.conversation(with: asha, in: thread).map(\.text) == ["1", "2"], "conversation in order, one friend only")
check(StudySocial.unreadCount(from: asha, in: thread) == 1, "unread count")
let idle = StudyFriend(id: UUID(), name: "Bala", token: "t", status: StudyStatus(sentAt: focusStart)), away = StudyFriend(id: UUID(), name: "Arun", token: "t")
check(StudySocial.sorted([away, idle, ashaFriend], connected: [asha, idle.id], at: focusStart.addingTimeInterval(30)).map(\.name) == ["Asha", "Bala", "Arun"], "studying friends first")
check(ThambiDrawingCheck.modelSource == "type: model\nmodel: heart", "model share source")
check(StudySocial.agoLabel(focusStart, now: focusStart.addingTimeInterval(400)) == "6 min ago", "ago label")

// MARK: Planner
let cal = Calendar(identifier: .gregorian)
let day0 = cal.date(from: DateComponents(year: 2026, month: 11, day: 17))!
func dayKey(_ offset: Int) -> String { StudyDay.key(for: cal.date(byAdding: .day, value: offset, to: day0)!, calendar: cal) }
check(dayKey(0) == "2026-11-17" && StudyDay.date(fromKey: "2026-11-17", calendar: cal) == day0, "day keys")
check(StudyStreak.compute(activeDays: [dayKey(0), dayKey(-1), dayKey(-2), dayKey(-5)], today: day0, calendar: cal) == (3, 3), "streak counts back from today")
check(StudyStreak.compute(activeDays: [dayKey(-1), dayKey(-2)], today: day0, calendar: cal).current == 2, "streak survives until today is studied")
check(StudyStreak.compute(activeDays: [dayKey(-3), dayKey(-4), dayKey(-5), dayKey(-6)], today: day0, calendar: cal) == (0, 4), "broken streak, longest kept")
check(StudyTimerRules.clockLabel(seconds: 1_499) == "24:59" && StudyTimerRules.durationLabel(minutes: 80) == "1 h 20 min", "timer labels")
let paper = """
ANNA UNIVERSITY Nov/Dec 2023
PART A
1. Define normalisation. (2)
2. What is a transaction? [2 marks]
PART B
11. (a) Explain the ACID properties of a transaction with examples. (16)
Or
(b) Discuss deadlock handling in databases with a neat diagram. (16)
"""
let paperQuestions = StudyPapers.questions(inPaperText: paper, paperTitle: "DBMS 2023")
check(paperQuestions.count == 4, "four questions found (\(paperQuestions.count))")
check(paperQuestions.first?.marks == 2 && paperQuestions.first?.text == "Define normalisation." && paperQuestions.first?.year == "2023", "marks, text and year read")
check(paperQuestions.last?.marks == 16 && paperQuestions.last?.text.hasPrefix("Discuss deadlock") == true, "sub-part read")
let older = StudyPapers.questions(inPaperText: "1. Explain ACID properties of transactions. (16)\n2. Explain B+ tree indexing with an example. (10)", paperTitle: "DBMS 2022")
let repeated = StudyPapers.repeatedQuestions(paperQuestions + older)
check(repeated.first?.askedCount == 2 && repeated.first?.years == ["2022", "2023"] && repeated.first?.text.contains("ACID") == true, "repeat found across years")
let mapped = StudyPapers.applyUnitMapping("1 | Unit 3 Transactions | ACID properties\n2 | other | x", to: repeated, units: ["Unit 1 Design", "Unit 3 Transactions"])
check(mapped[0].unit == "Unit 3 Transactions" && mapped[0].topic == "ACID properties" && mapped[1].unit == nil, "units mapped")
check(StudyPapers.unitWeights(mapped, units: ["Unit 1 Design", "Unit 3 Transactions"]).first?.unit == "Unit 3 Transactions", "heaviest unit first")
let exam = cal.date(byAdding: .day, value: 12, to: day0)!
let plan = StudyPlanBuilder.plan(units: [("U1", 0), ("U2", 32), ("U3", 10)], today: day0, examDate: exam, calendar: cal)
check(plan.count == 12, "one entry per day to the exam")
check(plan.last?.tasks.contains(StudyPlanTask(kind: .fullRevision)) == true, "last day is full revision")
check(["U1", "U2", "U3"].allSatisfy { unit in plan.contains { $0.tasks.contains(StudyPlanTask(kind: .learn, unit: unit)) } }, "every unit is learned")
check(plan.filter { $0.tasks.contains(StudyPlanTask(kind: .learn, unit: "U2")) }.count > plan.filter { $0.tasks.contains(StudyPlanTask(kind: .learn, unit: "U1")) }.count, "heavier unit gets more days")
check(plan.contains { $0.tasks.contains(StudyPlanTask(kind: .revise, unit: "U1")) }, "units are revised")
check(StudyPlanBuilder.plan(units: [("U1", 1)], today: day0, examDate: day0, calendar: cal).isEmpty, "no plan for an exam today")
check(StudyPlanBuilder.plan(units: [("U1", 1), ("U2", 1)], today: day0, examDate: cal.date(byAdding: .day, value: 1, to: day0)!, calendar: cal).count == 1, "one day left still plans")

// MARK: Language
check(StudyLanguage.isMostlyIndianScript("டெட்லாக் என்றால் என்ன?") && StudyLanguage.isMostlyIndianScript("डेडलॉक क्या है"), "tamil and hindi script seen")
check(!StudyLanguage.isMostlyIndianScript("deadlock na enna?") && !StudyLanguage.isMostlyIndianScript("What is paging (பக்கம்)?"), "latin and mostly-latin text not")
check(StudyLanguage.english.instruction(answeringStudent: true).contains("english") && StudyLanguage.sameAsQuestion.instruction(answeringStudent: false).isEmpty, "language instructions")
check(StudyLanguage.tamil.instruction(answeringStudent: false).contains("tamil script"), "tamil instruction")

print(failures == 0 ? "ALL \(passes) PASSED" : "\(failures) FAILED, \(passes) passed")
exit(failures == 0 ? 0 : 1)
