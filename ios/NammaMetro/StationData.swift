import CoreLocation
import Foundation

/// Station names per line, in line order. Positions and track geometry come from
/// OpenStreetMap via Resources/metro_track.json (tools/build_track.py); the stop
/// order there must match these lists.
private let purpleNames = [
    "Whitefield (Kadugodi)", "Hopefarm Channasandra", "Kadugodi Tree Park", "Pattandur Agrahara",
    "Sri Sathya Sai Hospital", "Nallurhalli", "Kundalahalli", "Seetharamapalya", "Hoodi",
    "Garudacharpalya", "Singayyanapalya", "KR Puram", "Benniganahalli", "Baiyappanahalli",
    "Swami Vivekananda Road", "Indiranagar", "Halasuru", "Trinity", "MG Road", "Cubbon Park",
    "Vidhana Soudha", "Sir M. Visvesvaraya", "Majestic", "City Railway Station", "Magadi Road",
    "Hosahalli", "Vijayanagar", "Attiguppe", "Deepanjali Nagar", "Mysuru Road", "Nayandahalli",
    "Rajarajeshwari Nagar", "Jnanabharathi", "Pattanagere", "Kengeri Bus Terminal", "Kengeri",
    "Challaghatta",
]

private let greenNames = [
    "Madavara", "Chikkabidarakallu", "Manjunathanagara", "Nagasandra", "Dasarahalli", "Jalahalli",
    "Peenya Industry", "Peenya", "Goraguntepalya", "Yeshwanthpur", "Sandal Soap Factory",
    "Mahalakshmi", "Rajajinagar", "Kuvempu Road", "Srirampura", "Mantri Square Sampige Road",
    "Majestic", "Chickpete", "Krishna Rajendra Market", "National College", "Lalbagh",
    "South End Circle", "Jayanagar", "Rashtreeya Vidyalaya Road", "Banashankari",
    "Jaya Prakash Nagar", "Yelachenahalli", "Konanakunte Cross", "Doddakallasandra", "Vajarahalli",
    "Thalaghattapura", "Silk Institute",
]

private let yellowNames = [
    "Rashtreeya Vidyalaya Road", "Ragigudda", "Jayadeva Hospital", "BTM Layout",
    "Central Silk Board", "Bommanahalli", "Hongasandra", "Kudlu Gate", "Singasandra", "Hosa Road",
    "Beratena Agrahara", "Electronics City", "Konappana Agrahara", "Huskur Road", "Hebbagodi",
    "Bommasandra",
]

private func stationID(_ name: String) -> String {
    name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
}

enum MetroNetwork {
    static let lines: [MetroLine] = built.lines
    static let stations: [String: Station] = built.stations
    static let tracks: [String: TrackGeometry] = built.tracks
    static let attribution: String = built.attribution

    static func line(_ id: String) -> MetroLine? { lines.first { $0.id == id } }

    private static let built: (lines: [MetroLine], stations: [String: Station], tracks: [String: TrackGeometry], attribution: String) = {
        let definitions: [(id: String, name: String, hex: UInt32, names: [String])] = [
            ("purple", "Purple Line", 0x7B2D8E, purpleNames),
            ("green", "Green Line", 0x00A651, greenNames),
            ("yellow", "Yellow Line", 0xF6B800, yellowNames),
        ]
        let file = TrackFile.load()
        var stations: [String: Station] = [:]
        var lines: [MetroLine] = []
        var tracks: [String: TrackGeometry] = [:]
        for def in definitions {
            guard let data = file.lines.first(where: { $0.id == def.id }) else {
                fatalError("metro_track.json has no \(def.id) line")
            }
            precondition(data.stations.count == def.names.count,
                         "\(def.id): \(data.stations.count) stops in metro_track.json, \(def.names.count) names")
            let track = TrackGeometry(
                lineID: def.id,
                coordinates: zip(data.lat, data.lon).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) },
                deck: data.deck,
                stationIndices: data.stations.map(\.trackIndex))
            tracks[def.id] = track
            for (name, s) in zip(def.names, track.stationDistances) {
                let id = stationID(name)
                // Interchanges keep the position from the first line that lists them.
                if stations[id] == nil {
                    let c = track.coordinate(at: s)
                    stations[id] = Station(id: id, name: name, latitude: c.latitude, longitude: c.longitude)
                }
            }
            lines.append(MetroLine(id: def.id, name: def.name, colorHex: def.hex, stationIDs: def.names.map(stationID)))
        }
        return (lines, stations, tracks, file.attribution)
    }()
}
