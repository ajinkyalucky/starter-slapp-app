import MapKit
import SceneKit
import UIKit

/// Satellite imagery under the scene, fetched as MapKit snapshots in square tiles
/// around the camera. Tiles are aligned to `MetroWorld`, so the OSM track sits on
/// the real streets.
final class GroundTiles {
    let root = SCNNode()
    private let tileMeters: Double = 640
    private let radius = 2
    private let maxInFlight = 4
    private var tiles: [Key: SCNNode] = [:]
    private var inFlight: Set<Key> = []
    private let base: SCNNode
    private let baseMaterial: SCNMaterial
    private var tileMaterials: [Key: SCNMaterial] = [:]
    private var brightness: CGFloat = 1
    private var opacity: CGFloat = 1

    private struct Key: Hashable { let i: Int, j: Int }

    init() {
        baseMaterial = SCNMaterial()
        baseMaterial.lightingModel = .physicallyBased
        baseMaterial.diffuse.contents = UIColor(red: 0.36, green: 0.36, blue: 0.31, alpha: 1)
        baseMaterial.roughness.contents = 1.0
        let plane = SCNPlane(width: 90_000, height: 90_000)
        plane.materials = [baseMaterial]
        base = SCNNode(geometry: plane)
        base.simdEulerAngles = [-.pi / 2, 0, 0]
        base.simdPosition = [0, -0.06, 0]
        root.addChildNode(base)
    }

    /// Call on the main thread whenever the focus moves noticeably.
    func update(focus: SIMD2<Double>) {
        let ci = Int(floor(focus.x / tileMeters)), cj = Int(floor(focus.y / tileMeters))
        for (key, node) in tiles where abs(key.i - ci) > radius + 1 || abs(key.j - cj) > radius + 1 {
            node.removeFromParentNode()
            tiles[key] = nil
            tileMaterials[key] = nil
        }
        var wanted: [Key] = []
        for di in -radius...radius {
            for dj in -radius...radius {
                let k = Key(i: ci + di, j: cj + dj)
                if tiles[k] == nil && !inFlight.contains(k) { wanted.append(k) }
            }
        }
        wanted.sort { abs($0.i - ci) + abs($0.j - cj) < abs($1.i - ci) + abs($1.j - cj) }
        for k in wanted.prefix(max(0, maxInFlight - inFlight.count)) { request(k) }
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
        inFlight.insert(k)
        let origin = MetroWorld.mapPoint(SIMD2(Double(k.i) * tileMeters, Double(k.j) * tileMeters))
        let span = tileMeters / MetroWorld.metersPerMapPoint
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
                self.addTile(k, image: image)
            }
        }
    }

    private func addTile(_ k: Key, image: UIImage) {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = image
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 8
        m.roughness.contents = 0.95
        m.metalness.contents = 0.0
        apply(m)
        let plane = SCNPlane(width: tileMeters, height: tileMeters)
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.simdEulerAngles = [-.pi / 2, 0, 0]
        node.simdPosition = [Float((Double(k.i) + 0.5) * tileMeters), 0, Float((Double(k.j) + 0.5) * tileMeters)]
        node.opacity = 0
        root.addChildNode(node)
        node.runAction(.fadeIn(duration: 0.6))
        tiles[k] = node
        tileMaterials[k] = m
    }
}
