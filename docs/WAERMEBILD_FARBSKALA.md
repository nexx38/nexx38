# Wärmebild-Farbskala für die 3D-Ansicht

Spezifikation für den zweiten Anzeigemodus in `Room3DView` (SceneKit).
Stand: 21.08.2026 · gilt für den Heizfall (DIN EN 12831, vereinfacht).

---

## 0. Die Entscheidung in fünf Sätzen

1. **Eingefärbt wird der flächenbezogene Verlust q = U · ΔT in W/m²** — nicht der absolute Verlust in Watt.
2. **Feste, absolute Schwellen** (15 / 30 / 50 / 80 W/m²), niemals relativ zum Raum-Maximum.
3. **Fünf diskrete Klassen**, sequenziell, monoton fallende Helligkeit, in Deuteranopie und Protanopie geprüft.
4. **Das Licht wird abgeschaltet** (`lightingModel = .constant`) — sonst färbt die Beleuchtung die Daten um.
5. **Die absoluten Watt stehen daneben als sortierte Balkenliste**, nicht als zweiter Farbmodus.

---

## 1. Was wird kodiert: q = U · ΔT [W/m²]

**Entscheidung: flächenbezogen. Ein Modus, kein Umschalter.**

### Warum nicht absolut in Watt

In einer 3D-Ansicht ist die Fläche **schon geometrisch kodiert** — die große Fassade ist groß, das kleine Fenster ist klein. Würde die Farbe den absoluten Verlust zeigen, wäre sie eine zweite Kodierung derselben Information: groß → viel Watt → dunkelrot. Der Farbkanal trüge nichts Neues und das schlechte kleine Fenster (U = 5,0) bliebe hellgrün neben der guten großen Wand. Genau die Aussage, die verkauft, ginge verloren.

### Warum flächenbezogen die ehrlichere Aussage ist

Das Auge integriert in einer Fläche automatisch **Größe × Farbintensität**. Ist die Farbe q = Φ/A und die Fläche A, dann entspricht der wahrgenommene „Farbeindruck insgesamt" ungefähr A · q = Φ — **dem absoluten Verlust.** Die Geometrie liefert also den Flächenfaktor gratis, und beide Fragen werden gleichzeitig richtig beantwortet:

| Frage | Wer beantwortet sie |
|---|---|
| „Welches Bauteil ist schlecht?" | die Farbe (q in W/m²) |
| „Welches Bauteil kostet am meisten?" | Fläche × Farbe, wahrgenommen — und exakt in der Balkenliste (Abschnitt 5) |

Zweiter, praktischer Vorteil: **q = A·U·ΔT / A = U · ΔT.** Keine Division, keine Fläche im Nenner, keine Artefakte bei winzigen Bauteilen, kein Sonderfall bei A → 0.

### Warum kein Umschalter W ↔ W/m²

Ein Umschalter kostet vor dem Kunden drei Sätze Erklärung und erzeugt die Frage „welches der beiden Bilder ist denn nun wahr?". Wer absolute Watt vergleichen will, soll sie nicht als Farbe lesen — **Länge wird deutlich genauer decodiert als Farbe.** Deshalb: absolute Watt als sortierte Balkenliste unter der 3D-Ansicht, Farbe bleibt eindeutig q.

### Wichtig: ΔT ist das **tatsächliche** ΔT des Bauteils

Also `indoor − adjacentTemp` bei Erdreich-/unbeheizt-Wänden, sonst `indoor − outdoor`. **Nicht** auf ein Referenz-ΔT normieren.

Begründung: nur so gilt Σ (A · q) = Transmissionsverlust des Raums. Die Farbsumme im Bild bleibt mit der Rechnung konsistent. Folge, die im Text stehen **muss**: eine Kellerwand mit U = 1,5 (ΔT 10 K) erscheint kühler als eine gleich schlechte Außenwand (ΔT 32 K) — und das ist richtig, sie verliert tatsächlich weniger. Deshalb heißt die Legende **„Verlust je m²"** und niemals „Dämmqualität" oder „U-Wert-Ampel". Bei dieser Beschriftung wäre die Kellerwand-Darstellung eine Falschaussage.

### Was NICHT in die Farbe eingeht

