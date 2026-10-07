import CoreLocation
import SwiftUI

struct Station: Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MetroLine: Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: UInt32
    /// Ordered from the first to the last station of the line.
    let stationIDs: [String]

    var color: Color {
        Color(
            red: Double((colorHex >> 16) & 0xFF) / 255,
            green: Double((colorHex >> 8) & 0xFF) / 255,
            blue: Double(colorHex & 0xFF) / 255
        )
    }

    var stations: [Station] { stationIDs.compactMap { MetroNetwork.stations[$0] } }
    var coordinates: [CLLocationCoordinate2D] { stations.map(\.coordinate) }
    var terminusName: (forward: String, reverse: String) {
        (stations.last?.name ?? "", stations.first?.name ?? "")
    }
}

enum Direction: String {
    case forward, reverse
}

struct Train: Identifiable, Hashable {
    enum Status { case atStation, moving }

    let id: String
    let lineID: String
    let direction: Direction
    let latitude: Double
    let longitude: Double
    let status: Status
    let nextStationID: String
    let destinationName: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Arrival: Identifiable, Hashable {
    let id: String
    let lineID: String
    let direction: Direction
    let destinationName: String
    let time: Date
}

/// Source of train positions and arrivals. `ScheduleFeed` estimates them from
/// the timetable; a real-time implementation can replace it without UI changes.
protocol TrainFeed {
    /// True when positions are derived from a timetable rather than live telemetry.
    var isEstimated: Bool { get }
    func trains(at date: Date) -> [Train]
    func arrivals(at stationID: String, from date: Date, limit: Int) -> [Arrival]
}
