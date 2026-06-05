import { useState, useEffect } from 'react'
import { api } from '../api'

const CAT_COLOR = {
  office:    '#3B82F6',
  baustelle: '#F59E0B',
  lager:     '#8B5CF6',
  privat:    '#10B981',
  montage:   '#EF4444',
  wartung:   '#F97316',
}
const CAT_ICON = {
  office:    '💼',
  baustelle: '🔧',
  lager:     '📦',
  privat:    '🏠',
  montage:   '🔩',
  wartung:   '⚙️',
}
const HOURS = Array.from({ length: 17 }, (_, i) => i + 6)  // 06-22
const pad   = (n) => String(n).padStart(2, '0')
const CATS  = Object.keys(CAT_COLOR)

const INIT = { title: '', hour: 8, duration: 1, category: 'office', person: 'Tamer' }

export default function Timeline({ date }) {
  const [blocks,  setBlocks]  = useState([])
  const [loading, setLoading] = useState(true)
  const [modal,   setModal]   = useState(false)
  const [form,    setForm]    = useState(INIT)
  const [err,     setErr]     = useState('')

  useEffect(() => {
    setLoading(true)
    api.getTimeblocks(date)
      .then(d => setBlocks(Array.isArray(d) ? d : []))
      .catch(() => setBlocks([]))
      .finally(() => setLoading(false))
  }, [date])

  const toggle = async (b) => {
    setBlocks(bs => bs.map(x => x.id === b.id ? { ...x, done: !x.done } : x))
    await api.updateTimeblock(b.id, { done: !b.done })
  }

  const remove = async (id) => {
    setBlocks(bs => bs.filter(b => b.id !== id))
    await api.deleteTimeblock(id)
  }

  const add = async () => {
    if (!form.title.trim()) { setErr('Bitte Titel eingeben'); return }
    setErr('')
    const created = await api.createTimeblock({ ...form, date })
    setBlocks(bs => [...bs, created].sort((a, b) => a.hour - b.hour))
    setModal(false)
    setForm(INIT)
  }

  const byHour = {}
  blocks.forEach(b => { const h = +b.hour; (byHour[h] ??= []).push(b) })

  return (
    <div style={{ position: 'relative', paddingBottom: 100 }}>

      {loading && <Spinner />}

      {!loading && (
        <div>
          {HOURS.map(h => (
            <div key={h} style={{ display: 'flex', minHeight: 56 }}>
              {/* Hour label */}
              <div style={{ width: 52, flexShrink: 0, paddingTop: 2, paddingRight: 10, textAlign: 'right', fontSize: 12, color: 'var(--text2)', userSelect: 'none' }}>
                {pad(h)}:00
              </div>

              {/* Line + blocks */}
              <div style={{ flex: 1, borderLeft: '1px solid var(--border)', paddingLeft: 12, paddingRight: 16, paddingBottom: 4, paddingTop: 2 }}>
                {(byHour[h] || []).map(b => (
                  <Block key={b.id} block={b} onToggle={toggle} onDelete={remove} />
                ))}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* FAB */}
      <button onClick={() => setModal(true)} style={fab}>+</button>

      {/* Modal */}
      {modal && (
        <Sheet onClose={() => setModal(false)} title="Zeitblock hinzufügen">
          <input placeholder="Titel *" value={form.title}
            onChange={e => setForm(f => ({ ...f, title: e.target.value }))}
            onKeyDown={e => e.key === 'Enter' && add()} autoFocus />
          {err && <p style={{ color: 'var(--red)', fontSize: 13 }}>{err}</p>}

          <Row>
            <Field label="Uhrzeit">
              <select value={form.hour} onChange={e => setForm(f => ({ ...f, hour: +e.target.value }))}>
                {HOURS.map(h => <option key={h} value={h}>{pad(h)}:00</option>)}
              </select>
            </Field>
            <Field label="Dauer (Std.)">
              <select value={form.duration} onChange={e => setForm(f => ({ ...f, duration: +e.target.value }))}>
                {[1,2,3,4,5,6,7,8].map(d => <option key={d} value={d}>{d} Std.</option>)}
              </select>
            </Field>
          </Row>

          <Field label="Kategorie">
            <ChipRow cats={CATS} selected={form.category} onSelect={cat => setForm(f => ({ ...f, category: cat }))} />
          </Field>

          <Field label="Person">
            <input placeholder="Person" value={form.person}
              onChange={e => setForm(f => ({ ...f, person: e.target.value }))} />
          </Field>

          <button onClick={add} style={submitBtn}>Hinzufügen</button>
        </Sheet>
      )}
    </div>
  )
}

function Block({ block, onToggle, onDelete }) {
  const color = CAT_COLOR[block.category] || 'var(--accent)'
  const endH  = +block.hour + +block.duration
  return (
    <div style={{
      background: 'var(--bg2)', borderRadius: 'var(--radius)',
      padding: '10px 12px', marginBottom: 8,
      display: 'flex', alignItems: 'center', gap: 10,
      borderLeft: `3px solid ${color}`,
      opacity: block.done ? 0.55 : 1, transition: 'opacity 0.2s',
    }}>
      <span style={{ fontSize: 18, flexShrink: 0 }}>{CAT_ICON[block.category] || '📋'}</span>

      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontWeight: 600, fontSize: 14,
          textDecoration: block.done ? 'line-through' : 'none',
          color: block.done ? 'var(--text2)' : 'var(--text)',
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        }}>
          {block.title}
        </div>
        <div style={{ fontSize: 12, color: 'var(--text2)', marginTop: 2 }}>
          {pad(block.hour)}:00 – {pad(endH)}:00
          {+block.duration > 1 && ` (${block.duration} Std.)`}
          {block.person && ` · ${block.person}`}
        </div>
      </div>

      {/* Delete */}
      <button onClick={() => onDelete(block.id)}
        style={{ color: 'var(--text2)', fontSize: 18, padding: '0 4px', flexShrink: 0 }}>×</button>

      {/* Done toggle */}
      <button onClick={() => onToggle(block)} style={{
        width: 28, height: 28, borderRadius: '50%', flexShrink: 0,
        border: `2px solid ${block.done ? 'var(--green)' : 'var(--border)'}`,
        background: block.done ? 'var(--green)' : 'transparent',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        transition: 'all 0.15s',
      }}>
        {block.done && <span style={{ color: 'white', fontSize: 14, lineHeight: 1 }}>✓</span>}
      </button>
    </div>
  )
}

// ── Shared UI helpers ──────────────────────────────────────────────────────

function Spinner() {
  return <div style={{ textAlign: 'center', padding: 48, color: 'var(--text2)' }}>Laden…</div>
}

function Sheet({ onClose, title, children }) {
  return (
    <div
      style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.65)', display: 'flex', alignItems: 'flex-end', zIndex: 200 }}
      onClick={e => e.target === e.currentTarget && onClose()}
    >
      <div style={{
        background: 'var(--bg2)', borderRadius: '20px 20px 0 0',
        padding: '20px 20px max(32px,env(safe-area-inset-bottom))', width: '100%',
        display: 'flex', flexDirection: 'column', gap: 12,
        maxHeight: '90dvh', overflowY: 'auto',
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }}>
          <h3 style={{ fontWeight: 700, fontSize: 18 }}>{title}</h3>
          <button onClick={onClose} style={{ color: 'var(--text2)', fontSize: 22, lineHeight: 1 }}>✕</button>
        </div>
        {children}
      </div>
    </div>
  )
}

function Field({ label, children }) {
  return (
    <div>
      <div style={{ fontSize: 12, color: 'var(--text2)', marginBottom: 6, fontWeight: 500 }}>{label}</div>
      {children}
    </div>
  )
}

function Row({ children }) {
  return <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>{children}</div>
}

function ChipRow({ cats, selected, onSelect }) {
  return (
    <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
      {cats.map(c => (
        <button key={c} onClick={() => onSelect(c)} style={{
          padding: '6px 12px', borderRadius: 20, fontSize: 13,
          background: selected === c ? (CAT_COLOR[c] || 'var(--accent)') : 'var(--bg3)',
          color: selected === c ? 'white' : 'var(--text2)',
          border: `1px solid ${selected === c ? (CAT_COLOR[c] || 'var(--accent)') : 'var(--border)'}`,
          transition: 'all 0.15s',
        }}>
          {CAT_ICON[c]} {c}
        </button>
      ))}
    </div>
  )
}

const fab = {
  position: 'fixed', bottom: 80, right: 20,
  width: 56, height: 56, borderRadius: '50%',
  background: 'var(--accent)', color: 'white', fontSize: 30, lineHeight: 1,
  display: 'flex', alignItems: 'center', justifyContent: 'center',
  boxShadow: '0 4px 20px rgba(59,130,246,0.45)', zIndex: 100,
}

const submitBtn = {
  background: 'var(--accent)', color: 'white',
  padding: '14px', borderRadius: 12, fontWeight: 600, fontSize: 16, marginTop: 4,
  width: '100%',
}
