#!/usr/bin/env python3
"""Builds NammaMetro/Resources/timetable.json from the BMRCL GTFS feed.

Source: https://github.com/Vonter/bmrcl-gtfs (ODbL 1.0), a transcription of the
timetables BMRCL publishes at https://www.bmrc.co.in/metro-timings/. BMRCL only
publishes terminal departures and headway bands, so station-to-station times in
that feed (and here) are modelled, typically within a couple of minutes.

Usage:
    python3 tools/build_timetable.py              # downloads the feed
    python3 tools/build_timetable.py path/to/gtfs # an unzipped feed directory

Output, all times in seconds:
    calendar: weekday -> service id, plus dated exceptions (2nd/4th Saturdays, holidays)
    patterns: per line and direction, our station IDs in travel order with the
              run time to the next station and the dwell at each station
    trips:    [service, line, direction, from index, to index, departure from the first stop]
    kannadaNames: station ID -> name in Kannada script
"""
import collections
import csv
import io
import json
import re
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

FEED_URL = "https://raw.githubusercontent.com/Vonter/bmrcl-gtfs/main/gtfs/bmrcl.zip"
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "NammaMetro/Resources/timetable.json"
STATION_DATA = ROOT / "NammaMetro/StationData.swift"

LINES = {"PURPLE": "purple", "GREEN": "green", "YELLOW": "yellow"}

# Official last departures from each terminus (BMRCL timetable images, 2026),
# per service. The feed rounds a few of these away; they matter for planning.
OFFICIAL_LAST = {
    ("purple", "forward"): {"*": "22:45"},
    ("purple", "reverse"): {"*": "23:05"},
    ("green", "forward"): {"weekday": "22:57", "monday": "22:57", "holiday": "23:00", "sunday": "23:00"},
    ("green", "reverse"): {"*": "23:05"},
    ("yellow", "forward"): {"*": "23:55"},
    ("yellow", "reverse"): {"*": "22:42"},
}


def station_id(name):
    """Same rule as `stationID` in StationData.swift."""
    return "".join(c if c.isalnum() else "-" for c in name.lower())


def our_station_names():
    """Station name lists per line, read from StationData.swift."""
    source = STATION_DATA.read_text()
    names = {}
    for line in LINES.values():
        block = re.search(rf"private let {line}Names = \[(.*?)\]", source, re.S).group(1)
        names[line] = re.findall(r'"([^"]+)"', block)
    return names


def load_feed(arg):
    if arg:
        return Path(arg)
    tmp = Path(tempfile.mkdtemp(prefix="bmrcl-gtfs-"))
    with urllib.request.urlopen(FEED_URL) as r:
        zipfile.ZipFile(io.BytesIO(r.read())).extractall(tmp)
    return tmp


def seconds(t):
    h, m, s = (int(x) for x in t.split(":"))
    return h * 3600 + m * 60 + s


