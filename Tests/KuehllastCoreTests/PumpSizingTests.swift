import XCTest
import Foundation
@testable import KuehllastCore

/// Tests für die Pumpenauslegung (`PumpSizing`).
///
/// Schwerpunkt liegt bewusst nicht auf „läuft durch", sondern auf den drei
/// Stellen, an denen ein Fehler teuer wird:
///
/// 1. **Zahlenwerte im Förderantrag** – jeder Erwartungswert unten ist von Hand
///    nachgerechnet, der Rechenweg steht als Kommentar daneben. Ändert jemand
///    eine Konstante (z. B. 9810 → 10000 Pa/m), fällt der Test um.
/// 2. **Konsistenz mit den anderen Rechenwegen** – `HydraulicBalancing.preset`
///    und `ValveDatabase.flowKgPerH` rechnen denselben Volumenstrom. Die
///    Anlage darf im Formular nicht zwei verschiedene Zahlen zeigen.
/// 3. **Robustheit** – Spreizung 0, negative Eingaben, fehlende JSON-Schlüssel:
///    nichts davon darf abstürzen oder NaN liefern.
final class PumpSizingTests: XCTestCase {

    // MARK: - Konstanten festnageln

    /// Die Umrechnung Pa → m ist der Wert, an dem die Förderhöhe im Formular
    /// hängt. ρ·g = 1000 kg/m³ · 9,81 m/s² = 9810 Pa je Meter Wassersäule.
    /// (Die verbreitete Faustformel „1 m ≙ 10.000 Pa" weicht davon um 1,9 % ab –
    /// wer sie einbaut, soll hier stolpern und es bewusst entscheiden.)
    func testKonstanteUmrechnungPaProMeter() {
        XCTAssertEqual(PumpSizing.paPerMeterHead, 9810, accuracy: 0.0001)
        XCTAssertEqual(PumpSizing.paPerMeterHead, 1000 * 9.81, accuracy: 0.0001,
                       "9810 muss ρ·g mit ρ = 1000 kg/m³ und g = 9,81 m/s² sein")
        // Abstand zur Faustformel 10.000 Pa/m: (10000 − 9810) / 10000 = 1,9 %.
        XCTAssertEqual((10_000 - PumpSizing.paPerMeterHead) / 10_000, 0.019,
                       accuracy: 0.0005)
    }

    /// Pumpengrenze: Standard-Hocheffizienzpumpen der Baugröße „25/1-6"
    /// (Grundfos Alpha2 25-60, Wilo Yonos PICO 25/1-6) haben 6 m maximale
    /// Förderhöhe. Wird der Wert stillschweigend hochgesetzt, fällt der Test.
    func testKonstantePumpengrenze() {
        XCTAssertEqual(PumpSizing.typicalPumpLimitM, 6.0, accuracy: 0.0001)
    }

    // MARK: - Vollständiges Zahlenbeispiel

    /// Rechenweg von Hand, Vorgabewerte des Formulars:
    ///
    ///   Rohranteil   = 50 m · 100 Pa/m · 1,3            = 6.500 Pa
    ///   Ventil       = 100 mbar · 100 Pa/mbar           = 10.000 Pa
    ///   Erzeuger     = 150 mbar · 100 Pa/mbar           = 15.000 Pa
    ///   Zusatz       = 0 mbar                           =      0 Pa
    ///   fester Anteil                                   = 25.000 Pa
    ///   Summe        = 6.500 + 25.000                   = 31.500 Pa
    ///                                                   =    315,0 mbar
    ///   Förderhöhe   = 31.500 / 9.810                   = 3,2110 m
    ///
    ///   Volumenstrom = 8.000 W · 0,86 / 10 K            = 688,0 kg/h
    ///                                                   = 0,688 m³/h
    func testVorgabeBeispielKomplettDurchgerechnet() {
        let r = PumpSizing.calculate(input: PumpSizingInput(),
                                     totalLoadW: 8000,
                                     spreadK: 10)

        XCTAssertEqual(r.pipeLossPa, 6500, accuracy: 0.001, "50 · 100 · 1,3")
        XCTAssertEqual(r.fixedLossPa, 25_000, accuracy: 0.001, "(100 + 150) mbar")
        XCTAssertEqual(r.totalPa, 31_500, accuracy: 0.001)
        XCTAssertEqual(r.totalMbar, 315.0, accuracy: 0.001, "1 mbar = 100 Pa")
        XCTAssertEqual(r.headM, 3.2110, accuracy: 0.001)
        XCTAssertEqual(r.totalFlowKgPerH, 688.0, accuracy: 0.001)
        XCTAssertEqual(r.totalFlowCubicMPerH, 0.688, accuracy: 0.0001)
        XCTAssertNil(r.warning, "3,2 m liegt deutlich unter der 6-m-Grenze")
    }

