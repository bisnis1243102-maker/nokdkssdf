import SwiftUI
import SceneKit
import UIKit

// A small SceneKit stage for the menus, so the bike you buy in the garage and
// the riders on the podium are the same models that race — not flat stand-ins
// that stop matching the moment the art changes.

struct ShowcaseView: UIViewRepresentable {

    enum Content: Equatable {
        /// The bike, with a rider aboard, on a slow turntable.
        case bike(bikeId: String, tint: String, withRider: Bool)
        /// A single rider stood up, for the rider screen.
        case rider(tint: String)
        /// Podium: jersey colours in finishing order, 1st … 3rd.
        case podium(tints: [String], playerPlace: Int)
    }

    let content: Content
    var spins = true

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = Showcase.scene(for: content, spins: spins)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling2X
        view.rendersContinuously = spins
        view.isPlaying = spins
        view.preferredFramesPerSecond = 60
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Rebuilding on every SwiftUI pass would restart the turntable, so the
        // scene is only replaced when the thing being shown actually changes.
        if context.coordinator.shown != content {
            context.coordinator.shown = content
            uiView.scene = Showcase.scene(for: content, spins: spins)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(shown: content) }

    final class Coordinator {
        var shown: Content
        init(shown: Content) { self.shown = shown }
    }
}

enum Showcase {

    static func scene(for content: ShowcaseView.Content, spins: Bool) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let stage = SCNNode()
        scene.rootNode.addChildNode(stage)

        var framing: (distance: Float, height: Float, fov: CGFloat)

        switch content {
        case let .bike(bikeId, tint, withRider):
            let spec = BikeSpec.byId(bikeId)
            stage.addChildNode(bikeNode(spec: spec,
                                        tint: UIColor(Color(hex: tint)),
                                        withRider: withRider))
            framing = (3.5, 0.15, 38)
        case let .rider(tint):
            let rider = Art.part("rider_stand") {
                SCNNode(geometry: SCNCapsule(capRadius: 0.22, height: 1.7))
            }
            Art.tint(rider, plastics: UIColor(Color(hex: tint)))
            rider.position = SCNVector3(0, -0.9, 0)   // stand them on the origin
            stage.addChildNode(rider)
            framing = (3.9, 0.05, 34)
        case let .podium(tints, playerPlace):
            stage.addChildNode(podiumNode(tints: tints, playerPlace: playerPlace))
            framing = (5.6, 0.1, 36)
        }

        addGround(to: scene)
        addLighting(to: scene)

