import SwiftUI

struct StationsScreen: View {
    let feed: TrainFeed
    @State private var query = ""

    private var stations: [Station] {
        let all = MetroNetwork.stations.values.sorted { $0.name < $1.name }
        return query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(stations) { station in
                NavigationLink(value: station) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.name)
                        HStack(spacing: 4) {
                            ForEach(MetroNetwork.lines.filter { $0.stationIDs.contains(station.id) }) {
                                Circle().fill($0.color).frame(width: 8, height: 8)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stations")
            .navigationDestination(for: Station.self) { StationDetailView(feed: feed, station: $0) }
            .searchable(text: $query, prompt: "Search stations")
        }
    }
}

struct StationDetailView: View {
    let feed: TrainFeed
    let station: Station

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let arrivals = feed.arrivals(at: station.id, from: context.date, limit: 12)
            List {
                if arrivals.isEmpty {
                    Text("No more trains scheduled right now.").foregroundStyle(.secondary)
                }
                ForEach(arrivals) { arrival in
                    let line = MetroNetwork.lines.first { $0.id == arrival.lineID }
                    HStack {
                        Circle().fill(line?.color ?? .gray).frame(width: 12, height: 12)
                        VStack(alignment: .leading) {
                            Text("Towards \(arrival.destinationName)")
                            Text(line?.name ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(label(for: arrival.time, now: context.date)).monospacedDigit().bold()
                    }
                }
                if feed.isEstimated {
                    Text("Times are estimated from the timetable, not live train data.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(station.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(for time: Date, now: Date) -> String {
        let minutes = Int(time.timeIntervalSince(now) / 60)
        return minutes < 1 ? "Due" : "\(minutes) min"
    }
}
