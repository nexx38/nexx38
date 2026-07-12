/* ────────────────────────────────────────────────────────
   HeizlastProfi — Application Logic
   ──────────────────────────────────────────────────────── */

let chart = null;

// ── State ────────────────────────────────────────────────
const state = {
  project: {
    name:            'Mein Projekt',
    city:            'Berlin',
    outdoorTemp:     -14,
    buildingType:    'residential',
    constructionYear: 2000,
    indoorTemp:      20,
    thermalBridges:  5,
    heatingSystem:   'radiator',
  },
  rooms: [],
  circuits: [],           // [{ id, name, type: 'radiator'|'underfloor' }]
  selectedRoomId: null,
  _editingCompId: null,
};

// Expose on window so other modules (scanner.js) can read the live project
// state. `const state` is a lexical binding, NOT a window property, so
// `window.state` would otherwise be undefined and scanner U-value lookups
// would silently fall back to their default construction year.
window.state = state;

let _idCounter = 1;
let _roomCounter = 0;
const newId = () => 'id_' + (_idCounter++);

// ── Room type emoji map ──────────────────────────────────
const roomEmoji = {
  living: '🛋️', dining: '🍽️', bedroom: '🛏️', kids: '🧸',
  bath: '🚿', kitchen: '🍳', office: '💻', hallway: '🚪',
  toilet: '🚽', cellar: '🏚️', utility: '🔧', other: '🏠',
};

