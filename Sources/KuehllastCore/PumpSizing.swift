import Foundation

/// Auslegung der Umwälzpumpe und Gesamt-Anlagendaten.
///
/// Warum das hier gebraucht wird: Das VdZ-Nachweisformular zum hydraulischen
/// Abgleich (Verfahren B) verlangt neben den Ventil-Einstellwerten auch die
/// **Systemdaten der Anlage** – Vor-/Rücklauftemperatur, Spreizung,
/// Gesamtvolumenstrom und die eingestellte **Pumpenförderhöhe**. Die ersten
/// drei hat die App, die letzten beiden werden hier ergänzt.
///
/// Das Verfahren ist bewusst das übliche überschlägige: Rohrreibung über den
/// ungünstigsten Strang, Einzelwiderstände als Zuschlag, dazu die festen
/// Anteile von Ventil und Wärmeerzeuger. Eine echte Rohrnetzberechnung ist es
/// NICHT – deshalb kann der Nutzer jeden Eingangswert überschreiben, und der
/// Bericht weist die Annahmen aus.
public struct PumpSizingInput: Codable, Hashable, Sendable {
    /// Länge des ungünstigsten Heizkreises (Hin- und Rückweg) in m.
    public var longestCircuitM: Double
    /// Spezifischer Rohrreibungsdruckverlust in Pa/m. 100 Pa/m ist der
    /// übliche Auslegungswert (wirtschaftliches Optimum).
    public var specificLossPaPerM: Double
    /// Zuschlagsfaktor für Einzelwiderstände (Bögen, T-Stücke, Armaturen).
    /// 1,3 heißt: 30 % Aufschlag auf die reine Rohrreibung.
    public var singleResistanceFactor: Double
    /// Differenzdruck am Thermostatventil in mbar (Verfahren B: 100 mbar,
    /// derselbe Wert, mit dem die Voreinstellungen gerechnet werden).
    public var valveDpMbar: Double
    /// Druckverlust des Wärmeerzeugers in mbar (Datenblatt Wärmepumpe).
    public var generatorDpMbar: Double
    /// Zusätzliche Widerstände in mbar (Filter, Wärmemengenzähler,
    /// Rückschlagklappe, Weiche). Vorgabe 0 – bewusst nicht geraten.
    public var extraDpMbar: Double
    /// **Restförderhöhe** der Wärmepumpe laut Datenblatt in m (auch
    /// „max. externer Druckverlust"). Bei Wärmepumpen sitzt die Umwälzpumpe
    /// fast immer IM Gerät; verglichen werden darf dann nur der EXTERNE
    /// Anteil (Rohr + Ventil + Zusatz) mit diesem Wert – nicht die Summe
    /// inklusive Gerätewiderstand. 0 = unbekannt, dann greift der
    /// allgemeine Richtwert für Standardpumpen.
    public var availableHeadM: Double

    public init(longestCircuitM: Double = 50,
                specificLossPaPerM: Double = 100,
                singleResistanceFactor: Double = 1.3,
                valveDpMbar: Double = 100,
                generatorDpMbar: Double = 150,
                extraDpMbar: Double = 0,
                availableHeadM: Double = 0) {
        self.longestCircuitM = longestCircuitM
        self.specificLossPaPerM = specificLossPaPerM
        self.singleResistanceFactor = singleResistanceFactor
        self.valveDpMbar = valveDpMbar
        self.generatorDpMbar = generatorDpMbar
        self.extraDpMbar = extraDpMbar
        self.availableHeadM = availableHeadM
    }

    private enum CodingKeys: String, CodingKey {
        case longestCircuitM, specificLossPaPerM, singleResistanceFactor
        case valveDpMbar, generatorDpMbar, extraDpMbar, availableHeadM
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.longestCircuitM        = (try? c.decode(Double.self, forKey: .longestCircuitM)) ?? 50
        self.specificLossPaPerM     = (try? c.decode(Double.self, forKey: .specificLossPaPerM)) ?? 100
        self.singleResistanceFactor = (try? c.decode(Double.self, forKey: .singleResistanceFactor)) ?? 1.3
        self.valveDpMbar            = (try? c.decode(Double.self, forKey: .valveDpMbar)) ?? 100
        self.generatorDpMbar        = (try? c.decode(Double.self, forKey: .generatorDpMbar)) ?? 150
        self.extraDpMbar            = (try? c.decode(Double.self, forKey: .extraDpMbar)) ?? 0
        self.availableHeadM         = (try? c.decode(Double.self, forKey: .availableHeadM)) ?? 0
    }
}

/// Ergebnis der Pumpenauslegung.
public struct PumpSizingResult: Sendable {
    /// Druckverlust der Rohrleitung inkl. Einzelwiderstände in Pa.
    public var pipeLossPa: Double
    /// Feste Anteile (Ventil + Erzeuger + Zusatz) in Pa.
    public var fixedLossPa: Double
    /// Gesamtdruckverlust in Pa.
    public var totalPa: Double
    /// Gesamtdruckverlust in mbar (so steht es meist im Formular).
    public var totalMbar: Double { totalPa / 100.0 }
    /// Erforderliche Förderhöhe in m Wassersäule (Gesamtanlage inkl.
    /// Wärmeerzeuger – maßgeblich, wenn eine EXTERNE Pumpe verbaut ist).
    public var headM: Double
    /// EXTERNER Druckverlust in Pa: Rohr + Ventil + Zusatz, ohne den
    /// Wärmeerzeuger. Das ist die Zahl, die mit der Restförderhöhe einer
    /// Wärmepumpe mit interner Pumpe verglichen werden muss.
    public var externalPa: Double
    public var externalMbar: Double { externalPa / 100.0 }
    /// Externer Anteil als Förderhöhe in m.
    public var externalHeadM: Double
    /// Fachliche Hinweise zur Belastbarkeit der Rechnung (kein Fehler,
    /// sondern Grenzen des Verfahrens – gehören in den Bericht).
    public var hints: [String]
    /// Gesamtvolumenstrom der Anlage in kg/h.
    public var totalFlowKgPerH: Double
    /// Gesamtvolumenstrom in m³/h.
    public var totalFlowCubicMPerH: Double { totalFlowKgPerH / 1000.0 }
    /// Hinweis, wenn die Förderhöhe über dem liegt, was Standardpumpen in
    /// Ein- und Zweifamilienhäusern leisten (Hocheffizienzpumpen: ~6 m).
    public var warning: String?
}

