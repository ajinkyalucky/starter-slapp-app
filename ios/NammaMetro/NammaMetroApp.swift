import SwiftUI

@main
struct NammaMetroApp: App {
    private let base: TrainFeed
    private let feed: TrainFeed
    @State private var tracker: TripTracker
    @State private var tab = Tab.plan

    enum Tab { case plan, map, stations }

    init() {
        let base = ScheduleFeed()
        let calibration = Calibration()
        let feed = CalibratedFeed(base: base, calibration: calibration)
        self.base = base
        self.feed = feed
        _tracker = State(initialValue: TripTracker(feed: feed, base: base, calibration: calibration))
        // Launch shortcuts `-autoRide <lineID>` / `-openMap YES` (see MapScreen) need the map tab up front.
        if UserDefaults.standard.string(forKey: "autoRide") != nil || UserDefaults.standard.bool(forKey: "openMap") {
            _tab = State(initialValue: .map)
        }
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                PlanScreen(feed: feed)
                    .tabItem { Label("Plan", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                    .tag(Tab.plan)
                MapScreen(feed: feed)
                    .safeAreaInset(edge: .bottom) { tripBar }
                    .tabItem { Label("Live Map", systemImage: "map") }
                    .tag(Tab.map)
                StationsScreen(feed: feed)
                    .safeAreaInset(edge: .bottom) { tripBar }
                    .tabItem { Label("Stations", systemImage: "tram.fill") }
                    .tag(Tab.stations)
            }
            .environment(tracker)
        }
    }

    /// While a trip is on, other tabs show its status; tapping goes back to it.
    @ViewBuilder
    private var tripBar: some View {
        if tracker.journey != nil {
            Button { tab = .plan } label: {
                TripBar(feed: feed)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }
}
