import XCTest

/// Scripted walkthrough for recording promo videos (scheme "Demo"; not part of
/// the normal test run). Prints "DEMO <mark> <epoch seconds>" so a recording can
/// be cut at the right moments.
final class DemoTour: XCTestCase {
    private func mark(_ name: String) {
        print("DEMO \(name) \(Date().timeIntervalSince1970)")
    }

    private func pause(_ seconds: Double) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func testPlanAndTrack() {
        let app = XCUIApplication()
        app.launchArguments = ["-plan.from", "electronics-city", "-plan.to", "indiranagar", "-tracker.journey", "", "-calibration.offsets", ""]
        app.launch()
        // Allow notifications if asked (first run only).
        addUIInterruptionMonitor(withDescription: "alerts") { alert in
            for label in ["Allow", "Allow While Using App"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS '–'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        pause(1)
        mark("plan")
        pause(3)
        first.tap()
        mark("detail")
        pause(2.5)
        app.swipeUp(velocity: .slow)
        pause(1.5)
        app.buttons["Start trip"].tap()
        mark("trip")
        app.tap()  // lets the interruption monitor handle a permission alert
        pause(5)
        app.tabBars.buttons["Live Map"].tap()
        mark("map")
        pause(5)
        mark("end")
    }

    /// One 3D take: launches straight into a ride (the map flies onto the train first).
    private func ride(_ args: [String], seconds: Double, then cameras: [String] = []) {
        let app = XCUIApplication()
        // No saved trip: its status bar would sit over the 3D view.
        app.launchArguments = args + ["-tracker.journey", ""]
        app.launch()
        mark("rideLaunch")
        pause(seconds)
        for camera in cameras where app.buttons[camera].exists {
            app.buttons[camera].tap()
            mark(camera)
            pause(6)
        }
        mark("end")
    }

    func testRideDay() {
        ride(["-autoRide", "purple", "-rideNear", "indiranagar", "-skyHour", "17.3"], seconds: 16, then: ["Front"])
    }

    func testRideNight() {
        ride(["-autoRide", "purple", "-rideNear", "indiranagar", "-skyHour", "19.6"], seconds: 14)
    }

    func testRideTracksideBTM() {
        ride(["-autoRide", "yellow", "-rideNear", "btm-layout", "-rideCamera", "Trackside", "-skyHour", "10"], seconds: 14)
    }

    func testRideTrackside() {
        ride(["-autoRide", "yellow", "-rideNear", "jayadeva-hospital", "-rideCamera", "Trackside", "-skyHour", "10"], seconds: 12)
    }

    /// Plan screen scrolled to the accuracy note, for checking crowd sync by eye.
    func testAccuracyNote() {
        let app = XCUIApplication()
        app.launchArguments = ["-plan.from", "indiranagar", "-plan.to", "mg-road", "-tracker.journey", "", "-calibration.offsets", ""]
        app.launch()
        pause(20)
        app.swipeUp()
        app.swipeUp()
        mark("note")
        pause(6)
    }
}
