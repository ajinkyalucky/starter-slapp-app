# Namma Metro (iOS)

SwiftUI app (iOS 17+) showing Bengaluru Namma Metro trains on a map plus per-station arrivals.

## Status

BMRCL has not published an official realtime feed. The app therefore uses `ScheduleFeed`,
which **estimates** train positions from a fixed-headway timetable and labels them as
estimated in the UI. Everything depends on the `TrainFeed` protocol (`Models.swift`), so a
realtime source (GTFS-RT, a partner API, crowdsourced reports) can replace it by providing
another implementation and changing one line in `NammaMetroApp.swift`.

Known placeholders to replace before shipping:
- `ServiceProfile` headways, first/last train and 2-minute segment times are assumptions.
- Station coordinates are anchors plus linear interpolation (`StationData.swift`). Use
  `stops.txt` from a GTFS dataset (e.g. the unofficial BMRCL GTFS) for real positions and
  to draw track shapes.
- Station lists/lines (Purple, Green, Yellow) should be checked against current BMRCL data.

## Build

Requires macOS with Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

    brew install xcodegen
    cd ios && xcodegen generate && open NammaMetro.xcodeproj

Set your team and bundle ID (`project.yml`) to run on a device. This code was written
without access to Xcode, so the `ios` GitHub workflow is the first real compile/test.
