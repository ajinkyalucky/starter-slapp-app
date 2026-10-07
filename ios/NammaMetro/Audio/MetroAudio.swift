import AVFoundation
import os

/// Ride sounds, background music and trilingual station announcements, all
/// synthesised (`Synth`) or spoken by the system voices.
///
/// `update` may be called every frame from any thread (the 3D view calls it on
/// SceneKit's render thread): it only stores the latest values. A 30 Hz timer
/// on the audio queue applies them to the engine.
final class MetroAudio: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = MetroAudio()

    enum Context { case ride, trip }

    enum Setting: String, CaseIterable {
        case music = "sound.music"
        case trainSounds = "sound.train"
        case announcements = "sound.announce"
        /// Music and announcements while tracking a real trip (off by default: the real train has its own).
        case duringTrips = "sound.duringTrips"

        var defaultValue: Bool { self != .duringTrips }
        var isOn: Bool { UserDefaults.standard.object(forKey: rawValue) as? Bool ?? defaultValue }
    }

    private struct Motion {
        var speed = 0.0
        var underground = false
        var cameraDistance = 30.0
    }

    private let motion = OSAllocatedUnfairLock(initialState: Motion())
    private let queue = DispatchQueue(label: "namma.metro.audio")
    private var timer: DispatchSourceTimer?

    private let engine = AVAudioEngine()
    private let music = AVAudioPlayerNode()
    private let rumble = AVAudioPlayerNode()
    private let whine = AVAudioPlayerNode()
    private let effects = AVAudioPlayerNode()
    private let rumblePitch = AVAudioUnitVarispeed()
    private let whinePitch = AVAudioUnitVarispeed()
    private let trainMixer = AVAudioMixerNode()
    private let distanceFilter = AVAudioUnitEQ(numberOfBands: 1)
    private let reverb = AVAudioUnitReverb()
    private let speech = AVSpeechSynthesizer()

    private struct Buffers {
        let music, rumble, whine, chime, beeps: AVAudioPCMBuffer
    }
    private var buffers: Buffers?
    private var context: Context?
    private var lastSpeed = 0.0
    private var smoothedAccel = 0.0
    private var musicLevel: Float = 0.32
    private var ducked = false
    /// Main thread only. Bumped by `stop()` so an announcement still in flight is dropped.
    private var speechGeneration = 0

    private static let mono = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
    private static let stereo = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 2)!

    private override init() {
        super.init()
        speech.delegate = self
        let band = distanceFilter.bands[0]
        band.filterType = .lowPass
        band.frequency = 8000
        band.bypass = false
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 8
    }

    // MARK: Lifecycle

    /// Starts sound for a screen. Builds the sounds the first time (about a quarter of a second, off the main thread).
    func start(context: Context) {
        queue.async { [self] in
            self.context = context
            if buffers == nil { buffers = Self.makeBuffers(); wire() }
            configureSession()
            do { try engine.start() } catch { return }
            restartLoops()
            startTimer()
        }
    }

    func stop() {
        queue.async { [self] in
            context = nil
            timer?.cancel()
            timer = nil
            [music, rumble, whine, effects].forEach { $0.stop() }
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        DispatchQueue.main.async {
            self.speechGeneration += 1
            self.speech.stopSpeaking(at: .word)
        }
    }

    /// Re-reads the settings (call after a toggle changes).
    func settingsChanged() {
        queue.async { [self] in
            guard context != nil else { return }
            configureSession()
            restartLoops()
        }
    }

    // MARK: Per-frame input (any thread)

    /// `speed` in m/s of the train being followed, `cameraDistance` in metres
    /// from the listener (under ~2 m sounds like the driver's cab).
    func update(speed: Double, underground: Bool, cameraDistance: Double = 30) {
        motion.withLock { $0 = Motion(speed: speed, underground: underground, cameraDistance: cameraDistance) }
    }

    // MARK: Events (main thread)

    func arrived(at stationID: String) {
        play(\.chime, when: .trainSounds)
    }

    func departing() {
        play(\.beeps, when: .trainSounds)
    }

    /// "Next station" in Kannada, English and Hindi, as on Namma Metro trains. Call on the main thread.
    func announceNext(stationID: String, lineID: String, isLast: Bool) {
        let generation = speechGeneration
        queue.async { [self] in
            // `context` belongs to the audio queue; check it there.
            guard allowed(.announcements), let lines = Self.announcement(stationID: stationID, lineID: lineID, isLast: isLast) else { return }
            DispatchQueue.main.async { [self] in
                // stop() ran since the call: the screen is gone, stay quiet.
                guard generation == speechGeneration else { return }
                speech.stopSpeaking(at: .word)
                for (text, language) in lines {
                    let u = AVSpeechUtterance(string: text)
                    u.voice = AVSpeechSynthesisVoice(language: language)
                    u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
                    u.postUtteranceDelay = 0.35
                    speech.speak(u)
                }
            }
        }
    }

    /// The three lines and their voice languages.
    private static func announcement(stationID: String, lineID: String, isLast: Bool) -> [(String, String)]? {
        guard let station = MetroNetwork.stations[stationID] else { return nil }
        let name = station.name
        let changes = MetroNetwork.lines.filter { $0.id != lineID && $0.stationIDs.contains(stationID) }
        var lines: [(String, String)] = []
        if let kannada = kannadaVoice, let kn = Timetable.bundled.kannadaNames?[stationID] {
            lines.append(("ಮುಂದಿನ ನಿಲ್ದಾಣ, \(kn).", kannada.language))
        } else {
            lines.append(("Mundina nildaana, \(name).", "en-IN"))
        }
        var english = "Next station, \(name)."
        if let change = changes.first { english += " Change here for the \(change.name)." }
        if isLast { english += " This train terminates at \(name)." }
        lines.append((english, "en-IN"))
        lines.append(("अगला स्टेशन, \(name).", "hi-IN"))
        return lines
    }

    private static let kannadaVoice: AVSpeechSynthesisVoice? =
        AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("kn") }

    // MARK: Engine

    private static func makeBuffers() -> Buffers {
        Buffers(music: buffer(Synth.music(), format: mono),
                rumble: buffer(Synth.rumble(), format: stereo),
                whine: buffer(Synth.whine(), format: stereo),
                chime: buffer(Synth.chime(), format: stereo),
                beeps: buffer(Synth.doorBeeps(), format: stereo))
    }

    private static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        b.frameLength = b.frameCapacity
        samples.withUnsafeBufferPointer { src in
            for c in 0..<Int(format.channelCount) {
                b.floatChannelData![c].update(from: src.baseAddress!, count: samples.count)
            }
        }
        return b
    }

    private func wire() {
        [music, rumble, whine, effects, rumblePitch, whinePitch, trainMixer, distanceFilter, reverb].forEach(engine.attach)
        let stereo = Self.stereo
        engine.connect(music, to: engine.mainMixerNode, format: Self.mono)
        engine.connect(rumble, to: rumblePitch, format: stereo)
        engine.connect(rumblePitch, to: trainMixer, format: stereo)
        engine.connect(whine, to: whinePitch, format: stereo)
        engine.connect(whinePitch, to: trainMixer, format: stereo)
        engine.connect(effects, to: trainMixer, format: stereo)
        engine.connect(trainMixer, to: distanceFilter, format: stereo)
        engine.connect(distanceFilter, to: reverb, format: stereo)
        engine.connect(reverb, to: engine.mainMixerNode, format: stereo)
        rumble.volume = 0
        whine.volume = 0
    }

    private var playsMusic: Bool {
        allowed(.music) && !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
    }

    /// Ambient (mixes with the rider's own audio, obeys the silent switch)
    /// unless our own music is on and nothing else is playing.
    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        if playsMusic {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } else {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        }
        try? session.setActive(true)
    }

    private func restartLoops() {
        guard let buffers, engine.isRunning else { return }
        if playsMusic {
            if !music.isPlaying {
                music.volume = musicLevel
                music.scheduleBuffer(buffers.music, at: nil, options: .loops)
                music.play()
            }
        } else {
            music.stop()
        }
        let train = context == .ride && allowed(.trainSounds)
        for (node, buffer) in [(rumble, buffers.rumble), (whine, buffers.whine)] {
            if train, !node.isPlaying {
                node.scheduleBuffer(buffer, at: nil, options: .loops)
                node.play()
            } else if !train {
                node.stop()
            }
        }
        if train, !effects.isPlaying { effects.play() }
    }

    private func allowed(_ setting: Setting) -> Bool {
        switch context {
        case .ride: return setting.isOn
        case .trip: return Setting.duringTrips.isOn && setting != .trainSounds && setting.isOn
        case nil: return false
        }
    }

    private func play(_ sound: KeyPath<Buffers, AVAudioPCMBuffer>, when setting: Setting) {
        queue.async { [self] in
            guard allowed(setting), let buffers, engine.isRunning, effects.isPlaying else { return }
            effects.scheduleBuffer(buffers[keyPath: sound], at: nil, options: .interrupts)
        }
    }

    private func startTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(33))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// Applies the latest motion to the train sounds.
    private func tick() {
        let m = motion.withLock { $0 }
        let dt = 0.033
        let accel = (m.speed - lastSpeed) / dt
        lastSpeed = m.speed
        smoothedAccel += 0.15 * (accel - smoothedAccel)

        let v = min(m.speed / 20, 1.2)
        let moving = m.speed > 0.2
        // Distance: full level within 30 m, about -18 dB at 500 m; under 2 m is the cab.
        let d = max(m.cameraDistance, 0.5)
        let distanceGain = Float(d <= 30 ? 1 : pow(30 / d, 0.75))
        let cab: Float = d < 2 ? 1.3 : 1

        rumblePitch.rate = Float(0.7 + 0.6 * v)
        rumble.volume = moving ? Float(0.12 + 0.5 * v) * distanceGain * cab * (m.underground ? 1.5 : 1) : 0
        whinePitch.rate = Float(0.55 + 2.1 * min(v, 1))
        let effort = min(abs(smoothedAccel) / 0.9, 1)
        whine.volume = moving ? Float(0.04 + 0.32 * effort) * distanceGain * cab : 0
        // Far away, only the low rumble carries.
        distanceFilter.bands[0].frequency = Float(d <= 30 ? 9000 : max(350, 9000 * pow(30 / d, 1.2)))
        reverb.wetDryMix = d < 2 ? 4 : (m.underground ? 42 : 10)
    }

    // MARK: Ducking

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        queue.async { [self] in
            guard !ducked else { return }
            ducked = true
            music.volume = musicLevel * 0.3
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let done = !synthesizer.isSpeaking
        queue.async { [self] in
            guard done else { return }
            ducked = false
            music.volume = musicLevel
        }
    }
}
