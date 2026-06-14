const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const https = require('https');

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST || 'shk-db',
  user: process.env.DB_USER || 'shk',
  password: process.env.DB_PASS || 'shk2024sicher',
  database: process.env.DB_NAME || 'shkdb',
  port: process.env.DB_PORT || 5432,
});

app.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok' });
  } catch (e) {
    res.status(500).json({ status: 'error', message: e.message });
  }
});

// ── TODOS ──────────────────────────────────────────────────────────────────

app.get('/api/todos', async (req, res) => {
  try {
    const date = req.query.date || new Date().toISOString().split('T')[0];
    const result = await pool.query(
      'SELECT * FROM todos WHERE date = $1 ORDER BY done ASC, created_at ASC',
      [date]
    );
    res.json(result.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/todos', async (req, res) => {
  try {
    const { text, category = 'office', person = 'Tamer', priority = 'medium', date } = req.body;
    const d = date || new Date().toISOString().split('T')[0];
    const result = await pool.query(
      'INSERT INTO todos (text, category, person, priority, date) VALUES ($1, $2, $3, $4, $5) RETURNING *',
      [text, category, person, priority, d]
    );
    res.json(result.rows[0]);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.patch('/api/todos/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const fields = req.body;
    const keys = Object.keys(fields);
    const values = Object.values(fields);
    const setClause = keys.map((k, i) => `"${k}" = $${i + 1}`).join(', ');
    const result = await pool.query(
      `UPDATE todos SET ${setClause} WHERE id = $${keys.length + 1} RETURNING *`,
      [...values, id]
    );
    res.json(result.rows[0]);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.delete('/api/todos/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM todos WHERE id = $1', [req.params.id]);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── TIMEBLOCKS ──────────────────────────────────────────────────────────────

app.get('/api/timeblocks', async (req, res) => {
  try {
    const date = req.query.date || new Date().toISOString().split('T')[0];
    const result = await pool.query(
      'SELECT * FROM timeblocks WHERE date = $1 ORDER BY hour ASC, created_at ASC',
      [date]
    );
    res.json(result.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/timeblocks', async (req, res) => {
  try {
    const { title, hour, duration = 1, category = 'office', person = 'Tamer', date } = req.body;
    const d = date || new Date().toISOString().split('T')[0];
    const result = await pool.query(
      'INSERT INTO timeblocks (title, hour, duration, category, person, date) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *',
      [title, hour, duration, category, person, d]
    );
    res.json(result.rows[0]);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.patch('/api/timeblocks/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const fields = req.body;
    const keys = Object.keys(fields);
    const values = Object.values(fields);
    const setClause = keys.map((k, i) => `"${k}" = $${i + 1}`).join(', ');
    const result = await pool.query(
      `UPDATE timeblocks SET ${setClause} WHERE id = $${keys.length + 1} RETURNING *`,
      [...values, id]
    );
    res.json(result.rows[0]);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.delete('/api/timeblocks/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM timeblocks WHERE id = $1', [req.params.id]);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── TERMINE (aus bestehender SHK-Datenbank) ────────────────────────────────

// ── iCloud CalDAV (direkt aus der gemeinsamen kalender_einstellungen) ──────

function caldavRequest(url, method, auth, body, extraHeaders = {}) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const headers = {
      'Content-Type': 'application/xml; charset=utf-8',
      'Authorization': auth,
      ...extraHeaders,
    };
    if (body) headers['Content-Length'] = Buffer.byteLength(body);
    const r = https.request(
      { hostname: parsed.hostname, path: parsed.pathname + parsed.search, method, headers },
      (resp) => {
        let data = '';
        resp.on('data', (c) => (data += c));
        resp.on('end', () => resolve({ status: resp.statusCode, body: data }));
      }
    );
    r.on('error', reject);
    if (body) r.write(body);
    r.end();
  });
}

function parseIcalDt(dt) {
  dt = (dt || '').trim().replace(/Z$/, '');
  if (dt.length === 8) return { date: `${dt.slice(0, 4)}-${dt.slice(4, 6)}-${dt.slice(6, 8)}`, time: null };
  return {
    date: `${dt.slice(0, 4)}-${dt.slice(4, 6)}-${dt.slice(6, 8)}`,
    time: `${dt.slice(9, 11)}:${dt.slice(11, 13)}`,
  };
}

// Lädt die aktiven iCloud-Zugangsdaten (apple_id, app_passwort, kalender_url, auth)
async function getKalenderCred() {
  const cred = await pool.query(
    "SELECT apple_id, app_passwort, kalender_url FROM kalender_einstellungen WHERE aktiv = true ORDER BY id LIMIT 1"
  );
  if (!cred.rows.length || !cred.rows[0].kalender_url) return null;
  const { apple_id, app_passwort, kalender_url } = cred.rows[0];
  const auth = 'Basic ' + Buffer.from(`${apple_id}:${app_passwort}`).toString('base64');
  return { apple_id, app_passwort, kalender_url, auth };
}

// Holt Termine direkt aus iCloud für den Zeitraum [von, bis] (Datum-Strings)
async function fetchIcloudEvents(von, bis) {
  const cred = await getKalenderCred();
  if (!cred) return [];
  const { kalender_url, auth } = cred;
  const vonDt = (von || '').replace(/-/g, '') + 'T000000Z';
  const bisDt = (bis || '').replace(/-/g, '') + 'T235959Z';
  const body = `<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:D="DAV:">
  <D:prop><D:getetag/><C:calendar-data/></D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VEVENT">
        <C:time-range start="${vonDt}" end="${bisDt}"/>
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>`;
  const result = await caldavRequest(kalender_url, 'REPORT', auth, body, { Depth: '1' });
  if (result.status !== 207) return [];
  const events = [];
  let cdataBlocks = result.body.match(/<!\[CDATA\[([\s\S]*?)\]\]>/g) || [];
  if (!cdataBlocks.length) {
    const raw = result.body.match(/BEGIN:VCALENDAR[\s\S]*?END:VCALENDAR/g) || [];
    cdataBlocks = raw.map((r) => `<![CDATA[${r}]]>`);
  }
  for (const block of cdataBlocks) {
    const ical = block.replace(/^<!\[CDATA\[/, '').replace(/\]\]>$/, '');
    const lines = ical.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const get = (key) => {
      const m = lines.match(new RegExp(key + ':([^\\n]+)'));
      return m ? m[1].trim() : null;
    };
    const uid = get('UID');
    const summary = get('SUMMARY') || 'Termin';
    const dtStart = lines.match(/DTSTART[^:\n]*:([^\n]+)/)?.[1]?.trim();
    const dtEnd = lines.match(/DTEND[^:\n]*:([^\n]+)/)?.[1]?.trim();
    const desc = get('DESCRIPTION') || '';
    if (!uid || !dtStart) continue;
    const start = parseIcalDt(dtStart);
    const end = dtEnd ? parseIcalDt(dtEnd) : start;
    events.push({
      id: `ic_${uid}`,
      icloud_uid: uid,
      titel: summary,
      typ: 'termin',
      datum: start.date,
      zeit_von: start.time,
      zeit_bis: end.time,
      techniker: null,
      notizen: desc,
      kunde_name: null,
      quelle: 'icloud',
    });
  }
  return events;
}

async function localTermine(date) {
  const result = await pool.query(
    `SELECT t.id, t.titel, t.typ, t.datum, t.zeit_von, t.zeit_bis,
            t.techniker, t.notizen,
            COALESCE(NULLIF(k.firma, ''), k.nachname) AS kunde_name
     FROM termine t
     LEFT JOIN kunden k ON t.kunden_id = k.id
     WHERE t.datum::date = $1::date
     ORDER BY t.zeit_von NULLS LAST`,
    [date]
  );
  return result.rows.map((r) => ({ ...r, quelle: 'lokal' }));
}

app.get('/api/termine', async (req, res) => {
  const date = req.query.date || new Date().toISOString().split('T')[0];
  let events = [];
  let icloudOk = false;
  try {
    events = await fetchIcloudEvents(date, date);
    icloudOk = true;
  } catch (e) {
    console.error('iCloud-Fehler:', e.message);
  }
  // Lokale (im Planer angelegte) Termine ergänzen
  let local = [];
  try {
    local = await localTermine(date);
  } catch (e) {
    console.error('Lokale Termine Fehler:', e.message);
  }
  // Wenn iCloud komplett fehlschlug und keine lokalen Daten: Fehler melden
  if (!icloudOk && local.length === 0) {
    return res.status(502).json({ error: 'iCloud nicht erreichbar und keine lokalen Termine' });
  }
  const all = [...events, ...local].sort((a, b) =>
    (a.zeit_von || '99:99').localeCompare(b.zeit_von || '99:99')
  );
  res.json(all);
});

// ── iCloud schreiben: anlegen / ändern / löschen ──────────────────────────

function icalEscape(s) {
  return String(s || '')
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r?\n/g, '\\n');
}

// Baut DTSTART/DTEND-Wert: "YYYYMMDDTHHMMSS" (lokale Zeit) oder "YYYYMMDD" (ganztägig)
function toIcalDt(datum, zeit) {
  const d = (datum || '').replace(/-/g, '');
  if (!zeit) return { value: d, allday: true };
  const t = zeit.replace(/:/g, '').padEnd(6, '0').slice(0, 6);
  return { value: `${d}T${t}`, allday: false };
}

function buildIcs({ uid, titel, datum, zeit_von, zeit_bis, notizen }) {
  const now = new Date().toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z';
  const start = toIcalDt(datum, zeit_von);
  let endVal;
  if (start.allday) {
    endVal = start.value;
  } else if (zeit_bis) {
    endVal = toIcalDt(datum, zeit_bis).value;
  } else {
    const [h, m] = zeit_von.split(':').map(Number);
    const eh = String((h + 1) % 24).padStart(2, '0');
    endVal = `${datum.replace(/-/g, '')}T${eh}${String(m).padStart(2, '0')}00`;
  }
  const dtLines = start.allday
    ? `DTSTART;VALUE=DATE:${start.value}\r\nDTEND;VALUE=DATE:${endVal}`
    : `DTSTART:${start.value}\r\nDTEND:${endVal}`;
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//SHK Planer//DE',
    'CALSCALE:GREGORIAN',
    'BEGIN:VEVENT',
    `UID:${uid}`,
    `DTSTAMP:${now}`,
    dtLines,
    `SUMMARY:${icalEscape(titel)}`,
    `DESCRIPTION:${icalEscape(notizen)}`,
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');
}

function eventUrl(kalender_url, uid) {
  return kalender_url.replace(/\/$/, '') + '/' + uid + '.ics';
}

async function putTermin(uid, data) {
  const cred = await getKalenderCred();
  if (!cred) throw new Error('Keine iCloud-Zugangsdaten');
  const ics = buildIcs({ uid, ...data });
  const r = await caldavRequest(eventUrl(cred.kalender_url, uid), 'PUT', cred.auth, ics, {
    'Content-Type': 'text/calendar; charset=utf-8',
  });
  if (r.status < 200 || r.status >= 300) {
    throw new Error(`iCloud PUT fehlgeschlagen (Status ${r.status})`);
  }
  return {
    id: `ic_${uid}`,
    icloud_uid: uid,
    titel: data.titel,
    typ: 'termin',
    datum: data.datum,
    zeit_von: data.zeit_von || null,
    zeit_bis: data.zeit_bis || null,
    notizen: data.notizen || '',
    techniker: null,
    kunde_name: null,
    quelle: 'icloud',
  };
}

// Neuen Termin in iCloud anlegen
app.post('/api/termine', async (req, res) => {
  try {
    const { titel, datum, zeit_von, zeit_bis, notizen } = req.body;
    if (!titel || !datum) return res.status(400).json({ error: 'titel und datum erforderlich' });
    const uid = `shkplaner-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const event = await putTermin(uid, { titel, datum, zeit_von, zeit_bis, notizen });
    res.json(event);
  } catch (e) {
    res.status(502).json({ error: e.message });
  }
});

// Bestehenden iCloud-Termin ändern (überschreibt per UID)
app.put('/api/termine/:uid', async (req, res) => {
  try {
    const uid = decodeURIComponent(req.params.uid).replace(/^ic_/, '');
    const { titel, datum, zeit_von, zeit_bis, notizen } = req.body;
    if (!titel || !datum) return res.status(400).json({ error: 'titel und datum erforderlich' });
    const event = await putTermin(uid, { titel, datum, zeit_von, zeit_bis, notizen });
    res.json(event);
  } catch (e) {
    res.status(502).json({ error: e.message });
  }
});

// iCloud-Termin löschen
app.delete('/api/termine/:uid', async (req, res) => {
  try {
    const uid = decodeURIComponent(req.params.uid).replace(/^ic_/, '');
    const cred = await getKalenderCred();
    if (!cred) return res.status(502).json({ error: 'Keine iCloud-Zugangsdaten' });
    const r = await caldavRequest(eventUrl(cred.kalender_url, uid), 'DELETE', cred.auth, null);
    if ((r.status >= 200 && r.status < 300) || r.status === 404) return res.json({ ok: true });
    res.status(502).json({ error: `iCloud DELETE fehlgeschlagen (Status ${r.status})` });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => console.log(`SHK Planer API running on port ${PORT}`));

