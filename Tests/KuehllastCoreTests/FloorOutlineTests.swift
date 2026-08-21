import XCTest
@testable import KuehllastCore

/// Tests für die Grundriss-Geometrie der 3D-Ansicht.
///
/// Hintergrund: Die Boden-Logik lief vorher in `App/Room3DView.swift` und war
/// damit auf keinem Rechner prüfbar (kein Swift unter Windows, CI testet nur das
/// Package). Genau dort steckte der vermutete Bildfehler – ein überkreuzter
/// Umriss, den SceneKit laut Apple-Doku undefiniert extrudiert. Die Fälle hier
/// bilden echte Scan-Situationen nach: verdrehte Reihenfolge, Lücken an den
/// Ecken, 13-cm-Schnipsel.
final class FloorOutlineTests: XCTestCase {

    // MARK: - Hilfsmittel

    private func w(_ x1: Double, _ z1: Double, _ x2: Double, _ z2: Double) -> WallPosition {
        WallPosition(x1: x1, z1: z1, x2: x2, z2: z2)
    }

    /// Zerlegt eine waagerechte Kante in Teilstücke – so wie ein Scan eine Wand
    /// in mehrere Fragmente zerlegt. `xs` sind die Stützstellen der Reihe nach.
    private func piecesAlongX(_ xs: [Double], z: Double) -> [WallPosition] {
        var result: [WallPosition] = []
        for i in 0..<(xs.count - 1) {
            result.append(w(xs[i], z, xs[i + 1], z))
        }
        return result
    }

    private func piecesAlongZ(_ zs: [Double], x: Double) -> [WallPosition] {
        var result: [WallPosition] = []
        for i in 0..<(zs.count - 1) {
            result.append(w(x, zs[i], x, zs[i + 1]))
        }
        return result
    }

    /// Rechteck 5 × 4 m, sauber verbunden, in Reihenfolge.
    private var rectangle: [WallPosition] {
        [w(0, 0, 5, 0), w(5, 0, 5, 4), w(5, 4, 0, 4), w(0, 4, 0, 0)]
    }

    /// L-Form: 6 × 3 m plus 3 × 2 m obendrauf = 24 m². Bounding-Box wäre 30 m².
    private var lShape: [WallPosition] {
        [w(0, 0, 6, 0), w(6, 0, 6, 3), w(6, 3, 3, 3),
         w(3, 3, 3, 5), w(3, 5, 0, 5), w(0, 5, 0, 0)]
    }

    // MARK: - Sauberer Grundriss

    /// Fängt: kaputte Verkettung, falsche Flächenformel, versehentliches
    /// Wegräumen echter Ecken durch die Kollinearitäts-Bereinigung.
    func testRechteckLiefertVierEcken() throws {
        let ring = try XCTUnwrap(FloorOutline.polygon(from: rectangle))
        XCTAssertEqual(ring.count, 4)
        XCTAssertEqual(FloorOutline.area(of: ring), 20, accuracy: 0.001)
        XCTAssertFalse(FloorOutline.isSelfIntersecting(ring))
    }

    /// Der eigentliche Zweck der ganzen Übung: Bei einem L-Raum darf NICHT die
    /// Bounding-Box herauskommen. Fängt: stiller Rückfall auf die Rechteckplatte
    /// (dann wären es 4 Punkte und 30 m² statt 6 Punkte und 24 m²).
    func testLFormLiefertSechsEcken() throws {
        let ring = try XCTUnwrap(FloorOutline.polygon(from: lShape))
        XCTAssertEqual(ring.count, 6)
        XCTAssertEqual(FloorOutline.area(of: ring), 24, accuracy: 0.001)
        XCTAssertFalse(FloorOutline.isSelfIntersecting(ring))
    }

    /// RoomPlan liefert die Wände weder sortiert noch einheitlich gerichtet.
    /// Fängt: Abhängigkeit von der Eingabereihenfolge und eine falsch herum
    /// angehängte Wand (dann käme ein Zickzack statt des L heraus).
    func testReihenfolgeUndRichtungAendernNichts() throws {
        let ordered = try XCTUnwrap(FloorOutline.polygon(from: lShape))

        // Gleiche sechs Wände: durcheinander und teilweise umgedreht.
        let shuffled: [WallPosition] = [
            w(3, 5, 3, 3),      // war (3,3)->(3,5), umgedreht
            w(0, 0, 6, 0),
            w(0, 0, 0, 5),      // war (0,5)->(0,0), umgedreht
            w(6, 3, 3, 3),
            w(0, 5, 3, 5),      // war (3,5)->(0,5), umgedreht
            w(6, 3, 6, 0)       // war (6,0)->(6,3), umgedreht
        ]

        let result = try XCTUnwrap(FloorOutline.polygon(from: shuffled))
        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(FloorOutline.area(of: result), 24, accuracy: 0.001)
        // Exakt dieselben Eckpunkte – die Werte werden nur ausgewählt, nie
        // verrechnet, deshalb ist der Mengenvergleich hier zulässig.
        XCTAssertEqual(Set(result), Set(ordered))
    }

