import Foundation

/// Gebäudeweite Anlagen-Einstellungen (Wärmepumpe, Klima, Abgleich).
/// Wird in der App als building.json gespeichert; fehlende Schlüssel fallen
/// auf die Vorgaben zurück (gleiche Robustheit wie HeatingParameters).
public struct BuildingSettings: Codable, Hashable, Sendable {
    /// Personen im Haushalt für den Warmwasser-Zuschlag der WP-Auslegung.
    public var dhwPersons: Int
    /// EVU-Sperrzeit in h/Tag (typisch 2; 0 = keine Sperrzeit).
    public var blockingHours: Double
    /// Geplante Vorlauftemperatur der Wärmepumpe in °C.
    public var flowTemp: Double
    /// Geplante Rücklauftemperatur in °C.
    public var returnTemp: Double
    /// Auslegungs-Spreizung für den hydraulischen Abgleich in K.
    public var spreadK: Double
    /// Gleichzeitigkeitsfaktor der Klima-Innengeräte (Multisplit, 0–1).
    public var simultaneity: Double

    public init(dhwPersons: Int = 3, blockingHours: Double = 2,
                flowTemp: Double = 55, returnTemp: Double = 45,
                spreadK: Double = 10, simultaneity: Double = 0.8) {
        self.dhwPersons = dhwPersons
        self.blockingHours = blockingHours
        self.flowTemp = flowTemp
        self.returnTemp = returnTemp
        self.spreadK = spreadK
        self.simultaneity = simultaneity
    }

    private enum CodingKeys: String, CodingKey {
        case dhwPersons, blockingHours, flowTemp, returnTemp, spreadK, simultaneity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.dhwPersons    = (try? c.decode(Int.self, forKey: .dhwPersons)) ?? 3
        self.blockingHours = (try? c.decode(Double.self, forKey: .blockingHours)) ?? 2
        self.flowTemp      = (try? c.decode(Double.self, forKey: .flowTemp)) ?? 55
        self.returnTemp    = (try? c.decode(Double.self, forKey: .returnTemp)) ?? 45
        self.spreadK       = (try? c.decode(Double.self, forKey: .spreadK)) ?? 10
        self.simultaneity  = (try? c.decode(Double.self, forKey: .simultaneity)) ?? 0.8
    }
}

// MARK: - Wärmepumpen-Auslegung

/// Ergebnis der überschlägigen WP-Auslegung (angelehnt an VDI 4645:
/// Gebäude-Heizlast + Warmwasser-Zuschlag, hochgerechnet um die EVU-Sperrzeit).
public struct HeatPumpRecommendation: Sendable {
    public var heatingLoadW: Double
    public var dhwW: Double
    public var blockingFactor: Double
    /// Erforderliche Heizleistung in kW (inkl. Zuschläge).
    public var requiredKW: Double
    /// Nächste übliche Gerätegröße in kW.
    public var suggestedKW: Double
}

public enum HeatPumpSizing {

    /// Übliche Nenn-Heizleistungen von Wärmepumpen in kW.
    public static let standardSizesKW: [Double] = [4, 6, 8, 10, 12, 14, 16, 20, 25, 30]

    /// Warmwasser-Zuschlag je Person in W (VDI-4645-Anhaltswert 0,2–0,3 kW).
    public static let dhwWattPerPerson: Double = 250

    public static func recommend(heatingLoadW: Double,
                                 dhwPersons: Int,
                                 blockingHours: Double) -> HeatPumpRecommendation {
        let dhw = Double(max(0, dhwPersons)) * dhwWattPerPerson
        let hours = min(max(blockingHours, 0), 8)
        let factor = 24.0 / (24.0 - hours)
        let requiredKW = (heatingLoadW + dhw) * factor / 1000.0
        let suggested = standardSizesKW.first { $0 >= requiredKW }
            ?? (requiredKW / 5).rounded(.up) * 5
        return HeatPumpRecommendation(heatingLoadW: heatingLoadW, dhwW: dhw,
                                      blockingFactor: factor,
                                      requiredKW: requiredKW, suggestedKW: suggested)
    }
}

// MARK: - Multisplit-Klima-Auslegung

