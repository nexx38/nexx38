# KühllastScan

iPhone-App zur **Kühllastberechnung** nach dem Kurzverfahren VDI 2078 – das
Sommer-Gegenstück zu HeizlastScan. Sie liest die JSON-Exporte aus HeizlastScan
direkt ein (gleiches Format, erweitert um Fenster-Ausrichtung) und gibt pro Raum
die Kühllast in Watt plus eine passende Klimageräte-Empfehlung aus.

## Was drin ist

```
KuehllastScan/
├─ Package.swift                     Swift-Package für den Rechenkern (testbar)
├─ Sources/KuehllastCore/            reine Logik, keine UI
│   ├─ Models.swift                  Room, Wall, Door, Window, InternalLoads
│   ├─ ClimateData.swift             Klimaregionen + Einstrahlung je Ausrichtung
│   ├─ CoolingLoadCalculator.swift   die Berechnung + Geräteempfehlung
│   └─ HeizlastScanImport.swift      liest HeizlastScan-JSON ein
├─ Tests/KuehllastCoreTests/         Unit-Tests des Rechenkerns
├─ App/                              SwiftUI-App
│   ├─ KuehllastScanApp.swift        @main
│   ├─ RoomStore.swift               Speicherung + Import
│   ├─ RoomListView.swift            Raumliste
│   ├─ RoomEditView.swift            Fenster/Ausrichtung, innere Lasten
│   ├─ ResultView.swift              Ergebnis + Balken + PDF teilen
│   ├─ PDFReport.swift               PDF-Bericht
│   └─ Info.plist
└─ project.yml                       XcodeGen-Projektdefinition
```

## Rechenkern testen (macOS, ohne Xcode-Projekt)

```bash
cd KuehllastScan
swift test
```

Deckt Solarlast, Verschattung, Transmission, innere Lasten, Lüftung,
Geräteempfehlung, ein Ende-zu-Ende-Beispiel (echter Raum 1) und den
JSON-Import ab.

## Als iPhone-App in Xcode öffnen

**Variante A – mit XcodeGen (empfohlen, ein Befehl):**

```bash
brew install xcodegen      # falls noch nicht vorhanden
cd KuehllastScan
xcodegen generate
open KuehllastScan.xcodeproj
```

**Variante B – von Hand:**

1. Xcode → *File ▸ New ▸ Project ▸ iOS App*, SwiftUI, Name `KuehllastScan`.
2. Die vorgefertigte `App/…swift`-Datei-Gruppe löschen und stattdessen die
   Dateien aus `App/` ins Ziel ziehen (Info.plist als Custom Info.plist setzen).
3. *File ▸ Add Package Dependencies ▸ Add Local…* und den Ordner
   `KuehllastScan` (mit der `Package.swift`) als lokales Package hinzufügen,
   Produkt `KuehllastCore` zum App-Target linken.
4. Bauen auf einem iPhone/Simulator (iOS 16+).

## Aufs iPhone ohne eigenen Mac (Windows + Sideloadly)

Sideloadly installiert eine fertige `.ipa`, kompiliert aber keinen Swift-Code.
Die `.ipa` baut ein Mac in der Cloud kostenlos über GitHub Actions – genau so
ist auch die vorhandene `HeizlastScan-unsigned-ipa` entstanden.

1. Diesen Ordner in ein **GitHub-Repo** pushen (der Workflow liegt schon in
   `.github/workflows/build-ipa.yml`).
2. Auf GitHub unter **Actions** läuft „Build unsigned IPA" automatisch (oder per
   *Run workflow* manuell starten).
3. Nach ~5 Min unten beim Lauf das Artefakt **`KuehllastScan-unsigned-ipa`**
   herunterladen und entpacken → `KuehllastScan.ipa`.
4. In **Sideloadly** die `.ipa` laden, mit deiner Apple-ID signieren, aufs
   iPhone installieren. (Kostenloser Account: alle 7 Tage neu sideloaden.)

Der Workflow läuft vorher `swift test` – schlägt ein Test fehl, bricht der Build
ab und zeigt den Fehler im Log.

## Berechnung – was passiert

Kühllast je Raum = Summe aus:

| Posten        | Formel |
|---------------|--------|
| Solar         | Fensterfläche · g-Wert · Einstrahlung(Ausrichtung) · Verschattung |
| Transmission  | U · A · ΔT über Außenwände, Außentüren, Fenster (ΔT = außen − innen) |
| Personen      | Anzahl · W/Person (Standard 100 W) |
| Geräte        | eingegebene Geräteleistung |
| Beleuchtung   | W/m² · Raumfläche |
| Lüftung       | 0,34 · Luftwechsel · Volumen · ΔT |

Die Geräteempfehlung wählt die kleinste Split-Klasse (2,0 / 2,5 / 3,5 / 5,0 /
7,0 kW), deren Nennleistung die Kühllast deckt.

**Wichtig:** Dies ist ein Kurzverfahren zur Auslegung von Split-/Multisplit-
Geräten – konservativ (maximale Einstrahlung, keine Speichermasse), gut genug
für die Praxis, aber **kein prüffähiger Nachweis**. Dafür bräuchte es das
vollständige Stundenverfahren nach VDI 2078 (siehe „Nächste Schritte“).

## Nächste Schritte / offen

- **LiDAR-Scan direkt in der App** (Apple RoomPlan), damit man nicht erst durch
  HeizlastScan muss. Andockpunkt: neue `ScanView`, die einen `Room` erzeugt.
- **Klimadaten aus DWD-Testreferenzjahren** je Postleitzahl statt der fünf
  hinterlegten Regionen.
- **Stundenverfahren (V2)** mit Gebäudespeichermasse für prüffähige Nachweise.
- **Mehrere Räume zu einem Projekt/Gebäude** summieren (Multisplit-Auslegung).

## Klimawerte anpassen

Außentemperaturen und Einstrahlung stehen in `ClimateData.swift`
(`ClimateRegion.all` und `standardIrradiance`). Die Einstrahlungswerte sind
gerundete Näherungen für Mitteleuropa und lassen sich pro Region feinjustieren.
