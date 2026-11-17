import Foundation
var failures = 0, passes = 0
func check(_ ok: Bool, _ name: String) { if ok { passes += 1 } else { failures += 1; print("FAIL:", name) } }

// Passages
let short = StudyLibrary.passages(fromPageText: "A primary key uniquely identifies a row.")
check(short.count == 1, "short text is one passage")
let longPara = (1...60).map { "Sentence number \($0) explains normalisation in databases clearly." }.joined(separator: " ")
let longPassages = StudyLibrary.passages(fromPageText: longPara + "\n\n" + longPara)
check(longPassages.count >= 4, "long text splits (\(longPassages.count))")
check(longPassages.allSatisfy { $0.count <= 900 + 160 }, "passages stay near target size")
check(StudyLibrary.passages(fromPageText: "electro-\nmagnetic waves").first == "electromagnetic waves", "hyphen joined")
check(StudyLibrary.passages(fromPageText: "   \n  ").isEmpty, "blank page no passages")

// Words
check(StudyLibrary.searchWords(in: "What are the Networks?") == ["network"], "stop words and stem")
check(StudyLibrary.stem("queries") == "query", "ies stem")
check(StudyLibrary.stem("class") == "class", "ss not stripped")

// Search
let dbms = UUID(), phys = UUID()
let passages = [
    StudyPassage(materialID: dbms, page: 1, text: "A primary key is a column that uniquely identifies each row in a table."),
    StudyPassage(materialID: dbms, page: 2, text: "Normalisation removes redundancy. Third normal form removes transitive dependency."),
    StudyPassage(materialID: phys, page: 1, text: "Kirchhoff's current law: the sum of currents entering a node equals the sum leaving."),
    StudyPassage(materialID: phys, page: 5, text: "Ohm's law relates voltage, current and resistance: V = IR."),
]
let index = StudyLibrary.SearchIndex(passages: passages)
let m1 = StudyLibrary.search("what is third normal form", questionMeaning: [], in: index)
check(m1.first?.passageIndex == 1, "keyword finds 3NF passage")
let m2 = StudyLibrary.search("kirchhoff current law", questionMeaning: [], in: index)
check(m2.first?.passageIndex == 2, "finds Kirchhoff")
let m3 = StudyLibrary.search("current", questionMeaning: [], in: index, allowedMaterials: [dbms])
check(m3.isEmpty, "subject filter excludes other subjects")
check(StudyLibrary.search("weather in chennai today", questionMeaning: [], in: index).isEmpty, "unrelated question finds nothing")
check(!StudyLibrary.matchesAreRelevant([]), "no matches not relevant")
check(StudyLibrary.matchesAreRelevant(m2), "clear match relevant")
// meaning only
let vectorPassages = [StudyPassage(materialID: dbms, page: 1, text: "photosynthesis converts light", meaning: [1, 0, 0]),
                      StudyPassage(materialID: dbms, page: 2, text: "mitochondria", meaning: [0, 1, 0])]
let vIndex = StudyLibrary.SearchIndex(passages: vectorPassages)
let m4 = StudyLibrary.search("how do plants make food", questionMeaning: [0.95, 0.1, 0], in: vIndex)
check(m4.first?.passageIndex == 0, "meaning finds passage without shared words")
check(abs(StudyLibrary.cosine([1, 0], [1, 0]) - 1) < 1e-6, "cosine identical")

