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

    // Floor area from the axis-aligned bounding box spanned by the wall
    // endpoints (world x/z). Uses only Surface.transform / .dimensions, which
    // are stable across RoomPlan SDK versions. (The iOS-17 floor-polygon API
    // would be more exact for L-shaped rooms — a later refinement.)
    private static func floorArea(_ room: CapturedRoom) -> Double {
        return boundingBoxArea(room)
    }

    // Min/max of wall endpoint positions in world x/z → rectangular footprint.
    private static func boundingBoxArea(_ room: CapturedRoom) -> Double {
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude, maxZ = -Double.greatestFiniteMagnitude
        for wall in room.walls {
            let t = wall.transform
            let cx = Double(t.columns.3.x)
            let cz = Double(t.columns.3.z)
            let halfLen = Double(wall.dimensions.x) / 2.0
            // wall's local x axis in world space
            let ax = Double(t.columns.0.x)
            let az = Double(t.columns.0.z)
            let ex = cx + ax * halfLen, ex2 = cx - ax * halfLen
            let ez = cz + az * halfLen, ez2 = cz - az * halfLen
            minX = min(minX, ex, ex2); maxX = max(maxX, ex, ex2)
            minZ = min(minZ, ez, ez2); maxZ = max(maxZ, ez, ez2)
        }
        guard maxX > minX, maxZ > minZ else { return 0 }
        return (maxX - minX) * (maxZ - minZ)
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}
