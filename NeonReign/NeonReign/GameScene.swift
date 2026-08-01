import SwiftUI
import SceneKit

/// Hosts the SceneKit view and owns the simulation.
struct GameSceneView: UIViewRepresentable {
    @ObservedObject var model: GameModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.buildScene()
        view.delegate = context.coordinator
        view.pointOfView = context.coordinator.cameraNode
        view.isPlaying = true
        view.rendersContinuously = true
        view.backgroundColor = .black
        view.antialiasingMode = model.quality.antialiasing
        view.preferredFramesPerSecond = 60
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        // Rebuild the post chain when the player changes quality tier.
        if context.coordinator.appliedQualityVersion != model.qualityVersion {
            context.coordinator.appliedQualityVersion = model.qualityVersion
            view.antialiasingMode = model.quality.antialiasing
            context.coordinator.rebuildPipeline(for: view)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {

        let model: GameModel
        init(model: GameModel) { self.model = model }

        // Scene graph
        var scene = SCNScene()
        weak var view: SCNView?
        let cameraNode = SCNNode()
        let sunNode = SCNNode()
        let ambientNode = SCNNode()
        /// Follows the player so weather particles stay local.
        let weatherAnchor = SCNNode()

        // Rendering
        var sky = SkyState()
        let weather = WeatherSystem()
        var pipeline: RenderPipeline?
        var appliedQualityVersion = 0

        // Player — car
        let carNode = SCNNode()
        var wheelNodes: [SCNNode] = []
        var steerPivots: [SCNNode] = []
        var headlightNodes: [SCNNode] = []
        var carX: Float = 0
        var carZ: Float = 0
        var carHeading: Float = 0
        var carSpeed: Float = 0

        // Player — on foot
        let pedNode = SCNNode()
        var footX: Float = 0
        var footZ: Float = 0
        var footHeading: Float = 0
        var walkPhase: Float = 0
        var mode: PlayerMode = .driving

        // World
        /// (centreX, centreZ, halfX, halfZ) of every solid building footprint.
        var buildings: [(Float, Float, Float, Float)] = []
        var streetLights: [SCNNode] = []
        var neonMaterials: [SCNMaterial] = []
        /// Facade materials whose window emission is raised after dark.
        var emissiveFacades: [SCNMaterial] = []

        // Actors
        var traffic: [AICar] = []
        var cops: [AICar] = []
        var missionTarget: AICar?
        var pedestrians: [Pedestrian] = []

        // Markers
        let waypointNode = SCNNode()
        let startMarkerNode = SCNNode()
        /// True while the player is on foot and close enough to get back in.
        var nearCar = false
        var exhaustNode: SCNNode?
        /// Volumetric-looking headlight beams, shown only at night.
        var headlightCones: [SCNNode] = []
        /// Emissive tail-light materials, brightened under braking.
        var brakeMaterials: [SCNMaterial] = []
        /// Seconds the police have had the player boxed in and stationary.
        var bustedTimer: Float = 0

        // Heat
        var heat = 0
        var heatCooldown: Float = 0
        var copSpawnTimer: Float = 0

        // Mission runtime.
        //
        // The authoritative objective index lives here, not on the model: the
        // model's copy is written asynchronously on the main queue for the HUD,
        // and reading it back on the render thread would race.
        var objectiveIdx = 0
        var objectiveTime: Double = 0
        var waitProgress: Double = 0
        /// Authoritative copy of the mission in progress.
        var runningMission: Mission?

        // Bookkeeping
        var lastFrameTime: TimeInterval = 0
        var hudAccum: Float = 0
        var totalTime: Double = 0

        func attach(to view: SCNView) {
            self.view = view
            appliedQualityVersion = model.qualityVersion
            rebuildPipeline(for: view)
        }

        func rebuildPipeline(for view: SCNView) {
            TextureFactory.flush()
            let p = RenderPipeline(quality: model.quality)
            pipeline = p
            view.technique = p.technique
            applyCameraGrade()
        }

        // MARK: Camera

        func applyCameraGrade() {
            guard let cam = cameraNode.camera else { return }
            let q = model.quality
            cam.wantsHDR = true
            cam.wantsExposureAdaptation = true
            cam.exposureAdaptationBrighteningSpeedFactor = 0.4
            cam.exposureAdaptationDarkeningSpeedFactor = 0.6
            cam.bloomIntensity = 0.35
            cam.bloomThreshold = 0.85
            cam.bloomBlurRadius = 12
            cam.motionBlurIntensity = q.wantsMotionBlur ? 0.55 : 0
            cam.screenSpaceAmbientOcclusionIntensity = q == .balanced ? 0.4 : 1.1
            cam.screenSpaceAmbientOcclusionRadius = 2.2
            cam.screenSpaceAmbientOcclusionBias = 0.02
            cam.contrast = 0.12
            cam.saturation = 1.18
            cam.zFar = 900
            cam.zNear = 0.1
            cam.fieldOfView = 62
        }

        // MARK: - Scene construction

        func buildScene() -> SCNScene {
            let scene = SCNScene()
            self.scene = scene

            scene.fogColor = UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1)
            scene.fogStartDistance = 120
            scene.fogEndDistance = 700
            scene.fogDensityExponent = 1.6

            // Camera
            let cam = SCNCamera()
            cameraNode.camera = cam
            cameraNode.position = SCNVector3(0, 9, -18)
            scene.rootNode.addChildNode(cameraNode)
            applyCameraGrade()

            // Sun + ambient
            let sun = SCNLight()
            sun.type = .directional
            sun.castsShadow = true
            sun.shadowMode = .deferred
            sun.shadowSampleCount = model.quality == .balanced ? 4 : 16
            sun.shadowRadius = model.quality == .balanced ? 3 : 6
            sun.shadowMapSize = CGSize(width: model.quality.shadowMapSize,
                                       height: model.quality.shadowMapSize)
            sun.shadowColor = UIColor(white: 0, alpha: 0.62)
            // Cascades concentrate resolution near the car, so contact shadows
            // under the wheels stay crisp while the block behind still casts.
            sun.shadowCascadeCount = model.quality.shadowCascades
            sun.shadowCascadeSplittingFactor = 0.35
            sun.shadowBias = 0.004
            sun.orthographicScale = 60
            sun.zFar = 460
            sunNode.light = sun
            scene.rootNode.addChildNode(sunNode)

            let amb = SCNLight()
            amb.type = .ambient
            ambientNode.light = amb
            scene.rootNode.addChildNode(ambientNode)

            applySky()

            // World geometry (SceneBuild.swift)
            buildGround()
            buildRoads()
            buildCity()
            buildLandmarks()

            // Actors
            buildPlayerCar()
            buildPlayerPed()
            spawnTraffic()
            spawnPedestrians()

            // Markers
            buildMarkers()

            // Weather rig follows the player.
            scene.rootNode.addChildNode(weatherAnchor)
            weather.attachRain(to: weatherAnchor)

            // Start the player at the lockup, in their car.
            let start = CityWorld.point("Your lockup")
            carX = start.x; carZ = start.y
            carNode.position = SCNVector3(carX, 0.42, carZ)
            mode = .driving

            return scene
        }

        /// Pushes the current time of day into the lights, sky and environment.
        func applySky() {
            sunNode.light?.color = sky.sunColor
            sunNode.light?.intensity = sky.sunIntensity
            ambientNode.light?.color = sky.ambientColor
            ambientNode.light?.intensity = sky.ambientIntensity

            // Sun direction from elevation + azimuth.
            sunNode.eulerAngles = SCNVector3(-sky.sunElevation - 0.15, sky.sunAzimuth, 0)

            let img = Sky.gradient(sky)
            scene.background.contents = img
            scene.lightingEnvironment.contents = img
            scene.lightingEnvironment.intensity = CGFloat(0.35 + sky.daylight * 1.5)

            let night = 1 - sky.daylight
            scene.fogColor = UIColor(red: CGFloat(0.06 + sky.daylight * 0.30),
                                     green: CGFloat(0.07 + sky.daylight * 0.34),
                                     blue: CGFloat(0.13 + sky.daylight * 0.38),
                                     alpha: 1)

            // Night switches the city's own lighting on.
            for m in neonMaterials {
                m.setValue(NSNumber(value: night), forKey: "nightMix")
            }
            for m in emissiveFacades {
                m.emission.intensity = CGFloat(night) * 0.85
            }
            for h in headlightNodes {
                h.light?.intensity = CGFloat(night) * 1400
            }
            // The visible beam cones only make sense after dark.
            for c in headlightCones {
                c.isHidden = night < 0.35
                c.opacity = CGFloat(night) * 0.09
            }
        }

        // MARK: - Per-frame

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = lastFrameTime == 0 ? 0 : Float(min(0.05, time - lastFrameTime))
            lastFrameTime = time
            guard dt > 0 else { return }
            totalTime += Double(dt)

            handleRequests()

            // Time of day: a full 24h cycle every 20 minutes of play.
            sky.hour += Double(dt) * (24.0 / (20 * 60))
            if sky.hour >= 24 { sky.hour -= 24 }
            applySky()

            weather.update(dt: dt, scene: scene, speed: mode == .driving ? carSpeed : 0)

            if mode == .driving {
                updateDriving(dt: dt)
            } else {
                updateOnFoot(dt: dt)
            }

            updateTraffic(dt: dt)
            updatePedestrians(dt: dt)
            updateHeat(dt: dt)
            updateCops(dt: dt)
            updateMissionTargetCar(dt: dt)
            updateMission(dt: dt)
            updateMarkers()
            streamLights()
            updateCamera(dt: dt)

            pipeline?.update(sky: sky,
                             wetness: weather.wetness,
                             rain: weather.rainAmount,
                             viewSize: view?.bounds.size ?? CGSize(width: 1, height: 1),
                             time: totalTime)

            hudAccum += dt
            if hudAccum >= 0.16 {
                hudAccum = 0
                pushHUD()
            }
        }

