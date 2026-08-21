import Foundation

// MARK: - Ventil-Datenbank für den hydraulischen Abgleich
//
// Diese Datei liefert die kv-Werte je Voreinstellstufe echter Thermostat-
// Ventilunterteile. Damit wird aus dem generischen Abgleich (siehe
// `HydraulicBalancing` in SystemSizing.swift) eine Einstellung, die der
// Monteur so am Ventil drehen kann.
//
// GRUNDLAGE DER ZAHLEN
// Alle Hersteller-Tabellen sind aus den jeweiligen Datenblättern übernommen –
// jeweils die Spalte für **2 K Regeldifferenz** (P-Band / xp / P-Abweichung).
// Das ist der Auslegungsfall nach DIN EN 215 und der Wert, mit dem
// Abgleich-Programme rechnen. Die kv-Werte bei 1 K liegen niedriger, die
// kvs-Werte (Ventil voll offen) höher; beide sind für den Abgleich nicht
// maßgebend und deshalb hier nur als `kvs` bzw. im Kommentar hinterlegt.
//
// Quellen je Hersteller stehen als Kommentar direkt über der jeweiligen
// Tabelle und zusätzlich maschinenlesbar im Feld `source` jedes Modells.
//
// WO KEINE BELASTBAREN WERTE VORLIEGEN, STEHEN HIER KEINE ZAHLEN.
// Modelle mit abgeleiteten Werten sind über `quality == .naeherung`
// gekennzeichnet (derzeit nur der Rückfall „Fabrikat unbekannt").

// MARK: - Hersteller

/// Hersteller von Thermostat-Ventilunterteilen mit Voreinstellung.
/// `generic` ist der Rückfall, wenn das Fabrikat vor Ort nicht bekannt ist.
public enum ValveManufacturer: String, Codable, CaseIterable, Sendable {
    case heimeier
    case oventrop
    case danfoss
    case resideo
    case taconova
    case generic

    public var label: String {
        switch self {
        case .heimeier: return "IMI Heimeier"
        case .oventrop: return "Oventrop"
        case .danfoss:  return "Danfoss"
        case .resideo:  return "Resideo (Honeywell Home)"
        case .taconova: return "Taconova"
        case .generic:  return "Fabrikat unbekannt"
        }
    }
}

// MARK: - Datenherkunft

/// Woher die kv-Werte eines Modells stammen. Der Monteur muss sehen können,
/// ob er eine echte Herstellertabelle oder einen Schätzwert vor sich hat.
public enum ValveDataQuality: String, Codable, CaseIterable, Sendable {
    /// Aus dem Herstellerdatenblatt übernommen.
    case herstellerangabe
    /// Abgeleiteter Anhaltswert – Herstellertabelle bleibt maßgebend.
    case naeherung

    public var label: String {
        switch self {
        case .herstellerangabe: return "Herstellerangabe"
        case .naeherung:        return "Näherung"
        }
    }

    /// true = die Zahlen sind belegt.
    public var isVerified: Bool { self == .herstellerangabe }
}

// MARK: - Nennweite

/// Nennweite des Ventilunterteils. Am Ventil steht meist die zöllige
/// Anschlussbezeichnung, im Datenblatt die DN-Angabe – deshalb beides.
public enum ValveSize: String, Codable, CaseIterable, Sendable {
    case dn10
    case dn15
    case dn20

    /// Nennweite als Zahl (10 / 15 / 20).
    public var dn: Int {
        switch self {
        case .dn10: return 10
        case .dn15: return 15
        case .dn20: return 20
        }
    }

    /// Anschlussgewinde, wie es der Monteur am Ventil abliest.
    public var inchLabel: String {
        switch self {
        case .dn10: return "3/8\""
        case .dn15: return "1/2\""
        case .dn20: return "3/4\""
        }
    }

    public var label: String { "DN \(dn) (\(inchLabel))" }
}

// MARK: - Voreinstellstufe

/// Eine Voreinstellstufe des Ventils mit ihrem kv-Wert.
public struct ValveSetting: Codable, Hashable, Sendable {
    /// Beschriftung am Einstellring, z. B. "1" … "8".
    public var label: String
    /// kv-Wert dieser Stufe in m³/h (Durchfluss bei 1 bar Druckverlust).
    public var kv: Double

    public init(label: String, kv: Double) {
        self.label = label
        self.kv = kv
    }
}

