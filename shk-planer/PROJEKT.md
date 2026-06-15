# SHK Tagesplaner – Projektdokumentation

**Stand:** Juni 2026  
**URL:** https://planer.shk-innovation.de  
**Branch:** `claude/shk-tagesplaner-pwa-GWi78`

---

## Übersicht

Der SHK Tagesplaner ist eine Progressive Web App (PWA) für die tägliche Arbeitsplanung.  
Er ist direkt mit **Apple Kalender (iCloud)** und dem **SHK-Hauptprogramm** verbunden — alle drei Systeme teilen sich dieselbe PostgreSQL-Datenbank.

```
Apple Kalender (iCloud CalDAV)
        ↕  (live, bidirektional)
SHK Tagesplaner PWA          ←→   SHK Hauptprogramm
        ↕                              (app.shk-innovation.de)
    PostgreSQL (shkdb)
    Docker: shk-db
```

---

## Server / Infrastruktur

| Komponente | Details |
|---|---|
| VPS | Hetzner, IP `178.104.159.191` |
| OS-Nutzer | root |
| Domain | `planer.shk-innovation.de` |
| Reverse Proxy | nginx |
| Datenbank | PostgreSQL, Docker-Container `shk-db` |
| DB Zugangsdaten | user=`shk`, password=`shk2024sicher`, db=`shkdb` |
| Docker-Netzwerk | `shk-app_default` |

### Docker-Container im Netzwerk

| Container | Port | Beschreibung |
|---|---|---|
| `shk-db` | 5432 | PostgreSQL |
| `shk-planer-api` | 3002 (intern) | Tagesplaner Backend |
| `shk-backend` | 3000 (intern) | SHK Hauptprogramm |
| `n8n` | — | Automatisierungsplattform |

---

## Architektur

### Frontend

- **Framework:** React + Vite
- **PWA:** Workbox (vite-plugin-pwa)
- **Pfad auf VPS:** `/var/www/shk-planer/`
- **Build:** `npm run build` → `dist/` → nach `/var/www/shk-planer/` kopiert

### Backend

- **Framework:** Express.js (Node.js)
- **Datei:** `/root/shk-planer/server.js`
- **Port:** `3002` (nur intern, nginx leitet weiter)
- **Start:** Docker-Container `shk-planer-api`
- **Dockerfile:** `/root/shk-planer/Dockerfile`

### Nginx

- **Config:** `/root/shk-planer/setup/nginx.conf`
- Leitet `/api/` an `http://localhost:3002` weiter
- Serviert das Frontend aus `/var/www/shk-planer/`

---

## iCloud / Apple Kalender Integration

### Verbindungsart

CalDAV-Protokoll direkt zu Apples iCloud-Servern — kein Zwischendienst.

### Zugangsdaten (in der DB)

Tabelle `kalender_einstellungen` (in shkdb):

```sql
SELECT apple_id, app_passwort, kalender_url, home_url, aktiv
FROM kalender_einstellungen WHERE aktiv = true;
```

- `apple_id`: Apple-ID (E-Mail)
- `app_passwort`: App-spezifisches Passwort (nicht das Apple-ID-Passwort!)
- `kalender_url`: Vollständige CalDAV-URL des Kalenders
- `home_url`: CalDAV-Home-URL (für Discovery)

> **Wichtig:** App-Passwort unter https://appleid.apple.com → Anmeldung und Sicherheit → App-spezifische Passwörter erstellen.

### Wie die Synchronisation funktioniert

**Lesen (GET /api/termine?date=YYYY-MM-DD):**
1. Backend liest Zugangsdaten aus `kalender_einstellungen`
2. Sendet CalDAV `REPORT` an iCloud mit Datumsfilter
3. Parst iCal-Antwort (VCALENDAR/VEVENT)
4. Lädt zusätzlich lokale Termine aus `termine`-Tabelle
5. Merged und sortiert alle Einträge nach Uhrzeit

