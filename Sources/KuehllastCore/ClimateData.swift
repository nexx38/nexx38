import Foundation

/// Klimastandort mit den Auslegungswerten für die Kühllast.
///
/// `designOutdoorTemperature` = maßgebende sommerliche Außentemperatur (°C).
/// `solarIrradiance` = maximale Strahlungsleistung je Himmelsrichtung in W/m²
/// Glasfläche (Näherungswerte für Mitteleuropa, Auslegungstag im Juli).
public struct ClimateRegion: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var designOutdoorTemperature: Double
    public var solarIrradiance: [Orientation: Double]

    public init(id: String, name: String, designOutdoorTemperature: Double,
                solarIrradiance: [Orientation: Double]) {
        self.id = id
        self.name = name
        self.designOutdoorTemperature = designOutdoorTemperature
        self.solarIrradiance = solarIrradiance
    }

    public func irradiance(for orientation: Orientation) -> Double {
        solarIrradiance[orientation] ?? 0
    }
}

public extension ClimateRegion {
    /// Näherungswerte der maximalen sommerlichen Einstrahlung je Ausrichtung (W/m²).
    /// Grundlage: Auslegungstag Juli, klarer Himmel, senkrechte Verglasung
    /// (Dachfläche = horizontal). Werte sind bewusst konservativ gerundet und
    /// dienen dem Kurzverfahren zur Auslegung von Klimageräten, nicht dem
    /// prüffähigen Stundennachweis nach VDI 2078.
    static func standardIrradiance(scale: Double = 1.0) -> [Orientation: Double] {
        [
            .nord: 110 * scale,
            .ost: 490 * scale,
            .sued: 370 * scale,
            .west: 490 * scale,
            .horizontal: 700 * scale
        ]
    }

    /// Kleine, editierbare Auswahl deutscher Klimaregionen.
    /// Außentemperaturen orientieren sich an den sommerlichen Auslegungswerten
    /// der Klimazonen; bei Bedarf pro Projekt anpassbar.
    static let all: [ClimateRegion] = [
        ClimateRegion(id: "de-west-rheinland", name: "Rheinland / Niederrhein",
                      designOutdoorTemperature: 32,
                      solarIrradiance: standardIrradiance()),
        ClimateRegion(id: "de-nord-kueste", name: "Norddeutschland / Küste",
                      designOutdoorTemperature: 30,
                      solarIrradiance: standardIrradiance(scale: 0.95)),
        ClimateRegion(id: "de-mitte", name: "Mitteldeutschland",
                      designOutdoorTemperature: 32,
                      solarIrradiance: standardIrradiance()),
        ClimateRegion(id: "de-sued-oberrhein", name: "Oberrhein / Südwest",
                      designOutdoorTemperature: 34,
                      solarIrradiance: standardIrradiance(scale: 1.05)),
        ClimateRegion(id: "de-sued-alpen", name: "Süddeutschland / Alpenvorland",
                      designOutdoorTemperature: 32,
                      solarIrradiance: standardIrradiance())
    ]

    static let `default` = all[0]

    static func region(id: String) -> ClimateRegion {
        all.first { $0.id == id } ?? .default
    }
}
