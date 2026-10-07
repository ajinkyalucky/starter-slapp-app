import XCTest
@testable import NammaMetro

/// Checks the feed against BMRCL's published timetable (2026).
final class TimetableTests: XCTestCase {
    private let feed = ScheduleFeed()

    /// 2026-10-07 is a Wednesday, 10-05 a Monday, 10-04 a Sunday, 10-10 the 2nd Saturday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = day
        parts.hour = hour; parts.minute = minute
        return feed.calendar.date(from: parts)!
    }

    private func departures(from station: String, line: String, direction: Direction, after d: Date, limit: Int = 200) -> [Arrival] {
        feed.arrivals(at: station, from: d, limit: limit).filter { $0.lineID == line && $0.direction == direction }
    }

    func testFirstTrainsByDay() throws {
        let weekday = try XCTUnwrap(departures(from: "whitefield--kadugodi-", line: "purple", direction: .forward, after: date(7, 3, 0)).first)
        XCTAssertEqual(weekday.time, date(7, 5, 0))
        let monday = try XCTUnwrap(departures(from: "whitefield--kadugodi-", line: "purple", direction: .forward, after: date(5, 3, 0)).first)
        XCTAssertEqual(monday.time, date(5, 4, 15))
        let sunday = try XCTUnwrap(departures(from: "whitefield--kadugodi-", line: "purple", direction: .forward, after: date(4, 3, 0)).first)
        XCTAssertEqual(sunday.time, date(4, 7, 0))
    }

    func testOfficialLastTrains() {
        let fromWhitefield = departures(from: "whitefield--kadugodi-", line: "purple", direction: .forward, after: date(7, 22, 30))
        XCTAssertTrue(fromWhitefield.contains { $0.time == date(7, 22, 45) })
        XCTAssertFalse(fromWhitefield.contains { $0.time > date(7, 22, 45) && $0.time < date(8, 4, 0) })
        let fromRVRoad = departures(from: "rashtreeya-vidyalaya-road", line: "yellow", direction: .forward, after: date(7, 23, 30))
        XCTAssertTrue(fromRVRoad.contains { $0.time == date(7, 23, 55) })
    }

    func testPeakShortLoopsRunAndEndMidLine() {
        // Weekday peak: Garudacharpalya to Mysuru Road every 5 minutes on top of the full-line trains.
        let trains = feed.trains(at: date(7, 9, 0)).filter { $0.lineID == "purple" }
        XCTAssertTrue(trains.contains { $0.destinationName == "Mysuru Road" })
        let atMGRoad = departures(from: "mg-road", line: "purple", direction: .reverse, after: date(7, 9, 0))
            .prefix { $0.time < date(7, 9, 30) }
        XCTAssertGreaterThanOrEqual(atMGRoad.count, 7, "peak core section should see a train every ~4 min")
    }

    func testSecondSaturdayUsesTheSaturdayTable() {
        // Majestic to Pattandur Agrahara morning trips: 9 on the weekday table,
        // 7 on the Saturday table (2nd/4th Saturdays and holidays).
        func trips(_ day: Int) -> Int {
            departures(from: "majestic", line: "purple", direction: .reverse, after: date(day, 8, 50), limit: 400)
                .filter { $0.destinationName == "Pattandur Agrahara" && $0.time < date(day, 10, 30) }
                .count
        }
        XCTAssertEqual(trips(7), 9)
        XCTAssertEqual(trips(10), 7)
    }

    func testEndToEndRunTimesMatchBMRCL() throws {
        let first = try XCTUnwrap(departures(from: "whitefield--kadugodi-", line: "purple", direction: .forward, after: date(7, 12, 0)).first)
        let stops = feed.stops(ofTrip: first.tripID)
        let minutes = try XCTUnwrap(stops.last).arrive.timeIntervalSince(try XCTUnwrap(stops.first).depart) / 60
        XCTAssertEqual(minutes, 80, accuracy: 3)
        XCTAssertEqual(stops.last?.stationID, "challaghatta")
    }

    func testTrainsStandAtTerminiAndStayOnTrack() {
        for train in feed.trains(at: date(7, 18, 0)) {
            let line = MetroNetwork.line(train.lineID)!
            XCTAssertTrue((0...line.track.length).contains(train.distance))
            XCTAssertLessThan(train.speed, 30)
            if train.status == .atStation { XCTAssertEqual(train.speed, 0) }
        }
    }

    func testTripIDsAreUniqueAndResolve() {
        let trains = feed.trains(at: date(7, 18, 0))
        XCTAssertEqual(Set(trains.map(\.id)).count, trains.count)
        for train in trains {
            XCTAssertFalse(feed.stops(ofTrip: train.id).isEmpty, train.id)
        }
    }

    func testTrainsAtIsCheapEnoughForEveryFrame() {
        let d = date(7, 18, 0)
        measure {
            for i in 0..<60 { _ = feed.trains(at: d.addingTimeInterval(Double(i) / 60)) }
        }
    }
}