        /// Consumes the momentary actions the SwiftUI layer raised.
        private func handleRequests() {
            if model.enterExitRequested {
                model.enterExitRequested = false
                toggleVehicle()
            }
            if let id = model.startMissionRequested {
                model.startMissionRequested = nil
                if let m = Campaign.mission(id) { startMission(m) }
            }
            if model.abandonMissionRequested {
                model.abandonMissionRequested = false
                if let m = runningMission {
                    endMission(m, success: false, reason: "Abandoned")
                }
            }
        }

        // MARK: Camera follow

        private func updateCamera(dt: Float) {
            let px = mode == .driving ? carX : footX
            let pz = mode == .driving ? carZ : footZ
            let ph = mode == .driving ? carHeading : footHeading

            weatherAnchor.position = SCNVector3(px, 0, pz)
            // Keep the directional light's frustum centred on the player.
            sunNode.position = SCNVector3(px, 120, pz)

            let fx = sinf(ph), fz = cosf(ph)
            // Pull the camera back and lower it as speed rises.
            let speedT = mode == .driving ? min(1, abs(carSpeed) / 34) : 0
            let dist: Float = mode == .driving ? 13 + speedT * 3.5 : 6.5
            let height: Float = mode == .driving ? 5.4 - speedT * 0.9 : 3.4

            let desired = SCNVector3(px - fx * dist, height, pz - fz * dist)
            let lerp = min(1, dt * (mode == .driving ? 4.2 : 7.0))
            cameraNode.position = SCNVector3(
                cameraNode.position.x + (desired.x - cameraNode.position.x) * lerp,
                cameraNode.position.y + (desired.y - cameraNode.position.y) * lerp,
                cameraNode.position.z + (desired.z - cameraNode.position.z) * lerp)
            cameraNode.look(at: SCNVector3(px + fx * 7, mode == .driving ? 1.5 : 1.7, pz + fz * 7),
                            up: SCNVector3(0, 1, 0),
                            localFront: SCNVector3(0, 0, -1))

            // Speed widens the lens a touch — cheap, effective sense of pace.
            cameraNode.camera?.fieldOfView = CGFloat(62 + speedT * 12)
        }