- **Wärmebrückenzuschlag** (pauschal 5 %): ein gleichmäßiger Faktor auf alles. Er verändert das Bild nicht, kann aber Bauteile künstlich über eine Klassengrenze schieben. → nicht einrechnen, als Zahl in der Fußzeile ausweisen.
- **Lüftungsverlust Φ_V**: hat keine Fläche. → nicht einfärbbar, als Zahl in der Fußzeile ausweisen (Abschnitt 7).

---

## 2. Skalierung: feste Schwellen

**Entscheidung: absolute, feste Grenzen bei 15 / 30 / 50 / 80 W/m². Nie relativ.**

### Warum relativ ausscheidet

- Eine relative Skala **färbt immer irgendetwas rot** — auch im KfW-40-Neubau. Ein Werkzeug, das jedem Haus einen Schuldigen zuweist, verliert beim ersten guten Objekt seine Glaubwürdigkeit.
- Sie macht **Vorher/Nachher unmöglich**. Genau das ist die Verkaufsgeschichte: heute rote Fenster, nach dem Tausch grüne. Bei einer relativen Skala sähen beide Bilder gleich aus, weil sich die Skala mitverschiebt. Das wäre die 3D-Variante der abgeschnittenen Balken-Achse.
- Sie macht **Raumvergleiche unmöglich** (Wohnzimmer vs. Keller vs. Nachbarhaus).

### Die Klassen

| Klasse | q [W/m²] | Wortlaut in der App | entspricht bei ΔT = 32 K |
|---|---|---|---|
| 1 | < 15 | unauffällig | U < 0,47 |
| 2 | 15 – 30 | leicht erhöht | U 0,47 – 0,94 |
| 3 | 30 – 50 | deutlich erhöht | U 0,94 – 1,56 |
| 4 | 50 – 80 | hoch | U 1,56 – 2,50 |
| 5 | ≥ 80 | sehr hoch | U ≥ 2,50 |
| – | = 0 | kein Verlust (Innenbauteil) | neutral, außerhalb der Skala |

Die Grenzen sind bewusst **grob und ungleichmäßig**. Sie sind an Handlungsempfehlungen kalibriert, nicht an gleiche Zahlenabstände.

### Kalibrierung am realen Gebäudebestand (ΔT = 32 K)

| Bauteil | U | q [W/m²] | Klasse |
|---|---|---|---|
| Dach GEG-Neubau | 0,20 | 6 | 1 |
| Außenwand saniert / GEG | 0,24 – 0,28 | 8 – 9 | 1 |
| Außenwand 1984–1994 | 0,60 | 19 | 2 |
| Außenwand 1978–1983 | 0,80 | 26 | 2 |
| **Fenster 3-fach (bestmöglich)** | 0,80 | **26** | **2** |
| Außenwand 1969–1978 | 1,00 | 32 | 3 |
| Fenster GEG-Höchstwert | 1,30 | 42 | 3 |
| Außenwand Vollziegel unsaniert | 1,40 | 45 | 3 |
| Außenwand 24er Ziegel ungedämmt | 1,70 | 54 | 4 |
| Fenster 2-fach, 1990er | 1,80 | 58 | 4 |
| Dach ungedämmt | 2,00 | 64 | 4 |
| Fenster Isolierglas 1980er | 2,80 | 90 | 5 |
| Alte Haustür | 3,50 | 112 | 5 |
| Einfachverglasung | 5,00 | 160 | 5 |
| Kellerwand Erdreich U 1,5 (ΔT 10 K) | 1,50 | **15** | 2 |

**Prüfsteine, die diese Grenzen bestehen:**

- *Top-Neubau:* Wände und Dach Klasse 1, Fenster Klasse 2 → **kein Rot im Bild.** Genau richtig.
- *Haus 1965 unsaniert:* Wände Klasse 3, Fenster/Tür Klasse 5 → Botschaft „zuerst die Fenster". Das ist auch fachlich die richtige Reihenfolge.
- *Haus 1995:* Wände Klasse 2, Fenster Klasse 4 → „Fenster tauschen". Richtig.

Glas verliert je m² grundsätzlich das Vier- bis Zehnfache einer Wand. Dass Fenster im Bild deshalb systematisch heißer erscheinen, ist keine Verzerrung, sondern die Kernaussage.

