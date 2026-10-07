import SceneKit
import UIKit

/// 3D assets shared by every ride: built once off the main thread (`prewarm`) so
/// tapping a train never stalls the map, and kept for the next ride.
final class RideAssets {
    static let shared = RideAssets()

    let materials = MetroMaterials()
    let factories: [String: TrainFactory]
    let sceneries: [LineScenery]

    private let lock = NSLock()
    private var chunks: [String: SCNNode] = [:]
    private var chunkOrder: [String] = []
    private let maxChunks = 90
    private let tiles = NSCache<NSString, UIImage>()
    private var sky: (key: Int, image: UIImage)?

    /// 8 m cells covered by a track (±14 m) or a station (±26 m): nothing grows there.
    let trackMask: Set<Int64> = {
        var cells = Set<Int64>()
        let size = 8.0
        for track in MetroNetwork.tracks.values {
            for (i, p) in track.points.enumerated() {
                let s = track.cumulative[i]
                let atStation = track.stationDistances.contains { abs($0 - s) < 85 }
                let reach = Int((atStation ? 26.0 : 14.0) / size) + 1
                let cx = Int((p.x / size).rounded(.down)), cy = Int((p.y / size).rounded(.down))
                for dx in -reach...reach {
                    for dy in -reach...reach { cells.insert(Int64(cx + dx) << 32 | Int64(UInt32(bitPattern: Int32(cy + dy)))) }
                }
            }
        }
        return cells
    }()

    func isNearTrack(_ p: SIMD2<Double>) -> Bool {
        let cx = Int((p.x / 8).rounded(.down)), cy = Int((p.y / 8).rounded(.down))
        return trackMask.contains(Int64(cx) << 32 | Int64(UInt32(bitPattern: Int32(cy))))
    }

    private init() {
        var factories: [String: TrainFactory] = [:]
        var sceneries: [LineScenery] = []
        for line in MetroNetwork.lines {
            factories[line.id] = TrainFactory(lineColor: Livery.color(for: line.id), library: materials)
            sceneries.append(LineScenery(line: line, materials: materials))
        }
        self.factories = factories
        self.sceneries = sceneries
        tiles.countLimit = 120
    }

    /// Builds the shared assets and today's sky in the background.
    static func prewarm() {
        DispatchQueue.global(qos: .utility).async {
            _ = shared.skyImage(for: SkyState(date: Date()), date: Date())
        }
    }

    /// A track chunk for one scene: a clone (sharing geometry) of a cached original,
    /// since a node can only live in one scene. Call off the main thread.
    func chunk(_ scenery: LineScenery, _ c: Int) -> SCNNode {
        let key = "\(scenery.line.id)-\(c)"
        lock.lock()
        if let node = chunks[key] { lock.unlock(); return node.clone() }
        lock.unlock()
        let node = scenery.makeChunk(c)
        lock.lock()
        chunks[key] = node
        chunkOrder.append(key)
        if chunkOrder.count > maxChunks { chunks[chunkOrder.removeFirst()] = nil }
        lock.unlock()
        return node.clone()
    }

    func tile(_ key: String) -> UIImage? { tiles.object(forKey: key as NSString) }
    func storeTile(_ image: UIImage, key: String) { tiles.setObject(image, forKey: key as NSString) }

    /// Sky image for the current 10-minute slot (regenerating it takes ~100 ms).
    func skyImage(for state: SkyState, date: Date) -> UIImage {
        let key = Int(date.timeIntervalSince1970 / 600)
        lock.lock()
        if let sky, sky.key == key { lock.unlock(); return sky.image }
        lock.unlock()
        let image = state.skyImage()
        lock.lock()
        sky = (key, image)
        lock.unlock()
        return image
    }

    func cachedSky(for date: Date) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        guard let sky, sky.key == Int(date.timeIntervalSince1970 / 600) else { return nil }
        return sky.image
    }
}
