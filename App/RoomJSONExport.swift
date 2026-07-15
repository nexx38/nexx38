import Foundation
import KuehllastCore

/// JSON-Repräsentation eines Raums zum Teilen und Ansehen (z. B. am PC).
/// Bewusst flach und lesbar gehalten – enthält alle Eingaben plus das Ergebnis.
struct RoomJSONExport: Codable {
    struct Wall: Codable {
        let width: Double
        let height: Double
        let external: Bool
    }
    struct Door: Codable {
        let width: Double
        let height: Double
        let glazed: Bool
        let orientation: String?
    }
    struct Window: Codable {
        let width: Double
        let height: Double
        let orientation: String
        let gValue: Double
        let shading: Double
    }

    let app: String
    let version: Int
    let exportedAt: String
    let name: String
    let floorArea: Double
    let height: Double
    let indoorTemperature: Double
    let climateRegion: String
    let walls: [Wall]
    let doors: [Door]
    let windows: [Window]
    let coolingLoadWatt: Double
    let recommendedDeviceKW: Double

    static func make(from room: Room) -> RoomJSONExport {
        let region = ClimateRegion.region(id: room.climateRegionID)
        let calc = CoolingLoadCalculator(region: region)
        let result = calc.calculate(room)
        let recommendation = calc.recommendDevice(for: result.total)
        let iso = ISO8601DateFormatter()

        return RoomJSONExport(
            app: "KuehllastScan",
            version: 1,
            exportedAt: iso.string(from: Date()),
            name: room.name,
            floorArea: round2(room.floorArea),
            height: round2(room.height),
            indoorTemperature: room.indoorTemperature,
            climateRegion: region.name,
            walls: room.walls.map { Wall(width: round2($0.width), height: round2($0.height), external: $0.isExternal) },
            doors: room.doors.map {
                Door(width: round2($0.width), height: round2($0.height),
                     glazed: $0.isGlazed,
                     orientation: $0.isGlazed ? $0.orientation.rawValue : nil)
            },
            windows: room.windows.map {
                Window(width: round2($0.width), height: round2($0.height),
                       orientation: $0.orientation.rawValue,
                       gValue: $0.gValue, shading: $0.shading)
            },
            coolingLoadWatt: result.total.rounded(),
            recommendedDeviceKW: recommendation.ratedPowerKW
        )
    }

    /// Schreibt den Export als JSON-Datei in ein temporäres Verzeichnis und gibt
    /// die URL zurück (zum Teilen per ShareLink).
    static func fileURL(for room: Room) -> URL {
        let export = make(from: room)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(export)) ?? Data()
        let safeName = room.name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KuehllastScan-\(safeName).json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}
