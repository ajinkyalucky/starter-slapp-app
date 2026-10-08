import CoreLocation
import Foundation
import Observation
import UserNotifications

/// Where the rider is in a journey at a given moment.
enum TripProgress: Hashable {
    /// Before boarding leg `leg`, at its origin platform (a change counts too).
    case waiting(leg: Int, departs: Date)
    /// On leg `leg`; `next` is the index into that leg's stops of the next station.
    case riding(leg: Int, next: Int, arrives: Date)
    case arrived(at: Date)

    static func at(_ date: Date, _ times: JourneyTimes) -> TripProgress {
        for (n, leg) in times.legs.enumerated() {
            if date < leg.depart { return .waiting(leg: n, departs: leg.depart) }
            if date < leg.arrive {
                // The next station is the first one the train has not yet left.
                let next = leg.stops.indices.dropFirst().first { date < leg.stops[$0].depart } ?? leg.stops.count - 1
                return .riding(leg: n, next: next, arrives: leg.stops[next].arrive)
            }
        }
        return .arrived(at: times.arrive)
    }
}

/// Holds the journey the rider is on, keeps alerts in step with the latest
/// estimate and, with location access, learns delays from stops the phone passes.
@Observable
final class TripTracker: NSObject, CLLocationManagerDelegate {
    private(set) var journey: Journey?
    private(set) var startedAt: Date?
    /// Last automatic correction from location, shown to the rider.
    private(set) var lastAutoSighting: Sighting?
    private(set) var locationAllowed = false

    let feed: TrainFeed
    let base: TrainFeed
    let calibration: Calibration

    private let location = CLLocationManager()
    private let defaults: UserDefaults
    private var seenStations: Set<String> = []
    private static let storageKey = "tracker.journey"

