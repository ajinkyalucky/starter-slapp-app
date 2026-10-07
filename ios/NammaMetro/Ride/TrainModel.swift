import SceneKit
import simd
import UIKit

/// Dimensions of a Namma Metro car (standard gauge, 2.88 m wide), in metres.
/// Car-local frame: x right, y up from the rail head, z forward.
enum CarSpec {
    static let bodyLength: Float = 20.4
    static let noseLength: Float = 0.95
    static let gap: Float = 0.7
    static let halfWidth: Float = 1.44
    static let bogieOffset: Float = 7.3
    static let gauge: Float = 1.435
    static let cars = 6

    static var cabLength: Float { bodyLength + noseLength }
    /// Full-length centres of each car measured back from the front of the train.
    static var carCenters: [Float] {
        var out: [Float] = [], cursor: Float = 0
        for i in 0..<cars {
            let len = (i == 0 || i == cars - 1) ? cabLength : bodyLength
            out.append(cursor + len / 2)
            cursor += len + gap
        }
        return out
    }
    static var trainLength: Float { 2 * cabLength + Float(cars - 2) * bodyLength + Float(cars - 1) * gap }
}

/// Livery colours (a brighter magenta than the map's line colour, per the reference renders).
enum Livery {
    static func color(for lineID: String) -> UInt32 {
        switch lineID {
        case "purple": return 0xB0259C
        case "green": return 0x12A150
        case "yellow": return 0xF2B400
        default: return 0x888888
        }
    }
}

/// Builds car meshes for one line's livery and stamps out trains from them.
///
/// Look follows design/reference: brushed stainless body with a thin waist stripe,
/// black-framed windows and doors; the cab end is a glossy livery-colour surround
/// framing a black fascia (windscreen, LED destination board, four round lamps)
/// over a silver skirt with an exposed coupler.
final class TrainFactory {
    enum Slot: Int, CaseIterable {
        case steel, paint, roof, glass, fascia, rubber, underframe, wheel, headlight, taillight, marker
    }

    private let materials: [SCNMaterial]
    private let lead: SCNNode
    private let middle: SCNNode
    private let tail: SCNNode

    init(lineColor: UInt32, library: MetroMaterials) {
        materials = [library.steel, library.paint(lineColor), library.roof, library.glass, library.fascia,
                     library.rubber, library.underframe, library.wheel, library.headlight, library.taillight,
                     library.marker]
        lead = Self.car(cab: true, gangway: true, lights: .headlight, materials: materials)
        middle = Self.car(cab: false, gangway: true, lights: nil, materials: materials)
        tail = Self.car(cab: true, gangway: false, lights: .taillight, materials: materials)
    }

    /// Six cars, front first. Each car node's origin is the centre of its full length on the rail head.
    func makeTrain(destination: String) -> [SCNNode] {
        var cars: [SCNNode] = []
        for i in 0..<CarSpec.cars {
            let proto = i == 0 ? lead : (i == CarSpec.cars - 1 ? tail : middle)
            let car = proto.clone()
            car.name = "car\(i)"
            cars.append(car)
        }
        cars[0].addChildNode(Self.destinationBoard(destination))
        return cars
    }

    // MARK: Body section

    private static let stripe: ClosedRange<Float> = 1.42...1.56

    /// Right half of the cross-section from the underside up to the roof crown,
    /// with the slot of the edge leaving each point.
    private static let rightHalf: [(SIMD2<Float>, Slot)] = {
        let w = CarSpec.halfWidth
        var pts: [(SIMD2<Float>, Slot)] = [
            ([1.36, 0.95], .steel),
            ([w, 1.15], .steel),
            ([w, stripe.lowerBound], .paint),
            ([w, stripe.upperBound], .steel),
        ]
        let arcCenter = SIMD2<Float>(1.0, 3.15)
        for deg in stride(from: 0, through: 90, by: 15) {
            let t = Float(deg) * .pi / 180
            pts.append((arcCenter + [0.44 * cos(t), 0.52 * sin(t)], deg < 30 ? .steel : .roof))
        }
        pts.append(([0.5, 3.71], .roof))
        return pts
    }()