### Klimaabhängigkeit

ΔT schwankt standortabhängig zwischen etwa 28 und 36 K (± 12 %). Die Klassenbreiten (15/15/20/30) sind deutlich größer als diese Streuung. **Die Schwellen bleiben trotzdem fix** — sonst wären zwei Objekte in verschiedenen Klimazonen nicht mehr vergleichbar. Der Auslegungsfall gehört in die Legendenzeile (Abschnitt 5).

---

## 3. Die Farbskala

**Entscheidung: 5 diskrete Stufen, sequenziell, monoton fallende Helligkeit, hell-kühl → dunkel-rot.**

| Klasse | Hex | RGB 0–1 (sRGB, für `UIColor(red:green:blue:alpha:)`) | L\* | Kontrast zum Hintergrund |
|---|---|---|---|---|
| 1 unauffällig | `#D2DBE1` | (0.824, 0.859, 0.882) | 86,9 | 1,19 |
| 2 leicht erhöht | `#E4BB4D` | (0.894, 0.733, 0.302) | 77,6 | 1,55 |
| 3 deutlich erhöht | `#C87F22` | (0.784, 0.498, 0.133) | 59,5 | 2,74 |
| 4 hoch | `#AE4A12` | (0.682, 0.290, 0.071) | 44,1 | 4,72 |
| 5 sehr hoch | `#86160F` | (0.525, 0.086, 0.059) | 28,6 | 8,37 |
| kein Verlust | `#A6ADB4` | (0.651, 0.678, 0.706) | 70,4 | 1,93 (bei 45 % Deckkraft) |

**Hintergrund der Szene** (`SCNView.backgroundColor`): `#EAEDF0` (0.918, 0.929, 0.941) im hellen, `#E1E5E8` (0.882, 0.898, 0.910) im dunklen Darstellungsmodus.

### Nachgerechnete Eigenschaften

**Helligkeit monoton fallend**, Abstände ΔL\* = 9,3 / 18,1 / 15,4 / 15,6 → die Reihenfolge überlebt Graustufen (S/W-Ausdruck des PDF-Berichts) und jede Form von Farbenblindheit inklusive Monochromasie.

**Deuteranopie-Simulation** (Viénot 1999): `#D8D8E1` · `#C8C84A` · `#999916` · `#737300` · `#4E4E00` — sauber nach Helligkeit geordnet, Nachbar-Abstand ΔE ≥ 16,9, Nicht-Nachbarn ΔE ≥ 32,9.
**Protanopie:** `#DADAE1` · `#C0C04E` · `#8A8A24` · `#5D5D15` · `#343411` — Nachbar-Abstand ΔE ≥ 20,6.

