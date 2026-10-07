import Foundation
import simd
import UIKit

/// Sun position over Bengaluru and the matching sky colours.
struct SkyState {
    /// Unit vector toward the sun in scene space (x east, y up, z south).
    let sunDirection: SIMD3<Float>
    let sunElevation: Double   // radians
    /// 0 in daylight, 1 at night (sun more than ~6° below the horizon).
    let night: Float
    let zenith: SIMD3<Float>
    let horizon: SIMD3<Float>
    let sunColor: SIMD3<Float>

    init(date: Date, latitude: Double = 12.97, longitude: Double = 77.59) {
        // Low-precision solar position (NOAA / Astronomical Almanac approximation).
        let n = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        let rad = Double.pi / 180
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = (357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360) * rad
        let lambda = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let epsilon = (23.439 - 0.0000004 * n) * rad
        let ra = atan2(cos(epsilon) * sin(lambda), cos(lambda))
        let dec = asin(sin(epsilon) * sin(lambda))
        let gmst = (18.697374558 + 24.06570982441908 * n).truncatingRemainder(dividingBy: 24)
        let hourAngle = (gmst * 15 + longitude) * rad - ra
        let phi = latitude * rad
        let elevation = asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(hourAngle))
        let azimuth = atan2(-sin(hourAngle), tan(dec) * cos(phi) - sin(phi) * cos(hourAngle))

        sunElevation = elevation
        sunDirection = simd_normalize(SIMD3(Float(sin(azimuth) * cos(elevation)), Float(sin(elevation)),
                                            Float(-cos(azimuth) * cos(elevation))))
        let e = Float(sin(elevation))
        night = min(max((0.05 - e) / 0.15, 0), 1)
        let dusk = min(max(1 - abs(e - 0.02) / 0.2, 0), 1)

        let dayZenith = SIMD3<Float>(0.22, 0.44, 0.80), dayHorizon = SIMD3<Float>(0.74, 0.82, 0.90)
        let duskZenith = SIMD3<Float>(0.24, 0.30, 0.52), duskHorizon = SIMD3<Float>(0.98, 0.66, 0.44)
        let nightZenith = SIMD3<Float>(0.015, 0.02, 0.05), nightHorizon = SIMD3<Float>(0.09, 0.075, 0.09)
        var z = simd_mix(dayZenith, duskZenith, SIMD3(repeating: dusk))
        var h = simd_mix(dayHorizon, duskHorizon, SIMD3(repeating: dusk))
        z = simd_mix(z, nightZenith, SIMD3(repeating: night))
        h = simd_mix(h, nightHorizon, SIMD3(repeating: night))
        zenith = z
        horizon = h
        sunColor = simd_mix(SIMD3(1.0, 0.97, 0.92), SIMD3(1.0, 0.62, 0.38), SIMD3(repeating: dusk))
    }

    var horizonColor: UIColor { UIColor(red: CGFloat(horizon.x), green: CGFloat(horizon.y), blue: CGFloat(horizon.z), alpha: 1) }
    var sunUIColor: UIColor { UIColor(red: CGFloat(sunColor.x), green: CGFloat(sunColor.y), blue: CGFloat(sunColor.z), alpha: 1) }

    /// Equirectangular sky (width 2:1) for the scene background and image-based lighting.
    func skyImage(width: Int = 1024) -> UIImage {
        let w = width, h = width / 2
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let el = (0.5 - (Float(y) + 0.5) / Float(h)) * .pi   // +pi/2 at top
            for x in 0..<w {
                // Longitude: image centre looks down -z (north) in SceneKit's convention.
                let lon = (Float(x) + 0.5) / Float(w) * 2 * .pi - .pi
                let dir = SIMD3<Float>(sin(lon) * cos(el), sin(el), -cos(lon) * cos(el))
                var c: SIMD3<Float>
                // Below the horizon matches the fog colour, so distant ground fades into it.
                c = el >= 0 ? simd_mix(horizon, zenith, SIMD3(repeating: pow(sin(el), 0.45))) : horizon
                let cosSun = simd_dot(dir, sunDirection)
                if night < 1 {
                    let glow = pow(max(cosSun, 0), 24) * 0.35 + pow(max(cosSun, 0), 900) * 6
                    c += sunColor * glow * (1 - night)
                }
                let i = (y * w + x) * 4
                pixels[i] = UInt8(min(c.x, 1) * 255)
                pixels[i + 1] = UInt8(min(c.y, 1) * 255)
                pixels[i + 2] = UInt8(min(c.z, 1) * 255)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: image)
    }
}
