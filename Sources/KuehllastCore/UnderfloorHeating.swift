import Foundation

// MARK: - Art der Heizfläche

/// Art der Heizfläche eines Raums.
/// Eigene Aufzählung statt eines Bool, weil ein Raum beides haben kann
/// (Fußbodenheizung im Wohnbereich + Handtuchheizkörper im Bad) und weil
/// später weitere Flächen dazukommen können (Wand-/Deckenheizung).
public enum HeatingSurfaceKind: String, Codable, CaseIterable, Sendable {
    case radiator
    case underfloor

    public var label: String {
        switch self {
        case .radiator:   return "Heizkörper"
        case .underfloor: return "Fußbodenheizung"
        }
    }
}

// MARK: - Verlegeabstand

/// Verlegeabstand der Heizrohre im Estrich.
///
/// `baseCoefficient` ist der Wärmeleitwert K_H der Heizfläche in W/(m²·K),
/// also die Wärmeabgabe je m² und je Kelvin mittlerer Übertemperatur, bei
/// **Belag-Wärmedurchlasswiderstand 0** (blanker Estrich/Fliesen) und dem
/// üblichen Nassaufbau: Zementestrich ~45 mm über dem Rohr, Rohr 16×2 bis
/// 17×2. Die Werte sind die gängigen Anhaltswerte der Herstellertabellen
/// (Größenordnung DIN EN 1264-2, Basiskennlinie).
///
/// ⚠️ Kurzverfahren: der echte K_H hängt zusätzlich von Estrichdicke,
/// Estrich-Wärmeleitfähigkeit, Rohraußendurchmesser und Rohrwandmaterial ab.
/// Für die Vorplanung und den WP-Tauglichkeits-Check reicht das; **maßgebend
/// bleibt die Auslegungstabelle des Systemherstellers.**
public enum PipeSpacing: String, Codable, CaseIterable, Sendable {
    case va10, va15, va20, va25, va30

    /// Verlegeabstand in m (Rohrlänge = Fläche / Verlegeabstand).
    public var spacingM: Double {
        switch self {
        case .va10: return 0.10
        case .va15: return 0.15
        case .va20: return 0.20
        case .va25: return 0.25
        case .va30: return 0.30
        }
    }

    public var label: String {
        switch self {
        case .va10: return "VA 10 cm"
        case .va15: return "VA 15 cm"
        case .va20: return "VA 20 cm"
        case .va25: return "VA 25 cm"
        case .va30: return "VA 30 cm"
        }
    }

    /// Wärmeleitwert K_H in W/(m²·K) ohne Bodenbelag.
    /// Enger Abstand = mehr Rohr je m² = geringerer Estrich-Ausbreitwiderstand
    /// = höherer K_H. Deshalb ist die Reihe streng fallend.
    public var baseCoefficient: Double {
        switch self {
        case .va10: return 8.6
        case .va15: return 7.4
        case .va20: return 6.5
        case .va25: return 5.8
        case .va30: return 5.2
        }
    }
}

// MARK: - Bodenbelag

/// Bodenbelag über der Heizfläche. Der Belag sitzt als zusätzlicher
/// Wärmedurchlasswiderstand R_λ,B in Reihe vor der Raumluft und ist in der
/// Praxis der größte Hebel: ein Teppich halbiert die Leistung gegenüber
/// Fliesen fast.
public enum FloorCovering: String, Codable, CaseIterable, Sendable {
    case fliesen, laminat, parkett, teppich

    public var label: String {
        switch self {
        case .fliesen: return "Fliesen / Naturstein"
        case .laminat: return "Laminat / Vinyl"
        case .parkett: return "Parkett / Holz"
        case .teppich: return "Teppich"
        }
    }

    /// Wärmedurchlasswiderstand R_λ,B in m²K/W (Anhaltswerte; DIN EN 1264
    /// rechnet mit maximal 0,15 als Auslegungsgrenze für Wohnräume).
    public var resistance: Double {
        switch self {
        case .fliesen: return 0.00
        case .laminat: return 0.05
        case .parkett: return 0.10
        case .teppich: return 0.15
        }
    }
}

// MARK: - Rohrtyp