**Aufmerksamkeitshierarchie:** der Kontrast zum Hintergrund steigt monoton mit der Verlusthöhe (1,19 → 8,37). Klasse 1 verschwindet fast im Hintergrund („nichts zu sehen"), Klasse 5 ist das Dunkelste und Farbigste im Bild. Der Blick landet ohne Erklärung auf dem Problem.

**Semantik:** hell und kühl = gut, dunkel und rot = schlecht. Deckt sich mit der kulturellen Erwartung *und* mit der Wärmebild-Erwartung. Klasse 1 ist bewusst **fast unbunt** — sie liegt absichtlich neben der Farbrampe, weil sie „hier ist nichts" bedeutet und nicht „hier ist ein bisschen".

### Warum abgestuft und nicht kontinuierlich

1. **Es gibt keine Verläufe innerhalb einer Fläche.** Ein `SCNMaterial.diffuse` ist eine Farbe pro Bauteil — Kontinuität bringt geometrisch nichts.
2. **Beleuchtung fälscht Farbe.** Bei einer kontinuierlichen Helligkeitsrampe ist ein Schattierungsunterschied von 10 % nicht mehr von einem Datenunterschied zu trennen. Bei ΔL\* ≥ 9 zwischen den Stufen springt kein Bauteil durch Schattierung in eine falsche Klasse (siehe Abschnitt 4).
3. **Grobe Stufen sind bei einem Kurzverfahren die ehrlichere Darstellung.** Die U-Werte sind zum großen Teil aus Baujahrsklassen geschätzt. Ein weicher Verlauf würde eine Genauigkeit vortäuschen, die die Methode nicht hat. Die Klassenbreite *ist* die Unsicherheitsaussage.
4. **Fünf Stufen passen in eine Legende, die man in drei Sekunden liest.** Ein Farbbalken mit Zahlenachse wird vor dem Kunden nicht gelesen.

### Warum kein Regenbogen und kein Grün-Rot

- Regenbogen/Jet: nicht monoton in der Helligkeit → erfindet Grenzen, wo keine sind, und kippt in Graustufen komplett um.
- Grün-Rot-Ampel: fällt bei rund 8 % der Männer aus. Die Zielgruppe ist praktisch ausschließlich männlich — das ist hier kein Randfall, sondern jeder zwölfte Kunde.
- Viridis (blau→grün→gelb): perzeptuell einwandfrei, aber „Grün in der Mitte" liest sich als „in Ordnung", und das Ende in Gelb liest sich nicht als „schlimm".

---

## 4. Rendering-Regeln in SceneKit

Ohne diese vier Punkte lügt die schönste Skala.

### 4.1 Beleuchtung ausschalten

`SCNView.autoenablesDefaultLighting = false`, keine Lichtquellen in der Szene, für alle datentragenden Materialien `lightingModel = .constant`.

Begründung: bei Lambert-Beleuchtung hängt die wahrgenommene Farbe von der Wandnormalen ab. Zwei Wände derselben Klasse sähen unterschiedlich aus, zwei Wände verschiedener Klassen könnten gleich aussehen. **Damit würde die Kameraposition die Daten verändern.** Das ist im 3D-Raum das Äquivalent zur manipulierten Achse.

### 4.2 Räumlichkeit über einen festen, begrenzten Flächen-Tint

Statt Licht bekommt jede `SCNBox` feste Materialien je Seite (Reihenfolge `geometry.materials`: front, right, back, left, top, bottom):

| Fläche | Faktor (linear) | Kl. 1 | Kl. 2 | Kl. 3 | Kl. 4 | Kl. 5 |
|---|---|---|---|---|---|---|
| Vorne/Hinten | 100 % | `#D2DBE1` | `#E4BB4D` | `#C87F22` | `#AE4A12` | `#86160F` |
| Seiten | 92 % | `#CAD3D9` | `#DCB44A` | `#C17A20` | `#A84711` | `#81150E` |
| Oben/Unten | 85 % | `#C3CCD1` | `#D4AE47` | `#BA761F` | `#A24410` | `#7C140D` |

**Regel: die gesamte Schattierungsspanne darf ΔL\* = 6 nie überschreiten** — also weniger als eine halbe Klassenstufe. Gemessen liegt sie zwischen 2,4 und 5,4 L\*. Damit ist Formwahrnehmung möglich, ohne dass Schattierung je als Datenunterschied gelesen werden kann. Die Faktoren sind fest, für alle Bauteile identisch und kameraunabhängig.

### 4.3 Bauteile voneinander trennen

Wandboxen an beiden Enden um je 2 cm verkürzen. Der 4 cm breite helle Spalt an jeder Ecke trennt benachbarte Flächen auch dann, wenn sie in derselben Klasse liegen. Fenster/Türen behalten ihre größere Tiefe (0,12 gegen 0,08 der Wand) und stehen dadurch sichtbar vor der Wand — das löst gleichzeitig das Z-Fighting.

Keine Konturlinie: eine dunkle Kontur verschwindet auf Klasse 5 (Kontrast 1,39), eine helle auf Klasse 1. Der helle Spalt funktioniert bei allen fünf Klassen gleich gut.

### 4.4 Hintergrund folgt **nicht** dem Darstellungsmodus

Der Szenenhintergrund bleibt in beiden Modi ein helles Neutralgrau (`#EAEDF0` / `#E1E5E8`, ΔL\* = 3 — die Nachtabsenkung nimmt nur die Blendung, ohne die Umfeldwahrnehmung zu verschieben).

Begründung: bei einem theme-abhängigen Hintergrund kippt die Aufmerksamkeitshierarchie. Auf Schwarz wäre die helle Klasse 1 das Auffälligste im Bild — „alles in Ordnung" würde am lautesten schreien. Ein heller, neutraler Umfeldton ist außerdem die Bedingung, unter der Menschen Flächenfarben am zuverlässigsten beurteilen (geringste Simultankontrast-Verschiebung).

Ein hell begrenztes Viewport-Rechteck im dunklen Modus ist auf iOS etabliert (Grundrisse, Pläne, Dokumentenansichten) und wird nicht als Fehler gelesen. Die umgebende SwiftUI-Oberfläche — Legende, Balkenliste, Fußzeile — folgt normal dem Systemmodus.

**Die aktuelle Zeile `view.backgroundColor = UIColor.secondarySystemBackground` muss im Wärmemodus ersetzt werden.**

### 4.5 Bodenplatte

Die vorhandene beige Bodenplatte (`0.93/0.90/0.85`) muss im Wärmemodus weg — sie liegt farblich zwischen Klasse 1 und Klasse 2 und wäre die einzige Fläche im Bild, die eine Klasse vortäuscht, die sie nicht hat. Behandlung siehe Abschnitt 6.

---

## 5. Legende und Zahlen

### Aufbau von oben nach unten

```
┌─────────────────────────────────────────┐
│                                         │
│           3D-Ansicht (~50 % Höhe)       │
│                                         │
├─────────────────────────────────────────┤
│  [ Bauteile ]  [ Wärmebild ]            │  ← Segmented Picker, volle Breite
├─────────────────────────────────────────┤
│  wenig Verlust ▸               ▸ viel   │  ← Wortanker, nur an den Enden
│  ▓▓▓▓▓ ▓▓▓▓▓ ▓▓▓▓▓ ▓▓▓▓▓ ▓▓▓▓▓   ▒     │  ← 5 Segmente + abgesetzt: neutral
│      15    30    50    80  W/m²   innen │  ← Grenzwerte klein, sekundär
├─────────────────────────────────────────┤
│  Größte Verluste                        │
│  Fenster Süd    ███████████  810 W  24 %│  ← sortierte Balken, Nullpunkt links
│  Außenwand West ████████     580 W  17 %│
│  Dach           ██████       430 W  13 %│
├─────────────────────────────────────────┤
│  Lüftung 620 W (18 %) · Zuschlag 210 W  │
│  Überschlag DIN EN 12831 (vereinfacht)  │
│  – kein prüffähiger Nachweis            │
└─────────────────────────────────────────┘
```

### Regeln

- **Immer sichtbar**, nie hinter einem „?"-Knopf. Wer die Legende aufklappen muss, hat die drei Sekunden schon verloren.
- **Nur zwei Wörter** am Balken: „wenig Verlust" links, „viel Verlust" rechts. Fünf Textlabels wären fünf Leseakte — der Kunde liest die Reihenfolge, nicht die Werte.
- **Grenzzahlen 15/30/50/80** klein und in Sekundärfarbe unter die Segmentgrenzen. Kosten optisch fast nichts und geben dem Handwerker den Anker für die Fachdiskussion.
- **Neutral abgesetzt**, mit sichtbarem Abstand hinter dem Balken und eigener Beschriftung „innen". Es darf nicht so aussehen, als wäre „kein Verlust" die sechste, beste Stufe.
- **Auslegungsfall** in der Fußzeile: „bei −12 °C außen / 20 °C innen" mit den tatsächlichen Werten aus `HeatingClimate`.
- **Balkenliste**: maximal 3 Zeilen plus „übrige …". Balken beginnen bei null, Skala über alle Zeilen gleich, Reihenfolge absteigend. Hier — und nur hier — stehen absolute Watt.

### Antippen eines Bauteils

Popover, maximal vier Zeilen:

```
Außenwand Nord · 12,4 m²
38 W/m²  ·  470 W insgesamt
U ≈ 1,20 W/(m²K)   (geschätzt, Baujahr 1965)
```

Das „≈" markiert geschätzte U-Werte gegenüber eingegebenen. Zusätzlich in der Fußzeile: „9 von 12 U-Werten aus der Baujahrsklasse geschätzt".

> **Achtung, Konflikt mit dem bestehenden Code:** in `Room3DView.Coordinator.handleTap` schaltet ein Tipper heute `isExternal` um. **Im Wärmemodus darf Antippen nichts verändern** — sonst kippt der Handwerker vor dem Kunden versehentlich eine Wand nach innen und die gesamte Heizlast ändert sich stillschweigend mitten in der Präsentation. Der Umschalt-Tipper bleibt ausschließlich im Bauteil-Modus.

---

## 6. Sonderfälle

| Fall | Behandlung | Begründung |
|---|---|---|
| **Innenwände (0 W)** | Neutralgrau `#A6ADB4`, **45 % Deckkraft**, kein Flächen-Tint, `writesToDepthBuffer = false` | Nicht auf die Skala legen. Eine Innenwand ist nicht „gut gedämmt", sie ist **nicht Teil dieser Frage**. Als Klasse 1 dargestellt wäre sie ein Lob, das niemand verdient hat. Die Transparenz lässt zusätzlich in den Raum hineinsehen. |
| **ΔT ≤ 0** (adjacentTemp ≥ Innentemperatur) | wie Innenwand | Verlust ist rechnerisch 0. |
| **Boden** | Bodenplatte in ihrer Klassenfarbe einfärben, wenn `floorUValue != nil`; sonst Neutralgrau **und** Hinweis-Chip „Boden nicht angesetzt" | Der Boden hat Fläche in der Szene, also gehört er auf die Skala. |
| **Decke/Dach** | **keine Deckenplatte rendern** — sie würde den Raum von der Standardkamera aus verdecken. Stattdessen ein Chip neben der Legende: farbiges Quadrat + „Dach 64 W/m² · 3 520 W" bzw. „Dach nicht angesetzt" | Das Dach ist im Obergeschoss regelmäßig der größte Einzelposten. Es unsichtbar zu lassen wäre die gefährlichste Auslassung des ganzen Bildes. |
| **Alle Bauteile in derselben Klasse** | Bild bleibt einfarbig, **Skala wird nicht gedehnt.** Automatische Zeile: „Alle Bauteile liegen in einer Klasse — ein einzelner Tausch bringt hier wenig." | Genau der Fall, für den feste Schwellen existieren. Ein gleichmäßiges Bild ist eine echte Aussage, keine Fehlfunktion. |
| **Kleines Bauteil in Klasse 5** (z. B. 0,4 m² Kellerfenster) | Farbe **nicht** abschwächen | Die Klasse stimmt. Die Größenkorrektur leistet die Balkenliste: Farbe = Qualität, Balken = Geld. Der Handwerker sagt den Satz „klein, aber schlecht — lohnt sich nicht zuerst". |
| **Wände ohne `position`** (manuell/importiert) | tauchen in der 3D-Szene nicht auf → Fußzeile: „3 Bauteile ohne Grundriss-Lage, im Bild nicht dargestellt (zusammen 640 W)" | Ohne diesen Hinweis wirkt das Bild vollständig, obwohl Verlust fehlt. |
| **Verglaste Türen** | wie Fenster, dieselbe Skala | Es gibt genau eine Skala für alle Bauteile. |

---

## 7. Die zwei Zahlen, die über dem Bild stehen müssen

Über der 3D-Ansicht, nicht darunter:

```
Wohnzimmer · 55 m²          5 076 W          92 W/m² Grundfläche
```

Das ist die Informationshierarchie: **erst wie schlecht der Raum insgesamt ist, dann welches Bauteil schuld ist.**

Warum das nicht optional ist — das Feldbeispiel Kellerraum: 20 m², 2 043 W. Seine Wände liegen wegen ΔT ≈ 10 K überwiegend in Klasse 1 und 2, das 3D-Bild wirkt mild. Trotzdem sind das **102 W/m² Grundfläche** — ein miserabler Raum. Die Bauteilfarben können diese Aussage prinzipiell nicht treffen; sie beantworten eine andere Frage. Ohne die Kopfzeile führt das Bild in die Irre.

---

## 8. Ehrlichkeitsfallen

| # | Falle | Gegenmaßnahme |
|---|---|---|
| 1 | **Dach/Boden nicht angesetzt** (`ceilingUValue`/`floorUValue` = nil). Der größte Posten fehlt, das Bild sieht harmlos aus. | Chip „nicht angesetzt" ist **immer** sichtbar, auch wenn kein Wert da ist. Nie stillschweigend als 0 W darstellen. |
| 2 | **Lüftung hat keine Fläche** — 15–25 % der Heizlast sind im Bild unsichtbar. | Feste Fußzeile: „Lüftung 620 W (18 %) — nicht einfärbbar, weil sie kein Bauteil ist." |
| 3 | **Farbe wird als Geld gelesen.** Das rote Kellerfenster erscheint als Hauptproblem, kostet aber 60 W. | Balkenliste in Watt direkt daneben. Der Satz „Farbe = Qualität, Balken = Geld" gehört ins Handwerker-Onboarding. |
| 4 | **Relative Skala** würde in jedem Haus einen Schuldigen erfinden. | Verboten. Feste Schwellen, in einer Konstanten, nicht laufzeitabhängig. |
| 5 | **Erdreichwände sehen zu gut aus.** Per m² verlieren sie wegen ΔT ≈ 10 K wirklich weniger — die Wand ist trotzdem ungedämmt. | Legende sagt „Verlust je m²", nie „Dämmqualität". Das Popover zeigt zusätzlich den U-Wert. |
| 6 | **Geschätzte U-Werte wirken wie gemessene.** | „≈" im Popover bei Baujahrsschätzung, Zähler in der Fußzeile („9 von 12 geschätzt"). |
| 7 | **Vorher/Nachher-Vergleich mit verschobener Skala.** Sobald es eine Sanierungssimulation gibt, wäre eine nachgeführte Skala eine glatte Täuschung. | Beide Bilder zwingend gleiche Skala, gleiche Kamera, gleicher Zoom, nebeneinander. |
| 8 | **Kurzverfahren wirkt wie ein Nachweis** — ein farbiges 3D-Bild sieht sehr amtlich aus. | Der Hinweis steht in der Ansicht selbst, nicht nur im PDF: „Überschlag nach DIN EN 12831 (vereinfacht) — kein prüffähiger Nachweis." Dauerhaft, klein, aber nicht ausblendbar. |
| 9 | **Beleuchtung als Datenkanal.** | Abschnitt 4.1/4.2: `.constant`, Schattierungsbudget ΔL\* ≤ 6. |
| 10 | **Fehlende Bauteile ohne Grundriss-Lage.** | Fußzeilenhinweis mit Anzahl und Wattsumme. |

