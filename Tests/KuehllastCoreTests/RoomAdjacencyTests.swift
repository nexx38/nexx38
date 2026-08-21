import XCTest
@testable import KuehllastCore

/// Tests der automatischen Innenwand-Erkennung.
///
/// Die Richtung der Fehler ist hier entscheidend: Eine übersehene Innenwand
/// macht die Heizlast zu GROSS (Gerät zu groß, teuer, aber warm). Eine
/// fälschlich erkannte Innenwand macht sie zu KLEIN (Anlage unterdimensioniert,
/// Kunde friert, Nacharbeit auf eigene Kosten). Deshalb prüfen mehrere Tests
/// gezielt, dass die Automatik im Zweifel NICHTS markiert.
final class RoomAdjacencyTests: XCTestCase {

    /// Wand als Linie im Grundriss.
    private func wall(_ x1: Double, _ z1: Double, _ x2: Double, _ z2: Double) -> Wall {
        Wall(width: ((x2 - x1) * (x2 - x1) + (z2 - z1) * (z2 - z1)).squareRoot(),
             height: 2.5, isExternal: true,
             position: WallPosition(x1: x1, z1: z1, x2: x2, z2: z2))
    }

    /// Zwei Räume nebeneinander, dazwischen eine 20 cm dicke Trennwand:
    /// Raum A von x 0…4, Raum B von x 4,2…8, beide z 0…3.
    private func zweiRaeumeNebeneinander() -> [Room] {
        let a = Room(name: "A", floorArea: 12, height: 2.5, walls: [
            wall(0, 0, 4, 0),      // Süd (außen)
            wall(4, 0, 4, 3),      // Trennwand, Seite A
            wall(4, 3, 0, 3),      // Nord (außen)
            wall(0, 3, 0, 0)       // West (außen)
        ])
        let b = Room(name: "B", floorArea: 11.4, height: 2.5, walls: [
            wall(4.2, 0, 8, 0),    // Süd (außen)
            wall(8, 0, 8, 3),      // Ost (außen)
            wall(8, 3, 4.2, 3),    // Nord (außen)
            wall(4.2, 3, 4.2, 0)   // Trennwand, Seite B
        ])
        return [a, b]
    }

    // MARK: - Der Kernfall

    func testTrennwandZwischenZweiRaeumenWirdErkannt() {
        let rooms = zweiRaeumeNebeneinander()
        let result = RoomAdjacency.detect(in: rooms)

        XCTAssertEqual(result.pairCount, 1, "genau eine Trennwand")
        XCTAssertEqual(result.interiorWallIndices[rooms[0].id], [1])
        XCTAssertEqual(result.interiorWallIndices[rooms[1].id], [3])
    }

    func testAnwendenSetztNurDieTrennwandAufInnen() {
        let updated = RoomAdjacency.applied(to: zweiRaeumeNebeneinander())

        XCTAssertFalse(updated[0].walls[1].isExternal, "Trennwand A ist innen")
        XCTAssertFalse(updated[1].walls[3].isExternal, "Trennwand B ist innen")
        // Alle übrigen bleiben außen – sonst wäre die Heizlast zu klein.
        XCTAssertTrue(updated[0].walls[0].isExternal)
        XCTAssertTrue(updated[0].walls[2].isExternal)
        XCTAssertTrue(updated[0].walls[3].isExternal)
        XCTAssertTrue(updated[1].walls[0].isExternal)
        XCTAssertTrue(updated[1].walls[1].isExternal)
        XCTAssertTrue(updated[1].walls[2].isExternal)
    }

    func testWirkungAufDieHeizlast() {
        // Der eigentliche Zweck: die Rechnung wird kleiner und richtiger.
        let heizung = HeatingParameters(indoorTemperature: 20, climateName: "Berlin",
                                        thermalBridgePercent: 0, airChangeRate: 0)
        var rooms = zweiRaeumeNebeneinander()
        rooms[0].heating = heizung
        rooms[1].heating = heizung

        let vorher = HeatingLoadCalculator().calculate(rooms[0]).total
        let nachher = HeatingLoadCalculator().calculate(RoomAdjacency.applied(to: rooms)[0]).total

        XCTAssertLessThan(nachher, vorher)
        // Die 3-m-Trennwand von 4 Außenwänden (4+3+4+3 = 14 m) fällt weg.
        XCTAssertEqual(nachher / vorher, 11.0 / 14.0, accuracy: 0.01)
    }

    // MARK: - Was NICHT erkannt werden darf

    func testWaendeDesselbenRaumsBildenKeineTrennwand() {
        // Süd- und Nordwand eines schmalen Raums stehen sich gegenüber –
        // sie dürfen sich niemals gegenseitig als Innenwand markieren.
        let schmal = Room(name: "Flur", floorArea: 4, height: 2.5, walls: [
            wall(0, 0, 4, 0),
            wall(0, 1, 4, 1)      // nur 1 m entfernt, parallel
        ])
        XCTAssertEqual(RoomAdjacency.detect(in: [schmal]).pairCount, 0)
    }