/// Heizrohr eines Kreises. Der Innendurchmesser bestimmt die
/// Fließgeschwindigkeit, die empfohlene Höchstlänge den Druckverlust.
///
/// ⚠️ Die Längen sind **Faustwerte** aus der Praxis (Kreis soll mit einer
/// üblichen Verteiler-/Pumpenkennlinie ohne Sonderaufwand zu fahren sein),
/// keine Norm. Der Systemhersteller kann andere Grenzen nennen.
public enum PipeType: String, Codable, CaseIterable, Sendable {
    case pex16x2, pex17x2, pex20x2, verbund16x2, verbund20x2

    public var label: String {
        switch self {
        case .pex16x2:     return "PE-X 16 × 2"
        case .pex17x2:     return "PE-X 17 × 2"
        case .pex20x2:     return "PE-X 20 × 2"
        case .verbund16x2: return "Verbundrohr 16 × 2"
        case .verbund20x2: return "Verbundrohr 20 × 2"
        }
    }

    /// Lichter Innendurchmesser in mm (Außendurchmesser − 2 × Wandstärke).
    public var innerDiameterMM: Double {
        switch self {
        case .pex16x2, .verbund16x2: return 12
        case .pex17x2:               return 13
        case .pex20x2, .verbund20x2: return 16
        }
    }

    /// Empfohlene Höchstlänge eines Kreises in m (inkl. Anbindeleitung).
    public var recommendedMaxLengthM: Double {
        switch self {
        case .pex16x2, .verbund16x2: return 100
        case .pex17x2:               return 120
        case .pex20x2, .verbund20x2: return 150
        }
    }

    /// Ab hier wird der Druckverlust kritisch – Kreis teilen.
    /// 20 % Aufschlag auf die Empfehlung: dazwischen liegt der Bereich, den
    /// man mit erhöhter Pumpenleistung noch fahren kann.
    public var criticalLengthM: Double { recommendedMaxLengthM * 1.2 }
}

// MARK: - Bewertung der Kreislänge

public enum LoopLengthVerdict: String, Sendable {
    case ok
    case grenzwertig
    case zuLang

    public var label: String {
        switch self {
        case .ok:          return "in Ordnung"
        case .grenzwertig: return "grenzwertig"
        case .zuLang:      return "zu lang"
        }
    }

    /// Handlungsempfehlung für den Monteur; nil = nichts zu tun.
    public var advice: String? {
        switch self {
        case .ok:          return nil
        case .grenzwertig: return "Kreis ist grenzwertig lang – Druckverlust und Pumpenkennlinie prüfen"
        case .zuLang:      return "Kreis teilen – Druckverlust wird kritisch"
        }
    }
}

// MARK: - Heizkreis

