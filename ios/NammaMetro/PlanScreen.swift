import CoreLocation
import SwiftUI

struct PlanScreen: View {
    let feed: TrainFeed
    @Environment(TripTracker.self) private var tracker

    @AppStorage("plan.from") private var fromID = ""
    @AppStorage("plan.to") private var toID = ""
    @State private var leaveAt: Date?
    @State private var picking: Field?
    @State private var nearest = NearestStation()

    enum Field: String, Identifiable { case from, to; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 15)) { context in
            List {
                if tracker.journey != nil {
                    Section {
                        NavigationLink { TripView(feed: feed) } label: { TripBar(feed: feed) }
                    }
                }
                Section { stationFields }
                Section { timeChooser }
                results(now: context.date)
            }
            }
            .navigationTitle("Plan")
            .navigationDestination(for: Journey.self) { JourneyDetailView(feed: feed, journey: $0) }
            .sheet(item: $picking) { field in
                StationPicker(nearest: nearest) { station in
                    if field == .from { fromID = station.id } else { toID = station.id }
                    picking = nil
                }
            }
        }
    }

    private var stationFields: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                fieldRow("From", id: fromID) { picking = .from }
                Divider()
                fieldRow("To", id: toID) { picking = .to }
            }
            Button {
                (fromID, toID) = (toID, fromID)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Swap stations")
        }
    }

    private func fieldRow(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                if let station = MetroNetwork.stations[id] {
                    LineDots(stationID: id)
                    Text(station.name).foregroundStyle(.primary)
                } else {
                    Text("Choose station").foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var timeChooser: some View {
        HStack {
            Picker("Leave", selection: Binding(
                get: { leaveAt == nil },
                set: { leaveAt = $0 ? nil : (leaveAt ?? .now) })
            ) {
                Text("Now").tag(true)
                Text("Later").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
            if let leaveAt {
                Spacer()
                DatePicker("", selection: Binding(get: { leaveAt }, set: { self.leaveAt = $0 }),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func results(now: Date) -> some View {
        if MetroNetwork.stations[fromID] != nil, MetroNetwork.stations[toID] != nil, fromID != toID {
            let start = leaveAt ?? now
            let options = Planner(feed: feed).plan(from: fromID, to: toID, leaving: start)
            Section {
                if options.isEmpty {
                    Text("No trains found for this trip in the next few hours.")
                        .foregroundStyle(.secondary)
                }
                ForEach(options, id: \.journey.id) { option in
                    NavigationLink(value: option.journey) {
                        JourneyRow(journey: option.journey, times: option.times, now: now)
                    }
                }
            } footer: {
                AccuracyNote(feed: feed, lineIDs: Set(options.flatMap { $0.journey.legs.map(\.lineID) }))
            }
        } else if fromID == toID, !fromID.isEmpty {
            Text("Pick two different stations.").foregroundStyle(.secondary)
        }
    }
}

/// One journey option: times, duration, changes, fare and the lines used.
struct JourneyRow: View {
    let journey: Journey
    let times: JourneyTimes
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(times.depart.metroTime) – \(times.arrive.metroTime)")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Spacer()
                Text(leavesLabel).font(.subheadline.weight(.medium)).monospacedDigit()
                    .foregroundStyle(times.depart.timeIntervalSince(now) < 5 * 60 ? .orange : .secondary)
            }
            HStack(spacing: 6) {
                ForEach(Array(journey.legs.enumerated()), id: \.offset) { i, leg in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    LineChip(lineID: leg.lineID)
                }
            }
            Text(summary).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var leavesLabel: String {
        let m = Int(times.depart.timeIntervalSince(now) / 60)
        if m < 1 { return "Leaving" }
        if m < 90 { return "in \(m) min" }
        let sameDay = Calendar.current.isDate(times.depart, inSameDayAs: now)
        return sameDay ? "in \(m / 60) h" : "Tomorrow"
    }

    private var summary: String {
        let changes = journey.transfers == 0 ? "Direct" : journey.transfers == 1 ? "1 change" : "\(journey.transfers) changes"
        return "\(Int((times.duration / 60).rounded())) min · \(changes) · ₹\(journey.fare)"
    }
}

struct JourneyDetailView: View {
    let feed: TrainFeed
    let journey: Journey
    @Environment(TripTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    @State private var showTrip = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { _ in
            if let times = JourneyTimes(journey, feed: feed) {
                List {
                    Section {
                        LabeledContent("Leaves", value: times.depart.metroTime)
                        LabeledContent("Arrives", value: times.arrive.metroTime)
                        LabeledContent("Travel time", value: "\(Int((times.duration / 60).rounded())) min")
                        LabeledContent("Fare", value: "₹\(journey.fare) token/QR · ₹\(Fare.smartCard(journey.fare, at: times.depart).formatted(.number.precision(.fractionLength(0...2)))) card")
                        LabeledContent("Distance", value: String(format: "%.1f km", journey.distance / 1000))
                    }
                    ForEach(Array(times.legs.enumerated()), id: \.offset) { n, leg in
                        Section {
                            LegStops(leg: leg, highlight: nil)
                        } header: {
                            legHeader(n: n, leg: leg, times: times)
                        }
                    }
                    Section {
                        AccuracyNote(feed: feed, lineIDs: Set(journey.legs.map(\.lineID)))
                    }
                }
            } else {
                ContentUnavailableView("This train has left", systemImage: "tram",
                                       description: Text("Go back and pick a later train."))
            }
        }
        .navigationTitle(MetroNetwork.stations[journey.toID]?.name ?? "Journey")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                tracker.start(journey)
                showTrip = true
            } label: {
                Label(tracker.journey?.id == journey.id ? "Tracking this trip" : "Start trip", systemImage: "location.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
        .navigationDestination(isPresented: $showTrip) { TripView(feed: feed) }
    }

    @ViewBuilder
    private func legHeader(n: Int, leg: TimedLeg, times: JourneyTimes) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if n > 0 {
                let wait = leg.depart.timeIntervalSince(times.legs[n - 1].arrive)
                Text("Change at \(MetroNetwork.stations[leg.leg.fromID]?.name ?? "") · \(Int(wait / 60)) min")
                    .textCase(nil).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }
            HStack {
                LineChip(lineID: leg.leg.lineID)
                Text("towards \(leg.leg.towards)").textCase(nil)
                Spacer()
                Text("\(leg.stops.count - 1) stops").textCase(nil)
            }
        }
    }
}

/// Stops of one leg with times; the highlighted index is the train's next stop.
struct LegStops: View {
    let leg: TimedLeg
    let highlight: Int?

    var body: some View {
        let color = leg.leg.line?.color ?? .gray
        ForEach(Array(leg.stops.enumerated()), id: \.offset) { i, stop in
            let passed = highlight.map { i < $0 } ?? false
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().fill(color.opacity(passed ? 0.3 : 1))
                        .frame(width: 4)
                        .padding(.top, i == 0 ? 22 : 0)
                        .padding(.bottom, i == leg.stops.count - 1 ? 22 : 0)
                    Circle()
                        .fill(i == highlight ? color : Color(.systemBackground))
                        .overlay(Circle().stroke(color.opacity(passed ? 0.3 : 1), lineWidth: 2.5))
                        .frame(width: i == 0 || i == leg.stops.count - 1 || i == highlight ? 14 : 9)
                }
                .frame(width: 16)
                Text(MetroNetwork.stations[stop.stationID]?.name ?? stop.stationID)
                    .font(i == 0 || i == leg.stops.count - 1 ? .body.weight(.semibold) : .body)
                    .foregroundStyle(passed ? .secondary : .primary)
                Spacer()
                Text((i == 0 ? stop.depart : stop.arrive).metroTime)
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .frame(minHeight: 44)
        }
    }
}

/// Says how far to trust the times: synced from a sighting, or timetable only.
struct AccuracyNote: View {
    let feed: TrainFeed
    let lineIDs: Set<String>
    @Environment(TripTracker.self) private var tracker

    var body: some View {
        let synced = lineIDs.sorted().compactMap { id -> (String, Calibration.Offset)? in
            for d in [Direction.forward, .reverse] {
                if let o = tracker.calibration.activeOffset(id, d) { return (id, o) }
            }
            return nil
        }
        VStack(alignment: .leading, spacing: 4) {
            if !feed.isEstimated {
                Text("Live train data.")
            } else if synced.isEmpty {
                Text("Times follow BMRCL’s published timetable. Times between the end stations are modelled and usually within 2 min. Start the trip and tap “Train’s here” on the platform to sync with the real trains.")
            } else {
                ForEach(synced, id: \.0) { id, o in
                    Text("\(MetroNetwork.line(id)?.name ?? id) synced \(o.sighting.recorded.formatted(.relative(presentation: .named))): \(o.seconds.delayText).")
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        Text(Timetable.bundled.attribution)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

struct LineChip: View {
    let lineID: String

    var body: some View {
        let line = MetroNetwork.line(lineID)
        Text(line?.name.replacingOccurrences(of: " Line", with: "") ?? lineID)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(line?.color ?? .gray, in: Capsule())
            .foregroundStyle(lineID == "yellow" ? Color.black : Color.white)
    }
}

struct LineDots: View {
    let stationID: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(MetroNetwork.lines.filter { $0.stationIDs.contains(stationID) }) {
                Circle().fill($0.color).frame(width: 8, height: 8)
            }
        }
    }
}

struct StationPicker: View {
    let nearest: NearestStation
    let onPick: (Station) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        Button {
                            if let station = nearest.station { onPick(station) } else { nearest.locate() }
                        } label: {
                            if let station = nearest.station {
                                HStack {
                                    Label(station.name, systemImage: "location.fill")
                                    Spacer()
                                    if let d = nearest.distance {
                                        Text(d < 1000 ? "\(Int(d)) m" : String(format: "%.1f km", d / 1000))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                Label(nearest.denied ? "Location is off for Namma Metro" : "Nearest station",
                                      systemImage: "location")
                            }
                        }
                    }
                }
                Section {
                    ForEach(stations) { station in
                        Button { onPick(station) } label: {
                            HStack {
                                Text(station.name).foregroundStyle(.primary)
                                Spacer()
                                LineDots(stationID: station.id)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search stations")
            .navigationTitle("Station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { nearest.locate() }
        }
    }

    private var stations: [Station] {
        let all = MetroNetwork.stations.values.sorted { $0.name < $1.name }
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

/// One-shot "which station am I closest to".
@Observable
final class NearestStation: NSObject, CLLocationManagerDelegate {
    private(set) var station: Station?
    private(set) var distance: CLLocationDistance?
    private(set) var denied = false
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func locate() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: denied = true
        default: manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        denied = [.denied, .restricted].contains(manager.authorizationStatus)
        if [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let here = locations.last else { return }
        let best = MetroNetwork.stations.values
            .map { ($0, here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .min { $0.1 < $1.1 }
        station = best?.0
        distance = best?.1
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension Date {
    /// "08:42" in Bengaluru time, whatever the phone's time zone.
    var metroTime: String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return formatted(style)
    }
}

extension TimeInterval {
    var delayText: String {
        let s = Int(self.rounded())
        if abs(s) < 20 { return "on time" }
        let m = abs(s) / 60, r = abs(s) % 60
        let amount = m == 0 ? "\(r) s" : r == 0 ? "\(m) min" : "\(m) min \(r) s"
        return s > 0 ? "running \(amount) late" : "running \(amount) early"
    }
}
