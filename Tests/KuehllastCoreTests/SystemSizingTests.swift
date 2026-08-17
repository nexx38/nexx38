import XCTest
@testable import KuehllastCore

/// Tests für WP-Auslegung, Multisplit-Planung, Heizkörper-Check und
/// hydraulischen Abgleich.
final class SystemSizingTests: XCTestCase {

    // MARK: - Wärmepumpe

    func testHeatPumpRecommendation() {
        // 8000 W Heizlast + 3 Personen (750 W WW), 2 h Sperrzeit (Faktor 1,0909)
        // → (8000+750)·1,0909 = 9545 W → 9,55 kW → nächste Größe 10 kW.
        let r = HeatPumpSizing.recommend(heatingLoadW: 8000, dhwPersons: 3, blockingHours: 2)
        XCTAssertEqual(r.dhwW, 750, accuracy: 0.01)
        XCTAssertEqual(r.blockingFactor, 24.0 / 22.0, accuracy: 0.0001)
        XCTAssertEqual(r.requiredKW, 9.545, accuracy: 0.01)
        XCTAssertEqual(r.suggestedKW, 10, accuracy: 0.001)
    }

    func testHeatPumpNoBlockingNoDHW() {
        let r = HeatPumpSizing.recommend(heatingLoadW: 5500, dhwPersons: 0, blockingHours: 0)
        XCTAssertEqual(r.requiredKW, 5.5, accuracy: 0.001)
        XCTAssertEqual(r.suggestedKW, 6, accuracy: 0.001)
    }

    // MARK: - Multisplit

    func testMultiSplitPlan() {
        let plan = MultiSplitSizing.plan(rooms: [("Wohnen", 1800), ("Schlafen", 2600)],
                                         simultaneity: 0.8)
        XCTAssertEqual(plan.indoorUnits[0].unitKW, 2.0, accuracy: 0.001)
        XCTAssertEqual(plan.indoorUnits[1].unitKW, 3.5, accuracy: 0.001)
        XCTAssertEqual(plan.indoorTotalKW, 5.5, accuracy: 0.001)
        XCTAssertEqual(plan.outdoorRequiredKW, 4.4, accuracy: 0.05)
    }

    // MARK: - Heizkörper

    func testRadiatorNormAndReducedPower() {
        // Typ 22, 1,0 × 0,6 m = 0,6 m² → Norm 1020 W (75/65/20).
        // Bei 55/45 und 20 °C Raum: Übertemperatur 30 K → Faktor (30/50)^1,3 ≈ 0,515.
        let rad = Radiator(type: .typ22, widthM: 1.0, heightM: 0.6)
        XCTAssertEqual(rad.normPower, 1020, accuracy: 0.5)
        XCTAssertEqual(rad.power(flow: 55, ret: 45, roomTemp: 20), 525, accuracy: 5)
    }

    func testRadiatorCheckVerdicts() {
        let ok = RadiatorCheckResult(capacity: 1100, demand: 1000)
        XCTAssertEqual(ok.verdict, .ausreichend)
        let knapp = RadiatorCheckResult(capacity: 900, demand: 1000)
        XCTAssertEqual(knapp.verdict, .knapp)
        let klein = RadiatorCheckResult(capacity: 500, demand: 1000)
        XCTAssertEqual(klein.verdict, .zuKlein)
    }

    // MARK: - Hydraulischer Abgleich

    func testValvePreset() {
        // 800 W bei 10 K Spreizung → 68,8 kg/h; kv = 0,0688/√0,1 ≈ 0,218 → Stufe 3.
        let p = HydraulicBalancing.preset(loadW: 800, spreadK: 10)
        XCTAssertEqual(p.flowKgPerH, 68.8, accuracy: 0.1)
        XCTAssertEqual(p.kvNeeded, 0.218, accuracy: 0.005)
        XCTAssertEqual(p.preset, 3)
    }

    func testValvePresetHugeLoadExceedsScale() {
        let p = HydraulicBalancing.preset(loadW: 20000, spreadK: 5)
        XCTAssertNil(p.preset)
        XCTAssertEqual(p.presetLabel, "> Stufe 8")
    }

    // MARK: - Abwärtskompatibilität

    func testRoomDecodesWithoutRadiators() throws {
        let room = Room(floorArea: 20, height: 2.5)
        var dict = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(room)) as! [String: Any]
        dict.removeValue(forKey: "radiators")
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        XCTAssertNil(decoded.radiators)
    }

    func testBuildingSettingsDecodeWithMissingKeys() throws {
        let decoded = try JSONDecoder().decode(BuildingSettings.self,
                                               from: "{}".data(using: .utf8)!)
        XCTAssertEqual(decoded.dhwPersons, 3)
        XCTAssertEqual(decoded.flowTemp, 55, accuracy: 0.001)
        XCTAssertEqual(decoded.simultaneity, 0.8, accuracy: 0.001)
    }
}