/// Ein Fußbodenheizkreis: ein Rohrstrang vom Verteiler, der eine Teilfläche
/// eines Raums belegt. Ein Raum kann beliebig viele Kreise haben (große
/// Räume brauchen das schon wegen der Kreislänge), ein Kreis gehört immer
/// zu genau einem Raum.
public struct UnderfloorLoop: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    /// Raum, den dieser Kreis beheizt (Room.id).
    public var roomID: UUID
    /// Bezeichnung am Verteiler, z. B. "HK 1".
    public var name: String
    /// Belegte (aktive) Heizfläche in m².
    /// **Nicht** die Raumfläche: Randstreifen, Einbauküche, Duschtasse und
    /// fest verbaute Möbelzonen liegen ohne Rohr da und zählen nicht mit.
    public var areaSqm: Double
    public var spacing: PipeSpacing
    public var pipe: PipeType
    public var covering: FloorCovering
    /// Abweichender Belag-Wärmedurchlasswiderstand in m²K/W, wenn der Kunde
    /// ein Datenblatt hat (schlägt `covering.resistance`).
    public var coveringResistanceOverride: Double?
    /// Vorlauftemperatur nur für diesen Kreis in °C (eigener Mischer /
    /// eigene Zone). nil = Gebäudewert aus BuildingSettings.flowTemp.
    public var flowTempOverride: Double?
    /// Anbindeleitung Verteiler → Raum und zurück in m. Zählt beim
    /// Druckverlust voll mit, gibt aber kaum Wärme an den Raum ab.
    public var connectionLengthM: Double
    /// Höchste zulässige Fußboden-Oberflächentemperatur in °C.
    /// DIN EN 1264: 29 °C im Aufenthaltsbereich, 33 °C im Bad,
    /// 35 °C im Randstreifen.
    public var maxSurfaceTemp: Double

    public init(id: UUID = UUID(),
                roomID: UUID,
                name: String = "HK 1",
                areaSqm: Double,
                spacing: PipeSpacing = .va15,
                pipe: PipeType = .pex16x2,
                covering: FloorCovering = .fliesen,
                coveringResistanceOverride: Double? = nil,
                flowTempOverride: Double? = nil,
                connectionLengthM: Double = 5,
                maxSurfaceTemp: Double = 29) {
        self.id = id
        self.roomID = roomID
        self.name = name
        self.areaSqm = areaSqm
        self.spacing = spacing
        self.pipe = pipe
        self.covering = covering
        self.coveringResistanceOverride = coveringResistanceOverride
        self.flowTempOverride = flowTempOverride
        self.connectionLengthM = connectionLengthM
        self.maxSurfaceTemp = maxSurfaceTemp
    }

    private enum CodingKeys: String, CodingKey {
        case id, roomID, name, areaSqm, spacing, pipe, covering
        case coveringResistanceOverride, flowTempOverride
        case connectionLengthM, maxSurfaceTemp
    }

    /// Nachsichtiges Dekodieren wie bei Radiator/HeatingParameters: nur
    /// Raumzuordnung und Fläche sind Pflicht, alles andere fällt auf die
    /// Vorgaben zurück – so überleben ältere Dateien einen Feldzuwachs.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id      = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.roomID  = try c.decode(UUID.self, forKey: .roomID)
        self.name    = (try? c.decode(String.self, forKey: .name)) ?? "HK 1"
        self.areaSqm = try c.decode(Double.self, forKey: .areaSqm)
        self.spacing = (try? c.decode(PipeSpacing.self, forKey: .spacing)) ?? .va15
        self.pipe    = (try? c.decode(PipeType.self, forKey: .pipe)) ?? .pex16x2
        self.covering = (try? c.decode(FloorCovering.self, forKey: .covering)) ?? .fliesen
        self.coveringResistanceOverride = try? c.decode(Double.self, forKey: .coveringResistanceOverride)
        self.flowTempOverride = try? c.decode(Double.self, forKey: .flowTempOverride)
        self.connectionLengthM = (try? c.decode(Double.self, forKey: .connectionLengthM)) ?? 5
        self.maxSurfaceTemp = (try? c.decode(Double.self, forKey: .maxSurfaceTemp)) ?? 29
    }

    // MARK: Abgeleitete Größen

    /// Fläche, negative Eingaben abgefangen.
    public var activeAreaSqm: Double { max(areaSqm, 0) }

    /// Wirksamer Belag-Widerstand in m²K/W.
    public var coveringResistance: Double {
        max(coveringResistanceOverride ?? covering.resistance, 0)
    }

    /// Wärmeleitwert K_H dieses Kreises in W/(m²·K), Belag eingerechnet.
    public var heatTransferCoefficient: Double {
        UnderfloorHeating.heatTransferCoefficient(spacing: spacing,
                                                  coveringResistance: coveringResistance)
    }

    /// Verlegte Rohrlänge in m: Fläche / Verlegeabstand + Anbindeleitung.
    /// Die Näherung "Fläche durch Abstand" ist der Standardansatz; sie
    /// unterschlägt die Rohrbögen an den Wendepunkten (wenige Prozent) und
    /// überschätzt dafür bei Schneckenverlegung leicht – das gleicht sich aus.
    public var pipeLengthM: Double {
        activeAreaSqm / spacing.spacingM + max(connectionLengthM, 0)
    }

    public var lengthVerdict: LoopLengthVerdict {
        let len = pipeLengthM
        if len > pipe.criticalLengthM { return .zuLang }
        if len > pipe.recommendedMaxLengthM { return .grenzwertig }
        return .ok
    }

    /// Wärmeabgabe je m² in W/m² bei gegebenen Temperaturen.
    public func outputPerSqm(flow: Double, ret: Double, roomTemp: Double) -> Double {
        let over = UnderfloorHeating.logMeanOverTemperature(flow: flow, ret: ret,
                                                            roomTemp: roomTemp)
        return UnderfloorHeating.outputPerSqm(overTemp: over, spacing: spacing,
                                              coveringResistance: coveringResistance)
    }

    /// Wärmeabgabe des ganzen Kreises in W.
    public func output(flow: Double, ret: Double, roomTemp: Double) -> Double {
        outputPerSqm(flow: flow, ret: ret, roomTemp: roomTemp) * activeAreaSqm
    }
}

