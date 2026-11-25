// Controller radar scope: STARS / Eurocat-style 2D display on canvas, plus the
// side panel (flight strip, traffic, ATIS, phraseology, log).

import type { RadarTarget } from '../shared/protocol';
import type { WorldDef } from '../shared/world';
import { fitCanvas, h, MONO, setText, show, storageGet, storageSet, isTyping } from './dom';
import { bearingTo, D2R, hdgText, holdPath, msaAt, pointAt } from './geo';
import { state, update, type State } from './store';
import { mmss, PHRASEOLOGY } from './text';

const C = {
  bg: '#020805',
  ring: '#15361f',
  ringOuter: '#24553150',
  ringLabel: '#3c7449',
  compass: '#2f6a3d',
  map: '#3f8f55',
  cl: '#357a48',
  rwy: '#c9e8d0',
  fix: '#5fae72',
  terr: '#8c6b25',
  terrFill: 'rgba(140,107,37,0.07)',
  terrLabel: '#c0953a',
  msa: '#6d561c',
  msaLabel: '#b8922f',
  hold: '#3a8796',
  target: '#86ff98',
  block: '#8dff9d',
  hist: ['#1e5a2a', '#24703a', '#2c8947', '#35a456', '#3fbf64'],
  sel: '#f4fff6',
  ca: '#ff3b3b',
  la: '#ffb21e',
  rbl: '#f0e36a',
  hud: '#5fbf75',
  hudDim: '#2f6a3d',
  crash: '#d04040',
};

type LayerKey = 'rings' | 'cl' | 'fix' | 'terr' | 'msa' | 'hold' | 'ptl' | 'hist';
const LAYER_LABEL: Record<LayerKey, string> = {
  rings: 'RR',
  cl: 'CL',
  fix: 'FIX',
  terr: 'TERR',
  msa: 'MSA',
  hold: 'HOLD',
  ptl: 'PTL',
  hist: 'HIST',
};

// numpad-style leader directions: bearing of the leader line
const LEADER_DIR: Record<string, number> = { '8': 0, '9': 45, '6': 90, '3': 135, '2': 180, '1': 225, '4': 270, '7': 315 };
const MSA_RADIUS = 25;

interface View {
  cx: number;
  cy: number;
  k: number; // px per nm
}

