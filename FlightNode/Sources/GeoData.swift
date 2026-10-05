import Foundation
import CoreLocation

/// Offline geography bundled in the app (built by tools/build-data.mjs from Natural Earth).
struct GeoData: Decodable {
    struct BBox: Decodable { let minLat, maxLat, minLon, maxLon: Double }
    struct Place: Decodable, Identifiable {
        let name: String
        let lat: Double
        let lon: Double
        let pop: Int
        let country: String
        var id: String { "\(name)@\(lat),\(lon)" }
        var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    }
    struct Feature: Decodable, Identifiable {
        let name: String
        let kind: String   // airport | sea | land | landmark
        let lat: Double
        let lon: Double
        var id: String { name }
        var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    }

    let bbox: BBox
    let land: [[[Double]]]   // rings of [lon, lat]
    let places: [Place]
    let features: [Feature]

    static func load() -> GeoData {
        guard let url = Bundle.main.url(forResource: "geo", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let geo = try? JSONDecoder().decode(GeoData.self, from: data) else {
            fatalError("geo.json missing from app bundle — run tools/build-data.mjs and add it to the target")
        }
        return geo
    }

    func isOverLand(_ c: CLLocationCoordinate2D) -> Bool {
        land.contains { GeoMath.contains(ring: $0, lat: c.latitude, lon: c.longitude) }
    }
}
