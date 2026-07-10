# HeizlastProfi – SHK Heizlastberechnung

## Was ist das?
Web-App zur Heizlastberechnung nach DIN EN 12831 für SHK-Betriebe.
Läuft als **einzelne HTML-Datei** (app.html) — kein Server nötig, funktioniert offline.

## Infrastruktur
- **Synology NAS** → primäre Hosting-Plattform (Web Station, `http://<NAS-IP>/`)
- **GitHub Pages** → Fallback / Testing (`https://nexx38.github.io/nexx38/`)
- **Postgres (n8n)** → SHK-Kundendatenbank (Kunden, Angebote, Rechnungen)
- **n8n** → API-Gateway zwischen App und Postgres

## Entwicklung
```bash
# Lokale Dateien editieren
js/app.js         # Haupt-App-Logik, Zustand, Render-Funktionen
js/scanner.js     # Raum-Scanner: PLY-Import (Scaniverse) + Sensor-Messung
js/calc.js        # Heizlast-Berechnung (DIN EN 12831)
js/data.js        # Stammdaten (Klimazonen, U-Werte etc.)
js/modules.js     # Bauteile / Komponenten
js/modules_ui.js  # Bauteile UI
js/product_data.js # Produktdaten Heizung

css/styles.css    # Gesamt-Layout
css/scanner.css   # Scanner-Overlay
css/modules.css   # Bauteile-Modul

# App-Bundle bauen (für Deployment)
python3 build.py
# → schreibt app.html (alle CSS/JS inline, Chart.js offline eingebettet)
```

## Deployment
Push auf Branch `claude/heating-report-camera-layout-02mu7l` oder `main`
→ GitHub Actions (`pages.yml`) läuft automatisch:
1. `python3 build.py` — baut offline app.html (Chart.js wird eingebettet)
2. Pushed `app.html` auf `gh-pages` Branch

**NAS-Deployment:** `app.html` in Synology File Station → Ordner `web` legen.
Umbenennen zu `index.html` → erreichbar unter `http://<NAS-IP>/`.

## Datenspeicherung (aktuell)
Projekte → `localStorage` im Browser (nur lokal, pro Gerät).

## Geplant: Postgres-Integration via n8n
Ziel: Heizlast-Projekte mit SHK-Kunden verknüpfen.
- "Kunde laden" → n8n Webhook → Postgres → Kundendaten auto-fill
- Berechnungen speichern → n8n → Postgres → am Angebot hängen

n8n Tools (via MCP):
- `Postgres`  → Kunden suchen nach Name
- `Postgres1` → Angebote eines Kunden
- `Postgres2` → offene Rechnungen eines Kunden

## Scanner (iPhone/iPad)
- **LiDAR-Scan Tab**: PLY-Datei von Scaniverse importieren → Maße berechnen
- **Kamera Tab**: Sensor-basierte Entfernungsmessung (2 Schritte)
- Android: nur manuelle Eingabe (kein AR mehr)

## Scaniverse-Export (für Kunden/Monteure)
1. Scaniverse App → Scan öffnen → Export → **PLY (Mesh)**
2. In Downloads speichern → in HeizlastProfi unter "LiDAR-Scan" hochladen

## Geplant: Native iOS-App mit RoomPlan (statt Scaniverse-Umweg)
Ziel: Wände/Türen/Fenster direkt per LiDAR erkennen (cm-genau, wie autarc.energy),
ohne Umweg über Scaniverse + PLY-Import. Grund: **Safari/WebXR gibt LiDAR-Tiefendaten
auf iOS nicht frei** — das geht nur über eine native App, nicht im Browser.

Recherche-Ergebnis (Juli 2026):
- App wird mit Swift + Apples **RoomPlan**-Framework gebaut → liefert Wände/Türen/
  Fenster als fertiges parametrisches Modell (kein Punktwolken-Gefummel wie bei PLY)
- **Kein Apple Developer Account nötig zum Start:** GitHub Actions (macOS-Runner,
  kostenlos) baut eine **unsignierte IPA** (`CODE_SIGNING_ALLOWED=NO`)
- Installation aufs iPhone via **Sideloadly** (Windows/Mac) + normale kostenlose
  Apple-ID → App läuft 7 Tage, Sideloadly kann automatisch neu signieren solange
  der PC im selben WLAN läuft
- Upgrade-Pfad später: Apple Developer Account (99 €/Jahr) → 1 Jahr Gültigkeit
  oder TestFlight, kein Neu-Signieren mehr nötig
- Der alte Mac 2014 wird **nicht gebraucht** — Build läuft komplett in der Cloud

Workflow (Zielbild):
1. Neue App "HeizlastScan" scannt Raum mit RoomPlan → Export als JSON
   (Wände, Türen, Fenster mit Position/Maßen)
2. JSON-Import in HeizlastProfi (neuer Importpfad neben PLY) → Räume + Bauteile
   automatisch mit echten erkannten Objekten statt Schätzung angelegt
3. Alter PLY-Weg (Scaniverse) bleibt als Fallback für Android/ältere Geräte

Noch offen: Swift-App-Code schreiben, GitHub-Actions-Workflow für unsigned IPA
Build, JSON-Schnittstelle zwischen RoomPlan-Export und HeizlastProfi definieren.
