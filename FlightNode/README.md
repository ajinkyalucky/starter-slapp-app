# FlightNode

Offline iPhone app for flights BLR→CMB (UL 174, Thu 8 Oct 2026) and CMB→BLR (UL 1173, Fri 16 Oct 2026).
Real GPS (works in airplane mode) on a bundled offline map, with "what am I flying over", flight progress and ETA.
It does **not** show other aircraft: that needs internet or an ADS-B receiver.

## Build (on a Mac)
1. `brew install xcodegen && cd FlightNode && xcodegen` → opens `FlightNode.xcodeproj`.
2. Select your iPhone, set your Team under Signing, Run. (Free Apple ID works; the app expires after 7 days.)
3. Allow location "While Using" and keep **Precise Location** on.
4. Test at home: turn on *Simulate flight*, then airplane mode. Then try a real fix outdoors in airplane mode.

## Data
`Sources/Resources/geo.json` is generated (already committed). To rebuild with different bounds:
`node tools/build-data.mjs ne_10m_land.json ne_10m_populated_places_simple.json`
(Natural Earth GeoJSON, public domain.)

## Notes
- Indoors/cabin GPS: window seat, first fix can take a minute (no assisted GPS offline).
- Everything is untested on a device so far (written without Xcode); expect small compile fixes.