    // MARK: - Echte Scan-Fehler

    /// Endpunkte klaffen 9–13 cm auseinander, wie bei einem echten LiDAR-Scan.
    /// Fängt: eine zu kleine oder gar nicht vorhandene Fangweiten-Eskalation –
    /// mit fester 6-cm-Fangweite käme hier `nil` heraus.
    func testLueckenAnDenEckenWerdenGeschlossen() throws {
        let scanned = [
            w(0.00, 0.00, 4.93, 0.00),
            w(5.00, 0.06, 5.00, 3.94),
            w(4.90, 4.00, 0.05, 4.00),
            w(0.00, 3.88, 0.00, 0.10)
        ]
        let ring = try XCTUnwrap(FloorOutline.polygon(from: scanned))
        XCTAssertEqual(ring.count, 4)
        // Nennmaß wäre 5 × 4 = 20 m²; durch die Lücken bleiben ~19,6 m².
        XCTAssertEqual(FloorOutline.area(of: ring), 20, accuracy: 0.6)
        XCTAssertFalse(FloorOutline.isSelfIntersecting(ring))
    }

    /// Der Feldtest-Fall: 21 Wandstücke, viele davon 13/15/23 cm lang.
    /// Fängt: fehlende Kollinearitäts-Bereinigung (dann hätte der Boden 21
    /// Stützpunkte statt 4 Ecken) und eine Kette, die an Schnipseln abbricht.
    func testVieleMiniStueckeErgebenTrotzdemVierEcken() throws {
        var walls: [WallPosition] = []
        walls += piecesAlongX([0.0, 0.13, 0.28, 0.51, 0.64, 0.79, 1.02, 1.15, 6.0], z: 0.0)
        walls += piecesAlongZ([0.0, 0.13, 0.28, 0.51, 0.64, 4.0], x: 6.0)
        walls += piecesAlongX([6.0, 5.87, 5.72, 5.49, 0.0], z: 4.0)
        walls += piecesAlongZ([4.0, 3.87, 3.72, 3.49, 0.0], x: 0.0)

        XCTAssertEqual(walls.count, 21, "Aufbau des Testfalls stimmt nicht mehr")

        let ring = try XCTUnwrap(FloorOutline.polygon(from: walls))
        XCTAssertEqual(ring.count, 4)
        XCTAssertEqual(FloorOutline.area(of: ring), 24, accuracy: 0.05)
        XCTAssertFalse(FloorOutline.isSelfIntersecting(ring))
    }

    // MARK: - Selbstschnitt (der vermutete Bildfehler)

    /// Reiner Test des Schnitterkenners an einem überkreuzten Sechseck.
    /// Fängt: einen Schnitttest, der gar nicht greift.
    func testSelbstschnittWirdErkannt() {
        let crossed = [
            FloorPoint(x: 0, z: 0), FloorPoint(x: 5, z: 0),
            FloorPoint(x: 5, z: 4), FloorPoint(x: 2, z: 4),
            FloorPoint(x: 2, z: -1), FloorPoint(x: 0, z: -1)
        ]
        // Die Kante (2,4)->(2,-1) kreuzt die Kante (0,0)->(5,0) bei (2,0).
        XCTAssertTrue(FloorOutline.isSelfIntersecting(crossed))
    }

    /// Sauberes L und sauberes Rechteck dürfen NICHT als Selbstschnitt gelten.
    /// Fängt: einen zu scharf eingestellten Schnitttest, der jeden Grundriss
    /// verwirft und damit immer auf die Rechteckplatte zurückfällt.
    func testSauberePolygoneGeltenNichtAlsSelbstschnitt() throws {
        let rectRing = try XCTUnwrap(FloorOutline.polygon(from: rectangle))
        let lRing = try XCTUnwrap(FloorOutline.polygon(from: lShape))
        XCTAssertFalse(FloorOutline.isSelfIntersecting(rectRing))
        XCTAssertFalse(FloorOutline.isSelfIntersecting(lRing))
    }