    func testGegenueberliegendeWaendeZweierRaeumeSindKeineTrennwand() {
        // Zwei Räume mit 1 m Abstand (z. B. Flur dazwischen, nicht gescannt):
        // Die Wände stehen parallel, sind aber zu weit auseinander.
        let a = Room(name: "A", floorArea: 12, height: 2.5, walls: [wall(4, 0, 4, 3)])
        let b = Room(name: "B", floorArea: 12, height: 2.5, walls: [wall(5, 0, 5, 3)])
        XCTAssertEqual(RoomAdjacency.detect(in: [a, b]).pairCount, 0,
                       "1 m Abstand ist keine Trennwand")
    }

    func testSenkrechteWaendeWerdenNichtVerbunden() {
        let a = Room(name: "A", floorArea: 12, height: 2.5, walls: [wall(4, 0, 4, 3)])
        let b = Room(name: "B", floorArea: 12, height: 2.5, walls: [wall(4, 0, 7, 0)])
        XCTAssertEqual(RoomAdjacency.detect(in: [a, b]).pairCount, 0)
    }

    func testNurEckberuehrungReichtNicht() {
        // Zwei Wände parallel und dicht, aber sie überlappen nur 20 cm.
        let a = Room(name: "A", floorArea: 12, height: 2.5, walls: [wall(0, 0, 3, 0)])
        let b = Room(name: "B", floorArea: 12, height: 2.5, walls: [wall(2.8, 0.15, 5.8, 0.15)])
        XCTAssertEqual(RoomAdjacency.detect(in: [a, b]).pairCount, 0,
                       "20 cm Überlappung ist eine Ecke, keine Trennwand")
    }

    func testKurzeSchnipselWerdenIgnoriert() {
        // 13-cm-Stücke wie im echten Wohnzimmer-Scan.
        let a = Room(name: "A", floorArea: 12, height: 2.5, walls: [wall(0, 0, 0.13, 0)])
        let b = Room(name: "B", floorArea: 12, height: 2.5, walls: [wall(0, 0.15, 0.13, 0.15)])
        XCTAssertEqual(RoomAdjacency.detect(in: [a, b]).pairCount, 0)
    }

    func testRaeumeOhnePositionenWerdenUebersprungen() {
        // Einzeln gescannte Räume liegen in verschiedenen Koordinatensystemen –
        // dort wäre jede Zuordnung geraten.
        let a = Room(name: "A", floorArea: 12, height: 2.5,
                     walls: [Wall(width: 4, height: 2.5, isExternal: true)])
        let b = Room(name: "B", floorArea: 12, height: 2.5,
                     walls: [Wall(width: 4, height: 2.5, isExternal: true)])
        let result = RoomAdjacency.detect(in: [a, b])
        XCTAssertEqual(result.pairCount, 0)
        XCTAssertTrue(RoomAdjacency.applied(to: [a, b])[0].walls[0].isExternal)
    }

    func testLeereEingabeStuerztNicht() {
        XCTAssertEqual(RoomAdjacency.detect(in: []).pairCount, 0)
        XCTAssertTrue(RoomAdjacency.applied(to: []).isEmpty)
    }

    // MARK: - Toleranzen

    func testLeichteSchraeglageWirdAkzeptiert() {
        // Scans sind nie exakt: 5° Schräglage muss noch durchgehen.
        let a = Room(name: "A", floorArea: 12, height: 2.5, walls: [wall(4, 0, 4, 3)])
        let versetzt = wall(4.2, 0, 4.46, 2.99)   // ~5° gekippt
        let b = Room(name: "B", floorArea: 12, height: 2.5, walls: [versetzt])
        XCTAssertEqual(RoomAdjacency.detect(in: [a, b]).pairCount, 1)
    }

    func testStarkeSchraeglageWirdAbgelehnt() {
        let a = Room(name: "A", floorArea: 12, height: 2.5, walls: [wall(4, 0, 4, 3)])
        let schraeg = wall(4.2, 0, 5.4, 2.8)      // ~23° gekippt
        let b = Room(name: "B", floorArea: 12, height: 2.5, walls: [schraeg])
        XCTAssertEqual(RoomAdjacency.detect(in: [a, b]).pairCount, 0)
    }

    func testDreiRaeumeInReihe() {
        // Mittlerer Raum grenzt an beide Nachbarn – beide Wände innen.
        let a = Room(name: "A", floorArea: 12, height: 2.5, walls: [wall(4, 0, 4, 3)])
        let mitte = Room(name: "M", floorArea: 12, height: 2.5, walls: [
            wall(4.2, 0, 4.2, 3),
            wall(8, 0, 8, 3)
        ])
        let c = Room(name: "C", floorArea: 12, height: 2.5, walls: [wall(8.2, 0, 8.2, 3)])

        let result = RoomAdjacency.detect(in: [a, mitte, c])
        XCTAssertEqual(result.pairCount, 2)
        XCTAssertEqual(result.interiorWallIndices[mitte.id], [0, 1])
    }

    func testHandarbeitWirdNichtUeberschrieben() {
        // Der Nutzer hat eine Außenwand schon selbst auf innen gestellt –
        // die Automatik darf sie nicht zurücksetzen.
        var rooms = zweiRaeumeNebeneinander()
        rooms[0].walls[0].isExternal = false
        let updated = RoomAdjacency.applied(to: rooms)
        XCTAssertFalse(updated[0].walls[0].isExternal)
    }
}