    /// Die abgeleiteten Größen dürfen keine eigene Rechnung sein, sondern
    /// müssen exakt aus den Basiswerten folgen (sonst driften Pa und mbar im
    /// Bericht auseinander).
    func testAbgeleiteteEinheitenSindKonsistent() {
        let input = PumpSizingInput(longestCircuitM: 73,
                                    specificLossPaPerM: 120,
                                    singleResistanceFactor: 1.45,
                                    valveDpMbar: 100,
                                    generatorDpMbar: 220,
                                    extraDpMbar: 35)
        let r = PumpSizing.calculate(input: input, totalLoadW: 9500, spreadK: 5)

        // 73 · 120 · 1,45 = 12.702 Pa
        XCTAssertEqual(r.pipeLossPa, 12_702, accuracy: 0.001)
        // (100 + 220 + 35) mbar = 355 mbar = 35.500 Pa
        XCTAssertEqual(r.fixedLossPa, 35_500, accuracy: 0.001)
        XCTAssertEqual(r.totalPa, r.pipeLossPa + r.fixedLossPa, accuracy: 0.001)
        XCTAssertEqual(r.totalMbar, r.totalPa / 100.0, accuracy: 1e-9)
        XCTAssertEqual(r.headM, r.totalPa / PumpSizing.paPerMeterHead, accuracy: 1e-9)
        XCTAssertEqual(r.totalFlowCubicMPerH, r.totalFlowKgPerH / 1000.0, accuracy: 1e-9)
        // 48.202 Pa / 9.810 = 4,9135 m
        XCTAssertEqual(r.headM, 4.9135, accuracy: 0.001)
        // 9.500 W · 0,86 / 5 K = 1.634 kg/h
        XCTAssertEqual(r.totalFlowKgPerH, 1634.0, accuracy: 0.001)
    }

    // MARK: - Monotonie

    /// Längerer Strang → mehr Rohrdruckverlust, mehr Gesamtdruck, mehr Höhe.
    /// Fängt ein vertauschtes Vorzeichen oder eine Division statt Multiplikation.
    func testLaengererStrangErhoehtDruckverlust() {
        let kurz = PumpSizing.calculate(input: PumpSizingInput(longestCircuitM: 30),
                                        totalLoadW: 8000, spreadK: 10)
        let lang = PumpSizing.calculate(input: PumpSizingInput(longestCircuitM: 90),
                                        totalLoadW: 8000, spreadK: 10)

        XCTAssertGreaterThan(lang.pipeLossPa, kurz.pipeLossPa)
        XCTAssertGreaterThan(lang.totalPa, kurz.totalPa)
        XCTAssertGreaterThan(lang.headM, kurz.headM)
        // Der feste Anteil darf sich von der Länge NICHT beeindrucken lassen.
        XCTAssertEqual(lang.fixedLossPa, kurz.fixedLossPa, accuracy: 0.001)
        // 90 m − 30 m = 60 m · 100 Pa/m · 1,3 = 7.800 Pa Differenz.
        XCTAssertEqual(lang.pipeLossPa - kurz.pipeLossPa, 7800, accuracy: 0.001)
    }

