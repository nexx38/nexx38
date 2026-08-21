import XCTest
import Foundation
@testable import KuehllastCore

/// Tests für den Fußbodenheizungs-Rechenkern: Wärmeabgabe, Deckungsprüfung,
/// erforderliche Vorlauftemperatur, Kreislänge/Volumenstrom und Randfälle.
///
/// Die Zahlenbeispiele sind im Kommentar von Hand nachgerechnet – wer die
/// Formel später anfasst, sieht sofort, ob der neue Wert plausibel ist.
final class UnderfloorHeatingTests: XCTestCase {

    /// Fester Raum für alle Kreise der Tests.
    private let roomID = UUID()

    private func loop(area: Double,
                      spacing: PipeSpacing = .va15,
                      covering: FloorCovering = .fliesen,
                      pipe: PipeType = .pex16x2,
                      connection: Double = 5,
                      flowOverride: Double? = nil,
                      maxSurface: Double = 29) -> UnderfloorLoop {
        UnderfloorLoop(roomID: roomID, name: "HK 1", areaSqm: area,
                       spacing: spacing, pipe: pipe, covering: covering,
                       flowTempOverride: flowOverride,
                       connectionLengthM: connection,
                       maxSurfaceTemp: maxSurface)
    }

    // MARK: - Wärmeabgabe: Monotonie

    /// Fängt vertauschte Formelglieder: q muss mit der Übertemperatur steigen
    /// (linear) – ein Vorzeichen- oder Kehrwertfehler dreht das sofort um.
    func testOutputRisesWithOverTemperature() {
        var previous = -1.0
        for over in stride(from: 2.0, through: 30.0, by: 2.0) {
            let q = UnderfloorHeating.outputPerSqm(overTemp: over,
                                                   spacing: .va15,
                                                   coveringResistance: 0)
            XCTAssertGreaterThan(q, previous, "q muss mit ΔΘ_H steigen (ΔΘ_H = \(over))")
            previous = q
        }
    }

    /// Fängt eine vertauschte K_H0-Tabelle: enger Verlegeabstand = mehr Rohr
    /// je m² = mehr Leistung. Größerer Abstand muss weniger liefern.
    func testOutputFallsWithWiderSpacing() {
        let ordered = PipeSpacing.allCases.sorted { $0.spacingM < $1.spacingM }
        XCTAssertEqual(ordered.count, 5)
        var previous = Double.greatestFiniteMagnitude
        for spacing in ordered {
            let q = UnderfloorHeating.outputPerSqm(overTemp: 12,
                                                   spacing: spacing,
                                                   coveringResistance: 0)
            XCTAssertLessThan(q, previous, "größerer VA muss weniger liefern (\(spacing.label))")
            previous = q
        }
    }

    /// Fängt ein falsches Vorzeichen beim Belag-Widerstand: der Belag ist ein
    /// zusätzlicher Widerstand, er darf die Leistung nur senken.
    func testTilesOutperformCarpet() {
        let over = 12.0
        let fliesen = UnderfloorHeating.outputPerSqm(
            overTemp: over, spacing: .va15,
            coveringResistance: FloorCovering.fliesen.resistance)
        let parkett = UnderfloorHeating.outputPerSqm(
            overTemp: over, spacing: .va15,
            coveringResistance: FloorCovering.parkett.resistance)
        let teppich = UnderfloorHeating.outputPerSqm(
            overTemp: over, spacing: .va15,
            coveringResistance: FloorCovering.teppich.resistance)
        XCTAssertGreaterThan(fliesen, parkett)
        XCTAssertGreaterThan(parkett, teppich)
        // Der Belag ist der größte Hebel: Teppich muss deutlich (>30 %)
        // unter Fliesen liegen, sonst ist R_λ,B nicht wirksam eingerechnet.
        XCTAssertLessThan(teppich, fliesen * 0.7)
    }

    // MARK: - Von Hand nachgerechnetes Zahlenbeispiel

