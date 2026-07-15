import XCTest
@testable import KuehllastCore

final class CoolingLoadCalculatorTests: XCTestCase {

    private let region = ClimateRegion.default  // Rheinland, 32 °C, Süd 370 W/m²

    // MARK: - Einzelposten

    func testSolarGainSouthWindow() {
        // 2 m² Südfenster, g = 0.6, Verschattung 1.0, Einstrahlung Süd = 370 W/m²
        // erwartet: 2 · 0.6 · 370 · 1.0 = 444 W
        let window = Window(width: 2.0, height: 1.0, orientation: .sued, gValue: 0.6)
        let room = Room(floorArea: 20, height: 2.5, windows: [window],
                        internalLoads: InternalLoads(persons: 0, equipmentWatt: 0, lightingWattPerSqm: 0),
                        airChangeRate: 0)
        let result = CoolingLoadCalculator(region: region).calculate(room)
        XCTAssertEqual(result.solar, 444, accuracy: 0.01)
    }

    func testShadingReducesSolar() {
        let free = Window(width: 2, height: 1, orientation: .west, gValue: 0.6, shading: 1.0)
        let shaded = Window(width: 2, height: 1, orientation: .west, gValue: 0.6, shading: 0.4)
        let calc = CoolingLoadCalculator(region: region)
        let roomFree = Room(floorArea: 20, height: 2.5, windows: [free],
                            internalLoads: InternalLoads(persons: 0, equipmentWatt: 0, lightingWattPerSqm: 0),
                            airChangeRate: 0)
        let roomShaded = Room(floorArea: 20, height: 2.5, windows: [shaded],
                              internalLoads: InternalLoads(persons: 0, equipmentWatt: 0, lightingWattPerSqm: 0),
                              airChangeRate: 0)
        let s1 = calc.calculate(roomFree).solar
        let s2 = calc.calculate(roomShaded).solar
        XCTAssertEqual(s2, s1 * 0.4, accuracy: 0.01)
    }

    func testTransmissionExternalWallOnly() {
        // Außenwand 10 m², U = 0.3, ΔT = 32 - 26 = 6 → 10·0.3·6 = 18 W
        // Innenwand darf nicht zählen.
        let outer = Wall(width: 5, height: 2, isExternal: true, uValue: 0.3)
        let inner = Wall(width: 5, height: 2, isExternal: false, uValue: 0.3)
        let room = Room(floorArea: 20, height: 2.5, walls: [outer, inner],
                        internalLoads: InternalLoads(persons: 0, equipmentWatt: 0, lightingWattPerSqm: 0),
                        indoorTemperature: 26, airChangeRate: 0)
        let result = CoolingLoadCalculator(region: region).calculate(room)
        XCTAssertEqual(result.transmission, 18, accuracy: 0.01)
    }

    func testGlazedDoorAddsSolarLikeWindow() {
        // Schiebefenster als Tür: 4.6 × 2.25 m = 10.35 m², verglast, Süd, g=0.6
        // Solar = 10.35 · 0.6 · 370 = 2297.7 W
        let glazed = Door(width: 4.6, height: 2.25, isExternal: true,
                          isGlazed: true, orientation: .sued, gValue: 0.6)
        let room = Room(floorArea: 20, height: 2.5, doors: [glazed],
                        internalLoads: InternalLoads(persons: 0, equipmentWatt: 0, lightingWattPerSqm: 0),
                        airChangeRate: 0)
        let result = CoolingLoadCalculator(region: region).calculate(room)
        XCTAssertEqual(result.solar, 2297.7, accuracy: 0.1)
    }

    func testSolidDoorHasNoSolar() {
        // Massive Außentür: nur Transmission, kein Solar.
        let solid = Door(width: 1.0, height: 2.1, isExternal: true, uValue: 1.8, isGlazed: false)
        let room = Room(floorArea: 20, height: 2.5, doors: [solid],
                        internalLoads: InternalLoads(persons: 0, equipmentWatt: 0, lightingWattPerSqm: 0),
                        indoorTemperature: 26, airChangeRate: 0)
        let result = CoolingLoadCalculator(region: region).calculate(room)
        XCTAssertEqual(result.solar, 0, accuracy: 0.001)
        // Transmission: 1.0·2.1 · 1.8 · 6 = 22.68 W
        XCTAssertEqual(result.transmission, 22.68, accuracy: 0.01)
    }

