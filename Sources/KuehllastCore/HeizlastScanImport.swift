import Foundation

/// Liest das JSON-Exportformat der HeizlastScan-App ein und wandelt es in einen
/// `Room` um. Das Format ist bewusst kompatibel gehalten – vorhandene Scans
/// lassen sich also direkt für die Kühllast weiterverwenden.
///
/// Beispiel-JSON:
/// ```json
/// {
///   "name": "Raum 1", "app": "HeizlastScan", "version": 1,
///   "floorArea": 36.07, "height": 2.56, "scannedAt": "2026-07-11T14:48:58Z",
///   "walls":   [ { "width": 5.51, "height": 2.56 } ],
///   "doors":   [ { "width": 2.20, "height": 2.28 } ],
///   "windows": [ ]
/// }
/// ```
public enum HeizlastScanImport {

    public struct ImportError: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    private struct Raw: Decodable {
        struct Opening: Decodable {
            let width: Double
            let height: Double
            let orientation: String?
            let gValue: Double?
            // Von KuehllastScan-/Web-Viewer-Exporten geschrieben; HeizlastScan-
            // Altdateien haben diese Schlüssel nicht (→ nil, Heuristik greift).
            let external: Bool?
            let glazed: Bool?
            let shading: Double?
            let uValue: Double?
        }
        let name: String?
        let floorArea: Double?
        let height: Double?
        let walls: [Opening]?
        let doors: [Opening]?
        let windows: [Opening]?
        let scannedAt: String?
    }

    public static func room(fromJSON data: Data,
                            climateRegionID: String = ClimateRegion.default.id) throws -> Room {
        let decoder = JSONDecoder()
        guard let raw = try? decoder.decode(Raw.self, from: data) else {
            throw ImportError(message: "JSON konnte nicht gelesen werden.")
        }
        guard let floorArea = raw.floorArea, let height = raw.height else {
            throw ImportError(message: "Im Scan fehlen Fläche oder Höhe.")
        }

        let walls = (raw.walls ?? []).map { w in
            Wall(width: w.width, height: w.height,
                 isExternal: w.external ?? true,
                 orientation: w.orientation.flatMap(Orientation.init(rawValue:)),
                 uValue: w.uValue ?? 0.28)
        }
        let doors = (raw.doors ?? []).map { d -> Door in
            // Explizite Flags (unser eigenes Exportformat) haben Vorrang.
            // Altdateien ohne Flags: breite „Türen" sind fast immer Schiebe-
            // fenster/Terrassentüren → verglast + außen (gleiche Heuristik
            // wie beim Live-Scan in RoomPlanConverter, sonst rechnet derselbe
            // Raum je nach Weg unterschiedlich).
            let likelyGlazed = d.width >= 1.5
            let isGlazed = d.glazed ?? likelyGlazed
            return Door(width: d.width, height: d.height,
                        isExternal: d.external ?? isGlazed,
                        uValue: d.uValue ?? (isGlazed ? 1.1 : 1.8),
                        isGlazed: isGlazed,
                        orientation: d.orientation.flatMap(Orientation.init(rawValue:)) ?? .sued,
                        gValue: d.gValue ?? 0.6,
                        shading: d.shading ?? 1.0)
        }
        let windows = (raw.windows ?? []).map { w in
            Window(width: w.width, height: w.height,
                   orientation: w.orientation.flatMap(Orientation.init(rawValue:)) ?? .sued,
                   gValue: w.gValue ?? 0.6,
                   shading: w.shading ?? 1.0,
                   uValue: w.uValue ?? 1.1)
        }

        var scannedDate: Date?
        if let s = raw.scannedAt {
            let iso = ISO8601DateFormatter()
            scannedDate = iso.date(from: s)
        }

        // Import liefert Brutto-Wandflächen (inkl. Öffnungen) → Öffnungen abziehen,
        // damit Fenster/Türen nicht doppelt in die Transmission eingehen.
        let netWalls = WallAreaNormalizer.deductingOpenings(walls: walls, doors: doors, windows: windows)

        return Room(
            name: raw.name ?? "Raum",
            floorArea: floorArea,
            height: height,
            walls: netWalls,
            doors: doors,
            windows: windows,
            climateRegionID: climateRegionID,
            scannedAt: scannedDate
        )
    }
}
