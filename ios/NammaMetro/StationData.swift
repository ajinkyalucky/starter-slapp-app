import Foundation

/// Station order per line. Only some stations carry coordinates ("anchors");
/// the rest are interpolated along the line, so map positions between anchors
/// are APPROXIMATE. Replace with surveyed coordinates from a GTFS `stops.txt`
/// (e.g. the unofficial BMRCL GTFS dataset) before shipping.
private struct Seed {
    let name: String
    let lat: Double?
    let lon: Double?
    init(_ name: String, _ lat: Double? = nil, _ lon: Double? = nil) {
        self.name = name
        self.lat = lat
        self.lon = lon
    }
    var id: String {
        name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    }
}

private let purpleSeeds: [Seed] = [
    Seed("Whitefield (Kadugodi)", 12.9958, 77.7575),
    Seed("Hopefarm Channasandra"), Seed("Kadugodi Tree Park"), Seed("Pattandur Agrahara"),
    Seed("Sri Sathya Sai Hospital"), Seed("Nallurhalli"), Seed("Kundalahalli"),
    Seed("Seetharamapalya"), Seed("Hoodi", 12.9922, 77.7157), Seed("Garudacharpalya"),
    Seed("Singayyanapalya"), Seed("KR Puram", 13.0011, 77.6963), Seed("Benniganahalli"),
    Seed("Baiyappanahalli", 12.9907, 77.6522), Seed("Swami Vivekananda Road"),
    Seed("Indiranagar", 12.9783, 77.6386), Seed("Halasuru"), Seed("Trinity"),
    Seed("MG Road", 12.9756, 77.6067), Seed("Cubbon Park"),
    Seed("Vidhana Soudha"), Seed("Sir M. Visvesvaraya"),
    Seed("Majestic", 12.9757, 77.5728), Seed("City Railway Station"), Seed("Magadi Road"),
    Seed("Hosahalli"), Seed("Vijayanagar", 12.9709, 77.5300), Seed("Attiguppe"),
    Seed("Deepanjali Nagar"), Seed("Mysuru Road", 12.9467, 77.5300), Seed("Nayandahalli"),
    Seed("Rajarajeshwari Nagar"), Seed("Jnanabharathi"), Seed("Pattanagere"),
    Seed("Kengeri Bus Terminal"), Seed("Kengeri", 12.9150, 77.4833),
    Seed("Challaghatta", 12.8977, 77.4604),
]

private let greenSeeds: [Seed] = [
    Seed("Madavara", 13.0570, 77.4720),
    Seed("Chikkabidarakallu"), Seed("Manjunathanagara"), Seed("Nagasandra", 13.0480, 77.5000),
    Seed("Dasarahalli"), Seed("Jalahalli"), Seed("Peenya Industry"), Seed("Peenya"),
    Seed("Goraguntepalya"), Seed("Yeshwanthpur", 13.0235, 77.5497),
    Seed("Sandal Soap Factory"), Seed("Mahalakshmi"), Seed("Rajajinagar"),
    Seed("Kuvempu Road"), Seed("Srirampura"), Seed("Mantri Square Sampige Road"),
    Seed("Majestic", 12.9757, 77.5728), Seed("Chickpete"), Seed("Krishna Rajendra Market"),
    Seed("National College"), Seed("Lalbagh"), Seed("South End Circle"),
    Seed("Jayanagar", 12.9296, 77.5800), Seed("Rashtreeya Vidyalaya Road"),
    Seed("Banashankari", 12.9156, 77.5733), Seed("Jaya Prakash Nagar"),
    Seed("Yelachenahalli"), Seed("Konanakunte Cross"), Seed("Doddakallasandra"),
    Seed("Vajarahalli"), Seed("Thalaghattapura"), Seed("Silk Institute", 12.8620, 77.5260),
]

private let yellowSeeds: [Seed] = [
    Seed("Rashtreeya Vidyalaya Road", 12.9208, 77.5805),
    Seed("Ragigudda"), Seed("Jayadeva Hospital"), Seed("BTM Layout"),
    Seed("Central Silk Board", 12.9170, 77.6226), Seed("Bommanahalli"), Seed("Hongasandra"),
    Seed("Kudlu Gate"), Seed("Singasandra"), Seed("Hosa Road"), Seed("Beratena Agrahara"),
    Seed("Electronics City", 12.8490, 77.6700), Seed("Konappana Agrahara"),
    Seed("Huskur Road"), Seed("Hebbagodi"), Seed("Bommasandra", 12.8160, 77.6780),
]

enum MetroNetwork {
    static let lines: [MetroLine] = built.lines
    static let stations: [String: Station] = built.stations

    private static let built: (lines: [MetroLine], stations: [String: Station]) = {
        let definitions: [(id: String, name: String, hex: UInt32, seeds: [Seed])] = [
            ("purple", "Purple Line", 0x7B2D8E, purpleSeeds),
            ("green", "Green Line", 0x00A651, greenSeeds),
            ("yellow", "Yellow Line", 0xF6B800, yellowSeeds),
        ]
        var stations: [String: Station] = [:]
        var lines: [MetroLine] = []
        for def in definitions {
            let resolved = interpolate(def.seeds)
            for (seed, coord) in zip(def.seeds, resolved) {
                // Surveyed anchors win over interpolated values from another line.
                if stations[seed.id] == nil || seed.lat != nil {
                    stations[seed.id] = Station(
                        id: seed.id, name: seed.name,
                        latitude: coord.lat, longitude: coord.lon)
                }
            }
            lines.append(
                MetroLine(
                    id: def.id, name: def.name, colorHex: def.hex,
                    stationIDs: def.seeds.map(\.id)))
        }
        return (lines, stations)
    }()

    private static func interpolate(_ seeds: [Seed]) -> [(lat: Double, lon: Double)] {
        let anchors = seeds.indices.filter { seeds[$0].lat != nil }
        precondition(anchors.first == 0 && anchors.last == seeds.count - 1,
                     "First and last station of a line need coordinates")
        var out = [(lat: Double, lon: Double)](repeating: (0, 0), count: seeds.count)
        for (a, b) in zip(anchors, anchors.dropFirst()) {
            let (la, lo) = (seeds[a].lat!, seeds[a].lon!)
            let (lb, lob) = (seeds[b].lat!, seeds[b].lon!)
            for i in a...b {
                let t = Double(i - a) / Double(b - a)
                out[i] = (la + (lb - la) * t, lo + (lob - lo) * t)
            }
        }
        return out
    }
}
