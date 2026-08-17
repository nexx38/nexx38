import Foundation

/// Heizkörper-Bauart mit typischer Norm-Leistung (75/65/20 °C) je m² Frontfläche.
/// Anhaltswerte aus den gängigen Herstellertabellen – für den Heizkörper-Check
/// und den vereinfachten hydraulischen Abgleich ausreichend, die
/// herstellerspezifische Tabelle bleibt maßgebend.
public enum RadiatorType: String, Codable, CaseIterable, Sendable {
    case typ10, typ11, typ21, typ22, typ33, glieder

    public var label: String {
        switch self {
        case .typ10:   return "Typ 10 (glatt)"
        case .typ11:   return "Typ 11"
        case .typ21:   return "Typ 21"
        case .typ22:   return "Typ 22"
        case .typ33:   return "Typ 33"
        case .glieder: return "Gliederheizkörper"
        }
    }

    /// Norm-Wärmeleistung bei 75/65/20 in W je m² Frontfläche (Breite × Höhe).
    public var normWattPerSqm: Double {
        switch self {
        case .typ10:   return 750
        case .typ11:   return 1050
        case .typ21:   return 1350
        case .typ22:   return 1700
        case .typ33:   return 2350
        case .glieder: return 900
        }
    }
}

/// Ein vorhandener Heizkörper im Raum (Bestandsaufnahme für WP-Tauglichkeit
/// und hydraulischen Abgleich).
public struct Radiator: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var type: RadiatorType
    /// Baubreite in m.
    public var widthM: Double
    /// Bauhöhe in m.
    public var heightM: Double

    public init(id: UUID = UUID(), type: RadiatorType = .typ22,
                widthM: Double, heightM: Double) {
        self.id = id
        self.type = type
        self.widthM = widthM
        self.heightM = heightM
    }

    private enum CodingKeys: String, CodingKey { case id, type, widthM, heightM }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.type = (try? c.decode(RadiatorType.self, forKey: .type)) ?? .typ22
        self.widthM = try c.decode(Double.self, forKey: .widthM)
        self.heightM = try c.decode(Double.self, forKey: .heightM)
    }

    /// Norm-Wärmeleistung bei 75/65/20 in W.
    public var normPower: Double { type.normWattPerSqm * widthM * heightM }

    /// Wärmeleistung bei anderer Vor-/Rücklauftemperatur (Heizkörperexponent
    /// n = 1,3; arithmetische Übertemperatur – für den Praxis-Check genau genug).
    /// Beispiel: 55/45 bei 20 °C Raum = Faktor (30/50)^1,3 ≈ 0,51.
    public func power(flow: Double, ret: Double, roomTemp: Double) -> Double {
        let overTemp = (flow + ret) / 2 - roomTemp
        guard overTemp > 0 else { return 0 }
        return normPower * pow(overTemp / 50.0, 1.3)
    }
}

/// Ergebnis des Heizkörper-Checks eines Raums: reicht der Bestand bei
/// WP-Vorlauftemperatur?
public enum RadiatorVerdict: String, Sendable {
    case ausreichend   // Deckung >= 100 %
    case knapp         // Deckung >= 85 %
    case zuKlein       // Deckung < 85 %

    public var label: String {
        switch self {
        case .ausreichend: return "ausreichend"
        case .knapp:       return "knapp"
        case .zuKlein:     return "zu klein"
        }
    }
}

public struct RadiatorCheckResult: Sendable {
    /// Summenleistung aller Heizkörper des Raums bei VL/RL in W.
    public var capacity: Double
    /// Heizlast des Raums in W.
    public var demand: Double
    /// Deckung capacity/demand (1,0 = 100 %).
    public var coverage: Double
    public var verdict: RadiatorVerdict

    public init(capacity: Double, demand: Double) {
        self.capacity = capacity
        self.demand = demand
        self.coverage = demand > 0 ? capacity / demand : 1
        if coverage >= 1.0 { self.verdict = .ausreichend }
        else if coverage >= 0.85 { self.verdict = .knapp }
        else { self.verdict = .zuKlein }
    }
}
