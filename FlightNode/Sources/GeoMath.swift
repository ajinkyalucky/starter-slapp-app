import Foundation
import CoreLocation

/// Pure geodesy helpers (spherical earth, good to ~0.5% — plenty for "what am I over").
enum GeoMath {
    static let earthRadiusKm = 6371.0088

    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// Great-circle distance in km.
    static func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dLat = rad(b.latitude - a.latitude), dLon = rad(b.longitude - a.longitude)
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(rad(a.latitude)) * cos(rad(b.latitude)) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from a to b, 0..<360 degrees.
    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dLon = rad(b.longitude - a.longitude)
        let y = sin(dLon) * cos(rad(b.latitude))
        let x = cos(rad(a.latitude)) * sin(rad(b.latitude))
            - sin(rad(a.latitude)) * cos(rad(b.latitude)) * cos(dLon)
        return (deg(atan2(y, x)) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Point reached from `a` travelling `km` along `bearing` degrees.
    static func destination(from a: CLLocationCoordinate2D, bearing: Double, km: Double) -> CLLocationCoordinate2D {
        let d = km / earthRadiusKm, brg = rad(bearing)
        let lat1 = rad(a.latitude), lon1 = rad(a.longitude)
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brg))
        let lon2 = lon1 + atan2(sin(brg) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: deg(lat2), longitude: deg(lon2))
    }

    /// Intermediate point on the great circle a→b at fraction f (0...1).
    static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ f: Double) -> CLLocationCoordinate2D {
        let total = distanceKm(a, b)
        if total < 1e-6 { return a }
        return destination(from: a, bearing: bearing(a, b), km: total * f)
    }

    /// Distance travelled along a→b (km) for the point p, plus how far off the line it is (km, signed).
    static func alongAndCrossTrack(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, point p: CLLocationCoordinate2D) -> (along: Double, cross: Double) {
        let d13 = distanceKm(a, p) / earthRadiusKm
        let t13 = rad(bearing(a, p)), t12 = rad(bearing(a, b))
        let cross = asin(sin(d13) * sin(t13 - t12))
        let along = acos(max(-1, min(1, cos(d13) / max(1e-12, cos(cross)))))
        return (along * earthRadiusKm, cross * earthRadiusKm)
    }

    /// "NNE", "SW" ... for a bearing in degrees.
    static func compass(_ bearing: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let i = Int(((bearing + 11.25).truncatingRemainder(dividingBy: 360)) / 22.5)
        return names[(i + 16) % 16]
    }

    /// Ray-casting point-in-polygon on (lon, lat) rings.
    static func contains(ring: [[Double]], lat: Double, lon: Double) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let (xi, yi) = (ring[i][0], ring[i][1]), (xj, yj) = (ring[j][0], ring[j][1])
            if (yi > lat) != (yj > lat), lon < (xj - xi) * (lat - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }
}