    /// Handrechnung, VA 15 cm, Fliesen, 35/28 °C bei 20 °C Raum:
    ///
    ///   ΔΘ_H = (35 − 28) / ln((35 − 20)/(28 − 20))
    ///        = 7 / ln(15/8) = 7 / 0,628609 = 11,1357 K
    ///   K_H  = 1 / (1/7,4 + 0,00) = 7,4 W/(m²·K)
    ///   q    = 7,4 · 11,1357 = 82,40 W/m²
    ///   20 m² → 1648,1 W
    ///
    /// Mit Parkett (R_λ,B = 0,10):
    ///   K_H = 1 / (0,135135 + 0,10) = 4,2529 W/(m²·K)
    ///   q   = 4,2529 · 11,1357 = 47,36 W/m²
    func testHandCalculatedExample() {
        let over = UnderfloorHeating.logMeanOverTemperature(flow: 35, ret: 28, roomTemp: 20)
        XCTAssertEqual(over, 11.1357, accuracy: 0.001)

        let fliesen = loop(area: 20, spacing: .va15, covering: .fliesen)
        XCTAssertEqual(fliesen.heatTransferCoefficient, 7.4, accuracy: 0.001)
        XCTAssertEqual(fliesen.outputPerSqm(flow: 35, ret: 28, roomTemp: 20),
                       82.404, accuracy: 0.01)
        XCTAssertEqual(fliesen.output(flow: 35, ret: 28, roomTemp: 20),
                       1648.08, accuracy: 0.1)

        let parkett = loop(area: 20, spacing: .va15, covering: .parkett)
        XCTAssertEqual(parkett.heatTransferCoefficient, 4.2529, accuracy: 0.001)
        XCTAssertEqual(parkett.outputPerSqm(flow: 35, ret: 28, roomTemp: 20),
                       47.359, accuracy: 0.01)
    }

    // MARK: - Deckungsprüfung

    /// 20 m², VA 15, Fliesen, 35/28/20 → Kapazität 1648,1 W (siehe Handrechnung).
    /// Deckung: 1600 W → 103 % (ausreichend), 1800 W → 91,6 % (knapp),
    /// 2200 W → 74,9 % (zu klein).
    func testCheckVerdicts() {
        let loops = [loop(area: 20)]
        func verdict(demand: Double) -> RadiatorVerdict {
            UnderfloorHeating.check(loops: loops, demandW: demand,
                                    roomTemp: 20, flowTemp: 35, spreadK: 7).verdict
        }
        XCTAssertEqual(verdict(demand: 1600), .ausreichend)
        XCTAssertEqual(verdict(demand: 1800), .knapp)
        XCTAssertEqual(verdict(demand: 2200), .zuKlein)

        let ok = UnderfloorHeating.check(loops: loops, demandW: 1600,
                                         roomTemp: 20, flowTemp: 35, spreadK: 7)
        XCTAssertEqual(ok.capacity, 1648.08, accuracy: 0.1)
        XCTAssertEqual(ok.activeAreaSqm, 20, accuracy: 0.001)
        XCTAssertEqual(ok.coverage, 1.0301, accuracy: 0.001)
    }

    /// Die Schwellen selbst (100 % / 85 %) – bewusst exakt an der Kante
    /// geprüft, weil sie mit dem Heizkörper-Check geteilt werden.
    func testCheckVerdictThresholdsExactly() {
        func result(capacity: Double) -> UnderfloorCheckResult {
            UnderfloorCheckResult(activeAreaSqm: 10, capacity: capacity, demand: 1000,
                                  roomTemp: 20, maxSurfaceTemp: 29,
                                  requiredFlowTemp: nil, loops: [])
        }
        XCTAssertEqual(result(capacity: 1000).verdict, .ausreichend)
        XCTAssertEqual(result(capacity: 999).verdict, .knapp)
        XCTAssertEqual(result(capacity: 850).verdict, .knapp)
        XCTAssertEqual(result(capacity: 849).verdict, .zuKlein)
    }

    // MARK: - Erforderliche Vorlauftemperatur (Rundlauf)

