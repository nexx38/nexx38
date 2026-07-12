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

    // width/height stay for simple table display (unchanged from v1).
    // x1/z1/x2/z2 are new in v2: both endpoints in a shared room-local 2D
    // coordinate system (metres, room-oriented so walls come out roughly
    // axis-aligned) — enough to draw a 2D floor plan on the web side.
    struct Opening: Codable {
        let width: Double     // m
        let height: Double    // m
        let x1: Double
        let z1: Double
        let x2: Double
        let z2: Double
        var area: Double { width * height }
    }
}

enum RoomExporter {

    // Convert a RoomPlan CapturedRoom into the exchange model.
    static func make(from room: CapturedRoom, name: String) -> RoomExport {
        let obb = orientedFootprint(room)

        let toOpening = { (s: CapturedRoom.Surface) -> RoomExport.Opening in
            let seg = localSegment(s, obb)
            return RoomExport.Opening(
                width: round2(Double(s.dimensions.x)),
                height: round2(Double(s.dimensions.y)),
                x1: round2(seg.x1), z1: round2(seg.z1),
                x2: round2(seg.x2), z2: round2(seg.z2)
            )
        }

        let height = estimateHeight(room)
        let iso = ISO8601DateFormatter()
        return RoomExport(
            app: "HeizlastScan",
            version: 2,
            scannedAt: iso.string(from: Date()),
            name: name,
            floorArea: round2(obb.area),
            height: round2(height),
            walls:   room.walls.map(toOpening),
            windows: room.windows.map(toOpening),
            doors:   room.doors.map(toOpening)
        )
    }

    // Clear room height = median wall height (robust against a mis-detected wall).
    private static func estimateHeight(_ room: CapturedRoom) -> Double {
        let hs = room.walls.map { Double($0.dimensions.y) }.filter { $0 > 1.0 }.sorted()
        guard !hs.isEmpty else { return 2.5 }
        return hs[hs.count / 2]
    }

    // Minimum-area oriented bounding box (OBB) of the wall endpoints, plus the
    // rotation/offset needed to convert any world (x,z) point into the same
    // room-local frame. An axis-aligned box hugely overestimates a room
    // scanned at an angle (a 45°-rotated 5.5×3.2 m room has a ~36 m²
    // axis-aligned box but is only ~18 m²) — brute-forcing the rotation that
    // minimises the box recovers the true footprint regardless of scan
    // orientation, and doubles as the 2D floor-plan coordinate system.
    struct OBB { let cosA: Double; let sinA: Double; let minU: Double; let minV: Double; let area: Double }

    private static func orientedFootprint(_ room: CapturedRoom) -> OBB {
        var pts: [(x: Double, z: Double)] = []
        for wall in room.walls {
            let t = wall.transform
            let cx = Double(t.columns.3.x), cz = Double(t.columns.3.z)
            let halfLen = Double(wall.dimensions.x) / 2.0
            let ax = Double(t.columns.0.x), az = Double(t.columns.0.z)
            pts.append((cx + ax * halfLen, cz + az * halfLen))
            pts.append((cx - ax * halfLen, cz - az * halfLen))
        }
        guard pts.count >= 2 else { return OBB(cosA: 1, sinA: 0, minU: 0, minV: 0, area: 0) }

        var best: (area: Double, cosA: Double, sinA: Double, minU: Double, minV: Double)?
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
            if best == nil || area < best!.area {
                best = (area, c, s, minU, minV)
            }
            deg += 1
        }
        guard let b = best, b.area.isFinite else { return OBB(cosA: 1, sinA: 0, minU: 0, minV: 0, area: 0) }
        return OBB(cosA: b.cosA, sinA: b.sinA, minU: b.minU, minV: b.minV, area: b.area)
    }

    // Project one surface's two endpoints (wall/window/door — all share the
    // same Surface shape) into the room-local (u, v) frame defined by `obb`.
    private static func localSegment(_ s: CapturedRoom.Surface, _ obb: OBB) -> (x1: Double, z1: Double, x2: Double, z2: Double) {
        let t = s.transform
        let cx = Double(t.columns.3.x), cz = Double(t.columns.3.z)
        let halfLen = Double(s.dimensions.x) / 2.0
        let ax = Double(t.columns.0.x), az = Double(t.columns.0.z)
        let wx1 = cx + ax * halfLen, wz1 = cz + az * halfLen
        let wx2 = cx - ax * halfLen, wz2 = cz - az * halfLen

        func toLocal(_ x: Double, _ z: Double) -> (Double, Double) {
            let u = x * obb.cosA + z * obb.sinA - obb.minU
            let v = -x * obb.sinA + z * obb.cosA - obb.minV
            return (u, v)
        }
        let (u1, v1) = toLocal(wx1, wz1)
        let (u2, v2) = toLocal(wx2, wz2)
        return (u1, v1, u2, v2)
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}
