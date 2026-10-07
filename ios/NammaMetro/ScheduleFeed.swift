import Foundation

/// Timetable assumptions. These are placeholders, not BMRCL's published
/// numbers: tune them (or load real stop times from GTFS) for accuracy.
struct ServiceProfile {
    var firstDeparture = 5 * 3600           // seconds after midnight
    var lastDeparture = 22 * 3600 + 30 * 60
    var peakHeadway = 5 * 60
    var offPeakHeadway = 8 * 60
    var segmentSeconds: TimeInterval = 120  // station to station, including dwell
    var dwellSeconds: TimeInterval = 20

    func headway(atSecondOfDay s: Int) -> Int {
        let hour = s / 3600
        let peak = (7..<11).contains(hour) || (17..<21).contains(hour)
        return peak ? peakHeadway : offPeakHeadway
    }
}

/// Estimates train positions from a fixed-headway timetable.
struct ScheduleFeed: TrainFeed {
    var profile = ServiceProfile()
    var lines = MetroNetwork.lines
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()

    let isEstimated = true

    private struct Trip {
        let line: MetroLine
        let direction: Direction
        let departure: Date

        var id: String { "\(line.id)-\(direction.rawValue)-\(Int(departure.timeIntervalSince1970))" }
    }

    /// Station IDs in travel order for the trip's direction.
    private func path(of line: MetroLine, _ direction: Direction) -> [String] {
        direction == .forward ? line.stationIDs : line.stationIDs.reversed()
    }

    private func tripDuration(of line: MetroLine) -> TimeInterval {
        Double(line.stationIDs.count - 1) * profile.segmentSeconds
    }

    private func departures(onDayStarting day: Date) -> [Date] {
        var result: [Date] = []
        var s = profile.firstDeparture
        while s <= profile.lastDeparture {
            result.append(day.addingTimeInterval(TimeInterval(s)))
            s += profile.headway(atSecondOfDay: s)
        }
        return result
    }

    /// Trips that departed within `lookback` seconds before `date`, or depart up to `lookahead` after it.
    private func trips(around date: Date, lookback: TimeInterval, lookahead: TimeInterval) -> [Trip] {
        let today = calendar.startOfDay(for: date)
        let days = [-1, 0, 1].compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        var out: [Trip] = []
        for line in lines {
            for day in days {
                for dep in departures(onDayStarting: day)
                where dep >= date.addingTimeInterval(-lookback) && dep <= date.addingTimeInterval(lookahead) {
                    out.append(Trip(line: line, direction: .forward, departure: dep))
                    out.append(Trip(line: line, direction: .reverse, departure: dep))
                }
            }
        }
        return out
    }

    func trains(at date: Date) -> [Train] {
        let longest = lines.map(tripDuration(of:)).max() ?? 0
        return trips(around: date, lookback: longest, lookahead: 0).compactMap { trip in
            let duration = tripDuration(of: trip.line)
            let elapsed = date.timeIntervalSince(trip.departure)
            guard elapsed >= 0, elapsed < duration else { return nil }

            let ids = path(of: trip.line, trip.direction)
            let segment = min(Int(elapsed / profile.segmentSeconds), ids.count - 2)
            let within = elapsed - Double(segment) * profile.segmentSeconds
            let moving = max(0, (within - profile.dwellSeconds) / (profile.segmentSeconds - profile.dwellSeconds))

            guard let from = MetroNetwork.stations[ids[segment]],
                  let to = MetroNetwork.stations[ids[segment + 1]] else { return nil }
            let atStation = within < profile.dwellSeconds
            let destination = MetroNetwork.stations[ids.last!]?.name ?? ""
            return Train(
                id: trip.id,
                lineID: trip.line.id,
                direction: trip.direction,
                latitude: from.latitude + (to.latitude - from.latitude) * moving,
                longitude: from.longitude + (to.longitude - from.longitude) * moving,
                status: atStation ? .atStation : .moving,
                nextStationID: atStation ? from.id : to.id,
                destinationName: destination)
        }
    }

    func arrivals(at stationID: String, from date: Date, limit: Int) -> [Arrival] {
        let longest = lines.map(tripDuration(of:)).max() ?? 0
        var out: [Arrival] = []
        for trip in trips(around: date, lookback: longest, lookahead: longest) {
            let ids = path(of: trip.line, trip.direction)
            guard let index = ids.firstIndex(of: stationID) else { continue }
            let time = trip.departure.addingTimeInterval(Double(index) * profile.segmentSeconds)
            guard time >= date else { continue }
            out.append(Arrival(
                id: "\(trip.id)-\(stationID)",
                lineID: trip.line.id,
                direction: trip.direction,
                destinationName: MetroNetwork.stations[ids.last!]?.name ?? "",
                time: time))
        }
        return Array(out.sorted { $0.time < $1.time }.prefix(limit))
    }
}
