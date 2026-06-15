#!/usr/bin/env python3
"""
mail_rechnung_fetcher.py
Holt PDF-Rechnungen aus rechnungen@shk-innovation.de (IMAP)
und bucht sie automatisch in das SHK-System via /api/eingangsrechnungen/upload.

Cron: */10 * * * * /usr/bin/python3 /root/mail_rechnung_fetcher.py >> /var/log/shk_mail.log 2>&1
"""

import imaplib
import email
import os
import sys
import logging
import tempfile
import json
import time
import urllib.request
import urllib.parse
import urllib.error
from email.header import decode_header
from datetime import datetime

# ── Konfiguration ──────────────────────────────────────────────────────────────
IMAP_HOST     = 'imap.strato.de'
IMAP_PORT     = 993
IMAP_USER     = 'rechnungen@shk-innovation.de'
IMAP_PASS     = '1S9evinc00!'

API_URL       = 'http://localhost:3000/api/eingangsrechnungen/upload'
LOG_FILE      = '/var/log/shk_mail.log'
LOCK_FILE     = '/tmp/shk_mail_fetcher.lock'
MAX_PDF_SIZE  = 30 * 1024 * 1024   # 30 MB

# ── Logging ────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [mail_fetcher] %(levelname)s %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
log = logging.getLogger(__name__)


def decode_str(raw):
    """Decode encoded mail header value."""
    parts = decode_header(raw or '')
    result = []
    for part, enc in parts:
        if isinstance(part, bytes):
            result.append(part.decode(enc or 'utf-8', errors='replace'))
        else:
            result.append(part)
    return ''.join(result)


def upload_pdf(pdf_bytes: bytes, filename: str) -> dict:
    """POST PDF to /api/eingangsrechnungen/upload using multipart/form-data."""
    boundary = '----SHKMailFetcherBoundary' + str(int(time.time()))
    safe_name = filename.replace('"', '_')

    body_parts = []
    body_parts.append(
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="rechnung"; filename="{safe_name}"\r\n'
        f'Content-Type: application/pdf\r\n'
        f'\r\n'.encode()
    )
    body_parts.append(pdf_bytes)
    body_parts.append(f'\r\n--{boundary}--\r\n'.encode())

    body = b''.join(body_parts)

    req = urllib.request.Request(
        API_URL,
        data=body,
        method='POST',
        headers={
            'Content-Type':   f'multipart/form-data; boundary={boundary}',
            'Content-Length': str(len(body)),
        }
    )

    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())


def process_mailbox():
    """Connect to IMAP, fetch unseen mails with PDFs, upload each."""
    log.info('Verbinde mit %s …', IMAP_HOST)
    mail = imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT)
    mail.login(IMAP_USER, IMAP_PASS)
    mail.select('INBOX')

    # Suche alle ungelesenen Mails
    status, data = mail.search(None, 'UNSEEN')
    if status != 'OK':
        log.warning('IMAP search fehlgeschlagen: %s', status)
        return

    mail_ids = data[0].split()
    if not mail_ids:
        log.info('Keine neuen Mails.')
        mail.logout()
        return

    log.info('%d neue Mail(s) gefunden.', len(mail_ids))
    processed = 0
    errors    = 0

    for mail_id in mail_ids:
        try:
            status, msg_data = mail.fetch(mail_id, '(RFC822)')
            if status != 'OK':
                log.error('Fetch %s fehlgeschlagen.', mail_id)
                errors += 1
                continue

            raw_email = msg_data[0][1]
            msg       = email.message_from_bytes(raw_email)
            subject   = decode_str(msg.get('Subject', '(kein Betreff)'))
            sender    = decode_str(msg.get('From', ''))
            date_hdr  = msg.get('Date', '')
            log.info('Mail %s | Von: %s | Betreff: %s | Datum: %s',
                     mail_id.decode(), sender, subject, date_hdr)

            # PDF-Anhänge suchen
            pdf_found = False
            for part in msg.walk():
                ct = part.get_content_type()
                cd = part.get('Content-Disposition', '')
                is_pdf = (
                    ct == 'application/pdf' or
                    ct == 'application/octet-stream' and 'pdf' in cd.lower()
                )
                if not is_pdf:
                    continue

                filename = part.get_filename()
                if not filename:
                    filename = f'rechnung_{mail_id.decode()}.pdf'
                filename = decode_str(filename)

                pdf_data = part.get_payload(decode=True)
                if not pdf_data:
                    log.warning('PDF-Anhang leer: %s', filename)
                    continue
                if len(pdf_data) > MAX_PDF_SIZE:
                    log.warning('PDF zu groß (%d MB), übersprungen: %s',
                                len(pdf_data) // 1048576, filename)
                    continue

                log.info('Uploade PDF: %s (%d KB) …', filename, len(pdf_data) // 1024)
                try:
                    result = upload_pdf(pdf_data, filename)
                    log.info('✓ Gebucht: %s → ID %s | Betrag: %s €',
                             filename,
                             result.get('id', '?'),
                             result.get('gesamtbetrag', result.get('betrag', '?')))
                    pdf_found = True
                    processed += 1
                except urllib.error.HTTPError as e:
                    body = e.read().decode(errors='replace')
                    log.error('API-Fehler %d für %s: %s', e.code, filename, body)
                    errors += 1
                    continue
                except Exception as e:
                    log.error('Upload-Fehler für %s: %s', filename, e)
                    errors += 1
                    continue

            if pdf_found:
                # Als gelesen markieren erst nach erfolgreichem Upload
                mail.store(mail_id, '+FLAGS', '\\Seen')
                log.info('Mail %s als gelesen markiert.', mail_id.decode())
            else:
                log.info('Mail %s enthält keine PDF-Anhänge – übersprungen.',
                         mail_id.decode())

        except Exception as e:
            log.error('Fehler bei Mail %s: %s', mail_id, e)
            errors += 1
            continue

    mail.logout()
    log.info('Fertig. %d verarbeitet, %d Fehler.', processed, errors)
    return processed, errors


def main():
    # Lock-Datei – verhindert parallele Ausführung via Cron
    if os.path.exists(LOCK_FILE):
        age = time.time() - os.path.getmtime(LOCK_FILE)
        if age < 300:
            log.info('Bereits aktiv (lock %ds alt). Beende.', int(age))
            sys.exit(0)
        else:
            log.warning('Veralteter Lock (%ds) entfernt.', int(age))
            os.remove(LOCK_FILE)

    try:
        with open(LOCK_FILE, 'w') as f:
            f.write(str(os.getpid()))
        process_mailbox()
    finally:
        try:
            os.remove(LOCK_FILE)
        except FileNotFoundError:
            pass


if __name__ == '__main__':
    main()
