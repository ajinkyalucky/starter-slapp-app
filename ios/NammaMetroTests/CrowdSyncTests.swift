import XCTest
@testable import NammaMetro

/// Serves a canned /api/offsets response.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CrowdSyncTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "CrowdSyncTests.\(UUID().uuidString)")! }

    func testCrowdOffsetAppliesWhenRiderHasNone() {
        let cal = Calibration(defaults: defaults())
        let now = Date()
        cal.applyCrowd(["purple-forward": .init(seconds: 120, reports: 3, riders: 3, newestAt: now)])
        XCTAssertEqual(cal.offset("purple", .forward, at: now), 120)
        XCTAssertEqual(cal.offset("purple", .reverse, at: now), 0)
        XCTAssertEqual(cal.activeSync("purple", .forward, at: now), .crowd(.init(seconds: 120, reports: 3, riders: 3, newestAt: now)))
        // A crowd estimate stops counting once it's older than the server's window.
        XCTAssertEqual(cal.offset("purple", .forward, at: now.addingTimeInterval(Calibration.crowdLifetime + 1)), 0)
    }

    func testMoreRecentObservationWins() throws {
        let cal = Calibration(defaults: defaults())
        let base = ScheduleFeed()
        var parts = DateComponents(); parts.year = 2026; parts.month = 10; parts.day = 7; parts.hour = 13
        let noon = base.calendar.date(from: parts)!
        let scheduled = try XCTUnwrap(base.arrivals(at: "indiranagar", from: noon, limit: 20).first { $0.lineID == "purple" && $0.direction == .forward })
        // The rider saw the train 60 s late...
        cal.record(Sighting(lineID: "purple", direction: .forward, stationID: "indiranagar",
                            trainAt: scheduled.time.addingTimeInterval(60), source: .tapped, recorded: noon), base: base)
        // ...and the crowd's report is older, so the rider's own sighting wins.
        cal.applyCrowd(["purple-forward": .init(seconds: 200, reports: 2, riders: 2, newestAt: scheduled.time.addingTimeInterval(-600))])
        XCTAssertEqual(cal.offset("purple", .forward, at: scheduled.time), 60, accuracy: 1)
        // A newer crowd estimate takes over.
        cal.applyCrowd(["purple-forward": .init(seconds: 200, reports: 2, riders: 2, newestAt: scheduled.time.addingTimeInterval(600))])
        XCTAssertEqual(cal.offset("purple", .forward, at: scheduled.time), 200, accuracy: 1)
    }

    func testRecordingASightingIsHandedOnForSharing() throws {
        let cal = Calibration(defaults: defaults())
        let base = ScheduleFeed()
        var shared: (Sighting, TimeInterval)?
        cal.onRecord = { shared = ($0, $1) }
        var parts = DateComponents(); parts.year = 2026; parts.month = 10; parts.day = 7; parts.hour = 13
        let noon = base.calendar.date(from: parts)!
        let scheduled = try XCTUnwrap(base.arrivals(at: "indiranagar", from: noon, limit: 20).first { $0.lineID == "purple" && $0.direction == .forward })
        cal.record(Sighting(lineID: "purple", direction: .forward, stationID: "indiranagar",
                            trainAt: scheduled.time.addingTimeInterval(45), source: .platformBoard, recorded: noon), base: base)
        let (sighting, shift) = try XCTUnwrap(shared)
        XCTAssertEqual(sighting.source, .platformBoard)
        XCTAssertEqual(shift, 45, accuracy: 1)
    }

    @MainActor
    func testRefreshDecodesServerResponse() async {
        StubProtocol.body = Data(#"{"generatedAt":"2026-10-08T16:04:40.777Z","windowMinutes":45,"lines":{"green-reverse":{"offsetSeconds":-45,"reports":2,"riders":2,"newestAt":"2026-10-08T16:04:20.000Z"}}}"#.utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let cal = Calibration(defaults: defaults())
        let sync = CrowdSync(calibration: cal, defaults: defaults(), session: URLSession(configuration: config))
        await sync.refresh()
        XCTAssertNil(sync.lastError)
        XCTAssertEqual(cal.crowd["green-reverse"]?.seconds, -45)
        XCTAssertEqual(cal.crowd["green-reverse"]?.riders, 2)
    }
}
