/* ────────────────────────────────────────────────────────
   HeizlastProfi — Erweiterungsmodule
   4. Wärmepumpen-Auslegung
   5. Hydraulischer Abgleich (Method B)
   6. Heizkörper-Auslegung
   7. Angebot
   8. Kundenverwaltung (CRM)
   ──────────────────────────────────────────────────────── */

// ════════════════════════════════════════════════════════
//  4. WÄRMEPUMPEN-AUSLEGUNG
// ════════════════════════════════════════════════════════
const HPModule = {
  state: {
    mode: 'monovalent',      // monovalent | bivalent | monoenergetisch
    flowTemp: 45,
    returnTemp: 35,
    hwDemand: 3.0,           // kW hot-water extra demand
    selectedId: null,
    bivalentPoint: -5,       // °C outdoor temp where backup kicks in
    filter: { maxKw: 0, minScop: 0 },
  },

  // Interpolate COP at given outdoor/flow temp
  interpCOP(hp, ta, tw) {
    const pts = hp.perf.filter(p => p.tw === tw);
    if (pts.length === 0) {
      // Find nearest flow temp
      const tws = [...new Set(hp.perf.map(p => p.tw))].sort((a,b) => a-b);
      const closestTw = tws.reduce((a,b) => Math.abs(b-tw) < Math.abs(a-tw) ? b : a);
      return this.interpCOP(hp, ta, closestTw);
    }
    pts.sort((a,b) => a.ta - b.ta);
    if (ta <= pts[0].ta)  return { cop: pts[0].cop, kw: pts[0].kw };
    if (ta >= pts[pts.length-1].ta) return { cop: pts[pts.length-1].cop, kw: pts[pts.length-1].kw };
    for (let i = 0; i < pts.length - 1; i++) {
      if (ta >= pts[i].ta && ta <= pts[i+1].ta) {
        const t = (ta - pts[i].ta) / (pts[i+1].ta - pts[i].ta);
        return {
          cop: pts[i].cop + t * (pts[i+1].cop - pts[i].cop),
          kw:  pts[i].kw  + t * (pts[i+1].kw  - pts[i].kw),
        };
      }
    }
    return { cop: 0, kw: 0 };
  },

  // Simplified JAZ after VDI 4650 part 1 (space heating)
  calcJAZ(hp, outdoorTemp, flowTemp) {
    // Map SCOP to JAZ with correction for design conditions
    // JAZ ≈ SCOP × 1.0 for well-insulated, slightly lower for older buildings
    const scop = flowTemp <= 35 ? hp.scop35
               : flowTemp <= 45 ? hp.scop45
               : hp.scop55;
    // Correction factor for bivalent operation (more backup → lower JAZ)
    const bvCorr = this.state.mode === 'monovalent' ? 1.0
                 : this.state.mode === 'monoenergetisch' ? 0.97
                 : 0.93;
    return +(scop * bvCorr).toFixed(2);
  },

  // Bivalent point: outdoor temp where HP output = building demand
  calcBivalentPoint(hp, heatingLoad_W, flowTemp, outdoorDesign, indoorTemp) {
    // Heat load is proportional to (θi - θe)
    const maxDt = indoorTemp - outdoorDesign;
    // Search for ta where hp.kw at that ta < required load
    for (let ta = 15; ta >= -20; ta -= 0.5) {
      const dt = indoorTemp - ta;
      const requiredKw = (heatingLoad_W / 1000) * dt / maxDt;
      const { kw } = this.interpCOP(hp, ta, flowTemp);
      if (kw < requiredKw) return ta + 0.5;
    }
    return -20; // fully covers
  },

  // Annual energy estimate (kWh)
  calcAnnualEnergy(heatingLoad_W, jaz) {
    // VDI 4655: approx 2000 full-load hours for heating in Germany
    const fullLoadHours = 1800;
    const annualHeatKwh = (heatingLoad_W / 1000) * fullLoadHours;
    return { annualHeatKwh, annualElecKwh: +(annualHeatKwh / jaz).toFixed(0) };
  },

  // Filter and rank heat pumps for given load
  recommend(heatingLoad_W, hwDemand_kW, flowTemp, mode) {
    const totalLoad = heatingLoad_W / 1000 + hwDemand_kW;
    return PRODUCTS.heatPumps
      .map(hp => {
        const { cop, kw } = this.interpCOP(hp, 2, flowTemp); // A2/W35 or A2/W45
        const jaz = this.calcJAZ(hp, -14, flowTemp);
        const covers = hp.kwMax >= totalLoad;
        const ratio  = hp.kwMax / totalLoad;
        const scop   = flowTemp <= 35 ? hp.scop35 : flowTemp <= 45 ? hp.scop45 : hp.scop55;
        const { annualHeatKwh, annualElecKwh } = this.calcAnnualEnergy(heatingLoad_W, jaz);
        return { hp, cop, kw, jaz, scop, covers, ratio, annualElecKwh, annualHeatKwh };
      })
      .sort((a, b) => {
        // Sort: covers first, then best SCOP
        if (a.covers && !b.covers) return -1;
        if (!a.covers && b.covers) return  1;
        return b.scop - a.scop;
      });
  },
};