// MARK: - Ergebnis je Kreis

/// Hydraulik-Ergebnis eines einzelnen Kreises (Rohrlänge, Volumenstrom,
/// Fließgeschwindigkeit) – die Zahlen für den Verteiler-Zettel.
public struct UnderfloorLoopResult: Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var areaSqm: Double
    /// Verlegte Rohrlänge inkl. Anbindeleitung in m.
    public var pipeLengthM: Double
    public var lengthVerdict: LoopLengthVerdict
    /// Klartext-Warnung; nil = Kreis in Ordnung.
    public var warning: String?
    /// Vorlauftemperatur, mit der dieser Kreis gerechnet wurde, in °C.
    public var flowTemp: Double
    public var outputPerSqm: Double
    public var outputW: Double
    /// Auslegungs-Massenstrom in kg/h (≈ l/h bei Wasser).
    public var flowKgPerH: Double
    /// Fließgeschwindigkeit im Rohr in m/s. Über ~0,5 m/s wird es
    /// hörbar, unter ~0,1 m/s droht Luftansammlung.
    public var velocityMPerS: Double

    public init(id: UUID, name: String, areaSqm: Double, pipeLengthM: Double,
                lengthVerdict: LoopLengthVerdict, flowTemp: Double,
                outputPerSqm: Double, outputW: Double,
                flowKgPerH: Double, velocityMPerS: Double) {
        self.id = id
        self.name = name
        self.areaSqm = areaSqm
        self.pipeLengthM = pipeLengthM
        self.lengthVerdict = lengthVerdict
        self.warning = lengthVerdict.advice
        self.flowTemp = flowTemp
        self.outputPerSqm = outputPerSqm
        self.outputW = outputW
        self.flowKgPerH = flowKgPerH
        self.velocityMPerS = velocityMPerS
    }
}

// MARK: - Deckungsprüfung je Raum

/// Ergebnis der Deckungsprüfung eines Raums mit Fußbodenheizung.
///
/// Die Ampel (`verdict`) benutzt bewusst dieselbe Aufzählung und dieselben
/// Schwellen wie der Heizkörper-Check (`RadiatorVerdict`, 100 % / 85 %):
/// im Bericht steht am Ende eine Ampel je Raum, egal welche Heizfläche
/// drinliegt. Die Schwelle wird nicht dupliziert, sondern von
/// `RadiatorCheckResult` übernommen – sonst laufen beide auseinander.
public struct UnderfloorCheckResult: Sendable {
    /// Summe der belegten Heizflächen in m².
    public var activeAreaSqm: Double
    /// Wärmeabgabe aller Kreise bei geplanter Vorlauftemperatur in W.
    public var capacity: Double
    /// Heizlast des Raums in W.
    public var demand: Double
    /// Deckung capacity/demand (1,0 = 100 %).
    public var coverage: Double
    public var verdict: RadiatorVerdict
    /// Erforderliche Wärmestromdichte in W/m² (Heizlast / belegte Fläche).
    public var requiredOutputPerSqm: Double
    /// **Die wichtigste Zahl für WP-Projekte:** Vorlauftemperatur in °C, bei
    /// der die Kreise dieses Raums die Heizlast gerade decken.
    /// nil = nicht bestimmbar (keine Fläche / kein Kreis).
    /// Berechnet unter der Annahme, dass alle Kreise des Raums mit dieser
    /// Temperatur gefahren werden (`flowTempOverride` bleibt hier außen vor).
    public var requiredFlowTemp: Double?
    /// Sich einstellende mittlere Oberflächentemperatur in °C bei
    /// `requiredOutputPerSqm`.
    public var surfaceTemp: Double
    /// Höchstens zulässige Wärmestromdichte in W/m² aus der
    /// Oberflächentemperatur-Grenze (bei 20 °C Raum und 29 °C Grenze ≈ 100).
    public var maxOutputPerSqm: Double
    /// true = die Heizlast lässt sich auf dieser Fläche nicht normgerecht
    /// abdecken (Boden würde zu heiß). Dann hilft keine höhere
    /// Vorlauftemperatur, sondern nur mehr Fläche, engerer Verlegeabstand,
    /// anderer Belag oder ein Zusatz-Heizkörper.
    public var exceedsSurfaceLimit: Bool
    public var loops: [UnderfloorLoopResult]