    /// Höherer Zuschlagsfaktor → mehr Rohrdruckverlust.
    func testHoehererZuschlagsfaktorErhoehtDruckverlust() {
        let klein = PumpSizing.calculate(input: PumpSizingInput(singleResistanceFactor: 1.3),
                                         totalLoadW: 8000, spreadK: 10)
        let gross = PumpSizing.calculate(input: PumpSizingInput(singleResistanceFactor: 2.2),
                                         totalLoadW: 8000, spreadK: 10)

        XCTAssertGreaterThan(gross.pipeLossPa, klein.pipeLossPa)
        // 50 · 100 · 2,2 = 11.000 Pa gegen 6.500 Pa.
        XCTAssertEqual(gross.pipeLossPa, 11_000, accuracy: 0.001)
        XCTAssertEqual(gross.fixedLossPa, klein.fixedLossPa, accuracy: 0.001)
    }

    /// Höherer spezifischer Druckverlust → mehr Rohrdruckverlust.
    func testHoehererSpezifischerDruckverlustErhoehtDruckverlust() {
        let r100 = PumpSizing.calculate(input: PumpSizingInput(specificLossPaPerM: 100),
                                        totalLoadW: 8000, spreadK: 10)
        let r150 = PumpSizing.calculate(input: PumpSizingInput(specificLossPaPerM: 150),
                                        totalLoadW: 8000, spreadK: 10)
        XCTAssertGreaterThan(r150.pipeLossPa, r100.pipeLossPa)
        // 50 · 150 · 1,3 = 9.750 Pa
        XCTAssertEqual(r150.pipeLossPa, 9750, accuracy: 0.001)
    }

    /// Mehr Zusatzwiderstand (Filter, Wärmemengenzähler, Weiche) → mehr fester
    /// Anteil, Rohranteil unverändert.
    func testZusatzwiderstandErhoehtNurDenFestenAnteil() {
        let ohne = PumpSizing.calculate(input: PumpSizingInput(extraDpMbar: 0),
                                        totalLoadW: 8000, spreadK: 10)
        let mit = PumpSizing.calculate(input: PumpSizingInput(extraDpMbar: 80),
                                       totalLoadW: 8000, spreadK: 10)

        XCTAssertEqual(mit.pipeLossPa, ohne.pipeLossPa, accuracy: 0.001)
        // 80 mbar = 8.000 Pa Aufschlag.
        XCTAssertEqual(mit.fixedLossPa - ohne.fixedLossPa, 8000, accuracy: 0.001)
        XCTAssertGreaterThan(mit.headM, ohne.headM)
    }

    /// Auch Ventil und Erzeuger müssen monoton in den festen Anteil eingehen.
    func testVentilUndErzeugerGehenMonotonEin() {
        let basis = PumpSizing.calculate(input: PumpSizingInput(),
                                         totalLoadW: 8000, spreadK: 10)
        let mehrVentil = PumpSizing.calculate(input: PumpSizingInput(valveDpMbar: 200),
                                              totalLoadW: 8000, spreadK: 10)
        let mehrErzeuger = PumpSizing.calculate(input: PumpSizingInput(generatorDpMbar: 300),
                                                totalLoadW: 8000, spreadK: 10)

        XCTAssertEqual(mehrVentil.fixedLossPa - basis.fixedLossPa, 10_000, accuracy: 0.001)
        XCTAssertEqual(mehrErzeuger.fixedLossPa - basis.fixedLossPa, 15_000, accuracy: 0.001)
        XCTAssertGreaterThan(mehrVentil.totalPa, basis.totalPa)
        XCTAssertGreaterThan(mehrErzeuger.totalPa, basis.totalPa)
    }

    // MARK: - Konsistenz mit den anderen Rechenwegen (wichtigster Test)

