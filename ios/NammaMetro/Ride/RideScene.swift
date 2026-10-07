import Combine
import CoreLocation
import SceneKit
import simd
import UIKit

enum RideCamera: String, CaseIterable, Identifiable {
    case follow = "Follow", front = "Front", trackside = "Trackside"
    var id: String { rawValue }
}

/// The map camera the 3D view takes over from: the scene's camera holds the same
/// pose until `startEntry`, then glides down to the ride camera.
struct RideEntry: Equatable {
    var center: CLLocationCoordinate2D
    var distance: Double   // metres from the camera to the point it looks at
    var heading: Double    // degrees clockwise from north
    var pitch: Double      // degrees from straight down

    static func == (a: RideEntry, b: RideEntry) -> Bool {
        a.center.latitude == b.center.latitude && a.center.longitude == b.center.longitude
            && a.distance == b.distance && a.heading == b.heading && a.pitch == b.pitch
    }

    /// Camera position and look-at point in scene space.
    var pose: (eye: SIMD3<Double>, target: SIMD3<Double>) {
        let h = heading * .pi / 180, p = pitch * .pi / 180
        let c = MetroWorld.project(center)
        let look = SIMD3(c.x, 0, c.y)
        let ahead = SIMD3(sin(h), 0, -cos(h))
        return (look + SIMD3(0, distance * cos(p), 0) - ahead * distance * sin(p), look)
    }
}

struct RideHUD: Equatable {
    var lineName = ""
    var lineID = ""
    var destination = ""
    var headline = ""
    var detail = ""
    var underground = false
    var terminated = false
}

/// Owns the 3D scene for riding along with one train. SceneKit calls
/// `renderer(_:updateAtTime:)` on its render thread; everything shared with the
/// main thread goes through `shared` under `lock`.
final class RideSceneController: NSObject, ObservableObject, SCNSceneRendererDelegate {
    @Published private(set) var hud = RideHUD()
    @Published var camera: RideCamera = .follow {
        didSet { withShared { $0.mode = camera; $0.modeChanged = true } }
    }

    let scene = SCNScene()
    let cameraNode = SCNNode()
    let feed: TrainFeed
    /// Called once on the main thread when nearby ground and track have loaded.
    var onReady: (() -> Void)?
    private var announcedReady = false

    private let materials = MetroMaterials()
    private var factories: [String: TrainFactory] = [:]
    private var sceneries: [LineScenery] = []
    private let ground = GroundTiles()
    private let sceneryRoot = SCNNode()
    private let trainRoot = SCNNode()
    private let sunNode = SCNNode()
    private let headlamp = SCNNode()
    private let moonNode = SCNNode()
    private let ambientNode = SCNNode()

    // Main thread only.
    private var loadedChunks: [String: SCNNode] = [:]
    private var buildingChunks: Set<String> = []
    private let buildQueue = DispatchQueue(label: "ride.scenery", qos: .userInitiated)
    private var timer: Timer?
    private var lastSkyUpdate = Date.distantPast
    private var xray = false
    private var roofXray = false

    private struct Shared {
        var followedID: String
        var mode: RideCamera = .follow
        var modeChanged = false
        var yawOffset: Float = 0.75
        var pitch: Float = 0.30
        var distance: Float = 70
        var followed: Train?
        var terminated = false
        var focus = SIMD3<Double>(0, 0, 0)
        var underground = false
        var cameraAboveStationRoof = false
        /// While set, the camera holds this map pose; `entryGo` starts the glide.
        var entry: RideEntry?
        var entryGo = false
    }
    private let lock = NSLock()
    private var shared: Shared

    private func withShared<T>(_ body: (inout Shared) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(&shared)
    }

    // Render thread only.
    private var trainNodes: [String: [SCNNode]] = [:]
    private var lastTime: TimeInterval = 0
    private var smoothedYaw: Float?
    private var eye = SIMD3<Double>(0, 0, 0)
    private var target = SIMD3<Double>(0, 0, 0)
    private var transition: (eye: SIMD3<Double>, target: SIMD3<Double>, t: Double, duration: Double)?
    private var tracksideAnchor: Double?
    private var boardCache: [String: SCNNode] = [:]

