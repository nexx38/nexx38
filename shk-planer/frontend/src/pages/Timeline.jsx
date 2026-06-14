import { useState, useEffect, useCallback } from 'react'
import { api } from '../api'

const CAT_COLOR = {
  office: '#3B82F6', baustelle: '#FF9F0A', lager: '#AF52DE',
  privat: '#34C759', montage: '#FF3B30', wartung: '#FF9500',
}
const CAT_ICON = {
  office: '💼', baustelle: '🔧', lager: '📦',
  privat: '🏠', montage: '🔩', wartung: '⚙️',
}
const pad = (n) => String(n).padStart(2, '0')

// "HH:MM" -> Minuten ab Mitternacht (null -> -1 = ganztägig/oben)
const toMin = (t) => {
  if (!t) return -1
  const [h, m] = t.split(':').map(Number)
  return h * 60 + (m || 0)
}
const hm = (t) => (t ? t.slice(0, 5) : null)

const EMPTY = { titel: '', von: '08:00', bis: '09:00', notizen: '' }

export default function Timeline({ date }) {
  const [termine, setTermine] = useState([])
  const [blocks,  setBlocks]  = useState([])
  const [loading, setLoading] = useState(true)
  const [sheet,   setSheet]   = useState(null)   // null | { mode:'new'|'edit', form, uid }
  const [busy,    setBusy]    = useState(false)
  const [err,     setErr]     = useState('')
  const [now,     setNow]     = useState(new Date())

  const today = new Date().toISOString().split('T')[0]
  const isToday = date === today

  const reload = useCallback(() => {
    setLoading(true)
    Promise.all([
      api.getTermine(date).catch(() => []),
      api.getTimeblocks(date).catch(() => []),
    ]).then(([te, bl]) => {
      setTermine(Array.isArray(te) ? te : [])
      setBlocks(Array.isArray(bl) ? bl : [])
    }).finally(() => setLoading(false))
  }, [date])

  useEffect(() => { reload() }, [reload])

  // Uhr für „Jetzt"-Linie
  useEffect(() => {
    if (!isToday) return
    const id = setInterval(() => setNow(new Date()), 60000)
    return () => clearInterval(id)
  }, [isToday])

  // ── Items zusammenführen & sortieren ──
  const items = []
  termine.forEach(t => items.push({
    kind: 'termin', id: t.id, uid: t.icloud_uid || (t.id || '').replace(/^ic_/, ''),
    titel: t.titel, startMin: toMin(hm(t.zeit_von)),
    von: hm(t.zeit_von), bis: hm(t.zeit_bis), notizen: t.notizen || '',
  }))
  blocks.forEach(b => items.push({
    kind: 'block', id: b.id, titel: b.title, category: b.category, person: b.person,
    done: b.done, startMin: (+b.hour) * 60, von: `${pad(b.hour)}:00`,
    bis: `${pad(+b.hour + (+b.duration || 1))}:00`, duration: +b.duration || 1,
  }))
  items.sort((a, b) => a.startMin - b.startMin)

  const nowMin = now.getHours() * 60 + now.getMinutes()
  // Render-Liste mit „Jetzt"-Marker an der richtigen Stelle
  const rows = []
  let nowPlaced = !isToday
  for (const it of items) {
    if (!nowPlaced && it.startMin > nowMin) { rows.push({ now: true }); nowPlaced = true }
    rows.push(it)
  }
  if (!nowPlaced) rows.push({ now: true })

  // ── Aktionen ──
  const openNew = () => { setErr(''); setSheet({ mode: 'new', form: { ...EMPTY }, uid: null }) }
  const openEdit = (it) => {
    setErr('')
    setSheet({ mode: 'edit', uid: it.uid, form: { titel: it.titel, von: it.von || '08:00', bis: it.bis || '09:00', notizen: it.notizen || '' } })
  }

  const save = async () => {
    const f = sheet.form
    if (!f.titel.trim()) { setErr('Bitte einen Titel eingeben'); return }
    setBusy(true); setErr('')
    const payload = { titel: f.titel.trim(), datum: date, zeit_von: f.von, zeit_bis: f.bis, notizen: f.notizen }
    try {
      if (sheet.mode === 'new') await api.createTermin(payload)
      else await api.updateTermin(sheet.uid, payload)
      setSheet(null); reload()
    } catch (e) {
      setErr('Konnte nicht in Apple speichern. Bitte erneut versuchen.')
    } finally { setBusy(false) }
  }

  const remove = async () => {
    setBusy(true); setErr('')
    try { await api.deleteTermin(sheet.uid); setSheet(null); reload() }
    catch (e) { setErr('Löschen fehlgeschlagen.') }
    finally { setBusy(false) }
  }

  const toggleBlock = async (b) => {
    setBlocks(bs => bs.map(x => x.id === b.id ? { ...x, done: !x.done } : x))
    try { await api.updateTimeblock(b.id, { done: !b.done }) } catch {}
  }

  return (
    <div style={{ padding: '8px 0 110px', minHeight: '100%' }}>
      {loading && <div style={spinner}>Laden…</div>}

      {!loading && items.length === 0 && (
        <div style={emptyBox}>
          <div style={{ fontSize: 40, marginBottom: 10 }}>🗓️</div>
          <div style={{ fontWeight: 600, fontSize: 16 }}>Keine Termine an diesem Tag</div>
          <div style={{ fontSize: 13, color: 'var(--text2)', marginTop: 6 }}>Tippe auf + für einen neuen Termin</div>
        </div>
      )}

      {!loading && rows.map((row, i) =>
        row.now
          ? <NowMarker key={`now-${i}`} label={`${pad(now.getHours())}:${pad(now.getMinutes())}`} />
          : row.kind === 'termin'
            ? <TerminRow key={row.id} it={row} onClick={() => openEdit(row)} />
            : <BlockRow key={row.id} it={row} onToggle={() => toggleBlock({ id: row.id, done: row.done })} />
      )}

      {/* FAB */}
      <button onClick={openNew} style={fab} aria-label="Neuer Termin">+</button>

      {/* Sheet */}
      {sheet && (
        <Sheet
          title={sheet.mode === 'new' ? 'Neuer Termin' : 'Termin bearbeiten'}
          onClose={() => setSheet(null)}
        >
          <input autoFocus placeholder="Titel *" value={sheet.form.titel}
            onChange={e => setSheet(s => ({ ...s, form: { ...s.form, titel: e.target.value } }))} />

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            <Field label="Von">
              <input type="time" value={sheet.form.von}
                onChange={e => setSheet(s => ({ ...s, form: { ...s.form, von: e.target.value } }))} />
            </Field>
            <Field label="Bis">
              <input type="time" value={sheet.form.bis}
                onChange={e => setSheet(s => ({ ...s, form: { ...s.form, bis: e.target.value } }))} />
            </Field>
          </div>

          <Field label="Notiz">
            <textarea rows={2} placeholder="optional" value={sheet.form.notizen}
              onChange={e => setSheet(s => ({ ...s, form: { ...s.form, notizen: e.target.value } }))} />
          </Field>

          <div style={{ fontSize: 12, color: 'var(--text2)', display: 'flex', alignItems: 'center', gap: 6 }}>
            <span></span> Wird direkt in deinem Apple-Kalender gespeichert
          </div>

          {err && <p style={{ color: 'var(--red)', fontSize: 13 }}>{err}</p>}

          <button onClick={save} disabled={busy} style={{ ...submitBtn, opacity: busy ? 0.6 : 1 }}>
            {busy ? 'Speichern…' : 'Speichern'}
          </button>
          {sheet.mode === 'edit' && (
            <button onClick={remove} disabled={busy} style={deleteBtn}>Löschen</button>
          )}
        </Sheet>
      )}
    </div>
  )
}