// ════════════════════════════════════════════════════════
//  5. HYDRAULISCHER ABGLEICH (Methode B nach VDI 2070)
// ════════════════════════════════════════════════════════
const HydraulicsModule = {
  state: {
    flowTemp:   55,
    returnTemp: 45,
    systemDp:   150,  // Pa/m pressure drop per circuit meter
    circulators: [],
  },

  // Required volume flow per room [L/h]
  // V̇ = Q / (c_p × ρ × Δθ) where c_p × ρ = 1.163 Wh/(L·K)
  calcFlow(heatLoad_W, flowTemp, returnTemp) {
    const dt = flowTemp - returnTemp;
    if (dt <= 0) return 0;
    return +(heatLoad_W / (1.163 * dt)).toFixed(1);
  },

  // Danfoss RTD-N presetting table (simplified)
  // Returns presetting N (1.0 to 7.0) for given Kv
  kvToPresetting(kv) {
    // Danfoss RTD-N: Kv from presetting
    const table = [
      { n: 1.0, kv: 0.07 },
      { n: 1.5, kv: 0.10 },
      { n: 2.0, kv: 0.15 },
      { n: 2.5, kv: 0.22 },
      { n: 3.0, kv: 0.32 },
      { n: 3.5, kv: 0.46 },
      { n: 4.0, kv: 0.62 },
      { n: 4.5, kv: 0.82 },
      { n: 5.0, kv: 1.10 },
      { n: 5.5, kv: 1.40 },
      { n: 6.0, kv: 1.80 },
      { n: 6.5, kv: 2.20 },
      { n: 7.0, kv: 2.70 },
    ];
    let best = table[table.length - 1];
    for (const row of table) {
      if (kv <= row.kv) { best = row; break; }
    }
    return best.n;
  },

  // Kv = V̇ [m³/h] / sqrt(ΔP [bar])
  // For Methode B: available Δp at valve ≈ 50-100 Pa → assumed 50 Pa
  calcKv(flow_Lh, availableDp_Pa) {
    const flow_m3h  = flow_Lh / 1000;
    const dp_bar    = availableDp_Pa / 100000;
    if (dp_bar <= 0 || flow_m3h <= 0) return 0;
    return +(flow_m3h / Math.sqrt(dp_bar)).toFixed(3);
  },

  // Full hydraulic balancing for all rooms
  calcBalancing(rooms, roomResults, flowTemp, returnTemp) {
    const dt       = flowTemp - returnTemp;
    const totalLoad = roomResults.reduce((s, r) => s + r.total, 0);
    const totalFlow = totalLoad > 0 ? this.calcFlow(totalLoad, flowTemp, returnTemp) : 0;

    // Available Δp at each valve (simplified: 50 Pa uniform)
    const valveDp = 50;

    return roomResults.map((rr, i) => {
      const room     = rooms.find(r => r.id === rr.id);
      const flow     = this.calcFlow(rr.total, flowTemp, returnTemp);
      const kv       = this.calcKv(flow, valveDp);
      const presetting = this.kvToPresetting(kv);
      const flowPct  = totalFlow > 0 ? +(flow / totalFlow * 100).toFixed(1) : 0;
      return {
        roomId:    rr.id,
        roomName:  rr.name,
        heatingLoad: rr.total,
        flowLh:    flow,
        flowPct,
        kv,
        presetting,
        valveDp,
        note: presetting >= 7.0 ? '⚠ Max-Voreinstellung — evtl. Heizkreis teilen' : '',
      };
    });
  },
};