public enum PumpSizing {

    /// ρ·g für Wasser bei 20 °C: 1000 kg/m³ · 9,81 m/s² = 9810 Pa je Meter
    /// Wassersäule. Bewusst der Kaltwasserwert – Pumpenkennlinien der
    /// Hersteller sind darauf bezogen. Bei 50 °C Heizungswasser wären es
    /// ~9690 Pa/m; der Unterschied liegt bei rund 1 % und ginge zulasten der
    /// Sicherheitsreserve, deshalb bleibt es beim Kennlinien-Bezugswert.
    /// (Die verbreitete Faustformel rechnet sogar mit glatt 10.000 Pa/m.)
    public static let paPerMeterHead: Double = 9810

    /// Förderhöhe, ab der eine Standard-Hocheffizienzpumpe im Ein-/Zweifamilien-
    /// haus nicht mehr reicht.
    public static let typicalPumpLimitM: Double = 6.0

    /// Rechnet den Gesamtvolumenstrom aus Heizlast und Spreizung.
    /// m = Q · 0,86 / ΔT – dieselbe Formel wie beim einzelnen Heizkörper,
    /// damit die Summe im Formular zu den Einzelwerten passt.
    public static func totalFlowKgPerH(totalLoadW: Double, spreadK: Double) -> Double {
        let spread = max(spreadK, 3)
        return max(totalLoadW, 0) * 0.86 / spread
    }

    public static func calculate(input: PumpSizingInput,
                                 totalLoadW: Double,
                                 spreadK: Double) -> PumpSizingResult {
        let length = max(input.longestCircuitM, 0)
        let specific = max(input.specificLossPaPerM, 0)
        let factor = max(input.singleResistanceFactor, 1)

        let pipeLoss = length * specific * factor
        // mbar → Pa: 1 mbar = 100 Pa
        let valvePa = max(input.valveDpMbar, 0) * 100.0
        let generatorPa = max(input.generatorDpMbar, 0) * 100.0
        let extraPa = max(input.extraDpMbar, 0) * 100.0
        let fixedLoss = valvePa + generatorPa + extraPa
        let total = pipeLoss + fixedLoss
        // Extern = alles außer dem Wärmeerzeuger. Nur dieser Anteil darf mit
        // der Restförderhöhe einer WP mit interner Pumpe verglichen werden.
        let external = pipeLoss + valvePa + extraPa
        let head = total / paPerMeterHead
        let externalHead = external / paPerMeterHead
        let flow = totalFlowKgPerH(totalLoadW: totalLoadW, spreadK: spreadK)

        var warning: String?
        let available = max(input.availableHeadM, 0)
        if available > 0 {
            // Genauer Vergleich: Datenblattwert des Geräts gegen den externen Anteil.
            if externalHead > available {
                warning = "Externer Druckverlust " + meters(externalHead)
                    + " m übersteigt die Restförderhöhe des Geräts (" + meters(available)
                    + " m). Strangaufteilung, größere Querschnitte oder Zusatzpumpe prüfen."
            }
        } else if externalHead > typicalPumpLimitM {
            warning = "Erforderliche Förderhöhe " + meters(externalHead)
                + " m liegt über dem, was übliche Hocheffizienzpumpen im Ein-/Zweifamilienhaus "
                + "leisten (~" + meters(typicalPumpLimitM) + " m). "
                + "Strangaufteilung oder größere Rohrquerschnitte prüfen."
        }

        var hints: [String] = []
        if available <= 0 {
            hints.append("Restförderhöhe der Wärmepumpe aus dem Datenblatt eintragen – bei "
                         + "geräteinterner Pumpe ist sie der maßgebliche Vergleichswert. "
                         + "Der Richtwert von " + meters(typicalPumpLimitM)
                         + " m gilt bei Nullförderung; unter Last leistet dieselbe Pumpe weniger.")
        }
        if spreadK > 0, spreadK < 8 {
            hints.append("Kleine Spreizung (" + meters(spreadK) + " K) bedeutet großen Volumenstrom. "
                         + "Im vorhandenen Rohrnetz steigt der Druckverlust überproportional "
                         + "(etwa quadratisch) – die Rohrreibung hier ist ein Auslegungswert, "
                         + "keine Nachrechnung des bestehenden Netzes.")
        }
        hints.append("Überschlägige Auslegung (Rohrreibung über den ungünstigsten Strang, "
                     + "Einzelwiderstände als Zuschlag). Ersetzt keine Rohrnetzberechnung.")

        return PumpSizingResult(pipeLossPa: pipeLoss,
                                fixedLossPa: fixedLoss,
                                totalPa: total,
                                headM: head,
                                externalPa: external,
                                externalHeadM: externalHead,
                                hints: hints,
                                totalFlowKgPerH: flow,
                                warning: warning)
    }

    /// Zahl mit deutschem Dezimalkomma – die App schreibt sonst überall Komma,
    /// `String(format:)` liefert aber einen Punkt.
    private static func meters(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