**Erstellen (POST /api/termine):**
1. Generiert UUID: `shkplaner-{timestamp}-{random}`
2. Baut `.ics`-String (VCALENDAR/VEVENT)
3. PUT-Request an `{kalender_url}/{uid}.ics`
4. Erscheint sofort in Apple Kalender auf allen Geräten

**Aktualisieren (PUT /api/termine/:uid):**
- Gleicher Ablauf wie Erstellen (CalDAV PUT überschreibt)

**Löschen (DELETE /api/termine/:uid):**
- DELETE-Request an `{kalender_url}/{uid}.ics`

### Relevante Funktionen in server.js

| Funktion | Aufgabe |
|---|---|
| `getKalenderCred()` | Liest Zugangsdaten aus DB |
| `caldavRequest()` | Generischer CalDAV HTTP-Request |
| `fetchIcloudEvents(von, bis)` | REPORT-Query, gibt Event-Array zurück |
| `localTermine(date)` | Lokale Termine aus `termine`-Tabelle |
| `buildIcs({uid, titel, ...})` | Erstellt iCal-String |
| `putTermin(uid, data)` | PUT zu iCloud |
| `parseIcalDt(dt)` | Parst iCal-Datumsformat |

---

## Datenbank-Tabellen

### `todos`

```sql
CREATE TABLE IF NOT EXISTS todos (
  id SERIAL PRIMARY KEY,
  text TEXT NOT NULL,
  category VARCHAR(20) DEFAULT 'office',
  person VARCHAR(50) DEFAULT 'Tamer',
  priority VARCHAR(10) DEFAULT 'medium',
  done BOOLEAN DEFAULT false,
  date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMP DEFAULT NOW()
);
```

### `timeblocks`

```sql
CREATE TABLE IF NOT EXISTS timeblocks (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  hour INTEGER NOT NULL,
  duration INTEGER DEFAULT 1,
  category VARCHAR(20) DEFAULT 'office',
  person VARCHAR(50) DEFAULT 'Tamer',
  done BOOLEAN DEFAULT false,
  date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMP DEFAULT NOW()
);
```

### `termine` (SHK Hauptprogramm)

- Vom SHK-Hauptprogramm verwaltet
- Enthält Kundentermine mit Verknüpfung zu `kunden`
- Planer liest diese ebenfalls (schreibt aber nicht zurück)

### `kalender_einstellungen` (SHK Hauptprogramm)

- Enthält iCloud-Zugangsdaten
- Wird vom SHK-Backend und Tagesplaner geteilt

---

## API-Endpunkte (Backend)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/health` | Heartbeat-Check |
| GET | `/api/termine?date=YYYY-MM-DD` | Termine + iCloud-Events |
| POST | `/api/termine` | Neuer Termin → iCloud |
| PUT | `/api/termine/:uid` | Termin aktualisieren → iCloud |
| DELETE | `/api/termine/:uid` | Termin löschen → iCloud |
| GET | `/api/todos?date=` | To-Do-Liste |
| POST | `/api/todos` | Neues To-Do |
| PUT | `/api/todos/:id` | To-Do aktualisieren |
| DELETE | `/api/todos/:id` | To-Do löschen |
| GET | `/api/timeblocks?date=` | Zeitblöcke |
| POST | `/api/timeblocks` | Neuer Zeitblock |
| PUT | `/api/timeblocks/:id` | Zeitblock aktualisieren |
| DELETE | `/api/timeblocks/:id` | Zeitblock löschen |

---

## Deploy-Prozess

### Automatisch (GitHub Actions)

Jeder Push auf `claude/shk-tagesplaner-pwa-GWi78`, der Dateien in `shk-planer/**` ändert, löst automatisch einen Deploy aus.

**Workflow:** `.github/workflows/deploy.yml`  
**SSH-Key:** GitHub-Secret `VPS_SSH_KEY`  
**Befehl auf VPS:** `bash /root/shk-planer/deploy.sh`

### Manuell

