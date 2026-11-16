//
//  ThambiModels.swift
//  leanring-buddy
//
//  The ready-made 3D models: heart, animal cell, engine cylinder, DNA, atom, solar system.
//
//  Every one is built here, in code, from spheres, tubes and rings. There are no model files in
//  the app, so nothing is borrowed, nothing needs a licence, and nothing is downloaded. They are
//  teaching schematics, simplified on purpose; the heart and the solar system say so in their titles.
//
//  Each model names its parts and where a label for each belongs. The catalogue of names the AI
//  may use lives in ThambiDrawing.modelCatalogue; a test checks the two lists agree.
//

import AppKit
import SceneKit
import SwiftUI

@MainActor
enum ThambiModels {

    /// Where a part's label goes: a point in the space of `node` (labels on a moving part follow it).
    struct PartAnchor {
        let node: SCNNode
        let offset: SCNVector3
    }

    struct Built {
        let root: SCNNode
        var anchors: [String: PartAnchor] = [:]
        /// True when the model moves by itself (engine, atom, planets).
        var isAnimated = false
    }

    static func build(_ id: String, isMoving: Bool) -> Built? {
        switch id {
        case "heart": return heart()
        case "cell": return cell()
        case "engine": return engine(isMoving: isMoving)
        case "dna": return dna()
        case "atom": return atom(isMoving: isMoving)
        case "solar-system": return solarSystem(isMoving: isMoving)
        default: return nil
        }
    }

    // MARK: - Building blocks

    private static let red = DrawingSceneBuilder.color(.red)
    private static let blue = DrawingSceneBuilder.color(.blue)
    private static let deepBlue = NSColor(DS.Colors.coolDeep)
    private static let amber = DrawingSceneBuilder.color(.amber)
    private static let green = DrawingSceneBuilder.color(.green)
    private static let grey = DrawingSceneBuilder.color(.grey)
    private static let white = DrawingSceneBuilder.color(.white)
    private static let teal = DrawingSceneBuilder.color(.teal)

