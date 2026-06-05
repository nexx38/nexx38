import { useState, useEffect } from 'react'
import { api } from '../api'

const PRIO_COLOR = { high: '#EF4444', medium: '#F59E0B', low: '#10B981' }
const PRIO_LABEL = { high: 'Hoch', medium: 'Mittel', low: 'Niedrig' }
const CAT_COLOR  = {
  office:    '#3B82F6',
  baustelle: '#F59E0B',
  lager:     '#8B5CF6',
  privat:    '#10B981',
  montage:   '#EF4444',
  wartung:   '#F97316',
}
const CATS = Object.keys(CAT_COLOR)
const INIT = { text: '', category: 'office', person: 'Tamer', priority: 'medium' }

export default function TodoList({ date }) {
  const [todos,   setTodos]   = useState([])
  const [loading, setLoading] = useState(true)
  const [modal,   setModal]   = useState(false)
  const [form,    setForm]    = useState(INIT)
  const [err,     setErr]     = useState('')

  useEffect(() => {
    setLoading(true)
    api.getTodos(date)
      .then(d => setTodos(Array.isArray(d) ? d : []))
      .catch(() => setTodos([]))
      .finally(() => setLoading(false))
  }, [date])

  const toggle = async (t) => {
    setTodos(ts => ts.map(x => x.id === t.id ? { ...x, done: !x.done } : x))
    await api.updateTodo(t.id, { done: !t.done })
  }

  const remove = async (id) => {
    setTodos(ts => ts.filter(t => t.id !== id))
    await api.deleteTodo(id)
  }

  const add = async () => {
    if (!form.text.trim()) { setErr('Bitte Text eingeben'); return }
    setErr('')
    const created = await api.createTodo({ ...form, date })
    setTodos(ts => [...ts, created])
    setModal(false)
    setForm(INIT)
  }

  const open = todos.filter(t => !t.done)
  const done = todos.filter(t =>  t.done)

  return (
    <div style={{ padding: '16px 16px 100px', minHeight: '100%' }}>

      {loading && <div style={{ textAlign: 'center', padding: 48, color: 'var(--text2)' }}>Laden…</div>}

      {!loading && todos.length === 0 && (
        <div style={{ textAlign: 'center', padding: 64, color: 'var(--text2)' }}>
          <div style={{ fontSize: 44, marginBottom: 12 }}>☑</div>
          <div style={{ fontSize: 16, fontWeight: 500 }}>Keine To-Dos für diesen Tag</div>
          <div style={{ fontSize: 13, marginTop: 8 }}>Tippe + um etwas hinzuzufügen</div>
        </div>
      )}

      {open.length > 0 && (
        <section style={{ marginBottom: 24 }}>
          <SectionHeader label="Offen" count={open.length} />
          {open.map(t => <TodoItem key={t.id} todo={t} onToggle={toggle} onDelete={remove} />)}
        </section>
      )}

      {done.length > 0 && (
        <section>
          <SectionHeader label="Erledigt" count={done.length} />
          {done.map(t => <TodoItem key={t.id} todo={t} onToggle={toggle} onDelete={remove} />)}
        </section>
      )}

      {/* FAB */}
      <button onClick={() => setModal(true)} style={fab}>+</button>

      {/* Modal */}
      {modal && (
        <Sheet onClose={() => setModal(false)} title="To-Do hinzufügen">
          <input placeholder="Was muss erledigt werden? *" value={form.text}
            onChange={e => setForm(f => ({ ...f, text: e.target.value }))}
            onKeyDown={e => e.key === 'Enter' && add()} autoFocus />
          {err && <p style={{ color: 'var(--red)', fontSize: 13 }}>{err}</p>}

          <div>
            <div style={{ fontSize: 12, color: 'var(--text2)', marginBottom: 6, fontWeight: 500 }}>Priorität</div>
            <div style={{ display: 'flex', gap: 8 }}>
              {['high','medium','low'].map(p => (
                <button key={p} onClick={() => setForm(f => ({ ...f, priority: p }))} style={{
                  flex: 1, padding: '9px 4px', borderRadius: 8, fontSize: 13, fontWeight: 600,
                  background: form.priority === p ? PRIO_COLOR[p] : 'var(--bg3)',
                  color: form.priority === p ? 'white' : 'var(--text2)',
                  border: `1px solid ${form.priority === p ? PRIO_COLOR[p] : 'var(--border)'}`,
                  transition: 'all 0.15s',
                }}>
                  {PRIO_LABEL[p]}
                </button>
              ))}
            </div>
          </div>

          <div>
            <div style={{ fontSize: 12, color: 'var(--text2)', marginBottom: 6, fontWeight: 500 }}>Kategorie</div>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              {CATS.map(c => (
                <button key={c} onClick={() => setForm(f => ({ ...f, category: c }))} style={{
                  padding: '6px 12px', borderRadius: 20, fontSize: 13,
                  background: form.category === c ? (CAT_COLOR[c] || 'var(--accent)') : 'var(--bg3)',
                  color: form.category === c ? 'white' : 'var(--text2)',
                  border: `1px solid ${form.category === c ? (CAT_COLOR[c] || 'var(--accent)') : 'var(--border)'}`,
                  transition: 'all 0.15s',
                }}>
                  {c}
                </button>
              ))}
            </div>
          </div>

          <input placeholder="Person" value={form.person}
            onChange={e => setForm(f => ({ ...f, person: e.target.value }))} />

          <button onClick={add} style={submitBtn}>Hinzufügen</button>
        </Sheet>
      )}
    </div>
  )
}