---

## 9. Verhältnis zum bestehenden Bauteil-Modus

**Entscheidung: keine gemeinsamen Farben — mit genau einer Ausnahme.**

Die beiden Modi kodieren grundverschiedene Datentypen: Bauteil-Modus = **nominal** (Kategorie ohne Rangfolge), Wärme-Modus = **ordinal** (Rangfolge). Dieselbe Farbe in beiden Rollen ist die klassische Verwechslungsquelle. Konkret kollidiert heute `UIColor.systemOrange` (Außenwand, `#FF9500`) mit Klasse 3/4 der Wärmeskala — und Außenwände sind in beiden Modi die häufigste Fläche im Bild. Wer eben gelernt hat „orange = Außenwand", liest im zweiten Modus „orange = mittelschlecht" falsch.

**Umgefärbt wird der Bauteil-Modus, nicht die Wärmeskala** — dessen Palette ist frei wählbar, die Wärmeskala ist durch Wahrnehmungsanforderungen festgelegt.

| Bauteil-Modus | heute | neu | Hex |
|---|---|---|---|
| Außenwand | `systemOrange` | warmes Graubeige | `#B5A99A` |
| innen | `systemGray3` | hellgrau | `#D5D8DC` |
| Erdreich/unbeheizt | `brown` | Braungrau | `#8A7B6B` |
| Fenster | `systemBlue` 70 % | blasses Blau | `#9DB9C9` |
| Tür | Braun | Graubraun | `#A08A76` |
| verglaste Tür | `systemTeal` 70 % | blasses Blaugrün | `#9BC0BC` |

