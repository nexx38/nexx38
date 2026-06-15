# Übergabe-Notiz: KI-Beleg-Erkennung in die Live-App einbauen

> Diese Notiz ist für die **Laptop-Sitzung** von Claude Code gedacht.
> Sie fasst zusammen, was in der Cloud-/Handy-Sitzung erarbeitet wurde, damit
> direkt weitergearbeitet werden kann, ohne erneut zu recherchieren.

## Ziel

Die **KI-Beleg-Erkennung** (Quittung fotografieren → Datum, Händler, Betrag,
MwSt, Kategorie werden automatisch ausgelesen) soll in die **echte Live-App**
`app.shk-innovation.de` eingebaut werden — konkret in den Bereich
**„Eingangsrechnungen"** und für das **„Datenexport / Steuerberater-Paket"**.

## Wichtigste Erkenntnis

Es gibt **mehrere getrennte Projekte**:

| Projekt | Liegt wo | URL |
|---|---|---|
| **SHK Business-App** (Kunden, Projekte, Rechnungen, **Eingangsrechnungen**, **Datenexport**) | **nur auf Hetzner** – NICHT in diesem Git-Repo | `app.shk-innovation.de` |
| Tagesplaner (`shk-planer/`) | im Repo, Branch `claude/shk-tagesplaner-pwa-GWi78` | `planer.shk-innovation.de` |
| HeizlastProfi (`app.html`) | im Repo, Branch `main` | – |
| Belege-Demo (`index.html`) | im Repo, Branch `claude/shk-company-setup-X9y7A` | nur lokal/Demo |

➡️ **Der Code der Business-App ist NICHT in GitHub.** Erster Schritt am Laptop:
ihn auf dem Server finden und ins Repo holen.

## Schritt 1 – Code auf Hetzner finden

Per SSH auf den VPS, dann:

```bash
# Welche nginx-Konfig gehört zu app.shk-innovation.de?
grep -rl "app.shk-innovation.de" /etc/nginx/
grep -rA15 "app.shk-innovation.de" /etc/nginx/sites-enabled/

# Läuft sie als Container oder als statische Dateien?
docker ps
ls -la /root/ /var/www/
```

- `root /var/www/...`  → statische Dateien dort
- `proxy_pass http://localhost:PORT` → Backend-App, Quellcode meist in `/root/...`

## Schritt 2 – Deploy-Ablauf (Vorbild: shk-planer/deploy.sh)

Die bestehende Tagesplaner-App wird so deployt (gleiches Muster erwarten):
- **PostgreSQL** im Container `shk-db` (User `shk`, DB `shkdb`)
- Frontend mit Vite gebaut (`npm run build`) → nach `/var/www/...`
- Backend als Docker-Container, dahinter **nginx**
- Deploy = `bash deploy.sh` **auf dem Server**

## Schritt 3 – KI-OCR-Logik (fertig erprobt, wiederverwendbar)

Die Beleg-Erkennung läuft direkt per Browser→Anthropic-API. Kernpunkte aus
`index.html` (Funktion `runOCR`), die übernommen werden können:

- Modell: **`claude-opus-4-8`**
- Strukturierte Ausgabe via `output_config.format` (JSON-Schema) mit Feldern:
  `datum, beschreibung, betrag, mwst (19|7|0), kategorie`
- Kategorien: material, fahrzeuge, personal, werkzeug, buero, software,
  versicherung, steuerberater, marketing, sonstiges (Tankstelle → fahrzeuge)
- Header: `x-api-key`, `anthropic-version: 2023-06-01`,
  `anthropic-dangerous-direct-browser-access: true`
- **API-Schlüssel NIEMALS ins Repo** committen — nur clientseitig/Server-Env.

> Hinweis: In einer echten Server-App ist es sauberer, den API-Call **über das
> Backend** (server.js) laufen zu lassen, damit der Schlüssel nicht im Browser
> liegt. Foto-Speicherung als base64 im localStorage (wie in der Demo) ist nur
> für den Prototyp ok – in der Live-App in die Datenbank/Dateispeicher.

## Datenbank-Zugriff (read-only, bereits verbunden)

Es gibt MCP-Werkzeuge zur SHK-Datenbank (nur lesen): Kunden suchen, Angebote /
offene Rechnungen / Termine je Kunde, Termine der nächsten X Tage, Datum.
Kein Schreib- oder Code-Zugriff darüber.

## Status der Demo (`index.html`, dieser Branch)

Vollständig & geprüft: Belege mit Foto, KI-Erkennung, Kategorie-Übersicht,
EÜR + USt-Voranmeldung, Quartals-/Jahresumschaltung. Dient als Vorlage/Referenz.
