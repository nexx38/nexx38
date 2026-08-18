import XCTest
@testable import KuehllastCore

/// Tests für den erweiterten JSON-Import (explizite Flags aus unserem eigenen
/// Exportformat), die Baujahr-Vorgaben und die Plausibilitätsprüfung.
final class ImportAndPresetTests: XCTestCase {

    // MARK: - Import: explizite Flags haben Vorrang

    func testImportHonorsExplicitFlags() throws {
        // Unser eigenes Exportformat: Innenwand + verglaste Terrassentür mit
        // allen Details. Vorher gingen diese Flags beim Re-Import verloren
        // (Innenwand wurde Außenwand, verglaste Tür wurde massiv+innen).
        let json = """
        {
          "name": "Wohnzimmer", "app": "KuehllastScan", "version": 1,
          "floorArea": 25.0, "height": 2.5,
          "walls": [
            { "width": 5.0, "height": 2.5, "external": false, "uValue": 0.5 },
            { "width": 4.0, "height": 2.5, "external": true, "uValue": 0.8 }
          ],
          "doors": [
            { "width": 2.4, "height": 2.2, "glazed": true, "external": true,
              "orientation": "west", "gValue": 0.5, "shading": 0.8, "uValue": 1.1 }
          ],
          "windows": [
            { "width": 1.2, "height": 1.4, "orientation": "nord",
              "gValue": 0.55, "shading": 0.9, "uValue": 1.3 }
          ]
        }
        """.data(using: .utf8)!
        let room = try HeizlastScanImport.room(fromJSON: json)

        XCTAssertFalse(room.walls[0].isExternal, "external:false muss erhalten bleiben")
        XCTAssertTrue(room.walls[1].isExternal)
        XCTAssertEqual(room.walls[1].uValue, 0.8, accuracy: 0.001)

        let door = room.doors[0]
        XCTAssertTrue(door.isGlazed)
        XCTAssertTrue(door.isExternal)
        XCTAssertEqual(door.orientation, .west)
        XCTAssertEqual(door.gValue, 0.5, accuracy: 0.001)
        XCTAssertEqual(door.shading, 0.8, accuracy: 0.001)

        let window = room.windows[0]
        XCTAssertEqual(window.orientation, .nord)
        XCTAssertEqual(window.shading, 0.9, accuracy: 0.001)
        XCTAssertEqual(window.uValue, 1.3, accuracy: 0.001)
    }

    func testImportLegacyWideDoorBecomesGlazed() throws {
        // HeizlastScan-Altdatei ohne Flags: 2,20 m breite „Tür" ist ein
        // Schiebefenster → gleiche Heuristik wie beim Live-Scan.
        let json = """
        {
          "name": "Raum 1", "app": "HeizlastScan", "version": 1,
          "floorArea": 36.07, "height": 2.56,
          "walls": [ { "width": 5.51, "height": 2.56 } ],
          "doors": [ { "width": 2.20, "height": 2.28 } ],
          "windows": []
        }
        """.data(using: .utf8)!
        let room = try HeizlastScanImport.room(fromJSON: json)
        XCTAssertTrue(room.doors[0].isGlazed)
        XCTAssertTrue(room.doors[0].isExternal)
    }

    func testImportLegacyNarrowDoorStaysSolidInterior() throws {
        // Schmale Tür (0,9 m) ohne Flags = normale Zimmertür: massiv, innen.
        let json = """
        {
          "name": "Flur", "app": "HeizlastScan", "version": 1,
          "floorArea": 8.0, "height": 2.5,
          "walls": [ { "width": 3.0, "height": 2.5 } ],
          "doors": [ { "width": 0.9, "height": 2.05 } ],
          "windows": []
        }
        """.data(using: .utf8)!
        let room = try HeizlastScanImport.room(fromJSON: json)
        XCTAssertFalse(room.doors[0].isGlazed)
        XCTAssertFalse(room.doors[0].isExternal)
    }

    // MARK: - Baujahr-Vorgaben

