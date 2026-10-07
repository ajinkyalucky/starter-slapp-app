import XCTest
@testable import NammaMetro

final class ScheduleFeedTests: XCTestCase {
    private let feed = ScheduleFeed()

    private func date(_ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 7
        parts.hour = hour; parts.minute = minute
        return feed.calendar.date(from: parts)!
    }

    func testNetworkIsConsistent() {
        for line in MetroNetwork.lines {
            XCTAssertEqual(line.stations.count, line.stationIDs.count, "\(line.id) has unknown station")
        }
        XCTAssertNotNil(MetroNetwork.stations["majestic"])
    }

    func testNoTrainsBeforeServiceStarts() {
        XCTAssertTrue(feed.trains(at: date(3, 0)).isEmpty)
    }

    func testTrainsRunInTheDayAndStayNearBengaluru() {
        let trains = feed.trains(at: date(9, 0))
        XCTAssertFalse(trains.isEmpty)
        for t in trains {
            XCTAssertTrue((12.7...13.2).contains(t.latitude))
            XCTAssertTrue((77.4...77.8).contains(t.longitude))
        }
    }

    func testBothDirectionsRun() {
        let directions = Set(feed.trains(at: date(9, 0)).map(\.direction))
        XCTAssertEqual(directions, [.forward, .reverse])
    }

    func testArrivalsAreSortedAndInTheFuture() {
        let now = date(9, 0)
        let arrivals = feed.arrivals(at: "majestic", from: now, limit: 10)
        XCTAssertEqual(arrivals.count, 10)
        XCTAssertEqual(arrivals.map(\.time), arrivals.map(\.time).sorted())
        XCTAssertTrue(arrivals.allSatisfy { $0.time >= now })
    }

    func testInterchangeServesMultipleLines() {
        let lines = Set(feed.arrivals(at: "majestic", from: date(9, 0), limit: 30).map(\.lineID))
        XCTAssertEqual(lines, ["purple", "green"])
    }
}