    /// Der Gesamtvolumenstrom der Anlage muss exakt der Summe der
    /// Einzel-Volumenströme entsprechen, wenn man dieselbe Last auf Räume
    /// aufteilt. Sonst zeigt das Formular für eine Anlage zwei Zahlen:
    /// oben die Summe aus der Ventiltabelle, unten die Pumpenzeile.
    ///
    /// Von Hand: (1200 + 1800 + 900 + 2100) W = 6000 W
    ///           6000 · 0,86 / 10 K = 516,0 kg/h
    func testGesamtvolumenstromGleichSummeDerEinzelstroeme() {
        let lasten: [Double] = [1200, 1800, 900, 2100]
        let spreizung: Double = 10
        let gesamtlast = lasten.reduce(0, +)

        let gesamt = PumpSizing.totalFlowKgPerH(totalLoadW: gesamtlast, spreadK: spreizung)
        let summeAbgleich = lasten.reduce(0.0) {
            $0 + HydraulicBalancing.preset(loadW: $1, spreadK: spreizung).flowKgPerH
        }
        let summeVentilDB = lasten.reduce(0.0) {
            $0 + ValveDatabase.flowKgPerH(loadW: $1, spreadK: spreizung)
        }

        XCTAssertEqual(gesamt, 516.0, accuracy: 1e-9, "6000 · 0,86 / 10")
        XCTAssertEqual(gesamt, summeAbgleich, accuracy: 1e-9,
                       "PumpSizing und HydraulicBalancing müssen dieselbe Zahl liefern")
        XCTAssertEqual(gesamt, summeVentilDB, accuracy: 1e-9,
                       "PumpSizing und ValveDatabase müssen dieselbe Zahl liefern")
    }

    /// Dieselbe Prüfung an einem einzelnen Wert und über mehrere Spreizungen –
    /// fängt eine abweichende Konstante (0,86 gegen 1/1,163) oder eine
    /// abweichende Abfang-Grenze in einem der drei Rechenwege.
    func testEinzelwertUeberAlleRechenwegeIdentisch() {
        for last: Double in [0, 350, 800, 2600, 12_000] {
            for spreizung: Double in [3, 5, 8, 10, 15] {
                let ausPumpe = PumpSizing.totalFlowKgPerH(totalLoadW: last, spreadK: spreizung)
                let ausVentilDB = ValveDatabase.flowKgPerH(loadW: last, spreadK: spreizung)
                let ausAbgleich = HydraulicBalancing.preset(loadW: last,
                                                            spreadK: spreizung).flowKgPerH
                XCTAssertEqual(ausPumpe, ausVentilDB, accuracy: 1e-9,
                               "Last \(last) W, Spreizung \(spreizung) K")
                XCTAssertEqual(ausPumpe, ausAbgleich, accuracy: 1e-9,
                               "Last \(last) W, Spreizung \(spreizung) K")
            }
        }
    }

    /// Auch der Ventil-Differenzdruck ist eine Zahl, die an drei Stellen steht
    /// (Vorgabe der Pumpenauslegung, Verfahren B im Abgleich, Ventildatenbank).
    /// Läuft eine davon weg, rechnet das Formular mit zwei Annahmen.
    func testVentilDifferenzdruckUeberallGleich() {
        XCTAssertEqual(PumpSizingInput().valveDpMbar,
                       HydraulicBalancing.valveDpMbar, accuracy: 1e-9)
        XCTAssertEqual(PumpSizingInput().valveDpMbar,
                       ValveDatabase.defaultValveDpMbar, accuracy: 1e-9)
        XCTAssertEqual(PumpSizingInput().valveDpMbar, 100, accuracy: 1e-9,
                       "Verfahren B rechnet mit 100 mbar am Thermostatventil")
    }

    /// Der Gesamtvolumenstrom muss zur Ventilauslegung passen: derselbe
    /// Volumenstrom, derselbe angenommene Differenzdruck → derselbe kv-Wert.
    func testGesamtstromPasstZurKvRechnung() {
        let last: Double = 800
        let flowAusPumpe = PumpSizing.totalFlowKgPerH(totalLoadW: last, spreadK: 10)
        let kvAusFlow = ValveDatabase.kvNeeded(flowKgPerH: flowAusPumpe)
        let kvDirekt = ValveDatabase.kvNeeded(loadW: last, spreadK: 10)
        XCTAssertEqual(kvAusFlow, kvDirekt, accuracy: 1e-12)
        // 800 · 0,86 / 10 = 68,8 kg/h → 0,0688 m³/h / √0,1 bar = 0,2176
        XCTAssertEqual(kvDirekt, 0.2176, accuracy: 0.0005)
    }

    // MARK: - Spreizung: 3-K-Abfang