// MARK: - Ventilmodell

/// Ein konkretes Ventilunterteil eines Herstellers in einer Nennweite,
/// samt kv-Tabelle über alle Voreinstellstufen.
public struct ValveModel: Codable, Hashable, Identifiable, Sendable {
    public var manufacturer: ValveManufacturer
    /// Modellname wie im Katalog, z. B. "V-exact II".
    public var name: String
    public var size: ValveSize
    /// kv-Werte je Voreinstellstufe, **aufsteigend sortiert**.
    public var settings: [ValveSetting]
    /// kvs-Wert (Ventil voll offen) in m³/h; nil = nicht angegeben.
    public var kvs: Double?
    /// Regeldifferenz (P-Band / xp) in K, auf die sich die kv-Werte beziehen.
    /// Nach DIN EN 215 ist 2 K der Auslegungsfall.
    public var controlDeviationK: Double
    /// Herstellerangabe oder Näherung.
    public var quality: ValveDataQuality
    /// Fundstelle der Zahlen (Datenblatt-Nummer bzw. Katalog).
    public var source: String
    /// Zusatzhinweis für den Monteur (Bauform-Abhängigkeiten, Werkseinstellung).
    public var note: String?

    public init(manufacturer: ValveManufacturer,
                name: String,
                size: ValveSize,
                settings: [ValveSetting],
                kvs: Double? = nil,
                controlDeviationK: Double = 2.0,
                quality: ValveDataQuality = .herstellerangabe,
                source: String,
                note: String? = nil) {
        self.manufacturer = manufacturer
        self.name = name
        self.size = size
        self.settings = settings
        self.kvs = kvs
        self.controlDeviationK = controlDeviationK
        self.quality = quality
        self.source = source
        self.note = note
    }

    /// Stabile Kennung zum Speichern in der Heizkörper-/Raumakte.
    public var id: String { "\(manufacturer.rawValue)-\(name)-\(size.rawValue)" }

    /// Anzeigename für die Auswahlliste.
    public var displayName: String { "\(manufacturer.label) \(name), \(size.label)" }

    /// Kleinster einstellbarer kv-Wert (unterste Stufe).
    public var minKv: Double { settings.first?.kv ?? 0 }

    /// Größter einstellbarer kv-Wert (oberste Stufe).
    public var maxKv: Double { settings.last?.kv ?? 0 }

    /// Prüft, ob die kv-Werte streng monoton mit der Stufe steigen.
    /// Fängt Tippfehler und vertauschte Zeilen in den Tabellen ab.
    public var hasStrictlyIncreasingKv: Bool {
        guard settings.count > 1 else { return settings.count == 1 }
        for i in 1..<settings.count where settings[i].kv <= settings[i - 1].kv {
            return false
        }
        return true
    }

    /// Passende Voreinstellung für einen erforderlichen kv-Wert:
    /// die **kleinste** Stufe, deren kv den Bedarf deckt.
    ///
    /// Randfälle:
    /// - Bedarf unter der kleinsten Stufe → kleinste Stufe + Hinweis.
    /// - Bedarf über der größten Stufe → keine Stufe, Hinweis „Ventil zu klein".
    public func setting(forKv kvNeeded: Double) -> ValveSelectionResult {
        let need = max(kvNeeded, 0)
        let tol = ValveDatabase.kvTolerance

        guard let smallest = settings.first else {
            return ValveSelectionResult(
                model: self, kvNeeded: need, setting: nil, status: .ueberMaximum,
                hint: "Für dieses Ventil sind keine kv-Werte hinterlegt.")
        }

        // Bedarf liegt unter der kleinsten Stufe: kleinste Stufe einstellen.
        // Der Heizkörper bekommt dann etwas mehr Wasser als gerechnet.
        if need < smallest.kv - tol {
            return ValveSelectionResult(
                model: self, kvNeeded: need, setting: smallest, status: .unterMinimum,
                hint: "Erforderlicher kv-Wert (\(ValveDatabase.kvLabel(need))) liegt unter "
                    + "der kleinsten Stufe (\(ValveDatabase.kvLabel(smallest.kv))). "
                    + "Kleinste Voreinstellung wählen; der Heizkörper wird etwas "
                    + "überströmt.")
        }

        // Regelfall: kleinste Stufe, deren kv den Bedarf deckt.
        // Die Toleranz sorgt dafür, dass ein Bedarf, der rechnerisch exakt auf
        // einem Tabellenwert landet, auch genau diese Stufe trifft.
        if let hit = settings.first(where: { $0.kv + tol >= need }) {
            return ValveSelectionResult(model: self, kvNeeded: need, setting: hit,
                                        status: .passend, hint: nil)
        }

        return ValveSelectionResult(
            model: self, kvNeeded: need, setting: nil, status: .ueberMaximum,
            hint: "Ventil zu klein: erforderlicher kv-Wert "
                + "(\(ValveDatabase.kvLabel(need))) liegt über der größten Stufe "
                + "(\(ValveDatabase.kvLabel(maxKv))). Größere Nennweite wählen "
                + "oder Spreizung erhöhen.")
    }
}