    /// Closed section, counter-clockwise from the bottom left.
    private static let section: (points: [SIMD2<Float>], slots: [Slot], creases: Set<Int>) = {
        let right = rightHalf
        var pts: [SIMD2<Float>] = [[-1.36, 0.95]]
        var slots: [Slot] = [.underframe]
        for (p, s) in right { pts.append(p); slots.append(s) }
        pts.append([0, 3.74]); slots.append(.roof)
        // Down the left side: the edge leaving mirrored point k matches right edge k-1.
        for k in stride(from: right.count - 1, through: 1, by: -1) {
            pts.append([-right[k].0.x, right[k].0.y])
            slots.append(right[k - 1].1)
        }
        let n = pts.count
        return (pts, slots, [0, 1, 2, n - 1, n - 2])
    }()

    /// Half width of the body at height `y`, from the section outline.
    private static func halfWidth(at y: Float) -> Float {
        let pts = rightHalf.map(\.0) + [[0, 3.74]]
        if y <= pts[0].y { return pts[0].x }
        for (a, b) in zip(pts, pts.dropFirst()) where y <= b.y {
            let t = (y - a.y) / max(b.y - a.y, 1e-4)
            return a.x + (b.x - a.x) * t
        }
        return 0
    }

    // MARK: Cab

    /// How far the cab face sits ahead of the body end. The face is near vertical
    /// to the windscreen, then rakes back into a rounded roof dome; corners round off in plan.
    static func noseDepth(x: Float, y: Float) -> Float {
        let rise = min(max((y - 2.3) / (3.74 - 2.3), 0), 1)
        let rake = 1 - 0.25 * rise - 0.55 * pow(rise, 4)
        let skirt = y < 1.0 ? 1 - (1.0 - y) * 0.6 : 1
        let corner = 1 - 0.55 * pow(min(abs(x) / CarSpec.halfWidth, 1), 4)
        return CarSpec.noseLength * rake * corner * skirt
    }

    private static let noseShrink: Float = 0.94

    /// Point on (or `offset` in front of) the cab face, in body coordinates.
    private static func facePoint(x: Float, y: Float, offset: Float = 0) -> (SIMD3<Float>, SIMD3<Float>) {
        let half = CarSpec.bodyLength / 2
        func z(_ x: Float, _ y: Float) -> Float { half + noseDepth(x: x / noseShrink, y: y) }
        let e: Float = 0.01
        let dzdx = (z(x + e, y) - z(x - e, y)) / (2 * e)
        let dzdy = (z(x, y + e) - z(x, y - e)) / (2 * e)
        let n = simd_normalize(SIMD3<Float>(-dzdx, -dzdy, 1))
        return (SIMD3(x, y, z(x, y)) + n * offset, n)
    }

    /// A patch on the cab face: rounded rectangle `halfWidth` × `y`, `radius` corners.
    private static func facePatch(_ mesh: inout MeshBuilder, _ slot: Slot, y: ClosedRange<Float>,
                                  halfWidth: (Float) -> Float, offset: Float, rows: Int = 14, cols: Int = 16) {
        var points: [[SIMD3<Float>]] = [], normals: [[SIMD3<Float>]] = []
        for r in 0...rows {
            let yy = y.lowerBound + (y.upperBound - y.lowerBound) * Float(r) / Float(rows)
            let hw = halfWidth(yy)
            var rowP: [SIMD3<Float>] = [], rowN: [SIMD3<Float>] = []
            for c in 0...cols {
                let xx = -hw + 2 * hw * Float(c) / Float(cols)
                let (p, n) = facePoint(x: xx, y: yy, offset: offset)
                rowP.append(p); rowN.append(n)
            }
            points.append(rowP); normals.append(rowN)
        }
        mesh.surface(slot.rawValue, points: points, normals: normals)
    }

    private static func roundedHalfWidth(_ hw: Float, y: ClosedRange<Float>, radius: Float) -> (Float) -> Float {
        { yy in
            let dy = max(y.lowerBound + radius - yy, yy - (y.upperBound - radius), 0)
            return hw - radius + (radius * radius - min(dy * dy, radius * radius)).squareRoot()
        }
    }