export function createScope(): { el: HTMLElement; render: (s: State) => void } {
  // ---------------------------------------------------------------- DOM
  const canvas = h('canvas', { id: 'scope-canvas', tabindex: 0 });
  const dcb = h('div', { class: 'dcb' });
  const layers: Record<LayerKey, boolean> = {
    rings: true,
    cl: true,
    fix: true,
    terr: true,
    msa: true,
    hold: true,
    ptl: false,
    hist: true,
  };
  try {
    const saved = JSON.parse(storageGet('ft.layers') ?? '{}') as Partial<Record<LayerKey, boolean>>;
    for (const k of Object.keys(layers) as LayerKey[]) if (typeof saved[k] === 'boolean') layers[k] = saved[k]!;
  } catch {
    /* ignore */
  }
  const layerBtns: HTMLButtonElement[] = [];
  for (const k of Object.keys(layers) as LayerKey[]) {
    const b = h('button', { class: `dcb-btn ${layers[k] ? 'on' : ''}`, title: `Toggle ${LAYER_LABEL[k]}` }, LAYER_LABEL[k]);
    b.addEventListener('click', () => {
      layers[k] = !layers[k];
      b.classList.toggle('on', layers[k]);
      storageSet('ft.layers', JSON.stringify(layers));
    });
    layerBtns.push(b);
  }
  const zoomOut = h('button', { class: 'dcb-btn', title: 'Zoom out' }, 'RNG +');
  const zoomIn = h('button', { class: 'dcb-btn', title: 'Zoom in' }, 'RNG −');
  const resetBtn = h('button', { class: 'dcb-btn', title: 'Reset view (double-click)' }, 'RESET');
  dcb.append(...layerBtns, h('span', { class: 'dcb-sep' }), zoomIn, zoomOut, resetBtn);
  const help = h(
    'div',
    { class: 'scope-help' },
    'wheel zoom · drag pan · dbl-click reset · right/shift-drag measure · click target select · 1-9 leader dir',
  );
  const canvasWrap = h('div', { class: 'scope-canvas-wrap' }, canvas, dcb, help);

  // side panel
  const stripBox = h('div', { class: 'strip-box' });
  const trafficList = h('div', { class: 'traffic-list' });
  const atisBox = h('pre', { class: 'atis-text' });
  const atisHead = h('div', { class: 'atis-head' });
  const logBox = h('div', { class: 'event-log' });
  const pilotsBox = h('div', { class: 'pilots-box' });
  const phr = h(
    'details',
    { class: 'phraseology' },
    h('summary', {}, 'Phraseology'),
    ...PHRASEOLOGY.map((g) => h('div', { class: 'phr-group' }, h('div', { class: 'phr-title' }, g.title), ...g.lines.map((l) => h('div', { class: 'phr-line' }, l)))),
  );
  const side = h(
    'aside',
    { class: 'scope-side' },
    h('section', { class: 'side-sec' }, h('h4', {}, 'Flight strip'), stripBox),
    h('section', { class: 'side-sec' }, h('h4', {}, 'Traffic'), trafficList, pilotsBox),
    h('section', { class: 'side-sec' }, h('h4', {}, 'ATIS'), atisHead, atisBox),
    h('section', { class: 'side-sec' }, phr),
    h('section', { class: 'side-sec grow' }, h('h4', {}, 'Log'), logBox),
  );
  const el = h('div', { id: 'scope-view', class: 'scope-view' }, canvasWrap, side);

  // ---------------------------------------------------------------- view state
  let view: View = { cx: 4, cy: 0, k: 8 };
  let size = { w: 800, h: 600, dpr: 1 };
  let userMoved = false;
  const leader = new Map<string, number>();
  const blockRects = new Map<string, { x: number; y: number; w: number; h: number; tx: number; ty: number }>();
  let rbl: { a: { x: number; y: number }; b: { x: number; y: number }; live: boolean } | null = null;
  let mouse: { x: number; y: number } | null = null;

  const defaultView = (world: WorldDef | undefined): View => {
    const range = (world?.scopeRangeNm ?? 40) * 0.92;
    return { cx: 5, cy: 0, k: Math.min(size.w, size.h) / (2 * range) };
  };
  const toS = (x: number, y: number): [number, number] => [size.w / 2 + (x - view.cx) * view.k, size.h / 2 - (y - view.cy) * view.k];
  const toW = (sx: number, sy: number) => ({ x: view.cx + (sx - size.w / 2) / view.k, y: view.cy - (sy - size.h / 2) / view.k });

  const zoomAt = (sx: number, sy: number, f: number) => {
    const before = toW(sx, sy);
    view.k = Math.max(1.5, Math.min(120, view.k * f));
    const after = toW(sx, sy);
    view.cx += before.x - after.x;
    view.cy += before.y - after.y;
    userMoved = true;
  };
  zoomIn.addEventListener('click', () => zoomAt(size.w / 2, size.h / 2, 1.3));
  zoomOut.addEventListener('click', () => zoomAt(size.w / 2, size.h / 2, 1 / 1.3));
  resetBtn.addEventListener('click', () => {
    view = defaultView(state.round?.world);
    userMoved = false;
  });

  // ---------------------------------------------------------------- interaction
  const pos = (e: MouseEvent) => {
    const r = canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  };
  const targetsNow = (): RadarTarget[] => state.radar?.targets ?? [];
  const hitTarget = (sx: number, sy: number): RadarTarget | null => {
    let best: RadarTarget | null = null;
    let bd = 14;
    for (const t of targetsNow()) {
      if (t.status === 'landed') continue;
      const [x, y] = toS(t.x, t.y);
      const d = Math.hypot(x - sx, y - sy);
      if (d < bd) {
        bd = d;
        best = t;
      }
      const r = blockRects.get(t.callsign);
      if (!best && r && sx >= r.x - 2 && sx <= r.x + r.w + 2 && sy >= r.y - 2 && sy <= r.y + r.h + 2) best = t;
    }
    return best;
  };
  const snap = (p: { x: number; y: number }) => {
    const t = hitTarget(p.x, p.y);
    if (t) return { x: t.x, y: t.y };
    return toW(p.x, p.y);
  };

  let drag: { mode: 'pan' | 'rbl' | 'maybe'; sx: number; sy: number; cx: number; cy: number } | null = null;
  canvas.addEventListener('contextmenu', (e) => e.preventDefault());
  canvas.addEventListener('pointerdown', (e) => {
    canvas.focus({ preventScroll: true });
    const p = pos(e);
    try {
      canvas.setPointerCapture(e.pointerId);
    } catch {
      /* ignore */
    }
    if (e.button === 2 || (e.button === 0 && e.shiftKey)) {
      const a = snap(p);
      rbl = { a, b: a, live: true };
      drag = { mode: 'rbl', sx: p.x, sy: p.y, cx: view.cx, cy: view.cy };
    } else if (e.button === 0) {
      drag = { mode: 'maybe', sx: p.x, sy: p.y, cx: view.cx, cy: view.cy };
    } else if (e.button === 1) {
      e.preventDefault();
      drag = { mode: 'pan', sx: p.x, sy: p.y, cx: view.cx, cy: view.cy };
    }
  });
  canvas.addEventListener('pointermove', (e) => {
    const p = pos(e);
    mouse = p;
    if (!drag) return;
    if (drag.mode === 'maybe' && Math.hypot(p.x - drag.sx, p.y - drag.sy) > 4) drag.mode = 'pan';
    if (drag.mode === 'pan') {
      view.cx = drag.cx - (p.x - drag.sx) / view.k;
      view.cy = drag.cy + (p.y - drag.sy) / view.k;
      userMoved = true;
    } else if (drag.mode === 'rbl' && rbl) {
      rbl.b = snap(p);
    }
  });
  const endDrag = (e: PointerEvent) => {
    if (!drag) return;
    const p = pos(e);
    if (drag.mode === 'maybe') {
      const t = hitTarget(p.x, p.y);
      if (t && (e.ctrlKey || e.metaKey)) {
        // cycle leader direction
        const cur = leader.get(t.callsign) ?? 45;
        leader.set(t.callsign, (cur + 45) % 360);
      }
      update((s) => {
        s.selected = t ? t.callsign : null;
      });
      if (rbl && !rbl.live) rbl = null;
    } else if (drag.mode === 'rbl' && rbl) {
      rbl.live = false;
      if (Math.hypot(p.x - drag.sx, p.y - drag.sy) < 4) rbl = null;
    }
    drag = null;
  };
  canvas.addEventListener('pointerup', endDrag);
  canvas.addEventListener('pointercancel', endDrag);
  canvas.addEventListener('pointerleave', () => {
    mouse = null;
  });
  canvas.addEventListener(
    'wheel',
    (e) => {
      e.preventDefault();
      const p = pos(e);
      zoomAt(p.x, p.y, Math.pow(1.0015, -e.deltaY * (e.deltaMode === 1 ? 30 : 1)));
    },
    { passive: false },
  );
  canvas.addEventListener('dblclick', (e) => {
    e.preventDefault();
    view = defaultView(state.round?.world);
    userMoved = false;
  });
  window.addEventListener('keydown', (e) => {
    if (el.hidden || isTyping(e.target)) return;
    if (e.key === 'Escape') {
      rbl = null;
      update((s) => {
        s.selected = null;
      });
      return;
    }
    const dir = LEADER_DIR[e.key];
    if (dir !== undefined && state.selected) {
      leader.set(state.selected, dir);
      e.preventDefault();
    }
  });

  // ---------------------------------------------------------------- drawing
  let running = false;
  const ctx = canvas.getContext('2d')!;

  const font = (px: number, weight = '') => `${weight} ${px}px ${MONO}`.trim();

  function drawMap(world: WorldDef): void {
    const k = view.k;
    // range rings
    const maxR = world.scopeRangeNm;
    if (layers.rings) {
      ctx.lineWidth = 1;
      ctx.font = font(10);
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      const [ox, oy] = toS(0, 0);
      for (let r = 5; r <= maxR; r += 5) {
        ctx.strokeStyle = r % 10 === 0 ? '#1b4426' : C.ring;
        ctx.beginPath();
        ctx.arc(ox, oy, r * k, 0, Math.PI * 2);
        ctx.stroke();
        const lp = pointAt(0, 0, 200, r);
        const [lx, ly] = toS(lp.x, lp.y);
        ctx.fillStyle = C.ringLabel;
        ctx.fillText(String(r), lx, ly);
      }
      // compass ticks on the outer ring
      ctx.strokeStyle = C.compass;
      ctx.fillStyle = C.compass;
      ctx.font = font(10);
      for (let b = 0; b < 360; b += 5) {
        const len = b % 10 === 0 ? 8 : 4;
        const a = b * D2R;
        const x0 = ox + Math.sin(a) * maxR * k;
        const y0 = oy - Math.cos(a) * maxR * k;
        ctx.beginPath();
        ctx.moveTo(x0, y0);
        ctx.lineTo(x0 + Math.sin(a) * len, y0 - Math.cos(a) * len);
        ctx.stroke();
        if (b % 30 === 0) ctx.fillText(String(b).padStart(3, '0'), x0 + Math.sin(a) * 18, y0 - Math.cos(a) * 18);
      }
    }

    // MSA sectors
    if (layers.msa) {
      const [ox, oy] = toS(0, 0);
      ctx.strokeStyle = C.msa;
      ctx.setLineDash([6, 5]);
      ctx.beginPath();
      ctx.arc(ox, oy, MSA_RADIUS * k, 0, Math.PI * 2);
      ctx.stroke();
      for (const s of world.msa) {
        const p = pointAt(0, 0, s.fromDeg, MSA_RADIUS);
        const [x1, y1] = toS(p.x, p.y);
        ctx.beginPath();
        ctx.moveTo(ox, oy);
        ctx.lineTo(x1, y1);
        ctx.stroke();
      }
      ctx.setLineDash([]);
      ctx.fillStyle = C.msaLabel;
      ctx.font = font(11, 'bold');
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      for (const s of world.msa) {
        let span = s.toDeg - s.fromDeg;
        if (span <= 0) span += 360;
        const mid = s.fromDeg + span / 2;
        const p = pointAt(0, 0, mid, MSA_RADIUS - 3);
        const [x, y] = toS(p.x, p.y);
        ctx.fillText(`MSA ${s.altFt}`, x, y);
      }
    }

    // terrain
    if (layers.terr) {
      for (const t of world.terrain) {
        const [x, y] = toS(t.x, t.y);
        ctx.fillStyle = C.terrFill;
        ctx.strokeStyle = C.terr;
        ctx.setLineDash([3, 3]);
        ctx.beginPath();
        ctx.arc(x, y, t.radiusNm * k, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        ctx.setLineDash([]);
        // spot height
        ctx.fillStyle = C.terrLabel;
        ctx.beginPath();
        ctx.moveTo(x, y - 4);
        ctx.lineTo(x + 3.5, y + 2.5);
        ctx.lineTo(x - 3.5, y + 2.5);
        ctx.closePath();
        ctx.fill();
        ctx.font = font(11, 'bold');
        ctx.textAlign = 'center';
        ctx.textBaseline = 'top';
        ctx.fillText(String(t.elevFt), x, y + 5);
        ctx.font = font(9);
        ctx.fillStyle = '#8a6d2e';
        ctx.fillText(t.name.toUpperCase(), x, y + 18);
      }
    }

    // extended centreline
    if (layers.cl) {
      const range = world.ils.rangeNm;
      const crs = world.ils.courseDeg;
      const back = crs + 180; // direction from threshold out along final
      const end = pointAt(0, 0, back, range);
      const [x0, y0] = toS(0, 0);
      const [x1, y1] = toS(end.x, end.y);
      ctx.strokeStyle = C.cl;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.lineTo(x1, y1);
      ctx.stroke();
      const perp = (back + 90) * D2R;
      const px = Math.sin(perp);
      const py = -Math.cos(perp);
      for (let d = 1; d <= range; d++) {
        const p = pointAt(0, 0, back, d);
        const [x, y] = toS(p.x, p.y);
        const len = d % 5 === 0 ? 7 : 3.5;
        ctx.beginPath();
        ctx.moveTo(x - px * len, y - py * len);
        ctx.lineTo(x + px * len, y + py * len);
        ctx.stroke();
      }
    }

    // runway
    {
      const end = pointAt(0, 0, world.runway.headingDeg, world.runway.lengthNm);
      const [x0, y0] = toS(0, 0);
      const [x1, y1] = toS(end.x, end.y);
      ctx.strokeStyle = C.rwy;
      ctx.lineWidth = Math.max(3, Math.min(8, 0.03 * k * 3));
      ctx.lineCap = 'butt';
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.lineTo(x1, y1);
      ctx.stroke();
      ctx.lineWidth = 1;
      ctx.fillStyle = C.map;
      ctx.font = font(10);
      ctx.textAlign = 'right';
      ctx.textBaseline = 'top';
      ctx.fillText(`${world.icao} RWY ${world.runway.name}`, x1 - 4, y1 + 6);
    }

    // hold
    if (layers.hold) {
      const pts = holdPath(world);
      if (pts.length) {
        ctx.strokeStyle = C.hold;
        ctx.setLineDash([5, 4]);
        ctx.beginPath();
        pts.forEach((p, i) => {
          const [x, y] = toS(p.x, p.y);
          if (i === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        });
        ctx.stroke();
        ctx.setLineDash([]);
        const fix = world.fixes.find((f) => f.name === world.hold.fix);
        if (fix) {
          const lp = pointAt(fix.x, fix.y, world.hold.inboundCourseDeg + 180, 2.2);
          const [x, y] = toS(lp.x, lp.y);
          ctx.fillStyle = C.hold;
          ctx.font = font(10);
          ctx.textAlign = 'left';
          ctx.textBaseline = 'top';
          ctx.fillText(`HOLD ${hdgText(world.hold.inboundCourseDeg)}° ${world.hold.turn} ${world.hold.minAltFt}+`, x + 6, y + 6);
        }
      }
    }

    // fixes
    if (layers.fix) {
      ctx.font = font(10);
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      for (const f of world.fixes) {
        const [x, y] = toS(f.x, f.y);
        const isFaf = f.name === world.ils.faf.name;
        ctx.strokeStyle = C.fix;
        ctx.fillStyle = C.fix;
        ctx.beginPath();
        ctx.moveTo(x, y - 5);
        ctx.lineTo(x + 4.5, y + 3.5);
        ctx.lineTo(x - 4.5, y + 3.5);
        ctx.closePath();
        if (isFaf) ctx.fill();
        else ctx.stroke();
        ctx.fillText(f.name, x + 7, isFaf ? y - 9 : y);
      }
      // VOR/DME at the threshold
      const [x, y] = toS(0, 0);
      ctx.strokeStyle = C.fix;
      ctx.strokeRect(x - 4, y - 4, 8, 8);
    }
  }

  function drawTargets(s: State, world: WorldDef, now: number): void {
    const radar = s.radar;
    if (!radar) return;
    const flashOn = Math.floor(now / 400) % 2 === 0;
    blockRects.clear();
    const lineH = 13;
    ctx.font = font(12, 'bold');
    // history first (under everything)
    if (layers.hist) {
      for (const t of radar.targets) {
        if (t.status !== 'flying') continue;
        const hist = radar.history.get(t.callsign) ?? [];
        const n = hist.length;
        hist.forEach((p, i) => {
          const [x, y] = toS(p.x, p.y);
          const shade = C.hist[Math.max(0, C.hist.length - (n - i))] ?? C.hist[0]!;
          ctx.fillStyle = shade;
          ctx.beginPath();
          ctx.arc(x, y, 2.3, 0, Math.PI * 2);
          ctx.fill();
        });
      }
    }
    for (const t of radar.targets) {
      if (t.status === 'landed') continue;
      const [x, y] = toS(t.x, t.y);
      if (t.status === 'crashed') {
        ctx.strokeStyle = C.crash;
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(x - 5, y - 5);
        ctx.lineTo(x + 5, y + 5);
        ctx.moveTo(x + 5, y - 5);
        ctx.lineTo(x - 5, y + 5);
        ctx.stroke();
        ctx.lineWidth = 1;
        ctx.fillStyle = C.crash;
        ctx.font = font(11);
        ctx.textAlign = 'left';
        ctx.textBaseline = 'middle';
        ctx.fillText(`${t.callsign} XX`, x + 8, y);
        ctx.font = font(12, 'bold');
        continue;
      }
      const selected = s.selected === t.callsign;
      const alert = t.conflict ? 'CA' : t.msaw ? 'LA' : null;
      const alertCol = t.conflict ? C.ca : C.la;
      const col = alert && flashOn ? alertCol : selected ? C.sel : C.block;

      // predicted track line (1 min)
      if (layers.ptl && t.gs > 0) {
        const p = pointAt(t.x, t.y, t.track, t.gs / 60);
        const [px, py] = toS(p.x, p.y);
        ctx.strokeStyle = '#4fbf63';
        ctx.beginPath();
        ctx.moveTo(x, y);
        ctx.lineTo(px, py);
        ctx.stroke();
      }

      // target symbol
      ctx.fillStyle = alert ? alertCol : C.target;
      ctx.beginPath();
      ctx.arc(x, y, 4, 0, Math.PI * 2);
      ctx.fill();
      if (selected) {
        ctx.strokeStyle = C.sel;
        ctx.beginPath();
        ctx.arc(x, y, 8, 0, Math.PI * 2);
        ctx.stroke();
      }

      // data block
      const altHund = String(Math.max(0, Math.round(t.alt / 100))).padStart(3, '0');
      const trend = t.vsTrend > 0 ? '↑' : t.vsTrend < 0 ? '↓' : ' ';
      const gsTens = String(Math.max(0, Math.round(t.gs / 10))).padStart(2, '0');
      const lines: { text: string; color: string }[] = [];
      if (alert) lines.push({ text: alert, color: alertCol });
      lines.push({ text: t.callsign, color: col });
      lines.push({ text: `${altHund}${trend} ${gsTens}`, color: col });
      const sp = (s.scratch[t.callsign] ?? '').trim().toUpperCase().slice(0, 7);
      if (sp) lines.push({ text: sp, color: col });

      const dir = leader.get(t.callsign) ?? 45;
      const L = 26;
      const lx = x + Math.sin(dir * D2R) * L;
      const ly = y - Math.cos(dir * D2R) * L;
      ctx.strokeStyle = col;
      ctx.beginPath();
      ctx.moveTo(x + Math.sin(dir * D2R) * 6, y - Math.cos(dir * D2R) * 6);
      ctx.lineTo(lx, ly);
      ctx.stroke();

      let bw = 0;
      for (const l of lines) bw = Math.max(bw, ctx.measureText(l.text).width);
      const bh = lines.length * lineH;
      const sinD = Math.sin(dir * D2R);
      const cosD = Math.cos(dir * D2R);
      let bx: number;
      if (sinD > 0.3) bx = lx + 3;
      else if (sinD < -0.3) bx = lx - 3 - bw;
      else bx = lx - bw / 2;
      let by: number;
      if (cosD > 0.3) by = ly - bh + lineH / 2;
      else if (cosD < -0.3) by = ly - lineH / 2;
      else by = ly - bh / 2;
      // anchor the callsign line at the leader end for diagonal directions
      if (Math.abs(sinD) > 0.3 && Math.abs(cosD) > 0.3) by = cosD > 0 ? ly - bh + lineH * 0.5 : ly - lineH * 0.5;

      if (selected || alert) {
        ctx.fillStyle = 'rgba(2,8,5,0.8)';
        ctx.fillRect(bx - 2, by - 1, bw + 4, bh + 2);
      }
      ctx.textAlign = 'left';
      ctx.textBaseline = 'top';
      lines.forEach((l, i) => {
        ctx.fillStyle = l.color;
        ctx.fillText(l.text, bx, by + i * lineH);
      });
      if (selected) {
        ctx.strokeStyle = 'rgba(244,255,246,0.5)';
        ctx.strokeRect(bx - 3, by - 2, bw + 6, bh + 3);
      }
      blockRects.set(t.callsign, { x: bx, y: by, w: bw, h: bh, tx: x, ty: y });
    }
    void world;
  }

  function drawRbl(): void {
    if (!rbl) return;
    const [x0, y0] = toS(rbl.a.x, rbl.a.y);
    const [x1, y1] = toS(rbl.b.x, rbl.b.y);
    const dist = Math.hypot(rbl.b.x - rbl.a.x, rbl.b.y - rbl.a.y);
    ctx.strokeStyle = C.rbl;
    ctx.fillStyle = C.rbl;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x0, y0);
    ctx.lineTo(x1, y1);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(x0, y0, 3, 0, Math.PI * 2);
    ctx.arc(x1, y1, 3, 0, Math.PI * 2);
    ctx.fill();
    if (dist < 0.05) return;
    const brg = bearingTo(rbl.a.x, rbl.a.y, rbl.b.x, rbl.b.y);
    const label = `BRG ${hdgText(brg)}° / ${dist.toFixed(1)} NM`;
    ctx.font = font(12, 'bold');
    const tw = ctx.measureText(label).width;
    const mx = (x0 + x1) / 2 + 10;
    const my = (y0 + y1) / 2 - 10;
    ctx.fillStyle = 'rgba(2,8,5,0.85)';
    ctx.fillRect(mx - 3, my - 9, tw + 6, 18);
    ctx.fillStyle = C.rbl;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(label, mx, my);
  }

  function drawHud(s: State, world: WorldDef, now: number): void {
    const pad = 10;
    ctx.font = font(12);
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    const t = s.serverTime;
    const sweepAge = s.radar ? (now - s.radar.receivedAt) / 1000 : null;
    const lines = [
      `${world.icao}  ${mmss(t)}`,
      `ATIS ${s.round?.atis.letter ?? '-'}  QNH ${s.round?.atis.qnh ?? '----'}`,
      `RNG ${Math.round(Math.min(size.w, size.h) / 2 / view.k)}  TA ${world.transitionAltFt}`,
      `SEP ${world.separation.lateralNm}NM/${world.separation.verticalFt}FT`,
      sweepAge === null ? 'NO RADAR DATA' : `SWEEP ${sweepAge.toFixed(1)}s`,
    ];
    const y0 = 44;
    ctx.fillStyle = 'rgba(2,8,5,0.6)';
    ctx.fillRect(pad - 4, y0 - 4, 178, lines.length * 15 + 6);
    lines.forEach((l, i) => {
      ctx.fillStyle = i === 4 && (sweepAge === null || sweepAge > 4.5) ? C.la : C.hud;
      ctx.fillText(l, pad, y0 + i * 15);
    });
    // cursor readout
    if (mouse) {
      const w = toW(mouse.x, mouse.y);
      const d = Math.hypot(w.x, w.y);
      const b = bearingTo(0, 0, w.x, w.y);
      const msa = msaAt(world, w.x, w.y);
      const txt = `FTW ${hdgText(b)}°/${d.toFixed(1)}NM${msa !== null && d <= MSA_RADIUS ? `  MSA ${msa}` : ''}`;
      ctx.fillStyle = C.hudDim;
      ctx.textBaseline = 'bottom';
      ctx.fillText(txt, pad, size.h - 22);
    }
  }

  function frame(): void {
    if (!running) return;
    requestAnimationFrame(frame);
    const world = state.round?.world;
    size = fitCanvas(canvas);
    if (!userMoved) view = defaultView(world);
    ctx.setTransform(size.dpr, 0, 0, size.dpr, 0, 0);
    ctx.fillStyle = C.bg;
    ctx.fillRect(0, 0, size.w, size.h);
    // subtle vignette for a CRT-ish phosphor look
    const g = ctx.createRadialGradient(size.w / 2, size.h / 2, Math.min(size.w, size.h) * 0.2, size.w / 2, size.h / 2, Math.max(size.w, size.h) * 0.75);
    g.addColorStop(0, 'rgba(20,60,30,0.10)');
    g.addColorStop(1, 'rgba(0,0,0,0.35)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, size.w, size.h);
    if (!world) return;
    const now = performance.now();
    ctx.lineWidth = 1;
    drawMap(world);
    drawTargets(state, world, now);
    drawRbl();
    drawHud(state, world, now);
  }

  // ---------------------------------------------------------------- side panel
  const scratch = h('textarea', { class: 'scratchpad', rows: 2, placeholder: 'Scratchpad (local only) — first 7 chars show in the data block', spellcheck: 'false' });
  scratch.addEventListener('input', () => {
    const cs = state.selected;
    if (cs) state.scratch[cs] = scratch.value;
  });
  const stripFields = {
    cs: h('div', { class: 'strip-cs' }),
    pilot: h('div', { class: 'strip-pilot' }),
    alt: h('div', { class: 'strip-val' }),
    gs: h('div', { class: 'strip-val' }),
    trk: h('div', { class: 'strip-val' }),
    dme: h('div', { class: 'strip-val' }),
    msa: h('div', { class: 'strip-val' }),
    status: h('div', { class: 'strip-status' }),
  };
  const cell = (label: string, v: HTMLElement) => h('div', { class: 'strip-cell' }, h('div', { class: 'strip-label' }, label), v);
  const strip = h(
    'div',
    { class: 'strip' },
    h('div', { class: 'strip-head' }, stripFields.cs, stripFields.pilot, stripFields.status),
    h('div', { class: 'strip-grid' }, cell('ALT', stripFields.alt), cell('GS', stripFields.gs), cell('TRK', stripFields.trk), cell('DME', stripFields.dme), cell('MSA', stripFields.msa)),
    scratch,
  );
  const noStrip = h('div', { class: 'dim small' }, 'Click a target to select it.');
  stripBox.append(strip, noStrip);

  let lastSelected: string | null = null;
  let lastLogLen = -1;
  let lastTrafficSig = '';
  let lastAtis = '';

  const render = (s: State) => {
    const visible = s.view === 'round' && s.round?.you.role === 'controller';
    show(el, visible);
    if (visible && !running) {
      running = true;
      requestAnimationFrame(frame);
    } else if (!visible) {
      running = false;
      return;
    }
    const r = s.round!;
    // ATIS
    const atisKey = r.atis.letter + r.atis.text;
    if (atisKey !== lastAtis) {
      lastAtis = atisKey;
      setText(atisHead, `INFO ${r.atis.letter} · RWY ${r.atis.runway} · QNH ${r.atis.qnh} · ${String(r.atis.windDir).padStart(3, '0')}/${r.atis.windKt}KT`);
      setText(atisBox, r.atis.text);
    }
    // strip
    const sel = s.selected ? s.radar?.targets.find((t) => t.callsign === s.selected) : undefined;
    show(strip, !!s.selected);
    show(noStrip, !s.selected);
    if (s.selected) {
      if (lastSelected !== s.selected) {
        lastSelected = s.selected;
        scratch.value = s.scratch[s.selected] ?? '';
      }
      const pilot = r.players.find((p) => p.callsign === s.selected);
      setText(stripFields.cs, s.selected);
      setText(stripFields.pilot, pilot ? pilot.name : '');
      if (sel) {
        setText(stripFields.alt, `${Math.round(sel.alt)} ft ${sel.vsTrend > 0 ? '↑' : sel.vsTrend < 0 ? '↓' : '='}`);
        setText(stripFields.gs, `${Math.round(sel.gs)} kt`);
        setText(stripFields.trk, `${hdgText(sel.track)}°`);
        setText(stripFields.dme, `${Math.hypot(sel.x, sel.y).toFixed(1)} nm`);
        const msa = msaAt(r.world, sel.x, sel.y);
        setText(stripFields.msa, msa === null ? '—' : String(msa));
        const st = sel.status !== 'flying' ? sel.status.toUpperCase() : sel.conflict ? 'CA' : sel.msaw ? 'LA' : '';
        setText(stripFields.status, st);
        stripFields.status.className = `strip-status ${sel.conflict ? 'ca' : sel.msaw ? 'la' : sel.status}`;
      } else {
        setText(stripFields.alt, '—');
        setText(stripFields.gs, '—');
        setText(stripFields.trk, '—');
        setText(stripFields.dme, '—');
        setText(stripFields.msa, '—');
        setText(stripFields.status, 'NO TGT');
        stripFields.status.className = 'strip-status';
      }
    } else {
      lastSelected = null;
    }
    // traffic list
    const targets = s.radar?.targets ?? [];
    const sig = JSON.stringify(targets.map((t) => [t.callsign, Math.round(t.alt / 100), Math.round(t.gs / 10), t.status, t.conflict, t.msaw])) + s.selected;
    if (sig !== lastTrafficSig) {
      lastTrafficSig = sig;
      trafficList.replaceChildren(
        ...targets.map((t) => {
          const row = h(
            'button',
            { class: `traffic-row ${t.callsign === s.selected ? 'sel' : ''} ${t.status} ${t.conflict ? 'ca' : t.msaw ? 'la' : ''}` },
            h('span', { class: 'tr-cs' }, t.callsign),
            h('span', { class: 'tr-alt' }, t.status === 'flying' ? String(Math.round(t.alt / 100)).padStart(3, '0') : t.status.toUpperCase()),
            h('span', { class: 'tr-gs' }, t.status === 'flying' ? `${Math.round(t.gs)}kt` : ''),
            h('span', { class: 'tr-flag' }, t.conflict ? 'CA' : t.msaw ? 'LA' : ''),
          );
          row.addEventListener('click', () =>
            update((st) => {
              st.selected = t.callsign;
            }),
          );
          return row;
        }),
      );
      if (!targets.length) trafficList.append(h('div', { class: 'dim small' }, 'No targets yet — first sweep pending.'));
      const ctl = r.players.filter((p) => p.role === 'controller');
      pilotsBox.replaceChildren(
        h('div', { class: 'dim small' }, `Controllers: ${ctl.map((p) => (p.id === s.selfId ? `${p.name} (you)` : p.name)).join(', ')}`),
      );
    }
    // log
    if (s.log.length !== lastLogLen) {
      lastLogLen = s.log.length;
      logBox.replaceChildren(
        ...s.log.map((l) => h('div', { class: `log-line ${l.kind}` }, h('span', { class: 'log-t' }, l.time === null ? '--:--' : mmss(l.time)), ' ', l.text)),
      );
      logBox.scrollTop = logBox.scrollHeight;
    }
  };
  return { el, render };
}