// ════════════════════════════════════════════════════════
//  6. HEIZKÖRPER-AUSLEGUNG
// ════════════════════════════════════════════════════════
const RadiatorModule = {
  state: {
    nomFlowTemp:   75,   // Nominal conditions for radiator rating
    nomReturnTemp: 65,
    nomRoomTemp:   20,
    newFlowTemp:   45,   // Target operating temps (heat pump)
    newReturnTemp: 35,
    radiatorType:  'conv_22',
  },

  // Logarithmic mean temperature difference
  lmtd(flowTemp, returnTemp, roomTemp) {
    const dt1 = flowTemp  - roomTemp;
    const dt2 = returnTemp - roomTemp;
    if (dt1 <= 0 || dt2 <= 0 || dt1 === dt2) return (dt1 + dt2) / 2;
    return (dt1 - dt2) / Math.log(dt1 / dt2);
  },

  // Correction factor: ratio of actual to nominal output
  correctionFactor(newFlow, newReturn, roomTemp, nomFlow, nomReturn, nomRoom, n) {
    const lmtdNew = this.lmtd(newFlow, newReturn, roomTemp);
    const lmtdNom = this.lmtd(nomFlow, nomReturn, nomRoom);
    if (lmtdNom <= 0) return 1;
    return Math.pow(lmtdNew / lmtdNom, n);
  },

  // Required nominal radiator power [W] for given room load at new temps
  requiredNominalPower(roomLoad_W, newFlow, newReturn, roomTemp, nomFlow, nomReturn, nomRoom, n) {
    const cf = this.correctionFactor(newFlow, newReturn, roomTemp, nomFlow, nomReturn, nomRoom, n);
    if (cf <= 0) return Infinity;
    return +(roomLoad_W / cf).toFixed(0);
  },

  // Find smallest radiator in PRODUCTS table that covers required power
  findRadiator(requiredW, preferHeightMm) {
    const candidates = PRODUCTS.radiatorSizes.filter(r =>
      r.w75 >= requiredW && (preferHeightMm === 0 || r.h === preferHeightMm)
    );
    if (candidates.length === 0) {
      return PRODUCTS.radiatorSizes.filter(r => r.w75 >= requiredW)
        .sort((a, b) => a.w75 - b.w75)[0] || null;
    }
    return candidates.sort((a, b) => a.w75 - b.w75)[0];
  },

  // Assess all rooms
  assessRooms(roomResults, newFlow, newReturn, nomFlow, nomReturn) {
    const rtDef = PRODUCTS.radiatorTypes.find(r => r.id === 'conv_22');
    const n = rtDef?.n || 1.33;

    return roomResults.map(rr => {
      const roomTemp = 20; // use per-room temp if available
      const cf     = this.correctionFactor(newFlow, newReturn, roomTemp, nomFlow, nomReturn, 20, n);
      const reqNom = +(rr.total / cf).toFixed(0);
      const rec    = this.findRadiator(reqNom, 600);

      let status = 'ok', statusText = 'Ausreichend';
      if (cf < 0.5)  { status = 'danger';  statusText = 'Zu klein – Tausch nötig'; }
      else if (cf < 0.7) { status = 'warning'; statusText = 'Ggf. vergrößern'; }

      return {
        roomId:      rr.id,
        roomName:    rr.name,
        heatingLoad: rr.total,
        cf:          +cf.toFixed(3),
        cfPct:       +(cf * 100).toFixed(0),
        reqNomW:     reqNom,
        recSize:     rec ? `${rec.h}×${rec.l} mm (${rec.w75} W)` : '→ Sondermaß',
        status,
        statusText,
      };
    });
  },
};