    private static func cab(_ mesh: inout MeshBuilder, lights: Slot) {
        let half = CarSpec.bodyLength / 2
        let sec = section
        let steps = 8
        let rings: [[SIMD3<Float>]] = (0...steps).map { k in
            let t = sin(Float(k) / Float(steps) * .pi / 2)
            return sec.points.map { p in
                let shrink = 1 - (1 - noseShrink) * t * t
                return [p.x * shrink, p.y, half + noseDepth(x: p.x, y: p.y) * t]
            }
        }
        // The livery surround wraps the cab corners above the skirt.
        let noseSlots = sec.points.indices.map { i -> Int in
            let a = sec.points[i], b = sec.points[(i + 1) % sec.points.count]
            let midY = (a.y + b.y) / 2
            if sec.slots[i] == .underframe { return Slot.underframe.rawValue }
            return midY > stripe.lowerBound ? Slot.paint.rawValue : Slot.steel.rawValue
        }
        mesh.loft(rings: rings, slots: noseSlots, smooth: true, creases: sec.creases) { p in [0, 2.3, p.z - 2] }

        // Face: silver skirt below the stripe line, livery surround above.
        let faceWidth: (Float) -> Float = { halfWidth(at: $0) * noseShrink }
        facePatch(&mesh, .steel, y: 0.95...stripe.lowerBound, halfWidth: faceWidth, offset: 0, rows: 6)
        facePatch(&mesh, .paint, y: stripe.lowerBound...3.74, halfWidth: faceWidth, offset: 0, rows: 22)

        // Black fascia from the headlights up past the windscreen.
        let fasciaY: ClosedRange<Float> = 1.62...3.36
        facePatch(&mesh, .fascia, y: fasciaY, halfWidth: roundedHalfWidth(1.12, y: fasciaY, radius: 0.24), offset: 0.008)
        let screenY: ClosedRange<Float> = 2.34...3.06
        facePatch(&mesh, .glass, y: screenY, halfWidth: roundedHalfWidth(1.02, y: screenY, radius: 0.12), offset: 0.014)

        // Lamps: a larger outer and smaller inner round lamp each side.
        for side: Float in [-1, 1] {
            for (x, r) in [(0.93, 0.115), (0.68, 0.085)] as [(Float, Float)] {
                let (p, n) = facePoint(x: side * x, y: 1.86, offset: 0.012)
                mesh.cylinder(Slot.rubber.rawValue, center: p, axis: n, radius: r + 0.025, halfLength: 0.006)
                mesh.cylinder(lights.rawValue, center: p + n * 0.008, axis: n, radius: r, halfLength: 0.006)
            }
            // Wipers resting at the bottom of the windscreen.
            let (wp, wn) = facePoint(x: side * 0.45, y: 2.52, offset: 0.03)
            let along = simd_normalize(SIMD3<Float>(side * 0.8, 0.6, 0))
            mesh.box(Slot.rubber.rawValue, center: wp, half: [0.012, 0.012, 0.36],
                     axes: (simd_cross(wn, along), wn, along))
        }
        // Amber marker light on the roof dome.
        let (mp, mn) = facePoint(x: 0, y: 3.56, offset: 0.01)
        mesh.box(Slot.marker.rawValue, center: mp, half: [0.2, 0.05, 0.03],
                 axes: ([1, 0, 0], simd_cross(mn, [1, 0, 0]), mn))

        // Skirt with a recess and the coupler head.
        let front = half + noseDepth(x: 0, y: 0.9)
        mesh.box(Slot.steel.rawValue, center: [0, 0.78, front - 0.35], half: [1.18, 0.2, 0.35])
        mesh.box(Slot.underframe.rawValue, center: [0, 0.74, front + 0.004], half: [0.62, 0.17, 0.006])
        mesh.box(Slot.underframe.rawValue, center: [0, 0.72, front + 0.15], half: [0.2, 0.13, 0.18])
    }

    // MARK: Car

