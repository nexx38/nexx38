import Foundation
import RoomPlan
import simd
import KuehllastCore

/// Übersetzt einen von RoomPlan erfassten `CapturedRoom` in unser `Room`-Modell.
///
/// RoomPlan liefert Wände, Türen und Fenster mit Maßen (Breite × Höhe in Metern).
/// Die Grundfläche wird aus der Grundriss-Ausdehnung der Wände geschätzt und lässt
/// sich im Raum-Editor nachjustieren. Fenster bekommen eine Standardausrichtung
/// (Süd) – die tatsächliche Himmelsrichtung trägt man danach im Editor ein, weil
/// RoomPlan sie nicht liefert.
enum RoomPlanConverter {

    static func room(from captured: CapturedRoom, name: String = "Gescannter Raum") -> Room {
        let walls = captured.walls.map { surface in
            Wall(width: Double(surface.dimensions.x),
                 height: Double(surface.dimensions.y),
                 isExternal: true)
        }

        let doors = captured.doors.map { surface in
            Door(width: Double(surface.dimensions.x),
                 height: Double(surface.dimensions.y))
        }

        let windows = captured.windows.map { surface in
            Window(width: Double(surface.dimensions.x),
                   height: Double(surface.dimensions.y),
                   orientation: .sued)
        }

        let height = walls.map(\.height).max() ?? 2.5
        let floorArea = estimatedFloorArea(from: captured.walls, fallbackHeight: height)

        return Room(
            name: name,
            floorArea: floorArea,
            height: height,
            walls: walls,
            doors: doors,
            windows: windows,
            scannedAt: Date()
        )
    }

    /// Schätzt die Grundfläche aus der Ausdehnung der Wandpositionen im Grundriss
    /// (x/z-Ebene). Grobe, aber brauchbare Ausgangsgröße – im Editor korrigierbar.
    private static func estimatedFloorArea(from walls: [CapturedRoom.Surface],
                                           fallbackHeight: Double) -> Double {
        guard !walls.isEmpty else { return 20 }

        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude

        for wall in walls {
            let p = wall.transform.columns.3   // Position der Wandmitte
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
        }

        let width = Double(maxX - minX)
        let depth = Double(maxZ - minZ)
        let area = width * depth

        return area > 1 ? area : 20   // Notnagel, falls die Schätzung unbrauchbar ist
    }
}