    /// Spreizung 0 darf nicht durch null teilen. Der Abfang setzt 3 K an.
    /// Von Hand: 6000 · 0,86 / 3 = 1720,0 kg/h
    func testSpreizungNullGreiftAufDreiKelvinZurueck() {
        let r = PumpSizing.calculate(input: PumpSizingInput(),
                                     totalLoadW: 6000, spreadK: 0)
        XCTAssertTrue(r.totalFlowKgPerH.isFinite, "kein inf durch Division durch null")
        XCTAssertFalse(r.totalFlowKgPerH.isNaN)
        XCTAssertEqual(r.totalFlowKgPerH, 1720.0, accuracy: 0.001)
        XCTAssertEqual(r.totalFlowCubicMPerH, 1.72, accuracy: 0.0001)
    }

    /// Negative Spreizung darf keinen negativen Volumenstrom erzeugen.
    func testNegativeSpreizungGreiftEbenfallsAufDreiKelvin() {
        let negativ = PumpSizing.totalFlowKgPerH(totalLoadW: 6000, spreadK: -12)
        let bei3K = PumpSizing.totalFlowKgPerH(totalLoadW: 6000, spreadK: 3)
        XCTAssertEqual(negativ, bei3K, accuracy: 1e-9)
        XCTAssertEqual(negativ, 1720.0, accuracy: 0.001)
        XCTAssertGreaterThan(negativ, 0)
    }

    /// Oberhalb von 3 K greift der Abfang nicht mehr – sonst wäre jede
    /// Auslegung auf 3 K eingefroren.
    func testSpreizungOberhalbDerGrenzeWirdNichtVeraendert() {
        // 6000 · 0,86 / 4 = 1290,0 kg/h
        XCTAssertEqual(PumpSizing.totalFlowKgPerH(totalLoadW: 6000, spreadK: 4),
                       1290.0, accuracy: 0.001)
        XCTAssertLessThan(PumpSizing.totalFlowKgPerH(totalLoadW: 6000, spreadK: 4),
                          PumpSizing.totalFlowKgPerH(totalLoadW: 6000, spreadK: 3))
    }

    /// Negative Heizlast (Eingabefehler) → kein negativer Volumenstrom.
    func testNegativeHeizlastLiefertNull() {
        XCTAssertEqual(PumpSizing.totalFlowKgPerH(totalLoadW: -5000, spreadK: 10),
                       0, accuracy: 1e-12)
        let r = PumpSizing.calculate(input: PumpSizingInput(),
                                     totalLoadW: -5000, spreadK: 10)
        XCTAssertEqual(r.totalFlowKgPerH, 0, accuracy: 1e-12)
        XCTAssertEqual(r.totalFlowCubicMPerH, 0, accuracy: 1e-12)
    }

    // MARK: - Pumpengrenze: Grenzwert exakt

    /// Der Grenzwert wird exakt getroffen, damit „> Grenze" nicht versehentlich
    /// zu „>= Grenze" wird.
    ///
    /// Konstruktion: fester Anteil 0, Rohranteil = 58.860 Pa · 1 · 1.
    /// 58.860 / 9.810 = exakt 6,0 m (beide Zahlen sind als Double exakt
    /// darstellbar, die IEEE-Division liefert hier exakt 6,0).
    func testWarnungGreiftGenauUeberDerGrenzeNichtDarauf() {
        func hoehe(_ pa: Double) -> PumpSizingResult {
            PumpSizing.calculate(
                input: PumpSizingInput(longestCircuitM: pa,
                                       specificLossPaPerM: 1,
                                       singleResistanceFactor: 1,
                                       valveDpMbar: 0,
                                       generatorDpMbar: 0,
                                       extraDpMbar: 0),
                totalLoadW: 8000, spreadK: 10)
        }

        let genauAufDerGrenze = hoehe(58_860)
        XCTAssertEqual(genauAufDerGrenze.headM, 6.0, accuracy: 0,
                       "58.860 / 9.810 muss exakt 6,0 ergeben")
        XCTAssertNil(genauAufDerGrenze.warning,
                     "genau 6,0 m ist noch keine Überschreitung")

        let knappDarunter = hoehe(58_859)
        XCTAssertLessThan(knappDarunter.headM, 6.0)
        XCTAssertNil(knappDarunter.warning)

        let knappDarueber = hoehe(58_861)
        XCTAssertGreaterThan(knappDarueber.headM, 6.0)
        XCTAssertNotNil(knappDarueber.warning,
                        "ab der ersten Überschreitung muss gewarnt werden")
    }

