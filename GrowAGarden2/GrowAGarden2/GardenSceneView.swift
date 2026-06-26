import SwiftUI
import SceneKit
import UIKit

/// A 3D SceneKit garden: a grid of soil plots with crops that grow, an
/// orbitable camera, day/night lighting and weather particles. Tapping a plot
/// plants (via the SwiftUI sheet) or harvests.
struct GardenSceneView: UIViewRepresentable {
    @ObservedObject var game: GardenModel
    @Binding var plantingPlot: Int?

    private static let cols = 4
    private static let spacing: Float = 1.45

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.buildScene()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling2X
        view.backgroundColor = .black
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.scnView = view
        view.defaultCameraController.target = SCNVector3(0, 0, 0)
        context.coordinator.sync()
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync()
        if let h = game.lastHarvest {
            context.coordinator.playHarvestBurst(plotID: h.plotID, mutation: h.mutation)
            DispatchQueue.main.async { self.game.lastHarvest = nil }
        }
    }

    // Grid position for a plot index.
    static func position(for index: Int) -> SCNVector3 {
        let col = index % cols
        let row = index / cols
        let rows = (GardenModel.maxPlots + cols - 1) / cols
        let x = (Float(col) - Float(cols - 1) / 2) * spacing
        let z = (Float(row) - Float(rows - 1) / 2) * spacing
        return SCNVector3(x, 0, z)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var parent: GardenSceneView
        weak var scnView: SCNView?
        private let scene = SCNScene()
        private var plotNodes: [Int: SCNNode] = [:]
        private var sunNode: SCNNode?
        private var ambientNode: SCNNode?
        private var weatherNode: SCNNode?
        private var currentWeather: Weather?

        init(_ parent: GardenSceneView) { self.parent = parent }

        // MARK: Scene construction

        func buildScene() -> SCNScene {
            scene.background.contents = UIColor(red: 0.53, green: 0.77, blue: 0.92, alpha: 1)

            // Ground
            let ground = SCNFloor()
            ground.reflectivity = 0
            ground.firstMaterial?.diffuse.contents = UIColor(red: 0.38, green: 0.62, blue: 0.34, alpha: 1)
            let groundNode = SCNNode(geometry: ground)
            scene.rootNode.addChildNode(groundNode)

            // Plots (all built once; locked ones hidden)
            for i in 0..<GardenModel.maxPlots {
                let plot = makePlotNode(index: i)
                plotNodes[i] = plot
                scene.rootNode.addChildNode(plot)
            }

            // Camera
            let camera = SCNCamera()
            camera.fieldOfView = 55
            camera.zFar = 200
            let camNode = SCNNode()
            camNode.camera = camera
            camNode.position = SCNVector3(0, 9.5, 12)
            // Pitch down toward the garden centre; the orbit controller refines from here.
            camNode.eulerAngles = SCNVector3(-0.67, 0, 0)
            scene.rootNode.addChildNode(camNode)

            // Lights
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 400
            scene.rootNode.addChildNode(ambient)
            ambientNode = ambient

            let sun = SCNNode()
            sun.light = SCNLight()
            sun.light?.type = .directional
            sun.light?.intensity = 900
            sun.light?.castsShadow = true
            sun.light?.shadowMode = .deferred
            sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
            scene.rootNode.addChildNode(sun)
            sunNode = sun

            return scene
        }

        private func makePlotNode(index: Int) -> SCNNode {
            let soil = SCNBox(width: 1.2, height: 0.35, length: 1.2, chamferRadius: 0.06)
            soil.firstMaterial?.diffuse.contents = UIColor(red: 0.40, green: 0.27, blue: 0.17, alpha: 1)
            let node = SCNNode(geometry: soil)
            node.name = "plot_\(index)"
            node.position = GardenSceneView.position(for: index)
            node.position.y = 0.175

            // Decorative rim
            let rim = SCNBox(width: 1.32, height: 0.18, length: 1.32, chamferRadius: 0.04)
            rim.firstMaterial?.diffuse.contents = UIColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 1)
            let rimNode = SCNNode(geometry: rim)
            rimNode.position.y = -0.12
            node.addChildNode(rimNode)
            return node
        }

        private func makeCropNode(cropID: String, fertilized: Bool) -> SCNNode {
            let group = SCNNode()
            group.name = "crop"

            let stem = SCNCylinder(radius: 0.04, height: 0.34)
            stem.firstMaterial?.diffuse.contents = UIColor(red: 0.25, green: 0.55, blue: 0.25, alpha: 1)
            let stemNode = SCNNode(geometry: stem)
            stemNode.position.y = 0.17
            group.addChildNode(stemNode)

            let (r, g, b) = CropCatalog.rgb(cropID)
            let fruit = SCNSphere(radius: 0.2)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
            mat.roughness.contents = 0.4
            fruit.materials = [mat]
            let fruitNode = SCNNode(geometry: fruit)
            fruitNode.name = "fruit"
            fruitNode.position.y = 0.45
            group.addChildNode(fruitNode)

            // Two leaves
            for side in [-1, 1] {
                let leaf = SCNCone(topRadius: 0, bottomRadius: 0.07, height: 0.22)
                leaf.firstMaterial?.diffuse.contents = UIColor(red: 0.22, green: 0.5, blue: 0.22, alpha: 1)
                let leafNode = SCNNode(geometry: leaf)
                leafNode.position = SCNVector3(Float(side) * 0.12, 0.25, 0)
                leafNode.eulerAngles = SCNVector3(0, 0, Float(side) * Float.pi / 3.2)
                group.addChildNode(leafNode)
            }

            if fertilized {
                // Subtle golden ring marker on fertilized plots.
                let ring = SCNTorus(ringRadius: 0.45, pipeRadius: 0.03)
                ring.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
                ring.firstMaterial?.emission.contents = UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
                let ringNode = SCNNode(geometry: ring)
                ringNode.name = "fert"
                ringNode.position.y = 0.02
                group.addChildNode(ringNode)
            }
            return group
        }

        // MARK: Sync model -> scene

        func sync() {
            let game = parent.game
            for (i, node) in plotNodes {
                let unlocked = i < game.unlockedPlots
                node.isHidden = !unlocked
                guard unlocked, i < game.plots.count else { continue }
                let plot = game.plots[i]
                updateCrop(on: node, plot: plot, game: game)
            }
            updateEnvironment()
        }

        private func updateCrop(on plotNode: SCNNode, plot: GardenModel.Plot, game: GardenModel) {
            let existing = plotNode.childNode(withName: "crop", recursively: false)

            guard let cropID = plot.cropID else {
                existing?.removeFromParentNode()
                return
            }

            let crop: SCNNode
            if let existing = existing {
                crop = existing
            } else {
                crop = makeCropNode(cropID: cropID, fertilized: plot.fertilized)
                crop.position.y = 0.18
                plotNode.addChildNode(crop)
            }

            let progress = Float(game.progress(of: plot))
            let s = 0.3 + 0.7 * progress
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.9
            crop.scale = SCNVector3(s, s, s)
            SCNTransaction.commit()

            let ready = game.isReady(plot)
            if let fruit = crop.childNode(withName: "fruit", recursively: true) {
                fruit.geometry?.firstMaterial?.emission.contents =
                    ready ? UIColor(white: 0.6, alpha: 1) : UIColor.black
            }
            // Bobbing when ready.
            if ready, crop.action(forKey: "bob") == nil {
                let up = SCNAction.moveBy(x: 0, y: 0.12, z: 0, duration: 0.6)
                up.timingMode = .easeInEaseOut
                crop.runAction(.repeatForever(.sequence([up, up.reversed()])), forKey: "bob")
            } else if !ready, crop.action(forKey: "bob") != nil {
                crop.removeAction(forKey: "bob")
                crop.position.y = 0.18
            }
        }

        // MARK: Environment (day/night + weather)

        private func updateEnvironment() {
            let hour = Calendar.current.component(.hour, from: Date())
            // 0 at midnight, peaks at noon.
            let day = max(0, cos((Double(hour) - 12) / 12 * .pi))
            let bright = 0.25 + 0.75 * day

            ambientNode?.light?.intensity = 200 + 400 * day
            sunNode?.light?.intensity = 300 + 800 * day
            sunNode?.light?.color = UIColor(red: 1, green: 0.95 - 0.1 * (1 - day), blue: 0.8 + 0.2 * day, alpha: 1)

            let sky = UIColor(red: 0.20 + 0.33 * bright,
                              green: 0.28 + 0.49 * bright,
                              blue: 0.45 + 0.47 * bright, alpha: 1)
            scene.background.contents = sky

            let weather = Weather.current
            if weather != currentWeather {
                currentWeather = weather
                applyWeather(weather)
            }
        }

        private func applyWeather(_ weather: Weather) {
            weatherNode?.removeFromParentNode()
            weatherNode = nil
            guard weather == .rainy || weather == .snowy else { return }

            let node = SCNNode()
            node.position = SCNVector3(0, 10, 0)
            let ps = SCNParticleSystem()
            ps.emitterShape = SCNBox(width: 16, height: 0.1, length: 16, chamferRadius: 0)
            ps.birthLocation = .volume
            ps.emittingDirection = SCNVector3(0, -1, 0)
            ps.spreadingAngle = 4
            ps.particleLifeSpan = 3
            ps.acceleration = SCNVector3(0, -3, 0)

            if weather == .rainy {
                ps.birthRate = 600
                ps.particleVelocity = 11
                ps.particleSize = 0.03
                ps.particleColor = UIColor(red: 0.6, green: 0.75, blue: 1, alpha: 0.8)
            } else {
                ps.birthRate = 200
                ps.particleVelocity = 2.2
                ps.particleSize = 0.06
                ps.particleColor = UIColor(white: 1, alpha: 0.9)
            }
            node.addParticleSystem(ps)
            scene.rootNode.addChildNode(node)
            weatherNode = node
        }

        // MARK: Effects

        func playHarvestBurst(plotID: Int, mutation: Mutation) {
            guard let plot = plotNodes[plotID] else { return }
            let (r, g, b): (CGFloat, CGFloat, CGFloat)
            switch mutation {
            case .gold:    (r, g, b) = (1, 0.85, 0.2)
            case .rainbow: (r, g, b) = (1, 0.4, 0.8)
            case .frozen:  (r, g, b) = (0.6, 0.9, 1)
            case .wet:     (r, g, b) = (0.4, 0.6, 1)
            case .normal:  (r, g, b) = (1, 1, 0.6)
            }
            let burst = SCNNode(geometry: SCNSphere(radius: 0.2))
            burst.geometry?.firstMaterial?.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
            burst.geometry?.firstMaterial?.emission.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
            burst.position = plot.position
            burst.position.y = 0.6
            scene.rootNode.addChildNode(burst)
            let grow = SCNAction.scale(to: mutation == .normal ? 2 : 3.5, duration: 0.45)
            let fade = SCNAction.fadeOut(duration: 0.45)
            burst.runAction(.sequence([.group([grow, fade]), .removeFromParentNode()]))
        }

        // MARK: Tap

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            let p = gr.location(in: view)
            let hits = view.hitTest(p, options: [.boundingBoxOnly: true])
            guard let node = hits.first?.node, let plotID = plotID(of: node) else { return }
            guard plotID < parent.game.unlockedPlots else { return }
            let plot = parent.game.plots[plotID]
            if plot.cropID == nil {
                parent.plantingPlot = plotID
            } else if parent.game.isReady(plot) {
                _ = parent.game.harvest(plotID: plotID)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        private func plotID(of node: SCNNode) -> Int? {
            var current: SCNNode? = node
            while let n = current {
                if let name = n.name, name.hasPrefix("plot_") {
                    return Int(name.dropFirst("plot_".count))
                }
                current = n.parent
            }
            return nil
        }
    }
}
