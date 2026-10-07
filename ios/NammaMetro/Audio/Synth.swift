import Foundation

/// Offline synthesis of every sound the app plays. No recordings ship with the
/// app (none of Namma Metro's are licensed for reuse), so everything is
/// generated once at start-up and then looped or triggered.
enum Synth {
    static let sampleRate = 44_100.0

    /// Deterministic noise and choices, so the music loop is the same every launch.
    struct RNG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
        mutating func pick<T>(_ items: [T]) -> T { items[Int(next() % UInt64(items.count))] }
    }

    // MARK: Music

    /// A calm, seamless loop: a tanpura drone on D (Pa, Sa, Sa, low Sa) with
    /// sparse bell notes from raga Mohanam (D E F# A B). Every note wraps around
    /// the loop end, so it repeats without a seam.
    static func music(seconds: Double = 40) -> [Float] {
        let n = Int(seconds * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var rng = RNG(state: 0xB4_51_0C)

        // Tanpura: one string every 1.25 s.
        let strings: [(Double, Float)] = [(220.0, 0.32), (293.66, 0.26), (293.66, 0.26), (146.83, 0.4)]
        let cycle = 5.0
        for c in 0..<Int(seconds / cycle) {
            for (i, string) in strings.enumerated() {
                let start = Int((Double(c) * cycle + Double(i) * 1.25) * sampleRate)
                pluck(into: &out, at: start, freq: string.0, seconds: 6, gain: string.1, rng: &rng)
            }
        }

        // Bells: a slow random walk over the scale, about one note every 3–4 s.
        let scale: [Double] = [587.33, 659.26, 739.99, 880.0, 987.77, 1174.66]
        var degree = 2
        var t = 1.5
        while t < seconds - 0.5 {
            degree = max(0, min(scale.count - 1, degree + rng.pick([-2, -1, -1, 1, 1, 2])))
            bell(into: &out, at: Int(t * sampleRate), freq: scale[degree], gain: 0.12 + 0.06 * rng.unit(), decay: 2.8)
            // Now and then a second note answers the first.
            if rng.unit() < 0.3 {
                let answer = scale[max(0, degree - rng.pick([1, 2]))]
                bell(into: &out, at: Int((t + 0.6) * sampleRate), freq: answer, gain: 0.08, decay: 2.4)
            }
            t += 2.6 + 2.2 * Double(rng.unit())
        }
        normalize(&out, peak: 0.55)
        return out
    }

    /// Karplus–Strong string with a touch of buzz, like a tanpura's jawari bridge.
    static func pluck(into out: inout [Float], at start: Int, freq: Double, seconds: Double, gain: Float, rng: inout RNG) {
        let length = max(2, Int(sampleRate / freq))
        var line = (0..<length).map { _ in rng.unit() * 2 - 1 }
        let decay = Float(pow(0.01, 1 / (seconds * freq)))
        let count = Int(seconds * sampleRate)
        var i = 0
        for k in 0..<count {
            let a = line[i], b = line[(i + 1) % length]
            line[i] = decay * 0.5 * (a + b)
            i = (i + 1) % length
            let attack = min(Float(k) / 300, 1)
            out[(start + k) % out.count] += gain * attack * (a + 0.3 * tanh(4 * a))
        }
    }

    /// A soft bell: a few slightly inharmonic partials with exponential decay.
    static func bell(into out: inout [Float], at start: Int, freq: Double, gain: Float, decay: Double) {
        let partials: [(ratio: Double, amp: Double, decay: Double)] = [(1, 1, 1), (2.0, 0.28, 0.6), (2.99, 0.12, 0.45), (4.18, 0.05, 0.3)]
        let count = Int(decay * 2.5 * sampleRate)
        for k in 0..<count {
            let t = Double(k) / sampleRate
            var v = 0.0
            for p in partials {
                v += p.amp * sin(2 * .pi * freq * p.ratio * t) * exp(-t / (decay * p.decay))
            }
            let attack = min(t / 0.006, 1)
            out[(start + k) % out.count] += gain * Float(v * attack)
        }
    }

    // MARK: Train

    /// Wheel-on-rail and air rumble: brown noise, low-passed, crossfaded into a seamless loop.
    static func rumble(seconds: Double = 4) -> [Float] {
        let n = Int(seconds * sampleRate), fade = Int(0.25 * sampleRate)
        var rng = RNG(state: 0x7A11)
        var raw = [Float](repeating: 0, count: n + fade)
        var brown: Float = 0, low: Float = 0
        for i in raw.indices {
            brown = 0.985 * brown + 0.06 * (rng.unit() * 2 - 1)
            low += 0.08 * (brown - low)
            raw[i] = low
        }
        var out = Array(raw[0..<n])
        for i in 0..<fade {
            let w = Float(i) / Float(fade)
            out[i] = out[i] * w + raw[n + i] * (1 - w)
        }
        normalize(&out, peak: 0.8)
        return out
    }

    /// Traction-motor (VVVF inverter) whine: a buzzy harmonic tone with an exact
    /// whole number of cycles, so it loops cleanly and can be pitch-shifted with speed.
    static func whine(base: Double = 300, seconds: Double = 1) -> [Float] {
        let n = Int(seconds * sampleRate)
        let harmonics: [(Double, Double)] = [(1, 1), (2, 0.45), (3, 0.3), (5, 0.12), (7, 0.06)]
        var out = (0..<n).map { k -> Float in
            let t = Double(k) / sampleRate
            return Float(harmonics.reduce(0) { $0 + $1.1 * sin(2 * .pi * base * $1.0 * t) })
        }
        normalize(&out, peak: 0.5)
        return out
    }

    /// Two-tone arrival chime.
    static func chime() -> [Float] {
        var out = [Float](repeating: 0, count: Int(2.4 * sampleRate))
        bell(into: &out, at: 0, freq: 1318.51, gain: 0.5, decay: 0.7)
        bell(into: &out, at: Int(0.42 * sampleRate), freq: 1046.5, gain: 0.5, decay: 0.8)
        normalize(&out, peak: 0.6)
        return out
    }

    /// Door-closing warning: six short beeps.
    static func doorBeeps() -> [Float] {
        let on = 0.13, off = 0.17
        var out = [Float](repeating: 0, count: Int(6 * (on + off) * sampleRate))
        for b in 0..<6 {
            let start = Int(Double(b) * (on + off) * sampleRate)
            let count = Int(on * sampleRate)
            for k in 0..<count {
                let t = Double(k) / sampleRate
                let ramp = min(t / 0.005, (on - t) / 0.005, 1)
                out[start + k] = Float(0.35 * ramp * sin(2 * .pi * 2350 * t))
            }
        }
        return out
    }

    static func normalize(_ samples: inout [Float], peak: Float) {
        let m = samples.reduce(0) { max($0, abs($1)) }
        guard m > 0 else { return }
        let g = peak / m
        for i in samples.indices { samples[i] *= g }
    }
}