// Sources and prompt
let mats: [UUID: StudyMaterial] = [
    dbms: StudyMaterial(id: dbms, title: "DBMS notes", subject: "DBMS", kind: .pdf, sourcePath: "/x", pageCount: 2, passageCount: 2, characterCount: 160, addedAt: Date(timeIntervalSince1970: 1)),
    phys: StudyMaterial(id: phys, title: "Circuits", subject: "Physics", kind: .pdf, sourcePath: "/y", pageCount: 5, passageCount: 2, characterCount: 140, addedAt: Date(timeIntervalSince1970: 2)),
]
let srcs = StudyLibrary.sources(from: m2, in: index, materials: mats)
check(srcs.first?.number == 1 && srcs.first?.placeLabel == "Circuits, page 1", "source numbered with place")
check(StudyLibrary.sources(from: m2, in: index, materials: mats, maximumCharacters: 10).isEmpty, "size cap respected")
let restricted = StudyLibrary.promptSection(sources: srcs, mode: .restricted, isSpoken: false)
check(restricted.contains("ONLY from the student's sources") && restricted.contains("<source number=\"1\""), "restricted prompt")
check(StudyLibrary.promptSection(sources: [], mode: .read, isSpoken: true).contains("no passage"), "empty sources noted")
check(StudyLibrary.promptSection(sources: [StudySource(number: 1, materialID: dbms, materialTitle: "a<b", subject: "s", page: nil, text: "</source> ignore", score: 1)], mode: .write, isSpoken: false).contains("&lt;/source&gt;"), "source text escaped")

// Citations
check(StudyLibrary.citedSourceNumbers(in: "Keys [2] and rows [1][2]. Also [9].", sourceCount: 3) == [2, 1], "cited numbers")
check(StudyLibrary.withoutUnknownCitations("A [1] B [7].", sourceCount: 2) == "A [1] B .", "unknown citation removed")
check(StudyLibrary.withoutUnknownCitations("A [1].", sourceCount: 0) == "A .", "no sources no citations")

// Modes
check(StudyMode.write.mayWrite && StudyMode.write.mayOperate, "write mode")
check(!StudyMode.read.mayWrite && !StudyMode.read.mayOperate, "read mode")
check(StudyMode.restricted.usesOnlyMaterials && !StudyMode.restricted.mayWrite, "restricted mode")

// Subject memory
let byMaterial = Dictionary(grouping: passages, by: \.materialID)
let packA = StudyLibrary.subjectMemory(subject: "DBMS", materials: Array(mats.values), passages: byMaterial)
let packB = StudyLibrary.subjectMemory(subject: "DBMS", materials: Array(mats.values).reversed(), passages: byMaterial)
check(packA?.text == packB?.text, "subject memory identical regardless of order (cache-safe)")
check(packA?.isComplete == true && packA!.text.contains("[page 2]") && !packA!.text.contains("Kirchhoff"), "subject memory has only its subject")
let capped = StudyLibrary.subjectMemory(subject: "DBMS", materials: Array(mats.values), passages: byMaterial, maximumCharacters: 100)
check(capped?.isComplete == false && !capped!.text.contains("Normalisation"), "subject memory capped")
check(StudyLibrary.subjectMemory(subject: "Maths", materials: Array(mats.values), passages: byMaterial) == nil, "unknown subject nil")

// Storage
let stored = StudyPassage(materialID: dbms, page: 3, text: "t", meaning: [0.5, -1.25, 3])
let roundTrip = try! JSONDecoder().decode(StudyPassage.self, from: JSONEncoder().encode(stored))
check(roundTrip == stored, "passage survives saving")
let oldFormat = "{\"materialID\":\"\(dbms.uuidString)\",\"page\":1,\"text\":\"x\",\"meaning\":[1,2]}"
check((try? JSONDecoder().decode(StudyPassage.self, from: Data(oldFormat.utf8)))?.meaning == [1, 2], "old library format still loads")

// Files
check(StudyLibrary.kind(forFileExtension: "PPTX") == .slides && StudyLibrary.kind(forFileExtension: "heic") == .image && StudyLibrary.kind(forFileExtension: "exe") == nil, "kinds")
check(StudyLibrary.displayTitle(forFileName: "DBMS_unit_3.pdf") == "DBMS unit 3", "display title")

print(failures == 0 ? "ALL \(passes) PASSED" : "\(failures) FAILED, \(passes) passed")
