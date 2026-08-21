import XCTest
@testable import KuehllastCore

/// Tests für die Aufbereitung der VdZ-Unterlage.
///
/// Warum hier besonders scharf geprüft wird: Diese Zahlen wandern in ein
/// Formular, das der Fachbetrieb unterschreibt, und die Angaben sind
/// subventionserheblich. Ein stiller Rechenfehler wäre teurer als ein
/// abgestürzter Bildschirm.
final class VdZReportTests: XCTestCase {

    /// Zwei Räume, beide mit Heizkörper, plus ein Raum mit Fußbodenheizung.
    private func beispielRaeume() -> [Room] {
        let wand = Wall(width: 6, height: 2.5, isExternal: true, uValue: 1.0)
        let heizung = HeatingParameters(indoorTemperature: 20, climateName: "Berlin",
                                        thermalBridgePercent: 0, airChangeRate: 0)

        var wohnen = Room(name: "Wohnzimmer", floorArea: 25, height: 2.5,
                          walls: [wand], heating: heizung)
        wohnen.storey = 0
        wohnen.radiators = [Radiator(type: .typ22, widthM: 1.0, heightM: 0.6)]

        var bad = Room(name: "Bad", floorArea: 8, height: 2.5,
                       walls: [wand], heating: heizung)
        bad.storey = 1
        bad.radiators = [Radiator(type: .typ11, widthM: 0.6, heightM: 0.6)]

        var kueche = Room(name: "Küche", floorArea: 12, height: 2.5,
                          walls: [wand], heating: heizung)
        kueche.storey = 0
        kueche.underfloorLoops = [UnderfloorLoop(roomID: kueche.id, name: "FBH 1", areaSqm: 12)]

        return [wohnen, bad, kueche]
    }

    // MARK: - Struktur des Formulars

    func testHeizkoerperUndFussbodenWerdenGetrennteKreise() {
        // Das VdZ-Formular kreuzt je Heizkreis die Systemart an. Heizkörper
        // und Fußboden laufen mit verschiedenen Temperaturen – sie dürfen
        // niemals in einer Zeile landen.
        let report = VdZReportBuilder.build(rooms: beispielRaeume(), settings: BuildingSettings())

        XCTAssertEqual(report.circuits.count, 2)
        let zweirohr = report.circuits.first { $0.kind == .zweirohr }
        let fussboden = report.circuits.first { $0.kind == .fussboden }
        XCTAssertNotNil(zweirohr)
        XCTAssertNotNil(fussboden)
        XCTAssertEqual(zweirohr?.flowTemp ?? 0, 55, accuracy: 0.001)
        XCTAssertEqual(fussboden?.flowTemp ?? 0, 40, accuracy: 0.001,
                       "Fußboden muss die eigene, niedrigere Vorlauftemperatur führen")
        XCTAssertEqual(zweirohr?.surfaceCount, 2)
        XCTAssertEqual(fussboden?.surfaceCount, 1)
    }

    func testFormularFasstNurDreiKreise() {
        // Reine Absicherung der Annahme: mit Heizkörper + Fußboden bleiben
        // wir unter der Formulargrenze. Kommt je ein Kreis dazu, muss der
        // Hinweis greifen.
        let report = VdZReportBuilder.build(rooms: beispielRaeume(), settings: BuildingSettings())
        XCTAssertLessThanOrEqual(report.circuits.count, 3)
    }

    // MARK: - Zahlenkonsistenz (der teuerste Fehler)

    func testGesamtdurchflussIstSummeDerHeizflaechen() {
        // Das Formular verlangt den Gesamtdurchfluss je Kreis, die Anlage
        // die Einzelwerte. Weichen sie ab, fällt es dem Prüfer sofort auf.
        let settings = BuildingSettings()
        let report = VdZReportBuilder.build(rooms: beispielRaeume(), settings: settings)

        for circuit in report.circuits {
            let summe = report.surfaces
                .filter { $0.kind == circuit.kind }
                .reduce(0.0) { $0 + $1.flowLPerH }
            XCTAssertEqual(circuit.totalFlowLPerH, summe, accuracy: 1e-9,
                           "Kreis \(circuit.kind.label): Formularwert ≠ Summe der Anlage")
        }
    }

    func testRaumlisteEnthaeltJedenRaumGenauEinmal() {
        let raeume = beispielRaeume()
        let report = VdZReportBuilder.build(rooms: raeume, settings: BuildingSettings())
        XCTAssertEqual(report.rooms.count, raeume.count)
        XCTAssertEqual(Set(report.rooms.map(\.name)), Set(raeume.map(\.name)))
    }

