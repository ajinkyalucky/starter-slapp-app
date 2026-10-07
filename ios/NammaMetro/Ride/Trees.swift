import SceneKit
import simd
import UIKit

/// Tree canopies placed on the green parts of a satellite tile, so the city's
/// real tree cover stands up in 3D.
enum Trees {
    private static let grid = 52   // ~7.7 m cells on a 400 m tile

    static func node(from image: UIImage, tileMeters: Float, center: SIMD2<Double>, seed: Int) -> SCNNode? {
        guard let pixels = sample(image) else { return nil }
        let library = RideAssets.shared.materials
        let materials = library.foliage + [library.bark]
        let barkSlot = materials.count - 1
        var mesh = MeshBuilder(slots: materials.count)
        var rng = UInt64(bitPattern: Int64(seed)) | 1
        func random() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float(rng >> 40) / Float(1 << 24)
        }
        let cell = tileMeters / Float(grid)
        var count = 0
        for y in 0..<grid {
            for x in 0..<grid {
                let i = (y * grid + x) * 4
                let r = Float(pixels[i]), g = Float(pixels[i + 1]), b = Float(pixels[i + 2])
                // Vegetation: green clearly above red and blue, not too bright (lawns, crops) or dark (shadow).
                guard g > r * 1.06, g > b * 1.12, g > 38, g < 150 else { continue }
                guard random() < 0.75 else { continue }
                let brightness = (r + g + b) / 3
                let slot = min(library.foliage.count - 1, max(0, Int((brightness - 30) / 22)))
                let px = (Float(x) + 0.15 + random() * 0.7) * cell - tileMeters / 2
                let pz = (Float(y) + 0.15 + random() * 0.7) * cell - tileMeters / 2
                // Keep the viaduct and stations clear.
                guard !RideAssets.shared.isNearTrack(center + SIMD2(Double(px), Double(pz))) else { continue }
                // Rain-tree shape: a wide, flattish crown on a short trunk, plus a second clump.
                let h = 6 + random() * 8
                let radius = 2.8 + random() * 2.6
                let crownY = h * 0.70
                mesh.cylinder(barkSlot, center: [px, crownY * 0.5, pz], axis: [0, 1, 0], radius: 0.22 + radius * 0.04,
                              halfLength: crownY * 0.5, segments: 6)
                mesh.ellipsoid(slot, center: [px, crownY, pz], radii: [radius, h * 0.30, radius * (0.85 + random() * 0.3)])
                let angle = random() * 2 * .pi
                let offset = SIMD2<Float>(cos(angle), sin(angle)) * radius * 0.55
                mesh.ellipsoid(min(slot + 1, library.foliage.count - 1),
                               center: [px + offset.x, crownY + h * 0.08, pz + offset.y],
                               radii: [radius * 0.62, h * 0.22, radius * 0.62], segments: 6, rings: 4)
                count += 1
            }
        }
        guard count > 0, let g = mesh.geometry(materials: materials) else { return nil }
        g.levelsOfDetail = [SCNLevelOfDetail(geometry: nil, worldSpaceDistance: 900)]
        let node = SCNNode(geometry: g)
        node.name = "trees"
        node.castsShadow = true
        return node
    }

    /// The image averaged down to grid × grid RGBA pixels (row 0 = north edge).
    private static func sample(_ image: UIImage) -> [UInt8]? {
        guard let cg = image.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: grid * grid * 4)
        let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: grid, height: grid, bitsPerComponent: 8,
                                      bytesPerRow: grid * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: grid, height: grid))
            return true
        }
        return ok ? pixels : nil
    }
}
