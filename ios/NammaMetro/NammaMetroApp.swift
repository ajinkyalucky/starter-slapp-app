import SwiftUI

@main
struct NammaMetroApp: App {
    private let feed: TrainFeed = ScheduleFeed()

    var body: some Scene {
        WindowGroup {
            TabView {
                MapScreen(feed: feed)
                    .tabItem { Label("Live Map", systemImage: "map") }
                StationsScreen(feed: feed)
                    .tabItem { Label("Stations", systemImage: "tram.fill") }
            }
        }
    }
}
