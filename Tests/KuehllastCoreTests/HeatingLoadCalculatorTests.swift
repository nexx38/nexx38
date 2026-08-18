import XCTest
@testable import KuehllastCore

final class HeatingLoadCalculatorTests: XCTestCase {

    private let calc = HeatingLoadCalculator()

    // MARK: - Einzelposten

    func testTransmissionExternalWallOnly() {
        // Außenwand 10 m², U = 1.0, Berlin θ_e = −14, θ_i = 20 → ΔT = 34
        // 10 · 1.0 · 34 = 340 W. Innenwand zählt nicht.
        let outer = Wall(width: 5, height: 2, isExternal: true, uValue: 1.0)
        let inner = Wall(width: 5, height: 2, isExternal: false, uValue: 1.0)
        let room = Room(floorArea: 20, height: 2.5, walls: [outer, inner],
                        heating: HeatingParameters(indoorTemperature: 20, climateName: "Berlin",
                                                   thermalBridgePercent: 0, airChangeRate: 0))
        let r = calc.calculate(room)
        XCTAssertEqual(r.transmission, 340, accuracy: 0.01)
    }

    func testFloorAgainstCellarUsesAdjacentTemp() {
        // Boden 20 m², U = 1.0, Keller 10 °C, θ_i = 20 → ΔT = 10 (nicht 34!)
        // 20 · 1.0 · 10 = 200 W
        let room = Room(floorArea: 20, height: 2.5,
                        heating: HeatingParameters(indoorTemperature: 20, climateName: "Berlin",
                                                   thermalBridgePercent: 0, airChangeRate: 0,
                                                   floorUValue: 1.0, floorAdjacentTemp: 10))
        let r = calc.calculate(room)
        XCTAssertEqual(r.transmission, 200, accuracy: 0.01)
    }

    func testGroundContactWallUsesAdjacentTemp() {
        // Kellerwand 10 m², U = 1.4, Erdreich 10 °C, θ_i = 20 → ΔT = 10 (nicht 34!)
        // 10 · 1.4 · 10 = 140 W statt 476 W gegen Außenluft.
        let ground = Wall(width: 5, height: 2, isExternal: true, uValue: 1.4,
                          adjacentTemp: 10)
        let room = Room(floorArea: 20, height: 2.5, walls: [ground],
                        heating: HeatingParameters(indoorTemperature: 20, climateName: "Berlin",
                                                   thermalBridgePercent: 0, airChangeRate: 0))
        let r = calc.calculate(room)
        XCTAssertEqual(r.transmission, 140, accuracy: 0.01)
    }

    func testVentilationLoad() {
        // n = 0.5/h, V = 20·2.5 = 50 m³, ΔT = 34 → 0.34·0.5·50·34 = 289 W
        let room = Room(floorArea: 20, height: 2.5,
                        heating: HeatingParameters(indoorTemperature: 20, climateName: "Berlin",
                                                   thermalBridgePercent: 0, airChangeRate: 0.5))
        let r = calc.calculate(room)
        XCTAssertEqual(r.ventilation, 289, accuracy: 0.01)
    }

    func testHeatRecoveryReducesVentilation() {
        let base = HeatingParameters(indoorTemperature: 20, climateName: "Berlin",
                                     thermalBridgePercent: 0, airChangeRate: 0.5)
        let wrg = HeatingParameters(indoorTemperature: 20, climateName: "Berlin",
                                    thermalBridgePercent: 0, airChangeRate: 0.5,
                                    heatRecoveryPercent: 80)
        let r1 = calc.calculate(Room(floorArea: 20, height: 2.5, heating: base)).ventilation
        let r2 = calc.calculate(Room(floorArea: 20, height: 2.5, heating: wrg)).ventilation
        XCTAssertEqual(r2, r1 * 0.2, accuracy: 0.01)  // 80 % zurückgewonnen
    }

    // MARK: - Integrationsbeispiel: verifiziert gegen das HeizlastProfi-PDF