    /// Rundlauf-Test: die zurückgerechnete Vorlauftemperatur muss, wieder
    /// vorwärts gerechnet, genau die Heizlast decken. Fängt jeden Fehler in
    /// der Umkehrformel θ_V = θ_i + ΔT·E/(E−1).
    ///
    /// Handrechnung: 20 m² · 7,4 = 148 W/K; 1800 W / 148 = 12,1622 K
    /// E = exp(7 / 12,1622) = 1,77809 → θ_V = 20 + 7·1,77809/0,77809 = 36,00 °C
    func testRequiredFlowTempRoundTrip() {
        let loops = [loop(area: 20)]
        let demand = 1800.0
        let first = UnderfloorHeating.check(loops: loops, demandW: demand,
                                            roomTemp: 20, flowTemp: 35, spreadK: 7)
        guard let required = first.requiredFlowTemp else {
            return XCTFail("keine erforderliche Vorlauftemperatur berechnet")
        }
        XCTAssertEqual(required, 35.996, accuracy: 0.01)

        // Vorwärts mit genau dieser Vorlauftemperatur: Deckung muss 100 % sein.
        let second = UnderfloorHeating.check(loops: loops, demandW: demand,
                                             roomTemp: 20, flowTemp: required, spreadK: 7)
        XCTAssertEqual(second.capacity, demand, accuracy: 0.01)
        XCTAssertEqual(second.coverage, 1.0, accuracy: 0.0001)
        XCTAssertEqual(second.verdict, .ausreichend)
    }

    /// Der Rundlauf muss auch bei anderen Belägen, Abständen und Spreizungen
    /// halten – sonst stimmt nur der eine getestete Punkt.
    func testRequiredFlowTempRoundTripAcrossVariants() {
        for spacing in PipeSpacing.allCases {
            for covering in FloorCovering.allCases {
                for spread in [5.0, 7.0, 10.0] {
                    let loops = [loop(area: 18, spacing: spacing, covering: covering)]
                    let demand = 1400.0
                    let r = UnderfloorHeating.check(loops: loops, demandW: demand,
                                                    roomTemp: 21, flowTemp: 35,
                                                    spreadK: spread)
                    guard let required = r.requiredFlowTemp else {
                        XCTFail("keine Vorlauftemperatur für \(spacing) / \(covering)")
                        continue
                    }
                    let back = UnderfloorHeating.check(loops: loops, demandW: demand,
                                                       roomTemp: 21, flowTemp: required,
                                                       spreadK: spread)
                    XCTAssertEqual(back.capacity, demand, accuracy: 0.05,
                                   "Rundlauf \(spacing.label)/\(covering.label)/ΔT \(spread)")
                }
            }
        }
    }

    /// Kreise mit eigener Vorlauftemperatur zählen bei der Kapazität mit
    /// ihrem eigenen Wert – die erforderliche Vorlauftemperatur bleibt davon
    /// bewusst unberührt (dokumentierte Festlegung).
    func testLoopFlowTempOverrideUsedForCapacity() {
        let withOverride = [loop(area: 20, flowOverride: 40)]
        let r = UnderfloorHeating.check(loops: withOverride, demandW: 1800,
                                        roomTemp: 20, flowTemp: 30, spreadK: 7)
        // Mit 40/33 statt 30/23: ΔΘ_H = 7/ln(20/13) = 16,2499 K → 148 · 16,2499
        XCTAssertEqual(r.capacity, 2405.0, accuracy: 0.5)
        XCTAssertEqual(r.loops.first?.flowTemp ?? 0, 40, accuracy: 0.001)
    }

    // MARK: - Rohrlänge und Volumenstrom

