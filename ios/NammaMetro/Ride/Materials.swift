import SceneKit
import UIKit

/// Physically based materials shared by every node in the ride scene. Clones of
/// a train share these instances, so day/night changes apply everywhere at once.
final class MetroMaterials {
    let steel: SCNMaterial
    let roof: SCNMaterial
    let glass: SCNMaterial
    let fascia: SCNMaterial
    let rubber: SCNMaterial
    let underframe: SCNMaterial
    let wheel: SCNMaterial
    let headlight: SCNMaterial
    let taillight: SCNMaterial
    let marker: SCNMaterial
    let concrete: SCNMaterial
    let concreteDark: SCNMaterial
    let rail: SCNMaterial
    let thirdRail: SCNMaterial
    let platform: SCNMaterial
    let tactile: SCNMaterial
    let stationRoof: SCNMaterial
    let stationGlass: SCNMaterial
    let tunnel: SCNMaterial
    private var paints: [UInt32: SCNMaterial] = [:]

    init() {
        let brushed = Self.noiseImage(size: 256, seed: 7, streaks: true)
        let grain = Self.noiseImage(size: 512, seed: 3, streaks: false)

        steel = Self.pbr(UIColor(white: 0.80, alpha: 1), metal: 0.85, rough: 0.30)
        steel.roughness.contents = brushed
        steel.roughness.intensity = 0.35
        steel.roughness.wrapS = .repeat
        steel.roughness.wrapT = .repeat
        steel.roughness.contentsTransform = SCNMatrix4MakeScale(0.4, 4, 1)

        roof = Self.pbr(UIColor(white: 0.70, alpha: 1), metal: 0.5, rough: 0.55)
        glass = Self.pbr(UIColor(white: 0.02, alpha: 1), metal: 0.0, rough: 0.05)
        glass.emission.contents = UIColor(red: 1.0, green: 0.93, blue: 0.80, alpha: 1)
        glass.emission.intensity = 0
        fascia = Self.pbr(UIColor(white: 0.015, alpha: 1), metal: 0.3, rough: 0.08)
        fascia.clearCoat.contents = 1.0
        fascia.clearCoatRoughness.contents = 0.05
        rubber = Self.pbr(UIColor(white: 0.06, alpha: 1), metal: 0, rough: 0.9)
        underframe = Self.pbr(UIColor(white: 0.13, alpha: 1), metal: 0.4, rough: 0.7)
        wheel = Self.pbr(UIColor(white: 0.55, alpha: 1), metal: 1, rough: 0.35)
        headlight = Self.pbr(.white, metal: 0, rough: 0.2)
        headlight.emission.contents = UIColor(red: 1, green: 0.97, blue: 0.9, alpha: 1)
        headlight.emission.intensity = 4
        taillight = Self.pbr(UIColor(red: 0.3, green: 0, blue: 0, alpha: 1), metal: 0, rough: 0.2)
        taillight.emission.contents = UIColor(red: 1, green: 0.08, blue: 0.05, alpha: 1)
        taillight.emission.intensity = 2.5
        marker = Self.pbr(UIColor(red: 0.4, green: 0.2, blue: 0, alpha: 1), metal: 0, rough: 0.2)
        marker.emission.contents = UIColor(red: 1, green: 0.5, blue: 0.05, alpha: 1)
        marker.emission.intensity = 1.5

        concrete = Self.pbr(UIColor(red: 0.74, green: 0.70, blue: 0.63, alpha: 1), metal: 0, rough: 0.92)
        concrete.diffuse.contents = Self.tinted(grain, base: UIColor(red: 0.76, green: 0.71, blue: 0.63, alpha: 1))
        concrete.diffuse.wrapS = .repeat
        concrete.diffuse.wrapT = .repeat
        concreteDark = Self.pbr(UIColor(red: 0.45, green: 0.44, blue: 0.42, alpha: 1), metal: 0, rough: 0.95)
        rail = Self.pbr(UIColor(white: 0.62, alpha: 1), metal: 1, rough: 0.28)
        thirdRail = Self.pbr(UIColor(red: 0.86, green: 0.82, blue: 0.62, alpha: 1), metal: 0, rough: 0.6)
        platform = Self.pbr(UIColor(red: 0.78, green: 0.77, blue: 0.75, alpha: 1), metal: 0, rough: 0.7)
        platform.emission.contents = UIColor(red: 1.0, green: 0.94, blue: 0.84, alpha: 1)
        platform.emission.intensity = 0
        tactile = Self.pbr(UIColor(red: 0.95, green: 0.78, blue: 0.10, alpha: 1), metal: 0, rough: 0.6)
        stationRoof = Self.pbr(UIColor(white: 0.90, alpha: 1), metal: 0.6, rough: 0.4)
        stationRoof.emission.contents = UIColor(red: 1.0, green: 0.94, blue: 0.84, alpha: 1)
        stationRoof.emission.intensity = 0
        stationGlass = Self.pbr(UIColor(red: 0.20, green: 0.28, blue: 0.32, alpha: 1), metal: 0.2, rough: 0.08)
        stationGlass.emission.contents = UIColor(red: 1.0, green: 0.92, blue: 0.78, alpha: 1)
        stationGlass.emission.intensity = 0
        tunnel = Self.pbr(UIColor(red: 0.55, green: 0.54, blue: 0.52, alpha: 1), metal: 0, rough: 0.95)
        tunnel.isDoubleSided = true
    }

