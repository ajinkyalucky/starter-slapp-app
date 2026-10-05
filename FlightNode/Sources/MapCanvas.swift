import SwiftUI
import CoreLocation

/// Offline map drawn straight from the bundled coastline — no tiles, no network.
struct MapCanvas: View {
    let geo: GeoData
    let plan: FlightPlan
    let fix: Fix?
    let radiusKm: Double

    private let kmPerDeg = 111.195

    var body: some View {
        Canvas { ctx, size in
            let center = fix?.coordinate ?? GeoMath.interpolate(plan.from.coordinate, plan.to.coordinate, 0.5)
            let kmPerPt = radiusKm / (min(size.width, size.height) / 2)
            let cosLat = cos(GeoMath.rad(center.latitude))

            func pt(_ lat: Double, _ lon: Double) -> CGPoint {
                CGPoint(x: size.width / 2 + (lon - center.longitude) * cosLat * kmPerDeg / kmPerPt,
                        y: size.height / 2 - (lat - center.latitude) * kmPerDeg / kmPerPt)
            }

            // Land
            for ring in geo.land where ring.count > 2 {
                var path = Path()
                path.move(to: pt(ring[0][1], ring[0][0]))
                for p in ring.dropFirst() { path.addLine(to: pt(p[1], p[0])) }
                path.closeSubpath()
                ctx.fill(path, with: .color(Color(.systemGray5)))
                ctx.stroke(path, with: .color(Color(.systemGray3)), lineWidth: 0.7)
            }

            // Planned route (dashed great circle, 48 segments)
            var route = Path()
            for i in 0...48 {
                let c = GeoMath.interpolate(plan.from.coordinate, plan.to.coordinate, Double(i) / 48)
                let p = pt(c.latitude, c.longitude)
                i == 0 ? route.move(to: p) : route.addLine(to: p)
            }
            ctx.stroke(route, with: .color(.blue.opacity(0.7)), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

            // Places & airports within view
            let labelLimit = radiusKm > 300 ? 100_000 : 0
            for p in geo.places where p.pop >= labelLimit {
                draw(name: p.name, at: pt(p.lat, p.lon), in: size, ctx: &ctx, dot: .gray, bold: false)
            }
            for f in geo.features where f.kind == "airport" || f.kind == "landmark" || f.kind == "sea" {
                let color: Color = f.kind == "sea" ? .blue.opacity(0.6) : f.kind == "airport" ? .orange : .green
                draw(name: f.name, at: pt(f.lat, f.lon), in: size, ctx: &ctx, dot: color, bold: f.kind == "airport")
            }

            // You
            if let fix {
                let p = pt(fix.coordinate.latitude, fix.coordinate.longitude)
                let accKm = fix.accuracyM / 1000
                let accR = max(0, min(accKm / kmPerPt, 80))
                if accR > 6 {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - accR, y: p.y - accR, width: accR * 2, height: accR * 2)),
                             with: .color(.blue.opacity(0.15)))
                }
                var plane = ctx
                plane.translateBy(x: p.x, y: p.y)
                plane.rotate(by: .degrees(fix.courseDeg ?? 0))
                var arrow = Path()
                arrow.move(to: CGPoint(x: 0, y: -13)); arrow.addLine(to: CGPoint(x: 9, y: 10))
                arrow.addLine(to: CGPoint(x: 0, y: 5)); arrow.addLine(to: CGPoint(x: -9, y: 10)); arrow.closeSubpath()
                plane.fill(arrow, with: .color(.red))
                plane.stroke(arrow, with: .color(.white), lineWidth: 1.5)
            }
        }
        .background(Color(red: 0.80, green: 0.89, blue: 0.97))   // sea
        .clipped()
    }

    private func draw(name: String, at p: CGPoint, in size: CGSize, ctx: inout GraphicsContext, dot: Color, bold: Bool) {
        guard p.x > -20, p.y > -20, p.x < size.width + 20, p.y < size.height + 20 else { return }
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(dot))
        let t = Text(name).font(.system(size: 10, weight: bold ? .semibold : .regular)).foregroundColor(.primary.opacity(0.8))
        ctx.draw(t, at: CGPoint(x: p.x + 5, y: p.y), anchor: .leading)
    }
}
