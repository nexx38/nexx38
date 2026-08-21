import XCTest
@testable import KuehllastCore

/// Tests für die Ventil-Datenbank des hydraulischen Abgleichs.
///
/// Das Sicherheitsnetz hat zwei Aufgaben:
/// 1. Die abgetippten Herstellertabellen bleiben fehlerfrei (Monotonie,
///    Stichproben gegen das Datenblatt, plausible Wertebereiche).
/// 2. Die Stufenauswahl bleibt korrekt – besonders an den Rändern und
///    genau auf einem Tabellenwert (Off-by-one).
final class ValveDatabaseTests: XCTestCase {

    // MARK: - Bestand der Datenbank

    func testDatenbankIstNichtLeer() {
        XCTAssertFalse(ValveDatabase.all.isEmpty)
        // Mindestens die vier belegten Hersteller plus Rückfall.
        XCTAssertTrue(ValveDatabase.all.count >= 10)
        for model in ValveDatabase.all {
            XCTAssertFalse(model.settings.isEmpty, "\(model.id) hat keine Stufen")
            XCTAssertFalse(model.name.isEmpty)
            XCTAssertFalse(model.source.isEmpty, "\(model.id) ohne Quellenangabe")
        }
    }

    /// Fängt ein doppelt eingetragenes Modell (Copy-Paste beim Ergänzen).
    func testKeineDoppeltenModelleJeHersteller() {
        var gesehen = Set<String>()
        for model in ValveDatabase.all {
            let key = "\(model.manufacturer.rawValue)|\(model.name)|\(model.size.rawValue)"
            XCTAssertFalse(gesehen.contains(key), "Modell doppelt: \(key)")
            gesehen.insert(key)
        }
        // Die ID muss die Modelle ebenfalls eindeutig unterscheiden.
        let ids = Set(ValveDatabase.all.map { $0.id })
        XCTAssertEqual(ids.count, ValveDatabase.all.count)
    }

    // MARK: - Qualität der Tabellen

    /// Der wichtigste Test: ein Tippfehler in einer kv-Tabelle (vertauschte
    /// Ziffern, verrutschte Spalte, doppelter Wert) bricht die Monotonie.
    func testKvWerteSteigenStrengMonotonMitDerStufe() {
        for model in ValveDatabase.all {
            XCTAssertTrue(model.hasStrictlyIncreasingKv,
                          "kv-Werte nicht streng monoton: \(model.id)")
            guard model.settings.count > 1 else { continue }
            for i in 1..<model.settings.count {
                XCTAssertGreaterThan(model.settings[i].kv, model.settings[i - 1].kv,
                                     "\(model.id): Stufe \(model.settings[i].label) "
                                     + "ist nicht größer als die vorige Stufe")
            }
        }
    }

    /// Fängt einen um Faktor 10 verrutschten Wert (0,52 statt 5,2 o. ä.).
    func testKvWerteLiegenInPlausiblemBereich() {
        for model in ValveDatabase.all {
            for setting in model.settings {
                XCTAssertGreaterThanOrEqual(setting.kv, 0.02,
                                            "\(model.id) Stufe \(setting.label) zu klein")
                XCTAssertLessThanOrEqual(setting.kv, 1.5,
                                         "\(model.id) Stufe \(setting.label) zu groß")
            }
        }
    }

    /// kvs (Ventil voll offen) muss mindestens so groß sein wie die
    /// oberste Voreinstellstufe – sonst stimmt eine der beiden Zahlen nicht.
    func testKvsIstNichtKleinerAlsGroessteStufe() {
        for model in ValveDatabase.all {
            guard let kvs = model.kvs else { continue }
            XCTAssertGreaterThanOrEqual(kvs, model.maxKv,
                                        "\(model.id): kvs \(kvs) < größte Stufe \(model.maxKv)")
        }
    }

    /// Alle Herstellertabellen beziehen sich auf 2 K Regeldifferenz
    /// (Auslegungsfall nach DIN EN 215). Eine versehentlich eingetragene
    /// 1-K-Spalte würde hier auffallen.
    func testAlleTabellenBeziehenSichAufZweiKelvin() {
        for model in ValveDatabase.all {
            XCTAssertEqual(model.controlDeviationK, 2.0, accuracy: 0.001,
                           "\(model.id) nicht auf 2 K bezogen")
        }
    }

