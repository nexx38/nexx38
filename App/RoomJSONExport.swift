import Foundation
import KuehllastCore

/// JSON-Repräsentation eines Raums zum Teilen und Ansehen (z. B. am PC).
/// Bewusst flach und lesbar gehalten – enthält alle Eingaben plus das Ergebnis.
/// Schlüsselnamen bleiben kompatibel zu Web-Viewer und HeizlastProfi-Import
/// („app": "KuehllastScan" nicht umbenennen!); neue Schlüssel nur additiv.
struct RoomJSONExport: Codable {
    struct Wall: Codable {
        let width: Double
        let height: Double
        let external: Bool
        let uValue: Double
        let adjacentTemp: Double?
    }
    struct Door: Codable {
        let width: Double
        let height: Double
        let glazed: Bool
        let external: Bool
        let orientation: String?
        let gValue: Double?
        let shading: Double?
        let uValue: Double
    }
    struct Window: Codable {
        let width: Double
        let height: Double
        let orientation: String
        let gValue: Double
        let shading: Double
        let uValue: Double
    }

    let app: String
    let version: Int
    let exportedAt: String
    let name: String
    let floorArea: Double
    let height: Double
    let indoorTemperature: Double
    let climateRegion: String
    let constructionEra: String?
    let walls: [Wall]
    let doors: [Door]
    let windows: [Window]
    let coolingLoadWatt: Double
    let heatingLoadWatt: Double
    let recommendedDeviceKW: Double

    static func make(from room: Room) -> RoomJSONExport {
        let region = ClimateRegion.region(id: room.climateRegionID)
        let calc = CoolingLoadCalculator(region: region)
        let result = calc.calculate(room)
        let recommendation = calc.recommendDevice(for: result.total)
        let heating = HeatingLoadCalculator().calculate(room)
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
            constructionEra: room.constructionEra,
            walls: room.walls.map {
                Wall(width: round2($0.width), height: round2($0.height),
                     external: $0.isExternal, uValue: $0.uValue,
                     adjacentTemp: $0.adjacentTemp)
            },
            doors: room.doors.map {
                Door(width: round2($0.width), height: round2($0.height),
                     glazed: $0.isGlazed,
                     external: $0.isExternal,
                     orientation: $0.isGlazed ? $0.orientation.rawValue : nil,
                     gValue: $0.isGlazed ? $0.gValue : nil,
                     shading: $0.isGlazed ? $0.shading : nil,
                     uValue: $0.uValue)
            },
            windows: room.windows.map {
                Window(width: round2($0.width), height: round2($0.height),
                       orientation: $0.orientation.rawValue,
                       gValue: $0.gValue, shading: $0.shading, uValue: $0.uValue)
            },
            coolingLoadWatt: result.total.rounded(),
            heatingLoadWatt: heating.total.rounded(),
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
