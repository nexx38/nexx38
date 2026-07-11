import Foundation
import RoomPlan
import simd

// JSON schema exchanged with the HeizlastProfi web app.
// Keep field names in sync with scanner.js `_parseRoomPlanJSON`.
struct RoomExport: Codable {
    let app: String
    let version: Int
    let scannedAt: String
    let name: String
    let floorArea: Double     // m²
    let height: Double        // m (clear room height)
    let walls: [Opening]      // exterior + interior walls (net, openings already subtracted per wall)
    let windows: [Opening]
    let doors: [Opening]

    struct Opening: Codable {
        let width: Double     // m
        let height: Double    // m
        var area: Double { width * height }
    }
}

enum RoomExporter {

    // Convert a RoomPlan CapturedRoom into the exchange model.
    static func make(from room: CapturedRoom, name: String) -> RoomExport {
        let walls   = room.walls.map   { surfaceToOpening($0) }
        let windows = room.windows.map { surfaceToOpening($0) }
        let doors   = room.doors.map   { surfaceToOpening($0) }

        let height = estimateHeight(room)
        let area   = floorArea(room)

        let iso = ISO8601DateFormatter()
        return RoomExport(
            app: "HeizlastScan",
            version: 1,
            scannedAt: iso.string(from: Date()),
            name: name,
            floorArea: round2(area),
            height: round2(height),
            walls:   walls.map   { RoomExport.Opening(width: round2($0.w), height: round2($0.h)) },
            windows: windows.map { RoomExport.Opening(width: round2($0.w), height: round2($0.h)) },
            doors:   doors.map   { RoomExport.Opening(width: round2($0.w), height: round2($0.h)) }
        )
    }

    // Surface.dimensions: x = width, y = height (metres) in the surface's local frame.
    private static func surfaceToOpening(_ s: CapturedRoom.Surface) -> (w: Double, h: Double) {
        (Double(s.dimensions.x), Double(s.dimensions.y))
    }

    // Clear room height = median wall height (robust against a mis-detected wall).
    private static func estimateHeight(_ room: CapturedRoom) -> Double {
        let hs = room.walls.map { Double($0.dimensions.y) }.filter { $0 > 1.0 }.sorted()
        guard !hs.isEmpty else { return 2.5 }
        return hs[hs.count / 2]
    }

    // Floor area = minimum-area ORIENTED bounding box of the wall endpoints.
    // An axis-aligned box hugely overestimates a room scanned at an angle
    // (a 45°-rotated 5.5×3.2 m room has a ~36 m² axis-aligned box but is only
    // ~18 m²). Brute-forcing the rotation that minimises the box recovers the
    // true footprint regardless of scan orientation.
    private static func floorArea(_ room: CapturedRoom) -> Double {
        // Collect both endpoints of every wall as 2-D (x, z) points.
        var pts: [(x: Double, z: Double)] = []
        for wall in room.walls {
            let t = wall.transform
            let cx = Double(t.columns.3.x)
            let cz = Double(t.columns.3.z)
            let halfLen = Double(wall.dimensions.x) / 2.0
            let ax = Double(t.columns.0.x)   // wall's local x axis in world space
            let az = Double(t.columns.0.z)
            pts.append((cx + ax * halfLen, cz + az * halfLen))
            pts.append((cx - ax * halfLen, cz - az * halfLen))
        }
        guard pts.count >= 2 else { return 0 }

        var best = Double.greatestFiniteMagnitude
        var deg = 0
        while deg < 90 {
            let t = Double(deg) * .pi / 180
            let c = cos(t), s = sin(t)
            var minU = Double.greatestFiniteMagnitude, maxU = -Double.greatestFiniteMagnitude
            var minV = Double.greatestFiniteMagnitude, maxV = -Double.greatestFiniteMagnitude
            for p in pts {
                let u = p.x * c + p.z * s
                let v = -p.x * s + p.z * c
                minU = min(minU, u); maxU = max(maxU, u)
                minV = min(minV, v); maxV = max(maxV, v)
            }
            let area = (maxU - minU) * (maxV - minV)
            if area < best { best = area }
            deg += 1
        }
        return best.isFinite ? best : 0
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}