// ════════════════════════════════════════════════════════
//  7. ANGEBOT
// ════════════════════════════════════════════════════════
const QuoteModule = {
  state: {
    company: { name: '', street: '', city: '', phone: '', email: '', logo: '' },
    customer: { name: '', street: '', city: '', phone: '', email: '' },
    quoteNo: '',
    quoteDate: new Date().toLocaleDateString('de-DE'),
    validUntil: '',
    items: [],
    notes: '',
    vatPct: 19,
    includeKfw: true,
  },

  newItem(desc = '', qty = 1, unit = 'Stk.', price = 0) {
    return { id: 'qi_' + Date.now(), desc, qty, unit, price };
  },

  calcTotals() {
    const net = this.state.items.reduce((s, i) => s + i.qty * i.price, 0);
    const vat = net * this.state.vatPct / 100;
    return { net, vat, gross: net + vat };
  },

  // Generate print-ready HTML
  generateHTML(projectName, heatingLoad, heatPumpName) {
    const s = this.state;
    const t = this.calcTotals();

    const itemRows = s.items.map(i => `
      <tr>
        <td>${esc(i.desc)}</td>
        <td style="text-align:center">${i.qty}</td>
        <td style="text-align:center">${esc(i.unit)}</td>
        <td style="text-align:right">${fmtEuro(i.price)}</td>
        <td style="text-align:right"><strong>${fmtEuro(i.qty * i.price)}</strong></td>
      </tr>`).join('');

    const kfwBlock = s.includeKfw ? `
      <div class="quote-section">
        <h3>Fördermittel-Hinweis (BEG / KfW)</h3>
        <p>Für den Einbau dieser Wärmepumpe können Bundesförderung für effiziente Gebäude (BEG) nach BAFA/KfW beantragt werden.
        Grundlage: Hydraulischer Abgleich nach Methode B sowie Heizlastberechnung nach DIN EN 12831 liegen vor.
        Förderquote bis zu 70 % der förderfähigen Kosten möglich (Basis-35 % + Effizienzbonus + ggf. Einkommensbonus).</p>
      </div>` : '';

    return `<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<title>Angebot ${esc(s.quoteNo)} – ${esc(s.company.name)}</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:12px;color:#222;padding:20mm}
  h1{font-size:22px;color:#0057B8;margin-bottom:4px}
  h2{font-size:14px;color:#444;margin-bottom:12px;border-bottom:2px solid #0057B8;padding-bottom:4px}
  h3{font-size:12px;color:#0057B8;margin-bottom:6px}
  .header-grid{display:flex;justify-content:space-between;margin-bottom:24px}
  .company-block{flex:1}
  .company-name{font-size:16px;font-weight:700;color:#0057B8}
  .quote-meta{text-align:right;font-size:11px;color:#666}
  .quote-meta strong{font-size:14px;color:#222;display:block;margin-bottom:4px}
  .addresses{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:24px}
  .address-box{background:#f8f9fa;border:1px solid #dee2e6;border-radius:6px;padding:12px}
  .address-label{font-size:10px;font-weight:700;text-transform:uppercase;color:#6c757d;margin-bottom:6px;letter-spacing:.04em}
  table{width:100%;border-collapse:collapse;margin:12px 0}
  th{background:#0057B8;color:#fff;padding:8px 12px;text-align:left;font-size:11px;text-transform:uppercase;letter-spacing:.03em}
  td{padding:8px 12px;border-bottom:1px solid #e9ecef}
  tr:last-child td{border-bottom:none}
  .total-box{margin-top:16px;text-align:right}
  .total-row{display:flex;justify-content:flex-end;gap:40px;padding:4px 0}
  .total-row.gross{font-size:16px;font-weight:700;color:#0057B8;border-top:2px solid #0057B8;padding-top:8px;margin-top:4px}
  .quote-section{margin-top:20px;padding:12px;background:#e8f2ff;border-left:4px solid #0057B8;border-radius:0 6px 6px 0}
  .quote-section p{font-size:11px;color:#444;line-height:1.6;margin-top:6px}
  .project-badges{display:flex;gap:8px;margin-bottom:16px;flex-wrap:wrap}
  .badge{display:inline-block;padding:3px 10px;border-radius:20px;font-size:10px;font-weight:700;background:#e8f2ff;color:#0057B8;border:1px solid rgba(0,87,184,.2)}
  .footer{margin-top:32px;padding-top:12px;border-top:1px solid #dee2e6;font-size:10px;color:#6c757d;text-align:center}
  @media print{body{padding:10mm}}
</style>
</head>
<body>

<div class="header-grid">
  <div class="company-block">
    <div class="company-name">${esc(s.company.name) || 'Ihr Unternehmen'}</div>
    <div>${esc(s.company.street)}</div>
    <div>${esc(s.company.city)}</div>
    <div>${esc(s.company.phone)}</div>
    <div>${esc(s.company.email)}</div>
  </div>
  <div class="quote-meta">
    <strong>Angebot</strong>
    Angebots-Nr.: ${esc(s.quoteNo)}<br>
    Datum: ${esc(s.quoteDate)}<br>
    Gültig bis: ${esc(s.validUntil)}<br>
    Projekt: ${esc(projectName)}
  </div>
</div>

<div class="addresses">
  <div class="address-box">
    <div class="address-label">Kunde</div>
    <strong>${esc(s.customer.name)}</strong><br>
    ${esc(s.customer.street)}<br>
    ${esc(s.customer.city)}
  </div>
  <div class="address-box">
    <div class="address-label">Technische Kenndaten</div>
    Heizlast: <strong>${heatingLoad || '—'}</strong><br>
    Wärmepumpe: <strong>${heatPumpName || '—'}</strong>
  </div>
</div>

<div class="project-badges">
  <span class="badge">Heizlastberechnung DIN EN 12831</span>
  <span class="badge">Hydraulischer Abgleich Methode B</span>
  ${s.includeKfw ? '<span class="badge">BEG-Förderung möglich</span>' : ''}
</div>

<h2>Positionen</h2>
<table>
  <thead>
    <tr><th>Bezeichnung</th><th style="text-align:center">Menge</th><th style="text-align:center">Einh.</th><th style="text-align:right">E-Preis</th><th style="text-align:right">Gesamt</th></tr>
  </thead>
  <tbody>${itemRows}</tbody>
</table>

<div class="total-box">
  <div class="total-row"><span>Nettobetrag:</span><span>${fmtEuro(t.net)}</span></div>
  <div class="total-row"><span>MwSt. ${s.vatPct}%:</span><span>${fmtEuro(t.vat)}</span></div>
  <div class="total-row gross"><span>Gesamtbetrag:</span><span>${fmtEuro(t.gross)}</span></div>
</div>

${s.notes ? `<div class="quote-section"><h3>Hinweise</h3><p>${esc(s.notes).replace(/\n/g,'<br>')}</p></div>` : ''}

${kfwBlock}

<div class="footer">
  ${esc(s.company.name)} · ${esc(s.company.street)} · ${esc(s.company.city)} · ${esc(s.company.phone)} · ${esc(s.company.email)}
</div>
</body></html>`;
  },
};