        let camera = SCNCamera()
        camera.fieldOfView = framing.fov
        camera.zNear = 0.1
        camera.zFar = 60
        camera.wantsHDR = true
        camera.bloomIntensity = 0.15
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, framing.height + 0.35, framing.distance)
        cameraNode.eulerAngles = SCNVector3(-0.10, 0, 0)
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.name = "root"

        if spins {
            // A slow turntable reads as "this is a real object" far better
            // than a static three-quarter shot.
            let spin = SCNAction.repeatForever(
                .rotateBy(x: 0, y: .pi * 2, z: 0, duration: 18))
            stage.runAction(spin)
        } else {
            stage.eulerAngles.y = -0.5
        }
        return scene
    }

    // MARK: Bike

    static func bikeNode(spec: BikeSpec, tint: UIColor, withRider: Bool) -> SCNNode {
        let node = SCNNode()

        let frame = Art.part("bike_frame") {
            SCNNode(geometry: SCNBox(width: 1.2, height: 0.34, length: 0.28, chamferRadius: 0.05))
        }
        node.addChildNode(frame)

        let fork = Art.part("bike_fork") {
            SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.62))
        }
        fork.position = Rig.frontAxle
        node.addChildNode(fork)

        let swingarm = Art.part("bike_swingarm") {
            SCNNode(geometry: SCNBox(width: 0.58, height: 0.07, length: 0.2, chamferRadius: 0.02))
        }
        swingarm.position = Rig.swingPivot
        node.addChildNode(swingarm)

        for axle in [Rig.frontAxle, Rig.rearAxle] {
            let wheel = Art.part("bike_wheel") {
                let n = SCNNode(geometry: SCNCylinder(radius: 0.33, height: 0.11))
                n.eulerAngles.x = .pi / 2
                return n
            }
            wheel.position = axle
            node.addChildNode(wheel)
        }

        if withRider {
            let rider = Art.part("rider") {
                SCNNode(geometry: SCNCapsule(capRadius: 0.16, height: 1.1))
            }
            node.addChildNode(rider)
        }

        Art.tint(node, plastics: tint)
        // Sit the wheels on the floor: the model's origin is the centre of
        // mass, which is one wheel radius above the axles.
        node.position = SCNVector3(0, -(Rig.axleY - 0.33) - 0.66, 0)
        node.eulerAngles.y = -0.35
        return node
    }

    // MARK: Podium

    static func podiumNode(tints: [String], playerPlace: Int) -> SCNNode {
        let node = SCNNode()
        // Blocks in the order they stand: 2nd, 1st, 3rd.
        let layout: [(place: Int, x: Float, height: Float)] = [
            (2, -1.15, 0.55), (1, 0, 0.85), (3, 1.15, 0.38)
        ]

        for slot in layout {
            let block = SCNNode(geometry: SCNBox(width: 1.0,
                                                 height: CGFloat(slot.height),
                                                 length: 1.0,
                                                 chamferRadius: 0.02))
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(white: 0.82, alpha: 1)
            mat.roughness.contents = 0.6
            mat.lightingModel = .physicallyBased
            block.geometry?.materials = [mat]
            block.position = SCNVector3(slot.x, slot.height / 2, 0)
            node.addChildNode(block)

            let label = SCNNode(geometry: numberPlate(slot.place))
            label.position = SCNVector3(slot.x, slot.height * 0.55, 0.51)
            node.addChildNode(label)

            guard slot.place - 1 < tints.count else { continue }
            let rider = Art.part("rider_stand") {
                SCNNode(geometry: SCNCapsule(capRadius: 0.22, height: 1.7))
            }
            Art.tint(rider, plastics: UIColor(Color(hex: tints[slot.place - 1])))
            rider.position = SCNVector3(slot.x, slot.height, 0)
            rider.eulerAngles.y = slot.place == playerPlace ? -0.15 : Float.random(in: -0.3...0.3)
            node.addChildNode(rider)
        }

        node.position = SCNVector3(0, -0.75, 0)
        return node
    }

    private static func numberPlate(_ place: Int) -> SCNGeometry {
        let text = SCNText(string: "\(place)", extrusionDepth: 0.02)
        text.font = UIFont.systemFont(ofSize: 0.4, weight: .black)
        text.flatness = 0.05
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(white: 0.35, alpha: 1)
        text.materials = [mat]
        return text
    }

    // MARK: Stage dressing

    private static func addGround(to scene: SCNScene) {
        // A shadow catcher rather than a visible floor, so the model appears
        // to sit on the menu itself.
        let floor = SCNFloor()
        floor.reflectivity = 0.04
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.writesToDepthBuffer = false
        mat.colorBufferWriteMask = []
        floor.materials = [mat]
        let node = SCNNode(geometry: floor)
        node.position = SCNVector3(0, -0.9, 0)
        node.castsShadow = false
        scene.rootNode.addChildNode(node)
    }

    private static func addLighting(to scene: SCNScene) {
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1150
        key.light?.color = UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 1)
        key.light?.castsShadow = true
        key.light?.shadowMode = .deferred
        key.light?.shadowRadius = 6
        key.light?.shadowColor = UIColor(white: 0, alpha: 0.35)
        key.light?.orthographicScale = 3
        key.eulerAngles = SCNVector3(-0.9, 0.7, 0)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 420
        rim.light?.color = UIColor(red: 0.6, green: 0.78, blue: 1, alpha: 1)
        rim.eulerAngles = SCNVector3(-0.3, -2.4, 0)
        scene.rootNode.addChildNode(rim)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 380
        ambient.light?.color = UIColor(red: 0.72, green: 0.8, blue: 0.92, alpha: 1)
        scene.rootNode.addChildNode(ambient)
    }
}