    /// 20 m² bei VA 15 cm = 133,3 m + 5 m Anbindung = 138,3 m.
    /// Bei 16 × 2 (Empfehlung 100 m, kritisch 120 m) muss die Warnung
    /// "Kreis teilen" greifen.
    func testPipeLengthAndSplitWarning() {
        let big = loop(area: 20, spacing: .va15, pipe: .pex16x2, connection: 5)
        XCTAssertEqual(big.pipeLengthM, 138.333, accuracy: 0.01)
        XCTAssertEqual(big.lengthVerdict, .zuLang)

        let r = UnderfloorHeating.loopResult(loop: big, roomTemp: 20,
                                             flowTemp: 35, spreadK: 7)
        XCTAssertEqual(r.lengthVerdict, .zuLang)
        XCTAssertTrue(r.warning?.contains("teilen") == true,
                      "Warnung muss zum Teilen auffordern, war: \(r.warning ?? "nil")")
    }

    /// Die drei Stufen der Längenbewertung an ihren Grenzen.
    func testPipeLengthVerdictSteps() {
        // 8 m² bei VA 20 = 40 m + 5 m = 45 m → in Ordnung
        XCTAssertEqual(loop(area: 8, spacing: .va20).lengthVerdict, .ok)
        XCTAssertNil(loop(area: 8, spacing: .va20).lengthVerdict.advice)
        // 15 m² bei VA 15 = 100 m + 5 m = 105 m → zwischen 100 und 120
        let borderline = loop(area: 15, spacing: .va15)
        XCTAssertEqual(borderline.pipeLengthM, 105, accuracy: 0.001)
        XCTAssertEqual(borderline.lengthVerdict, .grenzwertig)
        // Dickeres Rohr verträgt dieselbe Länge problemlos
        XCTAssertEqual(loop(area: 15, spacing: .va15, pipe: .pex20x2).lengthVerdict, .ok)
    }

    /// Volumenstrom m = Q · 0,86 / ΔT und Fließgeschwindigkeit.
    /// 1648,1 W bei 7 K → 202,5 kg/h; bei 12 mm Innendurchmesser → 0,497 m/s.
    func testMassFlowAndVelocity() {
        let r = UnderfloorHeating.loopResult(loop: loop(area: 20), roomTemp: 20,
                                             flowTemp: 35, spreadK: 7)
        XCTAssertEqual(r.outputW, 1648.08, accuracy: 0.1)
        XCTAssertEqual(r.flowKgPerH, 202.48, accuracy: 0.05)
        XCTAssertEqual(r.velocityMPerS, 0.497, accuracy: 0.002)
    }

    // MARK: - Oberflächentemperatur

    /// Basiskennlinie q = 8,92 · (θ_F,m − θ_i)^1,1.
    /// Bei 29 °C Oberfläche und 20 °C Raum ergibt das die bekannten
    /// ~100 W/m² Grenzleistung; 82,4 W/m² führen auf 27,5 °C Oberfläche.
    func testSurfaceTemperatureAndLimit() {
        XCTAssertEqual(UnderfloorHeating.maxOutputPerSqm(roomTemp: 20, maxSurfaceTemp: 29),
                       100.0, accuracy: 0.5)
        XCTAssertEqual(UnderfloorHeating.surfaceTemperature(outputPerSqm: 82.404, roomTemp: 20),
                       27.55, accuracy: 0.05)

        let loops = [loop(area: 20)]
        // 1648 W auf 20 m² = 82,4 W/m² → Oberfläche 27,5 °C → zulässig
        let fine = UnderfloorHeating.check(loops: loops, demandW: 1648,
                                           roomTemp: 20, flowTemp: 35, spreadK: 7)
        XCTAssertFalse(fine.exceedsSurfaceLimit)
        XCTAssertEqual(fine.surfaceTemp, 27.55, accuracy: 0.05)

        // 2400 W auf 20 m² = 120 W/m² → über der 100-W/m²-Grenze
        let tooHot = UnderfloorHeating.check(loops: loops, demandW: 2400,
                                             roomTemp: 20, flowTemp: 35, spreadK: 7)
        XCTAssertTrue(tooHot.exceedsSurfaceLimit)
        XCTAssertEqual(tooHot.requiredOutputPerSqm, 120, accuracy: 0.001)
    }

