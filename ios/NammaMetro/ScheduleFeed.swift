import Foundation

/// Train positions and arrivals from BMRCL's published timetable (`Timetable`),
/// in Asia/Kolkata time. Every scheduled trip is included, short loops too.
///
/// Immutable after init, so it is safe to call from any thread: the 3D ride view
/// calls `trains(at:)` from SceneKit's render thread every frame, which is why
/// lookups binary-search a start-time index instead of scanning every trip.
struct ScheduleFeed: TrainFeed {
    /// Time a train stands at its first stop before departing and at its last after arriving.
    static let terminalStand: TimeInterval = 100
    static let acceleration = 0.9  // m/s², also used for braking

    let isEstimated = true
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()

    /// One line in one direction. Arrays are indexed by line-order station index.
    private struct Pattern {
        let line: MetroLine
        let direction: Direction
        let step: Int  // +1 forward, -1 reverse
        /// Offsets from leaving the direction's origin terminus.
        let arrive: [Double]
        let depart: [Double]
        let runs: [Run]  // runs[i]: from station i to station i + step
        let indexOf: [String: Int]
        let stationIDs: [String]
    }

    /// Station-to-station motion: accelerate, cruise, brake, fitted to the run time.
    private struct Run {
        let from: Double  // metres along the track, forward frame
        let length: Double
        let time: Double
        let cruise: Double
        let accel: Double

        init(from: Double, to: Double, time: Double) {
            self.from = from
            length = abs(to - from)
            self.time = max(time, 1)
            let a = ScheduleFeed.acceleration
            let disc = (a * self.time) * (a * self.time) - 4 * a * length
            if disc >= 0 {
                accel = a
                cruise = (a * self.time - disc.squareRoot()) / 2
            } else {
                // Too short to reach a cruise at the usual rate: a triangle profile.
                accel = 4 * length / (self.time * self.time)
                cruise = accel * self.time / 2
            }
        }

        /// Distance covered and speed `t` seconds after leaving.
        func at(_ t: Double) -> (distance: Double, speed: Double) {
            let t = min(max(t, 0), time)
            let ramp = cruise / accel
            if t < ramp { return (0.5 * accel * t * t, accel * t) }
            if t < time - ramp { return (0.5 * accel * ramp * ramp + cruise * (t - ramp), cruise) }
            let left = time - t
            return (length - 0.5 * accel * left * left, accel * left)
        }
    }

    private struct TripRef {
        let pattern: Int
        let from: Int
        let to: Int
        let start: Double  // seconds after the service day's midnight
    }

    private let patterns: [Pattern]
    /// Trips per service ID, sorted by start.
    private let services: [String: [TripRef]]
    private let weekdayService: [Int: String]
    private let exceptionService: [Int: String]
    /// Longest trip from first departure to last arrival.
    private let longest: Double

    private static let istOffset = 19_800.0  // UTC+5:30, no daylight saving