    init(feed: TrainFeed, trainID: String, entry: RideEntry? = nil) {
        self.feed = feed
        shared = Shared(followedID: trainID, entry: entry)
        super.init()
        for line in MetroNetwork.lines {
            factories[line.id] = TrainFactory(lineColor: Livery.color(for: line.id), library: materials)
            sceneries.append(LineScenery(line: line, materials: materials))
        }
        shared.followed = feed.trains(at: Date()).first { $0.id == trainID }
        buildScene()
    }

    deinit { timer?.invalidate() }

    // MARK: Setup

    private func buildScene() {
        let cam = SCNCamera()
        cam.fieldOfView = 55
        cam.zNear = 0.4
        cam.zFar = 7000
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = -0.2
        cam.bloomIntensity = 0.5
        cam.bloomThreshold = 0.95
        cam.bloomBlurRadius = 10
        cam.screenSpaceAmbientOcclusionIntensity = 0.6
        cam.screenSpaceAmbientOcclusionRadius = 1.6
        cam.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        cam.screenSpaceAmbientOcclusionDepthThreshold = 0.6
        cam.vignettingIntensity = 0.25
        cam.vignettingPower = 1.2
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowCascadeCount = 3
        sun.maximumShadowDistance = 400
        sun.shadowCascadeSplittingFactor = 0.25
        sun.automaticallyAdjustsShadowProjection = true
        sun.shadowSampleCount = 8
        sun.shadowRadius = 2.5
        sun.shadowColor = UIColor(white: 0, alpha: 0.6)
        sun.shadowMode = .deferred
        sunNode.light = sun
        scene.rootNode.addChildNode(sunNode)

        let spot = SCNLight()
        spot.type = .spot
        spot.color = UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1)
        spot.spotInnerAngle = 18
        spot.spotOuterAngle = 46
        spot.attenuationStartDistance = 5
        spot.attenuationEndDistance = 160
        spot.intensity = 0
        headlamp.light = spot
        scene.rootNode.addChildNode(headlamp)

        let moon = SCNLight()
        moon.type = .directional
        moon.color = UIColor(red: 0.62, green: 0.72, blue: 1.0, alpha: 1)
        moonNode.light = moon
        moonNode.simdOrientation = Self.lookRotation(forward: simd_normalize(SIMD3<Float>(0.4, -0.8, 0.45)))
        scene.rootNode.addChildNode(moonNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.85, green: 0.72, blue: 0.62, alpha: 1)   // sodium-lit city glow
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        scene.rootNode.addChildNode(ground.root)
        scene.rootNode.addChildNode(sceneryRoot)
        scene.rootNode.addChildNode(trainRoot)
        scene.fogStartDistance = 1400
        scene.fogEndDistance = 5200
        scene.fogDensityExponent = 1.4
        updateSky(force: true)

        if let t = shared.followed, let track = MetroNetwork.tracks[t.lineID] {
            let p = track.point(at: t.distance)
            let focus = SIMD2(p.x, p.y)
            streamScenery(focus: focus, initial: true)
            ground.update(focus: focus)
        }
        refreshHUD()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// Main-thread housekeeping: streaming, lighting, HUD.
    private func tick() {
        let s = withShared { $0 }
        let focus = SIMD2(s.focus.x, s.focus.z)
        streamScenery(focus: focus, initial: false)
        ground.update(focus: focus)
        updateSky(force: false)
        if !announcedReady, ground.loadedTileCount >= 6, loadedChunks.count >= 3 {
            announcedReady = true
            onReady?()
        }

        let sky = SkyState(date: Self.skyDate())
        let wantXray = s.underground
        if wantXray != xray {
            xray = wantXray
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.8
            materials.tunnel.transparency = wantXray ? 0.16 : 1
            SCNTransaction.commit()
        }
        ground.setAppearance(brightness: CGFloat(1 - 0.6 * sky.night), opacity: xray ? 0.14 : 1)
        if s.cameraAboveStationRoof != roofXray {
            roofXray = s.cameraAboveStationRoof
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.6
            for chunk in loadedChunks.values {
                for roof in chunk.childNodes(passingTest: { n, _ in n.name == "stationRoof" }) {
                    roof.opacity = roofXray ? 0.15 : 1
                }
            }
            SCNTransaction.commit()
        }
        refreshHUD()
    }

