# Übergabe-Notiz für die Laptop-Sitzung (Claude Code mit SSH/paramiko)

> Diese Notiz schreibt die **Cloud-Sitzung** (kein Server-Zugriff).
> Die **Laptop-Sitzung** liest sie und arbeitet direkt auf dem Server weiter.
> **Passwörter stehen NICHT hier** – die kennt der Nutzer.

**Letzter Stand:** 2026-06-15 · Branch `claude/shk-company-setup-X9y7A`

---

## TL;DR – Was gerade gilt

- ✅ Die **Rechnungs-Automatik läuft wieder sauber** (`/root/poll_rechnungsmail.py`, alle 10 Min).
- ✅ Die hängende Rechnung **#8352905** (GOTTSCHALL & SOHN, 7,04 €) ist **gebucht**.
- ✅ Ein versehentlich angelegtes Duplikat-Skript wurde wieder entfernt.
- ⚠️ Eine **Lücke** bleibt: Die Automatik holt nur **ungelesene** Mails → manuell im Webmail geöffnete Rechnungen werden für immer übersprungen. **Das war die Ursache.**
- 🎯 Nutzer-Wunsch: **direkt auf dem Server arbeiten, ohne GitHub-Umweg.**

---

## Der Server (Hetzner)

| Was | Wert |
|---|---|
| Host | `ubuntu-4gb-nbg1-1` |
| IP | `178.104.159.191` |
| Login | `root@178.104.159.191` (Passwort kennt der Nutzer) |
| App | `app.shk-innovation.de` (Docker compose, **nicht** in GitHub) |

**Container:** `shk-backend` (Port 3000), `shk-frontend` (nginx, 8082), `shk-db` (PostgreSQL: User `shk`, DB `shkdb`), `n8n`.

**DB-Zugriff:** `docker exec shk-db psql -U shk -d shkdb -c "..."`

---

## Die Rechnungs-Automatik (funktioniert)

**Skript:** `/root/poll_rechnungsmail.py` · **Log:** `/var/log/poll_rechnungsmail.log`
**Cron:** `*/10 * * * * /usr/bin/python3 /root/poll_rechnungsmail.py`

Ablauf:
1. IMAP `imap.strato.de:993`, Postfach `rechnungen@shk-innovation.de` (PW kennt Nutzer)
2. Sucht **UNSEEN**-Mails, lädt PDF-Anhänge
3. POST an `http://localhost:3000/api/eingangsrechnungen/upload`
4. Backend bucht + macht KI-OCR; **erkennt Duplikate selbst** (`result.duplikat`) → keine Doppelbuchung
5. Markiert Mail erst als **Seen**, wenn Upload geklappt hat (`mail_ok`)

**Andere Cronjobs (nicht anfassen):** `poll_calls.py` (vapi), `monitor.py`, `backup.sh` (täglich 2 Uhr).

---

## Die offene Lücke (Ursache des Problems)

Das Skript verlässt sich auf das **Gelesen/Ungelesen-Flag**. Wird eine Rechnungs-Mail
vorher im Webmail geöffnet → sie ist „Seen" → die `UNSEEN`-Suche überspringt sie dauerhaft.
Genau so ist #8352905 durchgerutscht.

**Empfohlener Fix (mit Nutzer abstimmen, Backup vorher!):**
Statt auf das Seen-Flag zu setzen, eine kleine Zustandsdatei führen
(`/root/.rechnung_seen_msgids`) mit bereits verarbeiteten **Message-IDs**.
Dann werden auch manuell geöffnete Mails verarbeitet, und nichts doppelt
(Backend-Duplikatschutz greift zusätzlich).

---

## Backend-Modul (auf dem Server, fertig)

`/opt/shk-app/backend/eingangsrechnungen.js` – komplett mit KI-OCR:
- `verarbeitePdf()` nutzt `@anthropic-ai/sdk`, Modell aktuell `claude-sonnet-4-5-20250929`
  (optional auf **`claude-opus-4-8`** anheben für bessere Erkennung)
- Routes: `POST/GET /api/eingangsrechnungen`, `/:id`, `/:id/pdf`, `PATCH`, `DELETE`
- API-Key liegt in DB-Tabelle `einstellungen` (`schluessel='anthropic_api_key'`), **nicht** in Env.

---

## Arbeitsweise: direkt auf dem Server (ohne GitHub)

Der Nutzer will **keinen GitHub-Umweg** mehr. In der Laptop-Sitzung:
- Per SSH (paramiko) einloggen und Dateien **direkt** in `/root/` bzw. `/opt/shk-app/` ändern.
- **Vor jeder Änderung Backup** (`cp datei datei.bak` bzw. `backup.sh`).
- GitHub nur optional als Sicherung – für den Arbeitsfluss nicht nötig.

---

## Offene Punkte / ToDo

1. **Betrag prüfen:** #8352905 = 7,04 € wirkt klein – gegen Original-PDF abgleichen, ggf. in der App korrigieren.
2. **Lücke schließen:** Message-ID-Tracking statt Seen-Flag (siehe oben), nur nach Nutzer-OK.
3. **Sicherheit:** Server- und Mail-Passwort wurden im Chat geteilt → ändern.
4. **Optional:** OCR-Modell auf `claude-opus-4-8` anheben.
