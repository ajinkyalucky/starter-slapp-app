import XCTest
@testable import NammaMetro

final class PlannerTests: XCTestCase {
    private let base = ScheduleFeed()
    private lazy var planner = Planner(feed: base)

    private func date(_ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 7
        parts.hour = hour; parts.minute = minute
        return base.calendar.date(from: parts)!
    }

    private func freshDefaults() -> UserDefaults {
        let name = "PlannerTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    func testDirectTripOnOneLine() throws {
        let option = try XCTUnwrap(planner.plan(from: "indiranagar", to: "mg-road", leaving: date(9, 0)).first)
        XCTAssertEqual(option.journey.legs.map(\.lineID), ["purple"])
        XCTAssertEqual(option.times.legs[0].stops.map(\.stationID), ["indiranagar", "halasuru", "trinity", "mg-road"])
        XCTAssertGreaterThanOrEqual(option.times.depart, date(9, 0))
        XCTAssertLessThan(option.times.duration, 15 * 60)
    }

    func testChangeAtMajestic() throws {
        let option = try XCTUnwrap(planner.plan(from: "mg-road", to: "chickpete", leaving: date(9, 0)).first)
        XCTAssertEqual(option.journey.legs.map(\.lineID), ["purple", "green"])
        XCTAssertEqual(option.journey.legs[0].toID, "majestic")
        let gap = option.times.legs[1].depart.timeIntervalSince(option.times.legs[0].arrive)
        XCTAssertGreaterThanOrEqual(gap, planner.transferTime)
    }

    func testTwoChangesAcrossThreeLines() throws {
        let option = try XCTUnwrap(planner.plan(from: "electronics-city", to: "indiranagar", leaving: date(10, 0)).first)
        XCTAssertEqual(option.journey.legs.map(\.lineID), ["yellow", "green", "purple"])
        XCTAssertEqual(option.journey.transfers, 2)
    }

    func testOptionsAreDistinctAndOrdered() {
        let options = planner.plan(from: "indiranagar", to: "mg-road", leaving: date(9, 0))
        XCTAssertGreaterThan(options.count, 1)
        XCTAssertEqual(Set(options.map(\.journey.id)).count, options.count)
        XCTAssertEqual(options.map(\.times.arrive), options.map(\.times.arrive).sorted())
    }

    func testLateAtNightOffersTheFirstMorningTrain() throws {
        // Wednesday 23:59: the next train is Thursday's first, from Whitefield at 05:00.
        let option = try XCTUnwrap(planner.plan(from: "indiranagar", to: "mg-road", leaving: date(23, 59)).first)
        XCTAssertGreaterThan(option.times.depart, date(24 + 5, 0))
        XCTAssertLessThan(option.times.depart, date(24 + 6, 0))
    }

    func testRoutesNeverRevisitAStation() {
        for route in planner.routes(from: "kengeri", to: "bommasandra") {
            XCTAssertLessThanOrEqual(route.hops.count, 3)
            XCTAssertEqual(route.hops.last?.toID, "bommasandra")
        }
    }

    func testFaresByStationsTravelled() {
        XCTAssertEqual(Fare.rupees(stations: 1), 10)
        XCTAssertEqual(Fare.rupees(stations: 3), 20)
        XCTAssertEqual(Fare.rupees(stations: 15), 60)
        XCTAssertEqual(Fare.rupees(stations: 36), 90)
        // RV Road to Bommasandra is 15 stations: ₹60, as BMRCL charges.
        XCTAssertEqual(planner.fare(from: "rashtreeya-vidyalaya-road", to: "bommasandra"), 60)
        // Indiranagar to MG Road is 3 stations.
        XCTAssertEqual(planner.fare(from: "indiranagar", to: "mg-road"), 20)
    }

    func testCalibrationShiftsArrivalsAndTrips() throws {
        let calibration = Calibration(defaults: freshDefaults())
        let feed = CalibratedFeed(base: base, calibration: calibration)
        // Midday, when trains are 8 minutes apart: a 2-minute delay is unambiguous.
        let now = date(13, 0)
        let scheduled = try XCTUnwrap(base.arrivals(at: "indiranagar", from: now, limit: 20)
            .first { $0.lineID == "purple" && $0.direction == .forward })

        // The rider sees that train 2 minutes later than the timetable says.
        let shift = calibration.record(
            Sighting(lineID: "purple", direction: .forward, stationID: "indiranagar",
                     trainAt: scheduled.time.addingTimeInterval(120), source: .tapped, recorded: now),
            base: base)
        XCTAssertEqual(try XCTUnwrap(shift), 120, accuracy: 1)

        let shifted = try XCTUnwrap(feed.arrivals(at: "indiranagar", from: now, limit: 20)
            .first { $0.tripID == scheduled.tripID })
        XCTAssertEqual(shifted.time.timeIntervalSince(scheduled.time), 120, accuracy: 1)
        let stop = try XCTUnwrap(feed.stops(ofTrip: scheduled.tripID).first { $0.stationID == "indiranagar" })
        XCTAssertEqual(stop.arrive.timeIntervalSince(scheduled.time), 120, accuracy: 1)

        // Other lines are untouched.
        XCTAssertEqual(calibration.offset("green", .forward, at: now), 0)
        // And it expires.
        XCTAssertEqual(calibration.offset("purple", .forward, at: scheduled.time.addingTimeInterval(120 + Calibration.lifetime + 1)), 0)
    }

    func testCalibrationIgnoresSightingsBetweenTrains() {
        let calibration = Calibration(defaults: freshDefaults())
        let now = date(9, 0)
        // A sighting several hours before service starts matches nothing.
        let shift = calibration.record(
            Sighting(lineID: "purple", direction: .forward, stationID: "indiranagar",
                     trainAt: date(2, 0), source: .tapped, recorded: now),
            base: base)
        XCTAssertNil(shift)
    }

    func testTripProgressThroughAJourney() throws {
        let option = try XCTUnwrap(planner.plan(from: "mg-road", to: "chickpete", leaving: date(9, 0)).first)
        let times = option.times
        XCTAssertEqual(TripProgress.at(times.depart.addingTimeInterval(-60), times), .waiting(leg: 0, departs: times.depart))
        if case .riding(let leg, let next, _) = TripProgress.at(times.depart.addingTimeInterval(10), times) {
            XCTAssertEqual(leg, 0)
            XCTAssertEqual(next, 1)
        } else {
            XCTFail("expected riding")
        }
        let change = times.legs[0].arrive.addingTimeInterval(30)
        XCTAssertEqual(TripProgress.at(change, times), .waiting(leg: 1, departs: times.legs[1].depart))
        XCTAssertEqual(TripProgress.at(times.arrive.addingTimeInterval(1), times), .arrived(at: times.arrive))
    }
}