    public init(activeAreaSqm: Double,
                capacity: Double,
                demand: Double,
                roomTemp: Double,
                maxSurfaceTemp: Double,
                requiredFlowTemp: Double?,
                loops: [UnderfloorLoopResult]) {
        self.activeAreaSqm = activeAreaSqm
        self.capacity = capacity
        self.demand = demand
        // Deckung und Ampel identisch zum Heizkörper-Check (keine zweite
        // Schwellen-Definition, die auseinanderlaufen könnte).
        let base = RadiatorCheckResult(capacity: capacity, demand: demand)
        self.coverage = base.coverage
        self.verdict = base.verdict
        let required = activeAreaSqm > 0 ? max(demand, 0) / activeAreaSqm : 0
        self.requiredOutputPerSqm = required
        self.requiredFlowTemp = requiredFlowTemp
        self.surfaceTemp = UnderfloorHeating.surfaceTemperature(outputPerSqm: required,
                                                                roomTemp: roomTemp)
        let limit = UnderfloorHeating.maxOutputPerSqm(roomTemp: roomTemp,
                                                     maxSurfaceTemp: maxSurfaceTemp)
        self.maxOutputPerSqm = limit
        self.exceedsSurfaceLimit = required > limit + 0.01
        self.loops = loops
    }
}

// MARK: - Rechenkern

/// Rechenkern Fußbodenheizung.
///
/// **Verfahren (Kurzverfahren, angelehnt an DIN EN 1264-2):**
///
///   q = K_H · ΔΘ_H            [W/m²]
///
/// * ΔΘ_H = mittlere (logarithmische) Übertemperatur zwischen Heizmittel
///   und Raum:  ΔΘ_H = (θ_V − θ_R) / ln((θ_V − θ_i) / (θ_R − θ_i)).
///   Das logarithmische Mittel ist der Ansatz der Norm; es liegt immer
///   etwas unter dem arithmetischen Mittel und ist damit die sichere Seite.
/// * K_H = Wärmeleitwert der Heizfläche in W/(m²·K). Er wird hier als
///   Reihenschaltung zweier Widerstände gebildet:
///
///       K_H = 1 / ( 1/K_H0(Verlegeabstand) + R_λ,B(Bodenbelag) )
///
///   K_H0 ist der Kennwert des Aufbaus **ohne** Belag (siehe
///   `PipeSpacing.baseCoefficient`); darin stecken Estrich-Ausbreitwiderstand
///   und der Wärmeübergang Boden→Raum (α ≈ 10,8 W/(m²·K)) bereits drin.
///   Der Belag kommt als zusätzlicher Widerstand einfach dazu.
///
/// **Oberflächentemperatur** über die Basiskennlinie der Norm:
///   q = 8,92 · (θ_F,m − θ_i)^1,1  → bei 29 °C Oberfläche und 20 °C Raum
///   ergibt das die bekannten ~100 W/m² Grenzleistung.
///
/// ⚠️ **Das ist ein Kurzverfahren für Vorplanung, Angebot und
/// WP-Tauglichkeits-Check.** Estrichdicke, Estrichgüte, Dämmung nach unten,
/// Randzonen und die konkrete Systemplatte sind nicht abgebildet.
/// **Maßgebend bleibt die Auslegung des Systemherstellers** – genau wie beim
/// Heizkörper-Check und beim hydraulischen Abgleich in dieser App.
public enum UnderfloorHeating {

    /// Faktor der Basiskennlinie nach DIN EN 1264 (Wärmeabgabe des Bodens
    /// an den Raum, Strahlung + Konvektion zusammengefasst).
    public static let basicCurveFactor: Double = 8.92
    /// Exponent der Basiskennlinie.
    public static let basicCurveExponent: Double = 1.1

    // MARK: Übertemperatur

    /// Mittlere (logarithmische) Übertemperatur ΔΘ_H in K.
    /// Liefert 0, wenn kein Wärmestrom in den Raum fließen kann
    /// (Vor- oder Rücklauf nicht über Raumtemperatur) – das ist zugleich
    /// der mathematische Grenzwert der Formel.
    public static func logMeanOverTemperature(flow: Double, ret: Double,
                                              roomTemp: Double) -> Double {
        let dFlow = flow - roomTemp
        let dRet  = ret - roomTemp
        guard dFlow > 0, dRet > 0 else { return 0 }
        let spread = dFlow - dRet
        // Grenzfall Spreizung → 0: das log-Mittel geht in die einfache
        // Übertemperatur über (und der Logarithmus im Nenner gegen 0).
        guard abs(spread) > 1e-6 else { return dFlow }
        return spread / log(dFlow / dRet)
    }