    private static func car(cab hasCab: Bool, gangway: Bool, lights: Slot?, materials: [SCNMaterial]) -> SCNNode {
        var mesh = MeshBuilder(slots: Slot.allCases.count)
        let half = CarSpec.bodyLength / 2
        let sec = section
        let interior: (SIMD3<Float>) -> SIMD3<Float> = { p in [0, 2.3, p.z] }
        func ring(z: Float) -> [SIMD3<Float>] { sec.points.map { [$0.x, $0.y, z] } }

        mesh.loft(rings: [ring(z: -half), ring(z: half)], slots: sec.slots.map(\.rawValue), smooth: true,
                  creases: sec.creases, interior: interior)
        mesh.cap(ring: ring(z: -half), facing: [0, 0, -1]) { _ in Slot.steel.rawValue }
        if hasCab, let lights {
            cab(&mesh, lights: lights)
        } else {
            mesh.cap(ring: ring(z: half), facing: [0, 0, 1]) { _ in Slot.steel.rawValue }
        }

        sides(&mesh, half: half, cab: hasCab)
        running(&mesh)
        if gangway {
            mesh.box(Slot.rubber.rawValue, center: [0, 2.25, -half - CarSpec.gap / 2], half: [0.78, 1.1, CarSpec.gap / 2 + 0.05])
        }

        let node = SCNNode(geometry: mesh.geometry(materials: materials))
        node.castsShadow = true
        // Re-centre so the origin is the middle of the car's full length.
        node.simdPosition = [0, 0, hasCab ? -CarSpec.noseLength / 2 : 0]
        let container = SCNNode()
        container.addChildNode(node)
        return container
    }

