import Foundation

/// One ride on one train, from boarding to alighting.
struct JourneyLeg: Identifiable, Hashable, Codable {
    let lineID: String
    let tripID: String
    /// Terminus the train is heading to ("Towards …" on the platform boards).
    let towards: String
    let fromID: String
    let toID: String

    var id: String { "\(tripID)/\(fromID)" }
    var line: MetroLine? { MetroNetwork.line(lineID) }
}

/// A planned trip. Times are not stored: they are read from the feed each time
/// (`JourneyTimes`) so a calibration shifts a planned journey too.
struct Journey: Identifiable, Hashable, Codable {
    let legs: [JourneyLeg]
    /// Token/QR fare in rupees.
    let fare: Int
    let distance: Double

    var id: String { legs.map(\.id).joined(separator: "|") }
    var fromID: String { legs.first!.fromID }
    var toID: String { legs.last!.toID }
    var transfers: Int { legs.count - 1 }
}

/// A leg with its stop times, as the feed currently estimates them.
struct TimedLeg: Hashable {
    let leg: JourneyLeg
    /// Stops from boarding to alighting, inclusive.
    let stops: [TripStop]

    var depart: Date { stops.first!.depart }
    var arrive: Date { stops.last!.arrive }
}

struct JourneyTimes: Hashable {
    let legs: [TimedLeg]

    var depart: Date { legs.first!.depart }
    var arrive: Date { legs.last!.arrive }
    var duration: TimeInterval { arrive.timeIntervalSince(depart) }

    init(legs: [TimedLeg]) { self.legs = legs }

    init?(_ journey: Journey, feed: TrainFeed) {
        var timed: [TimedLeg] = []
        for leg in journey.legs {
            let all = feed.stops(ofTrip: leg.tripID)
            guard let a = all.firstIndex(where: { $0.stationID == leg.fromID }),
                  let b = all.firstIndex(where: { $0.stationID == leg.toID }), a < b else { return nil }
            timed.append(TimedLeg(leg: leg, stops: Array(all[a...b])))
        }
        guard !timed.isEmpty else { return nil }
        legs = timed
    }
}

/// BMRCL token/QR fare by stations travelled on the shortest path (revised
/// fare chart, Feb 2025; the 2026 revision is on hold). Smart cards get 5% off,
/// 10% off-peak.
enum Fare {
    /// Upper bound of stations travelled for each fare; above the last it is ₹90.
    static let slabs: [(upToStations: Int, rupees: Int)] = [
        (2, 10), (4, 20), (6, 30), (8, 40), (10, 50), (15, 60), (20, 70), (25, 80),
    ]

    static func rupees(stations: Int) -> Int {
        slabs.first { stations <= $0.upToStations }?.rupees ?? 90
    }

    /// Smart-card fare: 10% off before 08:00, 12:00–16:00 and after 21:00 on
    /// weekdays and all day on Sundays, 5% off otherwise.
    static func smartCard(_ token: Int, at date: Date) -> Double {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let hour = c.component(.hour, from: date)
        let offPeak = c.component(.weekday, from: date) == 1 || hour < 8 || (12..<16).contains(hour) || hour >= 21
        return Double(token) * (offPeak ? 0.9 : 0.95)
    }
}

/// Finds journeys between two stations on the network, with interchanges.
struct Planner {
    let feed: TrainFeed
    var lines: [MetroLine] = MetroNetwork.lines
    /// Walking time between platforms at an interchange.
    var transferTime: TimeInterval = 4 * 60
    /// Time to get from the station entrance to the platform (security, ticket gates).
    var accessTime: TimeInterval = 0

    /// A way through the network that ignores time: which line from where to where.
    struct Route: Hashable {
        struct Hop: Hashable {
            let lineID: String
            let direction: Direction
            let fromID: String
            let toID: String
        }
        let hops: [Hop]
    }

    /// Routes from `a` to `b` using at most `maxLines` lines, without riding a line twice.
    func routes(from a: String, to b: String, maxLines: Int = 3) -> [Route] {
        guard a != b else { return [] }
        var found: [Route] = []

        func extend(_ hops: [Route.Hop], at station: String, used: Set<String>) {
            for line in lines where !used.contains(line.id) {
                guard let i = line.stationIDs.firstIndex(of: station) else { continue }
                // Get off at the destination, or at any interchange to another line.
                let exits = line.stationIDs.enumerated().filter { j, id in
                    j != i && (id == b || (hops.count + 1 < maxLines && isInterchange(id, besides: line.id)))
                }
                for (j, exit) in exits {
                    let hop = Route.Hop(lineID: line.id, direction: j > i ? .forward : .reverse, fromID: station, toID: exit)
                    if exit == b {
                        found.append(Route(hops: hops + [hop]))
                    } else {
                        extend(hops + [hop], at: exit, used: used.union([line.id]))
                    }
                }
            }
        }
        extend([], at: a, used: [])
        // Drop routes that pass through the destination or double back over a station.
        return found.filter { route in
            let visited = route.hops.flatMap(stationsRidden)
            return Set(visited).count == visited.count
        }
    }