    init(timetable: Timetable = .bundled, lines: [MetroLine] = MetroNetwork.lines) {
        var patterns: [Pattern] = []
        var patternIndex: [String: Int] = [:]
        for line in lines {
            guard let p = timetable.patterns[line.id] else { continue }
            precondition(p.stations == line.stationIDs, "timetable.json stations differ from StationData for \(line.id)")
            let s = line.track.stationDistances
            let n = line.stationIDs.count
            for (direction, times) in [(Direction.forward, p.forward), (.reverse, p.reverse)] {
                let step = direction == .forward ? 1 : -1
                let order = direction == .forward ? Array(0..<n) : Array((0..<n).reversed())
                var arrive = [Double](repeating: 0, count: n), depart = arrive
                var runs = [Run](repeating: Run(from: 0, to: 0, time: 1), count: n)
                for (a, b) in zip(order, order.dropFirst()) {
                    runs[a] = Run(from: s[a], to: s[b], time: Double(times.run[a]))
                    arrive[b] = depart[a] + Double(times.run[a])
                    depart[b] = arrive[b] + Double(times.dwell[b])
                }
                patternIndex["\(line.id)-\(direction.rawValue)"] = patterns.count
                patterns.append(Pattern(
                    line: line, direction: direction, step: step, arrive: arrive, depart: depart, runs: runs,
                    indexOf: Dictionary(uniqueKeysWithValues: line.stationIDs.enumerated().map { ($1, $0) }),
                    stationIDs: line.stationIDs))
            }
        }
        var services: [String: [TripRef]] = [:]
        for t in timetable.trips {
            guard let i = patternIndex["\(t.lineID)-\(t.direction.rawValue)"] else { continue }
            services[t.service, default: []].append(TripRef(pattern: i, from: t.from, to: t.to, start: Double(t.start)))
        }
        self.services = services.mapValues { $0.sorted { $0.start < $1.start } }
        self.patterns = patterns
        longest = patterns.map { p in p.arrive[p.step > 0 ? p.arrive.count - 1 : 0] }.max() ?? 0

        weekdayService = Dictionary(uniqueKeysWithValues: timetable.calendar.weekdays.compactMap { k, v in Int(k).map { ($0, v) } })
        var exceptions: [Int: String] = [:]
        for (key, service) in timetable.calendar.exceptions {
            guard let n = Int(key) else { continue }
            var parts = DateComponents()
            parts.year = n / 10000; parts.month = n / 100 % 100; parts.day = n % 100
            if let date = calendar.date(from: parts) { exceptions[Self.dayNumber(date)] = service }
        }
        exceptionService = exceptions
    }

    // MARK: Service days

    /// Days since 1970-01-01 in Bengaluru.
    private static func dayNumber(_ date: Date) -> Int {
        Int(((date.timeIntervalSince1970 + istOffset) / 86_400).rounded(.down))
    }

    private static func midnight(ofDay day: Int) -> Double { Double(day) * 86_400 - istOffset }

    private func trips(onDay day: Int) -> [TripRef] {
        // 1970-01-01 was a Thursday; ISO Monday = 1.
        let iso = (day + 3) % 7 + 1
        guard let service = exceptionService[day] ?? weekdayService[iso] else { return [] }
        return services[service] ?? []
    }

