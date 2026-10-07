#!/usr/bin/env python3
"""Builds NammaMetro/Resources/buildings.bin: OpenStreetMap building footprints
within ~180 m of each metro line, for the 3D ride view.

Data © OpenStreetMap contributors, ODbL 1.0.

Each building is assigned to the nearest track chunk (50 samples of
metro_track.json, matching LineScenery.chunkSamples) so the app streams it in
with the viaduct. Buildings on top of the track or a station are dropped.
Heights come from building:levels / height when mapped, otherwise from a
deterministic estimate by type and footprint size.

Binary layout (little endian):
  "NMB1", u32 count, then per building:
  u8 line index, u16 chunk, u16 height (dm), u8 palette, u8 vertex count,
  vertex count × (i32 lat·1e6, i32 lon·1e6)

Usage: python3 tools/build_buildings.py   (run from ios/; OSM_CACHE=dir reuses bld_<rel>.json)
"""
import json, math, os, struct, sys, time, urllib.parse, urllib.request, zlib

HERE = os.path.dirname(__file__)
TRACK = os.path.join(HERE, "..", "NammaMetro", "Resources", "metro_track.json")
OUT = os.path.join(HERE, "..", "NammaMetro", "Resources", "buildings.bin")
CACHE = os.environ.get("OSM_CACHE")
RELATIONS = {"purple": 1798771, "green": 7842287, "yellow": 19421944}
CORRIDOR = 180
CHUNK = 50
CLEAR_TRACK = 13.0      # no building closer than this to the alignment
CLEAR_STATION = 95.0    # ... or within this of a station centre along a 30 m band
FLOOR = 3.2
SKIP_TYPES = {"roof", "train_station", "transportation", "bridge", "construction", "ruins", "no"}

LAT0 = 12.97
KY = 110_574.0
KX = 111_320.0 * math.cos(math.radians(LAT0))


def xy(lat, lon):
    return ((lon - 77.59) * KX, (lat - LAT0) * KY)


def fetch(rel):
    path = os.path.join(CACHE, f"bld_{rel}.json") if CACHE else None
    if path and os.path.exists(path):
        return json.load(open(path))
    q = (f"[out:json][timeout:580];relation({rel});way(r)->.t;node(w.t)->.n;"
         f'way["building"](around.n:{CORRIDOR});out tags geom;')
    for url in ("https://overpass.kumi.systems/api/interpreter", "https://overpass-api.de/api/interpreter"):
        try:
            req = urllib.request.Request(url, data=urllib.parse.urlencode({"data": q}).encode(),
                                         headers={"User-Agent": "NammaMetro-build-buildings/1.0",
                                                  "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=620) as r:
                data = json.load(r)
            time.sleep(2)
            return data
        except Exception as e:  # busy server: try the next one
            print(f"  {url}: {e}", file=sys.stderr)
    sys.exit(f"could not fetch buildings for relation {rel}")


def area(poly):
    a = 0.0
    for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1]):
        a += x1 * y2 - x2 * y1
    return abs(a) / 2


