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

    var color: Color { Color(uiColor) }

    var uiColor: UIColor {
        UIColor(
            red: CGFloat((colorHex >> 16) & 0xFF) / 255,
            green: CGFloat((colorHex >> 8) & 0xFF) / 255,
            blue: CGFloat(colorHex & 0xFF) / 255,
            alpha: 1)
    }

    var stations: [Station] { stationIDs.compactMap { MetroNetwork.stations[$0] } }
    var track: TrackGeometry { MetroNetwork.tracks[id]! }
    /// Track alignment for drawing on the map, thinned to every fourth sample.
    var coordinates: [CLLocationCoordinate2D] {
        let all = track.coordinates
        return stride(from: 0, to: all.count, by: 4).map { all[$0] } + [all[all.count - 1]]
    }
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
    /// Station the train is at (when `atStation`) or heading to.
    let nextStationID: String
    let destinationName: String
    /// Train centre in metres along the line's track (`TrackGeometry`), forward direction.
    let distance: Double
    /// Metres per second.
    let speed: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Arrival: Identifiable, Hashable {
    let id: String
    let tripID: String
    let lineID: String
    let direction: Direction
    let destinationName: String
    let time: Date
}

/// One scheduled call of a trip at a station.
struct TripStop: Hashable {
    let stationID: String
    let arrive: Date
    let depart: Date
}

/// Source of train positions and arrivals. `ScheduleFeed` estimates them from
/// the timetable; a real-time implementation can replace it without UI changes.
protocol TrainFeed {
    /// True when positions are derived from a timetable rather than live telemetry.
    var isEstimated: Bool { get }
    func trains(at date: Date) -> [Train]
    func arrivals(at stationID: String, from date: Date, limit: Int) -> [Arrival]
    /// Every stop of a trip (`Train.id` / `Arrival.tripID`) in travel order; empty if unknown.
    func stops(ofTrip tripID: String) -> [TripStop]
}
