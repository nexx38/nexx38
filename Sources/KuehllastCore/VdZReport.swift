import Foundation

/// Vor-Ort-Feststellungen für das VdZ-Formular „Bestätigung des Hydraulischen
/// Abgleichs u. a. für die BEG Förderung (Einzelmaßnahmen)", Fassung 2023/01/01.
///
/// Diese Angaben kann keine Software errechnen – sie stehen aber im Formular
/// bzw. in der nach VdZ-Fachregel Kap. 8 verlangten Dokumentation. Deshalb
/// werden sie hier erfasst und im Datenblatt ausgegeben, damit der Betrieb
/// beim Ausfüllen nichts vergisst.
public struct VdZInputs: Codable, Hashable, Sendable {
    /// Ausdehnungsgefäß geprüft (Ankreuzfeld im Formular).
    public var expansionVesselChecked: Bool
    /// Fülldruck der Anlage in bar (Formularfeld).
    public var fillPressureBar: Double
    /// Vordruck des Ausdehnungsgefäßes in bar (Fachregel Kap. 8).
    public var vesselPrePressureBar: Double
    /// Enddruck in bar (Fachregel Kap. 8).
    public var vesselEndPressureBar: Double
    /// Differenzdruckregler vorhanden (Ankreuzfeld je Heizkreis).
    public var differentialPressureController: Bool
    /// Durchflussregler bzw. Strangregulierventil vorhanden (Ankreuzfeld).
    public var flowController: Bool
    /// Tatsächlich eingestellte Leistung des Wärmeerzeugers in kW
    /// (Fachregel Kap. 8 verlangt sie ausdrücklich).
    public var generatorSetPowerKW: Double
    /// Eingestellte Heizkurve/Regelung als Freitext – die Anpassung der
    /// Heizkurve ist technische Mindestanforderung der BEG.
    public var heatingCurveNote: String
    /// Bemerkungen fürs Formular.
    public var remarks: String

    public init(expansionVesselChecked: Bool = false,
                fillPressureBar: Double = 0,
                vesselPrePressureBar: Double = 0,
                vesselEndPressureBar: Double = 0,
                differentialPressureController: Bool = false,
                flowController: Bool = false,
                generatorSetPowerKW: Double = 0,
                heatingCurveNote: String = "",
                remarks: String = "") {
        self.expansionVesselChecked = expansionVesselChecked
        self.fillPressureBar = fillPressureBar
        self.vesselPrePressureBar = vesselPrePressureBar
        self.vesselEndPressureBar = vesselEndPressureBar
        self.differentialPressureController = differentialPressureController
        self.flowController = flowController
        self.generatorSetPowerKW = generatorSetPowerKW
        self.heatingCurveNote = heatingCurveNote
        self.remarks = remarks
    }

    private enum CodingKeys: String, CodingKey {
        case expansionVesselChecked, fillPressureBar, vesselPrePressureBar
        case vesselEndPressureBar, differentialPressureController, flowController
        case generatorSetPowerKW, heatingCurveNote, remarks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.expansionVesselChecked = (try? c.decode(Bool.self, forKey: .expansionVesselChecked)) ?? false
        self.fillPressureBar        = (try? c.decode(Double.self, forKey: .fillPressureBar)) ?? 0
        self.vesselPrePressureBar   = (try? c.decode(Double.self, forKey: .vesselPrePressureBar)) ?? 0
        self.vesselEndPressureBar   = (try? c.decode(Double.self, forKey: .vesselEndPressureBar)) ?? 0
        self.differentialPressureController = (try? c.decode(Bool.self, forKey: .differentialPressureController)) ?? false
        self.flowController         = (try? c.decode(Bool.self, forKey: .flowController)) ?? false
        self.generatorSetPowerKW    = (try? c.decode(Double.self, forKey: .generatorSetPowerKW)) ?? 0
        self.heatingCurveNote       = (try? c.decode(String.self, forKey: .heatingCurveNote)) ?? ""
        self.remarks                = (try? c.decode(String.self, forKey: .remarks)) ?? ""
    }
}

/// Heizungsart eines Kreises – entspricht den Ankreuzfeldern im Formular.
public enum VdZSystemKind: String, Sendable {
    case zweirohr
    case fussboden
    case einrohr

    public var label: String {
        switch self {
        case .zweirohr:  return "Zweirohrheizung"
        case .fussboden: return "Fußbodenheizung"
        case .einrohr:   return "Einrohrheizung"
        }
    }
}

/// Eine Heizkreis-Zeile des Formulars (es fasst maximal drei).
public struct VdZCircuit: Sendable, Identifiable {
    public var id: String { kind.rawValue }
    public var kind: VdZSystemKind
    /// Auslegungsvorlauftemperatur [°C].
    public var flowTemp: Double
    /// Heizkreisrücklauftemperatur [°C].
    public var returnTemp: Double
    /// Ermittelter Gesamtdurchfluss [l/h] – Summe der Heizflächen des Kreises.
    public var totalFlowLPerH: Double
    /// Ermittelte Pumpenförderhöhe bei diesem Durchfluss [m].
    public var pumpHeadM: Double
    /// Anzahl der Heizflächen im Kreis (für die Anlage).
    public var surfaceCount: Int
    /// Wärmeleistung des Kreises [W].
    public var loadW: Double
}