    func testGebaeudelastIstSummeDerRaumlasten() {
        let report = VdZReportBuilder.build(rooms: beispielRaeume(), settings: BuildingSettings())
        let summe = report.rooms.reduce(0.0) { $0 + $1.loadW }
        XCTAssertEqual(report.totalLoadW, summe, accuracy: 1e-9)
        XCTAssertGreaterThan(report.totalLoadW, 0)
    }

    func testHeizkoerperlastWirdAnteiligNachNormleistungVerteilt() {
        // Ein Raum, zwei ungleiche Heizkörper: die Aufteilung muss dem
        // Verhältnis der Normleistungen folgen und in Summe die Raumlast
        // ergeben – sonst stimmt die Anlage nicht mit der Heizlast überein.
        let wand = Wall(width: 6, height: 2.5, isExternal: true, uValue: 1.0)
        var raum = Room(name: "Wohnen", floorArea: 25, height: 2.5, walls: [wand],
                        heating: HeatingParameters(indoorTemperature: 20, climateName: "Berlin",
                                                   thermalBridgePercent: 0, airChangeRate: 0))
        let gross = Radiator(type: .typ22, widthM: 1.6, heightM: 0.6)   // Norm 1632 W
        let klein = Radiator(type: .typ11, widthM: 0.4, heightM: 0.6)   // Norm  252 W
        raum.radiators = [gross, klein]

        let report = VdZReportBuilder.build(rooms: [raum], settings: BuildingSettings())
        let flaechen = report.surfaces.filter { $0.kind == .zweirohr }
        XCTAssertEqual(flaechen.count, 2)

        let raumlast = report.rooms[0].loadW
        XCTAssertEqual(flaechen.reduce(0.0) { $0 + $1.loadW }, raumlast, accuracy: 1e-9,
                       "Die Summe der Heizflächen muss die Raumlast ergeben")

        let verhaeltnis = flaechen[0].loadW / flaechen[1].loadW
        XCTAssertEqual(verhaeltnis, gross.normPower / klein.normPower, accuracy: 1e-6)
    }

    // MARK: - Ventilangaben

    func testVoreinstellwertErscheintNurMitGewaehltemFabrikat() {
        var ohne = BuildingSettings()
        ohne.valveModelID = nil
        let reportOhne = VdZReportBuilder.build(rooms: beispielRaeume(), settings: ohne)
        XCTAssertTrue(reportOhne.surfaces.filter { $0.kind == .zweirohr }
                        .allSatisfy { $0.valveSetting == nil })
        XCTAssertTrue(reportOhne.hints.contains { $0.contains("Ventilfabrikat") })

        guard let modell = ValveDatabase.all.first else {
            return XCTFail("Ventil-Datenbank ist leer")
        }
        var mit = BuildingSettings()
        mit.valveModelID = modell.id
        let reportMit = VdZReportBuilder.build(rooms: beispielRaeume(), settings: mit)
        let heizkoerper = reportMit.surfaces.filter { $0.kind == .zweirohr }
        XCTAssertFalse(heizkoerper.isEmpty)
        XCTAssertTrue(heizkoerper.allSatisfy { $0.valveSetting != nil })
        XCTAssertTrue(heizkoerper.allSatisfy { $0.valveName == modell.displayName })
        XCTAssertTrue(heizkoerper.allSatisfy { $0.valveDpMbar != nil },
                      "Druckverlust je Ventil verlangt die VdZ-Fachregel Kap. 8")
    }

    // MARK: - Vollständigkeitsprüfung

    func testRaumOhneHeizflaecheWirdGemeldet() {
        var raeume = beispielRaeume()
        var flur = Room(name: "Flur", floorArea: 6, height: 2.5)
        flur.storey = 0
        raeume.append(flur)

        let report = VdZReportBuilder.build(rooms: raeume, settings: BuildingSettings())
        XCTAssertEqual(report.roomsWithoutSurface, ["Flur"])
        XCTAssertTrue(report.hints.contains { $0.contains("Flur") })
        XCTAssertEqual(report.rooms.count, 4, "der Raum fehlt in der Anlage, nicht in der Heizlast")
    }

    func testFehlendePflichtangabenWerdenGemeldet() {
        let report = VdZReportBuilder.build(rooms: beispielRaeume(), settings: BuildingSettings())
        XCTAssertTrue(report.hints.contains { $0.contains("Ausdehnungsgefäß") })
        XCTAssertTrue(report.hints.contains { $0.contains("Wärmeerzeugers") })
        XCTAssertTrue(report.hints.contains { $0.contains("Heizkurve") })
    }

    // MARK: - Vollständigkeit des Gebäudes (Förderrisiko!)