    /// Der wichtigste Test überhaupt: Diese sechs Wände verketten sich sauber,
    /// sind lang genug, füllen 40 % der Bounding-Box und bestehen alle alten
    /// Plausibilitätsprüfungen – der Ring überkreuzt sich aber. Ohne den
    /// Schnitttest käme hier ein Polygon heraus und SceneKit würde Unsinn
    /// zeichnen. Fängt genau die Regression, die zum Rückbau geführt hat.
    func testUeberkreuzterGrundrissLiefertNil() {
        let crossing = [
            w(0, 0, 5, 0),
            w(5, 0, 5, 4),
            w(5, 4, 2, 4),
            w(2, 4, 2, -1),     // schneidet die erste Wand bei (2,0)
            w(2, -1, 0, -1),
            w(0, -1, 0, 0)
        ]
        XCTAssertNil(FloorOutline.polygon(from: crossing))
    }

    // MARK: - Fälle, die `nil` liefern müssen

    /// Offene Kette: das letzte Stück endet weit vom Start entfernt.
    /// Fängt: eine Verkettung, die einen offenen Streckenzug als Ring durchwinkt.
    func testOffeneKetteLiefertNil() {
        let open = [w(0, 0, 4, 0), w(4, 0, 4, 3), w(4, 3, 2, 3)]
        XCTAssertNil(FloorOutline.polygon(from: open))
    }

    /// Zu wenige Wände für ein Polygon.
    func testZuWenigWaendeLiefertNil() {
        XCTAssertNil(FloorOutline.polygon(from: [w(0, 0, 4, 0), w(4, 0, 4, 3)]))
        XCTAssertNil(FloorOutline.polygon(from: []))
    }

    /// Manuell erfasste Räume haben gar keine Grundriss-Koordinaten; alle Punkte
    /// liegen aufeinander. Fängt: Division durch null / NaN im Umriss.
    func testEntarteteWaendeLiefernNil() {
        let degenerate = [w(0, 0, 0, 0), w(0, 0, 0, 0), w(0, 0, 0, 0), w(0, 0, 0, 0)]
        XCTAssertNil(FloorOutline.polygon(from: degenerate))
    }

    // MARK: - Fläche

    /// Fängt ein verlorenes `abs()`: im Uhrzeigersinn wäre die Fläche sonst negativ.
    func testFlaecheIstUnabhaengigVonDerUmlaufrichtung() {
        let counterClockwise = [FloorPoint(x: 0, z: 0), FloorPoint(x: 5, z: 0),
                                FloorPoint(x: 5, z: 4), FloorPoint(x: 0, z: 4)]
        let clockwise = Array(counterClockwise.reversed())
        XCTAssertEqual(FloorOutline.area(of: counterClockwise), 20, accuracy: 0.001)
        XCTAssertEqual(FloorOutline.area(of: clockwise), 20, accuracy: 0.001)
        XCTAssertEqual(FloorOutline.area(of: []), 0, accuracy: 0.001)
    }

    // MARK: - Punktbereinigung einzeln

    func testKollineareZwischenpunkteFallenWeg() {
        let ring = [FloorPoint(x: 0, z: 0), FloorPoint(x: 2, z: 0),
                    FloorPoint(x: 5, z: 0),                       // liegt auf der Kante
                    FloorPoint(x: 5, z: 4), FloorPoint(x: 0, z: 4)]
        let cleaned = FloorOutline.removeCollinear(ring, toleranceDegrees: 4)
        XCTAssertEqual(cleaned.count, 4)
        XCTAssertEqual(FloorOutline.area(of: cleaned), 20, accuracy: 0.001)
    }

    func testDoppelpunkteFallenWeg() {
        let ring = [FloorPoint(x: 0, z: 0), FloorPoint(x: 0.005, z: 0),
                    FloorPoint(x: 5, z: 0), FloorPoint(x: 5, z: 4), FloorPoint(x: 0, z: 4)]
        let cleaned = FloorOutline.dedupe(ring, minDistance: 0.03)
        XCTAssertEqual(cleaned.count, 4)
    }
}

// MARK: - Öffnungen

final class WallOpeningLocatorTests: XCTestCase {