    /// Im Bad sind 33 °C erlaubt – die strengste Grenze aller Kreise zählt.
    func testBathroomLimitIsHigherAndMostStrictWins() {
        let bath = UnderfloorHeating.check(loops: [loop(area: 6, maxSurface: 33)],
                                           demandW: 660, roomTemp: 24,
                                           flowTemp: 35, spreadK: 7)
        // 660 W / 6 m² = 110 W/m²; Grenze bei 24 °C Raum und 33 °C = 100 W/m²
        XCTAssertTrue(bath.exceedsSurfaceLimit)
        XCTAssertEqual(bath.maxOutputPerSqm, 100.0, accuracy: 0.5)

        let mixed = UnderfloorHeating.check(loops: [loop(area: 6, maxSurface: 33),
                                                    loop(area: 6, maxSurface: 29)],
                                            demandW: 500, roomTemp: 20,
                                            flowTemp: 35, spreadK: 7)
        XCTAssertEqual(mixed.maxOutputPerSqm, 100.0, accuracy: 0.5) // 29 °C gewinnt
    }

    // MARK: - Mehrere Kreise je Raum

    func testTwoLoopsAddUp() {
        let loops = [loop(area: 10, spacing: .va15, covering: .fliesen),
                     loop(area: 10, spacing: .va20, covering: .parkett)]
        let r = UnderfloorHeating.check(loops: loops, demandW: 1200,
                                        roomTemp: 20, flowTemp: 35, spreadK: 7)
        XCTAssertEqual(r.activeAreaSqm, 20, accuracy: 0.001)
        XCTAssertEqual(r.loops.count, 2)
        // 10·7,4·11,1357 + 10·(1/(1/6,5+0,10))·11,1357 = 824,04 + 438,68
        XCTAssertEqual(r.capacity, 1262.72, accuracy: 0.5)
        XCTAssertGreaterThan(r.loops[0].outputW, r.loops[1].outputW)
    }

    // MARK: - Randfälle (kein Absturz, keine Division durch null)

    /// Fläche 0 (oder negativ): keine Leistung, keine erforderliche
    /// Vorlauftemperatur, aber auch kein NaN/Inf.
    func testZeroAreaIsSafe() {
        for area in [0.0, -5.0] {
            let l = loop(area: area)
            XCTAssertEqual(l.activeAreaSqm, 0, accuracy: 0.001)
            XCTAssertEqual(l.pipeLengthM, 5, accuracy: 0.001) // nur Anbindeleitung
            let r = UnderfloorHeating.check(loops: [l], demandW: 1000,
                                            roomTemp: 20, flowTemp: 35, spreadK: 7)
            XCTAssertEqual(r.capacity, 0, accuracy: 0.001)
            XCTAssertNil(r.requiredFlowTemp)
            XCTAssertEqual(r.requiredOutputPerSqm, 0, accuracy: 0.001)
            XCTAssertEqual(r.surfaceTemp, 20, accuracy: 0.001)
            XCTAssertEqual(r.verdict, .zuKlein)
            XCTAssertTrue(r.coverage.isFinite)
            XCTAssertTrue(r.loops[0].flowKgPerH.isFinite)
            XCTAssertTrue(r.loops[0].velocityMPerS.isFinite)
        }
    }

    /// Spreizung 0: das log-Mittel geht in die einfache Übertemperatur über,
    /// der Volumenstrom rechnet ersatzweise mit 1 K statt durch null zu teilen.
    func testZeroSpreadIsSafe() {
        let over = UnderfloorHeating.logMeanOverTemperature(flow: 35, ret: 35, roomTemp: 20)
        XCTAssertEqual(over, 15, accuracy: 0.0001)

        let r = UnderfloorHeating.check(loops: [loop(area: 20)], demandW: 1800,
                                        roomTemp: 20, flowTemp: 35, spreadK: 0)
        XCTAssertEqual(r.capacity, 2220, accuracy: 0.1)   // 148 W/K · 15 K
        XCTAssertTrue(r.capacity.isFinite)
        XCTAssertTrue(r.loops[0].flowKgPerH.isFinite)
        XCTAssertTrue(r.loops[0].velocityMPerS.isFinite)
        // 1800 / 148 = 12,1622 K → bei ΔT = 0 direkt 20 + 12,1622 °C
        XCTAssertEqual(r.requiredFlowTemp ?? .nan, 32.162, accuracy: 0.01)

        XCTAssertEqual(UnderfloorHeating.massFlowKgPerH(outputW: 1000, spreadK: 0),
                       860, accuracy: 0.001)             // Ersatzspreizung 1 K
        XCTAssertEqual(UnderfloorHeating.massFlowKgPerH(outputW: 0, spreadK: 0),
                       0, accuracy: 0.0001)
    }