    /// Black-framed doors and windows on both sides.
    private static func sides(_ mesh: inout MeshBuilder, half: Float, cab: Bool) {
        let doors: [Float] = [-7.0, -2.35, 2.35, 7.0]
        let doorHalf: Float = 0.68
        let w = CarSpec.halfWidth
        for side: Float in [-1, 1] {
            let axes: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) = ([side, 0, 0], [0, 1, 0], [0, 0, 1])
            func panel(_ slot: Slot, y: Float, z: Float, halfY: Float, halfZ: Float, out: Float) {
                mesh.box(slot.rawValue, center: [side * (w + out), y, z], half: [0.005, halfY, halfZ], axes: axes)
            }
            for z in doors {
                panel(.rubber, y: 2.1, z: z, halfY: 1.0, halfZ: doorHalf + 0.07, out: 0.004)   // frame
                panel(.steel, y: 2.08, z: z, halfY: 0.97, halfZ: doorHalf, out: 0.008)          // leaves
                panel(.paint, y: (stripe.lowerBound + stripe.upperBound) / 2, z: z,
                      halfY: (stripe.upperBound - stripe.lowerBound) / 2, halfZ: doorHalf, out: 0.011)
                panel(.rubber, y: 2.08, z: z, halfY: 0.97, halfZ: 0.01, out: 0.014)             // centre seam
                for leaf: Float in [-1, 1] {
                    panel(.rubber, y: 2.42, z: z + leaf * 0.34, halfY: 0.5, halfZ: 0.2, out: 0.012)
                    panel(.glass, y: 2.42, z: z + leaf * 0.34, halfY: 0.46, halfZ: 0.16, out: 0.016)
                }
            }
            // Windows fill the gaps between doors.
            var edges: [Float] = [-half + 0.5]
            for z in doors { edges += [z - doorHalf - 0.07, z + doorHalf + 0.07] }
            edges.append(half - (cab ? 1.3 : 0.5))
            for k in stride(from: 0, to: edges.count, by: 2) {
                let a = edges[k] + 0.25, b = edges[k + 1] - 0.25
                guard b - a > 0.6 else { continue }
                panel(.rubber, y: 2.43, z: (a + b) / 2, halfY: 0.56, halfZ: (b - a) / 2 + 0.06, out: 0.004)
                panel(.glass, y: 2.45, z: (a + b) / 2, halfY: 0.47, halfZ: (b - a) / 2 - 0.03, out: 0.009)
            }
            if cab {
                // Cab door with grab rails.
                let z = half - 0.75
                panel(.rubber, y: 2.1, z: z, halfY: 0.98, halfZ: 0.38, out: 0.004)
                panel(.steel, y: 2.08, z: z, halfY: 0.95, halfZ: 0.33, out: 0.008)
                panel(.glass, y: 2.5, z: z, halfY: 0.4, halfZ: 0.22, out: 0.012)
                for dz: Float in [-0.48, 0.48] {
                    mesh.cylinder(Slot.wheel.rawValue, center: [side * (w + 0.06), 1.95, z + dz], axis: [0, 1, 0],
                                  radius: 0.018, halfLength: 0.55, segments: 8)
                }
            }
        }
    }

    /// Bogies, wheels, underframe equipment and roof units.
    private static func running(_ mesh: inout MeshBuilder) {
        let g = CarSpec.gauge / 2
        for bz in [-CarSpec.bogieOffset, CarSpec.bogieOffset] {
            mesh.box(Slot.underframe.rawValue, center: [0, 0.66, bz], half: [1.0, 0.12, 1.25])
            for side: Float in [-1, 1] {
                mesh.box(Slot.underframe.rawValue, center: [side * 1.02, 0.52, bz], half: [0.09, 0.2, 1.45])
                mesh.cylinder(Slot.rubber.rawValue, center: [side * 1.02, 0.82, bz], axis: [0, 1, 0],
                              radius: 0.17, halfLength: 0.1)
                // Third-rail current collector.
                mesh.box(Slot.underframe.rawValue, center: [side * 1.32, 0.34, bz + 0.9], half: [0.12, 0.05, 0.18])
            }
            for az: Float in [-1.1, 1.1] {
                mesh.cylinder(Slot.underframe.rawValue, center: [0, 0.43, bz + az], axis: [1, 0, 0], radius: 0.08,
                              halfLength: g + 0.15)
                for side: Float in [-1, 1] {
                    mesh.cylinder(Slot.wheel.rawValue, center: [side * (g - 0.04), 0.43, bz + az], axis: [1, 0, 0],
                                  radius: 0.43, halfLength: 0.065, segments: 24)
                }
            }
        }
        for (a, b, depth) in [(-5.4, -3.1, 0.42), (-2.8, -0.6, 0.32), (-0.2, 2.4, 0.4), (2.8, 5.4, 0.36)] as [(Float, Float, Float)] {
            mesh.box(Slot.underframe.rawValue, center: [0, 0.95 - depth / 2, (a + b) / 2], half: [1.12, depth / 2, (b - a) / 2])
        }
        for z: Float in [-5.0, 5.0] {
            mesh.box(Slot.roof.rawValue, center: [0, 3.80, z], half: [0.98, 0.16, 1.75])
            for fz: Float in [-0.8, 0.8] {
                mesh.cylinder(Slot.rubber.rawValue, center: [0, 3.965, z + fz], axis: [0, 1, 0], radius: 0.34,
                              halfLength: 0.008)
            }
        }
    }

    private static let boardLock = NSLock()
    private static var boardImages: [String: UIImage] = [:]

    /// Amber LED destination display above the windscreen. Images are cached per
    /// destination so trains entering view don't redraw text on the render thread.
    private static func destinationBoard(_ text: String) -> SCNNode {
        boardLock.lock()
        let cached = boardImages[text]
        boardLock.unlock()
        let image = cached ?? boardImage(text)
        if cached == nil {
            boardLock.lock()
            boardImages[text] = image
            boardLock.unlock()
        }
        return boardNode(image)
    }

    private static func boardImage(_ text: String) -> UIImage {
        let size = CGSize(width: 512, height: 72)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.04, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 40, weight: .bold),
                .foregroundColor: UIColor(red: 1, green: 0.62, blue: 0.1, alpha: 1),
                .kern: 2,
            ]
            let s = NSAttributedString(string: text.uppercased(), attributes: attrs)
            let b = s.boundingRect(with: size, options: [], context: nil)
            let scale = min(1, (size.width - 28) / b.width)
            ctx.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.scaleBy(x: scale, y: 1)
            s.draw(at: CGPoint(x: -b.width / 2, y: -b.height / 2))
        }
    }

    private static func boardNode(_ image: UIImage) -> SCNNode {
        let plane = SCNPlane(width: 1.1, height: 0.155)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.emission.contents = image
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        let (p, n) = facePoint(x: 0, y: 3.2, offset: 0.02)
        // Car nodes are re-centred by half the nose length.
        node.simdPosition = p - [0, 0, CarSpec.noseLength / 2]
        node.simdOrientation = simd_quatf(from: [0, 0, 1], to: n)
        return node
    }
}