    private static func point(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
        SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z))
    }

    /// A ball stretched to the given half-sizes.
    private static func ellipsoid(at center: SCNVector3, radii: SCNVector3, color: NSColor, opacity: CGFloat = 1) -> SCNNode {
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 40
        let material = DrawingSceneBuilder.material(color)
        if opacity < 1 {
            material.transparency = opacity
            // See-through shells must not hide what is inside them.
            material.writesToDepthBuffer = false
        }
        sphere.materials = [material]
        let node = SCNNode(geometry: sphere)
        node.position = center
        node.scale = radii
        if opacity < 1 { node.renderingOrder = 10 }
        return node
    }

    private static func ball(at center: SCNVector3, radius: Double, color: NSColor) -> SCNNode {
        let sphere = SCNSphere(radius: CGFloat(radius))
        sphere.segmentCount = 24
        sphere.materials = [DrawingSceneBuilder.material(color)]
        let node = SCNNode(geometry: sphere)
        node.position = center
        return node
    }

    /// A bendy pipe through the given points.
    private static func tube(through points: [SCNVector3], radius: Double, color: NSColor) -> SCNNode {
        let group = SCNNode()
        for index in points.indices {
            group.addChildNode(ball(at: points[index], radius: radius, color: color))
            if index > 0 {
                group.addChildNode(DrawingSceneBuilder.stick(from: points[index - 1], to: points[index], radius: CGFloat(radius), color: color))
            }
        }
        return group
    }

    private static func ring(radius: Double, thickness: Double, color: NSColor) -> SCNNode {
        let torus = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: CGFloat(thickness))
        torus.ringSegmentCount = 96
        torus.materials = [DrawingSceneBuilder.material(color, isFlat: true)]
        return SCNNode(geometry: torus)
    }

    /// The same "random" numbers every time, so a model looks the same on every Mac and in tests.
    private struct SteadyRandom {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 1_000_000) / 1_000_000
        }
        /// A point inside a ball of the given radius.
        mutating func pointInBall(radius: Double) -> SCNVector3 {
            while true {
                let x = next() * 2 - 1, y = next() * 2 - 1, z = next() * 2 - 1
                if x * x + y * y + z * z <= 1 { return ThambiModels.point(x * radius, y * radius, z * radius) }
            }
        }
    }

    // MARK: - Heart

    /// Four chambers and the great vessels, seen from the front. Red carries oxygen-rich blood,
    /// blue oxygen-poor blood, as in a textbook figure.
    private static func heart() -> Built {
        let root = SCNNode()
        var built = Built(root: root)
        func anchor(_ name: String, _ x: Double, _ y: Double, _ z: Double) {
            built.anchors[name] = PartAnchor(node: root, offset: point(x, y, z))
        }

        root.addChildNode(ellipsoid(at: point(0.48, -0.55, 0), radii: point(0.78, 1.05, 0.75), color: red))
        anchor("left ventricle", 1.15, -0.9, 0.5)
        root.addChildNode(ellipsoid(at: point(-0.42, -0.45, 0.22), radii: point(0.72, 0.92, 0.62), color: deepBlue))
        anchor("right ventricle", -1.1, -0.85, 0.6)
        root.addChildNode(ellipsoid(at: point(0.55, 0.72, -0.22), radii: point(0.5, 0.42, 0.45), color: red))
        anchor("left atrium", 1.25, 0.55, 0)
        root.addChildNode(ellipsoid(at: point(-0.68, 0.7, 0), radii: point(0.5, 0.48, 0.45), color: deepBlue))
        anchor("right atrium", -1.4, 0.55, 0.3)

        root.addChildNode(tube(through: [point(0.25, 0.4, 0.1), point(0.2, 1.45, 0.05), point(0.5, 1.9, -0.15), point(0.95, 1.75, -0.38), point(1.08, 1.1, -0.48), point(1.08, 0.3, -0.5)], radius: 0.2, color: red))
        anchor("aorta", 0.6, 2.25, -0.15)
        root.addChildNode(tube(through: [point(-0.25, 0.35, 0.42), point(-0.08, 1.12, 0.36), point(0.55, 1.36, 0.14)], radius: 0.16, color: deepBlue))
        root.addChildNode(tube(through: [point(-0.08, 1.12, 0.36), point(-0.78, 1.42, 0.12)], radius: 0.16, color: deepBlue))
        anchor("pulmonary artery", -0.2, 1.5, 0.75)
        root.addChildNode(tube(through: [point(-0.72, 2.05, -0.05), point(-0.7, 1.05, 0)], radius: 0.16, color: deepBlue))
        root.addChildNode(tube(through: [point(-0.72, -1.7, -0.12), point(-0.7, 0.32, -0.02)], radius: 0.16, color: deepBlue))
        anchor("vena cava", -1.2, 2.1, 0)
        root.addChildNode(tube(through: [point(1.45, 0.98, -0.5), point(0.9, 0.82, -0.32)], radius: 0.09, color: red))
        root.addChildNode(tube(through: [point(1.45, 0.62, -0.5), point(0.9, 0.64, -0.32)], radius: 0.09, color: red))
        anchor("pulmonary veins", 1.75, 0.95, -0.4)
        return built
    }

    // MARK: - Animal cell

    private static func cell() -> Built {
        let root = SCNNode()
        var built = Built(root: root)
        func anchor(_ name: String, _ x: Double, _ y: Double, _ z: Double) {
            built.anchors[name] = PartAnchor(node: root, offset: point(x, y, z))
        }
        var random = SteadyRandom(seed: 7)

        root.addChildNode(ellipsoid(at: point(0, 0, 0), radii: point(2.05, 1.85, 2.0), color: teal, opacity: 0.16))
        anchor("cell membrane", -1.7, 1.55, 0.4)

        let nucleusCenter = point(-0.35, 0.1, 0)
        root.addChildNode(ellipsoid(at: nucleusCenter, radii: point(0.72, 0.7, 0.7), color: blue, opacity: 0.6))
        anchor("nucleus", -1.2, 0.85, 0.5)
        root.addChildNode(ball(at: point(-0.28, 0.18, 0.1), radius: 0.22, color: deepBlue))
        anchor("nucleolus", -0.28, 0.18, 0.5)

        // Endoplasmic reticulum: folded sheets wrapped round the nucleus.
        for (index, radius) in [0.92, 1.04, 1.16].enumerated() {
            let fold = ring(radius: radius, thickness: 0.045, color: teal)
            fold.geometry?.materials = [DrawingSceneBuilder.material(teal)]
            fold.position = nucleusCenter
            fold.scale = point(1, 2.4, 1)
            fold.eulerAngles = point(0.25 * Double(index) - 0.2, 0, 0.18 * Double(index))
            root.addChildNode(fold)
        }
        anchor("endoplasmic reticulum", -1.45, -0.55, 0.6)

        // Mitochondria: short rounded rods.
        for (position, tilt) in [(point(1.15, 0.75, 0.3), 0.6), (point(0.6, -1.05, 0.7), -0.9), (point(-1.1, -1.0, -0.4), 0.3), (point(0.2, 1.2, -0.8), 1.2), (point(1.2, -0.2, -0.9), -0.4)] {
            let capsule = SCNCapsule(capRadius: 0.14, height: 0.6)
            capsule.materials = [DrawingSceneBuilder.material(amber)]
            let node = SCNNode(geometry: capsule)
            node.position = position
            node.eulerAngles = point(tilt, tilt * 0.7, 1.1 - tilt)
            root.addChildNode(node)
        }
        anchor("mitochondria", 1.5, 1.0, 0.35)

        // Golgi apparatus: a stack of curved, flattened sacs.
        for index in 0..<5 {
            let width = 0.5 - 0.05 * Double(index)
            root.addChildNode(ellipsoid(at: point(1.0, -0.62 - 0.11 * Double(index), 0.15), radii: point(width, 0.04, 0.26), color: green))
        }
        anchor("golgi apparatus", 1.55, -1.25, 0.3)

        for _ in 0..<34 {
            let position = random.pointInBall(radius: 1.6)
            // Keep them out of the nucleus.
            let dx = Double(position.x) + 0.35, dy = Double(position.y) - 0.1, dz = Double(position.z)
            guard dx * dx + dy * dy + dz * dz > 0.85 else { continue }
            root.addChildNode(ball(at: position, radius: 0.04, color: white))
        }
        anchor("ribosomes", -0.7, -1.5, 1.0)

        for position in [point(0.1, -1.3, -0.2), point(-0.9, 1.1, 0.5), point(0.9, 0.2, 1.1), point(-0.2, -0.6, -1.3)] {
            root.addChildNode(ball(at: position, radius: 0.13, color: red))
        }
        anchor("lysosomes", 0.1, -1.6, -0.2)

        let firstCentriole = DrawingSceneBuilder.stick(from: point(0.45, 1.0, 0.4), to: point(0.78, 1.0, 0.4), radius: 0.06, color: grey)
        let secondCentriole = DrawingSceneBuilder.stick(from: point(0.62, 0.8, 0.52), to: point(0.62, 1.12, 0.52), radius: 0.06, color: grey)
        root.addChildNode(firstCentriole)
        root.addChildNode(secondCentriole)
        anchor("centrioles", 0.75, 1.62, 0.5)
        return built
    }

    // MARK: - Engine

    /// One cylinder of a four-stroke engine, running: intake, compression, power, exhaust.
    private static func engine(isMoving: Bool) -> Built {
        let root = SCNNode()
        var built = Built(root: root, isAnimated: isMoving)

        let crankCenterY = -1.6
        let crankRadius = 0.5
        let rodLength = 1.6
        func pinHeight(atAngle angle: Double) -> Double {
            crankCenterY + crankRadius * cos(angle) + (rodLength * rodLength - crankRadius * crankRadius * sin(angle) * sin(angle)).squareRoot()
        }

        // Cylinder wall, see-through so the piston shows.
        let wall = SCNTube(innerRadius: 0.63, outerRadius: 0.72, height: 1.9)
        let wallMaterial = DrawingSceneBuilder.material(grey)
        wallMaterial.transparency = 0.28
        wallMaterial.writesToDepthBuffer = false
        wall.materials = [wallMaterial]
        let wallNode = SCNNode(geometry: wall)
        wallNode.position = point(0, 0.45, 0)
        wallNode.renderingOrder = 10
        root.addChildNode(wallNode)
        let head = SCNCylinder(radius: 0.72, height: 0.1)
        head.materials = [DrawingSceneBuilder.material(grey)]
        let headNode = SCNNode(geometry: head)
        headNode.position = point(0, 1.45, 0)
        root.addChildNode(headNode)
        built.anchors["cylinder"] = PartAnchor(node: root, offset: point(-1.15, 0.6, 0))

        // Piston, with the rod hanging from its pin and always aimed at the crank pin.
        let pistonNode = SCNNode()
        let pistonBody = SCNCylinder(radius: 0.6, height: 0.5)
        pistonBody.materials = [DrawingSceneBuilder.material(white)]
        let pistonBodyNode = SCNNode(geometry: pistonBody)
        pistonBodyNode.position = point(0, 0.12, 0)
        pistonNode.addChildNode(pistonBodyNode)
        root.addChildNode(pistonNode)
        built.anchors["piston"] = PartAnchor(node: pistonNode, offset: point(1.15, 0.2, 0))

        let crankNode = SCNNode()
        crankNode.position = point(0, crankCenterY, 0)
        let web = SCNCylinder(radius: 0.62, height: 0.14)
        web.materials = [DrawingSceneBuilder.material(amber)]
        let webNode = SCNNode(geometry: web)
        webNode.eulerAngles = point(Double.pi / 2, 0, 0)
        webNode.position = point(0, 0, -0.2)
        crankNode.addChildNode(webNode)
        let shaft = DrawingSceneBuilder.stick(from: point(0, 0, -0.9), to: point(0, 0, -0.2), radius: 0.12, color: amber)
        crankNode.addChildNode(shaft)
        let crankPin = ball(at: point(0, crankRadius, 0), radius: 0.11, color: amber)
        crankNode.addChildNode(crankPin)
        root.addChildNode(crankNode)
        built.anchors["crankshaft"] = PartAnchor(node: root, offset: point(1.1, crankCenterY - 0.3, 0))

        let rodNode = SCNNode()
        let rod = SCNCylinder(radius: 0.07, height: CGFloat(rodLength))
        rod.materials = [DrawingSceneBuilder.material(teal)]
        let rodBodyNode = SCNNode(geometry: rod)
        rodBodyNode.position = point(0, -rodLength / 2, 0)
        rodNode.addChildNode(rodBodyNode)
        let aim = SCNLookAtConstraint(target: crankPin)
        aim.localFront = point(0, -1, 0)
        aim.isGimbalLockEnabled = false
        rodNode.constraints = [aim]
        pistonNode.addChildNode(rodNode)
        built.anchors["connecting rod"] = PartAnchor(node: root, offset: point(-1.0, -0.75, 0))

        // Valves and spark plug in the head.
        func valve(x: Double, color: NSColor) -> SCNNode {
            let node = SCNNode()
            node.addChildNode(DrawingSceneBuilder.stick(from: point(0, 0, 0), to: point(0, 0.5, 0), radius: 0.04, color: color))
            let disc = SCNCylinder(radius: 0.17, height: 0.05)
            disc.materials = [DrawingSceneBuilder.material(color)]
            node.addChildNode(SCNNode(geometry: disc))
            node.position = point(x, 1.36, 0)
            return node
        }
        let intakeValve = valve(x: -0.32, color: blue)
        let exhaustValve = valve(x: 0.32, color: red)
        root.addChildNode(intakeValve)
        root.addChildNode(exhaustValve)
        built.anchors["intake valve"] = PartAnchor(node: root, offset: point(-0.75, 2.1, 0))
        built.anchors["exhaust valve"] = PartAnchor(node: root, offset: point(0.75, 2.1, 0))
        root.addChildNode(DrawingSceneBuilder.stick(from: point(0, 1.42, 0), to: point(0, 1.85, 0), radius: 0.06, color: white))
        let spark = ball(at: point(0, 1.3, 0), radius: 0.1, color: amber)
        spark.geometry?.materials = [DrawingSceneBuilder.material(amber, isFlat: true)]
        spark.opacity = 0
        root.addChildNode(spark)
        built.anchors["spark plug"] = PartAnchor(node: root, offset: point(0, 2.45, 0))

        guard isMoving else {
            // A still frame: piston part-way down on the intake stroke, intake valve open.
            let angle = Double.pi / 3
            crankNode.eulerAngles = point(0, 0, angle)
            pistonNode.position = point(0, pinHeight(atAngle: angle), 0)
            intakeValve.position = point(-0.32, 1.24, 0)
            return built
        }

        // One full cycle is two turns of the crank: intake, compression, power, exhaust.
        let secondsPerTurn = 2.0
        crankNode.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: CGFloat.pi * 2, duration: secondsPerTurn)))
        let framesPerTurn = 60
        pistonNode.position = point(0, pinHeight(atAngle: 0), 0)
        let pistonFrames = (1...framesPerTurn).map { frame -> SCNAction in
            let angle = Double.pi * 2 * Double(frame) / Double(framesPerTurn)
            return .move(to: point(0, pinHeight(atAngle: angle), 0), duration: secondsPerTurn / Double(framesPerTurn))
        }
        pistonNode.runAction(.repeatForever(.sequence(pistonFrames)))

        let strokeSeconds = secondsPerTurn / 2
        func opening(startingAtStroke stroke: Double) -> SCNAction {
            .repeatForever(.sequence([
                .wait(duration: strokeSeconds * stroke),
                .moveBy(x: 0, y: -0.13, z: 0, duration: 0.12),
                .wait(duration: strokeSeconds - 0.24),
                .moveBy(x: 0, y: 0.13, z: 0, duration: 0.12),
                .wait(duration: strokeSeconds * (3 - stroke))
            ]))
        }
        intakeValve.runAction(opening(startingAtStroke: 0))
        exhaustValve.runAction(opening(startingAtStroke: 3))
        spark.runAction(.repeatForever(.sequence([
            .wait(duration: strokeSeconds * 2 - 0.05),
            .fadeIn(duration: 0.04),
            .fadeOut(duration: 0.22),
            .wait(duration: strokeSeconds * 2 - 0.21)
        ])))
        return built
    }

    // MARK: - DNA

    private static func dna() -> Built {
        let root = SCNNode()
        var built = Built(root: root)
        let pairCount = 22
        let rise = 0.24
        let radius = 0.85
        let twist = Double.pi * 2 / 10.5
        var random = SteadyRandom(seed: 11)
        var previousFirst: SCNVector3?
        var previousSecond: SCNVector3?
        var adenineThymineAnchor: SCNVector3?
        var guanineCytosineAnchor: SCNVector3?

        for index in 0..<pairCount {
            let angle = Double(index) * twist
            let y = (Double(index) - Double(pairCount - 1) / 2) * rise
            let first = point(radius * cos(angle), y, radius * sin(angle))
            // The second strand sits a little less than half a turn round, which makes the two grooves.
            let second = point(radius * cos(angle + 2.4), y, radius * sin(angle + 2.4))
            root.addChildNode(ball(at: first, radius: 0.1, color: blue))
            root.addChildNode(ball(at: second, radius: 0.1, color: teal))
            if let previousFirst { root.addChildNode(DrawingSceneBuilder.stick(from: previousFirst, to: first, radius: 0.06, color: blue)) }
            if let previousSecond { root.addChildNode(DrawingSceneBuilder.stick(from: previousSecond, to: second, radius: 0.06, color: teal)) }
            previousFirst = first
            previousSecond = second

            // Each rung is two bases meeting in the middle: A with T, G with C.
            let middle = point((Double(first.x) + Double(second.x)) / 2, y, (Double(first.z) + Double(second.z)) / 2)
            let isAdenineThymine = random.next() < 0.5
            let isFlipped = random.next() < 0.5
            let colors: (NSColor, NSColor) = isAdenineThymine ? (amber, red) : (green, white)
            root.addChildNode(DrawingSceneBuilder.stick(from: first, to: middle, radius: 0.045, color: isFlipped ? colors.1 : colors.0))
            root.addChildNode(DrawingSceneBuilder.stick(from: middle, to: second, radius: 0.045, color: isFlipped ? colors.0 : colors.1))
            if isAdenineThymine, adenineThymineAnchor == nil, index > 3 { adenineThymineAnchor = middle }
            if !isAdenineThymine, guanineCytosineAnchor == nil, index > 12 { guanineCytosineAnchor = middle }
        }
        let top = (Double(pairCount - 1) / 2) * rise
        built.anchors["sugar-phosphate backbone"] = PartAnchor(node: root, offset: point(1.35, top * 0.6, 0))
        built.anchors["base pairs"] = PartAnchor(node: root, offset: point(-1.45, 0, 0))
        built.anchors["adenine-thymine pair"] = PartAnchor(node: root, offset: point(1.5, Double(adenineThymineAnchor?.y ?? -1), 0.2))
        built.anchors["guanine-cytosine pair"] = PartAnchor(node: root, offset: point(-1.5, Double(guanineCytosineAnchor?.y ?? 1), 0.2))
        return built
    }

    // MARK: - Atom

    /// Carbon in the Bohr picture: six protons and six neutrons, two electrons then four.
    private static func atom(isMoving: Bool) -> Built {
        let root = SCNNode()
        var built = Built(root: root, isAnimated: isMoving)
        var random = SteadyRandom(seed: 3)
        for index in 0..<12 {
            let position = random.pointInBall(radius: 0.26)
            root.addChildNode(ball(at: position, radius: 0.13, color: index % 2 == 0 ? red : grey))
        }
        built.anchors["nucleus"] = PartAnchor(node: root, offset: point(0, 0.5, 0))
        built.anchors["protons"] = PartAnchor(node: root, offset: point(-0.62, -0.1, 0.2))
        built.anchors["neutrons"] = PartAnchor(node: root, offset: point(0.66, -0.12, 0.2))

        var firstElectron: SCNNode?
        for (shellIndex, shell) in [(radius: 1.1, electrons: 2, seconds: 5.0, tilt: 0.18), (radius: 1.95, electrons: 4, seconds: 9.0, tilt: -0.12)].enumerated() {
            let shellNode = SCNNode()
            shellNode.eulerAngles = point(shell.tilt, 0, shell.tilt * 0.6)
            shellNode.addChildNode(ring(radius: shell.radius, thickness: 0.012, color: grey))
            let spinner = SCNNode()
            for electronIndex in 0..<shell.electrons {
                let angle = Double.pi * 2 * Double(electronIndex) / Double(shell.electrons) + Double(shellIndex) * 0.6
                let electron = ball(at: point(shell.radius * cos(angle), 0, shell.radius * sin(angle)), radius: 0.085, color: blue)
                spinner.addChildNode(electron)
                if firstElectron == nil { firstElectron = electron }
            }
            if isMoving {
                spinner.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: shell.seconds)))
            }
            shellNode.addChildNode(spinner)
            root.addChildNode(shellNode)
        }
        if let firstElectron {
            built.anchors["electrons"] = PartAnchor(node: firstElectron, offset: point(0, 0.2, 0))
        }
        built.anchors["electron shells"] = PartAnchor(node: root, offset: point(0, 0.42, -2.0))
        return built
    }

    // MARK: - Solar system

    /// The sun and eight planets in order. Sizes and distances are squeezed to fit: at true scale
    /// the planets would be invisible specks.
    private static func solarSystem(isMoving: Bool) -> Built {
        let root = SCNNode()
        var built = Built(root: root, isAnimated: isMoving)
        let sun = ball(at: point(0, 0, 0), radius: 0.5, color: amber)
        sun.geometry?.materials = [DrawingSceneBuilder.material(amber, isFlat: true)]
        root.addChildNode(sun)
        built.anchors["sun"] = PartAnchor(node: root, offset: point(0, 0.62, 0))

        let planets: [(name: String, radius: Double, distance: Double, color: NSColor, seconds: Double)] = [
            ("mercury", 0.055, 0.9, grey, 6), ("venus", 0.1, 1.22, white, 10), ("earth", 0.105, 1.58, blue, 14),
            ("mars", 0.075, 1.95, red, 20), ("jupiter", 0.27, 2.6, amber, 34), ("saturn", 0.22, 3.3, white, 46),
            ("uranus", 0.16, 3.9, teal, 60), ("neptune", 0.155, 4.4, deepBlue, 76)
        ]
        for (index, planet) in planets.enumerated() {
            root.addChildNode(ring(radius: planet.distance, thickness: 0.006, color: NSColor(DS.Colors.borderStrong)))
            let orbit = SCNNode()
            orbit.eulerAngles = point(0, Double(index) * 0.83, 0)
            let body = ball(at: point(planet.distance, 0, 0), radius: planet.radius, color: planet.color)
            if planet.name == "saturn" {
                let rings = ring(radius: planet.radius * 1.75, thickness: 0.03, color: grey)
                rings.scale = point(1, 0.15, 1)
                rings.eulerAngles = point(0.4, 0, 0)
                body.addChildNode(rings)
            }
            orbit.addChildNode(body)
            if isMoving {
                orbit.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: planet.seconds)))
            }
            root.addChildNode(orbit)
            built.anchors[planet.name] = PartAnchor(node: body, offset: point(0, planet.radius + 0.1, 0))
        }
        return built
    }
}
