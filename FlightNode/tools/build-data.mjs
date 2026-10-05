// Builds Sources/Resources/geo.json (offline land outline + places) from Natural Earth.
// Usage: node build-data.mjs <ne_10m_land.json> <ne_10m_populated_places_simple.json>
import fs from "node:fs";

const [landPath, placesPath] = process.argv.slice(2);
const BBOX = { minLat: 4.5, maxLat: 15.5, minLon: 73.5, maxLon: 83.5 };
const r = (n) => Math.round(n * 1000) / 1000;

// --- Sutherland–Hodgman clip of a ring to BBOX
function clip(ring) {
  const edges = [
    [(p) => p[0] >= BBOX.minLon, (a, b) => [BBOX.minLon, a[1] + ((b[1] - a[1]) * (BBOX.minLon - a[0])) / (b[0] - a[0])]],
    [(p) => p[0] <= BBOX.maxLon, (a, b) => [BBOX.maxLon, a[1] + ((b[1] - a[1]) * (BBOX.maxLon - a[0])) / (b[0] - a[0])]],
    [(p) => p[1] >= BBOX.minLat, (a, b) => [a[0] + ((b[0] - a[0]) * (BBOX.minLat - a[1])) / (b[1] - a[1]), BBOX.minLat]],
    [(p) => p[1] <= BBOX.maxLat, (a, b) => [a[0] + ((b[0] - a[0]) * (BBOX.maxLat - a[1])) / (b[1] - a[1]), BBOX.maxLat]],
  ];
  let out = ring;
  for (const [inside, cross] of edges) {
    const input = out;
    out = [];
    for (let i = 0; i < input.length; i++) {
      const cur = input[i], prev = input[(i + input.length - 1) % input.length];
      if (inside(cur)) {
        if (!inside(prev)) out.push(cross(prev, cur));
        out.push(cur);
      } else if (inside(prev)) out.push(cross(prev, cur));
    }
    if (!out.length) return [];
  }
  return out;
}

// --- Douglas–Peucker
function simplify(pts, tol) {
  if (pts.length < 3) return pts;
  const keep = new Uint8Array(pts.length);
  keep[0] = keep[pts.length - 1] = 1;
  const stack = [[0, pts.length - 1]];
  while (stack.length) {
    const [s, e] = stack.pop();
    let max = 0, idx = -1;
    const [x1, y1] = pts[s], [x2, y2] = pts[e];
    const dx = x2 - x1, dy = y2 - y1, len = Math.hypot(dx, dy) || 1e-12;
    for (let i = s + 1; i < e; i++) {
      const d = Math.abs(dy * pts[i][0] - dx * pts[i][1] + x2 * y1 - y2 * x1) / len;
      if (d > max) { max = d; idx = i; }
    }
    if (max > tol && idx > 0) { keep[idx] = 1; stack.push([s, idx], [idx, e]); }
  }
  return pts.filter((_, i) => keep[i]);
}

// Closed rings degenerate in Douglas–Peucker (start == end), so simplify two open halves.
function simplifyRing(ring, tol) {
  if (ring.length < 6) return ring;
  const mid = Math.floor(ring.length / 2);
  const a = simplify(ring.slice(0, mid + 1), tol);
  const b = simplify([...ring.slice(mid), ring[0]], tol);
  return [...a.slice(0, -1), ...b.slice(0, -1)];
}

const land = JSON.parse(fs.readFileSync(landPath, "utf8"));
const rings = [];
for (const f of land.features) {
  const polys = f.geometry.type === "Polygon" ? [f.geometry.coordinates] : f.geometry.coordinates;
  for (const poly of polys) {
    const outer = poly[0]; // holes are irrelevant for this region (no lakes at this scale)
    const xs = outer.map((p) => p[0]), ys = outer.map((p) => p[1]);
    if (Math.max(...xs) < BBOX.minLon || Math.min(...xs) > BBOX.maxLon || Math.max(...ys) < BBOX.minLat || Math.min(...ys) > BBOX.maxLat) continue;
    const c = simplifyRing(clip(outer.slice(0, -1)), 0.004);
    if (c.length >= 3) rings.push(c.map(([lo, la]) => [r(lo), r(la)]));
  }
}

const pl = JSON.parse(fs.readFileSync(placesPath, "utf8"));
const places = pl.features
  .map((f) => ({ name: f.properties.name, lat: r(f.geometry.coordinates[1]), lon: r(f.geometry.coordinates[0]), pop: f.properties.pop_max || 0, country: f.properties.adm0name }))
  .filter((p) => p.lat >= BBOX.minLat && p.lat <= BBOX.maxLat && p.lon >= BBOX.minLon && p.lon <= BBOX.maxLon && (p.pop >= 100000 || (p.country === "Sri Lanka" && p.pop >= 20000)));

// Hand-curated extras: airports, seas/straits, landmarks (kept small and checkable).
const features = [
  { name: "Kempegowda Airport (BLR)", kind: "airport", lat: 13.1989, lon: 77.7068 },
  { name: "Bandaranaike Airport (CMB)", kind: "airport", lat: 7.1808, lon: 79.8841 },
  { name: "Chennai Airport (MAA)", kind: "airport", lat: 12.99, lon: 80.1693 },
  { name: "Trichy Airport (TRZ)", kind: "airport", lat: 10.7654, lon: 78.7097 },
  { name: "Jaffna Airport (JAF)", kind: "airport", lat: 9.7923, lon: 80.0702 },
  { name: "Mattala Airport (HRI)", kind: "airport", lat: 6.2844, lon: 81.1245 },
  { name: "Palk Strait", kind: "sea", lat: 9.6, lon: 79.6 },
  { name: "Gulf of Mannar", kind: "sea", lat: 8.4, lon: 78.9 },
  { name: "Bay of Bengal", kind: "sea", lat: 10.5, lon: 82.3 },
  { name: "Arabian Sea / Laccadive Sea", kind: "sea", lat: 8.0, lon: 75.2 },
  { name: "Eastern Ghats", kind: "land", lat: 12.0, lon: 78.9 },
  { name: "Western Ghats", kind: "land", lat: 11.5, lon: 76.3 },
  { name: "Cauvery River basin", kind: "land", lat: 11.8, lon: 77.9 },
  { name: "Adam's Bridge (Rama Setu)", kind: "land", lat: 9.12, lon: 79.52 },
  { name: "Sigiriya", kind: "landmark", lat: 7.957, lon: 80.76 },
  { name: "Adam's Peak", kind: "landmark", lat: 6.8096, lon: 80.4994 },
  { name: "Galle Fort", kind: "landmark", lat: 6.0268, lon: 80.217 },
];

fs.writeFileSync(new URL("../Sources/Resources/geo.json", import.meta.url), JSON.stringify({ bbox: BBOX, land: rings, places, features }));
console.log(`rings=${rings.length} points=${rings.reduce((a, b) => a + b.length, 0)} places=${places.length}`);
