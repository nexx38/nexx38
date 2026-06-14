/* ────────────────────────────────────────────────────────
   HeizlastProfi — Room Scanner (iPhone / iPad fokussiert)
   Modes:
     1. File   — LiDAR-Scan via Scaniverse → PLY/XYZ/OBJ Import
     2. Camera — Kamera-Vorschau + Sensor-Messung / manuelle Eingabe
   ──────────────────────────────────────────────────────── */

const Scanner = {

  // ── State ──────────────────────────────────────────────
  s: {
    mode: null,          // 'file' | 'camera'
    roomId: null,
    cameraStream: null,
    result: { width: 0, depth: 0, height: 2.50, area: 0 },
    pcPoints: null,      // parsed point cloud [{x,y,z}]
    pcBounds: null,
    pcRotX: 0.4,
    pcRotY: 0,
    pcDragStart: null,
    animFrame: null,
  },

  // ── Open / Close ───────────────────────────────────────
  async open(roomId) {
    this.s.roomId = roomId;
    this.s.result = { width: 0, depth: 0, height: 2.50, area: 0 };
    document.getElementById('scannerOverlay').classList.add('active');

    // iPad mit Desktop-UA meldet sich als MacIntel mit Touchscreen
    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent)
      || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

    this.switchMode(isIOS ? 'file' : 'camera');
  },

  close() {
    this._stopCamera();
    this.stopMeasure();
    if (this.s.animFrame) { cancelAnimationFrame(this.s.animFrame); this.s.animFrame = null; }
    document.getElementById('scannerOverlay').classList.remove('active');
    this.s.mode = null;
  },

  // ── Mode switching ─────────────────────────────────────
  async switchMode(mode) {
    if (this.s.mode === mode) return;

    this._stopCamera();
    this.stopMeasure();
    this.s.mode = mode;

    // Update tabs
    document.querySelectorAll('.scanner-tab').forEach(t => t.classList.toggle('active', t.dataset.mode === mode));

    // Update panels
    document.querySelectorAll('.scanner-panel').forEach(p => p.classList.remove('active'));
    document.getElementById('scanPanel_' + mode).classList.add('active');

    if (mode === 'camera') await this._startCamera();
    if (mode === 'file')   this._setupFilePanel();
  },

  // ── Camera Mode ────────────────────────────────────────
  async _startCamera() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment', width: { ideal: 1920 }, height: { ideal: 1080 } },
      });
      const video = document.getElementById('cameraVideo');
      if (video) { video.srcObject = stream; video.play(); }
      this.s.cameraStream = stream;
      document.getElementById('cameraPlaceholder').style.display = 'none';
    } catch {
      document.getElementById('cameraPlaceholder').style.display = 'flex';
    }
    this._drawRoomSketch();
    this._setupCameraListeners();
  },

  _stopCamera() {
    this.stopMeasure();
    if (this.s.cameraStream) {
      this.s.cameraStream.getTracks().forEach(t => t.stop());
      this.s.cameraStream = null;
    }
    const video = document.getElementById('cameraVideo');
    if (video) { video.srcObject = null; }
  },

  _setupCameraListeners() {
    ['camWidth', 'camDepth', 'camHeight'].forEach(id => {
      document.getElementById(id)?.addEventListener('input', () => this._drawRoomSketch());
    });
  },

  // ── Sensor Measure Mode (tilt-based, no AR needed) ─────
  // d = cameraHeight × tan(beta_rad)
  // beta from deviceorientation: 0°=flat, 90°=upright portrait
  // Step 1: stand at Wand A, aim at Wand B → room width
  // Step 2: turn 90°, aim at adjacent wall → room depth
  m: {
    active: false,
    step: 0,      // 0 = measuring width, 1 = measuring depth
    dists: [],
    beta: null,
    camHeight: 1.6,
    handler: null,
    history: [],  // rolling window for stability detection
    stable: false,
  },

  startMeasure() {
    // iOS 13+ requires explicit permission via user gesture
    if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') {
      DeviceOrientationEvent.requestPermission()
        .then(state => {
          if (state === 'granted') this._beginMeasure();
          else App.toast?.('Sensor-Zugriff verweigert — bitte in Einstellungen erlauben', 'error');
        })
        .catch(() => App.toast?.('Sensor-Zugriff nicht möglich', 'error'));
    } else {
      this._beginMeasure();
    }
  },

  _beginMeasure() {
    this.m.active  = true;
    this.m.step    = 0;
    this.m.dists   = [];
    this.m.beta    = null;
    this.m.history = [];
    this.m.stable  = false;
    this.m.camHeight = parseFloat(document.getElementById('measureCamHeight')?.value) || 1.6;

    const overlay = document.getElementById('measureOverlay');
    if (overlay) overlay.style.display = 'flex';

    this.m.handler = (e) => this._onOrientation(e);
    window.addEventListener('deviceorientation', this.m.handler);

    // Warn if no sensor data arrives within 2 s
    setTimeout(() => {
      if (this.m.active && this.m.beta === null) {
        App.toast?.('Kein Neigungssensor — bitte Maße manuell eingeben', 'error');
        this.stopMeasure();
      }
    }, 2000);

    this._updateMeasureUI();
  },

  stopMeasure() {
    this.m.active = false;
    if (this.m.handler) {
      window.removeEventListener('deviceorientation', this.m.handler);
      this.m.handler = null;
    }
    const overlay = document.getElementById('measureOverlay');
    if (overlay) overlay.style.display = 'none';
  },

  _onOrientation(e) {
    if (e.beta == null || !this.m.active) return;
    this.m.beta = e.beta;
    const d = this._measureDistance();

    // Rolling stability: keep last 12 readings, stable if spread < 12 cm
    if (d > 0) {
      this.m.history.push(d);
      if (this.m.history.length > 12) this.m.history.shift();
      if (this.m.history.length >= 6) {
        const avg  = this.m.history.reduce((a, b) => a + b, 0) / this.m.history.length;
        const maxDev = Math.max(...this.m.history.map(v => Math.abs(v - avg)));
        this.m.stable = maxDev < 0.12;
      } else {
        this.m.stable = false;
      }
    } else {
      this.m.history = [];
      this.m.stable  = false;
    }

    // Update readout
    const readout = document.getElementById('measureReadout');
    if (readout) {
      readout.textContent  = d > 0 ? d.toFixed(2) + ' m' : '— m';
      readout.style.color  = this.m.stable ? '#4CAF50' : '#4FC3F7';
    }
    const badge = document.getElementById('measStable');
    if (badge) badge.style.visibility = this.m.stable ? 'visible' : 'hidden';
  },

  _measureDistance() {
    const b = this.m.beta;
    // beta: 0=flat, 90=upright. Valid aiming range: ~30–85°
    if (b == null || b < 15 || b > 87) return 0;
    return this.m.camHeight * Math.tan(b * Math.PI / 180);
  },

  captureMeasure() {
    const d = this._measureDistance();
    if (d <= 0) {
      App.toast?.('Handy etwas nach vorne neigen um die Wand anzuvisieren', 'error');
      return;
    }
    this.m.dists.push(d);
    this.m.step++;
    this.m.history = [];
    this.m.stable  = false;

    if (this.m.step >= 2) {
      this._finishMeasure();
    } else {
      this._updateMeasureUI();
    }
  },

  _finishMeasure() {
    const width = +this.m.dists[0].toFixed(2);
    const depth = +this.m.dists[1].toFixed(2);

    const wEl = document.getElementById('camWidth');
    const dEl = document.getElementById('camDepth');
    if (wEl) wEl.value = width;
    if (dEl) dEl.value = depth;

    this._drawRoomSketch();
    this.stopMeasure();
    App.toast?.(`📐 Gemessen: ${width.toFixed(2)} × ${depth.toFixed(2)} m`, 'success');
  },

  _updateMeasureUI() {
    const step = this.m.step; // 0 = width, 1 = depth

    // Dot indicators
    const dot1 = document.getElementById('measDot1');
    const dot2 = document.getElementById('measDot2');
    if (dot1) { dot1.classList.toggle('active', step === 0); dot1.classList.toggle('done', step > 0); }
    if (dot2) { dot2.classList.toggle('active', step === 1); dot2.classList.toggle('done', step > 1); }

    // Label
    const label = document.getElementById('measLabel');
    if (label) label.textContent = step === 0 ? 'Schritt 1 · Breite messen' : 'Schritt 2 · Tiefe messen';

    // Instruction
    const instr = document.getElementById('measureInstruction');
    if (instr) {
      instr.innerHTML = step === 0
        ? 'Stell dich direkt an <strong>Wand A</strong>.<br>Neige das Handy leicht nach vorne auf die gegenüberliegende Wand.'
        : 'Dreh dich um <strong>90°</strong>.<br>Stell dich an die nächste Wand und zeige auf die gegenüberliegende.';
    }

    // Reset readout
    const readout = document.getElementById('measureReadout');
    if (readout) { readout.textContent = '— m'; readout.style.color = '#4FC3F7'; }
    const badge = document.getElementById('measStable');
    if (badge) badge.style.visibility = 'hidden';

    // Update diagram SVG
    const content = document.getElementById('measDiagramContent');
    if (content) {
      content.innerHTML = step === 0
        // Step 1: person at bottom wall, arrow points up
        ? `<line x1="8" y1="8" x2="152" y2="8" stroke="#4FC3F7" stroke-width="3.5"/>
           <text x="80" y="6" text-anchor="middle" fill="#4FC3F7" font-size="7" font-family="sans-serif">Wand B</text>
           <text x="80" y="94" text-anchor="middle" fill="rgba(79,195,247,.55)" font-size="7" font-family="sans-serif">Wand A (du stehst hier)</text>
           <circle cx="80" cy="80" r="7" fill="#4FC3F7"/>
           <line x1="80" y1="72" x2="80" y2="18" stroke="#4FC3F7" stroke-width="2.5" marker-end="url(#mArrow)"/>
           <text x="94" y="50" fill="rgba(255,255,255,.5)" font-size="9" font-family="sans-serif" font-style="italic">Breite</text>`
        // Step 2: person at right wall, arrow points left
        : `<line x1="8" y1="8" x2="8" y2="88" stroke="#4FC3F7" stroke-width="3.5"/>
           <text x="6" y="50" text-anchor="middle" fill="#4FC3F7" font-size="7" font-family="sans-serif" transform="rotate(-90,6,50)">Wand C</text>
           <text x="158" y="50" text-anchor="middle" fill="rgba(79,195,247,.55)" font-size="7" font-family="sans-serif" transform="rotate(-90,158,50)">hier</text>
           <circle cx="144" cy="48" r="7" fill="#4FC3F7"/>
           <line x1="136" y1="48" x2="20" y2="48" stroke="#4FC3F7" stroke-width="2.5" marker-end="url(#mArrow)"/>
           <text x="80" y="40" text-anchor="middle" fill="rgba(255,255,255,.5)" font-size="9" font-family="sans-serif" font-style="italic">Tiefe</text>`;
    }
  },

  cameraConfirm() {
    const w = parseFloat(document.getElementById('camWidth')?.value)  || 0;
    const d = parseFloat(document.getElementById('camDepth')?.value)  || 0;
    const h = parseFloat(document.getElementById('camHeight')?.value) || 2.5;
    this.s.result = {
      width:  w,
      depth:  d,
      height: h,
      area:   +(w * d).toFixed(2),
    };
    this._stopCamera();
    this._showConfirm();
  },

  _drawRoomSketch() {
    const canvas = document.getElementById('sketchCanvas');
    if (!canvas) return;
    const w = parseFloat(document.getElementById('camWidth')?.value)  || 0;
    const d = parseFloat(document.getElementById('camDepth')?.value)  || 0;
    const h = parseFloat(document.getElementById('camHeight')?.value) || 0;
    const W = canvas.offsetWidth  || 248;
    const H = 180;
    canvas.width  = W;
    canvas.height = H;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#0a0a0f';
    ctx.fillRect(0, 0, W, H);

    if (w <= 0 || d <= 0) {
      ctx.fillStyle = 'rgba(255,255,255,.15)';
      ctx.font = '13px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('Breite und Tiefe eingeben …', W / 2, H / 2);
      return;
    }

    const pad = 28;
    const maxW = W - pad * 2;
    const maxH = H - pad * 2;
    const scale = Math.min(maxW / w, maxH / d);
    const rw = w * scale;
    const rd = d * scale;
    const rx = (W - rw) / 2;
    const ry = (H - rd) / 2;

    // Room shape
    ctx.strokeStyle = '#4FC3F7';
    ctx.lineWidth = 2;
    ctx.fillStyle = 'rgba(79,195,247,0.08)';
    ctx.beginPath();
    ctx.rect(rx, ry, rw, rd);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#4FC3F7';
    ctx.font = 'bold 12px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    // Width label (top)
    ctx.fillText(w.toFixed(2) + ' m', W / 2, ry - 10);
    // Depth label (right)
    ctx.save();
    ctx.translate(rx + rw + 12, H / 2);
    ctx.rotate(Math.PI / 2);
    ctx.fillText(d.toFixed(2) + ' m', 0, 0);
    ctx.restore();
    // Area label (center)
    ctx.fillStyle = 'rgba(255,255,255,.6)';
    ctx.font = '13px sans-serif';
    ctx.fillText((w * d).toFixed(1) + ' m²', W / 2, H / 2);
    if (h > 0) {
      ctx.fillStyle = 'rgba(255,255,255,.35)';
      ctx.font = '11px sans-serif';
      ctx.fillText('h = ' + h.toFixed(2) + ' m', W / 2, H / 2 + 18);
    }
  },

  // ── File Import Mode ───────────────────────────────────
  _setupFilePanel() {
    const dropZone = document.getElementById('fileDropZone');
    const input    = document.getElementById('fileInput');
    if (!dropZone || !input) return;

    dropZone.addEventListener('click', () => input.click());
    dropZone.addEventListener('dragover', e => {
      e.preventDefault();
      dropZone.classList.add('dragover');
    });
    dropZone.addEventListener('dragleave', () => dropZone.classList.remove('dragover'));
    dropZone.addEventListener('drop', e => {
      e.preventDefault();
      dropZone.classList.remove('dragover');
      const file = e.dataTransfer.files[0];
      if (file) this._loadFile(file);
    });
    input.addEventListener('change', e => {
      if (e.target.files[0]) this._loadFile(e.target.files[0]);
    });
  },

  async _loadFile(file) {
    const name = file.name.toLowerCase();
    const progressEl = document.getElementById('parseProgress');
    const dropZone   = document.getElementById('fileDropZone');
    progressEl.classList.add('active');
    dropZone.style.display = 'none';

    try {
      let points;
      if (name.endsWith('.ply'))      points = await this._parsePLY(file, progressEl);
      else if (name.endsWith('.xyz')) points = await this._parseXYZ(file, progressEl);
      else if (name.endsWith('.obj')) points = await this._parseOBJ(file, progressEl);
      else throw new Error('Format nicht unterstützt. Bitte PLY, XYZ oder OBJ.');

      let bounds = this._calcBounds(points);

      // Sanity check: real rooms are < ~100 m. Garbage (wrong byte layout)
      // produces values like 6e+38. If detected, drop outliers and retry.
      if (!this._boundsPlausible(bounds)) {
        points = this._filterOutliers(points);
        bounds = this._calcBounds(points);
      }
      if (!this._boundsPlausible(bounds)) {
        throw new Error('Die Datei konnte nicht korrekt gelesen werden (ungültige Koordinaten). '
          + 'Bitte exportiere in Scaniverse als PLY (Mesh) und versuche es erneut. '
          + 'Falls es weiter klemmt: schick mir die ersten Zeilen der Datei.');
      }

      this.s.pcPoints = points;
      this.s.pcBounds = bounds;
      progressEl.classList.remove('active');
      this._showPointCloud(points, bounds);
    } catch (err) {
      progressEl.classList.remove('active');
      dropZone.style.display = 'flex';
      alert('Fehler: ' + err.message);
    }
  },

  _boundsPlausible(b) {
    return [b.w, b.h, b.d].every(v => isFinite(v) && v > 0.05 && v < 200);
  },

  // Drop points whose coordinates are far outside the robust median range
  _filterOutliers(points) {
    const med = (arr) => {
      const s = arr.slice().sort((a, b) => a - b);
      return s[Math.floor(s.length / 2)];
    };
    const xs = points.map(p => p.x).filter(isFinite);
    const ys = points.map(p => p.y).filter(isFinite);
    const zs = points.map(p => p.z).filter(isFinite);
    if (!xs.length) return points;
    const mx = med(xs), my = med(ys), mz = med(zs);
    const R = 100; // metres from median centre
    return points.filter(p =>
      isFinite(p.x) && isFinite(p.y) && isFinite(p.z) &&
      Math.abs(p.x - mx) < R && Math.abs(p.y - my) < R && Math.abs(p.z - mz) < R);
  },

  async _parsePLY(file, progEl) {
    const buf = await file.arrayBuffer();
    const header = this._readPLYHeader(buf);
    this._setProgress(progEl, 30);

    const pts = [];
    if (header.format === 'ascii') {
      const text = new TextDecoder().decode(buf);
      const lines = text.slice(header.dataOffset).split('\n');
      const max = Math.min(header.vertexCount, 100000);
      for (let i = 0; i < max && i < lines.length; i++) {
        const parts = lines[i].trim().split(/\s+/);
        if (parts.length >= 3) {
          const x = parseFloat(parts[header.xIdx]);
          const y = parseFloat(parts[header.yIdx]);
          const z = parseFloat(parts[header.zIdx]);
          if (isFinite(x) && isFinite(y) && isFinite(z)) pts.push({ x, y, z });
        }
        if (i % 10000 === 0) this._setProgress(progEl, 30 + (i / max) * 65);
      }
    } else {
      // Binary little-endian
      const view   = new DataView(buf, header.dataOffset);
      const stride = header.stride;
      const max    = Math.min(header.vertexCount, 100000);
      const readF  = (off, type) => {
        if (type === 'double')                          return view.getFloat64(off, true);
        if (type === 'int'   || type === 'int32')       return view.getInt32(off, true);
        if (type === 'uint'  || type === 'uint32')      return view.getUint32(off, true);
        if (type === 'short' || type === 'int16')       return view.getInt16(off, true);
        if (type === 'ushort'|| type === 'uint16')      return view.getUint16(off, true);
        if (type === 'uchar' || type === 'uint8')       return view.getUint8(off);
        if (type === 'char'  || type === 'int8')        return view.getInt8(off);
        return view.getFloat32(off, true); // float, float32
      };
      for (let i = 0; i < max; i++) {
        const base = i * stride;
        const x = readF(base + header.xOff, header.xType);
        const y = readF(base + header.yOff, header.yType);
        const z = readF(base + header.zOff, header.zType);
        if (isFinite(x) && isFinite(y) && isFinite(z)) pts.push({ x, y, z });
        if (i % 10000 === 0) this._setProgress(progEl, 30 + (i / max) * 65);
      }
    }

    this._setProgress(progEl, 100);
    if (pts.length === 0) throw new Error('Keine Punkte gefunden.');
    return pts;
  },

  _readPLYHeader(buf) {
    const bytes = new Uint8Array(buf);

    // Find exact byte offset of data: search raw bytes for "end_header" + newline.
    // This avoids all \n vs \r\n length-calculation bugs.
    const needle = 'end_header';
    let dataOffset = -1;
    const limit = Math.min(bytes.length - needle.length, 65536);
    for (let i = 0; i < limit; i++) {
      let match = true;
      for (let k = 0; k < needle.length; k++) {
        if (bytes[i + k] !== needle.charCodeAt(k)) { match = false; break; }
      }
      if (match) {
        // Skip past "end_header" and the following newline (\n or \r\n)
        let j = i + needle.length;
        if (bytes[j] === 0x0d) j++; // CR
        if (bytes[j] === 0x0a) j++; // LF
        dataOffset = j;
        break;
      }
    }

    // Parse the textual header portion
    const headerTxt = new TextDecoder().decode(bytes.slice(0, dataOffset > 0 ? dataOffset : 8192));
    const lines = headerTxt.split('\n');
    let format = 'ascii', vertexCount = 0, props = [];
    let inVertex = false;

    for (const rawLine of lines) {
      const l = rawLine.trim();
      if (l.startsWith('format binary_little_endian')) format = 'binary';
      if (l.startsWith('format binary_big_endian'))    format = 'binary_be';
      if (l.startsWith('format ascii'))                format = 'ascii';
      if (l.startsWith('element vertex')) { vertexCount = parseInt(l.split(/\s+/)[2]); inVertex = true; }
      else if (l.startsWith('element'))  { inVertex = false; }
      if (inVertex && l.startsWith('property') && !l.startsWith('property list')) {
        const parts = l.split(/\s+/);
        const typeName = parts[1];
        const propName = parts[2];
        const size = (typeName === 'double' || typeName === 'float64')             ? 8
                   : (typeName === 'uchar'  || typeName === 'uint8'
                   || typeName === 'char'   || typeName === 'int8')                ? 1
                   : (typeName === 'ushort' || typeName === 'uint16'
                   || typeName === 'short'  || typeName === 'int16')               ? 2
                   : 4; // float, float32, int, uint, int32, uint32
        props.push({ name: propName, type: typeName, size });
      }
      if (l === 'end_header') break;
    }

    // Calculate per-property byte offsets
    let offset = 0;
    for (const p of props) { p.offset = offset; offset += p.size; }
    const stride = offset;

    const xP = props.find(p => p.name === 'x');
    const yP = props.find(p => p.name === 'y');
    const zP = props.find(p => p.name === 'z');

    return {
      format,
      vertexCount,
      dataOffset: dataOffset > 0 ? dataOffset : 0,
      xIdx: props.findIndex(p => p.name === 'x'),
      yIdx: props.findIndex(p => p.name === 'y'),
      zIdx: props.findIndex(p => p.name === 'z'),
      xOff:  xP?.offset ?? 0,
      yOff:  yP?.offset ?? 4,
      zOff:  zP?.offset ?? 8,
      xType: xP?.type ?? 'float',
      yType: yP?.type ?? 'float',
      zType: zP?.type ?? 'float',
      stride,
    };
  },

  async _parseXYZ(file, progEl) {
    const text = await file.text();
    const lines = text.split('\n');
    const max = Math.min(lines.length, 100000);
    const pts = [];
    for (let i = 0; i < max; i++) {
      const parts = lines[i].trim().split(/[\s,;]+/);
      if (parts.length >= 3) {
        const x = parseFloat(parts[0]);
        const y = parseFloat(parts[1]);
        const z = parseFloat(parts[2]);
        if (!isNaN(x) && !isNaN(y) && !isNaN(z)) pts.push({ x, y, z });
      }
      if (i % 10000 === 0) this._setProgress(progEl, (i / max) * 100);
    }
    if (pts.length === 0) throw new Error('Keine Punkte gefunden.');
    return pts;
  },

  async _parseOBJ(file, progEl) {
    const text = await file.text();
    const lines = text.split('\n');
    const pts = [];
    const max = Math.min(lines.length, 200000);
    for (let i = 0; i < max; i++) {
      if (lines[i].startsWith('v ')) {
        const parts = lines[i].trim().split(/\s+/);
        const x = parseFloat(parts[1]);
        const y = parseFloat(parts[2]);
        const z = parseFloat(parts[3]);
        if (!isNaN(x) && !isNaN(y) && !isNaN(z)) pts.push({ x, y, z });
      }
      if (i % 20000 === 0) this._setProgress(progEl, (i / max) * 100);
    }
    if (pts.length === 0) throw new Error('Keine Vertices gefunden.');
    return pts;
  },

  _setProgress(el, pct) {
    const fill = el?.querySelector('.progress-bar-fill');
    if (fill) fill.style.width = pct + '%';
    const label = el?.querySelector('.parse-status');
    if (label) label.textContent = `Verarbeite Punktwolke … ${Math.round(pct)}%`;
  },

  _calcBounds(pts) {
    // Robust percentile bounds — ignores scan-outliers (stray points below floor etc.)
    const pct = (arr, p) => arr[Math.max(0, Math.min(arr.length - 1, Math.floor(arr.length * p)))];
    const xs = pts.map(p => p.x).sort((a, b) => a - b);
    const ys = pts.map(p => p.y).sort((a, b) => a - b);
    const zs = pts.map(p => p.z).sort((a, b) => a - b);
    const minX = pct(xs, 0.01), maxX = pct(xs, 0.99);
    const minY = pct(ys, 0.02), maxY = pct(ys, 0.98);
    const minZ = pct(zs, 0.01), maxZ = pct(zs, 0.99);
    return {
      minX, maxX, minY, maxY, minZ, maxZ,
      w: maxX - minX,
      h: maxY - minY,
      d: maxZ - minZ,
    };
  },

  _showPointCloud(pts, b) {
    // Hide upload, show viewer
    document.getElementById('pcViewerWrap').style.display = 'flex';

    // Dims
    const sideX = Math.max(b.w, b.d);
    const sideY = b.h;
    // Determine which axis is "up" (tallest in smallest horizontal range = height)
    const dim1 = b.w.toFixed(2), dim2 = b.d.toFixed(2), dim3 = b.h.toFixed(2);

    document.getElementById('pcStatPoints').textContent = pts.length.toLocaleString('de');
    document.getElementById('pcStatDim').textContent  = `${dim1} × ${dim2} × ${dim3} m`;
    document.getElementById('pcStatW').textContent    = dim1 + ' m';
    document.getElementById('pcStatD').textContent    = dim2 + ' m';
    document.getElementById('pcStatH').textContent    = dim3 + ' m';
    document.getElementById('pcStatArea').textContent = (b.w * b.d).toFixed(1) + ' m²';

    this.s.result = {
      width:  b.w,
      depth:  b.d,
      height: b.h,
      area:   +(b.w * b.d).toFixed(2),
    };

    this._initPCCanvas(pts, b);
  },

  _initPCCanvas(pts, b) {
    const canvas = document.getElementById('pcCanvas');
    if (!canvas) return;

    // Subsample to max 40k points for rendering
    let renderPts = pts;
    if (pts.length > 40000) {
      const step = Math.ceil(pts.length / 40000);
      renderPts = pts.filter((_, i) => i % step === 0);
    }

    // Normalize to [-1, 1]
    const cx = (b.minX + b.maxX) / 2;
    const cy = (b.minY + b.maxY) / 2;
    const cz = (b.minZ + b.maxZ) / 2;
    const scale = 2 / Math.max(b.w, b.h, b.d);
    const nPts = renderPts.map(p => ({
      x: (p.x - cx) * scale,
      y: (p.y - cy) * scale,
      z: (p.z - cz) * scale,
    }));

    const draw = () => {
      const W = canvas.offsetWidth || 400;
      const H = canvas.offsetHeight || 300;
      canvas.width = W; canvas.height = H;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#000';
      ctx.fillRect(0, 0, W, H);

      const rx = this.s.pcRotX;
      const ry = this.s.pcRotY;
      const cosX = Math.cos(rx), sinX = Math.sin(rx);
      const cosY = Math.cos(ry), sinY = Math.sin(ry);

      const proj = W * 0.35;
      const pts2d = nPts.map(p => {
        // Rotate Y
        const x1 =  p.x * cosY + p.z * sinY;
        const z1 = -p.x * sinY + p.z * cosY;
        // Rotate X
        const y2 =  p.y * cosX - z1 * sinX;
        const z2 =  p.y * sinX + z1 * cosX;
        const fov = 1 / (1 + z2 * 0.3 + 1.5);
        return {
          sx: W / 2 + x1 * proj * fov,
          sy: H / 2 - y2 * proj * fov,
          depth: z2,
        };
      });

      // Sort back-to-front for rough depth sorting
      pts2d.sort((a, b) => b.depth - a.depth);

      const minD = Math.min(...pts2d.map(p => p.depth));
      const maxD = Math.max(...pts2d.map(p => p.depth));
      const dRange = maxD - minD || 1;

      // Draw as small dots
      for (const p of pts2d) {
        const t = (p.depth - minD) / dRange;
        const r = Math.round(30 + t * 180);
        const g = Math.round(140 + t * 55);
        const b = Math.round(200 - t * 60);
        ctx.fillStyle = `rgb(${r},${g},${b})`;
        ctx.fillRect(p.sx - 0.8, p.sy - 0.8, 1.6, 1.6);
      }

      // Bounding box wireframe
      this._drawBoundingBox(ctx, W, H, proj, rx, ry);
    };

    // Drag to rotate
    let lastX = 0, lastY = 0;
    canvas.addEventListener('mousedown', e => {
      lastX = e.clientX; lastY = e.clientY;
      this.s.pcDragStart = true;
    });
    canvas.addEventListener('mousemove', e => {
      if (!this.s.pcDragStart) return;
      this.s.pcRotY += (e.clientX - lastX) * 0.01;
      this.s.pcRotX += (e.clientY - lastY) * 0.01;
      lastX = e.clientX; lastY = e.clientY;
      draw();
    });
    canvas.addEventListener('mouseup',   () => { this.s.pcDragStart = false; });
    canvas.addEventListener('mouseleave',() => { this.s.pcDragStart = false; });

    // Touch to rotate
    canvas.addEventListener('touchstart', e => {
      lastX = e.touches[0].clientX; lastY = e.touches[0].clientY;
      this.s.pcDragStart = true;
    });
    canvas.addEventListener('touchmove', e => {
      e.preventDefault();
      if (!this.s.pcDragStart) return;
      this.s.pcRotY += (e.touches[0].clientX - lastX) * 0.01;
      this.s.pcRotX += (e.touches[0].clientY - lastY) * 0.01;
      lastX = e.touches[0].clientX; lastY = e.touches[0].clientY;
      draw();
    }, { passive: false });

    draw();
    // Continuous render for initial spin
    let spin = 0;
    const spinAnim = () => {
      if (spin++ < 120) {
        this.s.pcRotY += 0.01;
        draw();
        requestAnimationFrame(spinAnim);
      }
    };
    requestAnimationFrame(spinAnim);
  },

  _drawBoundingBox(ctx, W, H, proj, rx, ry) {
    const cosX = Math.cos(rx), sinX = Math.sin(rx);
    const cosY = Math.cos(ry), sinY = Math.sin(ry);

    const corners = [
      [-1,-1,-1],[ 1,-1,-1],[ 1, 1,-1],[-1, 1,-1],
      [-1,-1, 1],[ 1,-1, 1],[ 1, 1, 1],[-1, 1, 1],
    ];

    const project = ([x, y, z]) => {
      const x1 =  x * cosY + z * sinY;
      const z1 = -x * sinY + z * cosY;
      const y2 =  y * cosX - z1 * sinX;
      const z2 =  y * sinX + z1 * cosX;
      const fov = 1 / (1 + z2 * 0.3 + 1.5);
      return [W/2 + x1*proj*fov, H/2 - y2*proj*fov];
    };

    const edges = [
      [0,1],[1,2],[2,3],[3,0],
      [4,5],[5,6],[6,7],[7,4],
      [0,4],[1,5],[2,6],[3,7],
    ];

    ctx.strokeStyle = 'rgba(79,195,247,0.35)';
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 4]);
    for (const [a, b] of edges) {
      const [ax, ay] = project(corners[a]);
      const [bx, by] = project(corners[b]);
      ctx.beginPath();
      ctx.moveTo(ax, ay);
      ctx.lineTo(bx, by);
      ctx.stroke();
    }
    ctx.setLineDash([]);
  },

  fileConfirm() {
    // Run opening detection if we have a point cloud
    if (this.s.pcPoints && this.s.pcBounds) {
      const detected = this._detectOpenings(this.s.pcPoints, this.s.pcBounds);
      this.s.detectedOpenings = detected;
    } else {
      this.s.detectedOpenings = [];
    }
    this._showConfirm();
  },

  // ── Confirm screen ─────────────────────────────────────
  _showConfirm() {
    document.querySelectorAll('.scanner-panel').forEach(p => p.classList.remove('active'));
    document.getElementById('scanPanel_confirm').classList.add('active');

    const r = this.s.result;
    document.getElementById('confirmWidth').textContent  = r.width.toFixed(2)  + ' m';
    document.getElementById('confirmDepth').textContent  = r.depth.toFixed(2)  + ' m';
    document.getElementById('confirmHeight').textContent = r.height.toFixed(2) + ' m';
    document.getElementById('confirmArea').textContent   = (r.area > 0 ? r.area : r.width * r.depth).toFixed(1) + ' m²';

    // Render detected openings
    const openings = this.s.detectedOpenings || [];
    const container = document.getElementById('detectedOpenings');
    if (!container) return;
    if (!openings.length) {
      container.innerHTML = '<div style="color:var(--text-muted);font-size:.82rem;text-align:center;padding:8px 0;">Keine Fenster/Türen automatisch erkannt.<br>Bitte manuell unter Bauteile eintragen.</div>';
      return;
    }
    container.innerHTML = `
      <div style="font-weight:600;margin-bottom:8px;font-size:.9rem;">🔍 Erkannte Öffnungen (${openings.length})</div>
      ${openings.map((o, i) => `
        <label style="display:flex;align-items:center;gap:10px;padding:8px;background:var(--surface);border:1px solid var(--border);border-radius:8px;margin-bottom:6px;cursor:pointer;">
          <input type="checkbox" id="opening_${i}" checked style="width:16px;height:16px;accent-color:var(--primary);">
          <div style="flex:1">
            <div style="font-weight:600;font-size:.85rem;">${o.type === 'door' ? '🚪 Außentür' : '🪟 Fenster'} – ${o.wall}</div>
            <div style="font-size:.78rem;color:var(--text-muted);">${o.width.toFixed(2)} m × ${o.height.toFixed(2)} m = ${o.area.toFixed(2)} m²${o.type === 'window' ? ' · Brüstung ~' + o.sillHeight.toFixed(2) + ' m' : ''}</div>
          </div>
          <div style="font-size:.75rem;color:var(--primary);font-weight:600;">U = ${o.uDefault.toFixed(2)}</div>
        </label>
      `).join('')}
    `;
  },

  confirmApply() {
    const r = this.s.result;
    const area = r.area > 0 ? r.area : +(r.width * r.depth).toFixed(2);

    // Push room dimensions
    const areaEl   = document.getElementById('rArea');
    const heightEl = document.getElementById('rHeight');
    if (areaEl)   areaEl.value  = area.toFixed(1);
    if (heightEl) heightEl.value = r.height.toFixed(2);
    App.onRoomFormChange?.();

    // Add checked openings as components
    const openings = this.s.detectedOpenings || [];
    const room = App.getRoom?.(window.state?.selectedRoomId);
    let added = 0;
    if (room) {
      openings.forEach((o, i) => {
        const cb = document.getElementById('opening_' + i);
        if (!cb?.checked) return;
        room.components.push({
          id: 'id_sc_' + Date.now() + '_' + i,
          type: o.type === 'door' ? 'door' : 'window',
          description: o.type === 'door' ? ('Tür ' + o.wall) : ('Fenster ' + o.wall),
          area: +o.area.toFixed(2),
          uValue: o.uDefault,
          adjacentTemp: null,
        });
        added++;
      });
      if (added) {
        App.render?.();
        App.renderRoomDetail?.();
        App._autoSave?.();
      }
    }

    const msg = `Raummaße übernommen: ${area.toFixed(1)} m² · h=${r.height.toFixed(2)} m` +
                (added ? ` · ${added} Bauteil${added > 1 ? 'e' : ''} hinzugefügt` : '');
    App.toast?.(msg, 'success');
    this.close();
  },

  // ── Window / Door Detection from Point Cloud ───────────
  _detectOpenings(pts, bounds) {
    const WALL_THR = 0.14; // max distance from wall face [m]
    const GRID     = 0.07; // grid cell size [m]
    const MIN_W    = 0.35; // min opening width [m]
    const MIN_H    = 0.35; // min opening height [m]
    const MAX_H    = 2.80; // max opening height [m]
    const DENSITY  = 0.08; // occupied if ≥ this fraction of nearby wall pts

    const floorY = bounds.minY;
    const roomH  = bounds.maxY - bounds.minY;
    if (roomH < 1.5) return []; // bad scan

    const year = parseInt(window.state?.project?.constructionYear) || 2000;
    const getUDefault = (type) => {
      if (type === 'window') return year < 1975 ? 2.80 : year < 1995 ? 1.80 : year < 2010 ? 1.10 : 0.70;
      return year < 1990 ? 3.00 : year < 2010 ? 1.80 : 0.90;
    };

    const wallDefs = [
      { name: 'Nordwand', ai: 2, fv: bounds.minZ, ui: 0, uMin: bounds.minX, uMax: bounds.maxX },
      { name: 'Südwand',  ai: 2, fv: bounds.maxZ, ui: 0, uMin: bounds.minX, uMax: bounds.maxX },
      { name: 'Westwand', ai: 0, fv: bounds.minX, ui: 2, uMin: bounds.minZ, uMax: bounds.maxZ },
      { name: 'Ostwand',  ai: 0, fv: bounds.maxX, ui: 2, uMin: bounds.minZ, uMax: bounds.maxZ },
    ];

    const results = [];

    for (const w of wallDefs) {
      const cols = Math.max(1, Math.ceil((w.uMax - w.uMin) / GRID));
      const rows = Math.max(1, Math.ceil(roomH / GRID));
      const occ  = new Float32Array(cols * rows); // sum of near-wall pts per cell
      const tot  = new Float32Array(cols * rows); // total pts per cell (any depth)
      let wallPts = 0;

      const n = pts.length / 3;
      for (let k = 0; k < n; k++) {
        const ax = pts[k*3 + w.ai];
        const ux = pts[k*3 + w.ui];
        const vy = pts[k*3 + 1] - floorY;
        if (vy < -0.1 || vy > roomH + 0.1) continue;
        const ci = Math.min(cols-1, Math.max(0, Math.floor((ux - w.uMin) / GRID)));
        const ri = Math.min(rows-1, Math.max(0, Math.floor(vy / GRID)));
        tot[ri * cols + ci]++;
        if (Math.abs(ax - w.fv) < WALL_THR) { occ[ri * cols + ci]++; wallPts++; }
      }
      if (wallPts < 150) continue; // not enough data for this wall

      // Build binary occupancy: cell is "wall" if enough wall pts relative to total
      const wall = new Uint8Array(cols * rows);
      for (let c = 0; c < cols * rows; c++) {
        if (tot[c] > 0 && occ[c] / tot[c] >= DENSITY) wall[c] = 1;
      }

      // For each column: find vertical void spans (runs of empty rows surrounded by wall rows)
      const colVoids = [];
      for (let ci = 0; ci < cols; ci++) {
        const colVoid = [];
        let vStart = -1;
        for (let ri = 0; ri <= rows; ri++) {
          const isWall = ri < rows && wall[ri * cols + ci] === 1;
          if (!isWall && vStart < 0) { vStart = ri; }
          if (isWall && vStart >= 0) {
            const h = (ri - vStart) * GRID;
            if (h >= MIN_H && h <= MAX_H) {
              colVoid.push({ rStart: vStart, rEnd: ri, h });
            }
            vStart = -1;
          }
        }
        colVoids.push(colVoid);
      }

      // Merge adjacent columns with matching voids → rectangular openings
      const used = new Set();
      for (let ci = 0; ci < cols; ci++) {
        for (let vi = 0; vi < colVoids[ci].length; vi++) {
          const key = `${ci}_${vi}`;
          if (used.has(key)) continue;
          const base = colVoids[ci][vi];

          // Extend right as long as columns have matching void
          let ciEnd = ci;
          while (ciEnd + 1 < cols) {
            const next = colVoids[ciEnd + 1].find(v =>
              Math.abs(v.rStart - base.rStart) <= 1 && Math.abs(v.rEnd - base.rEnd) <= 1);
            if (!next) break;
            ciEnd++;
          }

          const width = (ciEnd - ci + 1) * GRID;
          if (width < MIN_W) continue;

          // Mark as used
          for (let c2 = ci; c2 <= ciEnd; c2++) {
            const match = colVoids[c2].findIndex(v =>
              Math.abs(v.rStart - base.rStart) <= 1 && Math.abs(v.rEnd - base.rEnd) <= 1);
            if (match >= 0) used.add(`${c2}_${match}`);
          }

          const sillH = base.rStart * GRID;
          const openH = base.h;
          const type  = sillH < 0.15 && openH > 1.8 ? 'door' : 'window';
          const uCtr  = w.uMin + (ci + (ciEnd - ci) / 2) * GRID;

          results.push({
            wall:        w.name,
            type,
            width:       +width.toFixed(2),
            height:      +openH.toFixed(2),
            area:        +(width * openH).toFixed(2),
            sillHeight:  +sillH.toFixed(2),
            uCenter:     +uCtr.toFixed(2),
            uDefault:    getUDefault(type),
          });
        }
      }
    }

    // Sort: doors first, then by area descending
    results.sort((a, b) => (a.type === 'door' ? 0 : 1) - (b.type === 'door' ? 0 : 1) || b.area - a.area);
    return results;
  },

  // ── Utils ──────────────────────────────────────────────
  _dist3D(a, b) {
    return Math.sqrt((a.x-b.x)**2 + (a.y-b.y)**2 + (a.z-b.z)**2);
  },
};
