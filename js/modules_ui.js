/* ────────────────────────────────────────────────────────
   Modules UI — render functions for tabs 4–8
   ──────────────────────────────────────────────────────── */

const Modules = {

  // ── Called when any module tab becomes active ──────────
  onTabActivate(tab) {
    if (tab === 'heatpump')   this.renderHP();
    if (tab === 'hydraulics') this.renderHydraulics();
    if (tab === 'radiators')  this.renderRadiators();
    if (tab === 'quote')      this.renderQuote();
    if (tab === 'crm')        this.renderCRM();
  },

  // ── Shared: get current calc result ───────────────────
  getResult() {
    return HLB_CALC.calcProject(state);
  },

  // ════════════════════════════════════════════════════════
  //  TAB 4 — Heat Pump
  // ════════════════════════════════════════════════════════
  renderHP() {
    const result = this.getResult();
    if (!result || result.totalLoad < 100) {
      document.getElementById('hpNoLoad').style.display = 'block';
      document.getElementById('hpContent').style.display = 'none';
      return;
    }
    document.getElementById('hpNoLoad').style.display = 'none';
    document.getElementById('hpContent').style.display = 'block';

    const flowTemp  = parseInt(document.getElementById('hpFlowTemp')?.value || 45);
    const returnTemp = parseInt(document.getElementById('hpReturnTemp')?.value || 35);
    const hwDemand  = parseFloat(document.getElementById('hpHwDemand')?.value || 3);
    const mode      = document.getElementById('hpMode')?.value || 'monoenergetisch';

    HPModule.state = { ...HPModule.state, flowTemp, returnTemp, hwDemand, mode };

    const totalKw = result.totalLoad / 1000;
    const reqKw   = +(totalKw + hwDemand).toFixed(2);

    // Load display
    document.getElementById('hpLoadDisplay').innerHTML = `
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:8px;">
        <div class="climate-stat"><div class="climate-stat-value">${HLB_CALC.fmt(result.totalLoad)}</div><div class="climate-stat-label">Heizlast Gebäude</div></div>
        <div class="climate-stat"><div class="climate-stat-value">${hwDemand} kW</div><div class="climate-stat-label">Warmwasser extra</div></div>
      </div>
      <div class="climate-stat" style="background:var(--primary-light);border:1px solid var(--primary);">
        <div class="climate-stat-value" style="color:var(--primary)">${reqKw} kW</div>
        <div class="climate-stat-label">Gesamtbedarf (Auslegungspunkt)</div>
      </div>
    `;

    // Ranked HP list
    const ranked = HPModule.recommend(result.totalLoad, hwDemand, flowTemp, mode);
    document.getElementById('hpMatchCount').textContent =
      ranked.filter(r => r.covers).length + ' passende Modelle';

    const list = document.getElementById('hpList');
    list.innerHTML = ranked.map(({ hp, scop, jaz, covers, ratio, annualElecKwh }) => {
      const sel = HPModule.state.selectedId === hp.id;
      const energy = jaz >= 4 ? 'A' : jaz >= 3.5 ? 'B' : jaz >= 3 ? 'C' : 'D';
      const barW = Math.min(100, ratio * 100);
      const oversize = ratio > 1.5;
      return `
        <div class="hp-card ${sel ? 'selected' : ''} ${!covers ? 'poor-cover' : ''}"
          onclick="Modules.selectHP('${hp.id}')">
          <div class="hp-card-header">
            <div>
              <div class="hp-card-make">${escUI(hp.make)}</div>
              <div class="hp-card-model">${escUI(hp.model)}</div>
            </div>
            <div class="hp-card-power">${hp.kwMax} kW</div>
          </div>
          <div class="hp-card-stats">
            <div class="hp-stat"><div class="hp-stat-val">${scop.toFixed(1)}</div><div class="hp-stat-lbl">SCOP</div></div>
            <div class="hp-stat"><div class="hp-stat-val">${jaz.toFixed(1)}</div><div class="hp-stat-lbl">JAZ</div></div>
            <div class="hp-stat"><div class="hp-stat-val"><span class="energy-label el-${energy}">${energy}</span></div><div class="hp-stat-lbl">Effizienz</div></div>
            <div class="hp-stat"><div class="hp-stat-val">${annualElecKwh.toLocaleString('de')} kWh</div><div class="hp-stat-lbl">Strom/Jahr</div></div>
          </div>
          <div class="hp-cover-bar">
            <div class="hp-cover-fill ${oversize ? 'over' : ''}" style="width:${Math.min(barW, 100)}%"></div>
          </div>
          <div class="hp-cover-text">
            ${covers ? `✓ Deckt ${(ratio*100).toFixed(0)}% des Bedarfs` : '⚠ Unterdeckung — nur für bivalent geeignet'}
          </div>
        </div>`;
    }).join('');
  },

  selectHP(id) {
    HPModule.state.selectedId = id;
    const hp = PRODUCTS.heatPumps.find(h => h.id === id);
    if (!hp) return;
    this.renderHP();
    this.renderHPDetail(hp);
  },

  renderHPDetail(hp) {
    const result    = this.getResult();
    const flowTemp  = parseInt(document.getElementById('hpFlowTemp')?.value || 45);
    const jaz       = HPModule.calcJAZ(hp, -14, flowTemp);
    const bv        = result ? HPModule.calcBivalentPoint(hp, result.totalLoad, flowTemp, state.project.outdoorTemp, state.project.indoorTemp) : null;
    const { annualHeatKwh, annualElecKwh } = result
      ? HPModule.calcAnnualEnergy(result.totalLoad, jaz)
      : { annualHeatKwh: 0, annualElecKwh: 0 };
    const annualCost = Math.round(annualElecKwh * 0.28); // 28 ct/kWh

    // COP table rows
    const tempPairs = [[7, 35],[2, 35],[-7, 35],[7, 45],[2, 45],[-7, 45],[7, 55],[2, 55],[-7, 55]];
    const copRows = tempPairs.map(([ta, tw]) => {
      const { cop, kw } = HPModule.interpCOP(hp, ta, tw);
      const cls = cop >= 4 ? '' : cop >= 3 ? '' : cop >= 2 ? 'low' : 'very-low';
      return `<tr>
        <td>A${ta}/W${tw}</td>
        <td class="cop-cell ${cls}">${cop.toFixed(2)}</td>
        <td>${kw.toFixed(1)} kW</td>
      </tr>`;
    }).join('');

    document.getElementById('hpDetailBody').innerHTML = `
      <div style="margin-bottom:12px;">
        <div style="font-size:.75rem;color:var(--text-muted);text-transform:uppercase;letter-spacing:.04em;">${escUI(hp.make)}</div>
        <div style="font-size:1rem;font-weight:700;margin:2px 0 8px;">${escUI(hp.model)}</div>
        <div style="display:flex;gap:8px;flex-wrap:wrap;">
          <span class="jaz-badge ${jaz >= 4 ? 'a' : jaz >= 3.5 ? 'b' : jaz >= 3 ? 'c' : 'd'}">JAZ ${jaz.toFixed(1)}</span>
          <span style="font-size:.82rem;background:var(--bg);padding:3px 10px;border-radius:20px;">${hp.kwMin}–${hp.kwMax} kW</span>
          <span style="font-size:.82rem;background:var(--bg);padding:3px 10px;border-radius:20px;">ca. ${escUI(hp.priceHint)}</span>
        </div>
      </div>

      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:12px;">
        <div class="climate-stat"><div class="climate-stat-value">${annualElecKwh.toLocaleString('de')} kWh</div><div class="climate-stat-label">Strom/Jahr</div></div>
        <div class="climate-stat"><div class="climate-stat-value">ca. ${annualCost} €</div><div class="climate-stat-label">Stromkosten/Jahr</div></div>
        <div class="climate-stat"><div class="climate-stat-value">${bv !== null ? bv.toFixed(1) + '°C' : '—'}</div><div class="climate-stat-label">Bivalenzpunkt</div></div>
        <div class="climate-stat"><div class="climate-stat-value">${annualHeatKwh.toLocaleString('de')} kWh</div><div class="climate-stat-label">Wärmebedarf/Jahr</div></div>
      </div>

      <div style="font-size:.82rem;font-weight:700;color:var(--text-muted);text-transform:uppercase;letter-spacing:.04em;margin-bottom:6px;">COP-Kennfeld</div>
      <table class="cop-table">
        <thead><tr><th>Bedingung</th><th>COP</th><th>Leistung</th></tr></thead>
        <tbody>${copRows}</tbody>
      </table>
    `;
  },

  // ════════════════════════════════════════════════════════
  //  TAB 5 — Hydraulics
  // ════════════════════════════════════════════════════════
  renderHydraulics() {
    const result = this.getResult();
    if (!result || result.rooms.length === 0) {
      document.getElementById('hydrNoLoad').style.display = 'block';
      document.getElementById('hydrContent').style.display = 'none';
      return;
    }
    document.getElementById('hydrNoLoad').style.display = 'none';
    document.getElementById('hydrContent').style.display = 'block';

    const flowTemp   = parseFloat(document.getElementById('hydrFlow')?.value || 55);
    const returnTemp = parseFloat(document.getElementById('hydrReturn')?.value || 45);
    const spread     = flowTemp - returnTemp;
    document.getElementById('hydrSpread').textContent = spread.toFixed(0);

    const rows = HydraulicsModule.calcBalancing(state.rooms, result.rooms, flowTemp, returnTemp);
    const totalFlow = rows.reduce((s, r) => s + r.flowLh, 0);
    const totalLoad = rows.reduce((s, r) => s + r.heatingLoad, 0);

    document.getElementById('hydrTableBody').innerHTML = rows.map(r => `
      <tr>
        <td><strong>${escUI(r.roomName)}</strong></td>
        <td>${Math.round(r.heatingLoad)}</td>
        <td>${r.flowLh.toFixed(1)}</td>
        <td>
          <div style="display:flex;align-items:center;gap:6px;">
            <div style="width:${Math.round(r.flowPct)}px;max-width:80px;height:5px;background:var(--primary);border-radius:3px;"></div>
            ${r.flowPct.toFixed(1)}%
          </div>
        </td>
        <td>${r.kv.toFixed(3)}</td>
        <td><span class="presetting-badge ${r.presetting >= 6.5 ? 'high' : ''}">${r.presetting.toFixed(1)}</span></td>
        <td style="font-size:.8rem;color:var(--warning)">${r.note}</td>
      </tr>`).join('');

    document.getElementById('hydrTableFoot').innerHTML = `
      <tr>
        <td><strong>Gesamt</strong></td>
        <td><strong>${Math.round(totalLoad)}</strong></td>
        <td><strong>${totalFlow.toFixed(1)} L/h</strong></td>
        <td colspan="4"></td>
      </tr>`;
  },

  printHydraulics() {
    const result = this.getResult();
    const flowTemp   = document.getElementById('hydrFlow')?.value || 55;
    const returnTemp = document.getElementById('hydrReturn')?.value || 45;
    const rows = HydraulicsModule.calcBalancing(state.rooms, result?.rooms || [], +flowTemp, +returnTemp);

    const w = window.open('', '_blank');
    w.document.write(`<!DOCTYPE html><html lang="de"><head><meta charset="UTF-8">
    <title>Hydraulischer Abgleich – ${escUI(state.project.name)}</title>
    <style>
      body{font-family:sans-serif;font-size:12px;padding:20mm;color:#222}
      h1{font-size:18px;color:#0057B8;margin-bottom:4px}
      h2{font-size:13px;color:#444;margin-bottom:12px;border-bottom:2px solid #0057B8;padding-bottom:4px}
      table{width:100%;border-collapse:collapse;font-size:11px}
      th{background:#0057B8;color:#fff;padding:7px 10px;text-align:left}
      td{padding:7px 10px;border-bottom:1px solid #e9ecef}
      .badge{display:inline-block;background:#e8f2ff;color:#0057B8;font-weight:700;padding:1px 8px;border-radius:20px}
      @media print{body{padding:10mm}}
    </style></head><body>
    <h1>Hydraulischer Abgleich – Methode B</h1>
    <p>Projekt: <strong>${escUI(state.project.name)}</strong> · Standort: ${escUI(state.project.city)} · VL/RL: ${flowTemp}/${returnTemp}°C · Datum: ${new Date().toLocaleDateString('de-DE')}</p>
    <h2>Voreinstellungen je Raum</h2>
    <table>
      <thead><tr><th>Raum</th><th>Heizlast W</th><th>Volumenstrom L/h</th><th>Kv-Wert</th><th>Voreinstellung N</th><th>Hinweis</th></tr></thead>
      <tbody>${rows.map(r => `<tr><td>${escUI(r.roomName)}</td><td>${Math.round(r.heatingLoad)}</td><td>${r.flowLh.toFixed(1)}</td><td>${r.kv.toFixed(3)}</td><td><span class="badge">${r.presetting.toFixed(1)}</span></td><td>${r.note}</td></tr>`).join('')}</tbody>
    </table>
    <p style="margin-top:20px;font-size:10px;color:#666;">Berechnet mit HeizlastProfi nach DIN EN 12831 · Hydraulischer Abgleich nach VDI 2070 Methode B</p>
    </body></html>`);
    w.document.close();
    w.print();
  },

  // ════════════════════════════════════════════════════════
  //  TAB 6 — Radiators
  // ════════════════════════════════════════════════════════
  renderRadiators() {
    const result = this.getResult();
    if (!result || result.rooms.length === 0) {
      document.getElementById('radNoLoad').style.display = 'block';
      document.getElementById('radContent').style.display = 'none';
      return;
    }
    document.getElementById('radNoLoad').style.display = 'none';
    document.getElementById('radContent').style.display = 'block';

    const nomFlow   = parseFloat(document.getElementById('radNomFlow')?.value   || 75);
    const nomReturn = parseFloat(document.getElementById('radNomReturn')?.value || 65);
    const newFlow   = parseFloat(document.getElementById('radNewFlow')?.value   || 45);
    const newReturn = parseFloat(document.getElementById('radNewReturn')?.value || 35);

    const cfGlobal = RadiatorModule.correctionFactor(newFlow, newReturn, 20, nomFlow, nomReturn, 20, 1.33);
    document.getElementById('radCfDisplay').innerHTML =
      `Korrekturfaktor: <strong>${(cfGlobal * 100).toFixed(0)}%</strong> bei ${newFlow}/${newReturn}°C vs. ${nomFlow}/${nomReturn}°C`;

    const assessment = RadiatorModule.assessRooms(result.rooms, newFlow, newReturn, nomFlow, nomReturn);

    document.getElementById('radTableBody').innerHTML = assessment.map(r => {
      const barPct = Math.min(100, r.cfPct);
      const barCls = r.cfPct >= 70 ? '' : r.cfPct >= 50 ? 'warn' : 'bad';
      return `
        <tr>
          <td><strong>${escUI(r.roomName)}</strong></td>
          <td>${Math.round(r.heatingLoad)}</td>
          <td>
            <div class="cf-bar"><div class="cf-fill ${barCls}" style="width:${barPct}%"></div></div>
            ${r.cfPct}%
          </td>
          <td>${r.reqNomW.toLocaleString('de')}</td>
          <td>${r.recSize}</td>
          <td><span class="status-badge ${r.status}">${r.statusText}</span></td>
        </tr>`;
    }).join('');
  },

  // ════════════════════════════════════════════════════════
  //  TAB 7 — Quote
  // ════════════════════════════════════════════════════════
  _quoteItems: [],

  renderQuote() {
    if (this._quoteItems.length === 0) {
      this._quoteItems = [
        QuoteModule.newItem('Wärmepumpe Luft/Wasser inkl. Innenmodul', 1, 'Stk.', 12000),
        QuoteModule.newItem('Pufferspeicher 200L', 1, 'Stk.', 800),
        QuoteModule.newItem('Warmwasserspeicher 300L', 1, 'Stk.', 900),
        QuoteModule.newItem('Montage und Inbetriebnahme', 1, 'Pausch.', 3500),
        QuoteModule.newItem('Hydraulischer Abgleich', 1, 'Pausch.', 500),
      ];
    }
    this._renderQuoteItems();
    this._renderQuoteTotals();

    // Set today's date
    const dateEl = document.getElementById('qDate');
    if (dateEl && !dateEl.value) dateEl.value = new Date().toISOString().split('T')[0];
    const validEl = document.getElementById('qValidUntil');
    if (validEl && !validEl.value) {
      const d = new Date(); d.setDate(d.getDate() + 30);
      validEl.value = d.toISOString().split('T')[0];
    }
  },

  _renderQuoteItems() {
    document.getElementById('quoteItemsBody').innerHTML = this._quoteItems.map((item, i) => `
      <tr>
        <td><input type="text"   value="${escUI(item.desc)}"  onchange="Modules._updateItem(${i},'desc',this.value)"></td>
        <td><input type="number" value="${item.qty}"           onchange="Modules._updateItem(${i},'qty',+this.value)" style="width:60px;text-align:center"></td>
        <td><input type="text"   value="${escUI(item.unit)}"  onchange="Modules._updateItem(${i},'unit',this.value)" style="width:60px;text-align:center"></td>
        <td><input type="number" value="${item.price}"         onchange="Modules._updateItem(${i},'price',+this.value)" style="width:90px;text-align:right"></td>
        <td style="text-align:right;font-weight:700">${fmtEuro(item.qty * item.price)}</td>
        <td><button class="item-del" onclick="Modules._deleteItem(${i})">×</button></td>
      </tr>`).join('');
    this._renderQuoteTotals();
  },

  _updateItem(i, key, val) {
    this._quoteItems[i][key] = val;
    this._renderQuoteTotals();
  },

  _deleteItem(i) {
    this._quoteItems.splice(i, 1);
    this._renderQuoteItems();
  },

  addQuoteItem() {
    this._quoteItems.push(QuoteModule.newItem('', 1, 'Stk.', 0));
    this._renderQuoteItems();
  },

  _renderQuoteTotals() {
    QuoteModule.state.items = this._quoteItems;
    const vat = parseFloat(document.getElementById('qVat')?.value || 19);
    QuoteModule.state.vatPct = vat;
    const t = QuoteModule.calcTotals();
    document.getElementById('quoteTotals').innerHTML = `
      <div class="quote-total-row"><span>Nettobetrag</span><span>${fmtEuro(t.net)}</span></div>
      <div class="quote-total-row"><span>MwSt. ${vat}%</span><span>${fmtEuro(t.vat)}</span></div>
      <div class="quote-total-row gross"><span>Gesamtbetrag</span><span>${fmtEuro(t.gross)}</span></div>
    `;
  },

  prefillQuoteFromProject() {
    const result = this.getResult();
    if (!result) return;
    const hp = HPModule.state.selectedId
      ? PRODUCTS.heatPumps.find(h => h.id === HPModule.state.selectedId)
      : null;
    if (hp) {
      this._quoteItems[0] = QuoteModule.newItem(
        `${hp.make} ${hp.model} (${hp.kwMax} kW)`, 1, 'Stk.',
        parseFloat(hp.priceHint.split('–')[0].replace(/\D/g,'')) || 12000
      );
    }
    this._renderQuoteItems();
    App.toast('Positionen aus Projekt befüllt', 'success');
  },

  exportQuotePDF() {
    const result = this.getResult();
    const hp = HPModule.state.selectedId
      ? PRODUCTS.heatPumps.find(h => h.id === HPModule.state.selectedId)
      : null;

    // Sync quote state
    const s = QuoteModule.state;
    s.company.name   = document.getElementById('qCompName')?.value  || '';
    s.company.street = document.getElementById('qCompStreet')?.value || '';
    s.company.city   = document.getElementById('qCompCity')?.value   || '';
    s.company.phone  = document.getElementById('qCompPhone')?.value  || '';
    s.company.email  = document.getElementById('qCompEmail')?.value  || '';
    s.customer.name  = document.getElementById('qCustName')?.value   || '';
    s.customer.street = document.getElementById('qCustStreet')?.value || '';
    s.customer.city  = document.getElementById('qCustCity')?.value   || '';
    s.quoteNo        = document.getElementById('qNo')?.value         || '';
    s.quoteDate      = document.getElementById('qDate')?.value       || '';
    s.validUntil     = document.getElementById('qValidUntil')?.value || '';
    s.notes          = document.getElementById('qNotes')?.value      || '';
    s.includeKfw     = document.getElementById('qKfw')?.checked      ?? true;
    s.items          = this._quoteItems;
    s.vatPct         = parseFloat(document.getElementById('qVat')?.value || 19);

    const heatingLoad = result ? HLB_CALC.fmt(result.totalLoad) : '—';
    const hpName      = hp ? `${hp.make} ${hp.model}` : '—';
    const html        = QuoteModule.generateHTML(state.project.name, heatingLoad, hpName);

    const w = window.open('', '_blank');
    w.document.write(html);
    w.document.close();
    setTimeout(() => w.print(), 400);
  },

  // ════════════════════════════════════════════════════════
  //  TAB 8 — CRM
  // ════════════════════════════════════════════════════════
  _selectedCustomerId: null,

  renderCRM() {
    const customers = CRMModule.loadCustomers();
    const listEl = document.getElementById('crmCustomerList');

    if (customers.length === 0) {
      listEl.innerHTML = `<div style="padding:20px;text-align:center;color:var(--text-muted);font-size:.85rem;">
        Noch keine Kunden angelegt.</div>`;
      return;
    }

    listEl.innerHTML = customers.map(c => `
      <div class="customer-card ${c.id === this._selectedCustomerId ? 'active' : ''}"
        onclick="Modules.selectCustomer('${c.id}')">
        <span class="customer-badge">${(c.projects || []).length} Proj.</span>
        <div class="customer-name">${escUI(c.name)}</div>
        <div class="customer-sub">${escUI(c.city || '')} · ${escUI(c.phone || '')}</div>
      </div>`).join('');

    if (this._selectedCustomerId) this.selectCustomer(this._selectedCustomerId);
  },

  selectCustomer(id) {
    this._selectedCustomerId = id;
    const c = CRMModule.getCustomer(id);
    if (!c) return;

    document.querySelector('.crm-layout .customer-card.active')?.classList.remove('active');
    document.querySelectorAll('.customer-card').forEach(el => {
      el.classList.toggle('active', el.onclick.toString().includes(id));
    });
    this.renderCRM();

    document.getElementById('crmDetailEmpty').style.display   = 'none';
    document.getElementById('crmDetailContent').style.display = 'block';
    document.getElementById('crmDetailHeader').textContent    = c.name;

    document.getElementById('crmDetailBody').innerHTML = `
      <div class="form-row" style="margin-bottom:12px;">
        <div class="form-group"><label>Name</label><input type="text" id="cEdit_name"   value="${escUI(c.name   || '')}" onchange="Modules._updateCustomer('${id}','name',this.value)"></div>
        <div class="form-group"><label>Telefon</label><input type="text" id="cEdit_phone" value="${escUI(c.phone || '')}" onchange="Modules._updateCustomer('${id}','phone',this.value)"></div>
      </div>
      <div class="form-row" style="margin-bottom:12px;">
        <div class="form-group"><label>Straße</label><input type="text" id="cEdit_street" value="${escUI(c.street || '')}" onchange="Modules._updateCustomer('${id}','street',this.value)"></div>
        <div class="form-group"><label>Ort</label><input type="text" id="cEdit_city" value="${escUI(c.city   || '')}" onchange="Modules._updateCustomer('${id}','city',this.value)"></div>
      </div>
      <div class="form-group" style="margin-bottom:16px;"><label>E-Mail</label><input type="text" id="cEdit_email" value="${escUI(c.email || '')}" onchange="Modules._updateCustomer('${id}','email',this.value)"></div>
      <div style="display:flex;gap:8px;margin-top:8px;">
        <button class="btn btn-outline btn-sm" onclick="Modules.linkProjectToCustomer('${id}')">📁 Aktuelles Projekt zuweisen</button>
        <button class="btn btn-danger btn-sm" onclick="Modules.deleteCustomer('${id}')">Löschen</button>
      </div>
      ${(c.projects || []).length > 0 ? `
        <div style="margin-top:16px;"><strong>Zugewiesene Projekte</strong>
          <ul style="margin-top:8px;padding-left:16px;font-size:.88rem;color:var(--text-muted);">
            ${c.projects.map(p => `<li>${escUI(p)}</li>`).join('')}
          </ul>
        </div>` : ''}
    `;
  },

  _updateCustomer(id, key, val) {
    CRMModule.updateCustomer(id, { [key]: val });
    document.getElementById('crmDetailHeader').textContent =
      CRMModule.getCustomer(id)?.name || '';
    this.renderCRM();
  },

  addCustomer() {
    const c = CRMModule.addCustomer({ name: 'Neuer Kunde', phone: '', email: '', street: '', city: '' });
    this._selectedCustomerId = c.id;
    this.renderCRM();
  },

  deleteCustomer(id) {
    CRMModule.deleteCustomer(id);
    this._selectedCustomerId = null;
    document.getElementById('crmDetailEmpty').style.display   = 'flex';
    document.getElementById('crmDetailContent').style.display = 'none';
    this.renderCRM();
  },

  linkProjectToCustomer(id) {
    const c = CRMModule.getCustomer(id);
    if (!c) return;
    const name = state.project.name;
    const projs = c.projects || [];
    if (!projs.includes(name)) {
      CRMModule.updateCustomer(id, { projects: [...projs, name] });
      this.renderCRM();
      App.toast(`Projekt „${name}" verknüpft`, 'success');
    }
  },
};

// ── Utility ──────────────────────────────────────────────
function escUI(s) {
  return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