        // MARK: Light streaming
        //
        // Only the nearest N street/neon lights are left enabled; the rest are
        // switched off. Without this the city would carry hundreds of live
        // lights and the shadow pass would collapse.

        private func streamLights() {
            let px = mode == .driving ? carX : footX
            let pz = mode == .driving ? carZ : footZ
            let budget = model.quality.liveLights
            let night = 1 - sky.daylight

            // World position, because sign lights are children of buildings.
            var scored: [(Float, SCNNode)] = streetLights.map { n in
                let w = n.worldPosition
                let dx = w.x - px, dz = w.z - pz
                return (dx * dx + dz * dz, n)
            }
            scored.sort { $0.0 < $1.0 }
            for (i, entry) in scored.enumerated() {
                let on = i < budget && night > 0.15
                entry.1.light?.intensity = on ? CGFloat(night) * 900 : 0
            }
        }

        // MARK: HUD

        private func pushHUD() {
            let px = mode == .driving ? carX : footX
            let pz = mode == .driving ? carZ : footZ
            let ph = mode == .driving ? carHeading : footHeading
            let kmh = mode == .driving ? Int(abs(carSpeed) * 7.2) : 0
            let area = CityWorld.name(x: px, z: pz)
            let clock = sky.clockText
            let wx = weather.condition.label
            let currentMode = mode
            let currentHeat = heat
            let canEnter = mode == .onFoot && nearCar

            // Waypoint, relative to where the player is facing.
            var angle: Float = 0
            var dist: Float = 0
            var has = false
            if let target = currentWaypoint() {
                let dx = target.x - px, dz = target.y - pz
                dist = sqrt(dx * dx + dz * dz)
                angle = atan2f(dx, dz) - ph
                has = true
            }

            let offered = offeredMissionID()
            let nearStart = offered.flatMap { id -> Bool? in
                guard let m = Campaign.mission(id) else { return false }
                let p = CityWorld.point(m.startPlace)
                return hypotf(p.x - px, p.y - pz) < 9
            } ?? false

            let objText = runningMission == nil ? "" : (currentObjective()?.hint ?? "")
            let hasLimit = currentObjective()?.timeLimit != nil
            let timer: Double? = hasLimit ? max(0, objectiveTime) : nil

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let m = self.model
                m.mode = currentMode
                m.speedKmh = kmh
                m.area = area
                m.clockText = clock
                m.weatherText = wx
                m.heat = currentHeat
                m.playerX = px
                m.playerZ = pz
                m.heading = ph
                m.canEnterCar = canEnter
                m.waypointAngle = angle
                m.waypointDistance = dist
                m.hasWaypoint = has
                m.offeredMissionID = offered
                m.nearMissionStart = nearStart
                if m.activeMission != nil {
                    m.objectiveText = objText
                    m.objectiveTimer = timer
                }
            }
        }
    }
}