// ── App ──────────────────────────────────────────────────
const App = {
  _newId() { return newId(); },
  init() {
    // Auto-load last session
    this._autoLoad();
    this.populateCitySelect();
    this.populateBuildingTypeSelect();
    this.updateClimateInfo();
    this.render();
    this.renderRoomDetail();

    document.addEventListener('change', () => {
      this.syncProjectFromForm();
      this.render();
      this._autoSave();
    });
  },

  // Persist only — form values are already synced into state by the field
  // handlers (onRoomFormChange / syncProjectFromForm). Reading the form here
  // would corrupt a freshly selected room with the previous room's values.
  _autoSave() {
    try {
      localStorage.setItem('hlb_autosave', JSON.stringify({
        project: state.project,
        rooms: state.rooms,
        circuits: state.circuits,
        selectedRoomId: state.selectedRoomId,
      }));
    } catch(e) {}
  },

  _autoLoad() {
    try {
      const raw = localStorage.getItem('hlb_autosave');
      if (!raw) return;
      const saved = JSON.parse(raw);
      Object.assign(state.project, saved.project || {});
      state.rooms = saved.rooms || [];
      state.circuits = saved.circuits || [];
      state.selectedRoomId = saved.selectedRoomId || null;
      _idCounter = state.rooms.reduce((m, r) => Math.max(m, parseInt(r.id.replace('id_',''))||0), 0) + 1;
      _roomCounter = state.rooms.reduce((m, r) => Math.max(m, parseInt(r.name.replace('Raum ',''))||0), 0);
    } catch(e) {}
  },

  // ── Navigation ──────────────────────────────────────────
  switchTab(tab) {
    document.querySelectorAll('.nav-tab').forEach(t => t.classList.toggle('active', t.dataset.tab === tab));
    document.querySelectorAll('.tab-content').forEach(t => t.classList.toggle('active', t.id === 'tab-' + tab));
    if (tab === 'results') this.renderResults();
    if (['heatpump','hydraulics','radiators','quote','crm'].includes(tab)) {
      Modules.onTabActivate(tab);
    }
  },

  // ── Project form ─────────────────────────────────────────
  populateCitySelect() {
    const sel = document.getElementById('citySelect');
    HLB_DATA.cities.forEach(c => {
      const opt = document.createElement('option');
      opt.value = c.name;
      opt.textContent = `${c.name}  (${c.temp}°C)`;
      if (c.name === state.project.city) opt.selected = true;
      sel.appendChild(opt);
    });
  },

  populateBuildingTypeSelect() {
    const sel = document.getElementById('buildingType');
    sel.value = state.project.buildingType;
  },

  onCityChange() {
    const city = document.getElementById('citySelect').value;
    const found = HLB_DATA.cities.find(c => c.name === city);
    if (found) {
      document.getElementById('outdoorTemp').value = found.temp;
    }
    this.syncProjectFromForm();
    this.updateClimateInfo();
    this.render();
  },

  onProjectChange() {
    this.syncProjectFromForm();
    this.updateClimateInfo();
    this.render();
  },

  syncProjectFromForm() {
    state.project.name           = document.getElementById('projectName').value || 'Projekt';
    state.project.city           = document.getElementById('citySelect').value;
    state.project.outdoorTemp    = parseFloat(document.getElementById('outdoorTemp').value) || -14;
    state.project.buildingType   = document.getElementById('buildingType').value;
    state.project.constructionYear = parseInt(document.getElementById('constructionYear').value) || 2000;
    state.project.indoorTemp     = parseFloat(document.getElementById('defaultIndoorTemp').value) || 20;
    state.project.thermalBridges = parseFloat(document.getElementById('thermalBridges').value) || 0;
    state.project.heatingSystem  = document.getElementById('heatingSystem').value;
  },

  updateClimateInfo() {
    const dt = state.project.indoorTemp - state.project.outdoorTemp;
    const el = document.getElementById('climateInfo');
    if (!el) return;
    el.innerHTML = `
      <div class="climate-stat">
        <div class="climate-stat-value">${state.project.outdoorTemp}°C</div>
        <div class="climate-stat-label">Normaussentemperatur θ<sub>e</sub></div>
      </div>
      <div class="climate-stat">
        <div class="climate-stat-value">${state.project.indoorTemp}°C</div>
        <div class="climate-stat-label">Innentemperatur θ<sub>i</sub></div>
      </div>
      <div class="climate-stat">
        <div class="climate-stat-value">${dt} K</div>
        <div class="climate-stat-label">Temperaturdifferenz Δθ</div>
      </div>
      <div class="climate-stat">
        <div class="climate-stat-value">${state.project.thermalBridges}%</div>
        <div class="climate-stat-label">Wärmebrückenzuschlag</div>
      </div>
    `;
  },

  // ── Rooms CRUD ───────────────────────────────────────────
  addRoom() {
    const type = 'living';
    const defaults = HLB_DATA.roomTypes[type];
    _roomCounter++;
    const room = {
      id: newId(),
      name: 'Raum ' + _roomCounter,
      type,
      area: 0,
      height: 0,
      indoorTemp: defaults.temp,
      components: [],
      vent: {
        airChange: defaults.airChange,
        hasHeatRecovery: false,
        recoveryEff: 80,
      },
    };
    state.rooms.push(room);
    state.selectedRoomId = room.id;
    this._autoSave();
    this.render();
    this.renderRoomDetail();
    this.switchTab('rooms');
  },

  // ── Gebäude-Vorlagen ─────────────────────────────────────
  openTemplateModal() {
    const year = parseInt(state.project.constructionYear) || 2000;
    const grid = document.getElementById('templateGrid');
    if (grid) {
      grid.innerHTML = HLB_DATA.buildingTemplates.map(t => {
        const totalArea = t.rooms.reduce((s, r) => s + r.area, 0);
        return `
          <button class="template-card" onclick="App.applyTemplate('${t.id}')">
            <div class="template-icon">${t.icon}</div>
            <div class="template-label">${t.label}</div>
            <div class="template-sub">${t.sub}</div>
            <div class="template-meta">${t.rooms.length} Räume · ${totalArea} m²</div>
          </button>`;
      }).join('');
    }
    const info = document.getElementById('templateYearInfo');
    if (info) info.textContent = `U-Werte automatisch für Baujahr ${year} (im Projekt änderbar)`;
    document.getElementById('templateModal').style.display = 'flex';
  },

  closeTemplateModal() {
    document.getElementById('templateModal').style.display = 'none';
  },

  applyTemplate(templateId) {
    const tpl = HLB_DATA.buildingTemplates.find(t => t.id === templateId);
    if (!tpl) return;
    const year = parseInt(state.project.constructionYear) || 2000;
    const u = HLB_DATA.uDefaultsByYear(year);

    const created = tpl.rooms.map(tr => {
      const defaults = HLB_DATA.roomTypes[tr.type] || HLB_DATA.roomTypes.other;
      _roomCounter++;

      // Wall length approximated from floor area (square room), one side per ext wall
      const side    = Math.sqrt(tr.area);
      const winArea = +(tr.area * (tr.winShare || 0)).toFixed(1);
      const wallArea = +Math.max(0, (tr.ext || 0) * side * tpl.height - winArea).toFixed(1);

      const components = [];
      if (wallArea > 0) components.push({
        id: newId(), type: 'wall', description: 'Außenwand',
        area: wallArea, uValue: u.wall, adjacentTemp: null,
      });
      if (winArea > 0) components.push({
        id: newId(), type: 'window', description: 'Fenster',
        area: winArea, uValue: u.window, adjacentTemp: null,
      });
      if (tr.roof) components.push({
        id: newId(), type: 'roof', description: 'Decke / Dach',
        area: tr.area, uValue: u.roof, adjacentTemp: null,
      });
      if (tr.floor) components.push({
        id: newId(), type: 'floor', description: 'Boden geg. Keller (10°C)',
        area: tr.area, uValue: u.floor, adjacentTemp: 10,
      });

      return {
        id: newId(),
        name: tr.name,
        type: tr.type,
        area: tr.area,
        height: tpl.height,
        indoorTemp: defaults.temp,
        components,
        vent: { airChange: defaults.airChange, hasHeatRecovery: false, recoveryEff: 80 },
      };
    });

    state.rooms.push(...created);
    state.selectedRoomId = created[0].id;
    this.closeTemplateModal();
    this._autoSave();
    this.render();
    this.renderRoomDetail();
    this.switchTab('rooms');
    this.toast(`${tpl.label}: ${created.length} Räume mit Bauteilen angelegt (Baujahr ${year})`, 'success');
  },

  // ── Heizkreise ───────────────────────────────────────────
  openCircuitManager() {
    this._renderCircuitManager();
    document.getElementById('circuitModal').style.display = 'flex';
  },

  closeCircuitManager() {
    document.getElementById('circuitModal').style.display = 'none';
    this.renderRoomDetail(); // refresh room dropdown with updated circuits
  },

  addCircuit() {
    const n = state.circuits.length + 1;
    state.circuits.push({ id: newId(), name: 'Heizkreis ' + n, type: 'radiator' });
    this._autoSave();
    this._renderCircuitManager();
  },

  updateCircuit(id, key, val) {
    const c = state.circuits.find(x => x.id === id);
    if (c) { c[key] = val; this._autoSave(); }
  },

  deleteCircuit(id) {
    state.circuits = state.circuits.filter(c => c.id !== id);
    // Unassign rooms that pointed at this circuit
    state.rooms.forEach(r => { if (r.circuitId === id) r.circuitId = null; });
    this._autoSave();
    this._renderCircuitManager();
  },

  _renderCircuitManager() {
    const body = document.getElementById('circuitManagerBody');
    if (!body) return;
    if (state.circuits.length === 0) {
      body.innerHTML = `<div style="color:var(--text-muted);font-size:.85rem;text-align:center;padding:12px 0;">
        Noch keine Heizkreise. Lege einen an, um Räume zu Kreisen zu gruppieren (z. B. FBH EG, Heizkörper OG).</div>`;
    } else {
      body.innerHTML = state.circuits.map(c => {
        const roomCount = state.rooms.filter(r => r.circuitId === c.id).length;
        return `
          <div style="display:flex;gap:8px;align-items:center;padding:8px 0;border-bottom:1px solid var(--border);">
            <input type="text" value="${esc(c.name)}" onchange="App.updateCircuit('${c.id}','name',this.value)" style="flex:1;">
            <select onchange="App.updateCircuit('${c.id}','type',this.value)">
              <option value="radiator"   ${c.type === 'radiator'   ? 'selected' : ''}>🌡 Heizkörper</option>
              <option value="underfloor" ${c.type === 'underfloor' ? 'selected' : ''}>♨️ Fußbodenheizung</option>
            </select>
            <span style="font-size:.78rem;color:var(--text-muted);white-space:nowrap;">${roomCount} Räume</span>
            <button class="item-del" onclick="App.deleteCircuit('${c.id}')">×</button>
          </div>`;
      }).join('');
    }
  },

  deleteRoom(id) {
    const name = state.rooms.find(r => r.id === id)?.name || 'Raum';
    state.rooms = state.rooms.filter(r => r.id !== id);
    if (state.selectedRoomId === id) {
      state.selectedRoomId = state.rooms.length ? state.rooms[state.rooms.length - 1].id : null;
    }
    this._autoSave();
    this.render();
    this.renderRoomDetail();
    this.toast(`"${name}" gelöscht`, 'success');
  },

  newProject() {
    if (!confirm('Neues Projekt starten?\nAlle Räume und Daten werden gelöscht.')) return;
    // Reset state
    Object.assign(state.project, {
      name: 'Mein Projekt', city: 'Berlin', outdoorTemp: -14,
      buildingType: 'residential', constructionYear: 2000,
      indoorTemp: 20, thermalBridges: 5, heatingSystem: 'radiator',
    });
    state.rooms = [];
    state.circuits = [];
    state.selectedRoomId = null;
    _idCounter = 1;
    _roomCounter = 0;
    // Reset project form fields
    const pn = document.getElementById('projectName');
    if (pn) pn.value = 'Mein Projekt';
    const cs = document.getElementById('citySelect');
    if (cs) cs.value = 'Berlin';
    const bt = document.getElementById('buildingType');
    if (bt) bt.value = 'residential';
    this.updateClimateInfo();
    this._autoSave();
    this.render();
    this.renderRoomDetail();
    this.switchTab('rooms');
    this.toast('Neues Projekt gestartet', 'success');
  },

  selectRoom(id) {
    state.selectedRoomId = id;
    this.render();
    this.renderRoomDetail();
  },

  getRoom(id) {
    return state.rooms.find(r => r.id === id);
  },

  // Read the room editor form and update state
  syncRoomFromForm(room) {
    room.name       = document.getElementById('rName')?.value || room.name;
    room.type       = document.getElementById('rType')?.value || room.type;
    room.area       = parseFloat(document.getElementById('rArea')?.value) || 0;
    room.height     = parseFloat(document.getElementById('rHeight')?.value) || 0;
    room.indoorTemp = parseFloat(document.getElementById('rTemp')?.value) || 20;
    const circEl = document.getElementById('rCircuit');
    if (circEl) room.circuitId = circEl.value || null;
    room.vent.airChange      = parseFloat(document.getElementById('rAirChange')?.value) || 0.5;
    room.vent.hasHeatRecovery = document.getElementById('rHeatRecovery')?.checked || false;
    room.vent.recoveryEff    = parseFloat(document.getElementById('rRecoveryEff')?.value) || 80;
  },

  // ── Components CRUD ──────────────────────────────────────
  openAddComponent() {
    state._editingCompId = null;
    document.getElementById('modalTitle').textContent = 'Bauteil hinzufügen';
    document.getElementById('compType').value = 'wall';
    document.getElementById('compDescription').value = '';
    document.getElementById('compArea').value = '10';
    // Pre-select U-value based on construction year (wall as dialog default type)
    const year = parseInt(state.project.constructionYear) || 2000;
    const defaultU = HLB_DATA.uDefaultsByYear(year).wall;
    document.getElementById('compUValue').value = defaultU.toFixed(2);
    this.onCompTypeChange();
    // Auto-select matching preset
    const presetSel = document.getElementById('compPreset');
    const match = [...presetSel.options].find(o => Math.abs(parseFloat(o.value) - defaultU) < 0.01);
    if (match) presetSel.value = match.value;
    document.getElementById('componentModal').style.display = 'flex';
  },

  openEditComponent(compId) {
    const room = this.getRoom(state.selectedRoomId);
    if (!room) return;
    const comp = room.components.find(c => c.id === compId);
    if (!comp) return;
    state._editingCompId = compId;
    document.getElementById('modalTitle').textContent = 'Bauteil bearbeiten';
    document.getElementById('compType').value = comp.type;
    document.getElementById('compDescription').value = comp.description || '';
    document.getElementById('compArea').value = comp.area;
    document.getElementById('compUValue').value = comp.uValue;
    this.onCompTypeChange();
    if (comp.type === 'internal') {
      document.getElementById('compAdjacentTemp').value = comp.adjacentTemp ?? 10;
    }
    document.getElementById('componentModal').style.display = 'flex';
  },

  closeModal() {
    document.getElementById('componentModal').style.display = 'none';
    state._editingCompId = null;
  },

  onCompTypeChange() {
    const type = document.getElementById('compType').value;
    const presets = HLB_DATA.uValuePresets[type] || [];
    const sel = document.getElementById('compPreset');
    sel.innerHTML = '<option value="">— Manuelle Eingabe —</option>';
    presets.forEach(p => {
      const opt = document.createElement('option');
      opt.value = p.value;
      opt.textContent = `${p.label}  (U = ${p.value} W/m²K)`;
      sel.appendChild(opt);
    });
    document.getElementById('adjacentTempGroup').style.display =
      type === 'internal' ? 'block' : 'none';
  },

  onCompPresetChange() {
    const val = document.getElementById('compPreset').value;
    if (val) document.getElementById('compUValue').value = val;
  },

  saveComponent() {
    const room = this.getRoom(state.selectedRoomId);
    if (!room) return;
    const type  = document.getElementById('compType').value;
    const area  = parseFloat(document.getElementById('compArea').value) || 0;
    const uVal  = parseFloat(document.getElementById('compUValue').value) || 0;
    const desc  = document.getElementById('compDescription').value.trim();
    const adjT  = type === 'internal'
      ? parseFloat(document.getElementById('compAdjacentTemp').value) || 10
      : null;

    if (state._editingCompId) {
      const comp = room.components.find(c => c.id === state._editingCompId);
      if (comp) {
        comp.type = type; comp.area = area; comp.uValue = uVal;
        comp.description = desc; comp.adjacentTemp = adjT;
      }
    } else {
      room.components.push({ id: newId(), type, area, uValue: uVal, description: desc, adjacentTemp: adjT });
    }

    this.closeModal();
    this.render();
    this.renderRoomDetail();
  },

  deleteComponent(compId) {
    const room = this.getRoom(state.selectedRoomId);
    if (!room) return;
    room.components = room.components.filter(c => c.id !== compId);
    this.render();
    this.renderRoomDetail();
  },

  // ── Master render ─────────────────────────────────────────
  render() {
    const result = HLB_CALC.calcProject(state);

    // Nav badge
    document.getElementById('roomCountBadge').textContent = state.rooms.length;

    // Nav summary
    const navLoad = document.getElementById('navHeatingLoad');
    navLoad.textContent = result ? HLB_CALC.fmt(result.totalLoad) : '– W';

    // Sidebar room list
    this.renderRoomList(result);

    // Sidebar total
    document.getElementById('sidebarTotal').textContent =
      result ? HLB_CALC.fmt(result.totalLoad) : '0 W';
  },

  renderRoomList(result) {
    const list = document.getElementById('roomList');
    if (!state.rooms.length) {
      list.innerHTML = `<div style="padding:20px;text-align:center;color:var(--text-muted);font-size:.82rem;">
        Noch keine Räume angelegt.</div>`;
      return;
    }
    list.innerHTML = state.rooms.map(room => {
      const rr = result?.rooms.find(r => r.id === room.id);
      const load = rr ? HLB_CALC.fmtW(rr.total) : '– W';
      const sel = room.id === state.selectedRoomId;
      const emoji = roomEmoji[room.type] || '🏠';
      return `
        <div class="room-item ${sel ? 'selected' : ''}" onclick="App.selectRoom('${room.id}')">
          <div class="room-item-icon">${emoji}</div>
          <div class="room-item-info">
            <div class="room-item-name">${esc(room.name)}</div>
            <div class="room-item-sub">${room.area} m² · ${room.height} m</div>
          </div>
          <div class="room-item-load">${load}</div>
        </div>`;
    }).join('');
  },

  // ── Room detail renderer ─────────────────────────────────
  renderRoomDetail() {
    const emptyEl   = document.getElementById('roomDetailEmpty');
    const contentEl = document.getElementById('roomDetailContent');

    if (!state.selectedRoomId) {
      emptyEl.style.display = 'flex';
      contentEl.style.display = 'none';
      return;
    }
    const room = this.getRoom(state.selectedRoomId);
    if (!room) { emptyEl.style.display = 'flex'; contentEl.style.display = 'none'; return; }

    emptyEl.style.display = 'none';
    contentEl.style.display = 'block';

    const result = HLB_CALC.calcProject(state);
    const rr = result?.rooms.find(r => r.id === room.id);

    // Room type options
    const typeOptions = Object.entries(HLB_DATA.roomTypes)
      .map(([k, v]) => `<option value="${k}" ${room.type === k ? 'selected' : ''}>${roomEmoji[k] || ''} ${v.label}</option>`)
      .join('');

    // Heizkreis options
    const circuitOptions = '<option value="">— kein Heizkreis —</option>' +
      state.circuits.map(c => `<option value="${c.id}" ${room.circuitId === c.id ? 'selected' : ''}>${c.type === 'underfloor' ? '♨️' : '🌡'} ${esc(c.name)}</option>`).join('');

    // Component rows — use index (not ID) to match componentDetail, since detail is
    // always built as room.components.map(...) and has the same order and length.
    const maxLoss = rr ? Math.max(...rr.componentDetail.map(c => c.loss), 1) : 1;
    const compRows = room.components.length
      ? room.components.map((c, idx) => {
          const loss = rr ? (rr.componentDetail[idx]?.loss ?? 0) : 0;
          const barW = Math.round(loss / maxLoss * 100);
          const adjInfo = c.adjacentTemp != null ? ` · θ_adj = ${c.adjacentTemp}°C` : '';
          return `
            <tr>
              <td><span class="comp-type-badge ${c.type}">${HLB_DATA.componentLabels[c.type]}</span></td>
              <td>${esc(c.description || '—')}</td>
              <td>${c.area.toFixed(1)}</td>
              <td>${c.uValue.toFixed(2)}${adjInfo}</td>
              <td>
                <div style="display:flex;align-items:center;gap:8px;">
                  <div class="loss-bar" style="width:${barW}px;max-width:80px"></div>
                  <strong>${Math.round(loss)} W</strong>
                </div>
              </td>
              <td>
                <div style="display:flex;gap:4px;">
                  <button class="btn-icon" onclick="App.openEditComponent('${c.id}')" title="Bearbeiten">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                  </button>
                  <button class="btn-icon" onclick="App.deleteComponent('${c.id}')" title="Löschen">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6M14 11v6"/></svg>
                  </button>
                </div>
              </td>
            </tr>`;
        }).join('')
      : `<tr><td colspan="6" style="text-align:center;color:var(--text-muted);padding:24px;">
           Noch keine Bauteile. Klicke "+ Bauteil hinzufügen".</td></tr>`;

    // Result banner
    const banner = rr ? `
      <div class="room-result-banner">
        <div class="room-result-stat">
          <div class="room-result-stat-value">${HLB_CALC.fmt(rr.total)}</div>
          <div class="room-result-stat-label">Gesamtheizlast</div>
        </div>
        <div class="room-result-divider"></div>
        <div class="room-result-stat">
          <div class="room-result-stat-value">${HLB_CALC.fmtW(rr.transmission)}</div>
          <div class="room-result-stat-label">Transmissionsverlust Φ<sub>T</sub></div>
        </div>
        <div class="room-result-divider"></div>
        <div class="room-result-stat">
          <div class="room-result-stat-value">${HLB_CALC.fmtW(rr.ventilation)}</div>
          <div class="room-result-stat-label">Lüftungsverlust Φ<sub>V</sub></div>
        </div>
        <div class="room-result-divider"></div>
        <div class="room-result-stat">
          <div class="room-result-stat-value">${rr.specificLoad.toFixed(0)} W/m²</div>
          <div class="room-result-stat-label">Spezifische Heizlast</div>
        </div>
      </div>` : '';

    const hrChecked = room.vent.hasHeatRecovery ? 'checked' : '';

    contentEl.innerHTML = `
      <div class="room-editor">

        <div class="room-editor-header">
          <span class="room-editor-title">${roomEmoji[room.type] || '🏠'} ${esc(room.name)}</span>
          <div style="display:flex;gap:8px;align-items:center;">
            <button class="btn btn-outline btn-sm" onclick="Scanner.open('${room.id}')" title="Raum mit Kamera / AR / Punktwolke ausmessen"
              style="color:var(--primary);border-color:var(--primary);display:flex;align-items:center;gap:5px;">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:14px;height:14px">
                <circle cx="12" cy="12" r="3"/><path d="M3 9a9 9 0 0 1 9-6 9 9 0 0 1 9 6M3 15a9 9 0 0 0 9 6 9 9 0 0 0 9-6"/>
              </svg>
              📡 Scan
            </button>
            <button class="btn btn-danger btn-sm" onclick="App.deleteRoom('${room.id}')">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:14px;height:14px"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6"/></svg>
              Raum löschen
            </button>
          </div>
        </div>

        ${banner}

        ${room.floorPlan ? `
        <div class="section-card">
          <div class="section-header">
            <div class="section-title">📐 Grundriss (aus LiDAR-Scan)</div>
          </div>
          <div class="section-body">
            <canvas id="roomFloorPlanCanvas" style="width:100%;height:220px;border-radius:10px;display:block;background:#0a0a0f;"></canvas>
          </div>
        </div>` : ''}

        <!-- Basic data -->
        <div class="section-card">
          <div class="section-header">
            <div class="section-title">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/></svg>
              Raumdaten
            </div>
          </div>
          <div class="section-body">
            <div class="form-row">
              <div class="form-group">
                <label>Bezeichnung</label>
                <input type="text" id="rName" value="${esc(room.name)}" oninput="App.onRoomFormChange()">
              </div>
              <div class="form-group">
                <label>Raumtyp</label>
                <select id="rType" onchange="App.onRoomTypeChange()">${typeOptions}</select>
              </div>
            </div>
            <div class="form-row-3">
              <div class="form-group">
                <label>Fläche [m²]</label>
                <input type="number" id="rArea" value="${room.area}" step="0.5" min="0" oninput="App.onRoomFormChange()">
              </div>
              <div class="form-group">
                <label>Raumhöhe [m]</label>
                <input type="number" id="rHeight" value="${room.height}" step="0.1" min="0" oninput="App.onRoomFormChange()">
              </div>
              <div class="form-group">
                <label>Innentemperatur [°C]</label>
                <input type="number" id="rTemp" value="${room.indoorTemp}" step="1" oninput="App.onRoomFormChange()">
              </div>
            </div>
            <div class="form-group">
              <label>Heizkreis <span style="font-weight:400;color:var(--text-muted);font-size:.8rem;">· für hydraulischen Abgleich nach Kreisen</span></label>
              <div style="display:flex;gap:6px;">
                <select id="rCircuit" onchange="App.onRoomFormChange()" style="flex:1;">${circuitOptions}</select>
                <button type="button" class="btn btn-outline btn-sm" onclick="App.openCircuitManager()" title="Heizkreise verwalten" style="white-space:nowrap;">⚙ Kreise</button>
              </div>
            </div>
          </div>
        </div>

        <!-- Components -->
        <div class="section-card">
          <div class="section-header">
            <div class="section-title">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2"/></svg>
              Bauteile (${room.components.length})
            </div>
            <button class="btn btn-outline btn-sm" onclick="App.openAddComponent()">+ Bauteil hinzufügen</button>
          </div>
          <div class="section-body" style="padding:0;">
            <div class="comp-table-wrapper">
              <table class="comp-table">
                <thead>
                  <tr>
                    <th>Typ</th>
                    <th>Bezeichnung</th>
                    <th>Fläche (m²)</th>
                    <th>U-Wert (W/m²K)</th>
                    <th>Heizlast</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>${compRows}</tbody>
              </table>
            </div>
            ${room.components.length === 0 ? `
            <div style="margin:12px 16px 8px;padding:10px 14px;background:#fff8e1;border-left:4px solid #f39c12;border-radius:6px;font-size:.82rem;color:#7d5c00;">
              ⚠️ Keine Bauteile eingetragen – Transmissionsverlust = 0 W.<br>
              Bitte Außenwände, Fenster, Dach und Boden hinzufügen für eine realistische Berechnung.<br>
              <strong>Altbau vor 1970:</strong> Wand U ≈ 1.6–2.1, Fenster U ≈ 2.8–5.0 → erwartet ca. 80–120 W/m²
            </div>` : ''}
          </div>
        </div>

        <!-- Ventilation -->
        <div class="section-card">
          <div class="section-header">
            <div class="section-title">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" y1="22" x2="4" y2="15"/></svg>
              Lüftung
            </div>
          </div>
          <div class="section-body">
            <div class="form-row">
              <div class="form-group">
                <label>Luftwechselzahl n [1/h]</label>
                <input type="number" id="rAirChange" value="${room.vent.airChange}" step="0.1" min="0" oninput="App.onRoomFormChange()">
                <div class="form-hint">Empfehlung: 0.3 (Keller) – 0.5 (Wohnen) – 0.8 (Bad)</div>
              </div>
              <div class="form-group">
                <label>Raumvolumen</label>
                <input type="text" readonly value="${(room.area * room.height).toFixed(1)} m³" style="background:var(--bg);color:var(--text-muted);">
              </div>
            </div>
            <div class="toggle-row">
              <span class="toggle-label">Wärmerückgewinnung (WRG)</span>
              <input type="checkbox" id="rHeatRecovery" ${hrChecked} onchange="App.onRoomFormChange()">
            </div>
            <div id="recoveryEffRow" style="${room.vent.hasHeatRecovery ? '' : 'display:none;'}margin-top:12px;">
              <div class="form-group">
                <label>WRG-Wirkungsgrad [%]</label>
                <input type="number" id="rRecoveryEff" value="${room.vent.recoveryEff}" step="5" min="0" max="100" oninput="App.onRoomFormChange()">
                <div class="form-hint">Typisch: 75–85 % für Kreuzgegenstromwärmetauscher</div>
              </div>
            </div>
          </div>
        </div>

      </div>`;

    if (room.floorPlan) {
      const fpCanvas = document.getElementById('roomFloorPlanCanvas');
      if (fpCanvas) Scanner.drawFloorPlan(fpCanvas, room.floorPlan);
    }

    // Toggle WRG row visibility
    document.getElementById('rHeatRecovery')?.addEventListener('change', function() {
      document.getElementById('recoveryEffRow').style.display = this.checked ? 'block' : 'none';
    });
  },

  onRoomFormChange() {
    const room = this.getRoom(state.selectedRoomId);
    if (!room) return;
    this.syncRoomFromForm(room);
    this.render();
    // Update result banner without full re-render
    const result = HLB_CALC.calcProject(state);
    const rr = result?.rooms.find(r => r.id === room.id);
    if (rr) {
      const banner = document.querySelector('.room-result-banner');
      if (banner) {
        banner.querySelectorAll('.room-result-stat-value')[0].textContent = HLB_CALC.fmt(rr.total);
        banner.querySelectorAll('.room-result-stat-value')[1].textContent = HLB_CALC.fmtW(rr.transmission);
        banner.querySelectorAll('.room-result-stat-value')[2].textContent = HLB_CALC.fmtW(rr.ventilation);
        banner.querySelectorAll('.room-result-stat-value')[3].textContent = rr.specificLoad.toFixed(0) + ' W/m²';
      }
    }
    // Update room name in header
    const title = document.querySelector('.room-editor-title');
    if (title) title.textContent = (roomEmoji[room.type] || '🏠') + ' ' + room.name;
  },

  onRoomTypeChange() {
    const room = this.getRoom(state.selectedRoomId);
    if (!room) return;
    const type = document.getElementById('rType').value;
    const defaults = HLB_DATA.roomTypes[type];
    room.type = type;
    // Update indoor temp to type default if user hasn't customised heavily
    document.getElementById('rTemp').value = defaults.temp;
    document.getElementById('rAirChange').value = defaults.airChange;
    this.onRoomFormChange();
    this.render();
    this.renderRoomDetail();
  },

  // ── Results Tab ──────────────────────────────────────────
  renderResults() {
    const result = HLB_CALC.calcProject(state);
    const emptyEl = document.getElementById('resultsEmpty');
    const dataEl  = document.getElementById('resultsData');

    if (!result || result.totalLoad === 0) {
      emptyEl.style.display = 'flex';
      dataEl.style.display  = 'none';
      return;
    }
    emptyEl.style.display = 'none';
    dataEl.style.display  = 'block';

    // Specific load rating
    const sl = result.specificLoad;
    let slClass = 'success', slText = 'Sehr gut (KfW 55)';
    if (sl > 80) { slClass = 'danger';  slText = 'Hoch (Altbau)'; }
    else if (sl > 50) { slClass = 'warning'; slText = 'Mittel (EnEV)'; }
    else if (sl > 30) { slClass = ''; slText = 'Gut (Neubau)'; }

    // KPI cards
    const pctTrans = result.totalLoad > 0 ? Math.round(result.totalTransmission / result.totalLoad * 100) : 0;
    const pctVent  = result.totalLoad > 0 ? Math.round(result.totalVentilation  / result.totalLoad * 100) : 0;

    dataEl.innerHTML = `
      <div class="kpi-grid">
        <div class="kpi-card">
          <div class="kpi-label">Gesamtheizlast</div>
          <div class="kpi-value">${HLB_CALC.fmt(result.totalLoad)}</div>
          <div class="kpi-sub">Φ<sub>HL</sub> = Φ<sub>T</sub> + Φ<sub>WB</sub> + Φ<sub>V</sub></div>
        </div>
        <div class="kpi-card ${slClass}">
          <div class="kpi-label">Spezifische Heizlast</div>
          <div class="kpi-value">${sl.toFixed(0)} W/m²</div>
          <div class="kpi-sub">${slText}</div>
        </div>
        <div class="kpi-card">
          <div class="kpi-label">Transmissionsverlust</div>
          <div class="kpi-value">${HLB_CALC.fmt(result.totalTransmission)}</div>
          <div class="kpi-sub">${pctTrans}% der Gesamtlast</div>
        </div>
        <div class="kpi-card">
          <div class="kpi-label">Lüftungsverlust</div>
          <div class="kpi-value">${HLB_CALC.fmt(result.totalVentilation)}</div>
          <div class="kpi-sub">${pctVent}% der Gesamtlast</div>
        </div>
      </div>

      <div class="results-grid" style="padding: 0 32px 20px;">
        <!-- Chart card -->
        <div class="card">
          <div class="card-header">Heizlast je Raum</div>
          <div class="card-body">
            <div class="chart-wrapper"><canvas id="resultsChart"></canvas></div>
          </div>
        </div>

        <!-- Summary table -->
        <div class="card">
          <div class="card-header">Raumübersicht</div>
          <div class="card-body" style="padding:0;">
            <table class="results-table">
              <thead>
                <tr>
                  <th>Raum</th>
                  <th>m²</th>
                  <th>Φ<sub>T</sub> (W)</th>
                  <th>Φ<sub>V</sub> (W)</th>
                  <th>Gesamt</th>
                  <th>W/m²</th>
                </tr>
              </thead>
              <tbody>
                ${result.rooms.map(r => `
                  <tr>
                    <td><strong>${esc(r.name)}</strong></td>
                    <td>${r.area.toFixed(0)}</td>
                    <td>${Math.round(r.transmission)}</td>
                    <td>${Math.round(r.ventilation)}</td>
                    <td><strong>${HLB_CALC.fmtW(r.total)}</strong></td>
                    <td>${r.specificLoad.toFixed(0)}</td>
                  </tr>`).join('')}
              </tbody>
              <tfoot>
                <tr>
                  <td><strong>Summe</strong></td>
                  <td>${result.totalArea.toFixed(0)}</td>
                  <td>${Math.round(result.totalTransmission)}</td>
                  <td>${Math.round(result.totalVentilation)}</td>
                  <td><strong>${HLB_CALC.fmt(result.totalLoad)}</strong></td>
                  <td>${result.specificLoad.toFixed(0)}</td>
                </tr>
              </tfoot>
            </table>
          </div>
        </div>
      </div>

      <!-- Project summary -->
      <div style="padding: 0 32px;">
        <div class="card">
          <div class="card-header">Berechnungsgrundlagen</div>
          <div class="card-body">
            <div class="climate-info-grid" style="grid-template-columns:repeat(5,1fr)">
              <div class="climate-stat">
                <div class="climate-stat-value">${esc(state.project.city)}</div>
                <div class="climate-stat-label">Standort</div>
              </div>
              <div class="climate-stat">
                <div class="climate-stat-value">${state.project.outdoorTemp}°C</div>
                <div class="climate-stat-label">Normaussentemperatur</div>
              </div>
              <div class="climate-stat">
                <div class="climate-stat-value">${state.project.indoorTemp}°C</div>
                <div class="climate-stat-label">Innentemperatur</div>
              </div>
              <div class="climate-stat">
                <div class="climate-stat-value">${state.project.thermalBridges}%</div>
                <div class="climate-stat-label">Wärmebrückenzuschlag</div>
              </div>
              <div class="climate-stat">
                <div class="climate-stat-value">${state.rooms.length}</div>
                <div class="climate-stat-label">Räume</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    `;

    this.renderChart(result);
  },

  renderChart(result) {
    const ctx = document.getElementById('resultsChart');
    if (!ctx) return;

    if (chart) { chart.destroy(); chart = null; }

    chart = new Chart(ctx, {
      type: 'bar',
      data: {
        labels: result.rooms.map(r => r.name),
        datasets: [
          {
            label: 'Transmissionsverlust (W)',
            data: result.rooms.map(r => Math.round(r.transmission)),
            backgroundColor: 'rgba(0,87,184,0.75)',
            borderRadius: 4,
          },
          {
            label: 'Lüftungsverlust (W)',
            data: result.rooms.map(r => Math.round(r.ventilation)),
            backgroundColor: 'rgba(0,166,80,0.75)',
            borderRadius: 4,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { position: 'top', labels: { font: { size: 11 } } },
          tooltip: {
            callbacks: {
              footer: items => {
                const total = items.reduce((s, i) => s + i.raw, 0);
                return `Gesamt: ${Math.round(total)} W`;
              }
            }
          }
        },
        scales: {
          x: { stacked: true, ticks: { font: { size: 11 } } },
          y: { stacked: true, beginAtZero: true, ticks: { callback: v => v + ' W', font: { size: 11 } } }
        }
      }
    });
  },

  // ── Save / Load ──────────────────────────────────────────
  saveToStorage() {
    this.syncProjectFromForm();
    // Sync selected room too
    const room = this.getRoom(state.selectedRoomId);
    if (room) this.syncRoomFromForm(room);

    localStorage.setItem('hlb_state', JSON.stringify({
      project: state.project,
      rooms: state.rooms,
      circuits: state.circuits,
      selectedRoomId: state.selectedRoomId,
    }));
    this.toast('Projekt gespeichert ✓', 'success');
  },

  loadFromStorage() {
    const raw = localStorage.getItem('hlb_state');
    if (!raw) { this.toast('Kein gespeichertes Projekt gefunden', 'error'); return; }
    try {
      const saved = JSON.parse(raw);
      Object.assign(state.project, saved.project);
      state.rooms = saved.rooms || [];
      state.circuits = saved.circuits || [];
      state.selectedRoomId = saved.selectedRoomId || null;
      _idCounter = state.rooms.reduce((max, r) => {
        const n = parseInt(r.id.replace('id_', '')) || 0;
        const cn = r.components.reduce((cm, c) => Math.max(cm, parseInt(c.id.replace('id_', '')) || 0), 0);
        return Math.max(max, n, cn);
      }, 0) + 1;

      // Update form fields
      document.getElementById('projectName').value = state.project.name;
      document.getElementById('citySelect').value = state.project.city;
      document.getElementById('outdoorTemp').value = state.project.outdoorTemp;
      document.getElementById('buildingType').value = state.project.buildingType;
      document.getElementById('constructionYear').value = state.project.constructionYear;
      document.getElementById('defaultIndoorTemp').value = state.project.indoorTemp;
      document.getElementById('thermalBridges').value = state.project.thermalBridges;
      document.getElementById('heatingSystem').value = state.project.heatingSystem;

      this.updateClimateInfo();
      this.render();
      this.renderRoomDetail();
      this.toast('Projekt geladen ✓', 'success');
    } catch (e) {
      this.toast('Fehler beim Laden', 'error');
    }
  },

  // ── PDF Export ───────────────────────────────────────────
  // Baut einen druckfertigen Bericht in #printReport und öffnet den
  // Druckdialog. Auf iPhone/iPad: Drucken → Vorschau aufziehen → Teilen als PDF.
  exportPDF() {
    this.syncProjectFromForm();
    const room = this.getRoom(state.selectedRoomId);
    if (room) this.syncRoomFromForm(room);

    const result = HLB_CALC.calcProject(state);
    if (!result) { this.toast('Keine Räume vorhanden — bitte zuerst Räume anlegen', 'error'); return; }

    document.getElementById('printReport').innerHTML = this._buildReportHTML(result);
    setTimeout(() => window.print(), 150);
  },

  _buildReportHTML(result) {
    const p = state.project;
    const esc = (s) => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
    const fmtW = (w) => w >= 10000 ? (w / 1000).toFixed(1).replace('.', ',') + ' kW' : Math.round(w).toLocaleString('de') + ' W';
    const num = (v, d = 1) => (+v).toLocaleString('de', { minimumFractionDigits: d, maximumFractionDigits: d });
    const today = new Date().toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric' });

    // Raumzeilen der Übersichtstabelle
    const roomRows = result.rooms.map(rr => {
      const room = this.getRoom(rr.id);
      return `<tr>
        <td>${esc(rr.name)}</td>
        <td class="num">${num(rr.area)}</td>
        <td class="num">${num(room?.height ?? 0, 2)}</td>
        <td class="num">${room?.indoorTemp ?? ''} °C</td>
        <td class="num">${fmtW(rr.transmission + rr.thermalBridges)}</td>
        <td class="num">${fmtW(rr.ventilation)}</td>
        <td class="num"><strong>${fmtW(rr.total)}</strong></td>
        <td class="num">${Math.round(rr.specificLoad)}</td>
      </tr>`;
    }).join('');

    // Bauteil-Details pro Raum
    const roomDetails = result.rooms.map(rr => {
      const room = this.getRoom(rr.id);
      if (!room || !room.components.length) return '';
      const compRows = rr.componentDetail.map(c => `
        <tr>
          <td>${esc(HLB_DATA.componentLabels[c.type] || c.type)}</td>
          <td>${esc(c.description || '—')}</td>
          <td class="num">${num(c.area)}</td>
          <td class="num">${num(c.uValue, 2)}</td>
          <td class="num">${c.adjacentTemp != null ? c.adjacentTemp + ' °C' : (p.outdoorTemp + ' °C')}</td>
          <td class="num">${fmtW(c.loss)}</td>
        </tr>`).join('');
      return `
        <div class="pr-room">
          <h3>${esc(rr.name)} <span class="pr-room-load">${fmtW(rr.total)} · ${Math.round(rr.specificLoad)} W/m²</span></h3>
          <table class="pr-table">
            <thead><tr><th>Bauteil</th><th>Bezeichnung</th><th class="num">Fläche m²</th><th class="num">U-Wert</th><th class="num">θ angrenzend</th><th class="num">Verlust</th></tr></thead>
            <tbody>${compRows}</tbody>
            <tfoot>
              <tr><td colspan="5">Transmission gesamt (inkl. ${p.thermalBridges}% Wärmebrücken)</td><td class="num">${fmtW(rr.transmission + rr.thermalBridges)}</td></tr>
              <tr><td colspan="5">Lüftungsverlust (n = ${room.vent.airChange}/h · V = ${num(room.area * room.height)} m³)</td><td class="num">${fmtW(rr.ventilation)}</td></tr>
              <tr class="pr-total"><td colspan="5"><strong>Heizlast ${esc(rr.name)}</strong></td><td class="num"><strong>${fmtW(rr.total)}</strong></td></tr>
            </tfoot>
          </table>
        </div>`;
    }).join('');

    // Ersteller (SHK-Betrieb) und Objekt/Auftraggeber aus dem Angebots-Modul,
    // damit die Daten nur einmal eingegeben werden müssen.
    const co = (typeof QuoteModule !== 'undefined' ? QuoteModule.state.company : {}) || {};
    const cu = (typeof QuoteModule !== 'undefined' ? QuoteModule.state.customer : {}) || {};
    const anyCo = co.name || co.street || co.city;
    const anyCu = cu.name || cu.street || cu.city;

    const partiesBlock = `
      <div class="pr-parties">
        <div class="pr-party">
          <div class="pr-party-label">Ersteller</div>
          ${anyCo ? `<strong>${esc(co.name)}</strong><br>${esc(co.street)}<br>${esc(co.city)}${co.phone ? '<br>' + esc(co.phone) : ''}${co.email ? '<br>' + esc(co.email) : ''}`
                  : '<span class="pr-empty">— im Angebot-Tab hinterlegen —</span>'}
        </div>
        <div class="pr-party">
          <div class="pr-party-label">Objekt / Auftraggeber</div>
          ${anyCu ? `<strong>${esc(cu.name)}</strong><br>${esc(cu.street)}<br>${esc(cu.city)}`
                  : '<span class="pr-empty">— im Angebot-Tab hinterlegen —</span>'}
        </div>
      </div>`;

    return `
      <div class="pr-header">
        <div>
          <div class="pr-title">Heizlastberechnung</div>
          <div class="pr-subtitle">Nachweis nach DIN EN 12831-1 · Grundlage für BEG/KfW-Heizungsförderung (z. B. KfW 458)</div>
        </div>
        <div class="pr-brand">🔥 HeizlastProfi</div>
      </div>

      ${partiesBlock}

      <table class="pr-meta">
        <tr><td>Projekt</td><td><strong>${esc(p.name)}</strong></td><td>Datum</td><td>${today}</td></tr>
        <tr><td>Standort</td><td>${esc(p.city)} (θₑ = ${p.outdoorTemp} °C)</td><td>Baujahr</td><td>${p.constructionYear}</td></tr>
        <tr><td>Gebäudetyp</td><td>${p.buildingType === 'residential' ? 'Wohngebäude' : 'Nichtwohngebäude'}</td><td>Wärmebrücken-Zuschlag</td><td>${p.thermalBridges} %</td></tr>
      </table>

      <div class="pr-kpis">
        <div class="pr-kpi pr-kpi-main"><div class="pr-kpi-val">${fmtW(result.totalLoad)}</div><div class="pr-kpi-lbl">Gesamtheizlast</div></div>
        <div class="pr-kpi"><div class="pr-kpi-val">${fmtW(result.totalTransmission + result.totalThermalBridges)}</div><div class="pr-kpi-lbl">Transmission Φ_T</div></div>
        <div class="pr-kpi"><div class="pr-kpi-val">${fmtW(result.totalVentilation)}</div><div class="pr-kpi-lbl">Lüftung Φ_V</div></div>
        <div class="pr-kpi"><div class="pr-kpi-val">${result.totalArea > 0 ? Math.round(result.totalLoad / result.totalArea) : 0} W/m²</div><div class="pr-kpi-lbl">spezifisch (${num(result.totalArea)} m²)</div></div>
      </div>

      <h2>Raumübersicht</h2>
      <table class="pr-table">
        <thead><tr><th>Raum</th><th class="num">Fläche m²</th><th class="num">Höhe m</th><th class="num">θᵢ</th><th class="num">Φ_T</th><th class="num">Φ_V</th><th class="num">Heizlast</th><th class="num">W/m²</th></tr></thead>
        <tbody>${roomRows}</tbody>
        <tfoot><tr class="pr-total"><td><strong>Gesamt</strong></td><td class="num">${num(result.totalArea)}</td><td></td><td></td>
          <td class="num">${fmtW(result.totalTransmission + result.totalThermalBridges)}</td>
          <td class="num">${fmtW(result.totalVentilation)}</td>
          <td class="num"><strong>${fmtW(result.totalLoad)}</strong></td>
          <td class="num">${result.totalArea > 0 ? Math.round(result.totalLoad / result.totalArea) : 0}</td></tr></tfoot>
      </table>

      <h2>Bauteile je Raum</h2>
      ${roomDetails || '<p class="pr-note">Keine Bauteile erfasst.</p>'}

      <h2>Berechnungsgrundlagen</h2>
      <table class="pr-basis">
        <tr><td>Norm</td><td>DIN EN 12831-1 (Heizungsanlagen in Gebäuden — Verfahren zur Berechnung der Norm-Heizlast)</td></tr>
        <tr><td>Norm-Außentemperatur</td><td>θₑ = ${p.outdoorTemp} °C (Standort ${esc(p.city)}, Klimazone nach DIN EN 12831 Beiblatt)</td></tr>
        <tr><td>Norm-Innentemperaturen</td><td>raumweise nach Nutzung (Wohnräume 20 °C, Bad 24 °C, Schlafräume 18 °C u. a.)</td></tr>
        <tr><td>Transmission Φ_T</td><td>Φ_T = Σ (A · U · Δθ), Wärmebrücken-Zuschlag pauschal ${p.thermalBridges} %</td></tr>
        <tr><td>Lüftung Φ_V</td><td>Φ_V = 0,34 · n · V · Δθ (n = Luftwechselrate je Raum)</td></tr>
        <tr><td>Verfahren</td><td>Vereinfachtes Verfahren (raumweise Norm-Heizlast, ohne Aufheizleistung)</td></tr>
      </table>

      <div class="pr-signature">
        <div class="pr-sign-line">
          <div class="pr-sign-rule"></div>
          <div class="pr-sign-lbl">Ort, Datum</div>
        </div>
        <div class="pr-sign-line">
          <div class="pr-sign-rule"></div>
          <div class="pr-sign-lbl">Unterschrift / Stempel Ersteller</div>
        </div>
      </div>

      <div class="pr-footer">
        Norm-Heizlast nach DIN EN 12831-1 (vereinfachtes Verfahren) · erstellt mit HeizlastProfi am ${today}.
        Diese Berechnung dient als Heizlastnachweis für BEG/KfW-Förderanträge (z. B. KfW 458).
        Die förmliche „Bestätigung zum Antrag" (BzA) ist durch eine·n eingetragene·n Energieeffizienz-Expert·in (dena-Liste) auszustellen.
        Angaben ohne Gewähr.
      </div>`;
  },

  // ── Toast ────────────────────────────────────────────────
  toast(msg, type = '') {
    let container = document.querySelector('.toast-container');
    if (!container) {
      container = document.createElement('div');
      container.className = 'toast-container';
      document.body.appendChild(container);
    }
    const t = document.createElement('div');
    t.className = 'toast ' + type;
    t.textContent = msg;
    container.appendChild(t);
    setTimeout(() => t.remove(), 3000);
  },
};

// ── Utility ──────────────────────────────────────────────
function esc(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── Bootstrap ────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => App.init());