    /// Umkehrung: welche Vorlauftemperatur in °C ergibt die verlangte
    /// mittlere Übertemperatur bei fester Spreizung?
    ///
    /// Herleitung (u = θ_V − θ_i, ΔT = Spreizung):
    ///   ΔΘ_H = ΔT / ln(u / (u − ΔT))
    ///   → E := exp(ΔT / ΔΘ_H) = u / (u − ΔT)
    ///   → u = ΔT · E / (E − 1)
    ///   → θ_V = θ_i + ΔT · E / (E − 1)
    /// Damit ist die Rückrechnung exakt die Umkehrfunktion von
    /// `logMeanOverTemperature` – kein Iterieren nötig.
    public static func requiredFlowTemp(overTemp: Double, spreadK: Double,
                                        roomTemp: Double) -> Double {
        guard overTemp > 0 else { return roomTemp }
        let spread = max(spreadK, 0)
        // Spreizung 0: Vor- = Rücklauf, Übertemperatur ist direkt der Abstand.
        guard spread > 1e-6 else { return roomTemp + overTemp }
        let exponent = spread / overTemp
        // exp() läuft bei ~709 über; ab Faktor 50 ist E/(E−1) auf Double-
        // Genauigkeit exakt 1,0 – dann ist θ_R praktisch Raumtemperatur.
        guard exponent < 50 else { return roomTemp + spread }
        let e = exp(exponent)
        return roomTemp + spread * e / (e - 1)
    }

    // MARK: Wärmeabgabe

    /// Wärmeleitwert K_H in W/(m²·K) aus Verlegeabstand und Belag.
    public static func heatTransferCoefficient(spacing: PipeSpacing,
                                               coveringResistance: Double) -> Double {
        let rCovering = max(coveringResistance, 0)
        let rBase = 1.0 / spacing.baseCoefficient
        return 1.0 / (rBase + rCovering)
    }

    /// Wärmeabgabe je m² in W/m².
    public static func outputPerSqm(overTemp: Double, spacing: PipeSpacing,
                                    coveringResistance: Double) -> Double {
        guard overTemp > 0 else { return 0 }
        return heatTransferCoefficient(spacing: spacing,
                                       coveringResistance: coveringResistance) * overTemp
    }

    /// Umkehrung: welche mittlere Übertemperatur in K braucht es für eine
    /// verlangte Wärmestromdichte?
    public static func requiredOverTemperature(outputPerSqm: Double,
                                               spacing: PipeSpacing,
                                               coveringResistance: Double) -> Double {
        guard outputPerSqm > 0 else { return 0 }
        return outputPerSqm / heatTransferCoefficient(spacing: spacing,
                                                      coveringResistance: coveringResistance)
    }

    // MARK: Oberflächentemperatur

    /// Mittlere Fußboden-Oberflächentemperatur in °C bei gegebener
    /// Wärmestromdichte (Basiskennlinie, umgestellt).
    public static func surfaceTemperature(outputPerSqm: Double,
                                          roomTemp: Double) -> Double {
        guard outputPerSqm > 0 else { return roomTemp }
        return roomTemp + pow(outputPerSqm / basicCurveFactor, 1.0 / basicCurveExponent)
    }

    /// Grenz-Wärmestromdichte in W/m², die die zulässige
    /// Oberflächentemperatur gerade einhält.
    public static func maxOutputPerSqm(roomTemp: Double,
                                       maxSurfaceTemp: Double) -> Double {
        let delta = maxSurfaceTemp - roomTemp
        guard delta > 0 else { return 0 }
        return basicCurveFactor * pow(delta, basicCurveExponent)
    }

    // MARK: Hydraulik

    /// Auslegungs-Massenstrom in kg/h:  m = Q · 0,86 / ΔT
    /// (0,86 = 1 / (c_p · Umrechnung) für Wasser, gleiche Formel wie beim
    /// hydraulischen Abgleich der Heizkörper).
    /// Eine Spreizung unter 1 K ist keine sinnvolle Auslegung; wir rechnen
    /// dann mit 1 K weiter, statt durch null zu teilen.
    public static func massFlowKgPerH(outputW: Double, spreadK: Double) -> Double {
        guard outputW > 0 else { return 0 }
        let spread = max(spreadK, 1)
        return outputW * 0.86 / spread
    }

