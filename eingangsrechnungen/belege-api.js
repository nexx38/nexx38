/**
 * Eingangsrechnungen / Belege – Express-Router
 *
 * Einbinden in server.js (2 Zeilen):
 *   const belegeRoutes = require('./belege-api');
 *   app.use('/api', belegeRoutes(pool));
 *
 * Umgebungsvariable auf dem Server setzen:
 *   ANTHROPIC_API_KEY=sk-ant-...
 *   (in docker run: -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY")
 *
 * Datenbank-Tabelle beim ersten Start anlegen:
 *   docker exec -i shk-db psql -U shk -d shkdb < /root/shk-app/belege-db.sql
 */

const express = require('express');
const https   = require('https');

const KAT_ENUM = [
  'material','fahrzeuge','personal','werkzeug',
  'buero','software','versicherung','steuerberater',
  'marketing','sonstiges'
];

module.exports = function belegeRoutes(pool) {
  const router = express.Router();

  /* ── GET /api/belege?year=2025&period=Q1 ──────────────────────────────── */
  router.get('/belege', async (req, res) => {
    try {
      const { year, period } = req.query;
      // period = Q1 | Q2 | Q3 | Q4 | JAHR
      let query = 'SELECT id, datum, beschreibung, betrag, mwst, kategorie, foto_base64, created_at FROM belege';
      const params = [];

      if (year && period) {
        const QUARTER_MONTHS = { Q1:[1,2,3], Q2:[4,5,6], Q3:[7,8,9], Q4:[10,11,12] };
        if (period === 'JAHR') {
          query += ' WHERE EXTRACT(YEAR FROM datum) = $1';
          params.push(parseInt(year));
        } else if (QUARTER_MONTHS[period]) {
          const [m1, m2, m3] = QUARTER_MONTHS[period];
          query += ' WHERE EXTRACT(YEAR FROM datum) = $1 AND EXTRACT(MONTH FROM datum) IN ($2,$3,$4)';
          params.push(parseInt(year), m1, m2, m3);
        }
      }

      query += ' ORDER BY datum DESC, created_at DESC';
      const result = await pool.query(query, params);
      res.json(result.rows);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  /* ── POST /api/belege ──────────────────────────────────────────────────── */
  router.post('/belege', async (req, res) => {
    try {
      const { datum, beschreibung, betrag, mwst = 19, kategorie = 'sonstiges', foto_base64 = null } = req.body;
      if (!datum || !beschreibung || betrag == null) {
        return res.status(400).json({ error: 'datum, beschreibung und betrag sind Pflichtfelder' });
      }
      const kat = KAT_ENUM.includes(kategorie) ? kategorie : 'sonstiges';
      const result = await pool.query(
        `INSERT INTO belege (datum, beschreibung, betrag, mwst, kategorie, foto_base64)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
        [datum, beschreibung.trim(), parseFloat(betrag), parseInt(mwst), kat, foto_base64]
      );
      res.status(201).json(result.rows[0]);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  /* ── PATCH /api/belege/:id ─────────────────────────────────────────────── */
  router.patch('/belege/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const allowed = ['datum','beschreibung','betrag','mwst','kategorie','foto_base64'];
      const fields  = Object.fromEntries(Object.entries(req.body).filter(([k]) => allowed.includes(k)));
      if (Object.keys(fields).length === 0) return res.status(400).json({ error: 'Keine Felder angegeben' });
      const keys   = Object.keys(fields);
      const values = Object.values(fields);
      const set    = keys.map((k, i) => `"${k}" = $${i + 1}`).join(', ');
      const result = await pool.query(
        `UPDATE belege SET ${set} WHERE id = $${keys.length + 1} RETURNING *`,
        [...values, id]
      );
      if (result.rowCount === 0) return res.status(404).json({ error: 'Beleg nicht gefunden' });
      res.json(result.rows[0]);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  /* ── DELETE /api/belege/:id ────────────────────────────────────────────── */
  router.delete('/belege/:id', async (req, res) => {
    try {
      const result = await pool.query('DELETE FROM belege WHERE id = $1', [req.params.id]);
      if (result.rowCount === 0) return res.status(404).json({ error: 'Beleg nicht gefunden' });
      res.json({ success: true });
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  /* ── POST /api/belege/ocr ──────────────────────────────────────────────── */
  // Empfängt: { mediaType: 'image/jpeg', data: '<base64 ohne data:-Prefix>' }
  // Gibt zurück: { datum, beschreibung, betrag, mwst, kategorie }
  router.post('/belege/ocr', async (req, res) => {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) return res.status(503).json({ error: 'ANTHROPIC_API_KEY nicht konfiguriert' });

    const { mediaType, data } = req.body;
    if (!data || !mediaType) return res.status(400).json({ error: 'mediaType und data fehlen' });

    const payload = JSON.stringify({
      model: 'claude-opus-4-8',
      max_tokens: 1024,
      messages: [{
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: mediaType, data } },
          { type: 'text', text:
            'Dies ist eine deutsche Quittung oder Rechnung (Eingangsbeleg eines Handwerksbetriebs). ' +
            'Extrahiere: Belegdatum, Händler/Lieferant als kurze Beschreibung, Bruttobetrag (Gesamtsumme inkl. MwSt) in Euro, ' +
            'den MwSt-Satz (19, 7 oder 0) und die passende Ausgaben-Kategorie. ' +
            'Mögliche Kategorien: material, fahrzeuge (Benzin/Diesel/Leasing/KFZ), personal, werkzeug, buero, software, ' +
            'versicherung, steuerberater, marketing, sonstiges. Bei Tankstellen → fahrzeuge.'
          }
        ]
      }],
      output_config: {
        format: {
          type: 'json_schema',
          schema: {
            type: 'object',
            properties: {
              datum:        { type: 'string', format: 'date', description: 'Belegdatum als YYYY-MM-DD' },
              beschreibung: { type: 'string', description: 'Händler / Lieferant, kurz' },
              betrag:       { type: 'number', description: 'Bruttobetrag gesamt in Euro' },
              mwst:         { type: 'integer', enum: [19, 7, 0] },
              kategorie:    { type: 'string', enum: KAT_ENUM }
            },
            required: ['datum','beschreibung','betrag','mwst','kategorie'],
            additionalProperties: false
          }
        }
      }
    });

    const options = {
      hostname: 'api.anthropic.com',
      path: '/v1/messages',
      method: 'POST',
      headers: {
        'x-api-key':           apiKey,
        'anthropic-version':   '2023-06-01',
        'content-type':        'application/json',
        'content-length':      Buffer.byteLength(payload)
      }
    };

    const apiReq = https.request(options, apiRes => {
      let body = '';
      apiRes.on('data', chunk => { body += chunk; });
      apiRes.on('end', () => {
        try {
          const result = JSON.parse(body);
          if (apiRes.statusCode !== 200) {
            return res.status(502).json({ error: result.error?.message || `Anthropic Fehler ${apiRes.statusCode}` });
          }
          if (result.stop_reason === 'refusal') {
            return res.status(422).json({ error: 'Beleg konnte nicht ausgelesen werden' });
          }
          const textBlock = (result.content || []).find(b => b.type === 'text');
          const parsed    = JSON.parse(textBlock.text);
          res.json(parsed);
        } catch (e) {
          res.status(500).json({ error: 'Antwort konnte nicht verarbeitet werden: ' + e.message });
        }
      });
    });

    apiReq.on('error', e => res.status(502).json({ error: 'Anthropic nicht erreichbar: ' + e.message }));
    apiReq.write(payload);
    apiReq.end();
  });

  return router;
};