// MARK: - Ergebnis der Ventilauswahl

/// Wie die Auswahl ausgegangen ist.
public enum ValveSelectionStatus: String, Codable, Sendable {
    /// Eine Stufe deckt den Bedarf.
    case passend
    /// Bedarf unter der kleinsten Stufe – kleinste Stufe wird empfohlen.
    case unterMinimum
    /// Bedarf über der größten Stufe – Ventil reicht nicht.
    case ueberMaximum
}

/// Ergebnis der Ventilauswahl für einen Heizkörper.
public struct ValveSelectionResult: Hashable, Sendable {
    public var model: ValveModel
    /// Erforderlicher kv-Wert in m³/h.
    public var kvNeeded: Double
    /// Empfohlene Stufe; nil, wenn das Ventil zu klein ist.
    public var setting: ValveSetting?
    public var status: ValveSelectionStatus
    /// Klartext-Hinweis für den Monteur; nil im Regelfall.
    public var hint: String?

    public init(model: ValveModel,
                kvNeeded: Double,
                setting: ValveSetting?,
                status: ValveSelectionStatus,
                hint: String?) {
        self.model = model
        self.kvNeeded = kvNeeded
        self.setting = setting
        self.status = status
        self.hint = hint
    }

    /// true, wenn eine Stufe eingestellt werden kann.
    public var isUsable: Bool { setting != nil }

    /// Beschriftung für die Anzeige, z. B. "Stufe 4".
    public var settingLabel: String {
        guard let setting = setting else { return "Ventil zu klein" }
        return "Stufe \(setting.label)"
    }
}

// MARK: - Datenbank

public enum ValveDatabase {

    /// Rundungstoleranz beim kv-Vergleich. Verhindert, dass ein Bedarf, der
    /// rechnerisch genau auf einem Tabellenwert liegt, wegen der
    /// Fließkomma-Darstellung eine Stufe zu hoch landet.
    public static let kvTolerance: Double = 1e-9

    /// Angenommener Differenzdruck am Thermostatventil in mbar
    /// (Verfahren B; gleicher Wert wie `HydraulicBalancing.valveDpMbar`).
    public static let defaultValveDpMbar: Double = 100

    // MARK: - Umrechnungen

    /// Massenstrom eines Heizkörpers in kg/h.
    /// m = Q · 0,86 / ΔT   (0,86 = 1 / 1,163 Wh/(kg·K))
    ///
    /// Die Spreizung wird wie in `HydraulicBalancing.preset` bei 3 K
    /// abgefangen – darunter ist der Wert physikalisch nicht sinnvoll und
    /// beide Rechenwege müssen dasselbe Ergebnis liefern.
    public static func flowKgPerH(loadW: Double, spreadK: Double) -> Double {
        let spread = max(spreadK, 3)
        return max(loadW, 0) * 0.86 / spread
    }

    /// Erforderlicher kv-Wert in m³/h.
    /// kv = V [m³/h] / √(Δp [bar]);  1000 kg/h ≙ 1 m³/h,  1000 mbar ≙ 1 bar.
    public static func kvNeeded(flowKgPerH: Double,
                                valveDpMbar: Double = ValveDatabase.defaultValveDpMbar) -> Double {
        let dpBar = max(valveDpMbar, 1) / 1000.0
        return (max(flowKgPerH, 0) / 1000.0) / sqrt(dpBar)
    }

    /// Erforderlicher kv-Wert direkt aus Heizlast und Spreizung.
    public static func kvNeeded(loadW: Double,
                                spreadK: Double,
                                valveDpMbar: Double = ValveDatabase.defaultValveDpMbar) -> Double {
        kvNeeded(flowKgPerH: flowKgPerH(loadW: loadW, spreadK: spreadK),
                 valveDpMbar: valveDpMbar)
    }

