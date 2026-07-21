import Foundation

/// Klimastandort für die winterliche Heizlast: die Norm-Außentemperatur θ_e
/// nach DIN EN 12831 Beiblatt (maßgebender Auslegungswert im Winter, °C).
/// Bewusst getrennt von `ClimateRegion` (Sommer/Kühllast), da beide völlig
/// unterschiedliche Auslegungspunkte sind.
public struct HeatingClimate: Codable, Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    /// Norm-Außentemperatur θ_e in °C (z. B. Berlin −14).
    public var designOutdoorTemperature: Double

    public init(name: String, designOutdoorTemperature: Double) {
        self.name = name
        self.designOutdoorTemperature = designOutdoorTemperature
    }
}

public extension HeatingClimate {
    /// Deutsche Städte mit ihrer Norm-Außentemperatur (Winter-Auslegung).
    /// 1:1 aus der bewährten HeizlastProfi-Tabelle (js/data.js) übernommen,
    /// damit die App dieselben Werte liefert wie die Web-Berechnung.
    static let all: [HeatingClimate] = [
        .init(name: "Aachen", designOutdoorTemperature: -10),
        .init(name: "Augsburg", designOutdoorTemperature: -16),
        .init(name: "Berlin", designOutdoorTemperature: -14),
        .init(name: "Bielefeld", designOutdoorTemperature: -12),
        .init(name: "Bochum", designOutdoorTemperature: -12),
        .init(name: "Bonn", designOutdoorTemperature: -10),
        .init(name: "Bremen", designOutdoorTemperature: -12),
        .init(name: "Braunschweig", designOutdoorTemperature: -14),
        .init(name: "Chemnitz", designOutdoorTemperature: -16),
        .init(name: "Dortmund", designOutdoorTemperature: -12),
        .init(name: "Dresden", designOutdoorTemperature: -16),
        .init(name: "Düsseldorf", designOutdoorTemperature: -10),
        .init(name: "Erfurt", designOutdoorTemperature: -16),
        .init(name: "Essen", designOutdoorTemperature: -10),
        .init(name: "Frankfurt am Main", designOutdoorTemperature: -12),
        .init(name: "Freiburg im Breisgau", designOutdoorTemperature: -12),
        .init(name: "Göttingen", designOutdoorTemperature: -14),
        .init(name: "Halle (Saale)", designOutdoorTemperature: -14),
        .init(name: "Hamburg", designOutdoorTemperature: -12),
        .init(name: "Hannover", designOutdoorTemperature: -14),
        .init(name: "Heidelberg", designOutdoorTemperature: -12),
        .init(name: "Karlsruhe", designOutdoorTemperature: -12),
        .init(name: "Kassel", designOutdoorTemperature: -14),
        .init(name: "Kiel", designOutdoorTemperature: -12),
        .init(name: "Köln", designOutdoorTemperature: -10),
        .init(name: "Leipzig", designOutdoorTemperature: -14),
        .init(name: "Magdeburg", designOutdoorTemperature: -16),
        .init(name: "Mainz", designOutdoorTemperature: -12),
        .init(name: "Mannheim", designOutdoorTemperature: -12),
        .init(name: "München", designOutdoorTemperature: -16),
        .init(name: "Münster", designOutdoorTemperature: -12),
        .init(name: "Nürnberg", designOutdoorTemperature: -16),
        .init(name: "Oldenburg", designOutdoorTemperature: -12),
        .init(name: "Osnabrück", designOutdoorTemperature: -12),
        .init(name: "Potsdam", designOutdoorTemperature: -14),
        .init(name: "Regensburg", designOutdoorTemperature: -16),
        .init(name: "Rostock", designOutdoorTemperature: -14),
        .init(name: "Saarbrücken", designOutdoorTemperature: -12),
        .init(name: "Stuttgart", designOutdoorTemperature: -14),
        .init(name: "Ulm", designOutdoorTemperature: -16),
        .init(name: "Wiesbaden", designOutdoorTemperature: -12),
        .init(name: "Würzburg", designOutdoorTemperature: -14),
    ]

    static let `default` = all.first { $0.name == "Berlin" } ?? all[0]

    static func named(_ name: String) -> HeatingClimate {
        all.first { $0.name == name } ?? .default
    }
}