    func testAnbauNeuMatchesHeizlastProfiPDF() {
        // "Anbau Neu" aus dem echten PDF: 18 m², h 2.54, θ_i 20, Düsseldorf θ_e −10 → ΔT 30.
        // ACHTUNG: das PDF nutzte θ_e = −14 (ΔT 34). Damit die Zahlen 1:1 stimmen,
        // hier ebenfalls −14 (über Klimastandort "Berlin"). Bauteile:
        //   Fenstertür 5.0 · 0.90, Fenstertür 10.9 · 0.90, Außenwand 44.6 · 0.20,
        //   Decke 18.0 · 0.15; Lüftung n = 0.5; Wärmebrücken 5 %.
        // Erwartet: Φ_T inkl. WB = 925 W, Φ_V = 264 W, gesamt = 1189 W, 66 W/m².
        let winWall = Wall(width: 1, height: 44.6, isExternal: true, uValue: 0.20) // 44.6 m² Außenwand
        let door1 = Door(width: 5.0, height: 1.0, isExternal: true, uValue: 0.90, isGlazed: true)
        let door2 = Door(width: 10.9, height: 1.0, isExternal: true, uValue: 0.90, isGlazed: true)
        let p = HeatingParameters(indoorTemperature: 20, climateName: "Berlin",
                                  thermalBridgePercent: 5, airChangeRate: 0.5,
                                  ceilingUValue: 0.15, ceilingAdjacentTemp: nil)
        let room = Room(name: "Anbau Neu", floorArea: 18.0, height: 2.54,
                        walls: [winWall], doors: [door1, door2],
                        heating: p)
        let r = calc.calculate(room)

        XCTAssertEqual(r.transmissionWithBridges, 925, accuracy: 2)
        XCTAssertEqual(r.ventilation, 264, accuracy: 2)
        XCTAssertEqual(r.total, 1189, accuracy: 3)
        XCTAssertEqual(r.specific(for: room.floorArea), 66, accuracy: 1)
    }

    // MARK: - Scan-Öffnungen nicht doppelt zählen (Netto-Wandfläche)

    func testScannedWallOpeningsAreNotDoubleCounted() {
        // Ein Scan liefert BRUTTO: 10 m² Außenwand, in der ein 2 m² Fenster sitzt.
        // Ohne Netto-Korrektur zählte die Fensterfläche doppelt (Wand-U + Fenster-U).
        let grossWall = Wall(width: 5, height: 2, isExternal: true, uValue: 1.0) // 10 m² brutto
        let window = Window(width: 2, height: 1, orientation: .sued, uValue: 1.0) // 2 m²
        let netWalls = WallAreaNormalizer.deductingOpenings(walls: [grossWall], doors: [], windows: [window])

        XCTAssertEqual(netWalls[0].netArea, 8, accuracy: 0.001)  // 10 − 2 m²

        let room = Room(floorArea: 20, height: 2.5, walls: netWalls, windows: [window],
                        heating: HeatingParameters(indoorTemperature: 20, climateName: "Berlin",
                                                   thermalBridgePercent: 0, airChangeRate: 0))
        let r = calc.calculate(room)
        // Korrekt: Wand (10−2)·1.0·34 + Fenster 2·1.0·34 = 272 + 68 = 340 W (nicht 408).
        XCTAssertEqual(r.transmission, 340, accuracy: 0.5)
    }

    // MARK: - Robustheit

    func testRoomWithoutHeatingParamsUsesDefaults() {
        // Kühllast-Raum ohne heating-Feld → Vorgaben (Berlin, 20 °C, WB 5 %) greifen.
        let room = Room(floorArea: 20, height: 2.5,
                        walls: [Wall(width: 4, height: 2.5, isExternal: true, uValue: 1.0)])
        let r = calc.calculate(room)
        // Außenwand 10 m² · 1.0 · 34 = 340 W + 5 % WB = 357 W
        XCTAssertEqual(r.transmissionWithBridges, 357, accuracy: 0.5)
        XCTAssertGreaterThan(r.total, r.transmissionWithBridges)  // + Lüftung
    }

    func testClimateLookup() {
        XCTAssertEqual(HeatingClimate.named("München").designOutdoorTemperature, -16, accuracy: 0.001)
        XCTAssertEqual(HeatingClimate.named("Köln").designOutdoorTemperature, -10, accuracy: 0.001)
        // Unbekannter Name → Vorgabe Berlin (−14)
        XCTAssertEqual(HeatingClimate.named("Timbuktu").designOutdoorTemperature, -14, accuracy: 0.001)
    }
}
