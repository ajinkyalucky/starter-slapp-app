import SceneKit
import SwiftUI

/// Full-screen 3D view riding along with one train on its real route.
struct RideView: View {
    @StateObject private var controller: RideSceneController
    @Environment(\.dismiss) private var dismiss

    init(feed: TrainFeed, trainID: String, camera: RideCamera = .follow) {
        let c = RideSceneController(feed: feed, trainID: trainID)
        c.camera = camera
        _controller = StateObject(wrappedValue: c)
    }

    var body: some View {
        ZStack {
            RideSceneView(controller: controller)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
    }

    private var lineColor: Color {
        MetroNetwork.line(controller.hud.lineID)?.color ?? .gray
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")
            HStack(spacing: 6) {
                Circle().fill(lineColor).frame(width: 9, height: 9)
                Text(controller.hud.lineName).fontWeight(.semibold)
                Text("to \(controller.hud.destination)").foregroundStyle(.secondary)
            }
            .font(.footnote)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.ultraThinMaterial, in: Capsule())
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(controller.hud.headline)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(controller.hud.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    if controller.hud.underground {
                        Label("Underground", systemImage: "arrow.down.to.line")
                    }
                    if controller.feed.isEstimated {
                        Text("Estimated from timetable")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
            if controller.hud.terminated {
                Button("Ride the next train") { controller.rideNextTrain() }
                    .buttonStyle(.borderedProminent)
                    .tint(lineColor)
            }
            Picker("Camera", selection: $controller.camera) {
                ForEach(RideCamera.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(.white)
    }
}

/// Hosts the SCNView and forwards gestures to the controller.
struct RideSceneView: UIViewRepresentable {
    let controller: RideSceneController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [
            SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue,
        ])
        view.scene = controller.scene
        view.pointOfView = controller.cameraNode
        view.delegate = controller
        view.isPlaying = true
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.backgroundColor = .black
        view.isJitteringEnabled = false

        let c = context.coordinator
        view.addGestureRecognizer(UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:))))
        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap))
        double.numberOfTapsRequired = 2
        view.addGestureRecognizer(double)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    final class Coordinator: NSObject {
        let controller: RideSceneController
        init(controller: RideSceneController) { self.controller = controller }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            controller.orbit(by: g.translation(in: g.view))
            g.setTranslation(.zero, in: g.view)
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            controller.zoom(by: g.scale)
            g.scale = 1
        }

        @objc func doubleTap() { controller.resetView() }
    }
}