    /// Der Warntext muss die Förderhöhe und die Grenze benennen – der Text geht
    /// so in den Bericht und muss ohne Rückfrage verständlich sein.
    func testWarntextNenntFoerderhoeheUndGrenze() {
        let r = PumpSizing.calculate(
            input: PumpSizingInput(longestCircuitM: 200,
                                   specificLossPaPerM: 300,
                                   singleResistanceFactor: 1.5,
                                   valveDpMbar: 100,
                                   generatorDpMbar: 300,
                                   extraDpMbar: 100),
            totalLoadW: 12_000, spreadK: 5)
        // 200 · 300 · 1,5 = 90.000 Pa; (100 + 300 + 100) mbar = 50.000 Pa
        // Summe 140.000 Pa / 9.810 = 14,27 m → weit über der Grenze.
        XCTAssertEqual(r.totalPa, 140_000, accuracy: 0.001)
        XCTAssertEqual(r.headM, 14.271, accuracy: 0.001)
        XCTAssertNotNil(r.warning)
        let text = r.warning ?? ""
        XCTAssertTrue(text.contains("Förderhöhe"), "Warntext: \(text)")
        XCTAssertTrue(text.contains("Hocheffizienzpumpen"), "Warntext: \(text)")
    }

    // MARK: - Eingabe-Robustheit (Klemmung)

    /// Unsinnige Eingaben dürfen keine negativen Druckverluste erzeugen.
    func testNegativeEingabenWerdenGeklemmt() {
        let r = PumpSizing.calculate(
            input: PumpSizingInput(longestCircuitM: -50,
                                   specificLossPaPerM: -100,
                                   singleResistanceFactor: 0.4,
                                   valveDpMbar: -100,
                                   generatorDpMbar: -150,
                                   extraDpMbar: -10),
            totalLoadW: 8000, spreadK: 10)

        XCTAssertEqual(r.pipeLossPa, 0, accuracy: 1e-12, "Länge und Pa/m auf 0 geklemmt")
        XCTAssertEqual(r.fixedLossPa, 0, accuracy: 1e-12, "mbar-Anteile auf 0 geklemmt")
        XCTAssertEqual(r.totalPa, 0, accuracy: 1e-12)
        XCTAssertEqual(r.headM, 0, accuracy: 1e-12)
        XCTAssertNil(r.warning)
    }

    /// Ein Zuschlagsfaktor unter 1 wäre physikalisch unmöglich (er würde die
    /// reine Rohrreibung verkleinern) und wird auf 1,0 angehoben.
    func testZuschlagsfaktorUnterEinsWirdAufEinsAngehoben() {
        let geklemmt = PumpSizing.calculate(input: PumpSizingInput(singleResistanceFactor: 0.5),
                                            totalLoadW: 8000, spreadK: 10)
        let faktorEins = PumpSizing.calculate(input: PumpSizingInput(singleResistanceFactor: 1.0),
                                              totalLoadW: 8000, spreadK: 10)
        // 50 · 100 · 1,0 = 5.000 Pa – nicht 2.500 Pa.
        XCTAssertEqual(geklemmt.pipeLossPa, 5000, accuracy: 0.001)
        XCTAssertEqual(geklemmt.pipeLossPa, faktorEins.pipeLossPa, accuracy: 1e-12)
    }

    // MARK: - Codable

    /// Leeres JSON → alle Vorgaben. Fängt einen vergessenen Fallback in
    /// `init(from:)` (dann würde der Decode werfen statt die Vorgabe zu setzen).
    func testDecodeOhneSchluesselLiefertVorgaben() throws {
        let decoded = try JSONDecoder().decode(PumpSizingInput.self,
                                               from: "{}".data(using: .utf8)!)
        XCTAssertEqual(decoded.longestCircuitM, 50, accuracy: 0.001)
        XCTAssertEqual(decoded.specificLossPaPerM, 100, accuracy: 0.001)
        XCTAssertEqual(decoded.singleResistanceFactor, 1.3, accuracy: 0.001)
        XCTAssertEqual(decoded.valveDpMbar, 100, accuracy: 0.001)
        XCTAssertEqual(decoded.generatorDpMbar, 150, accuracy: 0.001)
        XCTAssertEqual(decoded.extraDpMbar, 0, accuracy: 0.001)
        XCTAssertEqual(decoded, PumpSizingInput(),
                       "leeres JSON muss dem Standard-Initialisierer entsprechen")
    }

