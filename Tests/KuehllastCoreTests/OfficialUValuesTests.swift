import XCTest
@testable import KuehllastCore

/// Tests des amtlichen U-Wert-Katalogs.
///
/// Diese Tests sind Abschreibschutz: Jeder Wert stammt aus Tabelle 2 bzw. 3
/// der Bekanntmachung vom 08.10.2020. Eine verrutschte Spalte oder eine
/// vertauschte Ziffer fällt hier auf – im PDF beim Kunden nicht mehr.
final class OfficialUValuesTests: XCTestCase {

    // MARK: - Tabellenform

    func testJedeKonstruktionHatNeunSpalten() {
        for construction in ComponentConstruction.allCases {
            XCTAssertEqual(construction.uValues.count, 9,
                           "\(construction.label) hat nicht 9 Baualtersklassen")
        }
    }

    func testJedeFensterkonstruktionHatFuenfSpalten() {
        for construction in WindowConstruction.allCases {
            XCTAssertEqual(construction.windowUValues.count, 5, construction.label)
            XCTAssertEqual(construction.glazingUValues.count, 5, construction.label)
        }
    }

    func testSpaltenIndizesSindLueckenlos() {
        XCTAssertEqual(BuildingAgeClass.allCases.map(\.column), Array(0...8))
        XCTAssertEqual(WindowAgeClass.allCases.map(\.column), Array(0...4))
    }

    func testAlleBelegtenWerteSindPlausibel() {
        // Kein U-Wert im Bestand liegt unter 0,15 oder über 6,0 –
        // fängt eine um den Faktor 10 verrutschte Zahl.
        for construction in ComponentConstruction.allCases {
            for value in construction.uValues.compactMap({ $0 }) {
                XCTAssertTrue((0.15...6.0).contains(value),
                              "\(construction.label): \(value) unplausibel")
            }
        }
        for construction in WindowConstruction.allCases {
            for value in (construction.windowUValues + construction.glazingUValues).compactMap({ $0 }) {
                XCTAssertTrue((1.0...6.0).contains(value), construction.label)
            }
        }
    }

    // MARK: - Stichproben gegen das Original (Abschreibschutz)

