import SceneKit
import simd
import UIKit

/// Cross-track layout shared by the scenery and train placement.
enum TrackLayout {
    /// Each running line's centre from the alignment centre. Trains keep left:
    /// forward-direction trains run on the left of the line's forward direction.
    static let trackOffset: Double = 2.0
    static let railTop: Double = 0.42
    static let platformTop: Double = 1.5
    static let platformHalfLength: Float = 70

    static func lateral(for direction: Direction) -> Double {
        direction == .forward ? -trackOffset : trackOffset
    }
}

extension TrackGeometry {
    /// Right-hand unit vector (scene x/z) of the forward direction at `s`.
    func right(at s: Double) -> SIMD2<Double> {
        let t = tangent(at: s)
        return SIMD2(-t.y, t.x)
    }

    /// Scene-space point on the rail head of one running line.
    func railPoint(at s: Double, lateral: Double) -> SIMD3<Double> {
        let p = point(at: s) + right(at: s) * lateral
        return SIMD3(p.x, deckHeight(at: s) + TrackLayout.railTop, p.y)
    }
}

/// Builds one line's viaduct, track and stations in chunks of track so the scene
/// can stream them in around the camera.
final class LineScenery {
    static let chunkSamples = 50   // 400 m at 8 m spacing

    let track: TrackGeometry
    let line: MetroLine
    private let materials: MetroMaterials
    let chunkCount: Int

    init(line: MetroLine, materials: MetroMaterials) {
        self.line = line
        self.track = line.track
        self.materials = materials
        chunkCount = (track.points.count - 2) / Self.chunkSamples + 1
    }

    func chunkRange(_ c: Int) -> ClosedRange<Int> {
        let a = c * Self.chunkSamples
        return a...min(a + Self.chunkSamples, track.points.count - 1)
    }

    func chunkCenter(_ c: Int) -> SIMD2<Double> {
        let r = chunkRange(c)
        return track.points[(r.lowerBound + r.upperBound) / 2]
    }

    // MARK: Chunk

    private enum Slot: Int, CaseIterable { case concrete, concreteDark, rail, thirdRail }
    private var trackMaterials: [SCNMaterial] {
        [materials.concrete, materials.concreteDark, materials.rail, materials.thirdRail]
    }

    private static let deckProfile = Profile([
        [-4.6, 1.1], [-4.35, 1.1], [-4.35, 0], [4.35, 0], [4.35, 1.1], [4.6, 1.1],
        [4.6, -0.35], [2.3, -0.55], [1.9, -2.2], [-1.9, -2.2], [-2.3, -0.55], [-4.6, -0.35],
    ], slot: Slot.concrete.rawValue)

    private static func railProfile(at x: Float) -> Profile {
        Profile([[x - 0.075, 0.25], [x + 0.075, 0.25], [x + 0.075, 0.27], [x + 0.012, 0.29], [x + 0.012, 0.38],
                 [x + 0.036, 0.385], [x + 0.036, 0.42], [x - 0.036, 0.42], [x - 0.036, 0.385], [x - 0.012, 0.38],
                 [x - 0.012, 0.29], [x - 0.075, 0.27]], slot: Slot.rail.rawValue)
    }

