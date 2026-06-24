# Großhändler-Schnittstelle (ohne DATEV)

## Ziel

Direkte Anbindung an den Großhändler ohne DATEV als Zwischensystem. Alle Datenflüsse laufen direkt in unser Postgres-basiertes System via n8n.

---

## Benötigte Schnittstellen

### 1. Artikelstammdaten & Preise

**Format:** BMEcat 1.2 / 2005 (Standard im SHK-Handel)

| Feld | Beschreibung |
|---|---|
| Herstellernummer | Eindeutige Artikelnummer des Herstellers |
| EAN / GTIN | Barcode-Nummer |
| Großhändler-ArtNr | Interne Nummer des Großhändlers |
| Netto-EK-Preis | Einkaufspreis für unser Kundenkonto |
| Listenpreis | UVP des Herstellers |
| Lagerbestand | Verfügbare Menge |
| Lieferzeit | Werktage bis Lieferung |
| Produktbeschreibung | Text, Bilder, techn. Daten |

**Übertragung:** SFTP (täglicher Export) oder API (Echtzeit)

---

### 2. Bestellschnittstelle

**Format:** EDI EDIFACT ORDERS oder REST API

- Bestellung aufgeben
- Auftragsbestätigung empfangen (EDIFACT ORDRSP)
- Lieferstatus abfragen
- Teilbestellungen / Rückstände

---

### 3. Lieferschein (Delivery Advice)

**Format:** EDIFACT DESADV oder API

- Tatsächlich gelieferte Positionen
- Mengenabweichungen zur Bestellung
- Seriennummern / Chargennummern
- Lieferdatum und Lieferscheinnummer

---

### 4. Eingangsrechnung ← Kritisch ohne DATEV

**Format:** ZUGFeRD 2.x oder XRechnung (gesetzlicher Standard ab 2025)

- Strukturierte Rechnungsdaten (XML eingebettet in PDF)
- Automatischer Abgleich mit Bestellung und Lieferschein
- Direktimport in Postgres (kein DATEV-Umweg)
- Skonto-Fristen und Zahlungsziele

**Pflichtfelder je Rechnung:**

| Feld | Beschreibung |
|---|---|
| Rechnungsnummer | Eindeutige Belegnummer |
| Rechnungsdatum | Ausstellungsdatum |
| Lieferdatum | Leistungszeitraum |
| Positionen | ArtNr, Menge, EP, GP |
| MwSt-Aufschlüsselung | 7% / 19% |
| Zahlungsziel | Fälligkeitsdatum |
| Skonto | % und Frist |
| IBAN des Lieferanten | Für Zahlung |

---

### 5. Kontoauszug & Offene Posten

**Format:** Großhändler-Portal API, CSV oder SFTP

- Alle offenen Rechnungen
- Zahlungsstatus
- Kreditlimit und Auslastung
- Gutschriften / Retouren

---

## Datenflusss-Architektur

```
Großhändler
     │
     ├─── BMEcat (SFTP/API) ──────────── Preisliste / Artikel
     ├─── EDI ORDERS (SFTP/API) ─────── Bestellungen hin
     ├─── EDI ORDRSP (SFTP/API) ─────── Auftragsbestätigung zurück
     ├─── EDI DESADV (SFTP/API) ─────── Lieferschein
     └─── ZUGFeRD / XRechnung ────────── Eingangsrechnung
                │
                ▼
           n8n Workflows
           (Transformation, Validierung, Abgleich)
                │
                ▼
          PostgreSQL
          (Artikel, Bestellungen, Rechnungen, Zahlungen)
                │
                ▼
          Eigene Oberfläche
          (ohne DATEV)
```

---

## Checkliste: Was beim Großhändler anfragen?

- [ ] Gibt es eine **REST API** oder nur **SFTP/EDI**?
- [ ] Werden Rechnungen als **ZUGFeRD** oder **XRechnung** ausgestellt?
- [ ] Gibt es einen **BMEcat-Export** für Preislisten (täglich/wöchentlich)?
- [ ] Welches **EDI-Protokoll** wird verwendet?
- [ ] Gibt es eine **Test-/Sandbox-Umgebung**?
- [ ] Welche **Authentifizierung** (API-Key, OAuth, SFTP-Zertifikat)?
- [ ] Gibt es einen **technischen Ansprechpartner** / EDI-Koordinator?

---

## Gängige SHK-Großhändler & ihre Schnittstellen

| Großhändler | EDI | API | BMEcat | Anmerkung |
|---|---|---|---|---|
| GC-Gruppe | ✅ | teilweise | ✅ | EDIFACT Standard |
| Sonepar | ✅ | ✅ | ✅ | Eigene REST API |
| Richter+Frenzel | ✅ | ❓ | ✅ | EDI über SFTP |
| Cordes & Graefe | ✅ | ❓ | ✅ | EDIFACT |
| Hagebau | ✅ | teilweise | ✅ | |

---

## Ohne DATEV: Was übernimmt unser System?

| Aufgabe | DATEV-Weg | Unser Weg |
|---|---|---|
| Rechnungseingang | PDF → DATEV import | ZUGFeRD direkt → Postgres |
| Kontenabgleich | DATEV Sachkonten | Eigene Kontenstruktur |
| Zahlungsläufe | DATEV SEPA | Direkte SEPA-XML-Erstellung |
| Steuerauswertung | DATEV Reports | Eigene SQL-Auswertungen |
| Steuerberater-Export | DATEV-Format | CSV / DATEV-ASCII als Fallback |