    /// Übertemperatur ≤ 0: Vorlauf unter Raumtemperatur oder Rücklauf unter
    /// Raumtemperatur → keine Wärmeabgabe, kein negativer Wert.
    func testNonPositiveOverTemperatureGivesZero() {
        XCTAssertEqual(UnderfloorHeating.logMeanOverTemperature(flow: 18, ret: 16, roomTemp: 20),
                       0, accuracy: 0.0001)
        XCTAssertEqual(UnderfloorHeating.logMeanOverTemperature(flow: 20, ret: 20, roomTemp: 20),
                       0, accuracy: 0.0001)
        XCTAssertEqual(UnderfloorHeating.logMeanOverTemperature(flow: 35, ret: 15, roomTemp: 20),
                       0, accuracy: 0.0001)
        XCTAssertEqual(UnderfloorHeating.outputPerSqm(overTemp: 0, spacing: .va15,
                                                      coveringResistance: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(UnderfloorHeating.outputPerSqm(overTemp: -5, spacing: .va15,
                                                      coveringResistance: 0), 0, accuracy: 0.0001)

        let r = UnderfloorHeating.check(loops: [loop(area: 20)], demandW: 1800,
                                        roomTemp: 20, flowTemp: 18, spreadK: 7)
        XCTAssertEqual(r.capacity, 0, accuracy: 0.001)
        XCTAssertEqual(r.verdict, .zuKlein)
        XCTAssertTrue(r.coverage.isFinite)
    }

    /// Weitere Grenzwerte der Hilfsfunktionen.
    func testHelperEdgeCases() {
        // Keine Heizlast → keine erforderliche Vorlauftemperatur nötig
        let none = UnderfloorHeating.check(loops: [loop(area: 20)], demandW: 0,
                                           roomTemp: 20, flowTemp: 35, spreadK: 7)
        XCTAssertNil(none.requiredFlowTemp)
        XCTAssertEqual(none.coverage, 1, accuracy: 0.001) // wie beim Heizkörper-Check
        XCTAssertEqual(none.verdict, .ausreichend)

        // Gar keine Kreise
        let empty = UnderfloorHeating.check(loops: [], demandW: 1000,
                                            roomTemp: 20, flowTemp: 35, spreadK: 7)
        XCTAssertEqual(empty.capacity, 0, accuracy: 0.001)
        XCTAssertNil(empty.requiredFlowTemp)
        XCTAssertTrue(empty.loops.isEmpty)
        XCTAssertEqual(empty.maxOutputPerSqm, 100.0, accuracy: 0.5) // Rückfall 29 °C

        // Oberflächengrenze unter Raumtemperatur → 0 statt NaN
        XCTAssertEqual(UnderfloorHeating.maxOutputPerSqm(roomTemp: 24, maxSurfaceTemp: 22),
                       0, accuracy: 0.0001)
        XCTAssertEqual(UnderfloorHeating.surfaceTemperature(outputPerSqm: 0, roomTemp: 22),
                       22, accuracy: 0.0001)

        // Umkehrformel: Übertemperatur 0 → Raumtemperatur; winzige
        // Übertemperatur bei großer Spreizung darf nicht überlaufen.
        XCTAssertEqual(UnderfloorHeating.requiredFlowTemp(overTemp: 0, spreadK: 7, roomTemp: 20),
                       20, accuracy: 0.0001)
        let extreme = UnderfloorHeating.requiredFlowTemp(overTemp: 0.001, spreadK: 7, roomTemp: 20)
        XCTAssertTrue(extreme.isFinite)
        XCTAssertEqual(extreme, 27, accuracy: 0.001)

        // Geschwindigkeit ohne Durchmesser / ohne Durchfluss
        XCTAssertEqual(UnderfloorHeating.velocityMPerS(flowKgPerH: 200, innerDiameterMM: 0),
                       0, accuracy: 0.0001)
        XCTAssertEqual(UnderfloorHeating.velocityMPerS(flowKgPerH: 0, innerDiameterMM: 12),
                       0, accuracy: 0.0001)

        // Negativer Belag-Widerstand darf K_H nicht über den Grundwert heben
        XCTAssertEqual(UnderfloorHeating.heatTransferCoefficient(spacing: .va15,
                                                                 coveringResistance: -1),
                       7.4, accuracy: 0.001)
    }

    // MARK: - Stammdaten und Codable

    func testHeatingSurfaceKind() {
        XCTAssertEqual(HeatingSurfaceKind.allCases.count, 2)
        XCTAssertEqual(HeatingSurfaceKind.underfloor.label, "Fußbodenheizung")
        XCTAssertEqual(HeatingSurfaceKind(rawValue: "radiator"), .radiator)
    }

    func testPipeTypeLengthLimits() {
        XCTAssertEqual(PipeType.pex16x2.innerDiameterMM, 12, accuracy: 0.001)
        XCTAssertEqual(PipeType.pex16x2.recommendedMaxLengthM, 100, accuracy: 0.001)
        XCTAssertEqual(PipeType.pex16x2.criticalLengthM, 120, accuracy: 0.001)
        for pipe in PipeType.allCases {
            XCTAssertGreaterThan(pipe.criticalLengthM, pipe.recommendedMaxLengthM)
            XCTAssertGreaterThan(pipe.innerDiameterMM, 0)
        }
    }

    /// Nachsichtiges Dekodieren wie bei Radiator: fehlende Felder fallen auf
    /// die Vorgaben zurück, damit ältere Dateien weiter laden.
    func testLoopDecodesWithMissingOptionalKeys() throws {
        let original = loop(area: 12, spacing: .va20, covering: .parkett,
                            pipe: .pex20x2, connection: 4, maxSurface: 33)
        var dict = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(original)) as! [String: Any]
        for key in ["name", "spacing", "pipe", "covering",
                    "connectionLengthM", "maxSurfaceTemp"] {
            dict.removeValue(forKey: key)
        }
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(UnderfloorLoop.self, from: data)

        XCTAssertEqual(decoded.roomID, roomID)
        XCTAssertEqual(decoded.areaSqm, 12, accuracy: 0.001)
        XCTAssertEqual(decoded.name, "HK 1")
        XCTAssertEqual(decoded.spacing, .va15)
        XCTAssertEqual(decoded.pipe, .pex16x2)
        XCTAssertEqual(decoded.covering, .fliesen)
        XCTAssertEqual(decoded.connectionLengthM, 5, accuracy: 0.001)
        XCTAssertEqual(decoded.maxSurfaceTemp, 29, accuracy: 0.001)
        XCTAssertNil(decoded.flowTempOverride)
        XCTAssertNil(decoded.coveringResistanceOverride)
    }

    func testLoopRoundTripsThroughCodable() throws {
        let original = loop(area: 14.5, spacing: .va25, covering: .teppich,
                            pipe: .verbund20x2, connection: 3.5,
                            flowOverride: 38, maxSurface: 33)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UnderfloorLoop.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// Ein eigener Belag-Widerstand schlägt die Vorgabe des Belags.
    func testCoveringResistanceOverride() {
        var l = loop(area: 10, covering: .teppich)
        XCTAssertEqual(l.coveringResistance, 0.15, accuracy: 0.001)
        l.coveringResistanceOverride = 0.02
        XCTAssertEqual(l.coveringResistance, 0.02, accuracy: 0.001)
        XCTAssertEqual(l.heatTransferCoefficient,
                       1.0 / (1.0 / 7.4 + 0.02), accuracy: 0.0001)
    }
}
