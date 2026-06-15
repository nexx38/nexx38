-- Eingangsrechnungen / Belege – Datenbank-Schema
-- Ausführen: docker exec -i shk-db psql -U shk -d shkdb < belege-db.sql

CREATE TABLE IF NOT EXISTS belege (
  id           SERIAL PRIMARY KEY,
  datum        DATE           NOT NULL,
  beschreibung TEXT           NOT NULL,
  betrag       NUMERIC(10,2)  NOT NULL,
  mwst         INTEGER        NOT NULL DEFAULT 19 CHECK (mwst IN (0, 7, 19)),
  kategorie    VARCHAR(50)    NOT NULL DEFAULT 'sonstiges',
  foto_base64  TEXT,
  created_at   TIMESTAMP      DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS belege_datum_idx ON belege (datum);
