import Foundation

/// Winterliche Heizlast-Parameter eines Raums (DIN EN 12831, vereinfachtes
/// Verfahren). Als EIN optionales Feld an `Room` gehängt, damit bestehende
/// (nur für Kühllast angelegte) Räume und HeizlastScan-Importe weiter dekodieren
/// – fehlt das Feld, greifen die Vorgaben hier.
public struct HeatingParameters: Codable, Hashable, Sendable {
    /// Norm-Innentemperatur θ_i (Heizfall): Wohnen 20, Bad 24, Schlafen 18 °C.
    public var indoorTemperature: Double
    /// Name des Klimastandorts → Norm-Außentemperatur θ_e (siehe HeatingClimate).
    public var climateName: String
    /// Wärmebrückenzuschlag in % auf die Transmission (pauschal, DIN 4108 Bbl 2).
    public var thermalBridgePercent: Double
    /// Luftwechselrate n in 1/h für die Lüftungslast.
    public var airChangeRate: Double
    /// Wärmerückgewinnungsgrad in % (0 = keine WRG).
    public var heatRecoveryPercent: Double
    /// Dach/Decke (Fläche = Grundfläche). U-Wert in W/(m²K); nil = nicht angesetzt.
    public var ceilingUValue: Double?
    /// Falls die Decke nicht an Außenluft grenzt: Temperatur dahinter (°C).
    public var ceilingAdjacentTemp: Double?
    /// Boden (Fläche = Grundfläche). U-Wert; nil = nicht angesetzt.
    public var floorUValue: Double?
    /// Temperatur unter dem Boden (unbeheizter Keller ≈ 10 °C).
    public var floorAdjacentTemp: Double?

    public init(indoorTemperature: Double = 20,
                climateName: String = "Berlin",
                thermalBridgePercent: Double = 5,
                airChangeRate: Double = 0.5,
                heatRecoveryPercent: Double = 0,
                ceilingUValue: Double? = nil,
                ceilingAdjacentTemp: Double? = nil,
                floorUValue: Double? = nil,
                floorAdjacentTemp: Double? = 10) {
        self.indoorTemperature = indoorTemperature
        self.climateName = climateName
        self.thermalBridgePercent = thermalBridgePercent
        self.airChangeRate = airChangeRate
        self.heatRecoveryPercent = heatRecoveryPercent
        self.ceilingUValue = ceilingUValue
        self.ceilingAdjacentTemp = ceilingAdjacentTemp
        self.floorUValue = floorUValue
        self.floorAdjacentTemp = floorAdjacentTemp
    }

    // Fehlende Schlüssel auf die Vorgaben zurückfallen lassen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.indoorTemperature   = (try? c.decode(Double.self, forKey: .indoorTemperature)) ?? 20
        self.climateName         = (try? c.decode(String.self, forKey: .climateName)) ?? "Berlin"
        self.thermalBridgePercent = (try? c.decode(Double.self, forKey: .thermalBridgePercent)) ?? 5
        self.airChangeRate       = (try? c.decode(Double.self, forKey: .airChangeRate)) ?? 0.5
        self.heatRecoveryPercent = (try? c.decode(Double.self, forKey: .heatRecoveryPercent)) ?? 0
        self.ceilingUValue       = try? c.decode(Double.self, forKey: .ceilingUValue)
        self.ceilingAdjacentTemp = try? c.decode(Double.self, forKey: .ceilingAdjacentTemp)
        self.floorUValue         = try? c.decode(Double.self, forKey: .floorUValue)
        self.floorAdjacentTemp   = (try? c.decode(Double.self, forKey: .floorAdjacentTemp)) ?? 10
    }
}

/// Aufschlüsselung der Heizlast eines Raums (alle Werte in Watt).
public struct HeatingLoadResult: Codable, Hashable, Sendable {
    public var transmission: Double      // Φ_T ohne Zuschlag
    public var thermalBridges: Double    // Wärmebrückenzuschlag
    public var ventilation: Double       // Φ_V
    public var deltaT: Double            // θ_i − θ_e (K), für die Anzeige

    /// Transmission inklusive Wärmebrückenzuschlag.
    public var transmissionWithBridges: Double { transmission + thermalBridges }
    /// Gesamt-Norm-Heizlast Φ_HL = Φ_T + Zuschlag + Φ_V.
    public var total: Double { transmission + thermalBridges + ventilation }

    public func specific(for area: Double) -> Double {
        area > 0 ? total / area : 0
    }
}

/// Berechnet die Norm-Heizlast eines Raums nach DIN EN 12831 (vereinfachtes
/// Verfahren). Formeln 1:1 aus der bewährten HeizlastProfi-Web-Berechnung
/// (js/calc.js) portiert; gegen deren PDF-Ergebnisse verifiziert.
public struct HeatingLoadCalculator {

    /// c_p × ρ der Luft ≈ 0,34 Wh/(m³·K).
    public static let airHeatCapacity = 0.34

    public init() {}

    public func calculate(_ room: Room) -> HeatingLoadResult {
        let p = room.heating ?? HeatingParameters()
        let indoor = p.indoorTemperature
        let outdoor = HeatingClimate.named(p.climateName).designOutdoorTemperature
        let baseDeltaT = max(0, indoor - outdoor)

        // Φ_T = Σ (A · U · Δθ); Δθ nutzt adjacentTemp, sonst θ_i − θ_e.
        func loss(area: Double, u: Double, adjacent: Double?) -> Double {
            let dt = adjacent != nil ? (indoor - adjacent!) : (indoor - outdoor)
            return max(0, area * u * dt)
        }

        var transmission = 0.0
        // Außenwände (nur außenliegende) – Netto-Fläche, Öffnungen sind abgezogen.
        for wall in room.walls where wall.isExternal {
            transmission += loss(area: wall.netArea, u: wall.uValue, adjacent: nil)
        }
        // Fenster (führen immer nach außen)
        for window in room.windows {
            transmission += loss(area: window.area, u: window.uValue, adjacent: nil)
        }
        // Außen- und verglaste Türen
        for door in room.doors where door.isExternal || door.isGlazed {
            transmission += loss(area: door.area, u: door.uValue, adjacent: nil)
        }
        // Dach/Decke und Boden (Fläche = Grundfläche), falls angesetzt
        if let u = p.ceilingUValue {
            transmission += loss(area: room.floorArea, u: u, adjacent: p.ceilingAdjacentTemp)
        }
        if let u = p.floorUValue {
            transmission += loss(area: room.floorArea, u: u, adjacent: p.floorAdjacentTemp)
        }

        let thermalBridges = transmission * (p.thermalBridgePercent / 100.0)

        // Φ_V = 0,34 · n_eff · V · Δθ
        let volume = room.floorArea * room.height
        let effAirChange = p.airChangeRate * (1 - p.heatRecoveryPercent / 100.0)
        let ventilation = Self.airHeatCapacity * effAirChange * volume * baseDeltaT

        return HeatingLoadResult(
            transmission: transmission,
            thermalBridges: thermalBridges,
            ventilation: ventilation,
            deltaT: baseDeltaT
        )
    }
}
