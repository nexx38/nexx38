#!/bin/bash
# deploy_mail_fetcher.sh
# Einmal auf dem Hetzner-Server ausführen:
#   bash /root/deploy_mail_fetcher.sh
# Lädt den Mail-Fetcher aus GitHub, richtet Cron ein und verarbeitet sofort alle offenen Rechnungen.

set -e

SCRIPT_URL="https://raw.githubusercontent.com/nexx38/nexx38/claude/shk-company-setup-X9y7A/mail_rechnung_fetcher.py"
DEST="/root/mail_rechnung_fetcher.py"
LOG="/var/log/shk_mail.log"
CRON_ENTRY="*/10 * * * * /usr/bin/python3 /root/mail_rechnung_fetcher.py >> /var/log/shk_mail.log 2>&1"

echo "=== SHK Mail-Fetcher Deployment ==="
echo ""

# 1. Skript herunterladen
echo "[1/3] Lade Skript von GitHub …"
curl -fsSL "$SCRIPT_URL" -o "$DEST"
chmod 700 "$DEST"
echo "      Gespeichert: $DEST"

# 2. Cron einrichten (nur wenn noch nicht vorhanden)
echo "[2/3] Richte Cron-Job ein (alle 10 Minuten) …"
CURRENT_CRON=$(crontab -l 2>/dev/null || true)
if echo "$CURRENT_CRON" | grep -q "mail_rechnung_fetcher"; then
    echo "      Cron-Eintrag bereits vorhanden – keine Änderung."
else
    (echo "$CURRENT_CRON"; echo "$CRON_ENTRY") | crontab -
    echo "      Cron-Eintrag hinzugefügt: $CRON_ENTRY"
fi

# 3. Sofort ausführen – verarbeitet alle ungelesenen Rechnungs-Mails jetzt
echo "[3/3] Starte einmalige Verarbeitung aller offenen Mails …"
echo ""
python3 "$DEST"

echo ""
echo "=== Fertig ==="
echo "Log: $LOG"
echo "Cron läuft alle 10 Minuten automatisch."
echo ""
echo "Log anzeigen:   tail -f $LOG"
echo "Cron prüfen:    crontab -l"
