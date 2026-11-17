import Foundation
var failures = 0
func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FAIL:", name) } else { print("ok:", name) } }
typealias TD = ThambiDrawing
typealias TT = SpeechTimedTags
check("draw gate", TD.userAskedToDraw("draw the TCP handshake") && TD.userAskedToDraw("show me the heart") && TD.userAskedToDraw("show me a 3D model of an engine") && !TD.userAskedToDraw("explain this diagram") && !TD.userAskedToDraw("open calculator"))
check("model named", TD.modelNamed(in: "show me the human heart") == "heart" && TD.modelNamed(in: "how does a piston move") == "engine" && TD.modelNamed(in: "draw the double helix") == "dna" && TD.modelNamed(in: "draw a flowchart") == nil)
check("model parse", { if case .model(let m)? = TD.parse("type: model\nmodel: heart\nshow: left ventricle, aorta")?.content { return m.id == "heart" && m.shownParts.count == 2 }; return false }())
check("model fallback parse", TD.parse("type: model\nmodel: engine") != nil && TD.parse("type: model\nmodel: banana") == nil)
check("steps counted", TD.parse("type: sequence\nactor c \"C\"\nactor s \"S\"\nstep\nmsg c -> s \"a\"\nstep\nmsg s -> c \"b\"")?.stepCount == 3)
check("reasoning stripped", TT.withoutLeakedReasoning("here it is. <reasoning>secret stuff that never ends") == "here it is." && TT.withoutLeakedReasoning("a <thinking>x</thinking> b").contains("x") == false && TT.withoutLeakedReasoning("plain") == "plain")
check("mark gate", TT.userAskedToMark("highlight the important line") && TT.userAskedToMark("circle the bug") && !TT.userAskedToMark("explain this slide"))
let ex = TT.extract(from: "first. [STEP] the loop. [MARK:box:10,20,300,80:loop body] done.")
check("timed tags", ex.events.count == 2 && ex.events[0] == .revealStep && !TT.stripped(ex.text).contains("[") && TT.split(ex.text).count == 3)
check("formula", TD.Formula("2x + 3")?.value(x: 2) == 7 && TD.Formula("system(1)") == nil)
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
