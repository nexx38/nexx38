import Foundation

/// Amtliche Pauschal-U-Werte für Bestandsbauteile.
///
/// Quelle: „Bekanntmachung der Regeln zur Datenaufnahme und Datenverwendung
/// im Wohngebäudebestand" vom 8. Oktober 2020 (BAnz AT 04.12.2020 B1),
/// Nummer 3.2, Tabellen 2 und 3.
///
/// Warum genau diese Quelle: Die BEG erlaubt für die raumweise Heizlast
/// ausdrücklich „U-Werte nach Typologie" und verweist dafür auf diese
/// Bekanntmachung. Als amtliche Bekanntmachung ist sie nach § 5 Abs. 1 UrhG
/// frei von Urheberrechten – anders als die inhaltsgleichen Tabellen einer
/// DIN-Norm. Im Bericht kann die Herkunft damit belegt genannt werden.
///
/// ⚠️ Aus dieser Bekanntmachung wird NUR Nummer 3.1–3.3 (U-Werte) übernommen.
/// Ihre Tabelle 1 enthält geometrische Aufmaß-Vereinfachungen – die sind für
/// Energieausweise gedacht und für den BEG-Nachweis ausdrücklich unzulässig.
///
/// Nicht belegte Kombinationen liefern `nil` („keine Angabe" im Original).
/// Es wird nichts geschätzt und nichts interpoliert.
public enum BuildingAgeClass: String, Codable, CaseIterable, Sendable {
    case bis1918   = "bis1918"
    case a1919_1948 = "1919_1948"
    case a1949_1957 = "1949_1957"
    case a1958_1968 = "1958_1968"
    case a1969_1978 = "1969_1978"
    case a1979_1983 = "1979_1983"
    case a1984_1994 = "1984_1994"
    case a1995_2001 = "1995_2001"
    case ab2002    = "ab2002"

    /// Bezeichnung wörtlich wie in der Bekanntmachung.
    public var label: String {
        switch self {
        case .bis1918:    return "bis 1918"
        case .a1919_1948: return "1919 bis 1948"
        case .a1949_1957: return "1949 bis 1957"
        case .a1958_1968: return "1958 bis 1968"
        case .a1969_1978: return "1969 bis 1978"
        case .a1979_1983: return "1979 bis 1983"
        case .a1984_1994: return "1984 bis 1994"
        case .a1995_2001: return "1995 bis 2001"
        case .ab2002:     return "ab 2002"
        }
    }

    /// Spaltenindex in den Tabellen (0…8).
    public var column: Int {
        switch self {
        case .bis1918:    return 0
        case .a1919_1948: return 1
        case .a1949_1957: return 2
        case .a1958_1968: return 3
        case .a1969_1978: return 4
        case .a1979_1983: return 5
        case .a1984_1994: return 6
        case .a1995_2001: return 7
        case .ab2002:     return 8
        }
    }

    /// Ordnet ein Baujahr der amtlichen Klasse zu.
    /// Fußnote 1 der Bekanntmachung: maßgebend ist im Zweifel das Jahr der
    /// Fertigstellung; bei nachträglich eingebauten Bauteilen deren Baujahr.
    public static func forYear(_ year: Int) -> BuildingAgeClass {
        switch year {
        case ..<1919:    return .bis1918
        case 1919...1948: return .a1919_1948
        case 1949...1957: return .a1949_1957
        case 1958...1968: return .a1958_1968
        case 1969...1978: return .a1969_1978
        case 1979...1983: return .a1979_1983
        case 1984...1994: return .a1984_1994
        case 1995...2001: return .a1995_2001
        default:         return .ab2002
        }
    }
}

/// Baualtersklassen für transparente Bauteile – Tabelle 3 hat eine eigene,
/// gröbere Einteilung mit nur fünf Klassen.
public enum WindowAgeClass: String, Codable, CaseIterable, Sendable {
    case bis1978    = "bis1978"
    case a1979_1983 = "1979_1983"
    case a1984_1994 = "1984_1994"
    case a1995_2001 = "1995_2001"
    case ab2002     = "ab2002"

    public var label: String {
        switch self {
        case .bis1978:    return "bis 1978"
        case .a1979_1983: return "1979 bis 1983"
        case .a1984_1994: return "1984 bis 1994"
        case .a1995_2001: return "ab 1995 bis 2001"
        case .ab2002:     return "ab 2002"
        }
    }

