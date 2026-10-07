import Foundation
import Observation

/// What a rider actually saw, used to pull the timetable estimate onto real trains.
struct Sighting: Codable, Hashable {
    enum Source: String, Codable {
        /// "Train is at the platform now" tapped by the rider.
        case tapped
        /// Countdown read off the platform display ("Next train 3 min").
        case platformBoard
        /// The phone was at a station on an active journey (GPS).
        case location
    }

    let lineID: String
    let direction: Direction
    let stationID: String
    /// When the train was (or will be, for a board countdown) at the station.
    let trainAt: Date
    let source: Source
    let recorded: Date
}

/// Per line and direction time shifts learnt from sightings. A train running
/// 90 s behind the timetable gets offset +90 s, and so does every train on
/// that line and direction until the shift goes stale.
@Observable
final class Calibration {
    struct Offset: Codable, Hashable {
        let seconds: TimeInterval
        let sighting: Sighting
    }

    /// Delays drift and service gets rebalanced, so a sighting stops counting after this long.
    static let lifetime: TimeInterval = 90 * 60

    /// Read on the main thread by the UI (observed).
    private(set) var offsets: [String: Offset] = [:]
    /// Copy for `offset(_:_:at:)`, which the 3D view calls from its render thread.
    @ObservationIgnored private var snapshot: [String: Offset] = [:]
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "calibration.offsets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: Offset].self, from: data) {
            offsets = saved
            snapshot = saved
        }
    }

    static func key(_ lineID: String, _ direction: Direction) -> String { "\(lineID)-\(direction.rawValue)" }

    /// The shift for trains running at `date`: a sighting only says something
    /// about trains within `lifetime` of it, before or after. Safe from any thread.
    func offset(_ lineID: String, _ direction: Direction, at date: Date) -> TimeInterval {
        let key = Self.key(lineID, direction)
        guard let o = lock.withLock({ snapshot[key] }),
              abs(date.timeIntervalSince(o.sighting.trainAt)) < Self.lifetime else { return 0 }
        return o.seconds
    }

    func activeOffset(_ lineID: String, _ direction: Direction, at date: Date = .now) -> Offset? {
        guard let o = offsets[Self.key(lineID, direction)],
              date.timeIntervalSince(o.sighting.recorded) < Self.lifetime else { return nil }
        return o
    }

    /// Matches the sighting to the closest scheduled train and stores the
    /// difference. Returns the new offset, or nil if no scheduled train was
    /// close enough to be the same one (more than half a headway away).
    @discardableResult
    func record(_ sighting: Sighting, base: TrainFeed) -> TimeInterval? {
        let window: TimeInterval = 20 * 60
        let scheduled = base.arrivals(at: sighting.stationID, from: sighting.trainAt.addingTimeInterval(-window), limit: 80)
            .filter { $0.lineID == sighting.lineID && $0.direction == sighting.direction }
            .map(\.time)
        guard let nearest = scheduled.min(by: {
            abs($0.timeIntervalSince(sighting.trainAt)) < abs($1.timeIntervalSince(sighting.trainAt))
        }) else { return nil }
        // Half the gap to the neighbouring trains: any further and it is ambiguous which train was seen.
        // Median gap: short-loop trains can bunch up, so the minimum would reject good sightings.
        let gaps = zip(scheduled, scheduled.dropFirst()).map { $1.timeIntervalSince($0) }.sorted()
        let headway = gaps.isEmpty ? 8 * 60 : gaps[gaps.count / 2]
        let shift = sighting.trainAt.timeIntervalSince(nearest)
        guard abs(shift) <= headway / 2 + 1 else { return nil }
        offsets[Self.key(sighting.lineID, sighting.direction)] = Offset(seconds: shift, sighting: sighting)
        save()
        return shift
    }

    func clear(_ lineID: String, _ direction: Direction) {
        offsets[Self.key(lineID, direction)] = nil
        save()
    }

    /// Call on the main thread after every change to `offsets`.
    private func save() {
        let copy = offsets
        lock.withLock { snapshot = copy }
        if let data = try? JSONEncoder().encode(offsets) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// Wraps a feed and shifts each line/direction by its calibration offset.
/// Trip IDs pass through unchanged, so planned journeys follow the shift.
struct CalibratedFeed: TrainFeed {
    let base: TrainFeed
    let calibration: Calibration

    var isEstimated: Bool { base.isEstimated }

    private func activeKeys(at date: Date) -> [(lineID: String, direction: Direction, seconds: TimeInterval)] {
        MetroNetwork.lines.flatMap { line in
            [Direction.forward, .reverse].map { (line.id, $0, calibration.offset(line.id, $0, at: date)) }
        }
    }

    func trains(at date: Date) -> [Train] {
        let activeKeys = activeKeys(at: date)
        // A train running `offset` late is where the timetable put it `offset` ago.
        let groups = Dictionary(grouping: activeKeys, by: \.seconds)
        return groups.flatMap { seconds, keys in
            let wanted = Set(keys.map { Calibration.key($0.lineID, $0.direction) })
            return base.trains(at: date.addingTimeInterval(-seconds))
                .filter { wanted.contains(Calibration.key($0.lineID, $0.direction)) }
        }
    }

    func arrivals(at stationID: String, from date: Date, limit: Int) -> [Arrival] {
        let shifts = activeKeys(at: date).map(\.seconds)
        let earliest = date.addingTimeInterval(-(shifts.max() ?? 0))
        return base.arrivals(at: stationID, from: earliest, limit: limit * 2 + 20)
            .map { a in
                Arrival(id: a.id, tripID: a.tripID, lineID: a.lineID, direction: a.direction,
                        destinationName: a.destinationName,
                        time: a.time.addingTimeInterval(calibration.offset(a.lineID, a.direction, at: a.time)))
            }
            .filter { $0.time >= date }
            .sorted { $0.time < $1.time }
            .prefix(limit)
            .map { $0 }
    }

    func stops(ofTrip tripID: String) -> [TripStop] {
        let stops = base.stops(ofTrip: tripID)
        guard let (lineID, direction) = Self.lineAndDirection(of: stops) else { return stops }
        let shift = calibration.offset(lineID, direction, at: stops[0].depart)
        guard shift != 0 else { return stops }
        return stops.map {
            TripStop(stationID: $0.stationID, arrive: $0.arrive.addingTimeInterval(shift), depart: $0.depart.addingTimeInterval(shift))
        }
    }

    /// The line a stop sequence runs on, from its first two stops.
    static func lineAndDirection(of stops: [TripStop]) -> (String, Direction)? {
        guard stops.count >= 2 else { return nil }
        for line in MetroNetwork.lines {
            if let i = line.stationIDs.firstIndex(of: stops[0].stationID),
               let j = line.stationIDs.firstIndex(of: stops[1].stationID), abs(i - j) == 1 {
                return (line.id, j > i ? .forward : .reverse)
            }
        }
        return nil
    }
}

extension Direction: Codable {}
