#!/usr/bin/env python3
"""Builds NammaMetro/Resources/metro_track.json from OpenStreetMap.

Data © OpenStreetMap contributors, ODbL 1.0 (https://www.openstreetmap.org/copyright).

For each line it fetches the OSM route relation, chains its track ways into one
alignment, smooths and resamples it every SPACING metres, derives a height
profile (viaduct / ramp / tunnel) from the ways' bridge/tunnel tags, and pins
every stop to the nearest track sample. Station order must match the seed
order in StationData.swift; the script checks the counts.

Usage: python3 tools/build_track.py            (run from ios/)
"""
import json, math, os, sys, time, urllib.parse, urllib.request

LINES = [  # app line id, OSM relation id in the app's forward direction
    ("purple", 1798771),   # Whitefield (Kadugodi) -> Challaghatta
    ("green", 7842287),    # Madavara -> Silk Institute
    ("yellow", 19421944),  # RV Road -> Bommasandra
]
SPACING = 8.0            # metres between output samples
PAD = 200.0              # overrun track added past each terminus
DECK_ELEVATED = 13.0     # deck top above ground on viaducts
DECK_UNDERGROUND = -16.0
RAMP_HALF_WINDOW = 240.0  # box-filter half width (applied twice) for ramps
STATION_FLAT = 80.0      # keep the deck level this far either side of a station
STATION_BLEND = 60.0
OUT = os.path.join(os.path.dirname(__file__), "..", "NammaMetro", "Resources", "metro_track.json")
CACHE = os.environ.get("OSM_CACHE")  # optional directory holding rel_<id>.json

LAT0 = 12.97
KY = 110_574.0
KX = 111_320.0 * math.cos(math.radians(LAT0))


def fetch(rel):
    if CACHE and os.path.exists(os.path.join(CACHE, f"rel_{rel}.json")):
        return json.load(open(os.path.join(CACHE, f"rel_{rel}.json")))
    q = f"[out:json][timeout:100];relation({rel});out body;>;out geom tags;"
    req = urllib.request.Request(
        "https://overpass-api.de/api/interpreter",
        data=urllib.parse.urlencode({"data": q}).encode(),
        headers={"User-Agent": "NammaMetro-build-track/1.0", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=150) as r:
        data = json.load(r)
    time.sleep(2)
    return data


def xy(lat, lon):
    return ((lon - 77.59) * KX, (lat - LAT0) * KY)


def latlon(x, y):
    return (y / KY + LAT0, x / KX + 77.59)


def level(tags):
    layer = tags.get("layer", "0")
    if tags.get("tunnel") == "yes" or layer.startswith("-"):
        return "U"
    if tags.get("bridge") in ("yes", "viaduct") or (layer.isdigit() and int(layer) > 0):
        return "E"
    return "G"


def chain(data, rel):
    els = {(e["type"], e["id"]): e for e in data["elements"]}
    r = els[("relation", rel)]
    ways = [els[("way", m["ref"])] for m in r["members"]
            if m["type"] == "way" and m["role"] in ("", "route", "stop") and ("way", m["ref"]) in els]
    stops = [els[("node", m["ref"])] for m in r["members"]
             if m["type"] == "node" and m["role"].startswith("stop")]
    pts = []
    for i, w in enumerate(ways):
        g = [xy(p["lat"], p["lon"]) for p in w["geometry"]]
        k = level(w.get("tags", {}))
        if pts:
            end = pts[-1][:2]
            if math.dist(end, g[-1]) < math.dist(end, g[0]):
                g.reverse()
            gap = math.dist(end, g[0])
            if gap > 30:
                sys.exit(f"relation {rel}: {gap:.0f} m gap before way {w['id']}")
        elif len(ways) > 1:
            n = [xy(p["lat"], p["lon"]) for p in ways[1]["geometry"]]
            if min(math.dist(g[0], n[0]), math.dist(g[0], n[-1])) < min(math.dist(g[-1], n[0]), math.dist(g[-1], n[-1])):
                g.reverse()
        for j, p in enumerate(g):
            if pts and j == 0 and math.dist(pts[-1][:2], p) < 0.5:
                continue
            pts.append((p[0], p[1], k))
    return pts, stops


def resample(pts, step):
    out = [pts[0]]
    carry = 0.0
    for a, b in zip(pts, pts[1:]):
        seg = math.dist(a[:2], b[:2])
        d = step - carry
        while d <= seg:
            t = d / seg
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, b[2] if t > 0.5 else a[2]))
            d += step
        carry = seg - (d - step)
    if math.dist(out[-1][:2], pts[-1][:2]) > step * 0.25:
        out.append(pts[-1])
    return out