// ════════════════════════════════════════════════════════
//  8. KUNDENVERWALTUNG (CRM)
// ════════════════════════════════════════════════════════
const CRMModule = {
  loadCustomers() {
    try { return JSON.parse(localStorage.getItem('hlb_customers') || '[]'); } catch { return []; }
  },

  saveCustomers(list) {
    localStorage.setItem('hlb_customers', JSON.stringify(list));
  },

  addCustomer(data) {
    const list = this.loadCustomers();
    const c = { id: 'cust_' + Date.now(), createdAt: new Date().toISOString(), projects: [], ...data };
    list.push(c);
    this.saveCustomers(list);
    return c;
  },

  updateCustomer(id, data) {
    const list = this.loadCustomers();
    const i = list.findIndex(c => c.id === id);
    if (i >= 0) { list[i] = { ...list[i], ...data }; this.saveCustomers(list); }
  },

  deleteCustomer(id) {
    this.saveCustomers(this.loadCustomers().filter(c => c.id !== id));
  },

  getCustomer(id) {
    return this.loadCustomers().find(c => c.id === id);
  },
};

// ── Shared helpers ──────────────────────────────────────
function fmtEuro(n) {
  return new Intl.NumberFormat('de-DE', { style: 'currency', currency: 'EUR' }).format(n);
}

function esc(s) {
  return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
