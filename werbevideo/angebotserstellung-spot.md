# Werbespot: „Angebot diktieren – fertig."

Konzept für einen Produktwerbespot im Stil der neuen plancraft-Werbung:
Ein Handwerker diktiert ein Angebot, das sofort erstellt wird. Auftrags- und
Rechnungserstellung in Rekordzeit — vergangene Projekte, Stammdaten,
Drag-and-drop, ein Klick zum Versand.

- **Format:** 9:16 (Social) + 16:9 (YouTube/Web)
- **Länge:** ca. 30 Sekunden
- **Tonalität:** Schnell, selbstbewusst, handwerksnah. Kein Buzzword-Sprech.
- **Zielgruppe:** Handwerksbetriebe (1–20 Mitarbeiter), Meister, Büro-Mitinhaberin

---

## Storyboard

### Szene 1 — Hook (0–5 s)
**Bild:** Handwerker auf der Baustelle, Staub, Werkzeuggürtel. Er zieht das
Smartphone aus der Tasche und spricht hinein.
**Diktat (O-Ton):** „Angebot für Familie Weber: Bad sanieren, 12 Quadratmeter
Fliesen, neue Dusche, Anfahrt inklusive."
**On-Screen-Text:** *Diktieren statt tippen.*

### Szene 2 — Magie-Moment (5–10 s)
**Bild:** Screen-Recording-Look: Aus dem gesprochenen Text baut sich das
Angebot sichtbar Position für Position selbst auf. Preise erscheinen automatisch.
**Voiceover:** „Dein Angebot? Fertig, bevor du zurück am Auto bist."
**On-Screen-Text:** *Angebot in Sekunden.*

### Szene 3 — Rekordzeit (10–17 s)
**Bild:** Split-Screen: links vergangene Projekte, rechts Stammdaten-Verwaltung.
Positionen werden per Drag-and-drop ins neue Dokument gezogen.
**Voiceover:** „Auftrag und Rechnung in Rekordzeit: Greif auf vergangene
Projekte zurück, verwalte deine Stammdaten und bau deine Dokumente einfach
per Drag-and-drop."
**On-Screen-Text:** *Drag-and-drop. Fertig.*

### Szene 4 — Ein Klick (17–23 s)
**Bild:** Cursor klickt auf „Senden". Kurze Versand-Animation, dann
Smartphone des Kunden: Push-Benachrichtigung „Ihr Angebot ist da".
**Voiceover:** „Ein Klick — und dein Angebot ist beim Kunden."
**On-Screen-Text:** *Ein Klick zum Kunden.*

### Szene 5 — Abschluss & CTA (23–30 s)
**Bild:** Zeitraffer: Aus dem Angebot entstehen nacheinander
Auftragsbestätigung, Lieferschein, Rechnung — jeweils mit einem Klick.
Danach Logo auf ruhigem Hintergrund.
**Voiceover:** „Alle weiteren Dokumente? Nur ein paar Klicks. Mehr Zeit fürs
Handwerk — weniger Zeit im Büro. Jetzt kostenlos testen."
**On-Screen-Text:** *Jetzt kostenlos testen.*

---

## Voiceover (kompletter Text, ~28 s)

> Dein Angebot? Fertig, bevor du zurück am Auto bist.
> Auftrag und Rechnung in Rekordzeit: Greif auf vergangene Projekte zurück,
> verwalte deine Stammdaten und bau deine Dokumente einfach per Drag-and-drop.
> Ein Klick — und dein Angebot ist beim Kunden.
> Alle weiteren Dokumente? Nur ein paar Klicks.
> Mehr Zeit fürs Handwerk — weniger Zeit im Büro. Jetzt kostenlos testen.

Sprecher: männlich, warm, norddeutsch-neutral, leicht erhöhtes Tempo.

---

## Higgsfield-Generierungsprompts (pro Szene)

Sobald Credits verfügbar sind: pro Szene `generate_video` (bzw. den
UGC-/Ad-Workflow über `get_workflow_instructions`) mit diesen Prompts nutzen.
Audio (Voiceover) separat über `generate_audio` mit dem VO-Text oben.

1. **Szene 1:** "Handheld shot, German craftsman in his 40s on a dusty
   construction site, tool belt, pulls out smartphone and speaks into it,
   golden hour light, shallow depth of field, realistic, 4K, vertical 9:16"
2. **Szene 2:** "Clean screen recording style animation, a professional quote
   document builds itself line by line from dictated speech, line items and
   prices appear with subtle motion, modern SaaS UI, white background, blue
   accent color"
3. **Szene 3:** "Split screen SaaS UI animation: left side shows a list of
   past construction projects, right side a master data panel; line items are
   dragged and dropped into a new document, smooth cursor motion, modern flat
   design"
4. **Szene 4:** "UI animation: cursor clicks a prominent 'Senden' button,
   short sending animation, cut to a customer's smartphone lighting up with a
   push notification, cozy living room background, realistic"
5. **Szene 5:** "Fast timelapse-style UI animation: one document transforms
   into order confirmation, delivery note and invoice in sequence, each with a
   single click, ends on a calm logo end card with claim text"

---

## Produktions-Checkliste

- [ ] Higgsfield-Credits aufladen (aktuell: 0, Free-Plan)
- [ ] Ad-/UGC-Workflow laden (`get_workflow_instructions`)
- [ ] Szenen 1–5 generieren (9:16 zuerst, 16:9 per `reframe`)
- [ ] Voiceover generieren (`generate_audio`)
- [ ] Schnitt: harte Cuts auf Beat, Sounddesign (Whoosh bei Drag-and-drop,
      „Pling" bei Versand)
- [ ] Endcard mit eigenem Logo/Claim (kein plancraft-Branding verwenden —
      der Spot ist vom plancraft-Stil inspiriert, darf aber nicht als
      plancraft-Werbung erscheinen)
