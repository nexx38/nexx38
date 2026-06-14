#!/bin/bash
# SHK Planer – Deploy-Skript
# Ausführen auf dem VPS: bash /root/shk-planer/deploy.sh
set -e

# nvm laden (für PM2 in non-interaktiven SSH-Sessions)
export NVM_DIR="${HOME}/.nvm"
[ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"

PLANER_DIR="/root/shk-planer"
cd "$PLANER_DIR"

echo "╔═══════════════════════════════════╗"
echo "║    SHK Planer – Deploy Start      ║"
echo "╚═══════════════════════════════════╝"

# ── 1. PostgreSQL Tabellen ─────────────────────────────────────────────────
echo ""
echo "▶ Schritt 1: PostgreSQL Tabellen anlegen…"
docker exec -i shk-db psql -U shk -d shkdb << 'EOSQL'
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
docker run --rm \
  -v "$PLANER_DIR/frontend:/app" \
  -w /app \
  node:20-alpine \
  sh -c "npm install && npm run build"
echo "✓ Frontend gebaut → dist/"

# ── 4b. Frontend nach /var/www kopieren ────────────────────────────────────
echo ""
echo "▶ Schritt 4b: Frontend nach /var/www/shk-planer kopieren…"
mkdir -p /var/www/shk-planer
cp -r "$PLANER_DIR/frontend/dist/." /var/www/shk-planer/
echo "✓ Frontend kopiert."

# ── 5. Backend als Docker-Container neustarten ────────────────────────────
echo ""
echo "▶ Schritt 5: Backend-Docker-Container starten…"
cd "$PLANER_DIR"
# Port 3002 freigeben: PM2/node-Prozess beenden
pkill -9 -f "node server.js" 2>/dev/null || true
pkill -9 -f "node /root/shk-planer" 2>/dev/null || true
sleep 2
docker stop shk-planer-backend 2>/dev/null || true
docker rm   shk-planer-backend 2>/dev/null || true
docker build -t shk-planer-backend .
docker run -d \
  --name shk-planer-backend \
  --restart unless-stopped \
  --network shk-app_default \
  -p 3002:3002 \
  shk-planer-backend
echo "✓ Backend-Container gestartet."

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
docker ps --filter name=shk-planer-backend