/// Eine Zeile der Anlage: eine Heizfläche mit ihren Abgleichwerten.
public struct VdZSurfaceRow: Sendable, Identifiable {
    public var id = UUID()
    public var roomName: String
    public var storeyLabel: String
    /// Bezeichnung der Heizfläche („Typ 22, 100 × 60 cm" bzw. „HK 1, VA 15").
    public var surfaceLabel: String
    public var kind: VdZSystemKind
    /// Anteilige Heizlast der Fläche [W].
    public var loadW: Double
    /// Auslegungs-Volumenstrom [l/h].
    public var flowLPerH: Double
    /// Ventilbezeichnung, falls gewählt.
    public var valveName: String?
    /// Voreinstellwert.
    public var valveSetting: String?
    /// Differenzdruck am Ventil [mbar] – Fachregel Kap. 8 verlangt ihn.
    public var valveDpMbar: Double?

    public init(roomName: String, storeyLabel: String, surfaceLabel: String,
                kind: VdZSystemKind, loadW: Double, flowLPerH: Double,
                valveName: String? = nil, valveSetting: String? = nil,
                valveDpMbar: Double? = nil) {
        self.roomName = roomName
        self.storeyLabel = storeyLabel
        self.surfaceLabel = surfaceLabel
        self.kind = kind
        self.loadW = loadW
        self.flowLPerH = flowLPerH
        self.valveName = valveName
        self.valveSetting = valveSetting
        self.valveDpMbar = valveDpMbar
    }
}

/// Eine Raumzeile der raumweisen Heizlast (Pflichtanlage bei Verfahren B).
public struct VdZRoomRow: Sendable, Identifiable {
    public var id = UUID()
    public var name: String
    public var storeyLabel: String
    public var areaSqm: Double
    public var indoorTemp: Double
    public var loadW: Double
    public var specificW: Double
}

/// Fertig aufbereitete Unterlage: Formularwerte + Anlage.
public struct VdZReport: Sendable {
    public var circuits: [VdZCircuit]
    public var rooms: [VdZRoomRow]
    public var surfaces: [VdZSurfaceRow]
    public var totalLoadW: Double
    /// Räume ohne erfasste Heizfläche – die fehlen in der Anlage und fallen
    /// beim Prüfen auf. Lieber vorher melden als hinterher nachliefern.
    public var roomsWithoutSurface: [String]
    /// Hinweise zu Grenzen und Pflichten (gehören sichtbar aufs Papier).
    public var hints: [String]
}

public enum VdZReportBuilder {

    /// Geschossbezeichnung für die Anlage.
    public static func storeyLabel(_ storey: Int?) -> String {
        guard let storey else { return "" }
        switch storey {
        case ..<0: return "KG"
        case 0:    return "EG"
        case 4:    return "DG"
        default:   return "\(storey). OG"
        }
    }