    public var column: Int {
        switch self {
        case .bis1978:    return 0
        case .a1979_1983: return 1
        case .a1984_1994: return 2
        case .a1995_2001: return 3
        case .ab2002:     return 4
        }
    }

    /// Maßgebend ist das **Einbaujahr des Fensters**, nicht das Baujahr des
    /// Hauses (Fußnote 1). Nach einem Fenstertausch ist das der größte
    /// Einzelunterschied der ganzen Tabelle: U 5,0 gegenüber 1,5.
    public static func forYear(_ year: Int) -> WindowAgeClass {
        switch year {
        case ..<1979:     return .bis1978
        case 1979...1983: return .a1979_1983
        case 1984...1994: return .a1984_1994
        case 1995...2001: return .a1995_2001
        default:          return .ab2002
        }
    }
}

/// Konstruktionsart eines opaken Bauteils (Zeilen der Tabelle 2).
public enum ComponentConstruction: String, Codable, CaseIterable, Sendable {
    // Dach
    case dachMassiv, dachHolz
    // Oberste Geschossdecke
    case deckeMassiv, deckeHolzbalken
    // Außenwand massiv
    case wandZweischaligOhneDaemmung, wandZweischaligMitDaemmung
    case wandVollziegelBis20, wandVollziegel20bis30, wandVollziegelUeber30
    case wandHochlochziegel
    case wandSonstigeMassivBis20, wandSonstigeUeber20
    // Außenwand Holz
    case wandMassivholz, wandFachwerkLehm, wandFachwerkVollziegel, wandSonstigeHolz
    // Gegen Erdreich / unbeheizt
    case kellerdeckeStahlbeton, kellerdeckeHolzbalken, kellerdeckeZiegel
    case bodenErdreichStahlbeton, bodenErdreichZiegelHolz, bodenErdreichHohlraumHolz
    // Rollladenkasten
    case rollladenUngedaemmt, rollladenGedaemmt
    // Türen (ohne Baualtersabhängigkeit)
    case tuerMetall, tuerHolzKunststoff

    public var label: String {
        switch self {
        case .dachMassiv:  return "Dach, massive Konstruktion"
        case .dachHolz:    return "Dach, Holzkonstruktion"
        case .deckeMassiv: return "Oberste Geschossdecke, massiv"
        case .deckeHolzbalken: return "Oberste Geschossdecke, Holzbalken"
        case .wandZweischaligOhneDaemmung: return "Zweischalig ohne Dämmschicht"
        case .wandZweischaligMitDaemmung:  return "Zweischalig mit Dämmschicht"
        case .wandVollziegelBis20:   return "Vollziegel/Naturstein bis 20 cm"
        case .wandVollziegel20bis30: return "Vollziegel/Naturstein 20–30 cm"
        case .wandVollziegelUeber30: return "Vollziegel/Naturstein über 30 cm"
        case .wandHochlochziegel:    return "Hochlochziegel / Bimsbeton-Hohlstein"
        case .wandSonstigeMassivBis20: return "Sonstige massiv bis 20 cm"
        case .wandSonstigeUeber20:     return "Sonstige massiv über 20 cm"
        case .wandMassivholz:          return "Massivholz / Holzrahmen mit Füllung"
        case .wandFachwerkLehm:        return "Fachwerk mit Lehmausfachung bis 25 cm"
        case .wandFachwerkVollziegel:  return "Fachwerk mit Vollziegelausfachung bis 25 cm"
        case .wandSonstigeHolz:        return "Sonstige Holzkonstruktion"
        case .kellerdeckeStahlbeton:   return "Kellerdecke Stahlbeton massiv"
        case .kellerdeckeHolzbalken:   return "Kellerdecke Holzbalkendecke"
        case .kellerdeckeZiegel:       return "Kellerdecke Ziegel/Hohlstein"
        case .bodenErdreichStahlbeton: return "Boden gegen Erdreich, Stahlbeton"
        case .bodenErdreichZiegelHolz: return "Boden gegen Erdreich, Ziegel/Holz"
        case .bodenErdreichHohlraumHolz: return "Boden gegen Erdreich/Hohlraum, Holz"
        case .rollladenUngedaemmt: return "Rollladenkasten ungedämmt"
        case .rollladenGedaemmt:   return "Rollladenkasten gedämmt"
        case .tuerMetall:          return "Tür im Wesentlichen aus Metall"
        case .tuerHolzKunststoff:  return "Tür aus Holz, Holzwerkstoff oder Kunststoff"
        }
    }

