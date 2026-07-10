const HLB_DATA = {
  cities: [
    { name: 'Aachen', temp: -10 },
    { name: 'Augsburg', temp: -16 },
    { name: 'Berlin', temp: -14 },
    { name: 'Bielefeld', temp: -12 },
    { name: 'Bochum', temp: -12 },
    { name: 'Bonn', temp: -10 },
    { name: 'Bremen', temp: -12 },
    { name: 'Braunschweig', temp: -14 },
    { name: 'Chemnitz', temp: -16 },
    { name: 'Dortmund', temp: -12 },
    { name: 'Dresden', temp: -16 },
    { name: 'Düsseldorf', temp: -10 },
    { name: 'Erfurt', temp: -16 },
    { name: 'Essen', temp: -10 },
    { name: 'Frankfurt am Main', temp: -12 },
    { name: 'Freiburg im Breisgau', temp: -12 },
    { name: 'Göttingen', temp: -14 },
    { name: 'Halle (Saale)', temp: -14 },
    { name: 'Hamburg', temp: -12 },
    { name: 'Hannover', temp: -14 },
    { name: 'Heidelberg', temp: -12 },
    { name: 'Karlsruhe', temp: -12 },
    { name: 'Kassel', temp: -14 },
    { name: 'Kiel', temp: -12 },
    { name: 'Köln', temp: -10 },
    { name: 'Leipzig', temp: -14 },
    { name: 'Magdeburg', temp: -16 },
    { name: 'Mainz', temp: -12 },
    { name: 'Mannheim', temp: -12 },
    { name: 'München', temp: -16 },
    { name: 'Münster', temp: -12 },
    { name: 'Nürnberg', temp: -16 },
    { name: 'Oldenburg', temp: -12 },
    { name: 'Osnabrück', temp: -12 },
    { name: 'Potsdam', temp: -14 },
    { name: 'Regensburg', temp: -16 },
    { name: 'Rostock', temp: -14 },
    { name: 'Saarbrücken', temp: -12 },
    { name: 'Stuttgart', temp: -14 },
    { name: 'Ulm', temp: -16 },
    { name: 'Wiesbaden', temp: -12 },
    { name: 'Würzburg', temp: -14 },
  ],

  uValuePresets: {
    wall: [
      { label: 'Neubau KfW 40/55 (≥20 cm WDV)', value: 0.15 },
      { label: 'Neubau GEG / EnEV (14 cm WDV)', value: 0.24 },
      { label: 'Saniert (8 cm WDV)', value: 0.40 },
      { label: 'Saniert (4 cm WDV)', value: 0.65 },
      { label: 'Altbau 1995–2009', value: 0.80 },
      { label: 'Altbau 1980–1995', value: 1.20 },
      { label: 'Altbau 1960–1980', value: 1.60 },
      { label: 'Altbau vor 1960 (massiv)', value: 2.10 },
    ],
    window: [
      { label: 'Dreifachverglasung (modern, ab 2010)', value: 0.70 },
      { label: 'Zweifachverg. Wärmeschutz (ab 1995)', value: 1.10 },
      { label: 'Zweifachverg. Standard (1985–1995)', value: 1.80 },
      { label: 'Zweifachverg. alt (vor 1985)', value: 2.80 },
      { label: 'Einfachverglasung (vor 1975)', value: 5.00 },
    ],
    door: [
      { label: 'Modern gedämmt (ab 2010)', value: 0.90 },
      { label: 'Standard (1990–2010)', value: 1.80 },
      { label: 'Alt, wenig gedämmt', value: 3.00 },
      { label: 'Alt, ungedämmt (Holz massiv)', value: 4.00 },
    ],
    roof: [
      { label: 'Neubau KfW 40/55 (≥30 cm)', value: 0.12 },
      { label: 'Neubau GEG (20 cm)', value: 0.20 },
      { label: 'Saniert (14 cm)', value: 0.30 },
      { label: 'Saniert (10 cm)', value: 0.45 },
      { label: 'Altbau, leicht gedämmt', value: 0.60 },
      { label: 'Altbau, kaum gedämmt', value: 1.20 },
      { label: 'Altbau, ungedämmt', value: 2.00 },
    ],
    floor: [
      { label: 'Neubau GEG (≥12 cm)', value: 0.20 },
      { label: 'Gedämmt saniert (8 cm)', value: 0.35 },
      { label: 'Altbau, gedämmt', value: 0.60 },
      { label: 'Altbau, kaum gedämmt (Keller)', value: 1.00 },
    ],
    internal: [
      { label: 'Leichtbauwand / Gipskarton', value: 2.00 },
      { label: 'Innenwand Mauerwerk', value: 1.50 },
      { label: 'Holzbalkendecke', value: 1.00 },
      { label: 'Stahlbetondecke', value: 2.00 },
    ],
  },

  // Canonical U-value defaults by construction year [W/(m²K)].
  // Single source of truth — used by scan suggestions, building templates
  // and the component dialog. DIN 4108 / Baualtersklassen reference values.
  uDefaultsByYear(year) {
    const y = parseInt(year) || 1975;
    if (y <= 1968) return { wall: 1.75, window: 2.80, roof: 2.00, floor: 1.20, door: 3.50 };
    if (y <= 1978) return { wall: 1.40, window: 2.80, roof: 1.50, floor: 1.00, door: 3.00 };
    if (y <= 1984) return { wall: 0.90, window: 2.50, roof: 0.80, floor: 0.80, door: 2.50 };
    if (y <= 1995) return { wall: 0.60, window: 1.80, roof: 0.50, floor: 0.60, door: 1.80 };
    if (y <= 2002) return { wall: 0.45, window: 1.40, roof: 0.35, floor: 0.50, door: 1.60 };
    if (y <= 2015) return { wall: 0.28, window: 1.10, roof: 0.20, floor: 0.35, door: 1.20 };
    return { wall: 0.20, window: 0.90, roof: 0.15, floor: 0.25, door: 0.90 };
  },

  // ── Gebäude-Vorlagen ─────────────────────────────────────
  // Typical German room programs. Per room:
  //   type/area/height  → room data (temp & airChange come from roomTypes)
  //   ext               → number of exterior wall sides (corner room = 2)
  //   winShare          → window area as fraction of floor area
  //   roof              → ceiling to unheated attic / roof above
  //   floor             → floor to unheated cellar (adjacentTemp 10°C)
  // Wall length is approximated from the floor area (square room assumption).
  buildingTemplates: [
    {
      id: 'efh_klein', icon: '🏠', label: 'EFH klein', sub: '~100 m² · 2 Etagen',
      height: 2.50,
      rooms: [
        { name: 'Wohnzimmer EG',   type: 'living',  area: 28, ext: 2, winShare: 0.20, floor: true },
        { name: 'Küche EG',        type: 'kitchen', area: 12, ext: 1, winShare: 0.12, floor: true },
        { name: 'Flur EG',         type: 'hallway', area: 8,  ext: 1, winShare: 0.04, floor: true },
        { name: 'WC EG',           type: 'toilet',  area: 3,  ext: 1, winShare: 0.06, floor: true },
        { name: 'Schlafzimmer OG', type: 'bedroom', area: 16, ext: 2, winShare: 0.12, roof: true },
        { name: 'Kinderzimmer OG', type: 'kids',    area: 14, ext: 2, winShare: 0.12, roof: true },
        { name: 'Bad OG',          type: 'bath',    area: 8,  ext: 1, winShare: 0.08, roof: true },
        { name: 'Flur OG',         type: 'hallway', area: 6,  ext: 0, winShare: 0,    roof: true },
      ],
    },
    {
      id: 'efh_gross', icon: '🏡', label: 'EFH groß', sub: '~150 m² · 2 Etagen',
      height: 2.60,
      rooms: [
        { name: 'Wohnzimmer EG',    type: 'living',  area: 35, ext: 2, winShare: 0.22, floor: true },
        { name: 'Esszimmer EG',     type: 'dining',  area: 14, ext: 1, winShare: 0.15, floor: true },
        { name: 'Küche EG',         type: 'kitchen', area: 14, ext: 1, winShare: 0.12, floor: true },
        { name: 'Flur EG',          type: 'hallway', area: 10, ext: 1, winShare: 0.04, floor: true },
        { name: 'WC EG',            type: 'toilet',  area: 4,  ext: 1, winShare: 0.06, floor: true },
        { name: 'HWR EG',           type: 'utility', area: 8,  ext: 1, winShare: 0.05, floor: true },
        { name: 'Schlafzimmer OG',  type: 'bedroom', area: 18, ext: 2, winShare: 0.12, roof: true },
        { name: 'Kinderzimmer 1 OG',type: 'kids',    area: 14, ext: 2, winShare: 0.12, roof: true },
        { name: 'Kinderzimmer 2 OG',type: 'kids',    area: 14, ext: 1, winShare: 0.12, roof: true },
        { name: 'Bad OG',           type: 'bath',    area: 10, ext: 1, winShare: 0.08, roof: true },
        { name: 'Flur OG',          type: 'hallway', area: 8,  ext: 0, winShare: 0,    roof: true },
      ],
    },
    {
      id: 'dhh', icon: '🏘️', label: 'Doppelhaushälfte', sub: '~120 m² · 2 Etagen',
      height: 2.50,
      rooms: [
        { name: 'Wohnzimmer EG',   type: 'living',  area: 30, ext: 2, winShare: 0.20, floor: true },
        { name: 'Küche EG',        type: 'kitchen', area: 12, ext: 1, winShare: 0.12, floor: true },
        { name: 'Flur EG',         type: 'hallway', area: 8,  ext: 1, winShare: 0.04, floor: true },
        { name: 'WC EG',           type: 'toilet',  area: 3,  ext: 1, winShare: 0.06, floor: true },
        { name: 'Schlafzimmer OG', type: 'bedroom', area: 16, ext: 2, winShare: 0.12, roof: true },
        { name: 'Kinderzimmer 1 OG', type: 'kids',  area: 14, ext: 1, winShare: 0.12, roof: true },
        { name: 'Kinderzimmer 2 OG', type: 'kids',  area: 12, ext: 1, winShare: 0.12, roof: true },
        { name: 'Bad OG',          type: 'bath',    area: 8,  ext: 1, winShare: 0.08, roof: true },
      ],
    },
    {
      id: 'bungalow', icon: '🛖', label: 'Bungalow', sub: '~110 m² · 1 Etage',
      height: 2.50,
      rooms: [
        { name: 'Wohnzimmer',  type: 'living',  area: 35, ext: 2, winShare: 0.22, roof: true, floor: true },
        { name: 'Küche',       type: 'kitchen', area: 14, ext: 1, winShare: 0.12, roof: true, floor: true },
        { name: 'Schlafzimmer',type: 'bedroom', area: 16, ext: 2, winShare: 0.12, roof: true, floor: true },
        { name: 'Kinderzimmer',type: 'kids',    area: 14, ext: 2, winShare: 0.12, roof: true, floor: true },
        { name: 'Bad',         type: 'bath',    area: 10, ext: 1, winShare: 0.08, roof: true, floor: true },
        { name: 'Flur',        type: 'hallway', area: 12, ext: 0, winShare: 0,    roof: true, floor: true },
        { name: 'WC',          type: 'toilet',  area: 3,  ext: 1, winShare: 0.06, roof: true, floor: true },
      ],
    },
    {
      id: 'wohnung', icon: '🏢', label: 'Etagenwohnung', sub: '~80 m² · beheizte Nachbarn',
      height: 2.50,
      rooms: [
        { name: 'Wohnzimmer',  type: 'living',  area: 26, ext: 2, winShare: 0.20 },
        { name: 'Schlafzimmer',type: 'bedroom', area: 15, ext: 1, winShare: 0.12 },
        { name: 'Kinderzimmer',type: 'kids',    area: 12, ext: 1, winShare: 0.12 },
        { name: 'Küche',       type: 'kitchen', area: 10, ext: 1, winShare: 0.12 },
        { name: 'Bad',         type: 'bath',    area: 7,  ext: 0, winShare: 0 },
        { name: 'Flur',        type: 'hallway', area: 8,  ext: 0, winShare: 0 },
      ],
    },
  ],

  componentLabels: {
    wall: 'Außenwand',
    window: 'Fenster',
    door: 'Außentür',
    roof: 'Dach / Decke',
    floor: 'Fußboden',
    internal: 'Innenbauteil',
  },

  roomTypes: {
    living:   { label: 'Wohnzimmer',      temp: 20, airChange: 0.5 },
    dining:   { label: 'Esszimmer',       temp: 20, airChange: 0.5 },
    bedroom:  { label: 'Schlafzimmer',    temp: 18, airChange: 0.5 },
    kids:     { label: 'Kinderzimmer',    temp: 20, airChange: 0.5 },
    bath:     { label: 'Badezimmer',      temp: 24, airChange: 0.8 },
    kitchen:  { label: 'Küche',           temp: 20, airChange: 0.7 },
    office:   { label: 'Arbeitszimmer',   temp: 20, airChange: 0.5 },
    hallway:  { label: 'Flur / Diele',    temp: 15, airChange: 0.5 },
    toilet:   { label: 'WC / Gäste-WC',  temp: 22, airChange: 0.7 },
    cellar:   { label: 'Keller (beheizt)',temp: 15, airChange: 0.3 },
    utility:  { label: 'Hauswirtschaft',  temp: 15, airChange: 0.5 },
    other:    { label: 'Sonstiger Raum',  temp: 20, airChange: 0.5 },
  },

  buildingTypes: {
    residential: 'Wohngebäude',
    commercial:  'Gewerbe',
    office:      'Büro',
    industrial:  'Industrie / Lager',
  },
};