    func testFehlenderRaumFaelltUeberDieWohnflaecheAuf() {
        // 25 + 8 + 12 = 45 m² erfasst, laut Unterlagen hat das Haus 120 m².
        // Ohne diese Prüfung ginge eine viel zu kleine Gebäudeheizlast in
        // die Förderunterlage.
        var settings = BuildingSettings()
        settings.vdz.totalLivingAreaSqm = 120
        let report = VdZReportBuilder.build(rooms: beispielRaeume(), settings: settings)

        XCTAssertEqual(report.capturedAreaSqm, 45, accuracy: 0.001)
        XCTAssertEqual(report.areaDeviation ?? 0, 0.625, accuracy: 0.001)
        XCTAssertTrue(report.hints.contains { $0.contains("fehlt ein Raum") })
    }

    func testPassendeWohnflaecheErzeugtKeineMahnung() {
        var settings = BuildingSettings()
        settings.vdz.totalLivingAreaSqm = 46   // 45 erfasst → 2,2 % Abweichung
        let report = VdZReportBuilder.build(rooms: beispielRaeume(), settings: settings)
        XCTAssertLessThan(report.areaDeviation ?? 1, 0.10)
        XCTAssertFalse(report.hints.contains { $0.contains("fehlt ein Raum") })
    }

    func testOhneWohnflaecheWirdZurAngabeAufgefordert() {
        let report = VdZReportBuilder.build(rooms: beispielRaeume(), settings: BuildingSettings())
        XCTAssertNil(report.areaDeviation)
        XCTAssertTrue(report.hints.contains { $0.contains("Wohnfläche") })
    }

    func testVollstaendigeAngabenErzeugenKeineMahnung() {
        var settings = BuildingSettings()
        settings.valveModelID = ValveDatabase.all.first?.id
        settings.vdz = VdZInputs(expansionVesselChecked: true,
                                 fillPressureBar: 1.8,
                                 generatorSetPowerKW: 8,
                                 heatingCurveNote: "Steigung 0,4 / Niveau 0",
                                 totalLivingAreaSqm: 45)
        var raeume = beispielRaeume()
        // Alle Räume mit Heizfläche versehen – dann darf nichts mehr mahnen.
        raeume[2].underfloorLoops = [UnderfloorLoop(roomID: raeume[2].id, areaSqm: 12)]

        let report = VdZReportBuilder.build(rooms: raeume, settings: settings)
        XCTAssertTrue(report.hints.isEmpty, "Übrige Hinweise: \(report.hints)")
    }

    // MARK: - Geschossbezeichnung

    func testGeschossbezeichnung() {
        XCTAssertEqual(VdZReportBuilder.storeyLabel(-1), "KG")
        XCTAssertEqual(VdZReportBuilder.storeyLabel(0), "EG")
        XCTAssertEqual(VdZReportBuilder.storeyLabel(1), "1. OG")
        XCTAssertEqual(VdZReportBuilder.storeyLabel(4), "DG")
        XCTAssertEqual(VdZReportBuilder.storeyLabel(nil), "")
    }

    // MARK: - Robustheit

    func testLeeresGebaeudeStuerztNicht() {
        let report = VdZReportBuilder.build(rooms: [], settings: BuildingSettings())
        XCTAssertTrue(report.circuits.isEmpty)
        XCTAssertTrue(report.rooms.isEmpty)
        XCTAssertEqual(report.totalLoadW, 0, accuracy: 0.001)
    }

    func testVdZEingabenBleibenBeimSpeichernErhalten() throws {
        var settings = BuildingSettings()
        settings.vdz = VdZInputs(expansionVesselChecked: true, fillPressureBar: 1.8,
                                 vesselPrePressureBar: 1.2, vesselEndPressureBar: 2.5,
                                 differentialPressureController: true, flowController: true,
                                 generatorSetPowerKW: 9.5, heatingCurveNote: "0,4 / 0",
                                 remarks: "Fernwärme direkt")
        let decoded = try JSONDecoder().decode(BuildingSettings.self,
                                               from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.vdz.expansionVesselChecked)
        XCTAssertEqual(decoded.vdz.fillPressureBar, 1.8, accuracy: 0.001)
        XCTAssertEqual(decoded.vdz.generatorSetPowerKW, 9.5, accuracy: 0.001)
        XCTAssertEqual(decoded.vdz.heatingCurveNote, "0,4 / 0")
        XCTAssertEqual(decoded.pump.longestCircuitM, settings.pump.longestCircuitM, accuracy: 0.001)
    }

    func testAlteEinstellungsdateiOhneVdZBleibtLesbar() throws {
        let json = """
        {"dhwPersons":3,"flowTemp":55,"returnTemp":45,"spreadK":10,"simultaneity":0.8}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BuildingSettings.self, from: json)
        XCTAssertFalse(decoded.vdz.expansionVesselChecked)
        XCTAssertEqual(decoded.pump.specificLossPaPerM, 100, accuracy: 0.001)
    }
}
