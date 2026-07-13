import Foundation

/// Aufschlüsselung der Kühllast eines Raums in ihre Einzelposten (alle in Watt).
public struct CoolingLoadResult: Codable, Hashable, Sendable {
    public var solar: Double
    public var transmission: Double
    public var persons: Double
    public var equipment: Double
    public var lighting: Double
    public var ventilation: Double

    /// Summe der inneren Lasten (Personen + Geräte + Licht).
    public var internalTotal: Double { persons + equipment + lighting }

    /// Gesamte Kühllast des Raums in Watt.
    public var total: Double {
        solar + transmission + persons + equipment + lighting + ventilation
    }

    /// Gesamtlast auf die Raumfläche bezogen (W/m²) – Plausibilitätskennzahl.
    public func specific(for area: Double) -> Double {
        area > 0 ? total / area : 0
    }
}

/// Empfehlung für die Geräteauslegung auf Basis der Gesamtkühllast.
public struct DeviceRecommendation: Hashable, Sendable {
    /// Nennkälteleistung der empfohlenen Klasse in kW.
    public var ratedPowerKW: Double
    /// Ausnutzung der empfohlenen Klasse (Kühllast / Nennleistung), 0–1.
    public var utilization: Double

    public var label: String {
        String(format: "%.1f kW Split-Klimagerät", ratedPowerKW)
    }
}

/// Berechnet die sommerliche Kühllast eines Raums nach dem VDI-2078-Kurzverfahren.
///
/// Vereinfachungen gegenüber dem prüffähigen Stundenverfahren:
/// - keine dynamische Speichermasse; es wird die maximale Einstrahlung je
///   Ausrichtung angesetzt (konservativ, d. h. eher etwas zu groß).
/// - Transmission nur über Außenbauteile mit konstanter Temperaturdifferenz.
///
/// Ausreichend genau für die Auslegung von Split- und Multisplit-Klimageräten
/// in Wohn- und kleinen Gewerbeeinheiten.
public struct CoolingLoadCalculator {

    /// Spezifische Wärmekapazität der Luft × Dichte ≈ 0,34 Wh/(m³·K).
    public static let airHeatCapacity = 0.34

    public var region: ClimateRegion

    public init(region: ClimateRegion) {
        self.region = region
    }

    public func calculate(_ room: Room) -> CoolingLoadResult {
        let deltaT = max(0, region.designOutdoorTemperature - room.indoorTemperature)

        // 1) Solare Last durch Fenster: A · g · I(Ausrichtung) · Verschattung
        let solar = room.windows.reduce(0.0) { sum, window in
            let irr = region.irradiance(for: window.orientation)
            return sum + window.area * window.gValue * irr * window.shading
        }

        // 2) Transmission über Außenwände, Außentüren und Fensterflächen (U · A · ΔT)
        let wallTrans = room.walls
            .filter { $0.isExternal }
            .reduce(0.0) { $0 + $1.uValue * $1.area * deltaT }
        let doorTrans = room.doors
            .filter { $0.isExternal }
            .reduce(0.0) { $0 + $1.uValue * $1.area * deltaT }
        let windowTrans = room.windows
            .reduce(0.0) { $0 + $1.uValue * $1.area * deltaT }
        let transmission = wallTrans + doorTrans + windowTrans

        // 3) Innere Lasten
        let persons = Double(room.internalLoads.persons) * room.internalLoads.wattPerPerson
        let equipment = room.internalLoads.equipmentWatt
        let lighting = room.internalLoads.lightingWattPerSqm * room.floorArea

        // 4) Lüftungslast: 0,34 · n · V · ΔT
        let airFlow = room.airChangeRate * room.volume
        let ventilation = Self.airHeatCapacity * airFlow * deltaT

        return CoolingLoadResult(
            solar: solar,
            transmission: transmission,
            persons: persons,
            equipment: equipment,
            lighting: lighting,
            ventilation: ventilation
        )
    }

    /// Übliche Nennleistungsklassen von Single-Split-Geräten in kW.
    public static let deviceClassesKW: [Double] = [2.0, 2.5, 3.5, 5.0, 7.0]

    /// Wählt die kleinste Geräteklasse, deren Nennleistung die Kühllast deckt.
    public func recommendDevice(for load: Double,
                                classes: [Double] = deviceClassesKW) -> DeviceRecommendation {
        let loadKW = load / 1000.0
        if let fit = classes.sorted().first(where: { $0 >= loadKW }) {
            return DeviceRecommendation(ratedPowerKW: fit, utilization: loadKW / fit)
        }
        // Last über der größten Einzelklasse: nächstgrößeres Vielfaches vorschlagen.
        let largest = classes.max() ?? 7.0
        let needed = (loadKW / largest).rounded(.up) * largest
        return DeviceRecommendation(ratedPowerKW: needed, utilization: loadKW / needed)
    }
}