    private func isInterchange(_ station: String, besides lineID: String) -> Bool {
        lines.contains { $0.id != lineID && $0.stationIDs.contains(station) }
    }

    /// Station IDs ridden past on a hop, excluding the boarding station.
    private func stationsRidden(_ hop: Route.Hop) -> [String] {
        guard let line = lines.first(where: { $0.id == hop.lineID }),
              let i = line.stationIDs.firstIndex(of: hop.fromID),
              let j = line.stationIDs.firstIndex(of: hop.toID) else { return [] }
        return i < j ? Array(line.stationIDs[(i + 1)...j]) : Array(line.stationIDs[j..<i].reversed())
    }

    /// Stations travelled, counting an interchange once.
    func stationCount(of route: Route) -> Int {
        route.hops.reduce(0) { $0 + stationsRidden($1).count }
    }

    /// BMRCL charges by the shortest path, whichever way the rider goes.
    func fare(from a: String, to b: String) -> Int {
        Fare.rupees(stations: routes(from: a, to: b).map(stationCount).min() ?? 0)
    }

    func distance(of route: Route) -> Double {
        route.hops.reduce(0) { sum, hop in
            guard let line = lines.first(where: { $0.id == hop.lineID }),
                  let i = line.stationIDs.firstIndex(of: hop.fromID),
                  let j = line.stationIDs.firstIndex(of: hop.toID) else { return sum }
            let s = line.track.stationDistances
            return sum + abs(s[j] - s[i])
        }
    }

    /// The first train sequence along `route` that can be caught when reaching
    /// the origin platform at `ready`.
    func earliest(_ route: Route, after ready: Date, fare: Int? = nil) -> (Journey, JourneyTimes)? {
        var legs: [JourneyLeg] = []
        var timed: [TimedLeg] = []
        var t = ready
        for (n, hop) in route.hops.enumerated() {
            if n > 0 { t = t.addingTimeInterval(transferTime) }
            guard let next = board(hop, after: t) else { return nil }
            legs.append(next.leg)
            timed.append(next)
            t = next.arrive
        }
        let d = distance(of: route)
        let fare = fare ?? self.fare(from: route.hops[0].fromID, to: route.hops[route.hops.count - 1].toID)
        return (Journey(legs: legs, fare: fare, distance: d), JourneyTimes(legs: timed))
    }

    private func board(_ hop: Route.Hop, after t: Date) -> TimedLeg? {
        // Arrivals are sorted; the first matching train that runs through to the exit wins.
        let candidates = feed.arrivals(at: hop.fromID, from: t, limit: 60)
            .filter { $0.lineID == hop.lineID && $0.direction == hop.direction }
        for arrival in candidates {
            let all = feed.stops(ofTrip: arrival.tripID)
            guard let a = all.firstIndex(where: { $0.stationID == hop.fromID }),
                  let b = all.firstIndex(where: { $0.stationID == hop.toID }), a < b,
                  all[a].depart >= t else { continue }
            let leg = JourneyLeg(
                lineID: hop.lineID, tripID: arrival.tripID, towards: arrival.destinationName,
                fromID: hop.fromID, toID: hop.toID)
            return TimedLeg(leg: leg, stops: Array(all[a...b]))
        }
        return nil
    }

    /// Up to `count` journey options leaving from `date`, best arrival first. Each
    /// route contributes its next few departures so later trains are listed too.
    func plan(from a: String, to b: String, leaving date: Date, count: Int = 4) -> [(journey: Journey, times: JourneyTimes)] {
        let ready = date.addingTimeInterval(accessTime)
        var options: [(journey: Journey, times: JourneyTimes)] = []
        let routes = routes(from: a, to: b)
        let fare = Fare.rupees(stations: routes.map(stationCount).min() ?? 0)
        for route in routes {
            var t = ready
            for _ in 0..<count {
                guard let option = earliest(route, after: t, fare: fare) else { break }
                options.append(option)
                t = option.1.depart.addingTimeInterval(1)
            }
        }
        // Prefer earlier arrival, then fewer changes; drop an option that leaves no
        // later and arrives no earlier than another one.
        let sorted = options.sorted {
            ($0.times.arrive, $0.journey.transfers, $0.times.depart) < ($1.times.arrive, $1.journey.transfers, $1.times.depart)
        }
        var kept: [(journey: Journey, times: JourneyTimes)] = []
        for option in sorted where !kept.contains(where: {
            $0.times.depart >= option.times.depart && $0.times.arrive <= option.times.arrive
                && $0.journey.transfers <= option.journey.transfers
        }) {
            kept.append(option)
        }
        return Array(kept.prefix(count))
    }
}