    /// Werte je Baualtersklasse (Index 0…8). `nil` = „keine Angabe".
    /// ⚠️ Diese Zahlen sind 1:1 aus Tabelle 2 der Bekanntmachung übernommen –
    /// nicht verändern, ohne die Quelle erneut zu prüfen.
    public var uValues: [Double?] {
        switch self {
        case .dachMassiv:      return [2.1, 2.1, 2.1, 1.3, 1.3, 0.60, 0.40, 0.30, 0.20]
        case .dachHolz:        return [2.6, 1.4, 1.4, 1.4, 0.80, 0.70, 0.50, 0.30, 0.20]
        case .deckeMassiv:     return [2.1, 2.1, 2.1, 2.1, 0.60, 0.60, 0.30, 0.30, 0.20]
        case .deckeHolzbalken: return [1.0, 1.0, 0.80, 0.70, 0.60, 0.40, 0.30, 0.30, 0.20]

        case .wandZweischaligOhneDaemmung:
            return [1.3, 1.3, 1.3, 1.4, 1.0, 0.80, 0.60, 0.50, 0.40]
        case .wandZweischaligMitDaemmung:
            return [nil, nil, 1.0, 0.90, 0.90, 0.70, 0.50, 0.50, 0.40]
        case .wandVollziegelBis20:
            return [2.8, 2.8, 2.8, nil, nil, nil, nil, nil, nil]
        case .wandVollziegel20bis30:
            return [1.8, 1.8, 1.8, nil, nil, nil, nil, nil, nil]
        case .wandVollziegelUeber30:
            return [1.5, 1.5, 1.5, nil, nil, nil, nil, nil, nil]
        case .wandHochlochziegel:
            return [1.4, 1.4, 1.4, 1.4, 1.0, 0.80, 0.60, 0.50, 0.40]
        case .wandSonstigeMassivBis20:
            return [3.0, 3.0, 3.0, 1.4, 1.0, 0.80, 0.70, 0.70, 0.40]
        case .wandSonstigeUeber20:
            return [2.2, 2.2, 2.2, 1.4, 1.0, 0.80, 0.60, 0.50, 0.40]

        case .wandMassivholz:
            return [0.50, 0.50, 0.50, 0.50, 0.50, 0.50, 0.40, 0.40, 0.30]
        case .wandFachwerkLehm:
            return [1.5, 1.5, 1.5, nil, nil, nil, nil, nil, nil]
        case .wandFachwerkVollziegel:
            return [2.0, 2.0, 2.0, nil, nil, nil, nil, nil, nil]
        case .wandSonstigeHolz:
            return [2.0, 2.0, 1.5, 1.4, 0.60, 0.50, 0.40, 0.40, 0.30]

        case .kellerdeckeStahlbeton:
            return [1.6, 1.6, 2.3, 1.0, 1.0, 0.80, 0.60, 0.60, 0.50]
        case .kellerdeckeHolzbalken:
            return [1.0, 1.0, 1.0, 0.80, 0.60, 0.60, 0.40, 0.40, 0.40]
        case .kellerdeckeZiegel:
            return [1.2, 1.2, 1.5, 1.0, 1.0, 0.80, 0.60, 0.60, 0.50]
        case .bodenErdreichStahlbeton:
            return [1.6, 1.6, 2.3, 1.2, 1.2, 0.80, 0.60, 0.60, 0.50]
        case .bodenErdreichZiegelHolz:
            return [1.2, 1.2, 1.5, 1.0, 1.0, 0.80, 0.60, 0.60, nil]
        case .bodenErdreichHohlraumHolz:
            return [1.8, 1.8, 1.0, 0.80, 0.60, 0.60, 0.40, 0.40, nil]

        case .rollladenUngedaemmt:
            return [3.6, 3.6, 3.6, 3.6, 3.6, 3.6, 3.6, nil, nil]
        case .rollladenGedaemmt:
            return [2.2, 2.2, 2.2, 1.8, 1.8, 1.8, 1.5, 1.4, 0.85]

        // Türen sind in der Bekanntmachung über alle Klassen zusammengefasst.
        case .tuerMetall:         return Array(repeating: 4.0, count: 9)
        case .tuerHolzKunststoff: return Array(repeating: 2.9, count: 9)
        }
    }

    /// U-Wert für eine Baualtersklasse; `nil` wenn im Original nicht belegt.
    public func uValue(for ageClass: BuildingAgeClass) -> Double? {
        let values = uValues
        guard values.indices.contains(ageClass.column) else { return nil }
        return values[ageClass.column]
    }
}

