# HeizlastScan — native iOS LiDAR-Scan-App

Native App (Swift + Apple RoomPlan), die einen Raum mit dem LiDAR-Sensor scannt
und **Wände, Fenster und Türen als fertige Objekte** erkennt — cm-genau, ohne
Umweg über Scaniverse. Der Export ist eine JSON-Datei, die HeizlastProfi direkt
importiert (Tab „LiDAR-Scan" → `.json`).

## Warum eine eigene App?
Safari gibt auf dem iPhone **keine LiDAR-/Tiefendaten** frei (Stand 2026, WebXR
auf iOS nicht verfügbar). RoomPlan gibt es nur nativ. Deshalb dieser Weg.

## Voraussetzung am Gerät
iPhone/iPad **mit LiDAR**: iPhone 12 Pro oder neuer (Pro-Modelle), iPad Pro ab 2020.

---

## 1. IPA bauen (kostenlos, in der Cloud — kein Mac nötig)

Der Build läuft auf GitHub Actions (macOS-Runner):

1. GitHub → Repo `nexx38/nexx38` → Tab **Actions**
2. Links **„Build HeizlastScan IPA (unsigned)"** wählen
3. Rechts **„Run workflow"** → Branch wählen → **Run workflow**
4. Nach ~5–8 Min. ist der Lauf grün → unten unter **Artifacts** liegt
   **`HeizlastScan-unsigned-ipa`** → herunterladen → entzippen → `HeizlastScan.ipa`

Die IPA ist **unsigniert** — sie wird erst beim Sideloading mit deiner Apple-ID signiert.

## 2. Auf das iPhone bringen — Sideloadly (kostenlos)

1. **Sideloadly** installieren (Windows oder Mac): https://sideloadly.io
2. iPhone per Kabel anschließen, am iPhone **„Diesem Computer vertrauen"**
3. In Sideloadly:
   - `HeizlastScan.ipa` ins Fenster ziehen
   - **Apple-ID** eintragen (deine normale, kostenlose reicht)
   - **Start** → Passwort/2FA bestätigen
4. Am iPhone: **Einstellungen → Allgemein → VPN & Geräteverwaltung** →
   deine Apple-ID → **Vertrauen**
5. App **HeizlastScan** öffnen → scannen

### Gültigkeit
- **Kostenlose Apple-ID:** App läuft **7 Tage**, dann in Sideloadly erneut
  signieren (Auto-Refresh hält sie aktiv, solange PC + iPhone im selben WLAN sind).
- **Apple Developer Account (99 €/Jahr):** 1 Jahr gültig, kein wöchentliches
  Neu-Signieren. Optionaler Komfort — zum Testen nicht nötig.

## 3. Scan in HeizlastProfi übernehmen
1. In HeizlastScan Raum scannen → **„Scan fertig"** → **„JSON teilen / sichern"**
   → in Dateien sichern (oder direkt an dich per AirDrop)
2. In HeizlastProfi: Raum → **Scan** → Tab **LiDAR-Scan** → die `.json` wählen
3. Fläche, Höhe, Fenster & Türen sind vorbelegt → **In Raum übernehmen**

---

## Projektstruktur
```
ios/
  project.yml                     # XcodeGen-Projektdefinition
  HeizlastScan/
    HeizlastScanApp.swift         # App-Einstieg (SwiftUI)
    ContentView.swift             # Scan-UI, Ergebnis, Teilen
    RoomScanView.swift            # RoomCaptureView-Bridge (RoomPlan)
    RoomExport.swift              # CapturedRoom → JSON-Schema
    Info.plist                    # Kamera-Berechtigung, ARKit
```

## JSON-Schema (Schnittstelle zu HeizlastProfi)
```json
{
  "app": "HeizlastScan", "version": 2,
  "scannedAt": "2026-07-10T14:00:00Z",
  "name": "Wohnzimmer",
  "floorArea": 24.5, "height": 2.55,
  "walls":   [{ "width": 4.9, "height": 2.55, "x1": 0, "z1": 0, "x2": 4.9, "z2": 0 }],
  "windows": [{ "width": 1.4, "height": 1.3,  "x1": 1.5, "z1": 0, "x2": 2.9, "z2": 0 }],
  "doors":   [{ "width": 0.9, "height": 2.0,  "x1": 4.9, "z1": 1.0, "x2": 4.9, "z2": 1.9 }]
}
```
`x1/z1/x2/z2` (ab v2) sind die beiden Endpunkte jedes Bauteils in einem
gemeinsamen, raum-lokalen 2D-Koordinatensystem (Meter) — daraus zeichnet
`Scanner.drawFloorPlan()` den Grundriss. v1-Dateien ohne diese Felder werden
weiter unterstützt, zeigen aber keinen Grundriss.
Muss synchron bleiben mit `scanner.js` → `_loadRoomPlanJSON`.

## Bekannte Grenzen / nächste Schritte
- Grundfläche = orientierte Bounding-Box der Wände (OBB, robust gegen
  schrägen Scan). Für L-förmige Räume später auf die iOS-17-Floor-Polygon-API
  umstellen (exakter).
- Mehrere Räume: aktuell 1 Scan = 1 Raum. Multi-Room folgt bei Bedarf.
- 2D-Grundriss: siehe `Scanner.drawFloorPlan()` in `js/scanner.js` — wird im
  Scan-Bestätigungsbildschirm und im Raum-Editor (falls gespeichert) gezeigt.
