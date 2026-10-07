import MapKit
import SwiftUI

struct MapScreen: View {
    let feed: TrainFeed

    /// Tilted city view so buildings read as 3D blocks once you zoom in.
    @State private var camera: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 12.955, longitude: 77.595),
                  distance: 34_000, heading: 0, pitch: 40))
    @State private var hiddenLines: Set<String> = []
    @State private var selectedStation: Station?
    /// Camera distance in metres, used to size trains so they read at any zoom.
    @State private var cameraDistance: Double = 34_000
    /// Camera to return to after a ride, and the map's camera right now.
    @State private var lastCamera: MapCamera?
    @State private var liveCamera: MapCamera?
    @State private var ride: RideTarget?
    @State private var rideShown = false
    @State private var rideReady = false
    @State private var zoomDone = false

    private struct RideTarget: Identifiable {
        let id: String
        var camera: RideCamera = .follow
        var entry: RideEntry
        var returnCamera: MapCamera?
    }

    /// Map camera the ride zooms into before the 3D scene takes over.
    private static let entryDistance = 1100.0
    private static let entryPitch = 60.0

    var body: some View {
        ZStack {
            liveMap
                .overlay(alignment: .bottom) { legend.opacity(ride == nil ? 1 : 0) }

            if let ride {
                RideView(feed: feed, trainID: ride.id, camera: ride.camera, entry: ride.entry, started: rideShown,
                         onReady: { rideReady = true; revealRide() }, onClose: closeRide)
                    .opacity(rideShown ? 1 : 0)
                    .allowsHitTesting(rideShown)
            }
        }
        .toolbar(ride == nil ? .automatic : .hidden, for: .tabBar)
        .task { RideAssets.prewarm() }
        .sheet(item: $selectedStation) { station in
            NavigationStack { StationDetailView(feed: feed, station: station) }
                .presentationDetents([.medium, .large])
        }
        #if DEBUG
        .onAppear(perform: debugAutoRide)
        #endif
    }

    // MARK: Ride transition

    /// Zooms and tilts the map onto the train along its direction of travel, then
    /// cross-fades into the 3D scene, which starts from the same viewpoint.
    private func startRide(_ train: Train, camera mode: RideCamera = .follow) {
        guard ride == nil, let track = MetroNetwork.tracks[train.lineID] else { return }
        let sign = train.direction == .forward ? 1.0 : -1.0
        let t = track.tangent(at: train.distance) * sign
        let heading = atan2(t.x, -t.y) * 180 / .pi
        let entry = RideEntry(center: train.coordinate, distance: Self.entryDistance, heading: heading,
                              pitch: Self.entryPitch)
        ride = RideTarget(id: train.id, camera: mode, entry: entry, returnCamera: lastCamera)
        withAnimation(.easeInOut(duration: 1.1)) {
            camera = .camera(MapCamera(centerCoordinate: train.coordinate, distance: Self.entryDistance,
                                       heading: heading, pitch: Self.entryPitch))
        }
        rideReady = false
        zoomDone = false
        // The map reports when its flight lands (onMapCameraChange .onEnd); these are fallbacks.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { zoomDone = true; revealRide() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { rideReady = true; revealRide() }
    }

    /// Fades the 3D scene in once the map has landed and the scene's ground has loaded,
    /// starting the 3D camera from the map's actual final camera.
    private func revealRide() {
        guard ride != nil, zoomDone, rideReady, !rideShown else { return }
        if let cam = liveCamera {
            ride?.entry = RideEntry(center: cam.centerCoordinate, distance: cam.distance, heading: cam.heading,
                                    pitch: cam.pitch)
        }
        withAnimation(.easeInOut(duration: 0.6)) { rideShown = true }
    }

    private func closeRide() {
        let back = ride?.returnCamera
        withAnimation(.easeInOut(duration: 0.45)) { rideShown = false }
        zoomDone = true   // returning flight shouldn't count as an arrival
        if let back {
            withAnimation(.easeInOut(duration: 1.1)) { camera = .camera(back) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ride = nil }
    }

    #if DEBUG
    /// `-autoRide <lineID> [-rideNear <stationID>] [-rideCamera Follow|Front|Trackside]` opens the 3D view on launch.
    private func debugAutoRide() {
        let args = UserDefaults.standard
        guard let lineID = args.string(forKey: "autoRide"), let line = MetroNetwork.line(lineID) else { return }
        let running = feed.trains(at: .now).filter { $0.lineID == lineID && $0.status == .moving }
        // `-rideNear <stationID>` picks the train closest to that station.
        let near = args.string(forKey: "rideNear").flatMap { id in
            line.stationIDs.firstIndex(of: id).map { line.track.stationDistances[$0] }
        }
        guard let train = near.map({ s in running.min { abs($0.distance - s) < abs($1.distance - s) } }) ?? running.first
        else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            startRide(train, camera: args.string(forKey: "rideCamera").flatMap(RideCamera.init) ?? .follow)
        }
    }
    #endif

    // MARK: Map

    private var visibleLines: [MetroLine] {
        MetroNetwork.lines.filter { !hiddenLines.contains($0.id) }
    }

    /// The map itself is static (lines and stations); trains are drawn on a canvas
    /// above it every display frame, so they glide and the map never re-lays overlays.
    private var liveMap: some View {
        MapReader { proxy in
            Map(position: $camera) {
                ForEach(visibleLines) { line in
                    lineContent(line)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls { MapCompass(); MapPitchToggle() }
            .onMapCameraChange(frequency: .continuous) { context in
                let next = context.camera.distance
                if abs(next - cameraDistance) > cameraDistance * 0.05 { cameraDistance = next }
                if ride == nil { lastCamera = context.camera }
                liveCamera = context.camera
            }
            .onMapCameraChange(frequency: .onEnd) { _ in
                if ride != nil, !zoomDone {
                    zoomDone = true
                    revealRide()
                }
            }
            .onTapGesture { point in
                if let train = train(near: point, proxy: proxy) { startRide(train) }
            }
            .overlay {
                TimelineView(.animation(paused: rideShown)) { context in
                    Canvas { gc, _ in drawTrains(at: context.date, in: gc, proxy: proxy) }
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                TimelineView(.periodic(from: .now, by: 2)) { context in
                    header(trainCount: feed.trains(at: context.date).filter { !hiddenLines.contains($0.lineID) }.count)
                }
                .opacity(ride == nil ? 1 : 0)
            }
        }
    }

    /// Rough metres per screen point at the centre of the view (tilt-independent).
    private var metersPerPoint: Double { cameraDistance / 900 }

    @MapContentBuilder
    private func lineContent(_ line: MetroLine) -> some MapContent {
        MapPolyline(coordinates: line.coordinates)
            .stroke(line.color.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .mapOverlayLevel(level: .aboveLabels)
        ForEach(line.stations) { station in
            Annotation("", coordinate: station.coordinate) {
                stationDot(station, color: line.color)
            }
        }
    }

    /// Each train as a short bar riding its own side of the track, white head first.
    private func drawTrains(at date: Date, in gc: GraphicsContext, proxy: MapProxy) {
        let m = metersPerPoint
        for train in feed.trains(at: date) where !hiddenLines.contains(train.lineID) {
            let points = trainPath(train, metersPerPoint: m).compactMap { proxy.convert($0, to: .local) }
            guard points.count > 1, let head = points.first else { continue }
            var path = Path()
            path.addLines(points)
            let color = MetroNetwork.line(train.lineID)?.color ?? .gray
            gc.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            gc.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            gc.fill(Path(ellipseIn: CGRect(x: head.x - 3.2, y: head.y - 3.2, width: 6.4, height: 6.4)), with: .color(.white))
        }
    }

    /// Head-first coordinates of a train's bar. It is drawn ~32 pt long (never
    /// shorter than the real 128 m train) and offset to its direction's side.
    private func trainPath(_ train: Train, metersPerPoint m: Double) -> [CLLocationCoordinate2D] {
        guard let track = MetroNetwork.tracks[train.lineID] else { return [train.coordinate] }
        let sign = train.direction == .forward ? 1.0 : -1.0
        let length = max(Double(CarSpec.trainLength), m * 32)
        let lateral = TrackLayout.lateral(for: train.direction) / TrackLayout.trackOffset * max(2, m * 3.5)
        return (0...10).map { k in
            let s = train.distance + sign * length * (0.5 - Double(k) / 10)
            let p = track.point(at: s) + track.right(at: s) * lateral
            return MetroWorld.mapPoint(p).coordinate
        }
    }

    private func train(near point: CGPoint, proxy: MapProxy) -> Train? {
        let trains = feed.trains(at: .now).filter { !hiddenLines.contains($0.lineID) }
        var best: (train: Train, distance: CGFloat)?
        for t in trains {
            for c in trainPath(t, metersPerPoint: metersPerPoint) {
                guard let p = proxy.convert(c, to: .local) else { continue }
                let d = hypot(p.x - point.x, p.y - point.y)
                if d < (best?.distance ?? 30) { best = (t, d) }
            }
        }
        return best?.train
    }

    private func stationDot(_ station: Station, color: Color) -> some View {
        Button {
            selectedStation = station
        } label: {
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(color.opacity(0.8), lineWidth: 1.5))
                .frame(width: 7, height: 7)
                .padding(6)   // larger tap target
        }
        .accessibilityLabel(station.name)
    }

    private func header(trainCount: Int) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text("\(trainCount) trains running")
                if feed.isEstimated {
                    Text("· Estimated from timetable").foregroundStyle(.secondary)
                }
            }
            Text("Tap a train to ride it in 3D").font(.caption).foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 8)
    }

    private var legend: some View {
        VStack(spacing: 4) {
            legendButtons
            Text("Track data \(MetroNetwork.attribution)").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private var legendButtons: some View {
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
    }
}