    /// Builds the node for a chunk. Safe to call off the main thread.
    func makeChunk(_ c: Int) -> SCNNode {
        let range = chunkRange(c)
        let base = track.points[range.lowerBound]
        let node = SCNNode()
        node.simdPosition = [Float(base.x), 0, Float(base.y)]
        node.name = "chunk-\(line.id)-\(c)"

        func frame(_ i: Int) -> SweepFrame {
            let s = track.cumulative[i]
            let p = track.point(at: s) - base
            let r = track.right(at: s)
            return SweepFrame(origin: [Float(p.x), Float(track.deck[i]), Float(p.y)],
                              right: [Float(r.x), 0, Float(r.y)], distance: Float(s))
        }
        let frames = range.map(frame)

        var mesh = MeshBuilder(slots: Slot.allCases.count)
        mesh.sweep(Self.deckProfile, frames: frames)
        for side: Float in [-1, 1] {
            let center = side * Float(TrackLayout.trackOffset)
            for rail: Float in [-1, 1] {
                let x = center + rail * CarSpec.gauge / 2
                mesh.sweep(.rect(x: (x - 0.3)...(x + 0.3), y: 0...0.25, slot: Slot.concreteDark.rawValue), frames: frames)
                mesh.sweep(Self.railProfile(at: x), frames: frames, uvScale: 1)
            }
            let third = center + side * 1.55
            mesh.sweep(.rect(x: (third - 0.07)...(third + 0.07), y: 0.3...0.48, slot: Slot.thirdRail.rawValue), frames: frames)
        }

        // Piers on viaducts, every 32 m, except where a station carries the deck.
        let stations = track.stationDistances
        for i in range where i % 4 == 0 && i < range.upperBound {
            let s = track.cumulative[i], d = Float(track.deck[i])
            guard d > 6, !stations.contains(where: { abs($0 - s) < 80 }) else { continue }
            let f = frames[i - range.lowerBound]
            let along = simd_cross(f.right, [0, 1, 0]) * -1
            let yaw = atan2(along.x, along.z)
            let rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            let octagon: [SIMD2<Float>] = (0..<8).map { k in
                let a = Float(k) / 8 * 2 * .pi + .pi / 8
                return [0.95 * cos(a), 0.8 * sin(a)]
            }
            let ground = SIMD3<Float>(f.origin.x, 0, f.origin.z)
            mesh.prism(Slot.concrete.rawValue, footprint: octagon, bottom: 0, top: d - 3.3, at: ground, rotation: rotation)
            mesh.box(Slot.concrete.rawValue, center: ground + [0, d - 2.75, 0], half: [2.9, 0.55, 1.1],
                     axes: (f.right, [0, 1, 0], along))
        }
        // Retaining walls where a ramp runs close to the ground.
        for i in range where i < range.upperBound {
            let d = Float(track.deck[i])
            guard d > 0.4, d < 6.5 else { continue }
            let f = frames[i - range.lowerBound]
            let along = simd_cross(f.right, [0, 1, 0]) * -1
            let h = d - 0.35
            mesh.box(Slot.concreteDark.rawValue, center: [f.origin.x, h / 2, f.origin.z] + along * 4,
                     half: [4.55, h / 2, 4.1], axes: (f.right, [0, 1, 0], along))
        }
        if let g = mesh.geometry(materials: trackMaterials) {
            let n = SCNNode(geometry: g)
            n.castsShadow = true
            node.addChildNode(n)
        }

        // Tunnel box wherever the line is underground.
        var tunnel = MeshBuilder(slots: 1)
        var run: [SweepFrame] = []
        for (k, i) in range.enumerated() {
            if track.deck[i] < -1 { run.append(frames[k]) }
            if track.deck[i] >= -1 || i == range.upperBound {
                tunnel.sweep(.rect(x: -5.2...5.2, y: -0.6...6.8, slot: 0, inward: true), frames: run)
                run = []
            }
        }
        if let g = tunnel.geometry(materials: [materials.tunnel]) {
            let n = SCNNode(geometry: g)
            n.name = "tunnel"
            node.addChildNode(n)
        }

        for (k, s) in stations.enumerated() where s >= track.cumulative[range.lowerBound] && s < track.cumulative[range.upperBound] {
            let st = makeStation(index: k, s: s)
            st.simdPosition -= node.simdPosition
            node.addChildNode(st)
        }
        return node
    }

    // MARK: Stations

    private enum StationSlot: Int, CaseIterable { case concrete, concreteDark, platform, tactile, glass, roof, tunnel }