    /// Baut die Unterlage aus Räumen und Anlagen-Einstellungen.
    ///
    /// Aufteilung in Heizkreise: Heizkörper bilden Kreis 1 (Zweirohr),
    /// Fußbodenheizung Kreis 2 – genau die Trennung, die das Formular mit
    /// seinen Ankreuzfeldern vorsieht. Versorgt eine Pumpe beide, ist sie
    /// laut Fußnote dem ersten Kreis zuzuordnen.
    public static func build(rooms: [Room], settings: BuildingSettings) -> VdZReport {
        let calculator = HeatingLoadCalculator()
        var roomRows: [VdZRoomRow] = []
        var surfaceRows: [VdZSurfaceRow] = []
        var withoutSurface: [String] = []

        var radiatorLoad = 0.0
        var radiatorFlow = 0.0
        var radiatorCount = 0
        var underfloorLoad = 0.0
        var underfloorFlow = 0.0
        var underfloorCount = 0

        let valve = settings.valveModelID.flatMap { ValveDatabase.model(id: $0) }

        for room in rooms {
            let result = calculator.calculate(room)
            let storey = storeyLabel(room.storey)
            roomRows.append(VdZRoomRow(name: room.name,
                                       storeyLabel: storey,
                                       areaSqm: room.floorArea,
                                       indoorTemp: room.heating?.indoorTemperature ?? 20,
                                       loadW: result.total,
                                       specificW: result.specific(for: room.floorArea)))

            let radiators = room.radiators ?? []
            let loops = room.underfloorLoops ?? []
            if radiators.isEmpty && loops.isEmpty {
                withoutSurface.append(room.name)
                continue
            }

            // Raumlast anteilig nach Normleistung auf die Heizkörper verteilen –
            // derselbe Ansatz wie im Abgleich-Bildschirm, damit die Zahlen
            // an beiden Stellen übereinstimmen.
            let normTotal = radiators.reduce(0.0) { $0 + $1.normPower }
            for (index, radiator) in radiators.enumerated() {
                let share = normTotal > 0 ? radiator.normPower / normTotal : 0
                let load = result.total * share
                let flow = HydraulicBalancing.preset(loadW: load, spreadK: settings.spreadK).flowKgPerH
                var valveName: String?
                var setting: String?
                if let valve {
                    let selection = valve.setting(forKv: ValveDatabase.kvNeeded(flowKgPerH: flow))
                    valveName = valve.displayName
                    setting = selection.settingLabel
                }
                surfaceRows.append(VdZSurfaceRow(
                    roomName: room.name,
                    storeyLabel: storey,
                    surfaceLabel: String(format: "HK %d · %@ · %.0f × %.0f cm",
                                         index + 1, radiator.type.label,
                                         radiator.widthM * 100, radiator.heightM * 100),
                    kind: .zweirohr,
                    loadW: load,
                    flowLPerH: flow,
                    valveName: valveName,
                    valveSetting: setting,
                    valveDpMbar: valve != nil ? settings.pump.valveDpMbar : nil))
                radiatorLoad += load
                radiatorFlow += flow
                radiatorCount += 1
            }

            if !loops.isEmpty {
                let check = UnderfloorHeating.check(loops: loops,
                                                    demandW: result.total,
                                                    roomTemp: room.heating?.indoorTemperature ?? 20,
                                                    flowTemp: settings.underfloorFlowTemp,
                                                    spreadK: settings.spreadK)
                for loop in check.loops {
                    surfaceRows.append(VdZSurfaceRow(
                        roomName: room.name,
                        storeyLabel: storey,
                        surfaceLabel: String(format: "%@ · %.0f m² · %.0f m Rohr",
                                             loop.name, loop.areaSqm, loop.pipeLengthM),
                        kind: .fussboden,
                        loadW: loop.outputW,
                        flowLPerH: loop.flowKgPerH))
                    underfloorLoad += loop.outputW
                    underfloorFlow += loop.flowKgPerH
                    underfloorCount += 1
                }
            }
        }

        let totalLoad = roomRows.reduce(0.0) { $0 + $1.loadW }

        var circuits: [VdZCircuit] = []
        if radiatorCount > 0 {
            let pump = PumpSizing.calculate(input: settings.pump,
                                            totalLoadW: radiatorLoad,
                                            spreadK: settings.spreadK)
            circuits.append(VdZCircuit(kind: .zweirohr,
                                       flowTemp: settings.flowTemp,
                                       returnTemp: settings.returnTemp,
                                       totalFlowLPerH: radiatorFlow,
                                       pumpHeadM: pump.headM,
                                       surfaceCount: radiatorCount,
                                       loadW: radiatorLoad))
        }
        if underfloorCount > 0 {
            let pump = PumpSizing.calculate(input: settings.pump,
                                            totalLoadW: underfloorLoad,
                                            spreadK: settings.spreadK)
            circuits.append(VdZCircuit(kind: .fussboden,
                                       flowTemp: settings.underfloorFlowTemp,
                                       returnTemp: settings.underfloorReturnTemp,
                                       totalFlowLPerH: underfloorFlow,
                                       pumpHeadM: pump.headM,
                                       surfaceCount: underfloorCount,
                                       loadW: underfloorLoad))
        }

        var hints: [String] = []
        if !withoutSurface.isEmpty {
            hints.append("Ohne Heizfläche erfasst: " + withoutSurface.joined(separator: ", ")
                         + ". Diese Räume fehlen in der Abgleich-Anlage.")
        }
        if valve == nil {
            hints.append("Kein Ventilfabrikat gewählt – ohne Voreinstellwerte ist die Anlage "
                         + "für Verfahren B unvollständig.")
        }
        if settings.vdz.fillPressureBar <= 0 || !settings.vdz.expansionVesselChecked {
            hints.append("Ausdehnungsgefäß und Fülldruck sind Formularpflicht und noch nicht erfasst.")
        }
        if settings.vdz.generatorSetPowerKW <= 0 {
            hints.append("Eingestellte Leistung des Wärmeerzeugers fehlt (VdZ-Fachregel Kap. 8).")
        }
        if settings.vdz.heatingCurveNote.isEmpty {
            hints.append("Einstellung der Regelung/Heizkurve fehlt – Anpassung der Heizkurve ist "
                         + "technische Mindestanforderung der BEG.")
        }
        if circuits.count > 3 {
            hints.append("Das VdZ-Formular fasst nur drei Heizkreise.")
        }

        return VdZReport(circuits: circuits,
                         rooms: roomRows,
                         surfaces: surfaceRows,
                         totalLoadW: totalLoad,
                         roomsWithoutSurface: withoutSurface,
                         hints: hints)
    }
}