    /// Livery paint in a line colour, with a clear coat.
    func paint(_ hex: UInt32) -> SCNMaterial {
        if let m = paints[hex] { return m }
        let color = UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        let m = Self.pbr(color, metal: 0.15, rough: 0.32)
        m.clearCoat.contents = 0.8
        m.clearCoatRoughness.contents = 0.1
        paints[hex] = m
        return m
    }

    /// 0 = full daylight, 1 = night: lights the windows and station glass.
    func setNight(_ amount: CGFloat) {
        glass.emission.intensity = 0.32 * amount
        stationGlass.emission.intensity = 0.7 * amount
        headlight.emission.intensity = 2 + 6 * amount
        platform.emission.intensity = 0.22 * amount
        stationRoof.emission.intensity = 0.12 * amount
    }

    static func pbr(_ color: UIColor, metal: CGFloat, rough: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        return m
    }

    /// Deterministic greyscale noise: soft blotches for concrete, or fine horizontal
    /// streaks for brushed steel.
    static func noiseImage(size: Int, seed: UInt64, streaks: Bool) -> UIImage {
        var state = seed
        func random() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return Double(z ^ (z >> 31)) / Double(UInt64.max)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0.5, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: size, height: size))
            if streaks {
                for _ in 0..<(size * 3) {
                    let y = random() * Double(size)
                    let x = random() * Double(size)
                    let w = 20 + random() * Double(size) * 0.6
                    c.setFillColor(UIColor(white: CGFloat(random()), alpha: 0.18).cgColor)
                    c.fill(CGRect(x: x, y: y, width: w, height: 1))
                    c.fill(CGRect(x: x - Double(size), y: y, width: w, height: 1))
                }
            } else {
                for _ in 0..<1400 {
                    let r = 2 + random() * 26
                    let x = random() * Double(size), y = random() * Double(size)
                    c.setFillColor(UIColor(white: CGFloat(0.3 + random() * 0.4), alpha: 0.10).cgColor)
                    for dx in [-1.0, 0, 1] {
                        for dy in [-1.0, 0, 1] {
                            c.fillEllipse(in: CGRect(x: x - r + dx * Double(size), y: y - r + dy * Double(size),
                                                     width: r * 2, height: r * 2))
                        }
                    }
                }
            }
        }
    }

    /// Multiplies a greyscale noise image onto a base colour.
    static func tinted(_ noise: UIImage, base: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: noise.size, format: format).image { ctx in
            base.setFill()
            ctx.fill(CGRect(origin: .zero, size: noise.size))
            noise.draw(in: CGRect(origin: .zero, size: noise.size), blendMode: .overlay, alpha: 0.9)
        }
    }
}