    /// Fließgeschwindigkeit in m/s aus Massenstrom und Innendurchmesser.
    public static func velocityMPerS(flowKgPerH: Double, innerDiameterMM: Double) -> Double {
        guard flowKgPerH > 0, innerDiameterMM > 0 else { return 0 }
        let dM = innerDiameterMM / 1000.0
        let area = Double.pi / 4.0 * dM * dM          // m²
        let volumePerSecond = flowKgPerH / 1000.0 / 3600.0   // m³/s (Wasser ≈ 1 kg/l)
        return volumePerSecond / area
    }

    /// Rohrlänge, Volumenstrom, Geschwindigkeit und Längen-Warnung je Kreis.
    public static func loopResult(loop: UnderfloorLoop,
                                  roomTemp: Double,
                                  flowTemp: Double,
                                  spreadK: Double) -> UnderfloorLoopResult {
        let spread = max(spreadK, 0)
        let flow = loop.flowTempOverride ?? flowTemp
        let perSqm = loop.outputPerSqm(flow: flow, ret: flow - spread, roomTemp: roomTemp)
        let outputW = perSqm * loop.activeAreaSqm
        let kgPerH = massFlowKgPerH(outputW: outputW, spreadK: spread)
        let v = velocityMPerS(flowKgPerH: kgPerH,
                              innerDiameterMM: loop.pipe.innerDiameterMM)
        return UnderfloorLoopResult(id: loop.id,
                                    name: loop.name,
                                    areaSqm: loop.activeAreaSqm,
                                    pipeLengthM: loop.pipeLengthM,
                                    lengthVerdict: loop.lengthVerdict,
                                    flowTemp: flow,
                                    outputPerSqm: perSqm,
                                    outputW: outputW,
                                    flowKgPerH: kgPerH,
                                    velocityMPerS: v)
    }

    // MARK: Deckungsprüfung

    /// Deckt die Fußbodenheizung des Raums die Heizlast?
    ///
    /// - Parameter loops: alle Kreise dieses Raums.
    /// - Parameter demandW: Raum-Heizlast in W (aus HeatingLoadCalculator).
    /// - Parameter roomTemp: Raum-Solltemperatur θ_i in °C.
    /// - Parameter flowTemp: geplante Vorlauftemperatur in °C
    ///   (BuildingSettings.flowTemp); Kreise mit `flowTempOverride`
    ///   benutzen ihren eigenen Wert.
    /// - Parameter spreadK: Auslegungs-Spreizung in K (bei FBH üblich 5–8 K).
    public static func check(loops: [UnderfloorLoop],
                             demandW: Double,
                             roomTemp: Double,
                             flowTemp: Double,
                             spreadK: Double) -> UnderfloorCheckResult {
        let spread = max(spreadK, 0)
        let results = loops.map {
            UnderfloorHeating.loopResult(loop: $0, roomTemp: roomTemp,
                                         flowTemp: flowTemp, spreadK: spread)
        }
        let capacity = results.reduce(0.0) { $0 + $1.outputW }
        let area = loops.reduce(0.0) { $0 + $1.activeAreaSqm }

        // Für die erforderliche Vorlauftemperatur: q = K_H · ΔΘ_H ist linear
        // in ΔΘ_H, also ist auch die Summe aller Kreise linear. Deshalb genügt
        // die Summe (K_H · Fläche) – kein Iterieren über Temperaturen.
        let kTimesArea = loops.reduce(0.0) { $0 + $1.heatTransferCoefficient * $1.activeAreaSqm }
        var required: Double?
        if kTimesArea > 0, demandW > 0 {
            let overTemp = demandW / kTimesArea
            required = UnderfloorHeating.requiredFlowTemp(overTemp: overTemp,
                                                          spreadK: spread,
                                                          roomTemp: roomTemp)
        }

        // Strengste Oberflächengrenze aller Kreise des Raums gilt.
        let limit = loops.map { $0.maxSurfaceTemp }.min() ?? 29

        return UnderfloorCheckResult(activeAreaSqm: area,
                                     capacity: capacity,
                                     demand: demandW,
                                     roomTemp: roomTemp,
                                     maxSurfaceTemp: limit,
                                     requiredFlowTemp: required,
                                     loops: results)
    }
}