Alle Werte liegen unter Chroma 25 — der Bauteil-Modus wird zur gedeckten „technischen Zeichnung", der Wärme-Modus ist der einzige farbige. Die beiden Bilder sind dadurch schon als Gesamteindruck nicht verwechselbar, unabhängig von einzelnen Farben. Die Zustandsunterscheidung außen/innen/Erdreich bleibt klar erkennbar, das reicht für den Umschalt-Tipper.

**Die Ausnahme:** das Neutralgrau `#A6ADB4` für „kein Verlust / Innenbauteil" darf in beiden Modi identisch sein — es bedeutet in beiden dasselbe („diese Fläche gehört nicht zur Frage"). Gleiche Bedeutung, gleiche Farbe ist richtig.

**Zusätzlich:**
- Umschalter als Segmented Picker direkt unter dem Viewport, beschriftet **„Bauteile" / „Wärmebild"**.
- Beim Wechsel eine Überblendung von 250 ms. Ein harter Schnitt wird als Neuladen wahrgenommen, eine Überblendung als *dasselbe Modell in anderer Darstellung* — genau die Aussage, die stimmt.
- Die Legende wechselt vollständig mit. Nie beide Legenden gleichzeitig.

---

## 10. Ausbaustufe: Sommer-Modus

Kühllast ist ein **Eintrag**, kein Verlust — anderes Vorzeichen, andere Physik, andere Jahreszeit. Beides in eine Skala zu legen wäre der 3D-Zwilling der Doppelachse.