/// Fensterkonstruktion (Zeilen der Tabelle 3).
public enum WindowConstruction: String, Codable, CaseIterable, Sendable {
    case holzEinfach, holzZweiScheiben, kunststoffIsolier, metallIsolier

    public var label: String {
        switch self {
        case .holzEinfach:       return "Holzfenster, einfach verglast"
        case .holzZweiScheiben:  return "Holzfenster, zwei Scheiben"
        case .kunststoffIsolier: return "Kunststofffenster, Isolierverglasung"
        case .metallIsolier:     return "Aluminium-/Stahlfenster, Isolierverglasung"
        }
    }

    /// U-Wert des gesamten Fensters (U_W) je Fenster-Baualtersklasse.
    public var windowUValues: [Double?] {
        switch self {
        case .holzEinfach:       return [5.0, nil, nil, nil, nil]
        case .holzZweiScheiben:  return [2.7, 2.7, 2.7, 1.6, 1.5]
        case .kunststoffIsolier: return [3.0, 3.0, 3.0, 1.9, 1.5]
        case .metallIsolier:     return [4.3, 4.3, 3.2, 1.9, 1.5]
        }
    }

    /// U-Wert der Verglasung (U_g). ⚠️ NICHT der Gesamtenergiedurchlassgrad g –
    /// den enthält die Bekanntmachung nicht. Für die Heizlast wird g auch
    /// nicht gebraucht; für die Kühllast bleibt er eine eigene Annahme.
    public var glazingUValues: [Double?] {
        switch self {
        case .holzEinfach:       return [5.8, nil, nil, nil, nil]
        case .holzZweiScheiben:  return [2.9, 2.9, 2.9, 1.4, 1.2]
        case .kunststoffIsolier: return [2.9, 2.9, 2.9, 1.4, 1.2]
        case .metallIsolier:     return [2.9, 2.9, 2.9, 1.4, 1.2]
        }
    }

    public func windowU(for ageClass: WindowAgeClass) -> Double? {
        let values = windowUValues
        guard values.indices.contains(ageClass.column) else { return nil }
        return values[ageClass.column]
    }

    public func glazingU(for ageClass: WindowAgeClass) -> Double? {
        let values = glazingUValues
        guard values.indices.contains(ageClass.column) else { return nil }
        return values[ageClass.column]
    }
}

public enum OfficialUValues {

    /// Quellenangabe für den Bericht – so gehört sie zitiert.
    public static let sourceNote =
        "U-Werte nach Bekanntmachung der Regeln zur Datenaufnahme und "
        + "Datenverwendung im Wohngebäudebestand vom 08.10.2020 "
        + "(BAnz AT 04.12.2020 B1), Nummer 3.2, Tabellen 2 und 3"

    /// Wärmeleitfähigkeit für Dämmstoffe, wenn sie nicht bekannt ist –
    /// Vorgabewerte der Bekanntmachung, Nummer 3.3.
    public static let lambdaMineralOderKunststoff: Double = 0.04
    public static let lambdaNachwachsendOderEinblas: Double = 0.05

    /// Faktor für Heizkörpernischen (Nummer 3.2): U = 2 × U der Außenwand.
    public static let heizkoerpernischeFaktor: Double = 2.0

    /// Korrektur nach Nummer 3.3 für nachträglich gedämmte Bauteile:
    ///
    ///     U = 1 / (1/U₀ + Σ dᵢ/λᵢ)
    ///
    /// Wichtig: Die Wärmeübergangswiderstände stecken bereits in U₀ und
    /// dürfen NICHT zusätzlich angesetzt werden.
    ///
    /// - Parameter baseU: Pauschalwert aus Tabelle 2 (Urzustand).
    /// - Parameter layers: nachträgliche Dämmschichten (Dicke in m,
    ///   Wärmeleitfähigkeit in W/(m·K)).
    public static func withRetrofitInsulation(baseU: Double,
                                              layers: [(thicknessM: Double, lambda: Double)]) -> Double? {
        guard baseU > 0 else { return nil }
        var resistance = 1.0 / baseU
        for layer in layers {
            guard layer.thicknessM > 0, layer.lambda > 0 else { continue }
            resistance += layer.thicknessM / layer.lambda
        }
        guard resistance > 0 else { return nil }
        return 1.0 / resistance
    }
}