    /// `feed` is the calibrated feed shown to the rider; `base` the raw
    /// timetable that sightings are measured against.
    init(feed: TrainFeed, base: TrainFeed, calibration: Calibration, defaults: UserDefaults = .standard) {
        self.feed = feed
        self.base = base
        self.calibration = calibration
        self.defaults = defaults
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        location.distanceFilter = 25
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data),
           let times = JourneyTimes(saved.journey, feed: feed), times.arrive > .now.addingTimeInterval(-15 * 60) {
            journey = saved.journey
            startedAt = saved.startedAt
            startUpdatingLocation()
        }
    }

    private struct Saved: Codable {
        let journey: Journey
        let startedAt: Date
    }

    var times: JourneyTimes? { journey.flatMap { JourneyTimes($0, feed: feed) } }

    func start(_ journey: Journey) {
        self.journey = journey
        startedAt = .now
        seenStations = []
        lastAutoSighting = nil
        if let data = try? JSONEncoder().encode(Saved(journey: journey, startedAt: .now)) {
            defaults.set(data, forKey: Self.storageKey)
        }
        Task { await requestNotifications() }
        startUpdatingLocation()
        rescheduleAlerts()
    }

    func end() {
        journey = nil
        startedAt = nil
        defaults.removeObject(forKey: Self.storageKey)
        location.stopUpdatingLocation()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: alertIDs)
    }

    /// Missed the train, or it was not where the estimate said: plan again from
    /// the station the rider is waiting at, on the remaining part of the trip.
    func replanFromCurrentStop(at date: Date = .now) -> [(journey: Journey, times: JourneyTimes)] {
        guard let journey, let times else { return [] }
        let from: String
        switch TripProgress.at(date, times) {
        case .waiting(let leg, _): from = journey.legs[leg].fromID
        case .riding(let leg, let next, _): from = times.legs[leg].stops[next].stationID
        case .arrived: return []
        }
        guard from != journey.toID else { return [] }
        return Planner(feed: feed).plan(from: from, to: journey.toID, leaving: date)
    }

    /// The rider confirms the train is at their platform now, or (from the
    /// platform display's countdown) when it will be.
    @discardableResult
    func confirmTrainHere(leg n: Int, at stationID: String, date: Date = .now, source: Sighting.Source = .tapped) -> TimeInterval? {
        guard let leg = journey?.legs[n], let line = leg.line else { return nil }
        let direction = direction(of: leg, on: line)
        let shift = calibration.record(
            Sighting(lineID: leg.lineID, direction: direction, stationID: stationID, trainAt: date, source: source, recorded: .now),
            base: base)
        rescheduleAlerts()
        return shift
    }

    private func direction(of leg: JourneyLeg, on line: MetroLine) -> Direction {
        let i = line.stationIDs.firstIndex(of: leg.fromID) ?? 0
        let j = line.stationIDs.firstIndex(of: leg.toID) ?? 0
        return j > i ? .forward : .reverse
    }

    // MARK: Alerts

    private var alertIDs: [String] { (0..<12).map { "journey.alert.\($0)" } }

    private func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Re-issues alerts from the latest times: the train due at the origin, and
    /// "next stop" one stop before every change and the destination.
    func rescheduleAlerts() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: alertIDs)
        guard let times else { return }
        var alerts: [(Date, String, String)] = []
        if let first = times.legs.first, let station = MetroNetwork.stations[first.leg.fromID] {
            alerts.append((first.depart.addingTimeInterval(-3 * 60), "Train in 3 min at \(station.name)",
                           "\(first.leg.line?.name ?? "") towards \(first.leg.towards)."))
        }
        for (n, leg) in times.legs.enumerated() where leg.stops.count >= 2 {
            let alight = leg.stops[leg.stops.count - 1]
            let name = MetroNetwork.stations[alight.stationID]?.name ?? ""
            let isLast = n == times.legs.count - 1
            let body: String
            if isLast {
                body = "Get ready to get off."
            } else {
                let next = times.legs[n + 1].leg
                body = "Get off and change to the \(next.line?.name ?? "next line") towards \(next.towards)."
            }
            // Fires as the train leaves the stop before.
            alerts.append((leg.stops[leg.stops.count - 2].depart, "Next stop: \(name)", body))
        }
        for (i, alert) in alerts.prefix(alertIDs.count).enumerated() where alert.0 > .now {
            let content = UNMutableNotificationContent()
            content.title = alert.1
            content.body = alert.2
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, alert.0.timeIntervalSinceNow), repeats: false)
            center.add(UNNotificationRequest(identifier: alertIDs[i], content: content, trigger: trigger))
        }
    }

    // MARK: Location

    private func startUpdatingLocation() {
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationAllowed = true
            location.startUpdatingLocation()
        default: locationAllowed = false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAllowed = [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
        if locationAllowed, journey != nil { manager.startUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        observe(fix, at: fix.timestamp)
    }

    /// A good fix stopped at a station the rider's train calls at, while riding,
    /// means the train is there now. Underground stations simply give no fix.
    func observe(_ fix: CLLocation, at date: Date) {
        guard let journey, let times, fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= 60,
              fix.speed >= 0, fix.speed < 1.5,
              case .riding(let n, _, _) = TripProgress.at(date, times) else { return }
        let leg = journey.legs[n]
        guard let line = leg.line else { return }
        for stop in times.legs[n].stops.dropFirst() where !seenStations.contains("\(n)/\(stop.stationID)") {
            guard let station = MetroNetwork.stations[stop.stationID],
                  fix.distance(from: CLLocation(latitude: station.latitude, longitude: station.longitude)) < 120 else { continue }
            seenStations.insert("\(n)/\(stop.stationID)")
            let sighting = Sighting(lineID: leg.lineID, direction: direction(of: leg, on: line), stationID: stop.stationID,
                                    trainAt: date, source: .location, recorded: date)
            if calibration.record(sighting, base: base) != nil {
                lastAutoSighting = sighting
                rescheduleAlerts()
            }
            return
        }
    }
}
