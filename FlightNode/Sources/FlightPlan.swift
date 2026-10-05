import Foundation
import CoreLocation

struct Airport {
    let code: String
    let city: String
    let coordinate: CLLocationCoordinate2D
}

/// A single flight leg the user pre-loads before going offline.
struct FlightPlan: Identifiable {
    let id: String
    let flightNumber: String
    let from: Airport
    let to: Airport
    let note: String

    var totalKm: Double { GeoMath.distanceKm(from.coordinate, to.coordinate) }

    static let blr = Airport(code: "BLR", city: "Bengaluru", coordinate: .init(latitude: 13.1989, longitude: 77.7068))
    static let cmb = Airport(code: "CMB", city: "Colombo", coordinate: .init(latitude: 7.1808, longitude: 79.8841))

    // Schedules are from public listings (check the airline app/e-ticket before you fly).
    static let outbound = FlightPlan(id: "UL174", flightNumber: "UL 174", from: blr, to: cmb,
                                     note: "Thu 8 Oct 2026 · dep ~02:55 IST, arr ~04:20 Sri Lanka time")
    static let inbound = FlightPlan(id: "UL1173", flightNumber: "UL 1173", from: cmb, to: blr,
                                    note: "Fri 16 Oct 2026 · dep ~07:20, arr ~08:40 IST")
    static let all = [outbound, inbound]
}

struct FlightProgress {
    let distanceDoneKm: Double
    let distanceLeftKm: Double
    let offRouteKm: Double
    let fraction: Double
    let etaMinutes: Double?   // nil when speed is too low to estimate
}

extension FlightPlan {
    func progress(at c: CLLocationCoordinate2D, speedKmh: Double) -> FlightProgress {
        let (along, cross) = GeoMath.alongAndCrossTrack(from: from.coordinate, to: to.coordinate, point: c)
        let done = max(0, min(totalKm, along))
        let left = GeoMath.distanceKm(c, to.coordinate)
        let eta = speedKmh > 150 ? left / speedKmh * 60 : nil
        return FlightProgress(distanceDoneKm: done, distanceLeftKm: left, offRouteKm: cross,
                              fraction: totalKm > 0 ? done / totalKm : 0, etaMinutes: eta)
    }
}
