import SceneKit
import simd

/// A closed 2D cross-section (x right, y up) swept or extruded into 3D.
struct Profile {
    var points: [SIMD2<Float>]
    /// Material slot per edge (edge i runs from point i to point i + 1, wrapping).
    var slots: [Int]
    /// Average normals across vertices for a rounded look; `creases` stay sharp.
    var smooth = false
    var creases: Set<Int> = []
    /// Flip normals to face into the shape (tunnels).
    var inward = false

    init(_ points: [SIMD2<Float>], slot: Int, smooth: Bool = false, inward: Bool = false) {
        self.points = points
        self.slots = Array(repeating: slot, count: points.count)
        self.smooth = smooth
        self.inward = inward
    }

    init(points: [SIMD2<Float>], slots: [Int], smooth: Bool, creases: Set<Int> = []) {
        self.points = points
        self.slots = slots
        self.smooth = smooth
        self.creases = creases
    }

    static func rect(x: ClosedRange<Float>, y: ClosedRange<Float>, slot: Int, inward: Bool = false) -> Profile {
        Profile([[x.lowerBound, y.lowerBound], [x.upperBound, y.lowerBound],
                 [x.upperBound, y.upperBound], [x.lowerBound, y.upperBound]], slot: slot, inward: inward)
    }

    /// Outward unit normal of each edge, whatever the winding.
    var edgeNormals: [SIMD2<Float>] {
        var area: Float = 0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        let ccw = area > 0
        return points.indices.map { i in
            let d = points[(i + 1) % points.count] - points[i]
            let n = ccw ? SIMD2(d.y, -d.x) : SIMD2(-d.y, d.x)
            return simd_normalize(inward ? -n : n)
        }
    }
}

/// A position and orientation along a sweep path.
struct SweepFrame {
    var origin: SIMD3<Float>
    var right: SIMD3<Float>
    var up: SIMD3<Float> = [0, 1, 0]
    /// Distance along the path, used for texture coordinates.
    var distance: Float
}

/// Accumulates triangles per material slot and emits one SCNGeometry.
struct MeshBuilder {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var uvs: [SIMD2<Float>] = []
    private var indices: [[UInt32]]

    init(slots: Int) {
        indices = Array(repeating: [], count: slots)
    }

    var isEmpty: Bool { positions.isEmpty }