    private func makeStation(index k: Int, s: Double) -> SCNNode {
        let p = track.point(at: s), t = track.tangent(at: s)
        let d = Float(track.deck[track.cumulative.firstIndex { $0 >= s } ?? 0])
        let node = SCNNode()
        node.simdPosition = [Float(p.x), 0, Float(p.y)]
        node.simdOrientation = simd_quatf(angle: Float(atan2(t.x, t.y)), axis: [0, 1, 0])
        node.name = "station"

        let len = TrackLayout.platformHalfLength
        let top = d + Float(TrackLayout.platformTop)
        var mesh = MeshBuilder(slots: StationSlot.allCases.count)
        let elevated = d > 4
        let underground = d < -4

        mesh.box(StationSlot.concrete.rawValue, center: [0, d - 0.72, 0], half: [8.6, 0.7, len + 3])
        for side: Float in [-1, 1] {
            mesh.box(StationSlot.platform.rawValue, center: [side * 6.0, (d + top) / 2, 0], half: [2.4, (top - d) / 2, len])
            mesh.box(StationSlot.tactile.rawValue, center: [side * 3.92, top + 0.004, 0], half: [0.28, 0.004, len])
            if !underground {
                for z in stride(from: -len + 4, through: len - 4, by: 12) {
                    mesh.box(StationSlot.concreteDark.rawValue, center: [side * 8.1, top + 3.25, z], half: [0.16, 3.25, 0.16])
                }
            }
            // Backing for the name boards.
            for z: Float in [-45, 0, 45] {
                mesh.box(StationSlot.concreteDark.rawValue, center: [side * 7.46, top + 3.1, z], half: [0.04, 0.42, 2.2])
            }
        }
        if elevated {
            // Concourse under the tracks and its columns.
            mesh.box(StationSlot.concrete.rawValue, center: [0, d - 2.9, 0], half: [10.5, 0.5, 42])
            mesh.box(StationSlot.glass.rawValue, center: [0, d - 6.1, 0], half: [10, 2.7, 40])
            mesh.box(StationSlot.concrete.rawValue, center: [0, d - 9.0, 0], half: [10.5, 0.2, 42])
            for z: Float in [-60, -30, 0, 30, 60] {
                for x: Float in [-5, 5] {
                    mesh.box(StationSlot.concrete.rawValue, center: [x, (d - 9.2) / 2, z], half: [0.45, (d - 9.2) / 2, 0.45])
                }
            }
        }
        if underground {
            mesh.box(StationSlot.tunnel.rawValue, center: [0, d + 3.6, 0], half: [11, 4.4, len + 6])
        }
        let mats = [materials.concrete, materials.concreteDark, materials.platform, materials.tactile,
                    materials.stationGlass, materials.stationRoof, materials.tunnel]
        if let g = mesh.geometry(materials: mats) {
            let n = SCNNode(geometry: g)
            n.castsShadow = true
            node.addChildNode(n)
        }

        if !underground {
            // Curved roof shell.
            var roof = MeshBuilder(slots: 1)
            var outline: [SIMD2<Float>] = []
            for i in 0...16 {
                let x = -10.8 + 21.6 * Float(i) / 16
                outline.append([x, top + 6.6 + 1.6 * (1 - (x / 10.8) * (x / 10.8))])
            }
            for i in stride(from: 16, through: 0, by: -1) {
                let x = -10.8 + 21.6 * Float(i) / 16
                outline.append([x, top + 6.35 + 1.6 * (1 - (x / 10.8) * (x / 10.8))])
            }
            roof.sweep(Profile(outline, slot: 0), frames: [
                SweepFrame(origin: [0, 0, -len - 2], right: [1, 0, 0], distance: 0),
                SweepFrame(origin: [0, 0, len + 2], right: [1, 0, 0], distance: 2 * len + 4),
            ])
            let r = SCNNode(geometry: roof.geometry(materials: [materials.stationRoof]))
            r.castsShadow = true
            r.name = "stationRoof"
            node.addChildNode(r)
        }

        let board = nameBoard(line.stations[k].name)
        for side: Float in [-1, 1] {
            for z: Float in [-45, 0, 45] {
                let plane = SCNNode(geometry: board)
                plane.simdPosition = [side * 7.40, top + 3.1, z]
                plane.simdEulerAngles = [0, side > 0 ? -.pi / 2 : .pi / 2, 0]
                node.addChildNode(plane)
            }
        }
        return node
    }

    private func nameBoard(_ name: String) -> SCNGeometry {
        let size = CGSize(width: 1024, height: 180)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let color = line.uiColor
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.11, green: 0.14, blue: 0.19, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 28, height: size.height))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 84, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let s = NSAttributedString(string: name, attributes: attrs)
            let b = s.boundingRect(with: size, options: [], context: nil)
            let scale = min(1, (size.width - 110) / b.width)
            ctx.cgContext.translateBy(x: 70, y: size.height / 2)
            ctx.cgContext.scaleBy(x: scale, y: scale)
            s.draw(at: CGPoint(x: 0, y: -b.height / 2))
        }
        let plane = SCNPlane(width: 4.3, height: 0.76)
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = image
        m.emission.contents = image
        m.emission.intensity = 0.35
        m.roughness.contents = 0.5
        plane.materials = [m]
        return plane
    }
}