    func testInternalLoads() {
        // 3 Personen à 100 W + 200 W Geräte + 8 W/m² · 25 m² Licht = 300 + 200 + 200 = 700 W
        let room = Room(floorArea: 25, height: 2.5,
                        internalLoads: InternalLoads(persons: 3, wattPerPerson: 100,
                                                     equipmentWatt: 200, lightingWattPerSqm: 8),
                        airChangeRate: 0)
        let result = CoolingLoadCalculator(region: region).calculate(room)
        XCTAssertEqual(result.persons, 300, accuracy: 0.01)
        XCTAssertEqual(result.equipment, 200, accuracy: 0.01)
        XCTAssertEqual(result.lighting, 200, accuracy: 0.01)
        XCTAssertEqual(result.internalTotal, 700, accuracy: 0.01)
    }

    func testVentilationLoad() {
        // n = 0.5/h, V = 20·2.5 = 50 m³, ΔT = 6 → 0.34·0.5·50·6 = 51 W
        let room = Room(floorArea: 20, height: 2.5,
                        internalLoads: InternalLoads(persons: 0, equipmentWatt: 0, lightingWattPerSqm: 0),
                        indoorTemperature: 26, airChangeRate: 0.5)
        let result = CoolingLoadCalculator(region: region).calculate(room)
        XCTAssertEqual(result.ventilation, 51, accuracy: 0.01)
    }

    // MARK: - Geräteempfehlung

    func testDeviceRecommendationPicksSmallestFittingClass() {
        let calc = CoolingLoadCalculator(region: region)
        XCTAssertEqual(calc.recommendDevice(for: 2850).ratedPowerKW, 3.5, accuracy: 0.001)
        XCTAssertEqual(calc.recommendDevice(for: 2000).ratedPowerKW, 2.0, accuracy: 0.001)
        XCTAssertEqual(calc.recommendDevice(for: 2100).ratedPowerKW, 2.5, accuracy: 0.001)
        XCTAssertEqual(calc.recommendDevice(for: 4900).ratedPowerKW, 5.0, accuracy: 0.001)
    }

    func testDeviceRecommendationBeyondLargestClass() {
        let calc = CoolingLoadCalculator(region: region)
        // 12 kW Last: größte Klasse 7 kW → nächstes Vielfaches 14 kW (2 Geräte-Größe)
        let rec = calc.recommendDevice(for: 12000)
        XCTAssertGreaterThanOrEqual(rec.ratedPowerKW, 12)
    }

    // MARK: - Integrationsbeispiel: Raum 1 aus dem echten Scan

    func testRealisticRoomEndToEnd() {
        // Raum 1: 36.07 m², 2.56 m, Südfenster 2.8 m² + Westfenster 1.4 m²,
        // eine Außenwand, 3 Personen. Summe ≈ 2070 W → 2,5-kW-Klasse.
        let south = Window(width: 2.0, height: 1.4, orientation: .sued, gValue: 0.6)
        let west = Window(width: 1.0, height: 1.4, orientation: .west, gValue: 0.6)
        let outerWall = Wall(width: 5.51, height: 2.56, isExternal: true, uValue: 0.28)
        let room = Room(name: "Raum 1", floorArea: 36.07, height: 2.56,
                        walls: [outerWall], windows: [south, west],
                        internalLoads: InternalLoads(persons: 3, equipmentWatt: 300,
                                                     lightingWattPerSqm: 8),
                        indoorTemperature: 26, airChangeRate: 0.5)
        let calc = CoolingLoadCalculator(region: region)
        let result = calc.calculate(room)

        XCTAssertGreaterThan(result.solar, result.transmission,
                             "Solarlast ist bei Klimaräumen der dominante Posten.")
        XCTAssertGreaterThan(result.total, 1800)
        XCTAssertLessThan(result.total, 3000)

        let rec = calc.recommendDevice(for: result.total)
        XCTAssertTrue([2.5, 3.5].contains(rec.ratedPowerKW),
                      "Erwartet 2,5–3,5 kW, war \(rec.ratedPowerKW) kW bei \(Int(result.total)) W")
    }

    // MARK: - JSON-Import

    func testImportHeizlastScanJSON() throws {
        let json = """
        {
          "name": "Raum 1", "app": "HeizlastScan", "version": 1,
          "floorArea": 36.07, "height": 2.56,
          "scannedAt": "2026-07-11T14:48:58Z",
          "walls": [ { "width": 5.51, "height": 2.56 } ],
          "doors": [ { "width": 2.20, "height": 2.28 } ],
          "windows": []
        }
        """.data(using: .utf8)!
        let room = try HeizlastScanImport.room(fromJSON: json)
        XCTAssertEqual(room.name, "Raum 1")
        XCTAssertEqual(room.floorArea, 36.07, accuracy: 0.001)
        XCTAssertEqual(room.walls.count, 1)
        XCTAssertEqual(room.doors.count, 1)
        XCTAssertNotNil(room.scannedAt)
    }

    func testImportRejectsGarbage() {
        let bad = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try HeizlastScanImport.room(fromJSON: bad))
    }
}