    func testStichprobenTabelle2() {
        XCTAssertEqual(ComponentConstruction.dachHolz.uValue(for: .bis1918) ?? 0, 2.6, accuracy: 0.001)
        XCTAssertEqual(ComponentConstruction.dachHolz.uValue(for: .a1919_1948) ?? 0, 1.4, accuracy: 0.001)
        XCTAssertEqual(ComponentConstruction.kellerdeckeStahlbeton.uValue(for: .a1949_1957) ?? 0, 2.3, accuracy: 0.001)
        XCTAssertEqual(ComponentConstruction.kellerdeckeStahlbeton.uValue(for: .a1958_1968) ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(ComponentConstruction.wandSonstigeMassivBis20.uValue(for: .bis1918) ?? 0, 3.0, accuracy: 0.001)
        XCTAssertEqual(ComponentConstruction.wandZweischaligOhneDaemmung.uValue(for: .a1969_1978) ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(ComponentConstruction.rollladenGedaemmt.uValue(for: .ab2002) ?? 0, 0.85, accuracy: 0.001)
    }

    func testTuerenSindBaualtersunabhaengig() {
        for ageClass in BuildingAgeClass.allCases {
            XCTAssertEqual(ComponentConstruction.tuerMetall.uValue(for: ageClass) ?? 0, 4.0, accuracy: 0.001)
            XCTAssertEqual(ComponentConstruction.tuerHolzKunststoff.uValue(for: ageClass) ?? 0, 2.9, accuracy: 0.001)
        }
    }

    func testStichprobenTabelle3() {
        XCTAssertEqual(WindowConstruction.holzEinfach.windowU(for: .bis1978) ?? 0, 5.0, accuracy: 0.001)
        XCTAssertEqual(WindowConstruction.kunststoffIsolier.windowU(for: .ab2002) ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(WindowConstruction.metallIsolier.windowU(for: .a1984_1994) ?? 0, 3.2, accuracy: 0.001)
        XCTAssertEqual(WindowConstruction.holzZweiScheiben.glazingU(for: .a1995_2001) ?? 0, 1.4, accuracy: 0.001)
    }

    // MARK: - Lücken bleiben Lücken

    func testNichtBelegteKombinationenLiefernNil() {
        // „keine Angabe" im Original darf niemals zu einer Zahl werden.
        XCTAssertNil(ComponentConstruction.wandVollziegelBis20.uValue(for: .a1958_1968))
        XCTAssertNil(ComponentConstruction.wandZweischaligMitDaemmung.uValue(for: .bis1918))
        XCTAssertNil(ComponentConstruction.rollladenUngedaemmt.uValue(for: .a1995_2001))
        XCTAssertNil(ComponentConstruction.bodenErdreichZiegelHolz.uValue(for: .ab2002))
        XCTAssertNil(WindowConstruction.holzEinfach.windowU(for: .a1979_1983))
    }

    func testLueckenStehenGenauInDenBelegtenZeilen() {
        // Statt eine Gesamtzahl zu behaupten, wird je Zeile geprüft, wo im
        // Original „keine Angabe" steht – das ist nachvollziehbar belegt.
        func luecken(_ construction: ComponentConstruction) -> Int {
            construction.uValues.filter { $0 == nil }.count
        }
        // Zeilen, die nur die drei ältesten Klassen führen (bis 1957):
        XCTAssertEqual(luecken(.wandVollziegelBis20), 6)
        XCTAssertEqual(luecken(.wandVollziegel20bis30), 6)
        XCTAssertEqual(luecken(.wandVollziegelUeber30), 6)
        XCTAssertEqual(luecken(.wandFachwerkLehm), 6)
        XCTAssertEqual(luecken(.wandFachwerkVollziegel), 6)
        // Zweischalig MIT Dämmung erst ab 1949:
        XCTAssertEqual(luecken(.wandZweischaligMitDaemmung), 2)
        // Rollladenkasten ungedämmt endet nach 1994:
        XCTAssertEqual(luecken(.rollladenUngedaemmt), 2)
        // Böden ohne Wert für „ab 2002":
        XCTAssertEqual(luecken(.bodenErdreichZiegelHolz), 1)
        XCTAssertEqual(luecken(.bodenErdreichHohlraumHolz), 1)
        // Alle übrigen Zeilen sind vollständig belegt.
        let vollstaendig: [ComponentConstruction] = [
            .dachMassiv, .dachHolz, .deckeMassiv, .deckeHolzbalken,
            .wandZweischaligOhneDaemmung, .wandHochlochziegel,
            .wandSonstigeMassivBis20, .wandSonstigeUeber20,
            .wandMassivholz, .wandSonstigeHolz,
            .kellerdeckeStahlbeton, .kellerdeckeHolzbalken, .kellerdeckeZiegel,
            .bodenErdreichStahlbeton, .rollladenGedaemmt,
            .tuerMetall, .tuerHolzKunststoff
        ]
        for construction in vollstaendig {
            XCTAssertEqual(luecken(construction), 0, construction.label)
        }
        // Gegenprobe: die Aufzählung deckt alle Zeilen ab.
        XCTAssertEqual(ComponentConstruction.allCases.count, vollstaendig.count + 9)
    }

    // MARK: - Baujahr-Zuordnung

    func testBaujahrZuordnungAnDenGrenzen() {
        XCTAssertEqual(BuildingAgeClass.forYear(1918), .bis1918)
        XCTAssertEqual(BuildingAgeClass.forYear(1919), .a1919_1948)
        XCTAssertEqual(BuildingAgeClass.forYear(1948), .a1919_1948)
        XCTAssertEqual(BuildingAgeClass.forYear(1949), .a1949_1957)
        XCTAssertEqual(BuildingAgeClass.forYear(1957), .a1949_1957)
        XCTAssertEqual(BuildingAgeClass.forYear(1958), .a1958_1968)
        XCTAssertEqual(BuildingAgeClass.forYear(1978), .a1969_1978)
        // 1984: Inkrafttreten der Wärmeschutzverordnung 1982 – der Schnitt,
        // den meine frühere Klasse „1979–1994" verwischt hatte.
        XCTAssertEqual(BuildingAgeClass.forYear(1983), .a1979_1983)
        XCTAssertEqual(BuildingAgeClass.forYear(1984), .a1984_1994)
        XCTAssertEqual(BuildingAgeClass.forYear(2001), .a1995_2001)
        XCTAssertEqual(BuildingAgeClass.forYear(2002), .ab2002)
        XCTAssertEqual(BuildingAgeClass.forYear(2026), .ab2002)
    }

    func testFensterZuordnungFolgtDemEinbaujahr() {
        XCTAssertEqual(WindowAgeClass.forYear(1978), .bis1978)
        XCTAssertEqual(WindowAgeClass.forYear(1979), .a1979_1983)
        XCTAssertEqual(WindowAgeClass.forYear(1994), .a1984_1994)
        XCTAssertEqual(WindowAgeClass.forYear(1995), .a1995_2001)
        XCTAssertEqual(WindowAgeClass.forYear(2002), .ab2002)
    }

    func testDerWichtigsteEinzelunterschied() {
        // Fenstertausch: altes Einfachglas gegen neues Fenster.
        let alt = WindowConstruction.holzEinfach.windowU(for: .bis1978) ?? 0
        let neu = WindowConstruction.kunststoffIsolier.windowU(for: .ab2002) ?? 0
        XCTAssertEqual(alt / neu, 3.33, accuracy: 0.01,
                       "Faktor 3,3 – deshalb braucht das Fenster ein eigenes Einbaujahr")
    }

    // MARK: - Korrektur nach Nummer 3.3

    func testNachtraeglicheDaemmungRechnetRichtig() {
        // Außenwand U₀ = 1,4; nachträglich 12 cm Mineralwolle (λ 0,04):
        // 1/1,4 = 0,714286; 0,12/0,04 = 3,0; Summe 3,714286 → U = 0,26923
        let result = OfficialUValues.withRetrofitInsulation(
            baseU: 1.4,
            layers: [(thicknessM: 0.12, lambda: OfficialUValues.lambdaMineralOderKunststoff)])
        XCTAssertEqual(result ?? 0, 0.26923, accuracy: 0.0001)
    }

    func testMehrereDaemmschichtenAddieren() {
        let einzeln = OfficialUValues.withRetrofitInsulation(
            baseU: 2.0, layers: [(0.10, 0.04)]) ?? 0
        let doppelt = OfficialUValues.withRetrofitInsulation(
            baseU: 2.0, layers: [(0.10, 0.04), (0.06, 0.05)]) ?? 0
        XCTAssertLessThan(doppelt, einzeln, "zweite Schicht muss weiter dämmen")
        // 1/2,0 + 2,5 + 1,2 = 4,2 → U = 0,238095
        XCTAssertEqual(doppelt, 0.238095, accuracy: 0.0001)
    }

    func testUnsinnigeSchichtenWerdenIgnoriert() {
        let ohne = OfficialUValues.withRetrofitInsulation(baseU: 1.4, layers: []) ?? 0
        XCTAssertEqual(ohne, 1.4, accuracy: 0.001, "ohne Dämmung bleibt der Urzustand")
        let mitMuell = OfficialUValues.withRetrofitInsulation(
            baseU: 1.4, layers: [(0, 0.04), (0.1, 0)]) ?? 0
        XCTAssertEqual(mitMuell, 1.4, accuracy: 0.001)
        XCTAssertNil(OfficialUValues.withRetrofitInsulation(baseU: 0, layers: [(0.1, 0.04)]))
    }

    func testDaemmungMachtBauteilImmerBesser() {
        for construction in ComponentConstruction.allCases {
            for ageClass in BuildingAgeClass.allCases {
                guard let base = construction.uValue(for: ageClass) else { continue }
                let corrected = OfficialUValues.withRetrofitInsulation(
                    baseU: base, layers: [(0.08, 0.04)]) ?? .infinity
                XCTAssertLessThan(corrected, base, "\(construction.label) / \(ageClass.label)")
            }
        }
    }

    func testHeizkoerpernische() {
        // Nummer 3.2: U der Nische = 2 × U der Außenwand.
        let wand = ComponentConstruction.wandHochlochziegel.uValue(for: .a1969_1978) ?? 0
        XCTAssertEqual(wand * OfficialUValues.heizkoerpernischeFaktor, 2.0, accuracy: 0.001)
    }

    // MARK: - Quellenangabe

    func testQuellenangabeNenntBekanntmachungUndTabellen() {
        let note = OfficialUValues.sourceNote
        XCTAssertTrue(note.contains("08.10.2020"))
        XCTAssertTrue(note.contains("BAnz AT 04.12.2020 B1"))
        XCTAssertTrue(note.contains("Tabellen 2 und 3"))
    }
}
