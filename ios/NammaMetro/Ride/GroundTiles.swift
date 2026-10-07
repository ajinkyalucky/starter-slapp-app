import MapKit
import SceneKit
import UIKit

/// Satellite imagery under the scene, fetched as MapKit snapshots in square tiles
/// around the camera at two levels of detail: sharp 400 m tiles (~0.4 m/pixel)
/// near the train and 1.6 km tiles further out. Tiles are aligned to
/// `MetroWorld`, so the OSM track sits on the real streets.
final class GroundTiles {
    private struct Level {
        let meters: Double
        let radius: Int
        /// Coarse tiles sit lower so the fine ones win without z-fighting.
        let y: Float
    }

    private struct Key: Hashable { let level: Int, i: Int, j: Int }

    let root = SCNNode()
    private let levels = [Level(meters: 400, radius: 2, y: 0), Level(meters: 1600, radius: 1, y: -1.0)]
    private let maxInFlight = 5
    private var tiles: [Key: SCNNode] = [:]
    private var inFlight: Set<Key> = []
    private let baseMaterial: SCNMaterial
    private var tileMaterials: [Key: SCNMaterial] = [:]
    private var brightness: CGFloat = 1
    private var opacity: CGFloat = 1

    init() {
        baseMaterial = SCNMaterial()
        baseMaterial.lightingModel = .physicallyBased
        baseMaterial.diffuse.contents = UIColor(red: 0.36, green: 0.36, blue: 0.31, alpha: 1)
        baseMaterial.roughness.contents = 1.0
        let plane = SCNPlane(width: 90_000, height: 90_000)
        plane.materials = [baseMaterial]
        let base = SCNNode(geometry: plane)
        base.simdEulerAngles = [-.pi / 2, 0, 0]
        base.simdPosition = [0, -2, 0]
        root.addChildNode(base)
    }

    /// True once the sharp tiles right around the focus are in.
    var nearGroundLoaded: Bool {
        tiles.keys.filter { $0.level == 0 }.count >= 9 && tiles.keys.contains { $0.level == 1 }
    }

    /// Call on the main thread whenever the focus moves noticeably.
    func update(focus: SIMD2<Double>) {
        var wanted: [(key: Key, rank: Int)] = []
        for (li, level) in levels.enumerated() {
            let ci = Int(floor(focus.x / level.meters)), cj = Int(floor(focus.y / level.meters))
            for (key, node) in tiles where key.level == li && (abs(key.i - ci) > level.radius + 1 || abs(key.j - cj) > level.radius + 1) {
                node.removeFromParentNode()
                tiles[key] = nil
                tileMaterials[key] = nil
            }
            for di in -level.radius...level.radius {
                for dj in -level.radius...level.radius {
                    let k = Key(level: li, i: ci + di, j: cj + dj)
                    if tiles[k] == nil && !inFlight.contains(k) {
                        // Nearest sharp tiles first, then the coarse ring.
                        wanted.append((k, li * 10 + max(abs(di), abs(dj)) * (li == 0 ? 2 : 1)))
                    }
                }
            }
        }
        for w in wanted.sorted(by: { $0.rank < $1.rank }).prefix(max(0, maxInFlight - inFlight.count)) {
            request(w.key)
        }
    }

    /// Dims the imagery at night and fades it for the underground x-ray view.
    func setAppearance(brightness: CGFloat, opacity: CGFloat) {
        guard abs(brightness - self.brightness) > 0.01 || abs(opacity - self.opacity) > 0.01 else { return }
        self.brightness = brightness
        self.opacity = opacity
        for m in tileMaterials.values { apply(m) }
        baseMaterial.multiply.contents = UIColor(white: brightness, alpha: 1)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.8
        root.opacity = opacity
        SCNTransaction.commit()
    }

    private func apply(_ m: SCNMaterial) {
        m.multiply.contents = UIColor(white: brightness, alpha: 1)
    }

    private func request(_ k: Key) {
        let level = levels[k.level]
        let cacheKey = "\(k.level):\(k.i),\(k.j)"
        if let image = RideAssets.shared.tile(cacheKey) {
            addTile(k, image: image)
            return
        }
        inFlight.insert(k)
        let origin = MetroWorld.mapPoint(SIMD2(Double(k.i) * level.meters, Double(k.j) * level.meters))
        let span = level.meters / MetroWorld.metersPerMapPoint
        let options = MKMapSnapshotter.Options()
        options.mapRect = MKMapRect(origin: origin, size: MKMapSize(width: span, height: span))
        options.size = CGSize(width: 1024, height: 1024)
        options.traitCollection = UITraitCollection(displayScale: 1)
        options.preferredConfiguration = MKImageryMapConfiguration()
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start(with: .global(qos: .userInitiated)) { [weak self] snapshot, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(k)
                guard let image = snapshot?.image else { return }
                RideAssets.shared.storeTile(image, key: cacheKey)
                self.addTile(k, image: image)
            }
        }
    }

    private func addTile(_ k: Key, image: UIImage) {
        let level = levels[k.level]
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = image
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 16
        m.roughness.contents = 0.95
        m.metalness.contents = 0.0
        apply(m)
        let plane = SCNPlane(width: level.meters, height: level.meters)
        plane.materials = [m]
        let ground = SCNNode(geometry: plane)
        ground.simdEulerAngles = [-.pi / 2, 0, 0]
        let node = SCNNode()
        node.simdPosition = [Float((Double(k.i) + 0.5) * level.meters), level.y, Float((Double(k.j) + 0.5) * level.meters)]
        node.addChildNode(ground)
        node.opacity = 0
        if k.level == 0 {
            // Grow trees where the imagery is green (off the main thread).
            let meters = Float(level.meters), seed = k.i &* 73856093 ^ k.j &* 19349663
            let center = SIMD2((Double(k.i) + 0.5) * level.meters, (Double(k.j) + 0.5) * level.meters)
            DispatchQueue.global(qos: .utility).async { [weak node] in
                guard let trees = Trees.node(from: image, tileMeters: meters, center: center, seed: seed) else { return }
                DispatchQueue.main.async { node?.addChildNode(trees) }
            }
        }
        root.addChildNode(node)
        node.runAction(.fadeIn(duration: 0.6))
        tiles[k] = node
        tileMaterials[k] = m
    }
}
