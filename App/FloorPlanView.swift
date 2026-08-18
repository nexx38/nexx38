import SwiftUI
import KuehllastCore

/// Grundriss-Bildschirm: zeigt die gescannten Wände von oben; Antippen einer
/// Wand schaltet Außenwand ↔ innen/Nachbar um. Beantwortet die Frage „welche
/// Wand in der Liste ist welche?" visuell statt über Maße.
struct FloorPlanScreen: View {
    @Binding var walls: [Wall]

    var body: some View {
        VStack(spacing: 12) {
            Text("Fassadenseiten antippen, bis nur die echten Außenwände orange sind. Wände zum beheizten Nachbarn zählen als innen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            FloorPlanWallPicker(walls: $walls)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

            HStack(spacing: 18) {
                legendDot(.orange, "Außenwand")
                legendDot(Color(.systemGray3), "innen / Nachbar")
            }
            .font(.caption)
            .padding(.bottom, 8)
        }
        .navigationTitle("Grundriss")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 22, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

/// Zeichnet die Wandlinien maßstäblich und macht sie antippbar.
struct FloorPlanWallPicker: View {
    @Binding var walls: [Wall]

    var body: some View {
        GeometryReader { geo in
            let segments = Self.layout(walls: walls, in: geo.size)
            Canvas { context, _ in
                for segment in segments {
                    var path = Path()
                    path.move(to: segment.a)
                    path.addLine(to: segment.b)
                    context.stroke(path,
                                   with: .color(segment.external ? .orange : Color(.systemGray3)),
                                   style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    // Wandlänge in Metern an die Linienmitte – so findet man die
                    // Wand aus der Liste im Grundriss wieder.
                    let mid = CGPoint(x: (segment.a.x + segment.b.x) / 2,
                                      y: (segment.a.y + segment.b.y) / 2)
                    if segment.lengthM >= 0.6 {
                        context.draw(Text(String(format: "%.1f", segment.lengthM))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.primary),
                                     at: mid)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if let index = Self.nearestWallIndex(to: value.location, segments: segments) {
                            walls[index].isExternal.toggle()
                        }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    struct Segment {
        let a: CGPoint
        let b: CGPoint
        let external: Bool
        let lengthM: Double
        let wallIndex: Int
    }

    /// Skaliert die Wand-Endpunkte (Meter, Scan-Koordinaten) in die Ansicht.
    static func layout(walls: [Wall], in size: CGSize) -> [Segment] {
        let positioned = walls.enumerated().compactMap { index, wall in
            wall.position.map { (index: index, wall: wall, pos: $0) }
        }
        guard !positioned.isEmpty, size.width > 60, size.height > 60 else { return [] }

        var minX = Double.infinity, maxX = -Double.infinity
        var minZ = Double.infinity, maxZ = -Double.infinity
        for item in positioned {
            minX = min(minX, item.pos.x1, item.pos.x2)
            maxX = max(maxX, item.pos.x1, item.pos.x2)
            minZ = min(minZ, item.pos.z1, item.pos.z2)
            maxZ = max(maxZ, item.pos.z1, item.pos.z2)
        }
        let spanX = max(maxX - minX, 0.5)
        let spanZ = max(maxZ - minZ, 0.5)
        let pad: CGFloat = 28
        let scale = min((size.width - 2 * pad) / CGFloat(spanX),
                        (size.height - 2 * pad) / CGFloat(spanZ))
        let offsetX = (size.width - CGFloat(spanX) * scale) / 2
        let offsetY = (size.height - CGFloat(spanZ) * scale) / 2

        func point(_ x: Double, _ z: Double) -> CGPoint {
            CGPoint(x: offsetX + CGFloat(x - minX) * scale,
                    y: offsetY + CGFloat(z - minZ) * scale)
        }

        return positioned.map { item in
            Segment(a: point(item.pos.x1, item.pos.z1),
                    b: point(item.pos.x2, item.pos.z2),
                    external: item.wall.isExternal,
                    lengthM: item.wall.width,
                    wallIndex: item.index)
        }
    }

    /// Wand mit dem kleinsten Abstand zum Tipp-Punkt (max. 34 pt Toleranz).
    static func nearestWallIndex(to point: CGPoint, segments: [Segment]) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for segment in segments {
            let d = distance(from: point, toSegment: segment.a, segment.b)
            if d < 34, best == nil || d < best!.distance {
                best = (segment.wallIndex, d)
            }
        }
        return best?.index
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x, aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSquared))
        let proj = CGPoint(x: a.x + t * abx, y: a.y + t * aby)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}