    /// Herstellerangabe vs. Näherung muss korrekt gekennzeichnet sein.
    func testDatenherkunftIstGekennzeichnet() {
        for model in ValveDatabase.all where model.manufacturer != .generic {
            XCTAssertEqual(model.quality, .herstellerangabe,
                           "\(model.id) müsste Herstellerangabe sein")
            XCTAssertTrue(model.quality.isVerified)
        }
        XCTAssertEqual(ValveDatabase.genericValve.quality, .naeherung)
        XCTAssertFalse(ValveDatabase.genericValve.quality.isVerified)
    }

    // MARK: - Stichproben gegen das Datenblatt

    /// Regressionsschutz auf die abgetippten Zahlen selbst.
    /// Quelle: Danfoss Datenblatt RA-N (AI147386403838de), Zeile Xp = 2.
    func testStichprobeDanfossRaN15() throws {
        let model = try XCTUnwrap(ValveDatabase.models(of: .danfoss, size: .dn15).first)
        XCTAssertEqual(model.name, "RA-N")
        XCTAssertEqual(model.settings.map { $0.kv },
                       [0.04, 0.09, 0.16, 0.25, 0.36, 0.43, 0.52])
        XCTAssertEqual(try XCTUnwrap(model.kvs), 0.90, accuracy: 0.0001)
    }

    /// Quelle: IMI Heimeier V-exact II, Kv bei xp max. 2 K; Kvs 0,86.
    func testStichprobeHeimeierVExactII() throws {
        let model = try XCTUnwrap(ValveDatabase.models(of: .heimeier, size: .dn15).first)
        XCTAssertEqual(model.settings.map { $0.kv },
                       [0.049, 0.090, 0.150, 0.265, 0.330, 0.470, 0.590, 0.670])
        XCTAssertEqual(try XCTUnwrap(model.kvs), 0.86, accuracy: 0.0001)
        // Gegenprobe aus der Maßtabelle des Datenblatts: obere Grenze 0,670.
        XCTAssertEqual(model.maxKv, 0.670, accuracy: 0.0001)
    }

    /// Quelle: Resideo V2000SX (GE0H-2112GE23), kv-Wert bei 2 K p-Band.
    /// DN 10 endet auf Stufe 6 bei 0,51, DN 15/20 bei 0,54.
    func testStichprobeResideoV2000SX() throws {
        let dn10 = try XCTUnwrap(ValveDatabase.all.first { $0.id == "resideo-V2000SX-dn10" })
        let dn15 = try XCTUnwrap(ValveDatabase.all.first { $0.id == "resideo-V2000SX-dn15" })
        XCTAssertEqual(dn10.maxKv, 0.51, accuracy: 0.0001)
        XCTAssertEqual(dn15.maxKv, 0.54, accuracy: 0.0001)
        XCTAssertEqual(dn10.settings.count, 6)
    }

    /// Bei Danfoss ist „N" die Spülstellung (Voreinstellung aufgehoben).
    /// Sie darf nie als Abgleichstufe angeboten werden.
    func testDanfossSpuelstellungIstKeineAbgleichstufe() {
        let danfoss = ValveDatabase.models(of: .danfoss)
        XCTAssertFalse(danfoss.isEmpty)
        for model in danfoss {
            XCTAssertFalse(model.settings.contains { $0.label.uppercased() == "N" },
                           "\(model.id) bietet die Spülstellung N als Stufe an")
        }
    }

    // MARK: - Auswahl der Voreinstellung

    /// Bedarf mitten zwischen zwei Stufen → die nächsthöhere Stufe.
    func testAuswahlMittenInDerTabelle() throws {
        // Heimeier DN 15: 0,150 (Stufe 3) < 0,20 < 0,265 (Stufe 4)
        let heimeier = try XCTUnwrap(ValveDatabase.models(of: .heimeier, size: .dn15).first)
        let a = heimeier.setting(forKv: 0.20)
        XCTAssertEqual(a.status, .passend)
        XCTAssertEqual(a.setting?.label, "4")
        XCTAssertEqual(a.settingLabel, "Stufe 4")
        XCTAssertNil(a.hint)

        // Danfoss RA-N 15: 0,25 (Stufe 4) < 0,30 < 0,36 (Stufe 5)
        let danfoss = try XCTUnwrap(ValveDatabase.models(of: .danfoss, size: .dn15).first)
        let b = danfoss.setting(forKv: 0.30)
        XCTAssertEqual(b.status, .passend)
        XCTAssertEqual(b.setting?.label, "5")

        // Oventrop AV 9: 0,32 (Stufe 6) < 0,35 < 0,43 (Stufe 7)
        let oventrop = try XCTUnwrap(ValveDatabase.all.first { $0.id == "oventrop-AV 9-dn15" })
        XCTAssertEqual(oventrop.setting(forKv: 0.35).setting?.label, "7")

        // Resideo V2000SX DN 15: 0,16 (Stufe 3) < 0,20 < 0,28 (Stufe 4)
        let resideo = try XCTUnwrap(ValveDatabase.all.first { $0.id == "resideo-V2000SX-dn15" })
        XCTAssertEqual(resideo.setting(forKv: 0.20).setting?.label, "4")
    }