Regeln, wenn er gebaut wird:
- Dritter, gleichrangiger Modus **„Sommer"** — nie eine Überlagerung.
- **Gleiche fünf Farben, gleiche Legendenform**, andere Einheit und andere Schwellen. Der Kunde lernt eine visuelle Sprache; die Bedeutung „mehr = ungünstiger" ist in beiden Modi identisch, die Modi schließen sich gegenseitig aus und sind beschriftet.
- Kodiert wird der Eintrag je m² Bauteilfläche: Fenster A·g·I·Verschattung geteilt durch A = **g · I · Verschattung** plus Transmission; opake Wände nur Transmission; Erdreichwände bleiben neutral (`CoolingLoadCalculator` setzt sie ohnehin nicht an).
- Innere Lasten (Personen, Geräte, Licht) und Lüftung haben keine Fläche → Fußzeilen-Zahlen, wie Φ_V im Winter.
- Eigene, an der Sommer-Einstrahlung kalibrierte Schwellen. **Nicht** die Winter-Schwellen wiederverwenden.

---

## 11. Umsetzungs-Checkliste

```
Berechnung
□ q = U · ΔT je Bauteil, ΔT = indoor − (adjacentTemp ?? outdoor)
□ Wärmebrückenzuschlag NICHT in q
□ Klassifizierung an festen Konstanten 15 / 30 / 50 / 80
□ Innenwände und ΔT ≤ 0 → Klasse "neutral", nicht Klasse 1

Rendering
□ autoenablesDefaultLighting = false, keine Lichtquellen
□ lightingModel = .constant auf allen datentragenden Materialien
□ 6 Materialien je SCNBox, Tint 100/92/85 %
□ Wandboxen an beiden Enden 2 cm gekürzt
□ backgroundColor fest #EAEDF0 / #E1E5E8 — NICHT secondarySystemBackground
□ beige Bodenplatte im Wärmemodus ersetzt
□ Innenwände 45 % Deckkraft, writesToDepthBuffer = false

Interaktion
□ Tipper im Wärmemodus = Popover, KEIN isExternal-Toggle
□ Umschalter beschriftet "Bauteile" / "Wärmebild", 250 ms Überblendung

Anzeige
□ Kopfzeile: Gesamtlast in W UND W/m² Grundfläche
□ Legende dauerhaft sichtbar, Wortanker + Grenzzahlen + abgesetztes Neutral
□ Balkenliste Top 3 in absoluten Watt, Nullpunkt links
□ Dach-Chip, auch bei "nicht angesetzt"
□ Fußzeile: Lüftung, Zuschlag, geschätzte U-Werte, fehlende Bauteile, Kurzverfahren-Hinweis

Abnahme
□ CVD-Simulator (Deuteranopie + Protanopie) über einen echten Screenshot
□ Screenshot in Graustufen — Reihenfolge der fünf Klassen noch erkennbar?
□ Testfall Top-Neubau: kein Rot im Bild
□ Testfall Feldbeispiel 55 m² / 5 076 W und Keller 20 m² / 2 043 W
□ Kamera einmal rundum drehen: verändert sich eine Bauteilfarbe? → Fehler
```