    private func updateSky(force: Bool) {
        guard force || Date().timeIntervalSince(lastSkyUpdate) > 60 else { return }
        lastSkyUpdate = Date()
        let sky = SkyState(date: Self.skyDate())
        let image = sky.skyImage()
        scene.background.contents = image
        scene.lightingEnvironment.contents = image
        scene.lightingEnvironment.intensity = CGFloat(1.4 - 1.15 * sky.night)
        scene.fogColor = sky.horizonColor

        let up = max(Float(sin(sky.sunElevation)), 0)
        sunNode.light?.intensity = CGFloat(2600 * min(up / 0.25, 1))
        sunNode.light?.color = sky.sunUIColor
        sunNode.light?.castsShadow = up > 0.02
        sunNode.simdOrientation = Self.lookRotation(forward: -sky.sunDirection)
        headlamp.light?.intensity = CGFloat(3200 * sky.night)
        moonNode.light?.intensity = CGFloat(420 * sky.night)
        ambientNode.light?.intensity = CGFloat(260 * sky.night)
        // Let the eye adapt a little after dark.
        cameraNode.camera?.exposureOffset = CGFloat(-0.2 + 1.1 * sky.night)
        materials.setNight(CGFloat(sky.night))
    }

    /// Loads track chunks within reach of the focus on a background queue and drops distant ones.
    private func streamScenery(focus: SIMD2<Double>, initial: Bool) {
        let near = 2700.0, far = 3600.0
        var wanted: [(key: String, scenery: LineScenery, chunk: Int, distance: Double)] = []
        for scenery in sceneries {
            for c in 0..<scenery.chunkCount {
                let key = "\(scenery.line.id)-\(c)"
                let d = simd_distance(scenery.chunkCenter(c), focus)
                if d < near, loadedChunks[key] == nil, !buildingChunks.contains(key) {
                    wanted.append((key, scenery, c, d))
                } else if d > far, let node = loadedChunks[key] {
                    node.removeFromParentNode()
                    loadedChunks[key] = nil
                }
            }
        }
        for w in wanted.sorted(by: { $0.distance < $1.distance }) {
            buildingChunks.insert(w.key)
            buildQueue.async { [weak self] in
                let node = w.scenery.makeChunk(w.chunk)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.buildingChunks.remove(w.key)
                    if self.roofXray {
                        node.childNodes(passingTest: { n, _ in n.name == "stationRoof" }).forEach { $0.opacity = 0.15 }
                    }
                    self.sceneryRoot.addChildNode(node)
                    self.loadedChunks[w.key] = node
                }
            }
        }
    }

    // MARK: HUD

    private func refreshHUD() {
        let s = withShared { $0 }
        guard let t = s.followed, let line = MetroNetwork.line(t.lineID) else { return }
        var h = RideHUD()
        h.lineName = line.name
        h.lineID = line.id
        h.destination = t.destinationName
        h.underground = s.underground
        h.terminated = s.terminated
        let next = MetroNetwork.stations[t.nextStationID]?.name ?? ""
        if s.terminated {
            h.headline = "Arrived at \(t.destinationName)"
            h.detail = "This trip has ended"
        } else if t.status == .atStation {
            h.headline = next
            h.detail = "At platform · towards \(t.destinationName)"
        } else {
            h.headline = next
            let arrive = feed.stops(ofTrip: t.id).first { $0.stationID == t.nextStationID }?.arrive
            let seconds = arrive.map { $0.timeIntervalSinceNow } ?? 0
            let eta = seconds < 45 ? "arriving" : "in \(Int((seconds / 60).rounded())) min"
            h.detail = "Next station, \(eta) · \(Int((t.speed * 3.6).rounded())) km/h"
        }
        if h != hud { hud = h }
    }

    /// Jumps to the closest train running the same way on the same line.
    func rideNextTrain() {
        let s = withShared { $0 }
        guard let last = s.followed else { return }
        let candidates = feed.trains(at: Date()).filter {
            $0.lineID == last.lineID && $0.direction == last.direction && $0.id != last.id
        }
        guard let next = candidates.min(by: { abs($0.distance - last.distance) < abs($1.distance - last.distance) })
        else { return }
        withShared {
            $0.followedID = next.id
            $0.followed = next
            $0.terminated = false
            $0.modeChanged = true
        }
        refreshHUD()
    }

    /// Starts the glide from `entry` (the map's actual final camera) down to the train.
    func startEntry(_ entry: RideEntry) {
        withShared {
            $0.entry = entry
            $0.entryGo = true
        }
    }

    // MARK: Gestures (main thread)

    func orbit(by translation: CGPoint) {
        withShared {
            $0.yawOffset -= Float(translation.x) * 0.006
            $0.pitch = min(max($0.pitch + Float(translation.y) * 0.004, 0.04), 1.35)
        }
    }

    func zoom(by scale: CGFloat) {
        withShared { $0.distance = min(max($0.distance / Float(scale), 16), 900) }
    }

    func resetView() {
        withShared {
            $0.yawOffset = 0.75
            $0.pitch = 0.30
            $0.distance = 70
        }
    }

    // MARK: Render loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(time - lastTime, 0.1)
        lastTime = time
        let now = Date()
        var s = withShared { $0 }
        let trains = feed.trains(at: now)

        var followed = trains.first { $0.id == s.followedID }
        let terminated = followed == nil
        if followed == nil { followed = s.followed }
        guard let f = followed, let track = MetroNetwork.tracks[f.lineID] else { return }

        let fp = track.point(at: f.distance)
        let focus2 = SIMD2(fp.x, fp.y)
        var placed = Set<String>()
        var visible = trains.filter { simd_distance($0.coordinateIn(MetroNetwork.tracks[$0.lineID]), focus2) < 3200 }
        if terminated { visible.append(f) }
        for t in visible {
            guard let tr = MetroNetwork.tracks[t.lineID] else { continue }
            let cars = trainNodes[t.id] ?? makeTrain(t)
            place(cars, train: t, track: tr)
            placed.insert(t.id)
        }
        for (id, cars) in trainNodes where !placed.contains(id) {
            cars.forEach { $0.removeFromParentNode() }
            trainNodes[id] = nil
        }

        // Followed train frame.
        let sign: Double = f.direction == .forward ? 1 : -1
        let lateral = TrackLayout.lateral(for: f.direction)
        let center = track.railPoint(at: f.distance, lateral: lateral)
        let ahead = track.railPoint(at: f.distance + sign * 10, lateral: lateral)
        let forward = simd_normalize(ahead - track.railPoint(at: f.distance - sign * 10, lateral: lateral))
        let deck = track.deckHeight(at: f.distance)
        let half = Double(CarSpec.trainLength) / 2
        let head = track.railPoint(at: f.distance + sign * (half + 0.6), lateral: lateral)

        var holdingEntry = false
        if let e = s.entry {
            // Start exactly where the map camera is; the initial mode isn't a switch to animate.
            let pose = e.pose
            if s.entryGo {
                transition = (pose.eye, pose.target, 0, 2.4)
                withShared { $0.entry = nil; $0.entryGo = false; $0.modeChanged = false }
            } else {
                eye = pose.eye
                target = pose.target
                transition = nil
                holdingEntry = true
                withShared { $0.modeChanged = false }
            }
            s.modeChanged = false
        }
        if s.modeChanged {
            transition = (eye, target, 0, 1.1)
            tracksideAnchor = nil
            withShared { $0.modeChanged = false }
            s.modeChanged = false
        }

        var desiredEye: SIMD3<Double>, desiredTarget: SIMD3<Double>
        switch s.mode {
        case .follow:
            let headingYaw = Float(atan2(forward.x, forward.z))
            smoothedYaw = smoothedYaw.map { Self.angleLerp($0, headingYaw, Float(1 - exp(-dt * 1.6))) } ?? headingYaw
            let az = Double(smoothedYaw! + .pi + s.yawOffset)
            let pitch = Double(s.pitch), dist = Double(s.distance)
            desiredTarget = center + forward * 16 + SIMD3(0, 2.2, 0)
            desiredEye = desiredTarget + SIMD3(sin(az) * cos(pitch), sin(pitch), cos(az) * cos(pitch)) * dist
            cameraNode.camera?.zNear = 0.5
        case .front:
            desiredEye = head + SIMD3(0, 2.9, 0) + forward * 0.4
            desiredTarget = track.railPoint(at: f.distance + sign * (half + 90), lateral: lateral) + SIMD3(0, 1.4, 0)
            cameraNode.camera?.zNear = 0.1
        case .trackside:
            // Re-place the camera ahead once the train has passed it (or it's too far ahead).
            if tracksideAnchor.map({ sign * (f.distance - $0) > 75 || sign * ($0 - f.distance) > 700 }) ?? true {
                tracksideAnchor = f.distance + sign * 340
            }
            let a = tracksideAnchor!
            let side = lateral < 0 ? -1.0 : 1.0
            let underground = track.deckHeight(at: a) < -2
            let offset = underground ? lateral + side * 1.9 : lateral + side * 14
            let base = track.railPoint(at: a, lateral: offset)
            desiredEye = base + SIMD3(0, underground ? 2.6 : 4.0, 0)
            desiredTarget = center + SIMD3(0, 1.8, 0)
            cameraNode.camera?.zNear = 0.3
        }

        if holdingEntry {
            // eye/target already hold the map pose.
        } else if var tr = transition {
            tr.t += dt / tr.duration
            let k = tr.t >= 1 ? 1 : tr.t * tr.t * (3 - 2 * tr.t)
            eye = simd_mix(tr.eye, desiredEye, SIMD3(repeating: k))
            target = simd_mix(tr.target, desiredTarget, SIMD3(repeating: k))
            transition = tr.t >= 1 ? nil : tr
        } else {
            eye = desiredEye
            target = desiredTarget
        }
        cameraNode.simdPosition = SIMD3<Float>(eye)
        cameraNode.simdOrientation = Self.lookRotation(forward: SIMD3<Float>(simd_normalize(target - eye)))

        headlamp.simdPosition = SIMD3<Float>(head + SIMD3(0, 1.7, 0))
        headlamp.simdOrientation = Self.lookRotation(forward: SIMD3<Float>(simd_normalize(forward + SIMD3(0, -0.08, 0))))

        let nearStation = track.stationDistances.contains { abs($0 - f.distance) < 90 }
        withShared {
            $0.focus = center
            $0.underground = deck < -2
            $0.cameraAboveStationRoof = nearStation && deck > 4 && eye.y > deck + 9 && s.mode != .front
            if !terminated { $0.followed = f }
            $0.terminated = terminated
        }
    }

    private func makeTrain(_ t: Train) -> [SCNNode] {
        guard let factory = factories[t.lineID] else { return [] }
        let cars = factory.makeTrain(destination: t.destinationName)
        cars.forEach(trainRoot.addChildNode)
        trainNodes[t.id] = cars
        return cars
    }

    private func place(_ cars: [SCNNode], train t: Train, track: TrackGeometry) {
        let sign: Double = t.direction == .forward ? 1 : -1
        let lateral = TrackLayout.lateral(for: t.direction)
        let half = Double(CarSpec.trainLength) / 2
        let bogie = Double(CarSpec.bogieOffset)
        let centers = CarSpec.carCenters
        for (i, car) in cars.enumerated() {
            let sc = t.distance + sign * (half - Double(centers[i]))
            let front = track.railPoint(at: sc + sign * bogie, lateral: lateral)
            let rear = track.railPoint(at: sc - sign * bogie, lateral: lateral)
            let fwd = simd_normalize(front - rear)
            let yaw = Float(atan2(fwd.x, fwd.z)), pitch = Float(asin(fwd.y))
            var q = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [1, 0, 0])
            if i == cars.count - 1 { q = q * simd_quatf(angle: .pi, axis: [0, 1, 0]) }
            car.simdPosition = SIMD3<Float>((front + rear) / 2)
            car.simdOrientation = q
        }
    }

    /// Time used for the sun. `-skyHour 19.5` (debug builds) pins it to that IST hour today.
    private static func skyDate() -> Date {
        #if DEBUG
        let hour = UserDefaults.standard.double(forKey: "skyHour")
        if hour > 0 {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
            return cal.startOfDay(for: Date()).addingTimeInterval(hour * 3600)
        }
        #endif
        return Date()
    }

    // MARK: Math

    /// Orientation whose -z axis (SceneKit's view direction) points along `forward`.
    static func lookRotation(forward: SIMD3<Float>) -> simd_quatf {
        let z = -simd_normalize(forward)
        var x = simd_cross([0, 1, 0], z)
        if simd_length(x) < 1e-4 { x = [1, 0, 0] }
        x = simd_normalize(x)
        let y = simd_cross(z, x)
        return simd_quatf(simd_float3x3(x, y, z))
    }

    static func angleLerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        var d = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return a + d * t
    }
}

private extension Train {
    func coordinateIn(_ track: TrackGeometry?) -> SIMD2<Double> {
        track?.point(at: distance) ?? MetroWorld.project(coordinate)
    }
}