    /// Alte Datei mit nur einem Teil der Schlüssel: gesetzte Werte bleiben,
    /// fehlende fallen auf die Vorgabe.
    func testDecodeMitTeilweisenSchluesseln() throws {
        let json = """
        {"longestCircuitM":72,"generatorDpMbar":250}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PumpSizingInput.self, from: json)
        XCTAssertEqual(decoded.longestCircuitM, 72, accuracy: 0.001)
        XCTAssertEqual(decoded.generatorDpMbar, 250, accuracy: 0.001)
        XCTAssertEqual(decoded.specificLossPaPerM, 100, accuracy: 0.001, "Vorgabe greift")
        XCTAssertEqual(decoded.singleResistanceFactor, 1.3, accuracy: 0.001, "Vorgabe greift")
        XCTAssertEqual(decoded.valveDpMbar, 100, accuracy: 0.001, "Vorgabe greift")
        XCTAssertEqual(decoded.extraDpMbar, 0, accuracy: 0.001, "Vorgabe greift")
    }

    /// Einzelner entfernter Schlüssel aus einer sonst vollständigen Datei.
    func testDecodeMitEntferntemEinzelschluessel() throws {
        let original = PumpSizingInput(longestCircuitM: 65,
                                       specificLossPaPerM: 120,
                                       singleResistanceFactor: 1.7,
                                       valveDpMbar: 100,
                                       generatorDpMbar: 220,
                                       extraDpMbar: 40)
        var dict = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(original)) as! [String: Any]
        dict.removeValue(forKey: "singleResistanceFactor")
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(PumpSizingInput.self, from: data)

        XCTAssertEqual(decoded.singleResistanceFactor, 1.3, accuracy: 0.001, "Vorgabe greift")
        XCTAssertEqual(decoded.longestCircuitM, 65, accuracy: 0.001)
        XCTAssertEqual(decoded.generatorDpMbar, 220, accuracy: 0.001)
        XCTAssertEqual(decoded.extraDpMbar, 40, accuracy: 0.001)
    }

    /// Round-Trip: encodieren und wieder einlesen darf nichts verändern.
    func testCodableRoundTrip() throws {
        let original = PumpSizingInput(longestCircuitM: 84.5,
                                       specificLossPaPerM: 90,
                                       singleResistanceFactor: 1.55,
                                       valveDpMbar: 100,
                                       generatorDpMbar: 275,
                                       extraDpMbar: 65)
        let decoded = try JSONDecoder().decode(PumpSizingInput.self,
                                               from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)

        // Und die Rechnung muss danach dieselbe Zahl liefern wie vorher.
        let vorher = PumpSizing.calculate(input: original, totalLoadW: 9000, spreadK: 7)
        let nachher = PumpSizing.calculate(input: decoded, totalLoadW: 9000, spreadK: 7)
        XCTAssertEqual(nachher.totalPa, vorher.totalPa, accuracy: 1e-9)
        XCTAssertEqual(nachher.headM, vorher.headM, accuracy: 1e-9)
    }

    /// Falscher Werttyp (String statt Zahl, z. B. aus einem Fremdexport) darf
    /// die Datei nicht unlesbar machen – der Fallback greift.
    func testDecodeMitFalschemWerttypNutztVorgabe() throws {
        let json = """
        {"longestCircuitM":"sechzig","valveDpMbar":100}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PumpSizingInput.self, from: json)
        XCTAssertEqual(decoded.longestCircuitM, 50, accuracy: 0.001,
                       "unlesbarer Wert fällt auf die Vorgabe zurück")
        XCTAssertEqual(decoded.valveDpMbar, 100, accuracy: 0.001)
    }
}