    /// Bedarf exakt auf einem Tabellenwert → genau diese Stufe, nicht die
    /// nächsthöhere. Wird über die ganze Datenbank geprüft.
    func testBedarfExaktAufTabellenwertTrifftGenauDieseStufe() {
        for model in ValveDatabase.all {
            for setting in model.settings {
                let result = model.setting(forKv: setting.kv)
                XCTAssertEqual(result.status, .passend,
                               "\(model.id) Stufe \(setting.label)")
                XCTAssertEqual(result.setting?.label, setting.label,
                               "\(model.id): Bedarf kv \(setting.kv) müsste Stufe "
                               + "\(setting.label) treffen, traf aber "
                               + "\(result.setting?.label ?? "keine")")
            }
        }
    }

    /// Rundungsreste aus der kv-Berechnung dürfen nicht eine Stufe zu hoch
    /// führen – ein Hauch über dem Tabellenwert bleibt dieselbe Stufe,
    /// ein echter Mehrbedarf steigt auf.
    func testFliesskommaToleranzAnDerStufengrenze() throws {
        let danfoss = try XCTUnwrap(ValveDatabase.models(of: .danfoss, size: .dn15).first)
        // Stufe 3 = 0,16; Stufe 4 = 0,25
        XCTAssertEqual(danfoss.setting(forKv: 0.16 + 1e-15).setting?.label, "3")
        XCTAssertEqual(danfoss.setting(forKv: 0.16 - 1e-15).setting?.label, "3")
        XCTAssertEqual(danfoss.setting(forKv: 0.16 + 1e-6).setting?.label, "4")
    }

    /// Bedarf unter der kleinsten Stufe → kleinste Stufe plus Hinweis.
    func testBedarfUnterKleinsterStufe() throws {
        let heimeier = try XCTUnwrap(ValveDatabase.models(of: .heimeier, size: .dn15).first)
        let result = heimeier.setting(forKv: 0.01)   // kleinste Stufe = 0,049
        XCTAssertEqual(result.status, .unterMinimum)
        XCTAssertEqual(result.setting?.label, "1")
        XCTAssertTrue(result.isUsable)
        XCTAssertNotNil(result.hint)
    }

    /// Bedarf über der größten Stufe → keine Stufe, klarer Hinweis.
    func testBedarfUeberGroesserStufe() throws {
        let heimeier = try XCTUnwrap(ValveDatabase.models(of: .heimeier, size: .dn15).first)
        let result = heimeier.setting(forKv: 1.0)    // größte Stufe = 0,670
        XCTAssertEqual(result.status, .ueberMaximum)
        XCTAssertNil(result.setting)
        XCTAssertFalse(result.isUsable)
        XCTAssertEqual(result.settingLabel, "Ventil zu klein")
        XCTAssertNotNil(result.hint)
    }

    /// Genau auf der größten bzw. kleinsten Stufe ist noch „passend" –
    /// die Randfälle dürfen nicht eine Stufe zu früh umkippen.
    func testExakteRaenderSindNochPassend() throws {
        let danfoss = try XCTUnwrap(ValveDatabase.models(of: .danfoss, size: .dn15).first)
        let oben = danfoss.setting(forKv: danfoss.maxKv)
        XCTAssertEqual(oben.status, .passend)
        XCTAssertEqual(oben.setting?.label, "7")

        let unten = danfoss.setting(forKv: danfoss.minKv)
        XCTAssertEqual(unten.status, .passend)
        XCTAssertEqual(unten.setting?.label, "1")
    }

