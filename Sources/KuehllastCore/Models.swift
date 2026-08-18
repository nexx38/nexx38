import Foundation

/// Himmelsrichtung eines Fensters. Bestimmt die solare Einstrahlung.
public enum Orientation: String, Codable, CaseIterable, Sendable {
    case nord, ost, sued, west, horizontal

    public var label: String {
        switch self {
        case .nord: return "Nord"
        case .ost: return "Ost"
        case .sued: return "Süd"
        case .west: return "West"
        case .horizontal: return "Dachfläche"
        }
    }
}

/// Lage einer gescannten Wand im Grundriss: die beiden Endpunkte der
/// Wandlinie von oben betrachtet (Meter, Scan-Koordinatensystem — relativ,
/// nicht genordet). Nur der LiDAR-Scan liefert das; manuell angelegte und
/// importierte Alt-Wände haben keine Position.
public struct WallPosition: Codable, Hashable, Sendable {
    public var x1: Double
    public var z1: Double
    public var x2: Double
    public var z2: Double

    public init(x1: Double, z1: Double, x2: Double, z2: Double) {
        self.x1 = x1
        self.z1 = z1
        self.x2 = x2
        self.z2 = z2
    }
}

/// Eine Wand aus dem Raumscan. `width` × `height` in Metern.
public struct Wall: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var width: Double
    public var height: Double
    /// Grenzt die Wand an Außenluft? Nur Außenwände tragen Transmissionslast.
    public var isExternal: Bool
    /// Ausrichtung der Außenwand (für Dokumentation; Transmission ist richtungsunabhängig).
    public var orientation: Orientation?
    /// U-Wert der Wand in W/(m²·K). Default: gedämmte Außenwand.
    public var uValue: Double
    /// Fläche der Fenster-/Türöffnungen, die in dieser Wand liegen und für die
    /// Transmission abgezogen werden müssen. 0 = manuell erfasste (bereits opake)
    /// Wand – so wie in der Referenz-Berechnung. Nur Scan/Import setzen das (> 0),
    /// weil RoomPlan die volle Wandfläche inkl. Öffnungen liefert.
    public var openingDeductionArea: Double
    /// Grundriss-Lage der Wand (nur bei gescannten Wänden vorhanden).
    public var position: WallPosition?

    /// Brutto-Wandfläche (Breite × Höhe) – für Anzeige und Export.
    public var area: Double { width * height }
    /// Netto-opake Wandfläche für die Transmission: Brutto minus Öffnungen (≥ 0).
    public var netArea: Double { max(0, width * height - openingDeductionArea) }

    public init(id: UUID = UUID(), width: Double, height: Double,
                isExternal: Bool = true, orientation: Orientation? = nil,
                uValue: Double = 0.28, openingDeductionArea: Double = 0,
                position: WallPosition? = nil) {
        self.id = id
        self.width = width
        self.height = height
        self.isExternal = isExternal
        self.orientation = orientation
        self.uValue = uValue
        self.openingDeductionArea = openingDeductionArea
        self.position = position
    }

    private enum CodingKeys: String, CodingKey {
        case id, width, height, isExternal, orientation, uValue, openingDeductionArea, position
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.width = try c.decode(Double.self, forKey: .width)
        self.height = try c.decode(Double.self, forKey: .height)
        self.isExternal = (try? c.decode(Bool.self, forKey: .isExternal)) ?? true
        self.orientation = try? c.decode(Orientation.self, forKey: .orientation)
        self.uValue = (try? c.decode(Double.self, forKey: .uValue)) ?? 0.28
        self.openingDeductionArea = (try? c.decode(Double.self, forKey: .openingDeductionArea)) ?? 0
        self.position = try? c.decode(WallPosition.self, forKey: .position)
    }
}

