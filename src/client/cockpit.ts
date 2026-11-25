// Pilot cockpit: PFD + HSI canvases, autopilot panel (MCP), configuration,
// nav/fuel readouts, warnings, ATIS and approach plate overlays.

import type { ClientMsg, FlapSetting, OwnAircraft } from '../shared/protocol';
import type { Actions } from './actions';
import { chime, setSiren } from './alerts';
import { fitCanvas, h, isTyping, setClass, setText, show } from './dom';
import { angleDiff, D2R, hdgText, norm360 } from './geo';
import { drawHsi, drawPfd, fmaFor, HSI_H, HSI_W, PFD_H, PFD_W } from './pfd';
import { drawPlate, PLATE_H, PLATE_W } from './plate';
import { state, type State } from './store';
import { OUTCOME_TEXT } from './text';

const FLAP_MIN: Record<FlapSetting, number> = { 0: 200, 1: 180, 2: 160, 3: 135 };
type Knob = 'hdg' | 'alt' | 'spd' | 'baro';

const LIMITS: Record<Knob, { min: number; max: number; step: number; big: number }> = {
  hdg: { min: 0, max: 359, step: 1, big: 10 },
  alt: { min: 0, max: 20000, step: 100, big: 1000 },
  spd: { min: 140, max: 250, step: 1, big: 10 },
  baro: { min: 950, max: 1050, step: 1, big: 5 },
};

const RED_WARN = new Set(['TERRAIN', 'PULL UP', 'TOO LOW GEAR', 'TOO LOW TERRAIN', 'TOO LOW FLAPS', 'GLIDESLOPE', 'SINK RATE']);

