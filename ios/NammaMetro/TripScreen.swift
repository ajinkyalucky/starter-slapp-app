import SwiftUI

/// The journey in progress: what to do now, the countdown, and the stops.
struct TripView: View {
    let feed: TrainFeed
    @Environment(TripTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    @State private var boardMinutes = 2
    @State private var syncMessage: String?
    @State private var alternatives: [(journey: Journey, times: JourneyTimes)] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let journey = tracker.journey, let times = tracker.times {
                let progress = TripProgress.at(context.date, times)
                List {
                    Section { status(progress, journey: journey, times: times, now: context.date) }
                    if case .waiting(let n, _) = progress { syncSection(leg: n, journey: journey) }
                    if case .riding = progress {
                        Section {
                            Text("Location sync is \(tracker.locationAllowed ? "on" : "off"): stopping at an above-ground station updates the times.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(times.legs.enumerated()), id: \.offset) { n, leg in
                        Section {
                            LegStops(leg: leg, highlight: highlight(progress, leg: n))
                        } header: {
                            HStack {
                                LineChip(lineID: leg.leg.lineID)
                                Text("towards \(leg.leg.towards)").textCase(nil)
                            }
                        }
                    }
                    if !alternatives.isEmpty {
                        Section("Other trains from here") {
                            ForEach(alternatives, id: \.journey.id) { option in
                                Button {
                                    tracker.start(option.journey)
                                    alternatives = []
                                } label: {
                                    JourneyRow(journey: option.journey, times: option.times, now: context.date)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Section {
                        AccuracyNote(feed: feed, lineIDs: Set(journey.legs.map(\.lineID)))
                    }
                }
                .onChange(of: announcement(progress, times: times)) { _, next in
                    if let next { MetroAudio.shared.announceNext(stationID: next.stationID, lineID: next.lineID, isLast: next.isLast) }
                }
            } else {
                ContentUnavailableView("No trip", systemImage: "tram", description: Text("Plan a journey and tap Start trip."))
            }
        }
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { MetroAudio.shared.start(context: .trip) }
        .onDisappear { MetroAudio.shared.stop() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SoundMenu(trip: true) }
            if tracker.journey != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End", role: .destructive) {
                        tracker.end()
                        dismiss()
                    }
                }
            }
        }
    }

    struct Announcement: Equatable {
        let stationID: String
        let lineID: String
        /// The train terminates there.
        let isLast: Bool
    }

    /// The stop to announce: the next one, as soon as the train leaves the previous stop.
    private func announcement(_ progress: TripProgress, times: JourneyTimes) -> Announcement? {
        guard case .riding(let n, let next, _) = progress else { return nil }
        let leg = times.legs[n]
        let id = leg.stops[next].stationID
        return Announcement(stationID: id, lineID: leg.leg.lineID, isLast: MetroNetwork.stations[id]?.name == leg.leg.towards)
    }

    private func highlight(_ progress: TripProgress, leg n: Int) -> Int? {
        switch progress {
        case .waiting(let leg, _): return leg == n ? 0 : (leg > n ? Int.max : nil)
        case .riding(let leg, let next, _): return leg == n ? next : (leg > n ? Int.max : nil)
        case .arrived: return Int.max
        }
    }

    @ViewBuilder
    private func status(_ progress: TripProgress, journey: Journey, times: JourneyTimes, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch progress {
            case .waiting(let n, let departs):
                let leg = journey.legs[n]
                Text(n == 0 ? "Go to the platform" : "Change at \(MetroNetwork.stations[leg.fromID]?.name ?? "")")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    LineChip(lineID: leg.lineID)
                    Text("towards \(leg.towards)").font(.headline)
                }
                Countdown(to: departs, now: now, label: "Train leaves in")
                Button("Missed it? Show later trains") { alternatives = tracker.replanFromCurrentStop(at: now) }
                    .font(.subheadline)
            case .riding(let n, let next, let arrives):
                let stops = times.legs[n].stops
                let name = MetroNetwork.stations[stops[next].stationID]?.name ?? ""
                let remaining = stops.count - 1 - next
                Text(remaining == 0 ? (n == times.legs.count - 1 ? "Get off at" : "Get off and change at") : "Next stop")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(name).font(.title.weight(.semibold))
                Countdown(to: arrives, now: now, label: "Arriving in")
                if remaining > 0 {
                    Text("Then \(remaining) more stop\(remaining == 1 ? "" : "s") to \(MetroNetwork.stations[journey.legs[n].toID]?.name ?? "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            case .arrived(let at):
                Text("You’ve arrived").font(.title.weight(.semibold))
                Text("\(MetroNetwork.stations[journey.toID]?.name ?? "") · \(at.metroTime)").foregroundStyle(.secondary)
                Button("End trip") { tracker.end(); dismiss() }.buttonStyle(.borderedProminent)
            }
            Text("Arrive \(times.arrive.metroTime) · ₹\(journey.fare)")
                .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 6)
    }

    /// On the platform: tell the app what the real trains are doing.
    @ViewBuilder
    private func syncSection(leg n: Int, journey: Journey) -> some View {
        let station = journey.legs[n].fromID
        Section {
            Button {
                let shift = tracker.confirmTrainHere(leg: n, at: station)
                syncMessage = shift.map { "Synced: trains \($0.delayText)." } ?? "That didn’t match a scheduled train; times unchanged."
            } label: {
                Label("Train’s here now", systemImage: "tram.fill")
            }
            HStack {
                Stepper("Board says \(boardMinutes) min", value: $boardMinutes, in: 0...20)
                Button("Sync") {
                    let shift = tracker.confirmTrainHere(leg: n, at: station, date: .now.addingTimeInterval(Double(boardMinutes) * 60))
                    syncMessage = shift.map { "Synced: trains \($0.delayText)." } ?? "That didn’t match a scheduled train; times unchanged."
                }
                .buttonStyle(.bordered)
            }
            if let syncMessage {
                Text(syncMessage).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Sync with the platform").textCase(nil)
        } footer: {
            Text("The platform display shows the real countdown. Entering it here corrects every train on this line and direction for the next 90 minutes.")
        }
    }
}

struct Countdown: View {
    let to: Date
    let now: Date
    let label: String

    var body: some View {
        let s = max(0, Int(to.timeIntervalSince(now)))
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(s < 30 ? "Now" : String(format: "%d:%02d", s / 60, s % 60))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
        }
    }
}

/// Compact trip status for the top of the Plan tab and above other tabs.
struct TripBar: View {
    let feed: TrainFeed
    @Environment(TripTracker.self) private var tracker

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let journey = tracker.journey, let times = tracker.times {
                HStack(spacing: 10) {
                    Image(systemName: "tram.fill")
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(journey.legs.first?.line?.color ?? .accentColor, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line(TripProgress.at(context.date, times), journey: journey, times: times))
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("To \(MetroNetwork.stations[journey.toID]?.name ?? "") · arrive \(times.arrive.metroTime)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func line(_ progress: TripProgress, journey: Journey, times: JourneyTimes) -> String {
        func mins(_ d: Date) -> String {
            let m = Int(d.timeIntervalSince(.now) / 60)
            return m < 1 ? "now" : "in \(m) min"
        }
        switch progress {
        case .waiting(let n, let departs):
            return "Train towards \(journey.legs[n].towards) \(mins(departs))"
        case .riding(let n, let next, let arrives):
            return "\(MetroNetwork.stations[times.legs[n].stops[next].stationID]?.name ?? "") \(mins(arrives))"
        case .arrived:
            return "Arrived"
        }
    }
}
