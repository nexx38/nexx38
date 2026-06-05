const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST || 'shk-db',
  user: process.env.DB_USER || 'shkuser',
  password: process.env.DB_PASS || 'shkpass',
  database: process.env.DB_NAME || 'shkdb',
  port: 5432,
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

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => console.log(`SHK Planer API running on port ${PORT}`));
