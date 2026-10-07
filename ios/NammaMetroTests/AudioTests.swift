import AVFoundation
import XCTest
@testable import NammaMetro

final class AudioTests: XCTestCase {
    func testSoundsAreCleanAndLoopSeamlessly() {
        let sounds: [(String, [Float])] = [
            ("music", Synth.music()), ("rumble", Synth.rumble()), ("whine", Synth.whine()),
            ("chime", Synth.chime()), ("doorBeeps", Synth.doorBeeps()),
        ]
        for (name, samples) in sounds {
            XCTAssertFalse(samples.contains { !$0.isFinite }, name)
            XCTAssertLessThanOrEqual(samples.map(abs).max() ?? 0, 0.81, "\(name) clips")
            XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.1, "\(name) is silent")
        }
        // Loops: the jump from the last sample back to the first is no bigger than a normal step.
        for (name, samples) in sounds.prefix(3) {
            let steps = zip(samples, samples.dropFirst()).map { abs($1 - $0) }.sorted()
            let typical = steps[Int(Double(steps.count) * 0.999)]
            XCTAssertLessThanOrEqual(abs(samples[0] - samples[samples.count - 1]), typical * 1.5, "\(name) loop seam")
        }
        if let dir = ProcessInfo.processInfo.environment["AUDIO_PREVIEW_DIR"] {
            for (name, samples) in sounds { try? writeWAV(samples, to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).wav")) }
        }
    }

    func testEngineRunsAndAnnounces() {
        let audio = MetroAudio.shared
        audio.start(context: .ride)
        for i in 0..<30 { audio.update(speed: Double(i) * 0.5, underground: i > 15, cameraDistance: 40) }
        audio.arrived(at: "majestic")
        audio.departing()
        audio.announceNext(stationID: "majestic", lineID: "purple", isLast: false)
        let done = expectation(description: "audio ran")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { done.fulfill() }
        wait(for: [done], timeout: 5)
        audio.stop()
    }

    private func writeWAV(_ samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
