import Foundation
import Observation

/// Shares what riders see with metro-buddy-sync and brings back everyone's
/// combined corrections, so one rider's "Train's here" fixes times for all.
///
/// Sent per sighting: line, direction, station, how early or late the train
/// was, when, and how it was seen (tap, platform display, or a stop detected
/// during a trip), plus a random install ID the server only stores as a keyed
/// hash. No location trail, account or name ever leaves the phone.
@Observable
final class CrowdSync {
    static let endpoint = URL(string: "https://metro-buddy-sync.vercel.app")!
    /// Identifies this app to the server. Not a secret (it ships in the app); it filters casual abuse.
    private static let appKey = "gqNcnAyqSs7evswRqAlAwj73OgYlsOa6YbKjsW5fpPvG0jW"
    static let refreshInterval: Duration = .seconds(30)

    let calibration: Calibration
    private(set) var lastFetch: Date?
    private(set) var lastError: String?

    /// Whether this rider's sightings are shared. On by default; explained where the rider syncs.
    var sharing: Bool {
        didSet { defaults.set(sharing, forKey: Self.sharingKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let installID: String
    private static let sharingKey = "crowd.share"
    private static let installKey = "crowd.installID"

    init(calibration: Calibration, defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.calibration = calibration
        self.defaults = defaults
        self.session = session
        sharing = defaults.object(forKey: Self.sharingKey) as? Bool ?? true
        if let id = defaults.string(forKey: Self.installKey) {
            installID = id
        } else {
            installID = UUID().uuidString.lowercased()
            defaults.set(installID, forKey: Self.installKey)
        }
        calibration.onRecord = { [weak self] sighting, shift in
            Task { await self?.report(sighting, shift: shift) }
        }
    }

    // MARK: Fetching

    private struct OffsetsResponse: Decodable {
        struct Line: Decodable {
            let offsetSeconds: Double
            let reports: Int
            let riders: Int
            let newestAt: Date
        }
        let lines: [String: Line]
    }

    /// Keeps the crowd estimates fresh while the app is open; cancel the task to stop.
    @MainActor
    func run() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    @MainActor
    func refresh() async {
        var request = URLRequest(url: Self.endpoint.appending(path: "api/offsets"))
        request.timeoutInterval = 10
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let decoded = try Self.decoder.decode(OffsetsResponse.self, from: data)
            calibration.applyCrowd(decoded.lines.mapValues {
                Calibration.CrowdEstimate(seconds: $0.offsetSeconds, reports: $0.reports, riders: $0.riders, newestAt: $0.newestAt)
            })
            lastFetch = .now
            lastError = nil
        } catch {
            // Keep the last estimates; they age out on their own.
            lastError = error.localizedDescription
        }
    }

    // MARK: Reporting

    func report(_ sighting: Sighting, shift: TimeInterval) async {
        guard sharing else { return }
        var request = URLRequest(url: Self.endpoint.appending(path: "api/sightings"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(Self.appKey, forHTTPHeaderField: "x-app-key")
        let body: [String: Any] = [
            "installId": installID,
            "line": sighting.lineID,
            "direction": sighting.direction.rawValue,
            "stationId": sighting.stationID,
            "offsetSeconds": Int(shift.rounded()),
            "observedAt": ISO8601DateFormatter().string(from: sighting.trainAt),
            "source": sighting.source.rawValue,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: request)
        // Pick up our own report (and anyone else's) without waiting for the next tick.
        await refresh()
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Bad date \(s)")
        }
        return d
    }()
}
