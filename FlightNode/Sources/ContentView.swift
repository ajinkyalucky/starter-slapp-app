import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var location = LocationService()
    @State private var plan: FlightPlan = .outbound
    @State private var radiusKm = 150.0
    private let geo = GeoData.load()
    private var engine: InsightEngine { InsightEngine(geo: geo) }

    var body: some View {
        VStack(spacing: 0) {
            MapCanvas(geo: geo, plan: plan, fix: location.fix, radiusKm: radiusKm)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topTrailing) { zoomControl }
                .overlay(alignment: .topLeading) { statusBadge }
            panel
        }
        .onAppear { location.plan = plan; location.start() }
        .onChange(of: plan.id) { _ in location.plan = plan }
    }

    // MARK: pieces

    private var zoomControl: some View {
        VStack {
            Button { radiusKm = max(20, radiusKm / 1.6) } label: { Image(systemName: "plus.magnifyingglass") }
            Button { radiusKm = min(900, radiusKm * 1.6) } label: { Image(systemName: "minus.magnifyingglass") }
        }
        .padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(8)
    }

    private var statusBadge: some View {
        let text: String = {
            if location.simulate { return "SIMULATION" }
            switch location.authorization {
            case .denied, .restricted: return "Location denied — enable in Settings"
            case .notDetermined: return "Waiting for permission…"
            default: return location.fix == nil ? "Acquiring GPS… (hold near a window)" : "GPS ±\(Int(location.fix!.accuracyM)) m"
            }
        }()
        return Text(text).font(.caption.bold()).padding(6)
            .background(.thinMaterial, in: Capsule()).padding(8)
    }

    private var panel: some View {
        let fix = location.fix
        let insight = fix.map { engine.insight(at: $0.coordinate) }
        let progress = fix.map { plan.progress(at: $0.coordinate, speedKmh: $0.speedKmh) }

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Flight", selection: $plan) {
                    ForEach(FlightPlan.all) { Text("\($0.flightNumber)  \($0.from.code)→\($0.to.code)").tag($0) }
                }.pickerStyle(.segmented)
                Text(plan.note).font(.caption).foregroundStyle(.secondary)

                if let insight {
                    Text(insight.headline).font(.title2.bold())
                    Text(insight.detail).foregroundStyle(.secondary)
                } else {
                    Text("No position yet").font(.title3).foregroundStyle(.secondary)
                }

                if let fix {
                    HStack {
                        stat("Altitude", fix.altitudeM.isNaN ? "—" : "\(Int(fix.altitudeM * 3.28084).formatted()) ft")
                        stat("Speed", "\(Int(fix.speedKmh)) km/h")
                        stat("Heading", fix.courseDeg.map { "\(Int($0))° \(GeoMath.compass($0))" } ?? "—")
                    }
                }
                if let p = progress {
                    ProgressView(value: min(1, max(0, p.fraction)))
                    HStack {
                        stat("Flown", "\(Int(p.distanceDoneKm)) km")
                        stat("To \(plan.to.code)", "\(Int(p.distanceLeftKm)) km")
                        stat("ETA", p.etaMinutes.map { "\(Int($0)) min" } ?? "—")
                    }
                    if abs(p.offRouteKm) > 30 { Text("\(Int(abs(p.offRouteKm))) km off the direct line (normal — airways aren't straight)").font(.caption2).foregroundStyle(.secondary) }
                }

                if let insight {
                    Divider()
                    Text("Nearby").font(.headline)
                    ForEach(insight.nearby.prefix(5)) { Text($0.text).font(.callout) }
                }

                Divider()
                Toggle("Simulate flight (test at home)", isOn: $location.simulate)
                Text("Live aircraft traffic is not shown: the phone alone can't receive it in airplane mode.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding()
        }
        .frame(maxHeight: 330)
        .background(.regularMaterial)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.monospacedDigit().bold())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension FlightPlan: Hashable {
    static func == (l: FlightPlan, r: FlightPlan) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}