/// Auslegung einer Multisplit-Anlage: je Raum ein Innengerät (Klasse nach
/// Kühllast), Außengerät über die Summe mit Gleichzeitigkeitsfaktor
/// (nicht alle Räume brauchen gleichzeitig volle Leistung).
public struct MultiSplitPlan: Sendable {
    public struct IndoorUnit: Sendable {
        public var roomName: String
        public var coolingLoadW: Double
        public var unitKW: Double
    }
    public var indoorUnits: [IndoorUnit]
    public var simultaneity: Double
    /// Summe der Innengeräte-Nennleistungen in kW.
    public var indoorTotalKW: Double { indoorUnits.reduce(0) { $0 + $1.unitKW } }
    /// Erforderliche Außengeräteleistung in kW (Summe × Gleichzeitigkeit).
    public var outdoorRequiredKW: Double {
        (indoorTotalKW * simultaneity * 10).rounded() / 10
    }
}

public enum MultiSplitSizing {

    /// Kleinste Innengeräte-Klasse, deren Nennleistung die Kühllast deckt
    /// (gleiche Klassen wie die Einzelgerät-Empfehlung).
    public static func indoorClassKW(forLoadW load: Double) -> Double {
        let loadKW = load / 1000.0
        if let fit = CoolingLoadCalculator.deviceClassesKW.sorted().first(where: { $0 >= loadKW }) {
            return fit
        }
        let largest = CoolingLoadCalculator.deviceClassesKW.max() ?? 7.0
        return (loadKW / largest).rounded(.up) * largest
    }

    public static func plan(rooms: [(name: String, coolingLoadW: Double)],
                            simultaneity: Double) -> MultiSplitPlan {
        let units = rooms.map { room in
            MultiSplitPlan.IndoorUnit(roomName: room.name,
                                      coolingLoadW: room.coolingLoadW,
                                      unitKW: indoorClassKW(forLoadW: room.coolingLoadW))
        }
        let s = min(max(simultaneity, 0.5), 1.0)
        return MultiSplitPlan(indoorUnits: units, simultaneity: s)
    }
}

// MARK: - Hydraulischer Abgleich (Verfahren B, vereinfacht)

/// Voreinstellwert eines Heizkörper-Thermostatventils.
public struct ValvePreset: Sendable {
    /// Auslegungs-Volumenstrom in kg/h.
    public var flowKgPerH: Double
    /// Erforderlicher kv-Wert in m³/h.
    public var kvNeeded: Double
    /// Empfohlene Voreinstellstufe (1–8); nil = über Stufe 8 (Ventil prüfen).
    public var preset: Int?

    public var presetLabel: String {
        preset.map { "Stufe \($0)" } ?? "> Stufe 8"
    }
}

public enum HydraulicBalancing {

    /// Generische kv-Werte der Voreinstellstufen 1–8 (angelehnt an übliche
    /// Thermostatventile). Herstellertabelle bleibt maßgebend – die Stufen
    /// hier sind der Startwert für die Einstellung vor Ort.
    public static let presetKv: [(stage: Int, kv: Double)] = [
        (1, 0.09), (2, 0.16), (3, 0.29), (4, 0.50),
        (5, 0.72), (6, 0.95), (7, 1.15), (8, 1.40)
    ]

    /// Angenommener Differenzdruck am Ventil in mbar (Verfahren B).
    public static let valveDpMbar: Double = 100

    /// Volumenstrom und Voreinstellstufe für einen Heizkörper.
    /// - Parameter loadW: anteilige Heizlast des Heizkörpers in W.
    /// - Parameter spreadK: Auslegungs-Spreizung in K.
    public static func preset(loadW: Double, spreadK: Double) -> ValvePreset {
        let spread = max(spreadK, 3)
        // m = Q · 0,86 / ΔT  [kg/h]
        let flow = loadW * 0.86 / spread
        // kv = V [m³/h] / sqrt(Δp [bar])
        let kv = (flow / 1000.0) / sqrt(valveDpMbar / 1000.0)
        let stage = presetKv.first { $0.kv >= kv }?.stage
        return ValvePreset(flowKgPerH: flow, kvNeeded: kv, preset: stage)
    }
}