    /// Index of the first trip starting at or after `s`.
    private func lowerBound(_ trips: [TripRef], _ s: Double) -> Int {
        var lo = 0, hi = trips.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if trips[mid].start < s { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Trips (with their day's midnight) that start within [from, to], as epoch seconds.
    private func forEachTrip(startingBetween from: Double, and to: Double, _ body: (TripRef, Double) -> Void) {
        let first = Self.dayNumber(Date(timeIntervalSince1970: from)) - 1
        let last = Self.dayNumber(Date(timeIntervalSince1970: to))
        for day in first...last {
            let midnight = Self.midnight(ofDay: day)
            let list = trips(onDay: day)
            var i = lowerBound(list, from - midnight)
            while i < list.count, list[i].start <= to - midnight {
                body(list[i], midnight)
                i += 1
            }
        }
    }

    // MARK: Trip IDs

    private func tripID(_ trip: TripRef, midnight: Double) -> String {
        let p = patterns[trip.pattern]
        return "\(p.line.id)-\(p.direction.rawValue)-\(trip.from)-\(trip.to)-\(Int(midnight + trip.start))"
    }

    /// "<line>-<direction>-<from index>-<to index>-<departure epoch seconds>".
    private func parse(_ tripID: String) -> (pattern: Int, from: Int, to: Int, departure: Double)? {
        let parts = tripID.split(separator: "-")
        guard parts.count == 5, let from = Int(parts[2]), let to = Int(parts[3]), let epoch = Double(parts[4]),
              let i = patterns.firstIndex(where: { $0.line.id == parts[0] && $0.direction.rawValue == parts[1] }),
              patterns[i].stationIDs.indices.contains(from), patterns[i].stationIDs.indices.contains(to) else { return nil }
        return (i, from, to, epoch)
    }

    // MARK: TrainFeed

    func trains(at date: Date) -> [Train] {
        let now = date.timeIntervalSince1970
        let stand = Self.terminalStand
        var out: [Train] = []
        forEachTrip(startingBetween: now - longest - stand, and: now + stand) { trip, midnight in
            let p = patterns[trip.pattern]
            let departure = midnight + trip.start
            // Pattern time: offsets are measured from the direction's origin terminus.
            let t = now - departure + p.depart[trip.from]
            let end = p.arrive[trip.to]
            guard t >= p.depart[trip.from] - stand, t < end + stand else { return }

            let s = p.line.track.stationDistances
            var distance: Double, speed = 0.0, status = Train.Status.atStation, next: Int
            if t < p.depart[trip.from] {
                (distance, next) = (s[trip.from], trip.from)
            } else if t >= end {
                (distance, next) = (s[trip.to], trip.to)
            } else {
                // Walk from the first stop to the run or dwell containing t (at most ~36 steps).
                var k = trip.from
                while k != trip.to, t >= p.arrive[k + p.step] { k += p.step }
                if t < p.depart[k] {
                    (distance, next) = (s[k], k)  // dwelling at k
                } else {
                    let run = p.runs[k]
                    let r = run.at(t - p.depart[k])
                    distance = run.from + Double(p.step) * r.distance
                    speed = r.speed
                    status = .moving
                    next = k + p.step
                }
            }
            let c = p.line.track.coordinate(at: distance)
            out.append(Train(
                id: tripID(trip, midnight: midnight),
                lineID: p.line.id,
                direction: p.direction,
                latitude: c.latitude,
                longitude: c.longitude,
                status: status,
                nextStationID: p.stationIDs[next],
                destinationName: MetroNetwork.stations[p.stationIDs[trip.to]]?.name ?? "",
                distance: distance,
                speed: speed))
        }
        return out
    }

    func stops(ofTrip tripID: String) -> [TripStop] {
        guard let (i, from, to, departure) = parse(tripID) else { return [] }
        let p = patterns[i]
        let base = departure - p.depart[from]
        return Array(stride(from: from, through: to, by: p.step)).map { k in
            TripStop(
                stationID: p.stationIDs[k],
                arrive: Date(timeIntervalSince1970: base + (k == from ? p.depart[k] - Self.terminalStand : p.arrive[k])),
                depart: Date(timeIntervalSince1970: base + (k == to ? p.arrive[k] + Self.terminalStand : p.depart[k])))
        }
    }

    /// Trains calling at a station from `date` on, soonest first. Looks up to
    /// eight hours ahead, so late at night it returns the first morning trains.
    func arrivals(at stationID: String, from date: Date, limit: Int) -> [Arrival] {
        let now = date.timeIntervalSince1970
        var out: [Arrival] = []
        forEachTrip(startingBetween: now - longest, and: now + 8 * 3600) { trip, midnight in
            let p = patterns[trip.pattern]
            guard let k = p.indexOf[stationID], k != trip.to,
                  (k - trip.from) * p.step >= 0, (trip.to - k) * p.step > 0 else { return }
            let departure = midnight + trip.start
            // At the first stop the train stands at the platform; show when it leaves.
            let time = departure - p.depart[trip.from] + (k == trip.from ? p.depart[k] : p.arrive[k])
            guard time >= now else { return }
            let id = tripID(trip, midnight: midnight)
            out.append(Arrival(
                id: "\(id)-\(stationID)",
                tripID: id,
                lineID: p.line.id,
                direction: p.direction,
                destinationName: MetroNetwork.stations[p.stationIDs[trip.to]]?.name ?? "",
                time: Date(timeIntervalSince1970: time)))
        }
        out.sort { $0.time < $1.time }
        return Array(out.prefix(limit))
    }
}
