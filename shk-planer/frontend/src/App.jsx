import { useState } from 'react'
import Timeline from './pages/Timeline'
import TodoList from './pages/TodoList'

const DAYS  = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa']
const MONTHS = ['Januar','Februar','März','April','Mai','Juni','Juli','August','September','Oktober','November','Dezember']

function fmt(d) { return d.toISOString().split('T')[0] }

function getWeek(date) {
  const d = new Date(date)
  const day = d.getDay()
  const mon = new Date(d)
  mon.setDate(d.getDate() - (day === 0 ? 6 : day - 1))
  return Array.from({ length: 7 }, (_, i) => {
    const dd = new Date(mon)
    dd.setDate(mon.getDate() + i)
    return dd
  })
}

export default function App() {
  const [tab, setTab]   = useState('timeline')
  const [date, setDate] = useState(new Date())
  const today = new Date()
  const week  = getWeek(date)

  const shift = (n) => setDate(d => { const nd = new Date(d); nd.setDate(d.getDate() + n); return nd })

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100dvh', maxWidth: 480, margin: '0 auto', background: 'var(--bg)' }}>

      {/* ── Header ── */}
      <div style={{ flexShrink: 0, background: 'var(--bg)', borderBottom: '1px solid var(--border)', padding: '14px 16px 10px' }}>

        {/* Date row */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
          <button onClick={() => shift(-1)} style={navBtn}>‹</button>

          <div style={{ textAlign: 'center' }}>
            <div style={{ fontSize: 18, fontWeight: 700, letterSpacing: '-0.3px' }}>
              {date.getDate()}. {MONTHS[date.getMonth()]} <span style={{ color: 'var(--accent)' }}>{date.getFullYear()}</span>
            </div>
            {fmt(date) === fmt(today)
              ? <div style={{ fontSize: 11, color: 'var(--accent2)', marginTop: 1 }}>Heute</div>
              : <button onClick={() => setDate(new Date())} style={{ fontSize: 11, color: 'var(--text2)', marginTop: 1 }}>→ Heute</button>
            }
          </div>

          <button onClick={() => shift(1)} style={navBtn}>›</button>
        </div>

        {/* Week strip */}
        <div style={{ display: 'flex', gap: 2 }}>
          {week.map((d, i) => {
            const sel     = fmt(d) === fmt(date)
            const isToday = fmt(d) === fmt(today)
            return (
              <button
                key={i}
                onClick={() => setDate(new Date(d))}
                style={{
                  flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
                  padding: '6px 0', borderRadius: 8,
                  background: sel ? 'var(--accent)' : 'transparent',
                  transition: 'background 0.15s',
                }}
              >
                <span style={{ fontSize: 10, color: sel ? 'rgba(255,255,255,0.8)' : 'var(--text2)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
                  {DAYS[d.getDay()]}
                </span>
                <span style={{
                  fontSize: 14, fontWeight: sel || isToday ? 700 : 400,
                  color: sel ? 'white' : isToday ? 'var(--accent)' : 'var(--text)',
                  width: 26, height: 26, display: 'flex', alignItems: 'center', justifyContent: 'center',
                  borderRadius: '50%',
                  border: isToday && !sel ? '2px solid var(--accent)' : 'none',
                }}>
                  {d.getDate()}
                </span>
              </button>
            )
          })}
        </div>
      </div>

      {/* ── Content ── */}
      <div style={{ flex: 1, overflowY: 'auto', overflowX: 'hidden' }}>
        {tab === 'timeline'
          ? <Timeline date={fmt(date)} />
          : <TodoList  date={fmt(date)} />
        }
      </div>

      {/* ── Bottom Nav ── */}
      <div style={{
        display: 'flex', flexShrink: 0,
        background: 'var(--bg2)', borderTop: '1px solid var(--border)',
        padding: '8px 0 max(8px, env(safe-area-inset-bottom))',
      }}>
        {[
          { id: 'timeline', label: 'Tagesplan', icon: '⏱' },
          { id: 'todos',    label: 'To-Dos',    icon: '☑' },
        ].map(t => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            style={{
              flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, padding: '6px 0',
              color: tab === t.id ? 'var(--accent)' : 'var(--text2)',
            }}
          >
            <span style={{ fontSize: 22 }}>{t.icon}</span>
            <span style={{ fontSize: 11, fontWeight: tab === t.id ? 600 : 400 }}>{t.label}</span>
          </button>
        ))}
      </div>

    </div>
  )
}

const navBtn = {
  width: 36, height: 36,
  display: 'flex', alignItems: 'center', justifyContent: 'center',
  borderRadius: 8, background: 'var(--bg3)', color: 'var(--text2)',
  fontSize: 20, fontWeight: 300,
}