// ── Zeilen ──────────────────────────────────────────────────────────────────

function Rail({ icon, color }) {
  return (
    <div style={{ width: 52, flexShrink: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', position: 'relative' }}>
      <div style={{ position: 'absolute', top: 0, bottom: -16, width: 2, background: 'var(--line)' }} />
      <div style={{
        position: 'relative', width: 38, height: 38, borderRadius: '50%',
        background: color, color: '#fff', display: 'flex', alignItems: 'center',
        justifyContent: 'center', fontSize: 18, boxShadow: 'var(--shadow)', marginTop: 4,
      }}>{icon}</div>
    </div>
  )
}

function TerminRow({ it, onClick }) {
  return (
    <div style={{ display: 'flex', gap: 12, padding: '0 16px' }}>
      <div style={{ width: 44, flexShrink: 0, textAlign: 'right', paddingTop: 10, fontSize: 12, color: 'var(--text2)' }}>
        {it.von || ''}
      </div>
      <Rail icon="📅" color="var(--accent)" />
      <button onClick={onClick} style={{ ...card, textAlign: 'left' }}>
        <div style={{ fontWeight: 600, fontSize: 15 }}>{it.titel}</div>
        <div style={{ fontSize: 12.5, color: 'var(--text2)', marginTop: 3 }}>
          {it.von ? `${it.von}${it.bis ? '–' + it.bis : ''}` : 'ganztägig'}
          {it.notizen ? ` · ${it.notizen}` : ''}
        </div>
        <span style={appleBadge}>Apple</span>
      </button>
    </div>
  )
}

function BlockRow({ it, onToggle }) {
  const color = CAT_COLOR[it.category] || 'var(--blue)'
  return (
    <div style={{ display: 'flex', gap: 12, padding: '0 16px' }}>
      <div style={{ width: 44, flexShrink: 0, textAlign: 'right', paddingTop: 10, fontSize: 12, color: 'var(--text2)' }}>
        {it.von}
      </div>
      <Rail icon={CAT_ICON[it.category] || '📋'} color={color} />
      <div style={{ ...card, opacity: it.done ? 0.55 : 1, display: 'flex', alignItems: 'center', gap: 10 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 600, fontSize: 15, textDecoration: it.done ? 'line-through' : 'none' }}>{it.titel}</div>
          <div style={{ fontSize: 12.5, color: 'var(--text2)', marginTop: 3 }}>
            {it.von}–{it.bis}{it.duration > 1 ? ` (${it.duration} Std.)` : ''}{it.person ? ` · ${it.person}` : ''}
          </div>
        </div>
        <button onClick={onToggle} style={{
          width: 26, height: 26, borderRadius: '50%', flexShrink: 0,
          border: `2px solid ${it.done ? 'var(--green)' : 'var(--border)'}`,
          background: it.done ? 'var(--green)' : 'transparent',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>{it.done && <span style={{ color: '#fff', fontSize: 13 }}>✓</span>}</button>
      </div>
    </div>
  )
}

function NowMarker({ label }) {
  return (
    <div style={{ display: 'flex', gap: 12, padding: '0 16px', alignItems: 'center', margin: '2px 0' }}>
      <div style={{ width: 44, flexShrink: 0, textAlign: 'right', fontSize: 12, fontWeight: 700, color: 'var(--accent)' }}>{label}</div>
      <div style={{ width: 52, flexShrink: 0, display: 'flex', justifyContent: 'center' }}>
        <div style={{ width: 10, height: 10, borderRadius: '50%', background: 'var(--accent)' }} />
      </div>
      <div style={{ flex: 1, height: 2, background: 'var(--accent)', borderRadius: 2, opacity: 0.7 }} />
    </div>
  )
}

// ── UI-Helfer ────────────────────────────────────────────────────────────────

function Field({ label, children }) {
  return (
    <div>
      <div style={{ fontSize: 12, color: 'var(--text2)', marginBottom: 6, fontWeight: 500 }}>{label}</div>
      {children}
    </div>
  )
}

function Sheet({ title, onClose, children }) {
  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.35)', display: 'flex', alignItems: 'flex-end', zIndex: 200 }}
      onClick={e => e.target === e.currentTarget && onClose()}>
      <div style={{
        background: 'var(--bg)', borderRadius: '22px 22px 0 0', width: '100%',
        padding: '18px 18px max(28px, env(safe-area-inset-bottom))',
        display: 'flex', flexDirection: 'column', gap: 12, maxHeight: '92dvh', overflowY: 'auto',
        maxWidth: 480, margin: '0 auto',
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h3 style={{ fontWeight: 700, fontSize: 18 }}>{title}</h3>
          <button onClick={onClose} style={{ color: 'var(--text2)', fontSize: 22 }}>✕</button>
        </div>
        {children}
      </div>
    </div>
  )
}

const spinner = { textAlign: 'center', padding: 48, color: 'var(--text2)' }
const emptyBox = { textAlign: 'center', padding: '72px 24px', color: 'var(--text)' }
const card = {
  flex: 1, minWidth: 0, background: 'var(--bg2)', borderRadius: 'var(--radius)',
  padding: '12px 14px', marginBottom: 14, boxShadow: 'var(--shadow)', position: 'relative',
}
const appleBadge = {
  position: 'absolute', top: 12, right: 12, fontSize: 10, fontWeight: 700,
  color: 'var(--accent)', background: 'rgba(255,111,97,0.12)', padding: '2px 7px', borderRadius: 10,
}
const fab = {
  position: 'fixed', bottom: 84, right: 20, width: 58, height: 58, borderRadius: '50%',
  background: 'var(--accent)', color: '#fff', fontSize: 30, lineHeight: 1,
  display: 'flex', alignItems: 'center', justifyContent: 'center',
  boxShadow: '0 6px 20px rgba(255,111,97,0.45)', zIndex: 100,
}
const submitBtn = {
  background: 'var(--accent)', color: '#fff', padding: '14px', borderRadius: 14,
  fontWeight: 700, fontSize: 16, marginTop: 2, width: '100%',
}
const deleteBtn = {
  background: 'rgba(255,59,48,0.1)', color: 'var(--red)', padding: '12px', borderRadius: 14,
  fontWeight: 600, fontSize: 15, width: '100%',
}
