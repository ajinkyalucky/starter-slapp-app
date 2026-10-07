import SwiftUI

/// Speaker button with the sound toggles. `trip` shows the switch for sound
/// while tracking a real journey instead of the ride-only train sounds.
struct SoundMenu: View {
    var trip = false
    @AppStorage(MetroAudio.Setting.music.rawValue) private var music = true
    @AppStorage(MetroAudio.Setting.trainSounds.rawValue) private var trainSounds = true
    @AppStorage(MetroAudio.Setting.announcements.rawValue) private var announcements = true
    @AppStorage(MetroAudio.Setting.duringTrips.rawValue) private var duringTrips = false

    var body: some View {
        Menu {
            if trip {
                Toggle("Sound during trips", isOn: $duringTrips)
            }
            Toggle("Music", isOn: $music)
            if !trip {
                Toggle("Train sounds", isOn: $trainSounds)
            }
            Toggle("Station announcements", isOn: $announcements)
        } label: {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel("Sound")
        }
        .onChange(of: [music, trainSounds, announcements, duringTrips]) {
            MetroAudio.shared.settingsChanged()
        }
    }

    private var muted: Bool {
        if trip { return !duringTrips || (!music && !announcements) }
        return !music && !trainSounds && !announcements
    }
}
