#!/bin/bash
# SHK Planer – Deploy-Skript
# Ausführen auf dem VPS: bash /root/shk-planer/deploy.sh
set -e

PLANER_DIR="/root/shk-planer"
cd "$PLANER_DIR"

echo "╔═══════════════════════════════════╗"
echo "║    SHK Planer – Deploy Start      ║"
echo "╚═══════════════════════════════════╝"

# ── 1. PostgreSQL Tabellen ─────────────────────────────────────────────────
echo ""
echo "▶ Schritt 1: PostgreSQL Tabellen anlegen…"
docker exec shk-db psql -U shkuser -d shkdb << 'EOSQL'
CREATE TABLE IF NOT EXISTS todos (
  id SERIAL PRIMARY KEY,
  text TEXT NOT NULL,
  category VARCHAR(20) DEFAULT 'office',
  person VARCHAR(50) DEFAULT 'Tamer',
  priority VARCHAR(10) DEFAULT 'medium',
  done BOOLEAN DEFAULT false,
  date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS timeblocks (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  hour INTEGER NOT NULL,
  duration INTEGER DEFAULT 1,
  category VARCHAR(20) DEFAULT 'office',
  person VARCHAR(50) DEFAULT 'Tamer',
  done BOOLEAN DEFAULT false,
  date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMP DEFAULT NOW()
);
EOSQL
echo "✓ Tabellen erstellt."

# ── 2. Server-Abhängigkeiten ───────────────────────────────────────────────
echo ""
echo "▶ Schritt 2: Server-Abhängigkeiten installieren…"
cd "$PLANER_DIR"
npm install --omit=dev
echo "✓ Server-Pakete installiert."

# ── 3. PWA-Icons generieren ────────────────────────────────────────────────
echo ""
echo "▶ Schritt 3: PWA-Icons generieren…"
python3 - << 'PYEOF'
import struct, zlib

def make_png(size, r, g, b):
    def chunk(t, d):
        c = zlib.crc32(t + d) & 0xffffffff
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', c)
    raw = b''.join(b'\x00' + bytes([r, g, b] * size) for _ in range(size))
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 6))
            + chunk(b'IEND', b''))

for sz in [192, 512]:
    path = f'/root/shk-planer/frontend/public/icon-{sz}.png'
    open(path, 'wb').write(make_png(sz, 59, 130, 246))
    print(f'  icon-{sz}.png erstellt')
PYEOF
echo "✓ Icons generiert."

# ── 4. Frontend bauen ──────────────────────────────────────────────────────
echo ""
echo "▶ Schritt 4: Frontend bauen…"
cd "$PLANER_DIR/frontend"
npm install
npm run build
echo "✓ Frontend gebaut → dist/"

# ── 5. PM2 starten/neustarten ─────────────────────────────────────────────
echo ""
echo "▶ Schritt 5: PM2 starten…"
cd "$PLANER_DIR"
if pm2 describe shk-planer > /dev/null 2>&1; then
  pm2 restart shk-planer
  echo "✓ PM2 neugestartet."
else
  pm2 start server.js --name shk-planer
  echo "✓ PM2 gestartet."
fi
pm2 save

# ── 6. Nginx konfigurieren ─────────────────────────────────────────────────
echo ""
echo "▶ Schritt 6: Nginx konfigurieren…"
cp "$PLANER_DIR/setup/nginx.conf" /etc/nginx/sites-available/shk-planer
ln -sf /etc/nginx/sites-available/shk-planer /etc/nginx/sites-enabled/shk-planer
nginx -t
systemctl reload nginx
echo "✓ Nginx neu geladen."

# ── 7. Smoke-Test ──────────────────────────────────────────────────────────
echo ""
echo "▶ Schritt 7: API-Test…"
sleep 2
HEALTH=$(curl -s http://localhost:3002/api/health 2>/dev/null || echo '{"status":"no response"}')
echo "  Health: $HEALTH"

curl -s -X POST http://localhost:3002/api/todos \
  -H 'Content-Type: application/json' \
  -d '{"text":"Testtodo vom Deploy","category":"office","person":"Tamer","priority":"medium"}' | python3 -m json.tool || true

echo ""
echo "╔═══════════════════════════════════╗"
echo "║    SHK Planer – Deploy fertig!    ║"
echo "╚═══════════════════════════════════╝"
echo ""
echo "  API:      http://localhost:3002/api/health"
echo "  Frontend: http://planer.shk-innovation.de"
echo ""
pm2 status