    /// Unsinnige Eingaben dürfen nicht abstürzen und müssen definiert enden.
    func testNegativerOderNullBedarf() throws {
        let heimeier = try XCTUnwrap(ValveDatabase.models(of: .heimeier, size: .dn15).first)
        for bedarf in [0.0, -1.0, -1000.0] {
            let result = heimeier.setting(forKv: bedarf)
            XCTAssertEqual(result.status, .unterMinimum)
            XCTAssertEqual(result.setting?.label, "1")
            XCTAssertEqual(result.kvNeeded, 0, accuracy: 0.0001)
        }
    }

    // MARK: - Umrechnung Volumenstrom → kv

    /// Von Hand nachgerechnet:
    /// m = Q · 0,86 / ΔT = 800 · 0,86 / 10 = 68,8 kg/h
    /// kv = 0,0688 m³/h / √0,1 bar = 0,21756 m³/h
    func testVolumenstromUndKvUmrechnung() {
        XCTAssertEqual(ValveDatabase.flowKgPerH(loadW: 800, spreadK: 10),
                       68.8, accuracy: 0.001)
        XCTAssertEqual(ValveDatabase.kvNeeded(loadW: 800, spreadK: 10),
                       0.217565, accuracy: 0.00001)
        XCTAssertEqual(ValveDatabase.kvNeeded(flowKgPerH: 68.8, valveDpMbar: 100),
                       0.217565, accuracy: 0.00001)
    }

    /// Definition von kv: Durchfluss in m³/h bei 1 bar Druckverlust.
    /// Bei Δp = 1000 mbar muss kv also zahlengleich zum Volumenstrom sein.
    func testKvDefinitionBeiEinemBar() {
        XCTAssertEqual(ValveDatabase.kvNeeded(flowKgPerH: 250, valveDpMbar: 1000),
                       0.25, accuracy: 1e-12)
        XCTAssertEqual(ValveDatabase.kvNeeded(flowKgPerH: 1000, valveDpMbar: 1000),
                       1.0, accuracy: 1e-12)
        // Bei 100 mbar: kv = 0,1 / √0,1 = √0,1
        XCTAssertEqual(ValveDatabase.kvNeeded(flowKgPerH: 100, valveDpMbar: 100),
                       0.31622776601683794, accuracy: 1e-10)
    }

    /// Die Umrechnung muss dieselbe Physik verwenden wie der bestehende
    /// vereinfachte Abgleich – sonst weichen App-Anzeigen voneinander ab.
    func testUmrechnungPasstZumBestehendenAbgleich() {
        // Letzter Fall liegt unter der 3-K-Grenze: beide Wege müssen dort
        // gleich abfangen, sonst zeigt die App zwei verschiedene Zahlen an.
        for (loadW, spreadK) in [(800.0, 10.0), (1500.0, 15.0), (450.0, 8.0), (600.0, 1.0)] {
            let alt = HydraulicBalancing.preset(loadW: loadW, spreadK: spreadK)
            XCTAssertEqual(ValveDatabase.flowKgPerH(loadW: loadW, spreadK: spreadK),
                           alt.flowKgPerH, accuracy: 0.0001)
            XCTAssertEqual(ValveDatabase.kvNeeded(loadW: loadW, spreadK: spreadK),
                           alt.kvNeeded, accuracy: 0.0001)
        }
    }

    /// Rechenbeispiel aus dem IMI-Heimeier-Datenblatt selbst:
    /// Q = 1308 W, ΔT = 15 K, Δp = 110 mbar → Voreinstellung 4 (bei 2 K).
    /// Das prüft Umrechnung und Stufenauswahl in einem Durchgang gegen
    /// eine Lösung, die der Hersteller vorgibt.
    func testRechenbeispielAusDemHeimeierDatenblatt() throws {
        let flow = ValveDatabase.flowKgPerH(loadW: 1308, spreadK: 15)
        XCTAssertEqual(flow, 75, accuracy: 0.05)

        let model = try XCTUnwrap(ValveDatabase.models(of: .heimeier, size: .dn15).first)
        let result = ValveDatabase.recommend(model: model, loadW: 1308,
                                             spreadK: 15, valveDpMbar: 110)
        XCTAssertEqual(result.kvNeeded, 0.2261, accuracy: 0.0005)
        XCTAssertEqual(result.status, .passend)
        XCTAssertEqual(result.setting?.label, "4")
    }