/// Eine Tür aus dem Raumscan. RoomPlan erkennt große Schiebefenster/Terrassentüren
/// oft als „Tür" – deshalb kann eine Tür als `isGlazed` markiert werden und zählt
/// dann wie ein Fenster (solarer Eintrag über Ausrichtung + g-Wert).
public struct Door: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var width: Double
    public var height: Double
    public var isExternal: Bool
    public var uValue: Double
    /// Verglast? Dann wie ein Fenster gerechnet (Solar-Eintrag). Sonst nur Transmission.
    public var isGlazed: Bool
    /// Himmelsrichtung – nur relevant, wenn verglast.
    public var orientation: Orientation
    /// g-Wert des Glases – nur relevant, wenn verglast.
    public var gValue: Double
    /// Verschattungsfaktor – nur relevant, wenn verglast.
    public var shading: Double

    public var area: Double { width * height }

    public init(id: UUID = UUID(), width: Double, height: Double,
                isExternal: Bool = false, uValue: Double = 1.8,
                isGlazed: Bool = false, orientation: Orientation = .sued,
                gValue: Double = 0.6, shading: Double = 1.0) {
        self.id = id
        self.width = width
        self.height = height
        self.isExternal = isExternal
        self.uValue = uValue
        self.isGlazed = isGlazed
        self.orientation = orientation
        self.gValue = gValue
        self.shading = shading
    }

    private enum CodingKeys: String, CodingKey {
        case id, width, height, isExternal, uValue, isGlazed, orientation, gValue, shading
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.width = try c.decode(Double.self, forKey: .width)
        self.height = try c.decode(Double.self, forKey: .height)
        self.isExternal = (try? c.decode(Bool.self, forKey: .isExternal)) ?? false
        self.uValue = (try? c.decode(Double.self, forKey: .uValue)) ?? 1.8
        self.isGlazed = (try? c.decode(Bool.self, forKey: .isGlazed)) ?? false
        self.orientation = (try? c.decode(Orientation.self, forKey: .orientation)) ?? .sued
        self.gValue = (try? c.decode(Double.self, forKey: .gValue)) ?? 0.6
        self.shading = (try? c.decode(Double.self, forKey: .shading)) ?? 1.0
    }
}

/// Ein Fenster. Für die Kühllast der wichtigste Posten (solarer Eintrag).
public struct Window: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var width: Double
    public var height: Double
    public var orientation: Orientation
    /// Gesamtenergiedurchlassgrad g des Glases (0–1). Zweifach-Wärmeschutz ≈ 0.6.
    public var gValue: Double
    /// Verschattungsfaktor (0–1). 1 = frei besonnt, kleiner = Markise/Rollladen/Bäume.
    public var shading: Double
    /// U-Wert des Fensters in W/(m²·K).
    public var uValue: Double

    public var area: Double { width * height }

    public init(id: UUID = UUID(), width: Double, height: Double,
                orientation: Orientation = .sued, gValue: Double = 0.6,
                shading: Double = 1.0, uValue: Double = 1.1) {
        self.id = id
        self.width = width
        self.height = height
        self.orientation = orientation
        self.gValue = gValue
        self.shading = shading
        self.uValue = uValue
    }

    private enum CodingKeys: String, CodingKey {
        case id, width, height, orientation, gValue, shading, uValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.width = try c.decode(Double.self, forKey: .width)
        self.height = try c.decode(Double.self, forKey: .height)
        self.orientation = (try? c.decode(Orientation.self, forKey: .orientation)) ?? .sued
        self.gValue = (try? c.decode(Double.self, forKey: .gValue)) ?? 0.6
        self.shading = (try? c.decode(Double.self, forKey: .shading)) ?? 1.0
        self.uValue = (try? c.decode(Double.self, forKey: .uValue)) ?? 1.1
    }
}