def inside(p, poly):
    x, y = p
    c = False
    for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1]):
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def seg_dist(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy
    t = 0 if L == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def height(tags, a, oid):
    h = zlib.crc32(str(oid).encode()) / 0xFFFFFFFF   # stable per building
    try:
        if "height" in tags:
            return float(tags["height"].split()[0])
        if "building:levels" in tags:
            return float(tags["building:levels"]) * FLOOR + 0.6
    except ValueError:
        pass
    kind = tags.get("building", "yes")
    def floors(lo, hi):
        return (lo + int(h * (hi - lo + 1))) * FLOOR + 0.6
    if kind in ("industrial", "warehouse", "shed", "garage", "garages", "hangar", "service"):
        return 5 + h * 5
    if kind in ("house", "detached", "residential", "semidetached_house", "terrace"):
        return floors(2, 3)
    if kind == "apartments":
        return floors(5, 12)
    if kind in ("commercial", "office", "retail", "hotel", "hospital", "college", "university", "school"):
        return floors(3, 8)
    if a < 80:
        return floors(1, 2)
    if a < 250:
        return floors(2, 4)
    if a < 800:
        return floors(3, 5)
    if a < 3000:
        return floors(3, 7)
    return floors(1, 3)


def main():
    track = json.load(open(TRACK))
    lines = []
    for idx, line in enumerate(track["lines"]):
        pts = [xy(a, b) for a, b in zip(line["lat"], line["lon"])]
        stations = [pts[s["trackIndex"]] for s in line["stations"]]
        lines.append((idx, line["id"], pts, stations))

    # Coarse grid of track samples for nearest-sample lookups.
    cell = 200.0
    grid = {}
    for idx, _, pts, _ in lines:
        for i, p in enumerate(pts):
            grid.setdefault((int(p[0] // cell), int(p[1] // cell)), []).append((idx, i))

    def nearby(p):
        cx, cy = int(p[0] // cell), int(p[1] // cell)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                yield from grid.get((cx + dx, cy + dy), [])

    seen, out = set(), []
    dropped = 0
    for line_id, rel in RELATIONS.items():
        if os.environ.get("SKIP_MISSING") and CACHE and not os.path.exists(os.path.join(CACHE, f"bld_{rel}.json")):
            print(f"  skipping {line_id}: not in OSM_CACHE", file=sys.stderr)
            continue
        data = fetch(rel)
        for e in data["elements"]:
            if e["type"] != "way" or e["id"] in seen or len(e.get("geometry", [])) < 4:
                continue
            seen.add(e["id"])
            tags = e.get("tags", {})
            if tags.get("building") in SKIP_TYPES or tags.get("layer", "0").startswith("-"):
                continue
            ring = [(g["lat"], g["lon"]) for g in e["geometry"]]
            if ring[0] == ring[-1]:
                ring = ring[:-1]
            if len(ring) < 3 or len(ring) > 60:
                continue
            poly = [xy(*p) for p in ring]
            a = area(poly)
            if a < 12:
                continue
            cx = sum(p[0] for p in poly) / len(poly)
            cy = sum(p[1] for p in poly) / len(poly)

            best, clash = None, False
            for idx, i in nearby((cx, cy)):
                pts = lines[idx][2]
                p = pts[i]
                d = math.hypot(p[0] - cx, p[1] - cy)
                if best is None or d < best[0]:
                    best = (d, idx, i)
                # Footprint over the track: a nearby sample inside it, or an edge too close.
                if d < 400:
                    if inside(p, poly) or min(seg_dist(p, poly[k], poly[(k + 1) % len(poly)])
                                              for k in range(len(poly))) < CLEAR_TRACK:
                        clash = True
                        break
            if clash or best is None or best[0] > CORRIDOR + 20:
                dropped += 1
                continue
            idx = best[1]
            if any(math.hypot(s[0] - cx, s[1] - cy) < CLEAR_STATION and best[0] < 30 for s in lines[idx][3]):
                dropped += 1
                continue
            h = max(3.0, min(height(tags, a, e["id"]), 160.0))
            palette = zlib.crc32(b"p" + str(e["id"]).encode()) % 6
            out.append((idx, best[2] // CHUNK, int(h * 10), palette, ring))

    with open(OUT, "wb") as f:
        f.write(b"NMB1")
        f.write(struct.pack("<I", len(out)))
        for idx, chunk, h, pal, ring in out:
            f.write(struct.pack("<BHHBB", idx, chunk, h, pal, len(ring)))
            for lat, lon in ring:
                f.write(struct.pack("<ii", round(lat * 1e6), round(lon * 1e6)))
    print(f"{len(out)} buildings ({dropped} dropped over track/stations), "
          f"wrote {os.path.relpath(OUT)} ({os.path.getsize(OUT) // 1024} KB)", file=sys.stderr)


if __name__ == "__main__":
    main()
