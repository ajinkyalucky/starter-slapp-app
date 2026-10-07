# Namma Metro (iOS)

SwiftUI app (iOS 17+) showing Bengaluru Namma Metro trains on a map plus per-station arrivals.

## Status

Plan a journey (with changes at Majestic and RV Road), see fares, and track it live with
"next stop" alerts. BMRCL has no public realtime feed, so `ScheduleFeed` runs BMRCL's published
timetable: every trip, including peak short loops and the Monday, Saturday (2nd/4th and holidays)
and Sunday tables (`Resources/timetable.json`, built by `tools/build_timetable.py` from
[Vonter/bmrcl-gtfs](https://github.com/Vonter/bmrcl-gtfs), ODbL). Terminal departures are BMRCL's.
Times at other stations are modelled and usually within 2 min. Riders can sync to the real trains
from the platform ("Train's here", or the countdown on the platform display), and GPS stops at
above-ground stations sync automatically during a trip. `CalibratedFeed` shifts that line and
direction for 90 minutes.

Everything depends on the `TrainFeed` protocol (`Models.swift`), so a realtime source (GTFS-RT,
a partner API, crowdsourced reports) can replace it with one line in `NammaMetroApp.swift`.

Not yet covered: the Pink line (opening expected late Oct 2026), one-off late-night service
extensions, and service disruptions.

## Build

Requires macOS with Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

    brew install xcodegen
    cd ios && xcodegen generate && open NammaMetro.xcodeproj

Set your team and bundle ID (`project.yml`) to run on a device. This code was written
without access to Xcode, so the `ios` GitHub workflow is the first real compile/test.