    func testEraPresetsApplyUValues() {
        let wall = Wall(width: 4, height: 2.5, isExternal: true, uValue: 0.28)
        let window = Window(width: 1.2, height: 1.4)
        let solidDoor = Door(width: 1.0, height: 2.1, isExternal: true, isGlazed: false)
        let glazedDoor = Door(width: 2.4, height: 2.2, isExternal: true, isGlazed: true)
        let room = Room(floorArea: 20, height: 2.5, walls: [wall],
                        doors: [solidDoor, glazedDoor], windows: [window])

        let updated = BuildingEra.ab2016.applied(to: room)

        XCTAssertEqual(updated.constructionEra, BuildingEra.ab2016.rawValue)
        XCTAssertEqual(updated.walls[0].uValue, 0.24, accuracy: 0.001)
        XCTAssertEqual(updated.windows[0].uValue, 1.1, accuracy: 0.001)
        XCTAssertEqual(updated.doors[0].uValue, 1.3, accuracy: 0.001, "massive Tür → Tür-U")
        XCTAssertEqual(updated.doors[1].uValue, 1.1, accuracy: 0.001, "verglaste Tür → Fenster-U")
    }

    func testEraPresetsAltbauRaiseHeatingLoad() {
        // Gleicher Raum, einmal Neubau- und einmal Altbau-Klasse:
        // die Heizlast muss beim Altbau deutlich höher liegen.
        let wall = Wall(width: 8, height: 2.5, isExternal: true)
        let window = Window(width: 2, height: 1.4)
        let base = Room(floorArea: 20, height: 2.5, walls: [wall], windows: [window],
                        heating: HeatingParameters())
        let neubau = HeatingLoadCalculator().calculate(BuildingEra.ab2016.applied(to: base))
        let altbau = HeatingLoadCalculator().calculate(BuildingEra.vor1949.applied(to: base))
        XCTAssertGreaterThan(altbau.total, neubau.total * 2)
    }

    func testEraPresetsTouchCeilingOnlyWhenSet() {
        let withCeiling = Room(floorArea: 20, height: 2.5,
                               heating: HeatingParameters(ceilingUValue: 0.2))
        let withoutCeiling = Room(floorArea: 20, height: 2.5,
                                  heating: HeatingParameters())

        let updated1 = BuildingEra.vor1949.applied(to: withCeiling)
        let updated2 = BuildingEra.vor1949.applied(to: withoutCeiling)

        XCTAssertEqual(updated1.heating?.ceilingUValue ?? 0, 1.4, accuracy: 0.001)
        XCTAssertNil(updated2.heating?.ceilingUValue,
                     "Nicht angesetzte Decke darf die Baujahr-Klasse nicht aktivieren")
    }

    // MARK: - Plausibilität

    func testPlausibilityBands() {
        XCTAssertNil(Plausibility.coolingNote(specific: 100))
        XCTAssertNotNil(Plausibility.coolingNote(specific: 10))
        XCTAssertNotNil(Plausibility.coolingNote(specific: 400))
        XCTAssertNil(Plausibility.heatingNote(specific: 60))
        XCTAssertNotNil(Plausibility.heatingNote(specific: 5))
        XCTAssertNotNil(Plausibility.heatingNote(specific: 300))
    }

    // MARK: - Wand-Position (Grundriss)

    func testWallPositionRoundTripAndLegacyDecode() throws {
        let wall = Wall(width: 4, height: 2.5,
                        position: WallPosition(x1: 0, z1: 0, x2: 4, z2: 0))
        let decoded = try JSONDecoder().decode(Wall.self,
                                               from: JSONEncoder().encode(wall))
        XCTAssertEqual(decoded.position?.x2 ?? -1, 4, accuracy: 0.001)

        // Alte Dateien ohne position-Feld dekodieren weiter (position = nil).
        let legacy = try JSONDecoder().decode(
            Wall.self, from: #"{"width":3,"height":2.5}"#.data(using: .utf8)!)
        XCTAssertNil(legacy.position)
    }

    // MARK: - Room-Dekodierung bleibt abwärtskompatibel

    func testRoomDecodesWithoutNewOptionalFields() throws {
        // rooms.json aus einer älteren App-Version (ohne photoFilenames /
        // constructionEra) muss weiter dekodieren.
        let room = Room(floorArea: 20, height: 2.5)
        var dict = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(room)) as! [String: Any]
        dict.removeValue(forKey: "photoFilenames")
        dict.removeValue(forKey: "constructionEra")
        let data = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(Room.self, from: data)
        XCTAssertNil(decoded.photoFilenames)
        XCTAssertNil(decoded.constructionEra)
        XCTAssertEqual(decoded.floorArea, 20, accuracy: 0.001)
    }
}
