//
//  ThambiDrawing.swift
//  leanring-buddy
//
//  Drawings: "draw the TCP handshake", "plot sin x", "show methane in 3D".
//
//  The AI never makes a picture. It writes a few short lines describing one, between [DRAW] and
//  [/DRAW], and Thambi draws it on this Mac. A description is 100 to 400 output tokens, about a
//  paisa, where a generated image would cost a hundred times more and get the labels wrong.
//
//  This file is the language: when to draw, the instructions sent to the model, reading its
//  reply, laying out a flow chart, and evaluating a formula for a plot. Pure Foundation, no UI,
//  so all of it is unit-tested. Nothing here ever runs text from the model as code.
//

import Foundation

nonisolated enum ThambiDrawing {

    // MARK: - When to draw (pure)

    /// True when the user's own words ask for a picture. Text seen on screen can never open one.
    static func userAskedToDraw(_ transcript: String) -> Bool {
        let pattern = #"\b(draw|draws|drawing|sketch|plot|visuali[sz]e|illustrate|in 3 ?d|in three d|3 ?d (model|view|picture|structure|shape|diagram)|(make|create|give me|show me|build|generate)( me)? (a|an|the)? ?(quick |simple |small )?(diagram|flow ?chart|chart|picture|figure|graph|sketch|3 ?d model|model)|(show|see)( me)? (a |an |the )?(human |animal |plant |car |four[- ]stroke )?(heart|engine|dna|double helix|atom|solar system))\b"#
        return transcript.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Splits the model's answer into what is spoken and the drawing description.
    static func extractDrawing(from responseText: String) -> (spokenText: String, source: String?) {
        guard let openingTag = responseText.range(of: "[DRAW]", options: .caseInsensitive) else {
            return (responseText, nil)
        }
        let afterOpeningTag = responseText[openingTag.upperBound...]
        let closingTag = afterOpeningTag.range(of: "[/DRAW]", options: .caseInsensitive)
        let body = closingTag.map { String(afterOpeningTag[..<$0.lowerBound]) } ?? String(afterOpeningTag)
        let textAfter = closingTag.map { String(afterOpeningTag[$0.upperBound...]) } ?? ""
        let spokenText = (String(responseText[..<openingTag.lowerBound]) + " " + textAfter)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return (spokenText, source.isEmpty ? nil : String(source.prefix(maximumSourceCharacters)))
    }

    /// The ready-made model the user's words name, if any. Used when the model's reply forgot
    /// the drawing: the picture still appears, at no cost.
    static func modelNamed(in transcript: String) -> String? {
        let words = transcript.lowercased()
        let patterns: [(String, String)] = [
            ("heart", #"\bheart\b"#), ("engine", #"\b(engine|piston)\b"#), ("dna", #"\b(dna|double helix)\b"#),
            ("atom", #"\batom\b"#), ("solar-system", #"\b(solar system|planets)\b"#), ("cell", #"\bcell\b"#)
        ]
        return patterns.first { words.range(of: $0.1, options: .regularExpression) != nil }?.0
    }

    // MARK: - Limits

    static let maximumSourceCharacters = 6000
    static let maximumFlowNodes = 24
    static let maximumFlowEdges = 48
    static let maximumSequenceEvents = 24
    static let maximumSceneItems = 120
    static let maximumLabelCharacters = 60

    // MARK: - Instructions for the model

    /// Sent only with a question that asks for a drawing, in its own cached block, so ordinary
    /// questions never pay for it.
    static let promptSection = """
    drawing:
    the user asked for a drawing. say briefly what it shows, then put ONE drawing at the very end of your answer between [DRAW] and [/DRAW]. the app draws it on their screen. never read the lines aloud, never say you can't draw, don't comment on what is on their screen unless the drawing is about it, and don't use [NOTES] or [OPERATE] for this. keep it small and correct: at most 12 boxes, or 40 shapes. one item per line, only these forms. ids are short lowercase words.

    FIRST check: if the user asks for a heart, a cell, an engine (piston), DNA, an atom or the solar system, always use the ready-made model, never shapes of your own:
    type: model
    model: heart
    show: left ventricle, aorta
    (model is one of: heart, cell, engine, dna, atom, solar-system. "show" lists the parts you talk about, in the order you mention them; leave it out to name every part. parts. heart: right atrium, left atrium, right ventricle, left ventricle, aorta, pulmonary artery, vena cava, pulmonary veins. cell: cell membrane, nucleus, nucleolus, mitochondria, endoplasmic reticulum, golgi apparatus, ribosomes, lysosomes, centrioles. engine: cylinder, piston, connecting rod, crankshaft, intake valve, exhaust valve, spark plug. dna: sugar-phosphate backbone, base pairs, adenine-thymine pair, guanine-cytosine pair. atom: nucleus, protons, neutrons, electrons, electron shells.)

    building it up as you talk: when a drawing has three or more items, put a line with only the word step between its parts (2 to 6 parts, in the order you explain them), and say one short sentence for each part in that same order. the app shows each part as you say its sentence; you add nothing else to your speech. for a model, put each part's own "show:" line after a step line.

    flow chart, tree, graph, state machine, hierarchy:
    type: flow
    title: TCP handshake
    direction: down
    box a "Client sends SYN"
    round s "Start"
    diamond d "x > 0?"
    arrow a -> d "label"
    line a -- s
    (direction is down or right. the label on an arrow is optional. add the word amber at the end of a box line to highlight the part the user asked about.)

    messages between parties over time:
    type: sequence
    title: ...
    actor c "Client"
    actor s "Server"
    msg c -> s "SYN"
    note "connection is open"

    graph of a function:
    type: plot
    title: ...
    plot sin(x) from -6.28 to 6.28 "sin x"
    plot x^2 from -3 to 3 "x squared"
    mark crossings
    point 0,0 "origin"
    (one plot line per function, up to 3: "plot a and b" means two lines. never work out where curves cross, where they are zero, or where their peaks are: write "mark crossings", "mark roots" or "mark peaks" and the app calculates and labels those points exactly. use "point" only for a point the user gave you. formulas use x, + - * / ^, sin cos tan exp ln log sqrt abs, pi and e.)

    3D picture (molecules, vectors, solids, lattices, simple machines). units run about -3 to 3, y is up:
    type: scene3d
    title: Methane
    sphere c at 0,0,0 r 0.5 grey "carbon"
    box b at 1,0,0 size 1,1,1 blue
    cylinder p from 0,0,0 to 0,2,0 r 0.2 teal
    bond c h1
    arrow from 0,0,0 to 1,2,0 amber "v"
    label at 0,1.5,0 "text"
    axes
    surface sin(x)*cos(y) from -3 to 3
    (bond joins two named shapes with a stick. surface is height as a function of x and y, used on its own. add axes only for vectors, coordinates and surfaces, never for molecules or objects. colors: blue amber red green grey white teal. use amber for the part the user asked about.)
    """

    // MARK: - What a drawing is

    struct Drawing: Equatable, Sendable {
        var title: String
        var content: Content
        /// How many parts the drawing is built up in (1 = shown all at once). Every item carries
        /// the number of the part it belongs to; parts appear in step with the voice.
        var stepCount = 1
    }

    enum Content: Equatable, Sendable {
        case flow(Flow)
        case sequence(Sequence)
        case plot(Plot)
        case scene(Scene3D)
        case model(ModelRequest)
    }

    /// One of the ready-made 3D models, and which of its parts to name.
    struct ModelRequest: Equatable, Sendable {
        var id: String
        var shownParts: [ShownPart] = []
    }

    struct ShownPart: Equatable, Sendable {
        var name: String
        var step: Int
    }

    /// The ready-made models. Each is built in code from simple shapes (see ThambiModels.swift):
    /// there are no model files, so there is nothing to license or download.
    struct ModelEntry: Sendable {
        let id: String
        let title: String
        let parts: [String]
    }

    static let modelCatalogue: [ModelEntry] = [
        ModelEntry(id: "heart", title: "Human heart (schematic)", parts: ["right atrium", "left atrium", "right ventricle", "left ventricle", "aorta", "pulmonary artery", "vena cava", "pulmonary veins"]),
        ModelEntry(id: "cell", title: "Animal cell", parts: ["cell membrane", "nucleus", "nucleolus", "mitochondria", "endoplasmic reticulum", "golgi apparatus", "ribosomes", "lysosomes", "centrioles"]),
        ModelEntry(id: "engine", title: "Four-stroke engine cylinder", parts: ["cylinder", "piston", "connecting rod", "crankshaft", "intake valve", "exhaust valve", "spark plug"]),
        ModelEntry(id: "dna", title: "DNA double helix", parts: ["sugar-phosphate backbone", "base pairs", "adenine-thymine pair", "guanine-cytosine pair"]),
        ModelEntry(id: "atom", title: "Atom (Bohr model of carbon)", parts: ["nucleus", "protons", "neutrons", "electrons", "electron shells"]),
        ModelEntry(id: "solar-system", title: "Solar system (not to scale)", parts: ["sun", "mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune"])
    ]

    static func modelEntry(for id: String) -> ModelEntry? {
        let wanted = id.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
        let aliases = ["solar": "solar-system", "solarsystem": "solar-system", "animal-cell": "cell", "human-heart": "heart", "piston": "engine", "four-stroke-engine": "engine", "double-helix": "dna", "carbon-atom": "atom"]
        return modelCatalogue.first { $0.id == (aliases[wanted] ?? wanted) }
    }

    /// The catalogue part the model's words mean ("the nucleus", "Mitochondrion"), or nil.
    static func matchedPart(_ text: String, in entry: ModelEntry) -> String? {
        let wanted = text.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"^(the|a|an)\s+"#, with: "", options: .regularExpression)
        guard !wanted.isEmpty else { return nil }
        if let exact = entry.parts.first(where: { $0 == wanted }) { return exact }
        // Singular and plural, and one name contained in the other ("golgi", "membrane").
        let stem = wanted.replacingOccurrences(of: #"(ia|ion|a|s|es)$"#, with: "", options: .regularExpression)
        return entry.parts.first { $0.hasPrefix(stem) && stem.count >= 4 } ?? entry.parts.first { $0.contains(wanted) && wanted.count >= 4 }
    }

    enum NodeShape: String, Equatable, Sendable { case box, round, diamond }

    struct FlowNode: Equatable, Sendable {
        var id: String
        var label: String
        var shape: NodeShape
        var isHighlighted: Bool
        var step = 0
    }

    struct FlowEdge: Equatable, Sendable {
        var from: String
        var to: String
        var label: String
        var hasArrow: Bool
        var step = 0
    }

    struct Flow: Equatable, Sendable {
        var nodes: [FlowNode] = []
        var edges: [FlowEdge] = []
        var isHorizontal = false
    }

    struct SequenceActor: Equatable, Sendable {
        var id: String
        var label: String
    }

    enum SequenceEvent: Equatable, Sendable {
        case message(from: String, to: String, label: String)
        case note(String)
    }

    struct Sequence: Equatable, Sendable {
        var actors: [SequenceActor] = []
        var events: [SequenceEvent] = []
        /// The part each event belongs to (same order as `events`).
        var eventSteps: [Int] = []
    }

    struct PlotCurve: Equatable, Sendable {
        var formula: Formula
        var label: String
        var minX: Double
        var maxX: Double
        var step = 0
    }

    struct PlotPoint: Equatable, Sendable {
        var x: Double
        var y: Double
        var label: String
        var step = 0
    }

    /// Things the app works out itself and marks on a plot. The model only asks for them:
    /// it is not trusted to do the arithmetic.
    enum PlotMark: String, Equatable, Sendable { case roots, crossings, peaks }

    struct Plot: Equatable, Sendable {
        var curves: [PlotCurve] = []
        var points: [PlotPoint] = []
        var marks: [PlotMark] = []
    }

    struct Vector3: Equatable, Sendable {
        var x: Double
        var y: Double
        var z: Double
        static let zero = Vector3(x: 0, y: 0, z: 0)
    }

    enum SceneColor: String, Equatable, Sendable, CaseIterable {
        case blue, amber, red, green, grey, white, teal
    }

    enum SceneItem: Equatable, Sendable {
        case sphere(center: Vector3, radius: Double, color: SceneColor, label: String)
        case box(center: Vector3, size: Vector3, color: SceneColor, label: String)
        case stick(from: Vector3, to: Vector3, radius: Double, color: SceneColor, label: String)
        case arrow(from: Vector3, to: Vector3, color: SceneColor, label: String)
        case label(at: Vector3, text: String)
    }

    struct Surface: Equatable, Sendable {
        var formula: Formula
        var minimum: Double
        var maximum: Double
    }

    struct Scene3D: Equatable, Sendable {
        var items: [SceneItem] = []
        /// The part each item belongs to (same order as `items`).
        var itemSteps: [Int] = []
        var showsAxes = false
        var surface: Surface?
    }

    // MARK: - Reading the model's lines (pure)

    /// Reads a drawing description. Unknown lines are skipped; nil when nothing drawable is left.
    static func parse(_ source: String) -> Drawing? {
        var kind = ""
        var title = ""
        var flow = Flow()
        var sequence = Sequence()
        var plot = Plot()
        var scene = Scene3D()
        var sceneCenters: [String: Vector3] = [:]
        var pendingBonds: [(String, String, Int)] = []
        var modelRequest: ModelRequest?
        var modelEntryInUse: ModelEntry?
        // "step" on a line of its own starts the next part of the drawing.
        var currentStep = 0
        var currentStepHasContent = false
        func addSceneItem(_ item: SceneItem) {
            scene.items.append(item)
            scene.itemSteps.append(currentStep)
        }

        for rawLine in source.components(separatedBy: .newlines) {
            // Commas inside coordinates may be followed by spaces: "0, 1, 2".
            // (Only outside quotes: a label keeps its own spacing.)
            let line = rawLine.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: "\"").enumerated()
                .map { $0.offset % 2 == 0 ? $0.element.replacingOccurrences(of: #",\s+"#, with: ",", options: .regularExpression) : $0.element }
                .joined(separator: "\"")
            guard !line.isEmpty, !line.hasPrefix("("), !line.hasPrefix("#") else { continue }
            let lowercasedLine = line.lowercased()

            if lowercasedLine.hasPrefix("type:") {
                kind = value(after: "type:", in: line).lowercased()
                continue
            }
            if lowercasedLine.hasPrefix("title:") {
                title = clipped(value(after: "title:", in: line))
                continue
            }
            if lowercasedLine.hasPrefix("direction:") {
                flow.isHorizontal = value(after: "direction:", in: line).lowercased().hasPrefix("r")
                continue
            }
            if lowercasedLine == "step" || lowercasedLine.range(of: #"^step\s*\d*:?$"#, options: .regularExpression) != nil {
                if currentStepHasContent, currentStep < 11 {
                    currentStep += 1
                    currentStepHasContent = false
                }
                continue
            }
            if lowercasedLine.hasPrefix("model:") {
                if let entry = modelEntry(for: value(after: "model:", in: line)) {
                    modelEntryInUse = entry
                    modelRequest = ModelRequest(id: entry.id)
                }
                continue
            }
            if lowercasedLine.hasPrefix("show:") {
                guard let entry = modelEntryInUse else { continue }
                for name in value(after: "show:", in: line).components(separatedBy: ",") {
                    guard let part = matchedPart(name, in: entry), modelRequest?.shownParts.contains(where: { $0.name == part }) == false else { continue }
                    modelRequest?.shownParts.append(ShownPart(name: part, step: currentStep))
                    currentStepHasContent = true
                }
                continue
            }
            currentStepHasContent = true

            let tokens = tokenize(line)
            guard let keyword = tokens.first?.text.lowercased() else { continue }
            let words = tokens.filter { !$0.isQuoted }.map(\.text)
            let quoted = tokens.first(where: \.isQuoted).map { clipped($0.text) } ?? ""

            switch keyword {
            // Flow
            case "box", "round", "diamond":
                if kind == "scene3d" && keyword == "box" {
                    guard scene.items.count < maximumSceneItems, let center = vector(after: "at", in: words) else { continue }
                    let size = vector(after: "size", in: words) ?? Vector3(x: 1, y: 1, z: 1)
                    if words.count > 1 { sceneCenters[words[1].lowercased()] = center }
                    addSceneItem(.box(center: center, size: size, color: color(in: words, default: .blue), label: quoted))
                    continue
                }
                guard words.count >= 2, flow.nodes.count < maximumFlowNodes else { continue }
                let id = words[1].lowercased()
                guard !flow.nodes.contains(where: { $0.id == id }) else { continue }
                flow.nodes.append(FlowNode(
                    id: id, label: quoted.isEmpty ? words[1] : quoted,
                    shape: NodeShape(rawValue: keyword) ?? .box,
                    isHighlighted: words.dropFirst(2).contains { $0.lowercased() == "amber" },
                    step: currentStep
                ))
            case "arrow", "line":
                if kind == "scene3d" {
                    guard scene.items.count < maximumSceneItems,
                          let from = point(after: "from", in: words, centers: sceneCenters),
                          let to = point(after: "to", in: words, centers: sceneCenters) else { continue }
                    if keyword == "arrow" {
                        addSceneItem(.arrow(from: from, to: to, color: color(in: words, default: .amber), label: quoted))
                    } else {
                        addSceneItem(.stick(from: from, to: to, radius: 0.03, color: color(in: words, default: .grey), label: quoted))
                    }
                    continue
                }
                guard var edge = edge(in: words, label: quoted, hasArrow: keyword == "arrow"),
                      flow.edges.count < maximumFlowEdges else { continue }
                edge.step = currentStep
                flow.edges.append(edge)

            // Sequence
            case "actor":
                guard words.count >= 2, sequence.actors.count < 8 else { continue }
                let id = words[1].lowercased()
                guard !sequence.actors.contains(where: { $0.id == id }) else { continue }
                sequence.actors.append(SequenceActor(id: id, label: quoted.isEmpty ? words[1] : quoted))
            case "msg", "message":
                guard let edge = edge(in: words, label: quoted, hasArrow: true),
                      sequence.events.count < maximumSequenceEvents else { continue }
                sequence.events.append(.message(from: edge.from, to: edge.to, label: edge.label))
                sequence.eventSteps.append(currentStep)
            case "note":
                guard !quoted.isEmpty, sequence.events.count < maximumSequenceEvents else { continue }
                sequence.events.append(.note(quoted))
                sequence.eventSteps.append(currentStep)

            // Plot
            case "plot":
                guard plot.curves.count < 3 else { continue }
                let unquotedLine = tokens.filter { !$0.isQuoted }.map(\.text).joined(separator: " ")
                var formulaText = String(unquotedLine.dropFirst(keyword.count))
                var minX = -5.0, maxX = 5.0
                if let range = formulaText.range(of: #"\bfrom\s+(\S+)\s+to\s+(\S+)\s*$"#, options: .regularExpression) {
                    let parts = formulaText[range].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 4, let low = number(parts[1]), let high = number(parts[3]), low < high {
                        minX = low
                        maxX = high
                    }
                    formulaText.removeSubrange(range)
                }
                formulaText = formulaText.replacingOccurrences(of: #"^\s*y\s*="#, with: "", options: .regularExpression)
                guard let formula = Formula(formulaText) else { continue }
                plot.curves.append(PlotCurve(formula: formula, label: quoted, minX: minX, maxX: maxX, step: currentStep))
            case "mark":
                for word in words.dropFirst() {
                    let name = word.lowercased()
                    let mark: PlotMark? = name.hasPrefix("root") || name.hasPrefix("zero") ? .roots
                        : name.hasPrefix("cross") || name.hasPrefix("intersect") ? .crossings
                        : name.hasPrefix("peak") || name.hasPrefix("turn") || name.hasPrefix("max") || name.hasPrefix("min") ? .peaks : nil
                    if let mark, !plot.marks.contains(mark) { plot.marks.append(mark) }
                }
            case "point":
                guard plot.points.count < 12, words.count >= 2 else { continue }
                let parts = words[1].components(separatedBy: ",").compactMap(number)
                guard parts.count == 2 else { continue }
                plot.points.append(PlotPoint(x: parts[0], y: parts[1], label: quoted, step: currentStep))

            // 3D
            case "sphere":
                guard scene.items.count < maximumSceneItems, let center = vector(after: "at", in: words) else { continue }
                let radius = min(max(scalar(after: "r", in: words) ?? 0.4, 0.03), 3)
                if words.count > 1 { sceneCenters[words[1].lowercased()] = center }
                addSceneItem(.sphere(center: center, radius: radius, color: color(in: words, default: .blue), label: quoted))
            case "cylinder":
                guard scene.items.count < maximumSceneItems,
                      let from = point(after: "from", in: words, centers: sceneCenters),
                      let to = point(after: "to", in: words, centers: sceneCenters) else { continue }
                let radius = min(max(scalar(after: "r", in: words) ?? 0.15, 0.02), 2)
                addSceneItem(.stick(from: from, to: to, radius: radius, color: color(in: words, default: .teal), label: quoted))
            case "bond":
                guard words.count >= 3 else { continue }
                pendingBonds.append((words[1].lowercased(), words[2].lowercased(), currentStep))
            case "label":
                guard scene.items.count < maximumSceneItems, !quoted.isEmpty else { continue }
                if let position = vector(after: "at", in: words) {
                    addSceneItem(.label(at: position, text: quoted))
                } else if words.count >= 2, let center = sceneCenters[words[1].lowercased()] {
                    addSceneItem(.label(at: Vector3(x: center.x, y: center.y + 0.6, z: center.z), text: quoted))
                }
            case "axes":
                scene.showsAxes = true
            case "surface":
                let unquotedLine = words.dropFirst().joined(separator: " ")
                var formulaText = unquotedLine
                var low = -3.0, high = 3.0
                if let range = formulaText.range(of: #"\bfrom\s+(\S+)\s+to\s+(\S+)\s*$"#, options: .regularExpression) {
                    let parts = formulaText[range].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 4, let first = number(parts[1]), let second = number(parts[3]), first < second {
                        low = first
                        high = second
                    }
                    formulaText.removeSubrange(range)
                }
                formulaText = formulaText.replacingOccurrences(of: #"^\s*z\s*="#, with: "", options: .regularExpression)
                if let formula = Formula(formulaText) {
                    scene.surface = Surface(formula: formula, minimum: low, maximum: high)
                }
            default:
                continue
            }
        }

        // Bonds may be written before the shapes they join.
        for (first, second, step) in pendingBonds where scene.items.count < maximumSceneItems {
            guard let from = sceneCenters[first], let to = sceneCenters[second] else { continue }
            scene.items.append(.stick(from: from, to: to, radius: 0.07, color: .grey, label: ""))
            scene.itemSteps.append(step)
        }
        // Arrows that name boxes nobody declared would float in space: drop them.
        let nodeIDs = Set(flow.nodes.map(\.id))
        flow.edges.removeAll { !nodeIDs.contains($0.from) || !nodeIDs.contains($0.to) || $0.from == $0.to }
        let actorIDs = Set(sequence.actors.map(\.id))
        let keptEvents = zip(sequence.events, sequence.eventSteps).filter { event, _ in
            if case .message(let from, let to, _) = event { return actorIDs.contains(from) && actorIDs.contains(to) }
            return true
        }
        sequence.events = keptEvents.map(\.0)
        sequence.eventSteps = keptEvents.map(\.1)

        let hasFlow = !flow.nodes.isEmpty
        let hasSequence = sequence.actors.count >= 2 && !sequence.events.isEmpty
        let hasPlot = !plot.curves.isEmpty
        let hasScene = !scene.items.isEmpty || scene.surface != nil

        // Trust the stated type when it has content; otherwise use whatever was actually described.
        let content: Content
        switch kind {
        case _ where modelRequest != nil && (kind == "model" || !(hasFlow || hasSequence || hasPlot || hasScene)):
            content = .model(modelRequest!)
            if title.isEmpty { title = modelEntryInUse?.title ?? "" }
        case "flow" where hasFlow: content = .flow(flow)
        case "sequence" where hasSequence: content = .sequence(sequence)
        case "plot" where hasPlot: content = .plot(plot)
        case "scene3d" where hasScene: content = .scene(scene)
        default:
            if hasScene { content = .scene(scene) }
            else if hasPlot { content = .plot(plot) }
            else if hasSequence { content = .sequence(sequence) }
            else if hasFlow { content = .flow(flow) }
            else { return nil }
        }
        return Drawing(title: title, content: content, stepCount: stepCount(of: content))
    }

    /// The number of parts actually used by what will be drawn.
    static func stepCount(of content: Content) -> Int {
        let steps: [Int]
        switch content {
        case .flow(let flow): steps = flow.nodes.map(\.step) + flow.edges.map(\.step)
        case .sequence(let sequence): steps = sequence.eventSteps
        case .plot(let plot): steps = plot.curves.map(\.step) + plot.points.map(\.step)
        case .scene(let scene): steps = scene.itemSteps
        case .model(let request): steps = request.shownParts.map(\.step)
        }
        return (steps.max() ?? 0) + 1
    }

    /// An arrow can only appear once both of its boxes have.
    static func effectiveStep(of edge: FlowEdge, in flow: Flow) -> Int {
        let nodeSteps = flow.nodes.filter { $0.id == edge.from || $0.id == edge.to }.map(\.step)
        return max(edge.step, nodeSteps.max() ?? 0)
    }

    // MARK: Small parsing helpers

    private struct Token {
        let text: String
        let isQuoted: Bool
    }

    /// Splits on spaces, keeping "quoted text" (straight or curly quotes) as one token.
    private static func tokenize(_ line: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var isInsideQuotes = false
        for character in line {
            if character == "\"" || character == "“" || character == "”" {
                if isInsideQuotes {
                    tokens.append(Token(text: current, isQuoted: true))
                } else if !current.isEmpty {
                    tokens.append(Token(text: current, isQuoted: false))
                }
                current = ""
                isInsideQuotes.toggle()
            } else if character == " " && !isInsideQuotes {
                if !current.isEmpty { tokens.append(Token(text: current, isQuoted: false)) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(Token(text: current, isQuoted: isInsideQuotes)) }
        return tokens
    }

    private static func value(after prefix: String, in line: String) -> String {
        String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func clipped(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespaces).prefix(maximumLabelCharacters))
    }

    private static func number(_ text: String) -> Double? {
        let cleaned = text.lowercased().replacingOccurrences(of: "−", with: "-")
        if let value = Double(cleaned), value.isFinite { return value }
        // "2pi", "-pi", "pi/2" as plot limits.
        return Formula(cleaned)?.value(x: 0, y: 0).flatMap { $0.isFinite ? $0 : nil }
    }

    private static func vector(_ text: String) -> Vector3? {
        let parts = text.components(separatedBy: ",").compactMap { Double($0.replacingOccurrences(of: "−", with: "-")) }
        guard parts.count == 3, parts.allSatisfy({ $0.isFinite && abs($0) <= 50 }) else { return nil }
        return Vector3(x: parts[0], y: parts[1], z: parts[2])
    }

    private static func vector(after keyword: String, in words: [String]) -> Vector3? {
        guard let index = words.firstIndex(where: { $0.lowercased() == keyword }), index + 1 < words.count else { return nil }
        return vector(words[index + 1])
    }

    /// A point given as coordinates or as the name of a shape already placed.
    private static func point(after keyword: String, in words: [String], centers: [String: Vector3]) -> Vector3? {
        guard let index = words.firstIndex(where: { $0.lowercased() == keyword }), index + 1 < words.count else { return nil }
        return vector(words[index + 1]) ?? centers[words[index + 1].lowercased()]
    }

    private static func scalar(after keyword: String, in words: [String]) -> Double? {
        guard let index = words.firstIndex(where: { $0.lowercased() == keyword }), index + 1 < words.count else { return nil }
        return Double(words[index + 1])
    }

    private static func color(in words: [String], default defaultColor: SceneColor) -> SceneColor {
        for word in words.reversed() {
            let name = word.lowercased() == "gray" ? "grey" : word.lowercased()
            if let color = SceneColor(rawValue: name) { return color }
        }
        return defaultColor
    }

    /// "a -> b", "a->b", "a -- b".
    private static func edge(in words: [String], label: String, hasArrow: Bool) -> FlowEdge? {
        let joined = words.dropFirst().joined(separator: " ")
        guard let separator = joined.range(of: #"\s*(->|-->|→|--|—)\s*"#, options: .regularExpression) else { return nil }
        let from = joined[..<separator.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
        let rest = joined[separator.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let to = rest.components(separatedBy: " ").first?.lowercased(), !from.isEmpty, !to.isEmpty,
              !from.contains(" ") else { return nil }
        return FlowEdge(from: from, to: to, label: label, hasArrow: hasArrow)
    }

    // MARK: - Laying out a flow chart (pure)

    struct Rect: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var midX: Double { x + width / 2 }
        var midY: Double { y + height / 2 }
    }

    struct FlowLayout: Equatable, Sendable {
        var frames: [String: Rect]
        var labelLines: [String: [String]]
        /// Arrows that run back toward an earlier layer ("from>to"). They are drawn around the
        /// outside so they do not cut through the boxes in between.
        var backwardEdges: Set<String> = []
        var width: Double
        var height: Double
    }

    static let flowCharacterWidth = 7.0
    static let flowLineHeight = 17.0

    /// Breaks a label into at most three short lines.
    static func wrapped(_ label: String, lineLength: Int = 24) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in label.components(separatedBy: " ") where !word.isEmpty {
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= lineLength {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        if lines.count > 3 {
            lines = Array(lines.prefix(3))
            lines[2] = String(lines[2].prefix(lineLength - 1)) + "…"
        }
        return lines.isEmpty ? [""] : lines
    }

    /// Layered layout: every box sits one layer after the latest box that points to it.
    /// Arrows that would close a loop are ignored for ranking, so cycles cannot hang it.
    static func layout(_ flow: Flow) -> FlowLayout {
        let ids = flow.nodes.map(\.id)
        var outgoing: [String: [String]] = [:]
        for edge in flow.edges { outgoing[edge.from, default: []].append(edge.to) }

        // Depth-first search marks the arrows that point back up a path (loops).
        var state: [String: Int] = [:]   // 1 = on the current path, 2 = finished
        var loopEdges = Set<String>()
        func visit(_ id: String) {
            state[id] = 1
            for next in outgoing[id] ?? [] {
                if state[next] == 1 { loopEdges.insert(id + ">" + next) }
                else if state[next] == nil { visit(next) }
            }
            state[id] = 2
        }
        for id in ids where state[id] == nil { visit(id) }

        var rank: [String: Int] = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        // Longest path, by repeated relaxation (the graph is tiny).
        for _ in 0..<ids.count {
            var didChange = false
            for edge in flow.edges where !loopEdges.contains(edge.from + ">" + edge.to) {
                if let fromRank = rank[edge.from], let toRank = rank[edge.to], toRank < fromRank + 1 {
                    rank[edge.to] = fromRank + 1
                    didChange = true
                }
            }
            if !didChange { break }
        }

        let layerCount = (rank.values.max() ?? 0) + 1
        var layers: [[String]] = Array(repeating: [], count: layerCount)
        for id in ids { layers[rank[id] ?? 0].append(id) }

        // One pass to reduce crossings: order each layer by the average position of its parents.
        var incoming: [String: [String]] = [:]
        for edge in flow.edges { incoming[edge.to, default: []].append(edge.from) }
        if layerCount > 1 {
            for layerIndex in 1..<layerCount {
                let previous = layers[layerIndex - 1]
                let positions = Dictionary(uniqueKeysWithValues: previous.enumerated().map { ($1, Double($0)) })
                let original = Dictionary(uniqueKeysWithValues: layers[layerIndex].enumerated().map { ($1, Double($0)) })
                layers[layerIndex].sort { first, second in
                    func score(_ id: String) -> Double {
                        let parents = (incoming[id] ?? []).compactMap { positions[$0] }
                        return parents.isEmpty ? (original[id] ?? 0) : parents.reduce(0, +) / Double(parents.count)
                    }
                    let firstScore = score(first), secondScore = score(second)
                    return firstScore == secondScore ? (original[first] ?? 0) < (original[second] ?? 0) : firstScore < secondScore
                }
            }
        }

        // Box sizes from their text.
        var sizes: [String: (width: Double, height: Double)] = [:]
        var labelLines: [String: [String]] = [:]
        for node in flow.nodes {
            let lines = wrapped(node.label)
            labelLines[node.id] = lines
            let longest = Double(lines.map(\.count).max() ?? 0)
            var width = min(max(longest * flowCharacterWidth + 30, 86), 190)
            var height = 22 + Double(lines.count) * flowLineHeight
            if node.shape == .diamond {
                width += 36
                height += 20
            }
            sizes[node.id] = (width, height)
        }

        let backwardEdges = Set(flow.edges.filter { (rank[$0.to] ?? 0) <= (rank[$0.from] ?? 0) }.map { $0.from + ">" + $0.to })
        let boxGap = 30.0
        let layerGap = 54.0
        // Room at the sides for arrows that loop back.
        let margin = backwardEdges.isEmpty ? 18.0 : 64.0
        var frames: [String: Rect] = [:]

        // "along" runs through the layers, "across" runs within one layer.
        let layerAcross: [Double] = layers.map { layer in
            layer.reduce(0) { $0 + (flow.isHorizontal ? sizes[$1]!.height : sizes[$1]!.width) } + boxGap * Double(max(0, layer.count - 1))
        }
        let layerAlong: [Double] = layers.map { layer in
            layer.map { flow.isHorizontal ? sizes[$0]!.width : sizes[$0]!.height }.max() ?? 0
        }
        var totalAcross = layerAcross.max() ?? 0

        // A tree (every box has at most one parent, nothing loops back) reads best with each
        // parent centred over its children, so place the leaves in order and work upward.
        var treeCenters: [String: Double] = [:]
        let isTree = backwardEdges.isEmpty && !flow.edges.isEmpty && ids.allSatisfy { (incoming[$0] ?? []).count <= 1 }
        if isTree {
            func acrossSize(_ id: String) -> Double { flow.isHorizontal ? sizes[id]!.height : sizes[id]!.width }
            var cursor = 0.0
            func place(_ id: String, depth: Int) {
                let children = depth < 40 ? (outgoing[id] ?? []).filter { treeCenters[$0] == nil } : []
                guard !children.isEmpty else {
                    treeCenters[id] = cursor + acrossSize(id) / 2
                    cursor += acrossSize(id) + boxGap
                    return
                }
                let start = cursor
                for child in children { place(child, depth: depth + 1) }
                var center = (treeCenters[children.first!]! + treeCenters[children.last!]!) / 2
                // A parent wider than its children must not overlap the subtree before it.
                if center - acrossSize(id) / 2 < start {
                    let shift = start - (center - acrossSize(id) / 2)
                    func move(_ node: String) {
                        treeCenters[node]! += shift
                        for child in outgoing[node] ?? [] where child != node { move(child) }
                    }
                    for child in children { move(child) }
                    center += shift
                    cursor += shift
                }
                treeCenters[id] = center
                cursor = max(cursor, center + acrossSize(id) / 2 + boxGap)
            }
            for id in ids where (incoming[id] ?? []).isEmpty { place(id, depth: 0) }
            totalAcross = max(0, cursor - boxGap)
        }
        var along = margin
        for (layerIndex, layer) in layers.enumerated() {
            var across = margin + (totalAcross - layerAcross[layerIndex]) / 2
            for id in layer {
                let size = sizes[id]!
                if let center = treeCenters[id] {
                    across = margin + center - (flow.isHorizontal ? size.height : size.width) / 2
                }
                if flow.isHorizontal {
                    frames[id] = Rect(x: along + (layerAlong[layerIndex] - size.width) / 2, y: across, width: size.width, height: size.height)
                    across += size.height + boxGap
                } else {
                    frames[id] = Rect(x: across, y: along + (layerAlong[layerIndex] - size.height) / 2, width: size.width, height: size.height)
                    across += size.width + boxGap
                }
            }
            along += layerAlong[layerIndex] + layerGap
        }
        let totalAlong = along - layerGap + margin
        return FlowLayout(
            frames: frames, labelLines: labelLines, backwardEdges: backwardEdges,
            width: flow.isHorizontal ? totalAlong : totalAcross + margin * 2,
            height: flow.isHorizontal ? totalAcross + margin * 2 : totalAlong
        )
    }

    // MARK: - Formulas (pure)

    /// A formula such as "sin(x)*cos(y) + x^2/4", parsed once into a tree and then evaluated by
    /// walking the tree. Only numbers, x, y, pi, e, + - * / ^ and a fixed list of functions exist:
    /// there is no way to reach anything else from the model's text.
    struct Formula: Equatable, Sendable {
        indirect enum Node: Equatable, Sendable {
            case number(Double)
            case variableX
            case variableY
            case negate(Node)
            case binary(Character, Node, Node)
            case function(String, Node)
        }

        let root: Node

        static let functionNames: Set<String> = ["sin", "cos", "tan", "exp", "ln", "log", "sqrt", "abs", "asin", "acos", "atan", "sinh", "cosh", "tanh"]

        init?(_ text: String) {
            var parser = Parser(text)
            guard let node = parser.parseExpression(), parser.isAtEnd, parser.nodeCount <= 200 else { return nil }
            root = node
        }

        /// Nil where the formula has no real value (division by zero, square root of a negative).
        func value(x: Double, y: Double = 0) -> Double? {
            let result = Self.evaluate(root, x: x, y: y)
            return result.isFinite ? result : nil
        }

        private static func evaluate(_ node: Node, x: Double, y: Double) -> Double {
            switch node {
            case .number(let value): return value
            case .variableX: return x
            case .variableY: return y
            case .negate(let inner): return -evaluate(inner, x: x, y: y)
            case .binary(let operation, let left, let right):
                let leftValue = evaluate(left, x: x, y: y), rightValue = evaluate(right, x: x, y: y)
                switch operation {
                case "+": return leftValue + rightValue
                case "-": return leftValue - rightValue
                case "*": return leftValue * rightValue
                case "/": return rightValue == 0 ? .nan : leftValue / rightValue
                default: return pow(leftValue, rightValue)
                }
            case .function(let name, let inner):
                let value = evaluate(inner, x: x, y: y)
                switch name {
                case "sin": return sin(value)
                case "cos": return cos(value)
                case "tan": return tan(value)
                case "exp": return exp(value)
                case "ln": return value > 0 ? log(value) : .nan
                case "log": return value > 0 ? log10(value) : .nan
                case "sqrt": return value >= 0 ? sqrt(value) : .nan
                case "abs": return abs(value)
                case "asin": return asin(value)
                case "acos": return acos(value)
                case "atan": return atan(value)
                case "sinh": return sinh(value)
                case "cosh": return cosh(value)
                default: return tanh(value)
                }
            }
        }

        /// Recursive descent: expression = term (+|- term)*, term = factor (*|/ factor)*,
        /// factor = unary (^ factor)?, with "2x" and "2sin(x)" read as multiplication.
        private struct Parser {
            private let characters: [Character]
            private var position = 0
            private(set) var nodeCount = 0

            init(_ text: String) {
                characters = Array(text.lowercased()
                    .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
                    .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "π", with: "pi")
                    .replacingOccurrences(of: "**", with: "^")
                    .filter { !$0.isWhitespace })
            }

            var isAtEnd: Bool { position >= characters.count }
            private var current: Character? { position < characters.count ? characters[position] : nil }

            mutating func parseExpression() -> Node? {
                guard var left = parseTerm() else { return nil }
                while let operation = current, operation == "+" || operation == "-" {
                    position += 1
                    guard let right = parseTerm() else { return nil }
                    left = .binary(operation, left, right)
                    nodeCount += 1
                }
                return left
            }

            private mutating func parseTerm() -> Node? {
                guard var left = parseFactor() else { return nil }
                while let character = current {
                    if character == "*" || character == "/" {
                        position += 1
                        guard let right = parseFactor() else { return nil }
                        left = .binary(character, left, right)
                    } else if character.isLetter || character == "(" {
                        // Implicit multiplication: "2x", "3(x+1)", "2sin(x)".
                        guard let right = parseFactor() else { return nil }
                        left = .binary("*", left, right)
                    } else {
                        break
                    }
                    nodeCount += 1
                }
                return left
            }

            private mutating func parseFactor() -> Node? {
                guard let base = parseUnary() else { return nil }
                if current == "^" {
                    position += 1
                    guard let exponent = parseFactor() else { return nil }
                    nodeCount += 1
                    return .binary("^", base, exponent)
                }
                return base
            }

            private mutating func parseUnary() -> Node? {
                nodeCount += 1
                guard nodeCount <= 400 else { return nil }
                if current == "-" {
                    position += 1
                    guard let inner = parseFactor() else { return nil }
                    return .negate(inner)
                }
                if current == "+" { position += 1 }
                return parsePrimary()
            }

            private mutating func parsePrimary() -> Node? {
                guard let character = current else { return nil }
                if character == "(" {
                    position += 1
                    guard let inner = parseExpression(), current == ")" else { return nil }
                    position += 1
                    return inner
                }
                if character.isNumber || character == "." {
                    var text = ""
                    while let digit = current, digit.isNumber || digit == "." {
                        text.append(digit)
                        position += 1
                    }
                    guard let value = Double(text) else { return nil }
                    return .number(value)
                }
                if character.isLetter {
                    var name = ""
                    while let letter = current, letter.isLetter {
                        name.append(letter)
                        position += 1
                    }
                    if Formula.functionNames.contains(name) {
                        guard current == "(" else { return nil }
                        position += 1
                        guard let inner = parseExpression(), current == ")" else { return nil }
                        position += 1
                        return .function(name, inner)
                    }
                    switch name {
                    case "x": return .variableX
                    case "y": return .variableY
                    case "pi": return .number(Double.pi)
                    case "e": return .number(M_E)
                    default:
                        // "xy" or "pix" style products of known names.
                        return Self.product(of: name)
                    }
                }
                return nil
            }

            private static func product(of name: String) -> Node? {
                var remaining = Substring(name)
                var factors: [Node] = []
                while !remaining.isEmpty {
                    if remaining.hasPrefix("pi") { factors.append(.number(Double.pi)); remaining = remaining.dropFirst(2) }
                    else if remaining.hasPrefix("x") { factors.append(.variableX); remaining = remaining.dropFirst() }
                    else if remaining.hasPrefix("y") { factors.append(.variableY); remaining = remaining.dropFirst() }
                    else if remaining.hasPrefix("e") { factors.append(.number(M_E)); remaining = remaining.dropFirst() }
                    else { return nil }
                }
                guard var result = factors.first else { return nil }
                for factor in factors.dropFirst() { result = .binary("*", result, factor) }
                return result
            }
        }
    }

    // MARK: - Sampling a plot (pure)

    /// The curve as runs of points; a run ends where the formula has no value or jumps (an asymptote).
    static func samples(of curve: PlotCurve, count: Int = 240) -> [[(x: Double, y: Double)]] {
        var runs: [[(x: Double, y: Double)]] = []
        var current: [(x: Double, y: Double)] = []
        let step = (curve.maxX - curve.minX) / Double(max(1, count - 1))
        for index in 0..<count {
            let x = curve.minX + Double(index) * step
            guard let y = curve.formula.value(x: x), abs(y) < 1e6 else {
                if current.count > 1 { runs.append(current) }
                current = []
                continue
            }
            // A leap from far above the axis to far below it (or back) is an asymptote, not a line.
            if let last = current.last, abs(y - last.y) > 1e3 || (y * last.y < 0 && abs(y) > 4 && abs(last.y) > 4) {
                if current.count > 1 { runs.append(current) }
                current = []
            }
            current.append((x, y))
        }
        if current.count > 1 { runs.append(current) }
        return runs
    }

    /// The points the app marks by itself: where curves cross zero, cross each other, or turn.
    /// Found by looking for a change of sign between samples, then closing in by halving.
    static func markedPoints(for plot: Plot) -> [PlotPoint] {
        var found: [PlotPoint] = []

        func signChanges(of function: (Double) -> Double?, from minX: Double, to maxX: Double) -> [Double] {
            guard maxX > minX else { return [] }
            var results: [Double] = []
            let count = 400
            let step = (maxX - minX) / Double(count)
            var previousX = minX
            var previousValue = function(minX)
            for index in 1...count {
                let x = minX + Double(index) * step
                let value = function(x)
                defer {
                    previousX = x
                    previousValue = value
                }
                guard let value, let previous = previousValue else { continue }
                if previous == 0 {
                    results.append(previousX)
                } else if previous * value < 0, abs(previous - value) < 1e3 {
                    var low = previousX, high = x, lowValue = previous
                    for _ in 0..<50 {
                        let middle = (low + high) / 2
                        guard let middleValue = function(middle) else { break }
                        if lowValue * middleValue <= 0 { high = middle } else { low = middle; lowValue = middleValue }
                    }
                    // At an asymptote the sign flips too, but the value there is huge, not zero.
                    let candidate = (low + high) / 2
                    if let atCandidate = function(candidate), abs(atCandidate) < 1e-3 * max(1, abs(previous), abs(value)) {
                        results.append(candidate)
                    }
                }
            }
            if let last = previousValue, last == 0 { results.append(previousX) }
            return results
        }
        func described(_ x: Double, _ y: Double) -> String {
            func rounded(_ value: Double) -> String { tickLabel((value * 100).rounded() / 100) }
            return "(\(rounded(x)), \(rounded(y)))"
        }
        func add(_ x: Double, _ y: Double) {
            guard found.count < 12, !found.contains(where: { abs($0.x - x) < 1e-6 && abs($0.y - y) < 1e-6 }) else { return }
            found.append(PlotPoint(x: x, y: y, label: described(x, y)))
        }

        for mark in plot.marks {
            switch mark {
            case .roots:
                for curve in plot.curves {
                    for x in signChanges(of: { curve.formula.value(x: $0) }, from: curve.minX, to: curve.maxX) { add(x, 0) }
                }
            case .crossings:
                for first in 0..<plot.curves.count {
                    for second in (first + 1)..<max(first + 1, plot.curves.count) {
                        let a = plot.curves[first], b = plot.curves[second]
                        let difference: (Double) -> Double? = { x in
                            guard let av = a.formula.value(x: x), let bv = b.formula.value(x: x) else { return nil }
                            return av - bv
                        }
                        for x in signChanges(of: difference, from: max(a.minX, b.minX), to: min(a.maxX, b.maxX)) {
                            if let y = a.formula.value(x: x) { add(x, y) }
                        }
                    }
                }
            case .peaks:
                for curve in plot.curves {
                    let width = (curve.maxX - curve.minX) * 1e-5
                    let slope: (Double) -> Double? = { x in
                        guard let ahead = curve.formula.value(x: x + width), let behind = curve.formula.value(x: x - width) else { return nil }
                        return (ahead - behind) / (2 * width)
                    }
                    for x in signChanges(of: slope, from: curve.minX + width, to: curve.maxX - width) {
                        if let y = curve.formula.value(x: x) { add(x, y) }
                    }
                }
            }
        }
        return found
    }

    /// A vertical range that shows the curves without letting one spike flatten everything else.
    static func verticalRange(of runs: [[(x: Double, y: Double)]], points: [PlotPoint]) -> (low: Double, high: Double) {
        var values = runs.flatMap { $0.map(\.y) }.sorted()
        guard !values.isEmpty else { return (-1, 1) }
        // Ignore the most extreme 2% at each end (asymptotes), then pad.
        let trim = values.count / 50
        if values.count > 20 { values = Array(values[trim..<(values.count - trim)]) }
        var low = values.first ?? -1, high = values.last ?? 1
        for point in points {
            low = min(low, point.y)
            high = max(high, point.y)
        }
        if high - low < 1e-9 {
            low -= 1
            high += 1
        }
        let padding = (high - low) * 0.08
        return (low - padding, high + padding)
    }

    /// Round tick values for an axis: 1, 2 or 5 times a power of ten apart.
    static func ticks(from low: Double, to high: Double, target: Int = 6) -> [Double] {
        guard high > low, target > 0 else { return [] }
        let rawStep = (high - low) / Double(target)
        let magnitude = pow(10, floor(log10(rawStep)))
        let normalized = rawStep / magnitude
        let step = (normalized < 1.5 ? 1 : normalized < 3.5 ? 2 : normalized < 7.5 ? 5 : 10) * magnitude
        var ticks: [Double] = []
        var value = ceil(low / step) * step
        while value <= high + step * 1e-9, ticks.count < 40 {
            ticks.append(abs(value) < step * 1e-9 ? 0 : value)
            value += step
        }
        return ticks
    }

    static func tickLabel(_ value: Double) -> String {
        if value == 0 { return "0" }
        if abs(value) >= 1000 || abs(value) < 0.01 { return String(format: "%.1e", value) }
        let text = String(format: "%.2f", value)
        return text.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}