    private mutating func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float>) -> UInt32 {
        positions.append(p)
        normals.append(n)
        uvs.append(uv)
        return UInt32(positions.count - 1)
    }

    /// Adds a triangle, flipping the winding if needed so it faces along `facing`.
    private mutating func triangle(_ slot: Int, _ a: UInt32, _ b: UInt32, _ c: UInt32, facing: SIMD3<Float>) {
        let pa = positions[Int(a)], pb = positions[Int(b)], pc = positions[Int(c)]
        if simd_dot(simd_cross(pb - pa, pc - pa), facing) >= 0 {
            indices[slot] += [a, b, c]
        } else {
            indices[slot] += [a, c, b]
        }
    }

    /// Flat quad p0-p1-p2-p3 (in order around the edge) facing `normal`.
    mutating func quad(_ slot: Int, _ p: [SIMD3<Float>], normal: SIMD3<Float>, uv: [SIMD2<Float>]? = nil) {
        let uv = uv ?? [[0, 0], [1, 0], [1, 1], [0, 1]]
        let i = (0..<4).map { vertex(p[$0], normal, uv[$0]) }
        triangle(slot, i[0], i[1], i[2], facing: normal)
        triangle(slot, i[0], i[2], i[3], facing: normal)
    }

    /// Box with half-extents `half` centred at `center`, axes given by an orthonormal basis.
    mutating func box(_ slot: Int, center: SIMD3<Float>, half: SIMD3<Float>,
                      axes: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) = ([1, 0, 0], [0, 1, 0], [0, 0, 1])) {
        let (ax, ay, az) = axes
        let ex = ax * half.x, ey = ay * half.y, ez = az * half.z
        func face(_ n: SIMD3<Float>, _ u: SIMD3<Float>, _ v: SIMD3<Float>, _ su: Float, _ sv: Float) {
            let c = center + n
            let nn = simd_normalize(n)
            quad(slot, [c - u - v, c + u - v, c + u + v, c - u + v], normal: nn,
                 uv: [[0, 0], [su, 0], [su, sv], [0, sv]])
        }
        face(ex, ez, ey, half.z * 2, half.y * 2)
        face(-ex, ez, ey, half.z * 2, half.y * 2)
        face(ey, ex, ez, half.x * 2, half.z * 2)
        face(-ey, ex, ez, half.x * 2, half.z * 2)
        face(ez, ex, ey, half.x * 2, half.y * 2)
        face(-ez, ex, ey, half.x * 2, half.y * 2)
    }

    /// Smooth surface through a grid of points (rows × columns) with per-point normals.
    mutating func surface(_ slot: Int, points: [[SIMD3<Float>]], normals: [[SIMD3<Float>]]) {
        guard points.count >= 2, let cols = points.first?.count, cols >= 2 else { return }
        let ids = points.indices.map { r in
            (0..<cols).map { c in vertex(points[r][c], normals[r][c], [points[r][c].x, points[r][c].y]) }
        }
        for r in 0..<(points.count - 1) {
            for c in 0..<(cols - 1) {
                let facing = normals[r][c] + normals[r + 1][c + 1]
                triangle(slot, ids[r][c], ids[r][c + 1], ids[r + 1][c + 1], facing: facing)
                triangle(slot, ids[r][c], ids[r + 1][c + 1], ids[r + 1][c], facing: facing)
            }
        }
    }

    /// Flat polygon from precomputed triangles, facing `normal`.
    mutating func polygon(_ slot: Int, points: [SIMD3<Float>], triangles: [(Int, Int, Int)], normal: SIMD3<Float>) {
        let ids = points.map { vertex($0, normal, [$0.x / 4, $0.z / 4]) }
        for (a, b, c) in triangles { triangle(slot, ids[a], ids[b], ids[c], facing: normal) }
    }

    /// Smooth ellipsoid (a tree canopy), `segments` around and `rings` top to bottom.
    mutating func ellipsoid(_ slot: Int, center: SIMD3<Float>, radii: SIMD3<Float>, segments: Int = 7, rings: Int = 5) {
        var ids: [[UInt32]] = []
        for r in 0...rings {
            let phi = Float(r) / Float(rings) * .pi          // 0 at top
            var row: [UInt32] = []
            for k in 0...segments {
                let theta = Float(k) / Float(segments) * 2 * .pi
                let unit = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                let n = simd_normalize(unit / radii)   // ellipsoid normal
                row.append(vertex(center + unit * radii, n, [Float(k) / Float(segments), Float(r) / Float(rings)]))
            }
            ids.append(row)
        }
        for r in 0..<rings {
            for k in 0..<segments {
                let theta = (Float(k) + 0.5) / Float(segments) * 2 * .pi, phi = (Float(r) + 0.5) / Float(rings) * .pi
                let facing = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                triangle(slot, ids[r][k], ids[r][k + 1], ids[r + 1][k + 1], facing: facing)
                triangle(slot, ids[r][k], ids[r + 1][k + 1], ids[r + 1][k], facing: facing)
            }
        }
    }

    /// Capped cylinder around `axis` (unit), smooth-shaded sides.
    mutating func cylinder(_ slot: Int, center: SIMD3<Float>, axis: SIMD3<Float>, radius: Float,
                           halfLength: Float, segments: Int = 20) {
        let helper: SIMD3<Float> = abs(axis.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let u = simd_normalize(simd_cross(axis, helper)), v = simd_cross(axis, u)
        let a = center - axis * halfLength, b = center + axis * halfLength
        var ringA: [UInt32] = [], ringB: [UInt32] = []
        for i in 0...segments {
            let t = Float(i) / Float(segments) * 2 * .pi
            let n = u * cos(t) + v * sin(t)
            ringA.append(vertex(a + n * radius, n, [Float(i) / Float(segments), 0]))
            ringB.append(vertex(b + n * radius, n, [Float(i) / Float(segments), 1]))
        }
        for i in 0..<segments {
            let facing = u * cos((Float(i) + 0.5) / Float(segments) * 2 * .pi) + v * sin((Float(i) + 0.5) / Float(segments) * 2 * .pi)
            triangle(slot, ringA[i], ringA[i + 1], ringB[i + 1], facing: facing)
            triangle(slot, ringA[i], ringB[i + 1], ringB[i], facing: facing)
        }
        for (end, normal) in [(a, -axis), (b, axis)] {
            let c = vertex(end, normal, [0.5, 0.5])
            let ring = (0...segments).map { i -> UInt32 in
                let t = Float(i) / Float(segments) * 2 * .pi
                return vertex(end + (u * cos(t) + v * sin(t)) * radius, normal, [0.5 + cos(t) / 2, 0.5 + sin(t) / 2])
            }
            for i in 0..<segments { triangle(slot, c, ring[i], ring[i + 1], facing: normal) }
        }
    }

    /// Vertical prism from a 2D footprint (x, z) between two heights; sides only plus top.
    mutating func prism(_ slot: Int, footprint: [SIMD2<Float>], bottom: Float, top: Float, at origin: SIMD3<Float>,
                        rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) {
        let n = footprint.count
        for i in 0..<n {
            let a = footprint[i], b = footprint[(i + 1) % n]
            let pa = rotation.act([a.x, 0, a.y]), pb = rotation.act([b.x, 0, b.y])
            let mid = (pa + pb) / 2
            let normal = simd_normalize(SIMD3(mid.x, 0, mid.z))
            let len = simd_distance(a, b)
            quad(slot, [origin + pa + [0, bottom, 0], origin + pb + [0, bottom, 0],
                        origin + pb + [0, top, 0], origin + pa + [0, top, 0]],
                 normal: normal, uv: [[0, bottom / 4], [len / 4, bottom / 4], [len / 4, top / 4], [0, top / 4]])
        }
        let topCenter = vertex(origin + [0, top, 0], [0, 1, 0], [0, 0])
        let ring = footprint.map { p -> UInt32 in
            let q = rotation.act([p.x, 0, p.y])
            return vertex(origin + q + [0, top, 0], [0, 1, 0], [p.x / 4, p.y / 4])
        }
        for i in 0..<n {
            triangle(slot, topCenter, ring[i], ring[(i + 1) % n], facing: [0, 1, 0])
        }
    }

    /// Sweeps a profile through a series of frames. Normals come from the 2D profile,
    /// so the profile may be concave (parapets, troughs).
    mutating func sweep(_ profile: Profile, frames: [SweepFrame], uvScale: Float = 0.25) {
        guard frames.count >= 2 else { return }
        let pts = profile.points
        let n = pts.count
        let edgeN = profile.edgeNormals
        var arc: [Float] = [0]
        for i in 0..<n { arc.append(arc[i] + simd_distance(pts[i], pts[(i + 1) % n])) }

        func vertexNormal(_ v: Int, edge: Int) -> SIMD2<Float> {
            guard profile.smooth, !profile.creases.contains(v) else { return edgeN[edge] }
            return simd_normalize(edgeN[(v - 1 + n) % n] + edgeN[v % n])
        }

        for e in 0..<n {
            let a = e, b = (e + 1) % n
            let na = vertexNormal(a, edge: e), nb = vertexNormal(b, edge: e)
            var prev: (UInt32, UInt32)?
            for f in frames {
                func place(_ p: SIMD2<Float>) -> SIMD3<Float> { f.origin + f.right * p.x + f.up * p.y }
                func dir(_ d: SIMD2<Float>) -> SIMD3<Float> { simd_normalize(f.right * d.x + f.up * d.y) }
                let ia = vertex(place(pts[a]), dir(na), [arc[e] * uvScale, f.distance * uvScale])
                let ib = vertex(place(pts[b]), dir(nb), [arc[e + 1] * uvScale, f.distance * uvScale])
                if let (pa, pb) = prev {
                    let facing = dir(edgeN[e])
                    triangle(profile.slots[e], pa, pb, ib, facing: facing)
                    triangle(profile.slots[e], pa, ib, ia, facing: facing)
                }
                prev = (ia, ib)
            }
        }
    }

    /// Joins rings of equal point count with numerically computed normals, oriented away
    /// from `interior(point)`. Used for the convex car body and cab nose.
    mutating func loft(rings: [[SIMD3<Float>]], slots: [Int], smooth: Bool, creases: Set<Int> = [],
                       interior: (SIMD3<Float>) -> SIMD3<Float>) {
        guard let n = rings.first?.count, rings.count >= 2 else { return }
        let r = rings.count
        var face = Array(repeating: Array(repeating: SIMD3<Float>(0, 0, 0), count: n), count: r - 1)
        for k in 0..<(r - 1) {
            for e in 0..<n {
                let a = rings[k][e], b = rings[k][(e + 1) % n], c = rings[k + 1][e]
                var nrm = simd_cross(b - a, c - a)
                if simd_length(nrm) < 1e-9 { nrm = simd_cross(rings[k + 1][(e + 1) % n] - c, a - c) }
                nrm = simd_length(nrm) < 1e-9 ? [0, 1, 0] : simd_normalize(nrm)
                let center = (a + b + c) / 3
                if simd_dot(nrm, center - interior(center)) < 0 { nrm = -nrm }
                face[k][e] = nrm
            }
        }
        func normal(ring k: Int, vertex v: Int, edge e: Int) -> SIMD3<Float> {
            let edges = (smooth && !creases.contains(v)) ? [(v - 1 + n) % n, v % n] : [e]
            var sum = SIMD3<Float>(0, 0, 0)
            for kk in [k - 1, k] where kk >= 0 && kk < r - 1 {
                for ee in edges { sum += face[kk][ee] }
            }
            return simd_normalize(sum)
        }
        for e in 0..<n {
            let a = e, b = (e + 1) % n
            var prev: (UInt32, UInt32)?
            for k in 0..<r {
                let ia = vertex(rings[k][a], normal(ring: k, vertex: a, edge: e), [Float(e), rings[k][a].z * 0.25])
                let ib = vertex(rings[k][b], normal(ring: k, vertex: b, edge: e), [Float(e + 1), rings[k][b].z * 0.25])
                if let (pa, pb) = prev {
                    let facing = face[k - 1][e]
                    triangle(slots[e], pa, pb, ib, facing: facing)
                    triangle(slots[e], pa, ib, ia, facing: facing)
                }
                prev = (ia, ib)
            }
        }
    }

    /// Fan-fills a ring (a convex outline) facing `facing`; `slot` picks a material per triangle.
    mutating func cap(ring: [SIMD3<Float>], facing: SIMD3<Float>, slot: (SIMD3<Float>) -> Int) {
        let center = ring.reduce(SIMD3<Float>(0, 0, 0), +) / Float(ring.count)
        for i in ring.indices {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            var n = simd_cross(a - center, b - center)
            if simd_length(n) < 1e-9 { continue }
            n = simd_normalize(n)
            if simd_dot(n, facing) < 0 { n = -n }
            let s = slot((a + b + center) / 3)
            let ic = vertex(center, n, [center.x, center.y])
            let ia = vertex(a, n, [a.x, a.y]), ib = vertex(b, n, [b.x, b.y])
            triangle(s, ic, ia, ib, facing: n)
        }
    }

    /// Builds the geometry; materials are matched to slots and empty slots are dropped.
    func geometry(materials: [SCNMaterial]) -> SCNGeometry? {
        guard !positions.isEmpty else { return nil }
        let vData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let nData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let tData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let stride3 = MemoryLayout<SIMD3<Float>>.stride
        let sources = [
            SCNGeometrySource(data: vData, semantic: .vertex, vectorCount: positions.count, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: stride3),
            SCNGeometrySource(data: nData, semantic: .normal, vectorCount: normals.count, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: stride3),
            SCNGeometrySource(data: tData, semantic: .texcoord, vectorCount: uvs.count, usesFloatComponents: true,
                              componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0,
                              dataStride: MemoryLayout<SIMD2<Float>>.stride),
        ]
        var elements: [SCNGeometryElement] = []
        var used: [SCNMaterial] = []
        for (slot, idx) in indices.enumerated() where !idx.isEmpty {
            let data = idx.withUnsafeBufferPointer { Data(buffer: $0) }
            elements.append(SCNGeometryElement(data: data, primitiveType: .triangles,
                                               primitiveCount: idx.count / 3, bytesPerIndex: 4))
            used.append(materials[slot])
        }
        let g = SCNGeometry(sources: sources, elements: elements)
        g.materials = used
        return g
    }
}
