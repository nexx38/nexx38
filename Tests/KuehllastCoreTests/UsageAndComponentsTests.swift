import XCTest
@testable import KuehllastCore

/// Tests für Nutzungsprofile und die zentrale Bauteilbibliothek.
final class UsageAndComponentsTests: XCTestCase {

    // MARK: - Nutzungsprofile

    func testBathProfileRaisesHeatingLoad() {
        // Der fachliche Kern: Bad wird auf 24 °C ausgelegt, Wohnen auf 20.
        // Bei Berlin (−14) heißt das ΔT 38 statt 34 → rund 12 % mehr Heizlast.
        let wall = Wall(width: 4, height: 2.5, isExternal: true, uValue: 1.0)
        let base = Room(floorArea: 10, height: 2.5, walls: [wall],
                        heating: HeatingParameters(climateName: "Berlin",
                                                   thermalBridgePercent: 0))
        let wohnen = HeatingLoadCalculator().calculate(UsageProfile.wohnen.applied(to: base))
        let bad = HeatingLoadCalculator().calculate(UsageProfile.bad.applied(to: base))

        XCTAssertEqual(wohnen.deltaT, 34, accuracy: 0.01)
        XCTAssertEqual(bad.deltaT, 38, accuracy: 0.01)
        XCTAssertGreaterThan(bad.total, wohnen.total * 1.1)
    }

    func testKitchenHasHighestEquipmentLoad() {
        // Küche (Herd, Kühlschrank) muss die höchste Gerätelast haben –
        // vertauschte Zuordnungen fallen hier sofort auf.
        let kitchen = UsageProfile.kueche.equipmentWatt
        for profile in UsageProfile.allCases where profile != .kueche {
            XCTAssertLessThan(profile.equipmentWatt, kitchen,
                              "\(profile.label) darf nicht mehr Gerätelast haben als die Küche")
        }
    }

    func testProfileWritesBothSides() {
        // Ein Profil muss Heiz- UND Kühlseite setzen; früher wurde beim
        // Setzen der Raumtemperatur die Heizlast-Seite vergessen.
        let room = UsageProfile.bad.applied(to: Room(floorArea: 8, height: 2.5))
        XCTAssertEqual(room.usageProfile, UsageProfile.bad.rawValue)
        XCTAssertEqual(room.indoorTemperature, 26, accuracy: 0.01)     // Kühlfall
        XCTAssertEqual(room.heating?.indoorTemperature ?? 0, 24, accuracy: 0.01) // Heizfall
        XCTAssertEqual(room.airChangeRate, 1.0, accuracy: 0.01)
        XCTAssertEqual(room.internalLoads.equipmentWatt, 100, accuracy: 0.01)
    }

    func testProfileGuessFromName() {
        XCTAssertEqual(UsageProfile.guessed(fromName: "Badezimmer OG"), .bad)
        XCTAssertEqual(UsageProfile.guessed(fromName: "Küche"), .kueche)
        XCTAssertEqual(UsageProfile.guessed(fromName: "Kinderzimmer"), .schlafen)
        XCTAssertEqual(UsageProfile.guessed(fromName: "Kellerbüro"), .buero,
                       "Büro muss vor Keller greifen – der Raum wird als Büro genutzt")
        XCTAssertNil(UsageProfile.guessed(fromName: "Gescannter Raum 3"))
    }

    func testEveryProfileHasSaneValues() {
        for profile in UsageProfile.allCases {
            XCTAssertTrue((10...26).contains(profile.heatingIndoorTemp), profile.label)
            XCTAssertTrue((22...30).contains(profile.coolingIndoorTemp), profile.label)
            XCTAssertGreaterThanOrEqual(profile.persons, 0)
            XCTAssertGreaterThan(profile.airChangeRate, 0)
            XCTAssertFalse(profile.label.isEmpty)
        }
    }

    // MARK: - Zentrale Bauteilwerte

