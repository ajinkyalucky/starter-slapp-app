import QuartzCore
import Foundation

/// Frame-rate logging for profiling on a device: launch with `-perfLog YES` and read
/// stderr (e.g. `xcrun devicectl device process launch --console`). Silent otherwise.
final class PerfMonitor {
    static let enabled = UserDefaults.standard.bool(forKey: "perfLog")

    private let name: String
    private let lock = NSLock()
    private var windowStart: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var worst: CFTimeInterval = 0
    private var work: CFTimeInterval = 0

    init(_ name: String) { self.name = name }

    /// One-off marker line (ride opened, scene ready, ...).
    static func mark(_ text: String) {
        guard enabled else { return }
        fputs("PERF mark \(text) t=\(String(format: "%.2f", CACurrentMediaTime()))\n", stderr)
    }

    /// Call once per frame with the CPU time the frame's own work took.
    func frame(work cost: CFTimeInterval) {
        guard Self.enabled else { return }
        let now = CACurrentMediaTime()
        lock.lock(); defer { lock.unlock() }
        if windowStart == 0 { windowStart = now; last = now; return }
        frames += 1
        worst = max(worst, now - last)
        work += cost
        last = now
        if now - windowStart >= 5 {
            let fps = Double(frames) / (now - windowStart)
            let line = String(format: "PERF %@ fps=%.1f worst=%.1fms work=%.2fms\n", name, fps, worst * 1000,
                              work / Double(max(frames, 1)) * 1000)
            fputs(line, stderr)
            windowStart = now
            frames = 0
            worst = 0
            work = 0
        }
    }
}