    /// Grenzwerte dürfen nicht zu Division durch Null oder inf führen.
    func testUmrechnungBleibtEndlich() {
        // Spreizung 0 wird bei 3 K abgefangen: 800 · 0,86 / 3 = 229,33 kg/h.
        XCTAssertEqual(ValveDatabase.flowKgPerH(loadW: 800, spreadK: 0),
                       229.3333, accuracy: 0.001)
        XCTAssertEqual(ValveDatabase.flowKgPerH(loadW: -500, spreadK: 10),
                       0, accuracy: 0.001)
        XCTAssertTrue(ValveDatabase.kvNeeded(flowKgPerH: 100, valveDpMbar: 0).isFinite)
        XCTAssertTrue(ValveDatabase.kvNeeded(loadW: 0, spreadK: 0).isFinite)
    }

    // MARK: - Rückfall und Abfragen

    /// Der Rückfall muss exakt so rechnen wie der bisherige generische
    /// Abgleich – sonst ändert sich das Ergebnis für Bestandsprojekte.
    func testGenerischesModellPasstZuHydraulicBalancing() {
        XCTAssertEqual(ValveDatabase.genericSettings.map { $0.kv },
                       HydraulicBalancing.presetKv.map { $0.kv })
        XCTAssertEqual(ValveDatabase.genericSettings.map { $0.label },
                       HydraulicBalancing.presetKv.map { String($0.stage) })
        XCTAssertEqual(ValveDatabase.fallback.id, ValveDatabase.genericValve.id)
        XCTAssertEqual(ValveDatabase.fallback.manufacturer, .generic)
    }

    func testAbfragenLiefernDieRichtigenModelle() throws {
        XCTAssertFalse(ValveDatabase.models(of: .heimeier).isEmpty)
        XCTAssertFalse(ValveDatabase.models(of: .oventrop).isEmpty)
        XCTAssertFalse(ValveDatabase.models(of: .danfoss).isEmpty)
        XCTAssertFalse(ValveDatabase.models(of: .resideo).isEmpty)

        for model in ValveDatabase.models(of: .danfoss, size: .dn20) {
            XCTAssertEqual(model.manufacturer, .danfoss)
            XCTAssertEqual(model.size, .dn20)
        }
        for model in ValveDatabase.models(size: .dn10) {
            XCTAssertEqual(model.size, .dn10)
        }

        let erstes = try XCTUnwrap(ValveDatabase.all.first)
        XCTAssertEqual(ValveDatabase.model(id: erstes.id)?.id, erstes.id)
        XCTAssertNil(ValveDatabase.model(id: "gibt-es-nicht"))
    }

    /// Taconova ist als Hersteller vorgesehen, hat aber (noch) keine
    /// belegten kv-Tabellen – die Auswahlliste darf keinen leeren
    /// Eintrag anbieten.
    func testAuswahllisteZeigtNurBelegteHersteller() {
        let belegt = ValveDatabase.populatedManufacturers
        XCTAssertTrue(belegt.contains(.heimeier))
        XCTAssertTrue(belegt.contains(.oventrop))
        XCTAssertTrue(belegt.contains(.danfoss))
        XCTAssertTrue(belegt.contains(.resideo))
        XCTAssertTrue(belegt.contains(.generic))
        XCTAssertFalse(belegt.contains(.taconova))
        XCTAssertTrue(ValveDatabase.models(of: .taconova).isEmpty)
    }

    // MARK: - Speicherung

    /// Das gewählte Modell wird in der Heizkörperakte gespeichert –
    /// Codable muss verlustfrei hin und zurück gehen.
    func testModellIstVerlustfreiCodierbar() throws {
        let original = try XCTUnwrap(ValveDatabase.models(of: .oventrop, size: .dn15).first)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ValveModel.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.settings.map { $0.kv }, original.settings.map { $0.kv })
    }

    func testBeschriftungenSindGefuellt() {
        for manufacturer in ValveManufacturer.allCases {
            XCTAssertFalse(manufacturer.label.isEmpty)
        }
        for size in ValveSize.allCases {
            XCTAssertFalse(size.label.isEmpty)
            XCTAssertTrue(size.label.contains("DN"))
        }
        XCTAssertEqual(ValveSize.dn15.dn, 15)
        XCTAssertEqual(ValveSize.dn15.inchLabel, "1/2\"")
        XCTAssertEqual(ValveDatabase.kvLabel(0.2175647), "0,218")
    }
}