    func testComponentsFromEraAndApply() {
        let components = BuildingComponents.fromEra(.vor1949)
        XCTAssertEqual(components.wallU, BuildingEra.vor1949.wallU, accuracy: 0.001)
        XCTAssertEqual(components.era, BuildingEra.vor1949.rawValue)

        let wall = Wall(width: 4, height: 2.5, isExternal: true, uValue: 0.28)
        let window = Window(width: 1, height: 1.4)
        let solidDoor = Door(width: 1, height: 2.1, isExternal: true, isGlazed: false)
        let glazedDoor = Door(width: 2.4, height: 2.2, isExternal: true, isGlazed: true)
        let room = Room(floorArea: 20, height: 2.5, walls: [wall],
                        doors: [solidDoor, glazedDoor], windows: [window])

        let updated = components.applied(to: room)
        XCTAssertEqual(updated.walls[0].uValue, components.wallU, accuracy: 0.001)
        XCTAssertEqual(updated.windows[0].uValue, components.windowU, accuracy: 0.001)
        XCTAssertEqual(updated.windows[0].gValue, components.windowG, accuracy: 0.001)
        XCTAssertEqual(updated.doors[0].uValue, components.doorU, accuracy: 0.001, "massive Tür")
        XCTAssertEqual(updated.doors[1].uValue, components.windowU, accuracy: 0.001, "verglaste Tür = Fenster-U")
        XCTAssertEqual(updated.constructionEra, BuildingEra.vor1949.rawValue)
    }

    func testComponentsTouchCeilingOnlyWhenSet() {
        // Ob ein Raum eine Außendecke hat, weiß nur der Nutzer – die
        // Bauteilbibliothek darf sie nicht aus Versehen aktivieren.
        let components = BuildingComponents.fromEra(.vor1949)
        let withCeiling = Room(floorArea: 20, height: 2.5,
                               heating: HeatingParameters(ceilingUValue: 0.2))
        let without = Room(floorArea: 20, height: 2.5, heating: HeatingParameters())

        XCTAssertEqual(components.applied(to: withCeiling).heating?.ceilingUValue ?? 0,
                       components.roofU, accuracy: 0.001)
        XCTAssertNil(components.applied(to: without).heating?.ceilingUValue)
    }

    // MARK: - Getrennte Vorlauftemperaturen + Abwärtskompatibilität

    func testUnderfloorFlowTempDefaultsBelowRadiator() {
        let settings = BuildingSettings()
        XCTAssertLessThan(settings.underfloorFlowTemp, settings.flowTemp,
                          "Fußboden läuft kühler als Heizkörper")
        XCTAssertLessThan(settings.underfloorReturnTemp, settings.underfloorFlowTemp)
    }

    func testOldBuildingSettingsFileStillDecodes() throws {
        // Datei aus der Zeit vor Fußbodenheizung und Bauteilbibliothek.
        let json = """
        {"dhwPersons":4,"blockingHours":2,"flowTemp":55,"returnTemp":45,
         "spreadK":10,"simultaneity":0.8}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BuildingSettings.self, from: json)
        XCTAssertEqual(decoded.dhwPersons, 4)
        XCTAssertEqual(decoded.flowTemp, 55, accuracy: 0.001)
        XCTAssertEqual(decoded.underfloorFlowTemp, 40, accuracy: 0.001, "Vorgabe greift")
        XCTAssertEqual(decoded.components.wallU, 0.28, accuracy: 0.001)
    }

    func testRoomDecodesWithoutStoreyAndProfile() throws {
        let room = Room(floorArea: 20, height: 2.5)
        var dict = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(room)) as! [String: Any]
        dict.removeValue(forKey: "storey")
        dict.removeValue(forKey: "usageProfile")
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Room.self, from: data)
        XCTAssertNil(decoded.storey)
        XCTAssertNil(decoded.usageProfile)
    }
}
