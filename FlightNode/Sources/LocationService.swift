import Foundation
import CoreLocation
import UIKit

struct Fix {
    var coordinate: CLLocationCoordinate2D
    var altitudeM: Double
    var speedKmh: Double
    var courseDeg: Double?
    var accuracyM: Double
    var timestamp: Date
}

/// Real GPS from the phone's chip (works in airplane mode — no network needed), or a simulated flight for testing at home.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var fix: Fix?
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published var simulate = false { didSet { simulate ? startSimulation() : stopSimulation() } }
    @Published var simulationFraction = 0.0

    var plan: FlightPlan = .outbound { didSet { simulationFraction = 0 } }

    private let manager = CLLocationManager()
    private var timer: Timer?
    private let simTimeScale = 30.0   // 1 real second = 30 simulated seconds

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .airborne
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        UIApplication.shared.isIdleTimerDisabled = true   // keep the screen (and GPS) on
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        authorization = m.authorizationStatus
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways { m.startUpdatingLocation() }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !simulate, let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        fix = Fix(coordinate: l.coordinate, altitudeM: l.verticalAccuracy >= 0 ? l.altitude : .nan,
                  speedKmh: l.speed >= 0 ? l.speed * 3.6 : 0,
                  courseDeg: l.course >= 0 ? l.course : nil,
                  accuracyM: l.horizontalAccuracy, timestamp: l.timestamp)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) { /* keep last fix; GPS may need sky view */ }

    // MARK: Simulation

    private func startSimulation() {
        simulationFraction = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    private func stopSimulation() { timer?.invalidate(); timer = nil; fix = nil }

    private func tick() {
        let total = plan.totalKm
        // Climb 0–12%, cruise 12–85%, descent 85–100%.
        let f = simulationFraction
        let (alt, speed): (Double, Double) = f < 0.12 ? (f / 0.12 * 10_000, 500 + f / 0.12 * 300)
            : f < 0.85 ? (10_500, 800) : (max(100, (1 - f) / 0.15 * 10_000), 800 - (f - 0.85) / 0.15 * 400)
        let here = GeoMath.interpolate(plan.from.coordinate, plan.to.coordinate, f)
        let ahead = GeoMath.interpolate(plan.from.coordinate, plan.to.coordinate, min(1, f + 0.01))
        fix = Fix(coordinate: here, altitudeM: alt, speedKmh: speed, courseDeg: GeoMath.bearing(here, ahead),
                  accuracyM: 5, timestamp: Date())
        simulationFraction = min(1, f + (speed * simTimeScale / 3600) / total)
        if simulationFraction >= 1 { simulationFraction = 0 }
    }
}