```bash
ssh root@178.104.159.191
bash /root/shk-planer/deploy.sh
```

### Deploy-Schritte (deploy.sh)

1. PostgreSQL-Tabellen anlegen (IF NOT EXISTS)
2. PWA-Icons generieren (192px + 512px PNG)
3. Frontend bauen (`node:20-alpine` Docker)
4. Frontend nach `/var/www/shk-planer/` kopieren
5. Backend-Docker-Image bauen + Container neu starten
6. Nginx-Config einlesen + reload
7. Smoke-Test: `GET /api/health`

---

## Design / UI

### Theme: „Structured"-Style (hell)

Inspiriert von der iOS-App „Structured" — helles, klares Design mit Timeline-Ansicht.

```css
--bg:      #FFFFFF
--bg2:     #F5F5F7
--bg3:     #ECEDF1
--border:  #E6E7EC
--text:    #1B1B24
--text2:   #8A8D9B
--accent:  #FF6F61   /* Koralle */
--green:   #34C759
--red:     #FF3B30
--orange:  #FF9F0A
--purple:  #AF52DE
--blue:    #3B82F6
```

### PWA-Einstellungen

- `name`: SHK Planer
- `short_name`: Planer
- `theme_color`: #FF6F61
- Icons: 192px + 512px (blaues PNG, generiert beim Deploy)
- `display`: standalone
- Cache-Strategie: iCloud-Termine werden NIE gecacht (NetworkOnly)

---

## Bekannte Eigenheiten

### iCloud-Events vs. lokale Termine

- iCloud-Events kommen von Apple CalDAV (`quelle: 'icloud'`)
- Lokale Termine aus `termine`-Tabelle kommen vom SHK-Programm (`quelle: 'lokal'`)
- Beide erscheinen in derselben Timeline

### PWA-Cache auf Mobilgeräten

Nach Updates muss die PWA einmal neu installiert werden (Browser-Cache leeren + „Zum Homescreen hinzufügen"). Service Worker nutzt `NetworkOnly` für `/api/termine` — dadurch immer aktuelle Daten.

### Docker-Netzwerk

Alle Container laufen im Netzwerk `shk-app_default`. Das Backend (`shk-planer-api`) kann die DB direkt unter `shk-db:5432` ansprechen.

---

## Geplante Features (Rückstand)

| Feature | Beschreibung |
|---|---|
| Wiederholungen / Routinen | Tägliche feste Einträge (Aufwachen 06:00, Schlafen 23:00) |
| Unified Timeline | Todos + Termine in einer einzigen Ansicht |
| Zeitlücken-Anzeige | „7h frei"-Anzeige zwischen Terminen |
| KI-Tagesplanung | Automatischer Tagesplan per Claude/Anthropic API |
| Drag & Drop | Termine per Finger verschieben |
| Push-Benachrichtigungen | PWA-Notifications für Termine |

---

## Dateipfade (VPS)

```
/root/shk-planer/
  server.js           ← Backend
  deploy.sh           ← Deploy-Skript
  Dockerfile          ← Container-Build
  package.json
  setup/
    nginx.conf        ← Nginx-Konfiguration
    init.sql          ← DB-Schema (Referenz)
  frontend/
    src/
      pages/
        Timeline.jsx  ← Hauptansicht
        TodoList.jsx  ← To-Do-Tab
      api.js          ← API-Client
      index.css       ← Globales CSS
    vite.config.js    ← PWA/Workbox-Config
    index.html

/var/www/shk-planer/  ← Gebautes Frontend (nginx serviert)
/etc/nginx/sites-available/shk-planer  ← Nginx-Config
```

---

## Kontakte / Zugänge

| Was | Wo |
|---|---|
| GitHub Repo | `nexx38/nexx38` |
| VPS SSH | `root@178.104.159.191` |
| GitHub Secret | `VPS_SSH_KEY` (SSH-Private-Key für VPS) |
| Apple CalDAV Zugangsdaten | `kalender_einstellungen` in shkdb |