export function createCockpit(actions: Actions): { el: HTMLElement; render: (s: State) => void } {
  // ---------------------------------------------------------------- optimistic selections
  const pending: Partial<Record<Knob, { v: number; until: number }>> = {};
  const serverVal = (ac: OwnAircraft, k: Knob): number =>
    k === 'hdg' ? ac.selHdg : k === 'alt' ? ac.selAlt : k === 'spd' ? ac.selSpd : ac.altSetting;
  const current = (k: Knob): number => {
    const ac = state.own?.ac;
    const p = pending[k];
    if (p && performance.now() < p.until) return p.v;
    return ac ? serverVal(ac, k) : 0;
  };
  const send = (m: ClientMsg) => actions.send(m);
  const setKnob = (k: Knob, raw: number) => {
    if (!state.own) return;
    const L = LIMITS[k];
    let v = Math.round(raw);
    if (k === 'hdg') v = norm360(v);
    else if (k === 'alt') v = Math.max(L.min, Math.min(L.max, Math.round(v / 100) * 100));
    else v = Math.max(L.min, Math.min(L.max, v));
    pending[k] = { v, until: performance.now() + 1500 };
    if (k === 'hdg') send({ t: 'ap', hdg: v });
    else if (k === 'alt') send({ t: 'ap', alt: v });
    else if (k === 'spd') send({ t: 'ap', spd: v });
    else send({ t: 'ap', altSetting: v });
    renderMcp();
  };
  const nudge = (k: Knob, dir: number, big: boolean) => {
    const L = LIMITS[k];
    const base = current(k);
    const step = big ? L.big : L.step;
    let v = base + dir * step;
    if (k === 'alt') v = Math.round(v / step) * step;
    setKnob(k, v);
  };

  // ---------------------------------------------------------------- MCP DOM
  const knobInputs: Partial<Record<Knob, HTMLInputElement>> = {};
  const knob = (k: Knob, label: string, unit: string): HTMLElement => {
    const input = h('input', { class: 'mcp-input', type: 'text', inputmode: 'numeric', maxlength: 5, 'aria-label': label, id: `mcp-${k}` });
    knobInputs[k] = input;
    const minus = h('button', { class: 'mcp-step', title: `${label} − (shift: ×${LIMITS[k].big / LIMITS[k].step})`, tabindex: -1 }, '−');
    const plus = h('button', { class: 'mcp-step', title: `${label} + (shift: ×${LIMITS[k].big / LIMITS[k].step})`, tabindex: -1 }, '+');
    minus.addEventListener('click', (e) => nudge(k, -1, e.shiftKey));
    plus.addEventListener('click', (e) => nudge(k, 1, e.shiftKey));
    const commit = () => {
      const v = Number(input.value.replace(/[^0-9.]/g, ''));
      if (input.value.trim() !== '' && Number.isFinite(v)) setKnob(k, k === 'hdg' && v === 360 ? 0 : v);
      input.dataset.editing = '';
      renderMcp();
    };
    input.addEventListener('focus', () => {
      input.dataset.editing = '1';
      input.select();
    });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        commit();
        input.blur();
      } else if (e.key === 'Escape') {
        input.dataset.editing = '';
        input.blur();
        renderMcp();
      } else if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
        e.preventDefault();
        nudge(k, e.key === 'ArrowUp' ? 1 : -1, e.shiftKey);
        input.dataset.editing = '';
        renderMcp();
        input.dataset.editing = '1';
      }
    });
    input.addEventListener('blur', () => {
      if (input.dataset.editing) commit();
    });
    const wheel = (e: WheelEvent) => {
      e.preventDefault();
      if (e.deltaY === 0) return;
      nudge(k, e.deltaY < 0 ? 1 : -1, e.shiftKey);
      if (document.activeElement === input) input.blur();
    };
    const cell = h(
      'div',
      { class: `mcp-cell mcp-${k}` },
      h('div', { class: 'mcp-label' }, label, h('span', { class: 'mcp-unit' }, unit)),
      h('div', { class: 'mcp-row' }, minus, input, plus),
    );
    cell.addEventListener('wheel', wheel, { passive: false });
    return cell;
  };

  const appBtn = h('button', { class: 'mcp-btn app', title: 'Arm / disarm approach (A)' }, h('span', { class: 'lamp' }), 'APP');
  appBtn.addEventListener('click', () => {
    const ac = state.own?.ac;
    if (ac) send({ t: 'ap', app: !ac.appArmed });
  });
  const locLamp = h('div', { class: 'ann-lamp' }, 'LOC');
  const gsLamp = h('div', { class: 'ann-lamp' }, 'G/S');

  const stdBtn = h('button', { class: 'mcp-btn small', title: 'Standard 1013 (B)' }, 'STD');
  stdBtn.addEventListener('click', () => setKnob('baro', 1013));

  const gearBtn = h('button', { class: 'gear-lever', title: 'Gear (G)' }, h('span', { class: 'gear-knob' }), h('span', { class: 'gear-txt' }, 'GEAR'));
  gearBtn.addEventListener('click', () => {
    const ac = state.own?.ac;
    if (ac) send({ t: 'ap', gear: !ac.gearDown });
  });
  const gearLights = h('div', { class: 'gear-lights' }, h('span', { class: 'gl' }), h('span', { class: 'gl' }), h('span', { class: 'gl' }));

  const flapBtns = ([0, 1, 2, 3] as FlapSetting[]).map((fl) => {
    const b = h('button', { class: 'flap-btn', title: `Flaps ${fl} (F / Shift+F)` }, String(fl));
    b.addEventListener('click', () => send({ t: 'ap', flaps: fl }));
    return b;
  });

  const atisBtn = h('button', { class: 'mcp-btn doc', title: 'ATIS (I)' }, 'ATIS');
  const plateBtn = h('button', { class: 'mcp-btn doc', title: 'Approach plate (P)' }, 'PLATE');

  const mcp = h(
    'div',
    { class: 'mcp' },
    knob('spd', 'IAS', 'KT'),
    knob('hdg', 'HDG', 'SEL'),
    knob('alt', 'ALT', 'FT'),
    h('div', { class: 'mcp-cell mcp-app' }, h('div', { class: 'mcp-label' }, 'APPROACH'), h('div', { class: 'mcp-row' }, appBtn, h('div', { class: 'lamps' }, locLamp, gsLamp))),
    h('div', { class: 'mcp-sep' }),
    h('div', { class: 'mcp-cell mcp-baro-cell' }, knob('baro', 'BARO', 'HPA'), stdBtn),
    h('div', { class: 'mcp-sep' }),
    h('div', { class: 'mcp-cell mcp-gear' }, h('div', { class: 'mcp-label' }, 'LDG GEAR'), h('div', { class: 'mcp-row' }, gearBtn, gearLights)),
    h('div', { class: 'mcp-cell mcp-flaps' }, h('div', { class: 'mcp-label' }, 'FLAPS'), h('div', { class: 'mcp-row flap-row' }, ...flapBtns)),
    h('div', { class: 'mcp-sep' }),
    h('div', { class: 'mcp-cell mcp-docs' }, h('div', { class: 'mcp-label' }, 'DOCS'), h('div', { class: 'mcp-row' }, atisBtn, plateBtn)),
  );

  // ---------------------------------------------------------------- displays
  const pfdCanvas = h('canvas', { class: 'pfd-canvas', id: 'pfd-canvas' });
  const hsiCanvas = h('canvas', { class: 'hsi-canvas', id: 'hsi-canvas' });

  const callsignEl = h('div', { class: 'ck-callsign' });
  const ro = (label: string) => {
    const v = h('div', { class: 'ro-val' });
    const box = h('div', { class: 'ro' }, h('div', { class: 'ro-label' }, label), v);
    return { v, box };
  };
  const roDme = ro('DME FTW');
  const roBrg = ro('BRG TO FTW');
  const roFuel = ro('FUEL');
  const roBaro = ro('ALTIMETER');
  const roFlaps = ro('FLAPS');
  const roGear = ro('GEAR');
  const annun = h('div', { class: 'annunciators' });
  const ctlLine = h('div', { class: 'ck-ctl dim small' });
  const shortcuts = h(
    'div',
    { class: 'shortcuts' },
    h('div', { class: 'sc-title' }, 'Keys'),
    ...(
      [
        ['Space', 'push-to-talk (hold)'],
        ['← →', 'HDG ±1 (Shift ±10)'],
        ['↑ ↓', 'ALT ±100 (Shift ±1000)'],
        ['PgUp PgDn', 'SPD ±1 (Shift ±10)'],
        ['[ ]', 'BARO ±1 hPa · B = STD'],
        ['A', 'APP arm'],
        ['G', 'gear'],
        ['F / Shift+F', 'flaps down / up'],
        ['I / P', 'ATIS / plate · Esc close'],
      ] as const
    ).map(([k, d]) => h('div', { class: 'sc' }, h('kbd', {}, k), h('span', {}, d))),
  );

  const side = h(
    'div',
    { class: 'ck-side' },
    callsignEl,
    ctlLine,
    h('div', { class: 'ro-grid' }, roDme.box, roBrg.box, roFuel.box, roBaro.box, roFlaps.box, roGear.box),
    annun,
    shortcuts,
  );

  const waiting = h('div', { class: 'ck-waiting' }, 'Waiting for aircraft data…');
  const statusOverlay = h('div', { class: 'ck-status', hidden: true });

  // overlays
  const atisPre = h('pre', { class: 'atis-text big' });
  const atisHead = h('div', { class: 'atis-head big' });
  const atisOverlay = h(
    'div',
    { class: 'overlay', hidden: true },
    h('div', { class: 'overlay-card atis-card' }, h('div', { class: 'overlay-head' }, h('span', {}, 'ATIS'), h('button', { class: 'btn small close' }, 'Close (Esc)')), atisHead, atisPre),
  );
  const plateCanvas = h('canvas', { class: 'plate-canvas' });
  const plateOverlay = h(
    'div',
    { class: 'overlay', hidden: true },
    h('div', { class: 'overlay-card plate-card' }, h('div', { class: 'overlay-head' }, h('span', {}, 'Approach chart'), h('button', { class: 'btn small close' }, 'Close (Esc)')), plateCanvas),
  );
  for (const ov of [atisOverlay, plateOverlay]) {
    ov.addEventListener('click', (e) => {
      if (e.target === ov || (e.target as HTMLElement).classList.contains('close')) ov.hidden = true;
    });
  }
  const openAtis = () => {
    plateOverlay.hidden = true;
    atisOverlay.hidden = !atisOverlay.hidden;
  };
  const openPlate = () => {
    atisOverlay.hidden = true;
    plateOverlay.hidden = !plateOverlay.hidden;
    if (!plateOverlay.hidden) requestAnimationFrame(drawPlateNow);
  };
  atisBtn.addEventListener('click', openAtis);
  plateBtn.addEventListener('click', openPlate);
  const drawPlateNow = () => {
    const r = state.round;
    if (!r || plateOverlay.hidden) return;
    const { w, dpr } = fitCanvas(plateCanvas);
    const s = (w / PLATE_W) * dpr;
    const c = plateCanvas.getContext('2d');
    if (!c) return;
    c.setTransform(s, 0, 0, s, 0, 0);
    drawPlate(c, r.world, null);
  };
  window.addEventListener('resize', () => requestAnimationFrame(drawPlateNow));
  void PLATE_H;

  const main = h('div', { class: 'ck-main' }, h('div', { class: 'pfd-wrap' }, pfdCanvas), h('div', { class: 'hsi-wrap' }, hsiCanvas), side);
  const el = h('div', { id: 'cockpit', class: 'cockpit' }, mcp, main, waiting, statusOverlay, atisOverlay, plateOverlay);

  // ---------------------------------------------------------------- keyboard
  window.addEventListener('keydown', (e) => {
    if (el.hidden || isTyping(e.target) || e.ctrlKey || e.metaKey || e.altKey) return;
    const k = e.key;
    let handled = true;
    if (k === 'ArrowLeft') nudge('hdg', -1, e.shiftKey);
    else if (k === 'ArrowRight') nudge('hdg', 1, e.shiftKey);
    else if (k === 'ArrowUp') nudge('alt', 1, e.shiftKey);
    else if (k === 'ArrowDown') nudge('alt', -1, e.shiftKey);
    else if (k === 'PageUp') nudge('spd', 1, e.shiftKey);
    else if (k === 'PageDown') nudge('spd', -1, e.shiftKey);
    else if (k === '[' || k === '{') nudge('baro', -1, e.shiftKey);
    else if (k === ']' || k === '}') nudge('baro', 1, e.shiftKey);
    else if (k === 'b' || k === 'B') setKnob('baro', 1013);
    else if ((k === 'a' || k === 'A') && !e.repeat) appBtn.click();
    else if ((k === 'g' || k === 'G') && !e.repeat) gearBtn.click();
    else if ((k === 'f' || k === 'F') && !e.repeat) {
      const ac = state.own?.ac;
      if (ac) {
        const nf = Math.max(0, Math.min(3, ac.flaps + (e.shiftKey ? -1 : 1))) as FlapSetting;
        if (nf !== ac.flaps) send({ t: 'ap', flaps: nf });
      }
    } else if ((k === 'i' || k === 'I') && !e.repeat) openAtis();
    else if ((k === 'p' || k === 'P') && !e.repeat) openPlate();
    else if (k === 'Escape') {
      atisOverlay.hidden = true;
      plateOverlay.hidden = true;
    } else handled = false;
    if (handled) e.preventDefault();
  });

  // ---------------------------------------------------------------- MCP render
  function renderMcp(): void {
    const ac = state.own?.ac;
    for (const k of ['hdg', 'alt', 'spd', 'baro'] as Knob[]) {
      const input = knobInputs[k];
      if (!input || input.dataset.editing) continue;
      if (!ac) {
        input.value = '---';
        continue;
      }
      const v = current(k);
      const txt = k === 'hdg' ? hdgText(v) : String(Math.round(v));
      if (input.value !== txt) input.value = txt;
    }
    if (!ac) return;
    setClass(appBtn, 'on', ac.appArmed);
    setClass(locLamp, 'on', ac.apMode !== 'HDG');
    setClass(locLamp, 'armed', ac.appArmed && ac.apMode === 'HDG');
    setClass(gsLamp, 'on', ac.gsCaptured);
    setClass(gsLamp, 'armed', ac.appArmed && !ac.gsCaptured);
    setClass(gearBtn, 'down', ac.gearDown);
    for (const l of gearLights.children) {
      setClass(l, 'down', ac.gearDown);
    }
    flapBtns.forEach((b, i) => setClass(b, 'on', ac.flaps === i));
  }

  // ---------------------------------------------------------------- canvas loop
  const pfdCtx = pfdCanvas.getContext('2d')!;
  const hsiCtx = hsiCanvas.getContext('2d')!;
  let running = false;
  const est = { pitch: 0, bank: 0, lastHdg: null as number | null, lastT: 0, rate: 0, lastMsg: null as unknown };
  const fmaChanged = [0, 0, 0];
  let lastFma: string[] = ['', '', ''];

  function drawScaled(c: HTMLCanvasElement, ctx: CanvasRenderingContext2D, lw: number, lh: number, fn: () => void): void {
    const { w, h: hh, dpr } = fitCanvas(c);
    const s = Math.min(w / lw, hh / lh);
    const ox = (w - lw * s) / 2;
    const oy = (hh - lh * s) / 2;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = '#05070a';
    ctx.fillRect(0, 0, w, hh);
    ctx.setTransform(s * dpr, 0, 0, s * dpr, ox * dpr, oy * dpr);
    fn();
  }

  function frame(): void {
    if (!running) return;
    requestAnimationFrame(frame);
    const own = state.own;
    const r = state.round;
    if (!own || !r) return;
    const ac = own.ac;
    const now = performance.now();
    // attitude estimate from heading rate and vertical speed
    if (est.lastMsg !== own) {
      est.lastMsg = own;
      if (est.lastHdg !== null && est.lastT > 0) {
        const dt = (now - est.lastT) / 1000;
        if (dt > 0.02 && dt < 1) est.rate = angleDiff(est.lastHdg, ac.hdg) / dt;
      }
      est.lastHdg = ac.hdg;
      est.lastT = now;
    }
    const vMs = ac.ias * 0.5144;
    const flying = ac.status === 'flying';
    const bankT = flying ? Math.max(-30, Math.min(30, Math.atan((vMs * est.rate * D2R) / 9.81) / D2R)) : 0;
    const fpa = Math.atan(ac.vs / Math.max(60, ac.ias * 101.27)) / D2R;
    const pitchT = flying ? fpa + 2.5 + (ac.flaps === 0 ? 1 : 0) : 0;
    est.bank += (bankT - est.bank) * 0.08;
    est.pitch += (pitchT - est.pitch) * 0.08;

    const fma = fmaFor(ac);
    const cols = [fma.spd, fma.lat, fma.vert];
    cols.forEach((c, i) => {
      if (lastFma[i] !== c) {
        if (lastFma[i]) fmaChanged[i] = now;
        lastFma[i] = c;
      }
    });

    const sel = { hdg: current('hdg'), alt: current('alt'), spd: current('spd') };
    drawScaled(pfdCanvas, pfdCtx, PFD_W, PFD_H, () =>
      drawPfd(pfdCtx, ac, {
        pitch: est.pitch,
        bank: est.bank,
        daFt: r.world.ils.daFt,
        flapMin: FLAP_MIN[ac.flaps] ?? 135,
        fmaChanged,
        now,
        sel,
      }),
    );
    drawScaled(hsiCanvas, hsiCtx, HSI_W, HSI_H, () => drawHsi(hsiCtx, ac, sel.hdg, r.world.ils.courseDeg));
  }

  // ---------------------------------------------------------------- warnings
  let prevWarn = new Set<string>();
  let annSig = '';

  let lastAtis = '';
  const render = (s: State) => {
    const visible = s.view === 'round' && s.round?.you.role === 'pilot';
    show(el, visible);
    if (!visible) {
      running = false;
      setSiren(false);
      prevWarn = new Set();
      return;
    }
    if (!running) {
      running = true;
      lastFma = ['', '', ''];
      requestAnimationFrame(frame);
    }
    const r = s.round!;
    const own = s.own;
    show(waiting, !own);
    const atisKey = r.atis.letter + r.atis.text;
    if (atisKey !== lastAtis) {
      lastAtis = atisKey;
      setText(atisHead, `${r.world.icao} INFORMATION ${r.atis.letter}`);
      setText(atisPre, r.atis.text);
    }
    const ctl = r.players.filter((p) => p.role === 'controller').map((p) => p.name);
    setText(ctlLine, `Two controllers on frequency: ${ctl.join(' and ')}. One is the impostor.`);
    setText(callsignEl, own?.ac.callsign ?? r.you.callsign ?? '');
    renderMcp();
    if (!own) return;
    const ac = own.ac;

    setText(roDme.v, `${ac.dme.toFixed(1)} NM`);
    setText(roBrg.v, `${hdgText(ac.bearingToStation)}°`);
    const fm = Math.max(0, ac.fuelMin);
    const fmTxt = `${Math.floor(fm)}:${String(Math.floor((fm % 1) * 60)).padStart(2, '0')} MIN`;
    setText(roFuel.v, fmTxt);
    roFuel.box.className = `ro ${fm < 5 ? 'red' : fm < 10 ? 'amber' : ''}`;
    setText(roBaro.v, ac.altSetting === 1013 ? '1013 STD' : `${ac.altSetting} hPa`);
    setText(roFlaps.v, `${ac.flaps} · ${FLAP_MIN[ac.flaps]} kt`);
    setText(roGear.v, ac.gearDown ? 'DOWN ▼' : 'UP');
    roGear.box.className = `ro ${ac.gearDown ? 'green' : ''}`;

    // warnings
    const warn = ac.status === 'flying' ? ac.warnings : [];
    const sig = warn.join('|');
    if (sig !== annSig) {
      annSig = sig;
      annun.replaceChildren(
        ...(warn.length
          ? warn.map((w) => h('div', { class: `annun ${RED_WARN.has(w) ? 'red' : 'amber'}` }, w))
          : [h('div', { class: 'annun idle' }, 'NO WARNINGS')]),
      );
    }
    setSiren(warn.includes('TERRAIN') || warn.includes('PULL UP'));
    for (const w of warn) if (!prevWarn.has(w) && w !== 'TERRAIN' && w !== 'PULL UP') chime();
    prevWarn = new Set(warn);

    // status overlay
    if (ac.status !== 'flying') {
      const landed = ac.status === 'landed';
      const outcome = ac.outcome ?? (landed ? 'landed' : 'terrain');
      const key = `${ac.status}/${outcome}`;
      if (statusOverlay.dataset.key !== key) {
        statusOverlay.dataset.key = key;
        statusOverlay.className = `ck-status ${landed ? 'landed' : 'crashed'}`;
        statusOverlay.replaceChildren(
          h('div', { class: 'ck-status-title' }, landed ? 'LANDED' : 'CRASHED'),
          h('div', { class: 'ck-status-sub' }, `${ac.callsign} — ${OUTCOME_TEXT[outcome]}`),
          h(
            'div',
            { class: 'ck-status-note' },
            landed
              ? 'Welcome to Fallow Ridge. Stay on frequency — you can still listen and help the others.'
              : 'Your radio is dead, but you can still hear the frequency until the round ends.',
          ),
        );
      }
      show(statusOverlay, true);
    } else {
      show(statusOverlay, false);
      statusOverlay.dataset.key = '';
    }
    void actions;
  };
  return { el, render };
}