    private func w(_ x1: Double, _ z1: Double, _ x2: Double, _ z2: Double) -> WallPosition {
        WallPosition(x1: x1, z1: z1, x2: x2, z2: z2)
    }

    private var rectangle: [WallPosition] {
        [w(0, 0, 5, 0), w(5, 0, 5, 4), w(5, 4, 0, 4), w(0, 4, 0, 0)]
    }

    /// Fängt: Zuordnung zur falschen (z. B. gegenüberliegenden) Wand und ein
    /// falsches Vorzeichen beim Abstand zur Wandmitte.
    func testFensterLandetInDerRichtigenWand() throws {
        // Fenster von x 1,5 bis 2,7 in der unteren Wand, 2 cm neben der Wandlinie.
        let opening = w(1.5, 0.02, 2.7, 0.02)
        let hit = try XCTUnwrap(WallOpeningLocator.locate(opening: opening, in: rectangle))
        XCTAssertEqual(hit.index, 0)
        // Mitte bei x = 2,1; Wandmitte bei x = 2,5 → 0,4 m davor.
        XCTAssertEqual(hit.offset, -0.4, accuracy: 0.001)
    }

    /// Fängt: eine zu großzügige Zuordnung, die freistehende Öffnungen
    /// irgendeiner Wand zuschlägt und dort ein Loch in die falsche Stelle schneidet.
    func testFreistehendeOeffnungWirdNichtZugeordnet() {
        let opening = w(2.0, 2.0, 3.0, 2.0)      // mitten im Raum
        XCTAssertNil(WallOpeningLocator.locate(opening: opening, in: rectangle))
    }

    /// Fängt: fehlende Parallelitätsprüfung – eine quer stehende Öffnung darf
    /// keiner Wand zugeordnet werden.
    func testQuerStehendeOeffnungWirdNichtZugeordnet() {
        let opening = w(0.1, 0.5, 0.1, 1.5)      // senkrecht zur unteren Wand, nah dran
        let hit = WallOpeningLocator.locate(opening: opening, in: rectangle)
        // Falls überhaupt zugeordnet, dann höchstens der linken Wand (Index 3),
        // niemals der unteren.
        XCTAssertNotEqual(hit?.index, 0)
    }

    /// Fängt: Zuordnung an ein 13-cm-Schnipsel, das gar kein Fenster tragen kann.
    func testSchnipselTraegtKeinFenster() {
        let tiny = [w(0, 0, 0.13, 0), w(0.13, 0, 0.28, 0), w(0.28, 0, 0.41, 0)]
        let opening = w(0.05, 0.01, 1.25, 0.01)
        XCTAssertNil(WallOpeningLocator.locate(opening: opening, in: tiny))
    }
}

// MARK: - Aussparungen

final class WallCutoutPlannerTests: XCTestCase {

    private let wallLength = 4.0
    private let wallHeight = 2.5

    private func plan(_ cutouts: [WallCutout]) -> [WallCutout] {
        WallCutoutPlanner.usable(cutouts, wallLength: wallLength, wallHeight: wallHeight)
    }

    func testNormalesFensterBleibt() {
        let window = WallCutout(offset: 0, width: 1.2, bottom: 0.9, height: 1.3)
        XCTAssertEqual(plan([window]), [window])
    }

    /// Fängt den Pfad-Entartungsfall: Ein Loch, das über die Wandkante
    /// hinausragt, öffnet den Umriss – SceneKit zeichnet dann Unsinn.
    func testUeberDenWandrandHinausFaelltWeg() {
        // 1,8 + 0,6 = 2,4 m, die Wand reicht nur bis 2,0 m.
        let window = WallCutout(offset: 1.8, width: 1.2, bottom: 0.9, height: 1.3)
        XCTAssertTrue(plan([window]).isEmpty)
    }

    /// Fängt: eine Aussparung, die oben aus der Wand herausläuft.
    func testUeberDieWandhoeheHinausFaelltWeg() {
        let window = WallCutout(offset: 0, width: 1.2, bottom: 1.5, height: 1.2)
        XCTAssertTrue(plan([window]).isEmpty)
    }

    /// Türen ohne Schwelle berühren die Wandunterkante – auch das entartet
    /// den Pfad. Die App muss ihnen eine kleine Schwelle geben.
    func testTuerOhneSchwelleFaelltWeg() {
        let door = WallCutout(offset: 0, width: 0.9, bottom: 0, height: 2.0)
        XCTAssertTrue(plan([door]).isEmpty)

        let doorWithSill = WallCutout(offset: 0, width: 0.9, bottom: 0.08, height: 2.0)
        XCTAssertEqual(plan([doorWithSill]).count, 1)
    }

