import Foundation
import CoreLocation

struct Insight {
    let headline: String          // "Over the Palk Strait"
    let detail: String            // "45 km NNE of Jaffna"
    let nearby: [NearbyItem]
}

struct NearbyItem: Identifiable {
    let id: String
    let name: String
    let kind: String
    let km: Double
    let bearing: Double
    var text: String { "\(name) — \(Int(km.rounded())) km \(GeoMath.compass(bearing))" }
}

/// Turns a raw coordinate into "what am I over / near" using only bundled data.
struct InsightEngine {
    let geo: GeoData

    func insight(at c: CLLocationCoordinate2D) -> Insight {
        let all: [(String, String, CLLocationCoordinate2D)] =
            geo.places.map { ($0.name, "city", $0.coordinate) } +
            geo.features.map { ($0.name, $0.kind, $0.coordinate) }

        let items = all.map { name, kind, coord in
            NearbyItem(id: "\(kind):\(name)", name: name, kind: kind,
                       km: GeoMath.distanceKm(c, coord), bearing: GeoMath.bearing(c, coord))
        }.sorted { $0.km < $1.km }

        let over = geo.isOverLand(c)
        let seaOrLand = items.first { ($0.kind == "sea" && !over && $0.km < 350) || ($0.kind == "land" && over && $0.km < 200) }
        let city = items.first { $0.kind == "city" }

        let headline: String
        if let f = seaOrLand { headline = over ? "Over land near \(f.name)" : "Over \(f.name)" }
        else { headline = over ? "Over land" : "Over open water" }

        let detail: String
        if let city {
            // Direction is *from the city to you*, which is how people say it ("40 km NNE of Jaffna").
            let back = (city.bearing + 180).truncatingRemainder(dividingBy: 360)
            detail = city.km < 5 ? "Right above \(city.name)" : "\(Int(city.km.rounded())) km \(GeoMath.compass(back)) of \(city.name)"
        } else { detail = "No known place within range" }

        return Insight(headline: headline, detail: detail, nearby: Array(items.prefix(8)))
    }
}
