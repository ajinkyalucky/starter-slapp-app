import MapKit
import SwiftUI

struct MapScreen: View {
    let feed: TrainFeed

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)))
    @State private var hiddenLines: Set<String> = []
    @State private var selectedStation: Station?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            liveMap(at: context.date)
        }
        .overlay(alignment: .bottom) { legend }
        .sheet(item: $selectedStation) { station in
            NavigationStack { StationDetailView(feed: feed, station: station) }
                .presentationDetents([.medium, .large])
        }
    }

    private var visibleLines: [MetroLine] {
        MetroNetwork.lines.filter { !hiddenLines.contains($0.id) }
    }

    private func liveMap(at date: Date) -> some View {
        let trains: [Train] = feed.trains(at: date).filter { !hiddenLines.contains($0.lineID) }
        return Map(position: $camera) {
            ForEach(visibleLines) { line in
                lineContent(line)
            }
            ForEach(trains) { train in
                Annotation("", coordinate: train.coordinate) {
                    TrainMarker(train: train)
                }
            }
        }
        .overlay(alignment: .top) { header(trainCount: trains.count) }
    }

    @MapContentBuilder
    private func lineContent(_ line: MetroLine) -> some MapContent {
        MapPolyline(coordinates: line.coordinates)
            .stroke(line.color, lineWidth: 4)
        ForEach(line.stations) { station in
            Annotation("", coordinate: station.coordinate) {
                stationDot(station, color: line.color)
            }
        }
    }

    private func stationDot(_ station: Station, color: Color) -> some View {
        Button {
            selectedStation = station
        } label: {
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(color, lineWidth: 2))
                .frame(width: 10, height: 10)
        }
        .accessibilityLabel(station.name)
    }

    private func header(trainCount: Int) -> some View {
        HStack {
            Text("\(trainCount) trains running")
            if feed.isEstimated {
                Text("· Estimated from timetable").foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 8)
    }

    private var legend: some View {
        HStack {
            ForEach(MetroNetwork.lines) { line in
                let hidden = hiddenLines.contains(line.id)
                Button {
                    if hidden { hiddenLines.remove(line.id) } else { hiddenLines.insert(line.id) }
                } label: {
                    Label(line.name, systemImage: hidden ? "circle" : "circle.fill")
                        .font(.caption)
                        .foregroundStyle(line.color)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 8)
    }
}

struct TrainMarker: View {
    let train: Train

    var body: some View {
        let color = MetroNetwork.lines.first { $0.id == train.lineID }?.color ?? .gray
        Image(systemName: "tram.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(radius: 2)
    }
}
