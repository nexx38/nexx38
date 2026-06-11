/* ────────────────────────────────────────────────────────
   HeizlastProfi — LiDAR / AR Room Scanner
   Modes:
     1. AR     — WebXR immersive-ar + hit-testing (Android Chrome)
     2. Camera — camera preview + guided manual entry
     3. File   — PLY / XYZ / OBJ point cloud import
   ──────────────────────────────────────────────────────── */

const Scanner = {

  // ── State ──────────────────────────────────────────────
  s: {
    mode: null,          // 'ar' | 'camera' | 'file'
    roomId: null,
    xrSession: null,
    hitTestSource: null,
    refSpace: null,
    viewerSpace: null,
    cameraStream: null,
    floorPoints: [],     // [{x,y,z}]  world-space floor corners
    lastHitPos: null,    // current crosshair position
    viewInfo: null,      // {viewMatrix, projMatrix, viewport} for projection
    result: { width: 0, depth: 0, height: 2.50, area: 0 },
    pcPoints: null,      // parsed point cloud [{x,y,z}]
    pcBounds: null,
    pcRotX: 0.4,
    pcRotY: 0,
    pcDragStart: null,
    arActive: false,
    animFrame: null,
    detectedOpenings: [],
  },

  // ── Open / Close ───────────────────────────────────────
  async open(roomId) {
    this.s.roomId = roomId;
    this.s.floorPoints = [];
    this.s.result = { width: 0, depth: 0, height: 2.50, area: 0 };
    document.getElementById('scannerOverlay').classList.add('active');

    // Detect support
    const arOk = await this._checkAR();
    const camOk = !!(navigator.mediaDevices?.getUserMedia);

    const arTab = document.getElementById('scanTabAR');
    if (!arOk) {
      arTab.disabled = true;
      arTab.title = 'Erfordert Android Chrome + ARCore';
    }

    this.switchMode(arOk ? 'ar' : (camOk ? 'camera' : 'file'));
  },

  close() {
    this._stopAR();
    this._stopCamera();
    if (this.s.animFrame) { cancelAnimationFrame(this.s.animFrame); this.s.animFrame = null; }
    document.getElementById('scannerOverlay').classList.remove('active');
    this.s.mode = null;
  },

  // ── Mode switching ─────────────────────────────────────
  async switchMode(mode) {
    if (this.s.mode === mode) return;

    // Stop previous mode
    this._stopAR();
    this._stopCamera();

    this.s.mode = mode;
    this.s.floorPoints = [];
    this.s.detectedOpenings = [];

    // Update tabs
    document.querySelectorAll('.scanner-tab').forEach(t => t.classList.toggle('active', t.dataset.mode === mode));

    // Update panels
    document.querySelectorAll('.scanner-panel').forEach(p => p.classList.remove('active'));
    document.getElementById('scanPanel_' + mode).classList.add('active');

    if (mode === 'ar')     await this._startAR();
    if (mode === 'camera') await this._startCamera();
    if (mode === 'file')   this._setupFilePanel();
  },

  // ── AR Mode ────────────────────────────────────────────
  async _checkAR() {
    try {
      return navigator.xr
        ? await navigator.xr.isSessionSupported('immersive-ar')
        : false;
    } catch { return false; }
  },

  async _startAR() {
    const container = document.getElementById('arNotSupported');
    const viewport  = document.getElementById('arViewport');

    const ok = await this._checkAR();
    if (!ok) {
      container.style.display = 'flex';
      viewport.style.display  = 'none';
      return;
    }
    container.style.display = 'none';
    viewport.style.display  = 'block';

    try {
      const session = await navigator.xr.requestSession('immersive-ar', {
        requiredFeatures: ['hit-testing'],
        optionalFeatures: ['dom-overlay', 'depth-sensing'],
        domOverlay: { root: document.getElementById('arOverlayUI') },
      });
      this.s.xrSession = session;
      this.s.arActive  = true;

      this.s.refSpace    = await session.requestReferenceSpace('local');
      this.s.viewerSpace = await session.requestReferenceSpace('viewer');
      this.s.hitTestSource = await session.requestHitTestSource({ space: this.s.viewerSpace });

      // WebGL context for XR rendering (canvas is just for 2D overlay drawing)
      const canvas = document.getElementById('arCanvas');
      const gl = canvas.getContext('webgl', { xrCompatible: true });
      await gl.makeXRCompatible?.();
      session.updateRenderState({ baseLayer: new XRWebGLLayer(session, gl) });

      session.addEventListener('select', () => this._onARSelect());
      session.addEventListener('end', () => { this.s.arActive = false; });

      this._arLoop();
      this._updateARUI();
    } catch (err) {
      console.warn('AR session failed:', err);
      // Auto-fallback to camera mode if AR session creation fails
      await this.switchMode('camera');
    }
  },

  _arLoop() {
    if (!this.s.xrSession || !this.s.arActive) return;
    this.s.xrSession.requestAnimationFrame((time, frame) => {
      this._onARFrame(frame);
      if (this.s.arActive) this._arLoop();
    });
  },

  _onARFrame(frame) {
    const session = this.s.xrSession;
    if (!session || !this.s.hitTestSource) return;

    const hits = frame.getHitTestResults(this.s.hitTestSource);
    const canvas = document.getElementById('arCanvas');
    const ctx = canvas.getContext('2d');

    // Resize canvas to session viewport
    const layer = session.renderState.baseLayer;
    if (layer) {
      canvas.width  = layer.framebufferWidth;
      canvas.height = layer.framebufferHeight;
    }

    // Store viewer pose for screen-space projection
    const viewerPose = frame.getViewerPose(this.s.refSpace);
    if (viewerPose) {
      const view = viewerPose.views[0];
      this.s.viewInfo = {
        viewMatrix: view.transform.inverse.matrix,
        projMatrix: view.projectionMatrix,
        w: canvas.width,
        h: canvas.height,
      };
    }

    if (hits.length > 0) {
      const pose = hits[0].getPose(this.s.refSpace);
      this.s.lastHitPos = { ...pose.transform.position };
      this._moveCrosshair(true);
    } else {
      this._moveCrosshair(false);
    }

    // Draw overlay
    this._drawAROverlay(ctx, canvas.width, canvas.height);
  },

  _onARSelect() {
    if (!this.s.lastHitPos) return;
    const pts = this.s.floorPoints;
    if (pts.length >= 4) return;

    pts.push({ ...this.s.lastHitPos });
    this._calcARDimensions();
    this._updateARUI();
  },

  _drawAROverlay(ctx, w, h) {
    ctx.clearRect(0, 0, w, h);
    if (!this.s.viewInfo) return;

    const pts = this.s.floorPoints;
    const screenPts = pts.map(p => this._worldToScreen(p));

    // Draw lines between floor points
    if (screenPts.length > 1) {
      ctx.beginPath();
      ctx.strokeStyle = 'rgba(79,195,247,0.9)';
      ctx.lineWidth = 3;
      ctx.setLineDash([]);
      screenPts.forEach((sp, i) => {
        if (!sp) return;
        i === 0 ? ctx.moveTo(sp.x, sp.y) : ctx.lineTo(sp.x, sp.y);
      });
      if (screenPts.length === 4) ctx.closePath();
      ctx.stroke();

      // Fill polygon
      if (screenPts.length >= 3) {
        ctx.beginPath();
        screenPts.forEach((sp, i) => {
          if (!sp) return;
          i === 0 ? ctx.moveTo(sp.x, sp.y) : ctx.lineTo(sp.x, sp.y);
        });
        ctx.closePath();
        ctx.fillStyle = 'rgba(79,195,247,0.12)';
        ctx.fill();
      }
    }

    // Draw distance labels between consecutive points
    for (let i = 0; i < pts.length && i + 1 <= pts.length; i++) {
      const p1 = pts[i];
      const p2 = i < pts.length - 1 ? pts[i + 1] : (pts.length === 4 ? pts[0] : null);
      if (!p2) continue;
      const d = this._dist3D(p1, p2);
      const sp1 = this._worldToScreen(p1);
      const sp2 = this._worldToScreen(p2);
      if (sp1 && sp2) {
        const mx = (sp1.x + sp2.x) / 2;
        const my = (sp1.y + sp2.y) / 2;
        ctx.fillStyle = 'rgba(0,0,0,0.7)';
        ctx.roundRect?.(mx - 28, my - 12, 56, 24, 6);
        ctx.fillRect(mx - 28, my - 12, 56, 24);
        ctx.fillStyle = '#4FC3F7';
        ctx.font = 'bold 14px sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(d.toFixed(2) + ' m', mx, my);
      }
    }

    // Draw floor point dots
    screenPts.forEach((sp, i) => {
      if (!sp) return;
      ctx.beginPath();
      ctx.arc(sp.x, sp.y, 14, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      ctx.fill();
      ctx.beginPath();
      ctx.arc(sp.x, sp.y, 12, 0, Math.PI * 2);
      ctx.fillStyle = '#4FC3F7';
      ctx.fill();
      ctx.fillStyle = '#000';
      ctx.font = 'bold 13px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(i + 1, sp.x, sp.y);
    });

    // Hit test cursor
    if (this.s.lastHitPos) {
      const sp = this._worldToScreen(this.s.lastHitPos);
      if (sp) {
        ctx.beginPath();
        ctx.arc(sp.x, sp.y, 24, 0, Math.PI * 2);
        ctx.strokeStyle = 'rgba(79,195,247,0.7)';
        ctx.lineWidth = 2;
        ctx.setLineDash([6, 4]);
        ctx.stroke();
        ctx.setLineDash([]);
        ctx.beginPath();
        ctx.arc(sp.x, sp.y, 4, 0, Math.PI * 2);
        ctx.fillStyle = '#4FC3F7';
        ctx.fill();
      }
    }
  },

  _worldToScreen(worldPos) {
    const vi = this.s.viewInfo;
    if (!vi) return null;
    const { viewMatrix, projMatrix, w, h } = vi;

    const p = [worldPos.x, worldPos.y, worldPos.z, 1.0];
    const vp = this._m4v4(viewMatrix, p);
    const cp = this._m4v4(projMatrix, vp);
    if (cp[3] <= 0) return null;

    const nx = cp[0] / cp[3];
    const ny = cp[1] / cp[3];
    return {
      x: (nx + 1) * 0.5 * w,
      y: (1 - ny) * 0.5 * h,
    };
  },

  _m4v4(m, v) {
    return [
      m[0]*v[0] + m[4]*v[1] + m[8]*v[2]  + m[12]*v[3],
      m[1]*v[0] + m[5]*v[1] + m[9]*v[2]  + m[13]*v[3],
      m[2]*v[0] + m[6]*v[1] + m[10]*v[2] + m[14]*v[3],
      m[3]*v[0] + m[7]*v[1] + m[11]*v[2] + m[15]*v[3],
    ];
  },

  _moveCrosshair(active) {
    const el = document.getElementById('arCrosshair');
    if (el) el.style.opacity = active ? '1' : '0.3';
  },

  _calcARDimensions() {
    const pts = this.s.floorPoints;
    if (pts.length < 2) return;

    // With 2 points: just a length measurement
    if (pts.length === 2) {
      this.s.result.width = this._dist3D(pts[0], pts[1]);
      this.s.result.area  = 0;
    }
    // With 3+ points: compute polygon area in xz plane
    if (pts.length >= 3) {
      // Shoelace formula in xz plane
      let area = 0;
      const n = pts.length;
      for (let i = 0; i < n; i++) {
        const j = (i + 1) % n;
        area += pts[i].x * pts[j].z - pts[j].x * pts[i].z;
      }
      this.s.result.area = Math.abs(area) / 2;

      // Width and depth from bounding box
      const xs = pts.map(p => p.x), zs = pts.map(p => p.z);
      this.s.result.width = Math.max(...xs) - Math.min(...xs);
      this.s.result.depth = Math.max(...zs) - Math.min(...zs);
    }
  },

  _updateARUI() {
    const pts = this.s.floorPoints;
    const n = pts.length;
    const r = this.s.result;

    // Step indicators
    for (let i = 1; i <= 4; i++) {
      const el = document.getElementById('arStep' + i);
      if (!el) continue;
      el.classList.toggle('done',   i <= n);
      el.classList.toggle('active', i === n + 1);
    }

    // Instruction text
    const instr = document.getElementById('arInstruction');
    if (instr) {
      const msgs = [
        'Richte die Kamera auf eine Bodenecke des Raums und tippe',
        'Gehe zur nächsten Ecke und tippe (Ecke 2 von 4)',
        'Gehe zur dritten Ecke und tippe (Ecke 3 von 4)',
        'Gehe zur letzten Ecke und tippe (Ecke 4 von 4)',
        'Messung abgeschlossen — Höhe eingeben und bestätigen',
      ];
      instr.textContent = msgs[Math.min(n, 4)];
    }

    // Stats
    const elW = document.getElementById('arStatW');
    const elD = document.getElementById('arStatD');
    const elA = document.getElementById('arStatA');
    if (elW) elW.textContent = r.width > 0 ? r.width.toFixed(2) + ' m' : '—';
    if (elD) elD.textContent = r.depth > 0 ? r.depth.toFixed(2) + ' m' : '—';
    if (elA) elA.textContent = r.area  > 0 ? r.area.toFixed(1)  + ' m²': '—';

    // Confirm button
    const btn = document.getElementById('arConfirmBtn');
    if (btn) btn.disabled = n < 2;

    // Undo button
    const undoBtn = document.getElementById('arUndoBtn');
    if (undoBtn) undoBtn.disabled = n === 0;
  },

  arUndo() {
    if (this.s.floorPoints.length > 0) {
      this.s.floorPoints.pop();
      this._calcARDimensions();
      this._updateARUI();
    }
  },

  arConfirm() {
    if (this.s.floorPoints.length < 2) return;
    const h = parseFloat(document.getElementById('arHeightInput')?.value) || 2.50;
    this.s.result.height = h;
    this._stopAR();
    this._showConfirm();
  },

  _stopAR() {
    if (this.s.xrSession) {
      this.s.xrSession.end().catch(() => {});
      this.s.xrSession = null;
    }
    this.s.arActive = false;
    this.s.hitTestSource = null;
  },

  _showARError(msg) {
    const el = document.getElementById('arNotSupported');
    if (el) {
      el.style.display = 'flex';
      const p = el.querySelector('p');
      if (p) p.textContent = msg || 'AR wird auf diesem Gerät nicht unterstützt.';
    }
  },

  // ── Camera Mode ────────────────────────────────────────
  async _startCamera() {
    const video       = document.getElementById('cameraVideo');
    const placeholder = document.getElementById('cameraPlaceholder');

    // Try progressively simpler constraints so we always get a stream if a camera exists
    const tries = [
      { video: { facingMode: 'environment', width: { ideal: 1280 }, height: { ideal: 720 } } },
      { video: { facingMode: 'environment' } },
      { video: true },
    ];

    let stream = null, lastErr = null;
    for (const c of tries) {
      try { stream = await navigator.mediaDevices.getUserMedia(c); break; }
      catch (e) { lastErr = e; }
    }

    if (!stream) {
      if (placeholder) {
        placeholder.style.display = 'flex';
        placeholder.querySelector('p') && (placeholder.querySelector('p').textContent =
          (lastErr?.name === 'NotAllowedError')
            ? 'Kamera-Zugriff verweigert – Berechtigung in den Browser-Einstellungen erteilen.'
            : 'Kamera nicht verfügbar (' + (lastErr?.name || 'Fehler') + ')');
      }
      this._drawRoomSketch();
      this._setupCameraListeners();
      return;
    }

    if (video) {
      video.srcObject = stream;
      try { await video.play(); } catch { /* autoplay policy — stream still set */ }
    }
    this.s.cameraStream = stream;
    if (placeholder) placeholder.style.display = 'none';

    this._drawRoomSketch();
    this._setupCameraListeners();
  },

  _stopCamera() {
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
    if (!this.s.detectedOpenings) this.s.detectedOpenings = [];
    this._stopCamera();
    this._showConfirm();
  },

  // ── Camera Photo Analysis (A4 Reference) ──────────────
  capturePhoto() {
    const video    = document.getElementById('cameraVideo');
    const canvas   = document.getElementById('photoCanvas');
    const statusEl = document.getElementById('photoStatus');

    const showStatus = (html) => {
      if (!statusEl) return;
      statusEl.style.display = 'block';
      statusEl.innerHTML = html;
    };

    if (!video || !canvas) { showStatus('⚠️ Interner Fehler: Element fehlt.'); return; }
    if (!this.s.cameraStream) { showStatus('⚠️ Kamera nicht aktiv – Kamera-Zugriff prüfen.'); return; }
    if (video.readyState < 2) { showStatus('⚠️ Kamera lädt noch – kurz warten und nochmal tippen.'); return; }

    showStatus('📷 Foto aufgenommen – analysiere …');

    // videoWidth can be 0 on some mobile browsers even while streaming; fall back to element size
    const W = video.videoWidth  || video.offsetWidth  || 1280;
    const H = video.videoHeight || video.offsetHeight || 720;
    canvas.width = W; canvas.height = H;
    canvas.getContext('2d').drawImage(video, 0, 0, W, H);

    // Run analysis after a short yield so "Analysiere…" renders
    setTimeout(() => {
      const result = this._analyzePhoto(canvas, W, H);
      this.s.detectedOpenings = result.openings;

      let msg;
      if (result.a4Found) {
        msg = '✅ A4-Referenz erkannt';
        if (result.openings.length > 0) {
          msg += ` · ${result.openings.length} Öffnung${result.openings.length > 1 ? 'en' : ''} erkannt<br>` +
            result.openings.map(o =>
              `<span style="color:var(--text-muted)">${o.type === 'door' ? '🚪' : '🪟'} ` +
              `${o.width.toFixed(2)} × ${o.height.toFixed(2)} m</span>`
            ).join('  ');
        } else {
          msg += '<br><span style="color:var(--text-muted)">Keine Öffnungen erkannt – manuell unter Bauteile eintragen</span>';
        }
      } else {
        msg = '⚠️ Kein A4-Blatt erkannt.<br>' +
              '<span style="color:var(--text-muted)">Weißes Blatt direkt gegen Wand halten, gut beleuchten.</span>';
      }
      showStatus(msg);
    }, 30);
  },

  _analyzePhoto(canvas, W, H) {
    // Downsample to max 320px wide for performance
    const tw = Math.min(320, W);
    const th = Math.round(H * tw / W);

    const sc = document.createElement('canvas');
    sc.width = tw; sc.height = th;
    sc.getContext('2d').drawImage(canvas, 0, 0, tw, th);
    const px = sc.getContext('2d').getImageData(0, 0, tw, th).data;

    // Grayscale
    const g = new Uint8Array(tw * th);
    for (let i = 0; i < tw * th; i++) {
      g[i] = (px[i*4]*77 + px[i*4+1]*150 + px[i*4+2]*29) >> 8;
    }

    // Median brightness (sorted subset for speed)
    const sample = [];
    const step = Math.max(1, Math.floor((tw * th) / 2000));
    for (let i = 0; i < tw * th; i += step) sample.push(g[i]);
    sample.sort((a, b) => a - b);
    const median = sample[(sample.length / 2) | 0];

    // Bright region threshold: notably brighter than wall baseline
    const BRIGHT_THR = Math.max(180, Math.min(230, median + 55));
    const brightRegions = this._labelRegions(g, tw, th, v => v >= BRIGHT_THR);

    // Find A4: largest bright region with aspect ratio close to sqrt(2)
    const A4_R = 297 / 210; // ≈ 1.414
    let a4 = null, bestScore = 0;
    const minA4Px = tw * th * 0.015; // at least 1.5% of image

    for (const r of brightRegions) {
      if (r.size < minA4Px) continue;
      const ar = r.w / r.h;
      const arDiff = Math.min(
        Math.abs(ar - A4_R) / A4_R,
        Math.abs(ar - 1 / A4_R) / (1 / A4_R)
      );
      if (arDiff > 0.38) continue;
      const score = r.size * (1 - arDiff);
      if (score > bestScore) { bestScore = score; a4 = r; }
    }

    let pxPerM = null;
    if (a4) {
      const longPx = Math.max(a4.w, a4.h);
      pxPerM = longPx / 0.297; // A4 long side = 297mm
    }

    const openings = [];
    if (pxPerM) {
      const year = parseInt(window.state?.project?.constructionYear) || 2000;
      const getU = t => t === 'door'
        ? (year < 1990 ? 3.0 : year < 2010 ? 1.8 : 0.9)
        : (year < 1975 ? 2.8 : year < 1995 ? 1.8 : year < 2010 ? 1.1 : 0.7);

      // Bright regions = windows (outdoor light) or A4
      for (const r of brightRegions) {
        if (r === a4) continue;
        const rw = r.w / pxPerM, rh = r.h / pxPerM;
        if (rw < 0.25 || rw > 3.0 || rh < 0.25 || rh > 2.8) continue;
        if (r.size / (r.w * r.h) < 0.38) continue; // not rectangular enough
        const type = rh > 1.8 && rw < 1.2 ? 'door' : 'window';
        openings.push({
          type, wall: 'Foto', width: +rw.toFixed(2), height: +rh.toFixed(2),
          area: +(rw * rh).toFixed(2), sillHeight: 0.90, uDefault: getU(type),
        });
      }

      // Dark regions = possible recessed doors or night windows
      const DARK_THR = Math.min(70, Math.max(20, median - 50));
      if (median > 80) {
        const darkRegions = this._labelRegions(g, tw, th, v => v <= DARK_THR);
        for (const r of darkRegions) {
          const rw = r.w / pxPerM, rh = r.h / pxPerM;
          if (rw < 0.25 || rw > 3.0 || rh < 0.25 || rh > 2.8) continue;
          if (r.size / (r.w * r.h) < 0.40) continue;
          const type = rh > 1.8 && rw < 1.2 ? 'door' : 'window';
          // Avoid duplicates with bright detections (same bounding box area)
          const dup = openings.some(o => Math.abs(o.width - rw) < 0.15 && Math.abs(o.height - rh) < 0.15);
          if (!dup) openings.push({
            type, wall: 'Foto (dunkel)', width: +rw.toFixed(2), height: +rh.toFixed(2),
            area: +(rw * rh).toFixed(2), sillHeight: 0.90, uDefault: getU(type),
          });
        }
      }
    }

    // Keep up to 5 largest, sorted by area
    openings.sort((a, b) => b.area - a.area);
    return { a4Found: !!a4, pxPerM, openings: openings.slice(0, 5) };
  },

  _labelRegions(gray, w, h, pred) {
    const vis = new Uint8Array(w * h);
    const regions = [];

    for (let si = 0; si < w * h; si++) {
      if (vis[si] || !pred(gray[si])) continue;
      const q = [si]; vis[si] = 1;
      let sz = 0, x0 = w, x1 = 0, y0 = h, y1 = 0, qi = 0;
      while (qi < q.length) {
        const idx = q[qi++]; sz++;
        const x = idx % w, y = (idx / w) | 0;
        if (x < x0) x0 = x; if (x > x1) x1 = x;
        if (y < y0) y0 = y; if (y > y1) y1 = y;
        if (x > 0   && !vis[idx-1] && pred(gray[idx-1])) { vis[idx-1]=1; q.push(idx-1); }
        if (x < w-1 && !vis[idx+1] && pred(gray[idx+1])) { vis[idx+1]=1; q.push(idx+1); }
        if (y > 0   && !vis[idx-w] && pred(gray[idx-w])) { vis[idx-w]=1; q.push(idx-w); }
        if (y < h-1 && !vis[idx+w] && pred(gray[idx+w])) { vis[idx+w]=1; q.push(idx+w); }
      }
      if (sz >= 60) regions.push({ size: sz, w: x1-x0+1, h: y1-y0+1, minX: x0, maxX: x1, minY: y0, maxY: y1 });
    }

    return regions.sort((a, b) => b.size - a.size).slice(0, 12);
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

      this.s.pcPoints = points;
      this.s.pcBounds = this._calcBounds(points);
      progressEl.classList.remove('active');
      this._showPointCloud(points, this.s.pcBounds);
    } catch (err) {
      progressEl.classList.remove('active');
      dropZone.style.display = 'flex';
      alert('Fehler: ' + err.message);
    }
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
          if (!isNaN(x) && !isNaN(y) && !isNaN(z)) pts.push({ x, y, z });
        }
        if (i % 10000 === 0) this._setProgress(progEl, 30 + (i / max) * 65);
      }
    } else {
      // Binary little-endian
      const view = new DataView(buf, header.dataOffset);
      const stride = header.stride;
      const max = Math.min(header.vertexCount, 100000);
      for (let i = 0; i < max; i++) {
        const base = i * stride;
        const x = view.getFloat32(base + header.xOff, true);
        const y = view.getFloat32(base + header.yOff, true);
        const z = view.getFloat32(base + header.zOff, true);
        if (!isNaN(x) && !isNaN(y) && !isNaN(z)) pts.push({ x, y, z });
        if (i % 10000 === 0) this._setProgress(progEl, 30 + (i / max) * 65);
      }
    }

    this._setProgress(progEl, 100);
    if (pts.length === 0) throw new Error('Keine Punkte gefunden.');
    return pts;
  },

  _readPLYHeader(buf) {
    const txt = new TextDecoder().decode(buf.slice(0, 4096));
    const lines = txt.split('\n');
    let format = 'ascii', vertexCount = 0, props = [], headerEnd = 0;
    let inVertex = false, byteOffset = 0;

    for (let i = 0; i < lines.length; i++) {
      const l = lines[i].trim();
      if (l.startsWith('format binary_little_endian')) format = 'binary';
      if (l.startsWith('format ascii'))               format = 'ascii';
      if (l.startsWith('element vertex')) vertexCount = parseInt(l.split(' ')[2]);
      if (l.startsWith('element vertex')) inVertex = true;
      if (l.startsWith('element') && !l.startsWith('element vertex')) inVertex = false;
      if (inVertex && l.startsWith('property float')) props.push(l.split(' ')[2]);
      if (inVertex && l.startsWith('property double')) props.push(l.split(' ')[2]);
      if (l === 'end_header') {
        // Count header bytes
        let nb = 0;
        for (let j = 0; j <= i; j++) nb += new TextEncoder().encode(lines[j] + '\n').length;
        headerEnd = nb;
        break;
      }
    }

    const xIdx = props.indexOf('x');
    const yIdx = props.indexOf('y');
    const zIdx = props.indexOf('z');
    const stride = props.length * 4; // assume float32

    return {
      format, vertexCount, dataOffset: headerEnd,
      xIdx, yIdx, zIdx,
      xOff: xIdx * 4, yOff: yIdx * 4, zOff: zIdx * 4,
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
    let minX=Infinity, maxX=-Infinity;
    let minY=Infinity, maxY=-Infinity;
    let minZ=Infinity, maxZ=-Infinity;
    for (const p of pts) {
      if (p.x < minX) minX=p.x; if (p.x > maxX) maxX=p.x;
      if (p.y < minY) minY=p.y; if (p.y > maxY) maxY=p.y;
      if (p.z < minZ) minZ=p.z; if (p.z > maxZ) maxZ=p.z;
    }
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
