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

        let doors = captured.doors.map { surface -> Door in
            let width = Double(surface.dimensions.x)
            // Breite „Türen" sind fast immer Schiebefenster/Terrassentüren →
            // als verglast + außenliegend vorbelegen (im Editor korrigierbar).
            let likelyGlazed = width >= 1.5
            return Door(width: width,
                        height: Double(surface.dimensions.y),
                        isExternal: likelyGlazed,
                        isGlazed: likelyGlazed)
        }

        let windows = captured.windows.map { surface in
            Window(width: Double(surface.dimensions.x),
                   height: Double(surface.dimensions.y),
                   orientation: .sued)
        }

        let height = medianHeight(of: captured.walls)
        let floorArea = orientedFloorArea(from: captured.walls)
        // RoomPlan liefert die volle Wandfläche inkl. Öffnungen → Fenster/Türen
        // abziehen, sonst zählt die Öffnungsfläche doppelt (Wand-U + Öffnungs-U).
        let netWalls = WallAreaNormalizer.deductingOpenings(walls: walls, doors: doors, windows: windows)

        return Room(
            name: name,
            floorArea: floorArea,
            height: height,
            walls: netWalls,
            doors: doors,
            windows: windows,
            scannedAt: Date()
        )
    }

    /// Lichte Raumhöhe = Median der Wandhöhen (robust gegen eine fehl­erkannte Wand).
    private static func medianHeight(of walls: [CapturedRoom.Surface]) -> Double {
        let hs = walls.map { Double($0.dimensions.y) }.filter { $0 > 1.0 }.sorted()
        guard !hs.isEmpty else { return 2.5 }
        return hs[hs.count / 2]
    }

    /// Grundfläche über die flächenkleinste gedrehte Bounding-Box der Wand-Endpunkte.
    /// Eine achsparallele Box überschätzt schräg gescannte Räume massiv (ein um 45°
    /// gedrehter 5,5×3,2-m-Raum hätte achsparallel ~36 m², real sind es ~18 m²).
    /// Das Durchprobieren der Drehung findet die echte Grundfläche unabhängig von
    /// der Scan-Ausrichtung. Übernommen aus dem bewährten HeizlastScan-Code.
    private static func orientedFloorArea(from walls: [CapturedRoom.Surface]) -> Double {
        var pts: [(x: Double, z: Double)] = []
        for wall in walls {
            let t = wall.transform
            let cx = Double(t.columns.3.x), cz = Double(t.columns.3.z)
            let halfLen = Double(wall.dimensions.x) / 2.0
            let ax = Double(t.columns.0.x), az = Double(t.columns.0.z)
            pts.append((cx + ax * halfLen, cz + az * halfLen))
            pts.append((cx - ax * halfLen, cz - az * halfLen))
        }
        guard pts.count >= 2 else { return 20 }

        var bestArea = Double.greatestFiniteMagnitude
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
            if area < bestArea { bestArea = area }
            deg += 1
        }
        return bestArea.isFinite && bestArea > 1 ? bestArea : 20
    }
}