def main():
    feed = load_feed(sys.argv[1] if len(sys.argv) > 1 else None)

    def read(name):
        with open(feed / f"{name}.txt", encoding="utf-8-sig") as f:
            return list(csv.DictReader(f))

    stops = {s["stop_id"]: s for s in read("stops")}
    station_of = lambda stop_id: stops[stop_id]["parent_station"] or stop_id
    trips = {t["trip_id"]: t for t in read("trips")}
    stop_times = collections.defaultdict(list)
    for row in read("stop_times"):
        stop_times[row["trip_id"]].append(row)
    for rows in stop_times.values():
        rows.sort(key=lambda r: int(r["stop_sequence"]))

    names = our_station_names()
    patterns, code_index = {}, {}
    run = collections.defaultdict(collections.Counter)
    dwell = collections.defaultdict(collections.Counter)

    # Station order per line from its longest trip; it must match ours one to one.
    for route, line in LINES.items():
        longest = max((rows for tid, rows in stop_times.items() if trips[tid]["route_id"] == route), key=len)
        codes = [station_of(r["stop_id"]) for r in longest]
        ours = names[line]
        if len(codes) != len(ours):
            sys.exit(f"{line}: feed has {len(codes)} stations, StationData.swift {len(ours)}")
        # Feed and app may list the line from opposite ends; align on the first name.
        first = stops[codes[0]]["stop_name"].lower()
        if not (ours[0].lower() in first or first in ours[0].lower() or first.split()[0] in ours[0].lower()):
            codes.reverse()
        for i, (code, name) in enumerate(zip(codes, ours)):
            code_index[(line, code)] = i
            print(f"  {line:6} {code:5} {stops[code]['stop_name'][:40]:40} -> {name}", file=sys.stderr)
        patterns[line] = {"stations": [station_id(n) for n in ours]}

    out_trips = []
    for tid, rows in stop_times.items():
        t = trips[tid]
        line = LINES[t["route_id"]]
        idx = [code_index[(line, station_of(r["stop_id"]))] for r in rows]
        direction = "forward" if idx[-1] > idx[0] else "reverse"
        for a, b in zip(rows, rows[1:]):
            run[(line, direction, code_index[(line, station_of(a["stop_id"]))])][
                seconds(b["arrival_time"]) - seconds(a["departure_time"])] += 1
        for r in rows[1:-1]:
            dwell[(line, direction, code_index[(line, station_of(r["stop_id"]))])][
                seconds(r["departure_time"]) - seconds(r["arrival_time"])] += 1
        out_trips.append([t["service_id"], line, direction, idx[0], idx[-1], seconds(rows[0]["departure_time"])])

    for line, p in patterns.items():
        n = len(p["stations"])
        for direction in ("forward", "reverse"):
            order = range(n) if direction == "forward" else range(n - 1, -1, -1)
            # run[k] / dwell[k] are indexed by station index in line order, for this direction.
            p[direction] = {
                "run": [run[(line, direction, i)].most_common(1)[0][0] if run[(line, direction, i)] else 0 for i in range(n)],
                "dwell": [dwell[(line, direction, i)].most_common(1)[0][0] if dwell[(line, direction, i)] else 0 for i in range(n)],
            }
            missing = [i for i in list(order)[:-1] if not run[(line, direction, i)]]
            if missing:
                sys.exit(f"{line} {direction}: no run time from stations {missing}")

    # Patch official last trains from the termini.
    services = sorted({t[0] for t in out_trips})
    for (line, direction), by_service in OFFICIAL_LAST.items():
        n = len(patterns[line]["stations"])
        start, end = (0, n - 1) if direction == "forward" else (n - 1, 0)
        for service in services:
            official = seconds((by_service.get(service) or by_service["*"]) + ":00")
            full = [t for t in out_trips if t[:5] == [service, line, direction, start, end]]
            last = max(full, key=lambda t: t[5])
            if last[5] == official:
                continue
            if abs(official - last[5]) <= 5 * 60:
                print(f"  last {line} {direction} {service}: {last[5] // 60 // 60:02}:{last[5] // 60 % 60:02} -> official", file=sys.stderr)
                last[5] = official
            elif official > last[5]:
                print(f"  last {line} {direction} {service}: added official last train", file=sys.stderr)
                out_trips.append([service, line, direction, start, end, official])

    calendar = {"weekdays": {}, "exceptions": {}}
    for row in read("calendar"):
        for i, day in enumerate(["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]):
            if row[day] == "1":
                # ISO weekday numbers: Monday = 1.
                calendar["weekdays"][str(i + 1)] = row["service_id"]
    for row in read("calendar_dates"):
        if row["exception_type"] == "1":
            calendar["exceptions"][row["date"]] = row["service_id"]
    info = read("feed_info")[0]

    # Kannada station names, for the trilingual announcements.
    kannada = {}
    for row in read("translations"):
        if row["table_name"] == "stops" and row["field_name"] == "stop_name" and row["language"] == "kn":
            for (line, code), i in code_index.items():
                if code == row["record_id"]:
                    kannada[patterns[line]["stations"][i]] = row["translation"]

    out_trips.sort(key=lambda t: (t[0], t[1], t[2], t[5]))
    result = {
        "attribution": "Timetable: BMRCL, via github.com/Vonter/bmrcl-gtfs (ODbL 1.0)",
        "validUntil": info.get("feed_end_date", ""),
        "calendar": calendar,
        "kannadaNames": kannada,
        "patterns": patterns,
        "trips": out_trips,
    }
    OUT.write_text(json.dumps(result, separators=(",", ":")))
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB, {len(out_trips)} trips)", file=sys.stderr)


if __name__ == "__main__":
    main()