def pad(track, length):
    """Extends both ends straight along the end tangent, so a train standing at a
    terminus (and the viaduct under it) never runs off the surveyed track."""
    n = int(length / SPACING)
    def ext(a, b):  # points continuing from b away from a
        d = math.dist(a[:2], b[:2])
        ux, uy = (b[0] - a[0]) / d, (b[1] - a[1]) / d
        return [(b[0] + ux * SPACING * k, b[1] + uy * SPACING * k, b[2]) for k in range(1, n + 1)]
    head = ext(track[3], track[0])[::-1]
    tail = ext(track[-4], track[-1])
    return head + track + tail


def gaussian(values, sigma):
    r = int(sigma * 3)
    w = [math.exp(-0.5 * (i / sigma) ** 2) for i in range(-r, r + 1)]
    n = len(values)
    out = []
    for i in range(n):
        acc = tot = 0.0
        for k, wk in zip(range(i - r, i + r + 1), w):
            j = min(max(k, 0), n - 1)
            acc += values[j] * wk
            tot += wk
        out.append(acc / tot)
    return out


def box(values, half):
    n = len(values)
    pre = [0.0]
    for v in values:
        pre.append(pre[-1] + v)
    out = []
    for i in range(n):
        a, b = max(0, i - half), min(n, i + half + 1)
        out.append((pre[b] - pre[a]) / (b - a))
    return out


def heights(levels):
    # Untagged ("G") stretches next to a tunnel are portal ramps; elsewhere they are viaduct.
    runs, start = [], 0
    for i in range(1, len(levels) + 1):
        if i == len(levels) or levels[i] != levels[start]:
            runs.append((start, i, levels[start]))
            start = i
    target = [0.0] * len(levels)
    for idx, (a, b, k) in enumerate(runs):
        near_tunnel = any(runs[j][2] == "U" for j in (idx - 1, idx + 1) if 0 <= j < len(runs))
        h = {"E": DECK_ELEVATED, "U": DECK_UNDERGROUND}.get(k, 0.0 if near_tunnel else DECK_ELEVATED)
        for i in range(a, b):
            target[i] = h
    half = int(RAMP_HALF_WINDOW / SPACING)
    return box(box(target, half), half)


def main():
    out = {"attribution": "© OpenStreetMap contributors (ODbL)", "spacing": SPACING, "lines": []}
    for line_id, rel in LINES:
        raw, stops = chain(fetch(rel), rel)
        fine = resample(raw, 2.0)
        sx = gaussian([p[0] for p in fine], 4.0)   # ~8 m sigma at 2 m spacing
        sy = gaussian([p[1] for p in fine], 4.0)
        track = resample([(x, y, p[2]) for x, y, p in zip(sx, sy, fine)], SPACING)
        track = pad(track, PAD)
        h = heights([p[2] for p in track])

        # Pin stops in order, never moving backwards along the track.
        idxs, lo = [], 0
        for s in stops:
            p = xy(s["lat"], s["lon"])
            best = min(range(lo, len(track)), key=lambda i: math.dist(track[i][:2], p))
            if math.dist(track[best][:2], p) > 120:
                sys.exit(f"{line_id}: stop {s['tags'].get('name')} is {math.dist(track[best][:2], p):.0f} m off the track")
            idxs.append(best)
            lo = best + 1

        # Level the deck through each station.
        flat = int(STATION_FLAT / SPACING)
        blend = int(STATION_BLEND / SPACING)
        for i in idxs:
            level_h = h[i]
            for j in range(max(0, i - flat - blend), min(len(h), i + flat + blend + 1)):
                d = abs(j - i)
                t = 1.0 if d <= flat else 1.0 - (d - flat) / blend
                t = t * t * (3 - 2 * t)
                h[j] = h[j] * (1 - t) + level_h * t

        lat, lon = zip(*(latlon(p[0], p[1]) for p in track))
        out["lines"].append({
            "id": line_id,
            "osmRelation": rel,
            "lat": [round(v, 6) for v in lat],
            "lon": [round(v, 6) for v in lon],
            "deck": [round(v, 2) for v in h],
            "stations": [{"osmName": s["tags"].get("name", ""), "lat": s["lat"], "lon": s["lon"], "trackIndex": i}
                         for s, i in zip(stops, idxs)],
        })
        km = (len(track) - 1) * SPACING / 1000
        print(f"{line_id}: {len(stops)} stops, {len(track)} samples, {km:.1f} km", file=sys.stderr)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print(f"wrote {os.path.relpath(OUT)} ({os.path.getsize(OUT) // 1024} KB)", file=sys.stderr)


if __name__ == "__main__":
    main()