    /// Zwei ineinanderlaufende Löcher ergeben ebenfalls einen entarteten Pfad.
    /// Das größere gewinnt. Fängt: fehlende Überschneidungsprüfung.
    func testUeberlappendeAussparungenWerdenAusgeduennt() {
        let big = WallCutout(offset: 0, width: 1.4, bottom: 0.9, height: 1.3)
        let small = WallCutout(offset: 0.5, width: 0.8, bottom: 0.9, height: 1.3)
        let result = plan([small, big])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.width, 1.4)
    }

    /// Zwei weit auseinanderliegende Fenster müssen beide bleiben.
    /// Fängt: eine zu strenge Überschneidungsprüfung, die alles bis auf ein
    /// Loch wegwirft.
    func testGetrennteAussparungenBleibenBeide() {
        let left = WallCutout(offset: -1.0, width: 0.8, bottom: 0.9, height: 1.3)
        let right = WallCutout(offset: 1.0, width: 0.8, bottom: 0.9, height: 1.3)
        let result = plan([left, right])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].offset, -1.0, accuracy: 0.001)
        XCTAssertEqual(result[1].offset, 1.0, accuracy: 0.001)
    }

    func testWinzigeAussparungFaelltWeg() {
        let slit = WallCutout(offset: 0, width: 0.1, bottom: 0.9, height: 1.3)
        XCTAssertTrue(plan([slit]).isEmpty)
    }

    func testUnbrauchbareWandmasseLiefernNichts() {
        let window = WallCutout(offset: 0, width: 1.2, bottom: 0.9, height: 1.3)
        XCTAssertTrue(WallCutoutPlanner.usable([window], wallLength: 0, wallHeight: 2.5).isEmpty)
        XCTAssertTrue(WallCutoutPlanner.usable([window], wallLength: 4, wallHeight: 0).isEmpty)
    }
}

// MARK: - Wandecken

final class WallJointTests: XCTestCase {

    private func w(_ x1: Double, _ z1: Double, _ x2: Double, _ z2: Double) -> WallPosition {
        WallPosition(x1: x1, z1: z1, x2: x2, z2: z2)
    }

    /// Im Rechteck stößt an beide Enden jeder Wand eine rechtwinklige Nachbarin.
    func testRechteckHatAnBeidenEndenEineEcke() {
        let walls = [w(0, 0, 5, 0), w(5, 0, 5, 4), w(5, 4, 0, 4), w(0, 4, 0, 0)]
        let ends = WallJoint.squareEnds(of: 0, in: walls)
        XCTAssertTrue(ends.start)
        XCTAssertTrue(ends.end)
    }

    /// Der Feldtest-Fall: Eine lange Wand ist in Fragmente zerlegt. An der
    /// Nahtstelle darf NICHT verlängert werden, sonst schieben sich die Stücke
    /// ineinander. Fängt: bedingungsloses Verlängern beider Enden.
    func testGeradeNahtstelleWirdNichtVerlaengert() {
        let walls = [w(0, 0, 2, 0), w(2, 0, 5, 0)]
        let ends = WallJoint.squareEnds(of: 0, in: walls)
        XCTAssertFalse(ends.start)
        XCTAssertFalse(ends.end)
    }

    /// Spitzer Winkel (rund 18°): auch hier würde Verlängern sichtbar überlappen.
    func testSpitzerWinkelWirdNichtVerlaengert() {
        let walls = [w(0, 0, 5, 0), w(5, 0, 8, 1)]
        let ends = WallJoint.squareEnds(of: 0, in: walls)
        XCTAssertFalse(ends.end)
    }

    /// Freies Wandende ohne Nachbarin bleibt unverlängert.
    func testFreiesEndeBleibtUnveraendert() {
        let walls = [w(0, 0, 5, 0), w(5, 0, 5, 4)]
        let ends = WallJoint.squareEnds(of: 0, in: walls)
        XCTAssertFalse(ends.start)
        XCTAssertTrue(ends.end)
    }

    func testUngueltigerIndexLiefertKeineEcken() {
        let walls = [w(0, 0, 5, 0)]
        let ends = WallJoint.squareEnds(of: 7, in: walls)
        XCTAssertFalse(ends.start)
        XCTAssertFalse(ends.end)
    }
}