function TodoItem({ todo, onToggle, onDelete }) {
  const color = PRIO_COLOR[todo.priority] || 'var(--accent)'
  return (
    <div style={{
      background: 'var(--bg2)', borderRadius: 'var(--radius)',
      padding: '12px 14px', marginBottom: 8,
      display: 'flex', alignItems: 'center', gap: 12,
      borderLeft: `3px solid ${color}`,
      opacity: todo.done ? 0.55 : 1, transition: 'opacity 0.2s',
    }}>
      {/* Done toggle */}
      <button onClick={() => onToggle(todo)} style={{
        width: 24, height: 24, borderRadius: '50%', flexShrink: 0,
        border: `2px solid ${todo.done ? 'var(--green)' : 'var(--border)'}`,
        background: todo.done ? 'var(--green)' : 'transparent',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        transition: 'all 0.15s',
      }}>
        {todo.done && <span style={{ color: 'white', fontSize: 12, lineHeight: 1 }}>✓</span>}
      </button>

      {/* Content */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontWeight: 500, fontSize: 15,
          textDecoration: todo.done ? 'line-through' : 'none',
          color: todo.done ? 'var(--text2)' : 'var(--text)',
        }}>
          {todo.text}
        </div>
        <div style={{ fontSize: 12, color: 'var(--text2)', marginTop: 3, display: 'flex', gap: 8, alignItems: 'center' }}>
          <span style={{
            background: (CAT_COLOR[todo.category] || 'var(--accent)') + '2A',
            color: CAT_COLOR[todo.category] || 'var(--accent)',
            padding: '1px 8px', borderRadius: 20, fontSize: 11,
          }}>
            {todo.category}
          </span>
          {todo.person && <span>{todo.person}</span>}
        </div>
      </div>

      {/* Delete */}
      <button onClick={() => onDelete(todo.id)} style={{ color: 'var(--text2)', fontSize: 20, flexShrink: 0, padding: '0 4px' }}>×</button>
    </div>
  )
}

function SectionHeader({ label, count }) {
  return (
    <div style={{ fontSize: 11, fontWeight: 600, color: 'var(--text2)', textTransform: 'uppercase', letterSpacing: 1, marginBottom: 10 }}>
      {label} ({count})
    </div>
  )
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