    /// Komplettweg: Heizlast → Volumenstrom → kv → Voreinstellung.
    public static func recommend(model: ValveModel,
                                 loadW: Double,
                                 spreadK: Double,
                                 valveDpMbar: Double = ValveDatabase.defaultValveDpMbar) -> ValveSelectionResult {
        model.setting(forKv: kvNeeded(loadW: loadW, spreadK: spreadK,
                                      valveDpMbar: valveDpMbar))
    }

    /// kv-Wert als deutscher Text, z. B. "0,218".
    public static func kvLabel(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        return String(rounded).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - IMI Heimeier
    //
    // Quelle: IMI Heimeier, Datenblatt/Prospekt „V-exact II" (Thermostat-
    // Ventilunterteile mit stufenloser Präzisions-Voreinstellung).
    // Die kv-Tabelle gilt laut Datenblatt gemeinsam für DN 10/15/20
    // („Ventilunterteil (DN 10/15/20) Voreinstellung"), weil in allen drei
    // Nennweiten derselbe Ventileinsatz sitzt.
    //
    // Voreinstellung                1      2      3      4      5      6      7      8
    // Kv bei xp = 1,0 K          0,049  0,082  0,130  0,215  0,246  0,303  0,335  0,343
    // Kv bei xp = 2,0 K          0,049  0,090  0,150  0,265  0,330  0,470  0,590  0,670   ← verwendet
    // Kvs                        0,049  0,102  0,185  0,313  0,420  0,565  0,740  0,860
    //
    // Gegenprobe aus derselben Unterlage (Maßtabelle je Nennweite):
    // „Kv [xp] max. 2 K = 0,025 – 0,670" und „Kvs = 0,86" für DN 10, 15 und 20.

    public static let heimeierVExactIISettings: [ValveSetting] = [
        ValveSetting(label: "1", kv: 0.049),
        ValveSetting(label: "2", kv: 0.090),
        ValveSetting(label: "3", kv: 0.150),
        ValveSetting(label: "4", kv: 0.265),
        ValveSetting(label: "5", kv: 0.330),
        ValveSetting(label: "6", kv: 0.470),
        ValveSetting(label: "7", kv: 0.590),
        ValveSetting(label: "8", kv: 0.670)
    ]

    public static let heimeierModels: [ValveModel] =
        ValveSize.allCases.map { (size: ValveSize) -> ValveModel in
        ValveModel(
            manufacturer: .heimeier,
            name: "V-exact II",
            size: size,
            settings: ValveDatabase.heimeierVExactIISettings,
            kvs: 0.86,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: "IMI Heimeier, Datenblatt V-exact II – Kv bei xp max. 2 K, Kvs 0,86",
            note: "Voreinstellung stufenlos zwischen 1 und 8, Einstellung mit dem "
                + "Voreinstellschlüssel. Werkseinstellung ist 8 (voller Durchfluss). "
                + "Dieselbe Kennlinie gilt laut Datenblatt für DN 10, DN 15 und DN 20.")
    }

    // MARK: - Danfoss
    //
    // Quelle: Danfoss, Datenblatt „Voreinstellbare Ventilgehäuse Typ RA-N für
    // Pumpenwarmwasseranlagen" (Dok. AI147386403838de). Verwendet ist die
    // Zeile Xp = 2 (kv-Werte mit RA-2000-Fühler, m³/h).
    //
    //            1     2     3     4     5     6     7    | N     kvs
    // RA-N 10  0,04  0,09  0,16  0,25  0,32  0,38  0,42   | 0,56  0,65
    // RA-N 15  0,04  0,09  0,16  0,25  0,36  0,43  0,52   | 0,73  0,90
    // RA-N 20  0,10  0,16  0,24  0,33  0,44  0,56  0,73   | 1,04  1,40
    //
    // Die Stellung „N" ist bewusst NICHT als Abgleichstufe hinterlegt: bei N
    // ist die Voreinstellung aufgehoben (Spülstellung). Wer N einstellt,
    // gleicht nicht ab. Die kv-Werte von N stehen oben nur zur Information.
    // Zwischen 1 und 7 lässt sich in 0,5-Schritten einstellen.

    public static let danfossRaN10Settings: [ValveSetting] = [
        ValveSetting(label: "1", kv: 0.04),
        ValveSetting(label: "2", kv: 0.09),
        ValveSetting(label: "3", kv: 0.16),
        ValveSetting(label: "4", kv: 0.25),
        ValveSetting(label: "5", kv: 0.32),
        ValveSetting(label: "6", kv: 0.38),
        ValveSetting(label: "7", kv: 0.42)
    ]

    public static let danfossRaN15Settings: [ValveSetting] = [
        ValveSetting(label: "1", kv: 0.04),
        ValveSetting(label: "2", kv: 0.09),
        ValveSetting(label: "3", kv: 0.16),
        ValveSetting(label: "4", kv: 0.25),
        ValveSetting(label: "5", kv: 0.36),
        ValveSetting(label: "6", kv: 0.43),
        ValveSetting(label: "7", kv: 0.52)
    ]

    public static let danfossRaN20Settings: [ValveSetting] = [
        ValveSetting(label: "1", kv: 0.10),
        ValveSetting(label: "2", kv: 0.16),
        ValveSetting(label: "3", kv: 0.24),
        ValveSetting(label: "4", kv: 0.33),
        ValveSetting(label: "5", kv: 0.44),
        ValveSetting(label: "6", kv: 0.56),
        ValveSetting(label: "7", kv: 0.73)
    ]

    private static let danfossSource =
        "Danfoss, Datenblatt RA-N (AI147386403838de) – kv bei Xp = 2 K"

    public static let danfossModels: [ValveModel] = [
        ValveModel(
            manufacturer: .danfoss,
            name: "RA-N",
            size: .dn10,
            settings: ValveDatabase.danfossRaN10Settings,
            kvs: 0.65,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: ValveDatabase.danfossSource,
            note: "Einstellring in 0,5-Schritten zwischen 1 und 7. Stellung N hebt "
                + "die Voreinstellung auf (Spülstellung, kv 0,56) und ist zum "
                + "Abgleichen nicht zu verwenden."),
        ValveModel(
            manufacturer: .danfoss,
            name: "RA-N",
            size: .dn15,
            settings: ValveDatabase.danfossRaN15Settings,
            kvs: 0.90,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: ValveDatabase.danfossSource,
            note: "Einstellring in 0,5-Schritten zwischen 1 und 7. Stellung N hebt "
                + "die Voreinstellung auf (Spülstellung, kv 0,73) und ist zum "
                + "Abgleichen nicht zu verwenden. Gilt auch für RA-NCX 15."),
        ValveModel(
            manufacturer: .danfoss,
            name: "RA-N",
            size: .dn20,
            settings: ValveDatabase.danfossRaN20Settings,
            kvs: 1.40,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: ValveDatabase.danfossSource,
            note: "Einstellring in 0,5-Schritten zwischen 1 und 7. Stellung N hebt "
                + "die Voreinstellung auf (Spülstellung, kv 1,04) und ist zum "
                + "Abgleichen nicht zu verwenden.")
    ]

    // MARK: - Oventrop
    //
    // Quelle: Oventrop, Datenblatt „Thermostatventile" (Ausgabe 2017),
    // Abschnitt „Leistungsdaten: alle Ausführungen und NW".
    //
    // „AV 9" (Diagramme 5), kv-Wert bei 2 K P-Abweichung:
    //   1     2     3     4     5     6     7     8     9
    // 0,05  0,09  0,14  0,20  0,26  0,32  0,43  0,57  0,67
    // Gegenprobe aus der kv/Zeta-Tabelle desselben Datenblatts:
    // „AV 9/RFV 9/CV 9, kv bei 2 K = 0,67" für alle Nennweiten. ✓
    //
    // „AF" (Diagramme 6), kv-Wert bei 2 K P-Abweichung:
    //   1      2      3      4      5      6
    // 0,025  0,051  0,095  0,152  0,228  0,323
    // Gegenprobe aus der kv/Zeta-Tabelle: „AF, kv bei 2 K = 0,32", kvs 0,37. ✓
    //
    // Für „AV 6" liegt im Datenblatt nur ein Druckverlust-Diagramm vor,
    // keine Zahlentabelle je Voreinstellung – deshalb bewusst NICHT aufgenommen
    // (lieber kein Modell als geratene Werte).

    public static let oventropAV9Settings: [ValveSetting] = [
        ValveSetting(label: "1", kv: 0.05),
        ValveSetting(label: "2", kv: 0.09),
        ValveSetting(label: "3", kv: 0.14),
        ValveSetting(label: "4", kv: 0.20),
        ValveSetting(label: "5", kv: 0.26),
        ValveSetting(label: "6", kv: 0.32),
        ValveSetting(label: "7", kv: 0.43),
        ValveSetting(label: "8", kv: 0.57),
        ValveSetting(label: "9", kv: 0.67)
    ]

    public static let oventropAFSettings: [ValveSetting] = [
        ValveSetting(label: "1", kv: 0.025),
        ValveSetting(label: "2", kv: 0.051),
        ValveSetting(label: "3", kv: 0.095),
        ValveSetting(label: "4", kv: 0.152),
        ValveSetting(label: "5", kv: 0.228),
        ValveSetting(label: "6", kv: 0.323)
    ]

    public static let oventropAV9Models: [ValveModel] = [
        ValveModel(
            manufacturer: .oventrop,
            name: "AV 9",
            size: .dn10,
            settings: ValveDatabase.oventropAV9Settings,
            kvs: 1.10,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: "Oventrop, Datenblatt Thermostatventile 2017, Diagramme 5 – "
                + "kv bei 2 K P-Abweichung",
            note: "Stufenlose Voreinstellung 1–9; gleiche Kennlinie für AV 9, RFV 9 "
                + "und CV 9 in allen Nennweiten. kvs gilt für das Eckventil, "
                + "Durchgangsventil DN 10 = 0,90."),
        ValveModel(
            manufacturer: .oventrop,
            name: "AV 9",
            size: .dn15,
            settings: ValveDatabase.oventropAV9Settings,
            kvs: 1.20,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: "Oventrop, Datenblatt Thermostatventile 2017, Diagramme 5 – "
                + "kv bei 2 K P-Abweichung",
            note: "Stufenlose Voreinstellung 1–9; gleiche Kennlinie für AV 9, RFV 9 "
                + "und CV 9 in allen Nennweiten. kvs gilt für das Eckventil, "
                + "Durchgangsventil DN 15 = 1,00."),
        ValveModel(
            manufacturer: .oventrop,
            name: "AV 9",
            size: .dn20,
            settings: ValveDatabase.oventropAV9Settings,
            kvs: 1.30,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: "Oventrop, Datenblatt Thermostatventile 2017, Diagramme 5 – "
                + "kv bei 2 K P-Abweichung",
            note: "Stufenlose Voreinstellung 1–9; gleiche Kennlinie für AV 9, RFV 9 "
                + "und CV 9 in allen Nennweiten. kvs gilt für das Eckventil, "
                + "Durchgangsventil DN 20 = 1,20.")
    ]

    public static let oventropAFModels: [ValveModel] =
        ValveSize.allCases.map { (size: ValveSize) -> ValveModel in
        ValveModel(
            manufacturer: .oventrop,
            name: "AF",
            size: size,
            settings: ValveDatabase.oventropAFSettings,
            kvs: 0.37,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: "Oventrop, Datenblatt Thermostatventile 2017, Diagramme 6 – "
                + "kv bei 2 K P-Abweichung",
            note: "Stufenlose Feinstvoreinstellung 1–6 für kleine Volumenströme "
                + "(Niedertemperatur- und Wärmepumpenanlagen). Gleiche Kennlinie "
                + "für alle Ausführungen und Nennweiten.")
    }

    /// Alle Oventrop-Modelle (AV 9 und AF).
    public static let oventropModels: [ValveModel] =
        ValveDatabase.oventropAV9Models + ValveDatabase.oventropAFModels

    // MARK: - Resideo (Honeywell Home)
    //
    // Quelle: Resideo, Produkt-Datenblätter „Thermostatventil SX" (V2000SX,
    // GE0H-2112GE23) und „Thermostatventil FX" (V2000FX, GE0H-2113GE23),
    // Abschnitt „Durchflussrate", Zeile „kv-Wert, 2K p-Band".
    //
    // V2000SX – Winkelventile sowie DN 15/DN 20 Durchgang:
    //   1      2      3     4     5     6
    // 0,063  0,095  0,16  0,28  0,43  0,54   (kvs 0,70)
    //
    // V2000SX – Axial-/Winkel-Eck-Ventile und DN 10 Durchgang:
    // 0,063  0,095  0,16  0,28  0,43  0,51   (kvs 0,62)
    //
    // V2000FX (kleine Durchflüsse, DN 10 + DN 15):
    //   1      2      3      4      5      6
    // 0,032  0,054  0,085  0,135  0,185  0,220  (kvs 0,285)
    //
    // Hinweis zur Abgrenzung: Der ebenfalls von Resideo beworbene „Kombi-TRV"
    // ist ein druckunabhängiges Ventil. Seine Skala 1–8 stellt direkt einen
    // Volumenstrom (10–160 l/h) ein, KEINEN kv-Wert. Er passt deshalb nicht in
    // dieses kv-Schema und ist hier bewusst nicht enthalten.

    public static let resideoV2000SXStandardSettings: [ValveSetting] = [
        ValveSetting(label: "1", kv: 0.063),
        ValveSetting(label: "2", kv: 0.095),
        ValveSetting(label: "3", kv: 0.16),
        ValveSetting(label: "4", kv: 0.28),
        ValveSetting(label: "5", kv: 0.43),
        ValveSetting(label: "6", kv: 0.54)
    ]

    public static let resideoV2000SXAxialSettings: [ValveSetting] = [
        ValveSetting(label: "1", kv: 0.063),
        ValveSetting(label: "2", kv: 0.095),
        ValveSetting(label: "3", kv: 0.16),
        ValveSetting(label: "4", kv: 0.28),
        ValveSetting(label: "5", kv: 0.43),
        ValveSetting(label: "6", kv: 0.51)
    ]

    public static let resideoV2000FXSettings: [ValveSetting] = [
        ValveSetting(label: "1", kv: 0.032),
        ValveSetting(label: "2", kv: 0.054),
        ValveSetting(label: "3", kv: 0.085),
        ValveSetting(label: "4", kv: 0.135),
        ValveSetting(label: "5", kv: 0.185),
        ValveSetting(label: "6", kv: 0.220)
    ]

    private static let resideoSXSource =
        "Resideo, Produkt-Datenblatt V2000SX (GE0H-2112GE23) – kv-Wert bei 2 K p-Band"

    private static let resideoFXSource =
        "Resideo, Produkt-Datenblatt V2000FX (GE0H-2113GE23) – kv-Wert bei 2 K p-Band"

    public static let resideoModels: [ValveModel] = [
        ValveModel(
            manufacturer: .resideo,
            name: "V2000SX",
            size: .dn10,
            settings: ValveDatabase.resideoV2000SXAxialSettings,
            kvs: 0.62,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: ValveDatabase.resideoSXSource,
            note: "Werte für Axial- und Winkel-Eck-Ventile sowie DN 10 Durchgang. "
                + "Werkseinstellung ist Stufe 6, Zwischenstellungen sind laut "
                + "Hersteller nicht zulässig."),
        ValveModel(
            manufacturer: .resideo,
            name: "V2000SX",
            size: .dn15,
            settings: ValveDatabase.resideoV2000SXStandardSettings,
            kvs: 0.70,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: ValveDatabase.resideoSXSource,
            note: "Werte für Winkelventile und Durchgangsventile DN 15/DN 20. "
                + "Axial- und Winkel-Eck-Ausführungen haben auf Stufe 6 nur "
                + "kv 0,51. Werkseinstellung ist Stufe 6, Zwischenstellungen sind "
                + "laut Hersteller nicht zulässig."),
        ValveModel(
            manufacturer: .resideo,
            name: "V2000SX",
            size: .dn20,
            settings: ValveDatabase.resideoV2000SXStandardSettings,
            kvs: 0.70,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: ValveDatabase.resideoSXSource,
            note: "Werte für Winkelventile und Durchgangsventile DN 15/DN 20. "
                + "Werkseinstellung ist Stufe 6, Zwischenstellungen sind laut "
                + "Hersteller nicht zulässig."),
        ValveModel(
            manufacturer: .resideo,
            name: "V2000FX",
            size: .dn10,
            settings: ValveDatabase.resideoV2000FXSettings,
            kvs: 0.285,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: ValveDatabase.resideoFXSource,
            note: "Ausführung für kleine Durchflüsse (ca. 10–70 l/h). "
                + "Werkseinstellung ist Stufe 6."),
        ValveModel(
            manufacturer: .resideo,
            name: "V2000FX",
            size: .dn15,
            settings: ValveDatabase.resideoV2000FXSettings,
            kvs: 0.285,
            controlDeviationK: 2.0,
            quality: .herstellerangabe,
            source: ValveDatabase.resideoFXSource,
            note: "Ausführung für kleine Durchflüsse (ca. 10–70 l/h). "
                + "Werkseinstellung ist Stufe 6.")
    ]

    // MARK: - Taconova
    //
    // BEWUSST LEER. Taconova führt im deutschen Datenblatt-Katalog kein
    // Heizkörper-Thermostatventil mit veröffentlichter kv-Tabelle je
    // Voreinstellung; der Abgleich-Bereich dort sind Durchflussmesser für
    // Heizkreisverteiler (TopMeter/TopMeter Plus, kvs 1,1). Solange keine
    // belastbare Tabelle vorliegt, wird hier nichts eingetragen – geratene
    // Einstellwerte wären am Ventil schlicht falsch.

    // MARK: - Rückfall „Fabrikat unbekannt"
    //
    // Zahlen identisch mit `HydraulicBalancing.presetKv` in SystemSizing.swift,
    // damit die App bei unbekanntem Ventil weiterrechnet wie bisher.
    // Als Näherung gekennzeichnet: der Bereich reicht deutlich weiter als bei
    // echten DN-15-Ventilen (dort endet die oberste Stufe bei kv 0,52–0,67).

    public static let genericSettings: [ValveSetting] = [
        ValveSetting(label: "1", kv: 0.09),
        ValveSetting(label: "2", kv: 0.16),
        ValveSetting(label: "3", kv: 0.29),
        ValveSetting(label: "4", kv: 0.50),
        ValveSetting(label: "5", kv: 0.72),
        ValveSetting(label: "6", kv: 0.95),
        ValveSetting(label: "7", kv: 1.15),
        ValveSetting(label: "8", kv: 1.40)
    ]

    /// Rückfall-Modell, wenn das Fabrikat vor Ort nicht bekannt ist.
    public static let genericValve = ValveModel(
        manufacturer: .generic,
        name: "Standard-Thermostatventil",
        size: .dn15,
        settings: ValveDatabase.genericSettings,
        kvs: nil,
        controlDeviationK: 2.0,
        quality: .naeherung,
        source: "Anhaltswerte gängiger Thermostatventile – identisch mit "
            + "HydraulicBalancing.presetKv",
        note: "Nur verwenden, wenn das Fabrikat unbekannt ist. Die Stufen decken "
            + "einen größeren kv-Bereich ab als reale DN-15-Ventile; die "
            + "Herstellertabelle bleibt maßgebend.")

    public static let genericModels: [ValveModel] = [ValveDatabase.genericValve]

    // MARK: - Gesamtbestand und Abfragen

    /// Alle hinterlegten Ventilmodelle.
    public static let all: [ValveModel] =
        ValveDatabase.heimeierModels
        + ValveDatabase.oventropModels
        + ValveDatabase.danfossModels
        + ValveDatabase.resideoModels
        + ValveDatabase.genericModels

    /// Alle Modelle eines Herstellers.
    public static func models(of manufacturer: ValveManufacturer) -> [ValveModel] {
        ValveDatabase.all.filter { $0.manufacturer == manufacturer }
    }

    /// Alle Modelle eines Herstellers in einer Nennweite.
    public static func models(of manufacturer: ValveManufacturer,
                              size: ValveSize) -> [ValveModel] {
        ValveDatabase.all.filter { $0.manufacturer == manufacturer && $0.size == size }
    }

    /// Alle Modelle einer Nennweite (herstellerübergreifend).
    public static func models(size: ValveSize) -> [ValveModel] {
        ValveDatabase.all.filter { $0.size == size }
    }

    /// Modell über seine ID (zum Speichern in der Heizkörper-/Raumakte).
    public static func model(id: String) -> ValveModel? {
        ValveDatabase.all.first { $0.id == id }
    }

    /// Hersteller, für die Modelle hinterlegt sind – für die Auswahlliste,
    /// damit dort keine leeren Einträge auftauchen.
    public static var populatedManufacturers: [ValveManufacturer] {
        ValveManufacturer.allCases.filter { manufacturer in
            ValveDatabase.all.contains { $0.manufacturer == manufacturer }
        }
    }

    /// Rückfall, wenn kein Modell gewählt wurde.
    public static var fallback: ValveModel { ValveDatabase.genericValve }
}