/// Innere Lasten: Personen, Geräte, Beleuchtung.
public struct InternalLoads: Codable, Hashable, Sendable {
    public var persons: Int
    /// Wärmeabgabe je Person in W (sensibel, leichte Tätigkeit ≈ 100 W).
    public var wattPerPerson: Double
    /// Geräteleistung im Raum in W (TV, PC, Küchengeräte …).
    public var equipmentWatt: Double
    /// Beleuchtung in W/m². Wird mit der Raumfläche multipliziert.
    public var lightingWattPerSqm: Double

    public init(persons: Int = 2, wattPerPerson: Double = 100,
                equipmentWatt: Double = 200, lightingWattPerSqm: Double = 8) {
        self.persons = persons
        self.wattPerPerson = wattPerPerson
        self.equipmentWatt = equipmentWatt
        self.lightingWattPerSqm = lightingWattPerSqm
    }
}

/// Ein Raum. Kompatibel zum HeizlastScan-JSON, erweitert um Kühllast-Felder.
public struct Room: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var floorArea: Double
    public var height: Double
    public var walls: [Wall]
    public var doors: [Door]
    public var windows: [Window]
    public var internalLoads: InternalLoads
    /// Wunsch-Raumtemperatur im Sommer in °C (Auslegung meist 26 °C).
    public var indoorTemperature: Double
    /// Luftwechselrate in 1/h für die Lüftungslast.
    public var airChangeRate: Double
    /// Klimastandort für Außentemperatur und Einstrahlung.
    public var climateRegionID: String
    public var scannedAt: Date?
    /// Winterliche Heizlast-Parameter (Decke/Boden, θ_i, Klima, WB, Lüftung).
    /// Optional: fehlt bei reinen Kühllast-Räumen und alten Dateien – die
    /// Heizlast greift dann auf HeatingParameters()-Vorgaben zurück.
    public var heating: HeatingParameters?
    /// Dateinamen der beim Scan aufgenommenen Fotos (liegen im Dokumente-
    /// verzeichnis der App unter RoomPhotos/). Optional, damit alte
    /// rooms.json-Dateien ohne dieses Feld weiter dekodieren.
    public var photoFilenames: [String]?
    /// Gewählte Baujahr-Klasse (BuildingEra.rawValue) – bestimmt die
    /// U-Wert-Vorgaben und wird im PDF als Annahme ausgewiesen. Optional.
    public var constructionEra: String?
    /// Vorhandene Heizkörper (Bestandsaufnahme) – für den WP-Tauglichkeits-
    /// Check und den hydraulischen Abgleich. Optional für alte Dateien.
    public var radiators: [Radiator]?
    /// Zugehöriges Projekt (Kunde/Objekt). Optional: alte Dateien ohne
    /// Projekt werden beim Laden dem Standard-Projekt zugeordnet.
    public var projectID: UUID?

    public var volume: Double { floorArea * height }

    public init(id: UUID = UUID(), name: String = "Raum 1",
                floorArea: Double, height: Double,
                walls: [Wall] = [], doors: [Door] = [], windows: [Window] = [],
                internalLoads: InternalLoads = InternalLoads(),
                indoorTemperature: Double = 26,
                airChangeRate: Double = 0.5,
                climateRegionID: String = ClimateRegion.default.id,
                scannedAt: Date? = nil,
                heating: HeatingParameters? = nil,
                photoFilenames: [String]? = nil,
                constructionEra: String? = nil,
                radiators: [Radiator]? = nil,
                projectID: UUID? = nil) {
        self.id = id
        self.name = name
        self.floorArea = floorArea
        self.height = height
        self.walls = walls
        self.doors = doors
        self.windows = windows
        self.internalLoads = internalLoads
        self.indoorTemperature = indoorTemperature
        self.airChangeRate = airChangeRate
        self.climateRegionID = climateRegionID
        self.scannedAt = scannedAt
        self.heating = heating
        self.photoFilenames = photoFilenames
        self.constructionEra = constructionEra
        self.radiators = radiators
        self.projectID = projectID
    }
}
