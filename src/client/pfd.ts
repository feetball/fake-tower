// Glass-cockpit instruments drawn on canvas: Primary Flight Display and an
// HSI / navigation display. Pure drawing functions; state comes in as args.

import type { OwnAircraft } from '../shared/protocol';
import { D2R, hdgText, norm360, angleDiff } from './geo';
import { MONO } from './dom';

export const COL = {
  bg: '#05070a',
  panel: '#0b0e12',
  tape: '#3b4048',
  tapeEdge: '#59606b',
  white: '#f2f4f5',
  green: '#3ef07a',
  magenta: '#ff4fd8',
  cyan: '#38e3ff',
  amber: '#ffb31a',
  red: '#ff3030',
  sky: '#2b78c8',
  ground: '#8a5a2b',
  yellow: '#ffe04a',
  dim: '#7c858f',
};

const f = (px: number, w = 'bold') => `${w} ${px}px ${MONO}`;

export interface PfdExtras {
  pitch: number; // deg, estimated
  bank: number; // deg, estimated (right positive)
  daFt: number;
  flapMin: number;
  /** ms timestamps of the last FMA change per column, for the change box. */
  fmaChanged: number[];
  now: number;
  /** Optimistic selected values while the server catches up. */
  sel: { hdg: number; alt: number; spd: number };
}

export interface FmaCols {
  spd: string;
  lat: string;
  latArmed: string;
  vert: string;
  vertArmed: string;
}

export function fmaFor(ac: OwnAircraft): FmaCols {
  const lat = ac.apMode === 'HDG' ? 'HDG SEL' : 'LOC';
  const latArmed = ac.appArmed && ac.apMode === 'HDG' ? 'LOC' : '';
  let vert: string;
  if (ac.gsCaptured) vert = 'G/S';
  else if (Math.abs(ac.indAlt - ac.selAlt) < 60 && Math.abs(ac.vs) < 300) vert = 'ALT HOLD';
  else vert = ac.selAlt > ac.indAlt ? 'FLCH CLB' : 'FLCH DES';
  const vertArmed = ac.appArmed && !ac.gsCaptured ? 'G/S' : '';
  return { spd: 'SPD', lat, latArmed, vert, vertArmed };
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

// ------------------------------------------------------------------ PFD
export const PFD_W = 640;
export const PFD_H = 600;

export function drawPfd(ctx: CanvasRenderingContext2D, ac: OwnAircraft, ex: PfdExtras): void {
  ctx.fillStyle = COL.bg;
  ctx.fillRect(0, 0, PFD_W, PFD_H);
  const cy = 262;
  drawFma(ctx, ac, ex);
  drawAdi(ctx, ac, ex, 320, cy);
  drawSpeedTape(ctx, ac, ex, 40, cy);
  drawAltTape(ctx, ac, ex, 492, cy);
  drawVsi(ctx, ac, 586, cy);
  drawHeadingTape(ctx, ac, ex, 320, 530);
}

function drawFma(ctx: CanvasRenderingContext2D, ac: OwnAircraft, ex: PfdExtras): void {
  const fma = fmaFor(ac);
  const x0 = 140;
  const w = 100;
  const cols: [string, string][] = [
    [fma.spd, ''],
    [fma.lat, fma.latArmed],
    [fma.vert, fma.vertArmed],
  ];
  ctx.fillStyle = '#000';
  ctx.fillRect(x0, 4, w * 3 + 60, 46);
  ctx.strokeStyle = '#2a2f36';
  ctx.lineWidth = 1.5;
  for (let i = 1; i < 3; i++) {
    ctx.beginPath();
    ctx.moveTo(x0 + i * w, 6);
    ctx.lineTo(x0 + i * w, 48);
    ctx.stroke();
  }
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  cols.forEach(([act, arm], i) => {
    const cx = x0 + i * w + w / 2;
    ctx.font = f(15);
    ctx.fillStyle = COL.green;
    ctx.fillText(act, cx, 17);
    if (ex.now - (ex.fmaChanged[i] ?? 0) < 10000) {
      ctx.strokeStyle = COL.green;
      ctx.lineWidth = 1.5;
      const tw = ctx.measureText(act).width;
      ctx.strokeRect(cx - tw / 2 - 4, 7, tw + 8, 20);
    }
    if (arm) {
      ctx.font = f(13);
      ctx.fillStyle = COL.white;
      ctx.fillText(arm, cx, 38);
    }
  });
  // AP status
  ctx.font = f(15);
  ctx.fillStyle = COL.green;
  ctx.fillText('CMD', x0 + 3 * w + 30, 17);
  ctx.font = f(11, 'normal');
  ctx.fillStyle = COL.white;
  ctx.fillText('A/T', x0 + 3 * w + 30, 38);
}

function drawAdi(ctx: CanvasRenderingContext2D, ac: OwnAircraft, ex: PfdExtras, cx: number, cy: number): void {
  const bw = 270;
  const bh = 280;
  const bx = cx - bw / 2;
  const by = cy - bh / 2 + 6;
  const PPD = 7;
  ctx.save();
  roundRect(ctx, bx, by, bw, bh, 22);
  ctx.clip();
  ctx.translate(cx, cy);
  ctx.rotate(-ex.bank * D2R);
  const hy = ex.pitch * PPD;
  ctx.fillStyle = COL.sky;
  ctx.fillRect(-500, -900 + hy, 1000, 900);
  ctx.fillStyle = COL.ground;
  ctx.fillRect(-500, hy, 1000, 900);
  ctx.strokeStyle = COL.white;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(-500, hy);
  ctx.lineTo(500, hy);
  ctx.stroke();
  // pitch ladder (clipped to a central window)
  ctx.save();
  ctx.beginPath();
  ctx.rect(-80, -105, 160, 190);
  ctx.clip();
  ctx.lineWidth = 1.5;
  ctx.font = f(11);
  ctx.textBaseline = 'middle';
  for (let p = -30; p <= 30; p += 2.5) {
    if (p === 0) continue;
    const y = hy - p * PPD;
    const major = p % 10 === 0;
    const mid = p % 5 === 0;
    const half = major ? 40 : mid ? 22 : 10;
    ctx.strokeStyle = COL.white;
    ctx.beginPath();
    ctx.moveTo(-half, y);
    ctx.lineTo(half, y);
    ctx.stroke();
    if (major) {
      ctx.fillStyle = COL.white;
      ctx.textAlign = 'right';
      ctx.fillText(String(Math.abs(p)), -half - 4, y);
      ctx.textAlign = 'left';
      ctx.fillText(String(Math.abs(p)), half + 4, y);
    }
  }
  ctx.restore();
  // bank pointer (sky pointer rotates with the horizon)
  ctx.fillStyle = COL.white;
  ctx.beginPath();
  ctx.moveTo(0, -118);
  ctx.lineTo(-8, -104);
  ctx.lineTo(8, -104);
  ctx.closePath();
  ctx.fill();
  ctx.restore();

  // fixed bank scale
  ctx.save();
  ctx.translate(cx, cy);
  ctx.strokeStyle = COL.white;
  ctx.lineWidth = 2;
  for (const a of [-60, -45, -30, -20, -10, 10, 20, 30, 45, 60]) {
    const r1 = 120;
    const len = Math.abs(a) === 30 || Math.abs(a) === 60 ? 14 : 8;
    const s = Math.sin(a * D2R);
    const c = Math.cos(a * D2R);
    ctx.beginPath();
    ctx.moveTo(s * r1, -c * r1);
    ctx.lineTo(s * (r1 + len), -c * (r1 + len));
    ctx.stroke();
  }
  ctx.beginPath();
  ctx.arc(0, 0, 120, -Math.PI / 2 - 60 * D2R, -Math.PI / 2 + 60 * D2R);
  ctx.stroke();
  ctx.fillStyle = COL.white;
  ctx.beginPath();
  ctx.moveTo(0, -121);
  ctx.lineTo(-7, -134);
  ctx.lineTo(7, -134);
  ctx.closePath();
  ctx.fill();
  ctx.restore();

  // aircraft symbol
  ctx.save();
  ctx.translate(cx, cy);
  ctx.fillStyle = '#000';
  ctx.strokeStyle = COL.yellow;
  ctx.lineWidth = 2.5;
  for (const sgn of [-1, 1]) {
    ctx.beginPath();
    ctx.moveTo(sgn * 95, -4);
    ctx.lineTo(sgn * 45, -4);
    ctx.lineTo(sgn * 45, 14);
    ctx.lineTo(sgn * 37, 14);
    ctx.lineTo(sgn * 37, 4);
    ctx.lineTo(sgn * 95, 4);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
  }
  ctx.fillRect(-5, -5, 10, 10);
  ctx.strokeRect(-5, -5, 10, 10);
  ctx.restore();

  // frame
  ctx.strokeStyle = '#1a1e24';
  ctx.lineWidth = 2;
  roundRect(ctx, bx, by, bw, bh, 22);
  ctx.stroke();

  // minimums / radio altitude
  const belowMins = ac.indAlt < ex.daFt && ac.status === 'flying';
  ctx.textAlign = 'right';
  ctx.textBaseline = 'top';
  ctx.font = f(11, 'normal');
  ctx.fillStyle = belowMins ? COL.amber : COL.green;
  ctx.fillText('BARO', bx + bw - 10, by + 8);
  ctx.font = f(15);
  ctx.fillText(String(ex.daFt), bx + bw - 10, by + 21);
  if (belowMins && ac.radAlt !== null && Math.floor(ex.now / 500) % 2 === 0) {
    ctx.textAlign = 'center';
    ctx.font = f(18);
    ctx.fillStyle = COL.amber;
    ctx.fillText('MINIMUMS', cx, cy + 40);
  }
  if (ac.radAlt !== null) {
    const ra = ac.radAlt;
    const shown = ra < 10 ? Math.max(0, Math.round(ra)) : ra < 50 ? Math.round(ra / 2) * 2 : ra < 500 ? Math.round(ra / 10) * 10 : Math.round(ra / 20) * 20;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    ctx.font = f(22);
    ctx.fillStyle = '#000';
    const txt = String(shown);
    const tw = ctx.measureText(txt).width;
    ctx.fillRect(cx - tw / 2 - 6, by + bh - 38, tw + 12, 28);
    ctx.fillStyle = belowMins ? COL.amber : COL.white;
    ctx.fillText(txt, cx, by + bh - 12);
    ctx.font = f(10, 'normal');
    ctx.fillStyle = COL.dim;
    ctx.fillText('RADIO', cx, by + bh - 40);
  }

  // ILS ident
  ctx.textAlign = 'left';
  ctx.textBaseline = 'top';
  ctx.font = f(11, 'normal');
  if (ac.locDev !== null || ac.gsDev !== null) {
    ctx.fillStyle = COL.white;
    ctx.fillText('IFTW/270°', bx + 8, by + 8);
    ctx.fillText(`DME ${ac.dme.toFixed(1)}`, bx + 8, by + 22);
  }

  // localizer scale
  if (ac.locDev !== null) {
    const ly = by + bh + 16;
    const dot = 34;
    ctx.strokeStyle = COL.white;
    ctx.lineWidth = 1.5;
    for (const d of [-2, -1, 1, 2]) {
      ctx.beginPath();
      ctx.arc(cx + d * dot, ly, 4.5, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.beginPath();
    ctx.moveTo(cx, ly - 9);
    ctx.lineTo(cx, ly + 9);
    ctx.stroke();
    const dv = Math.max(-2.5, Math.min(2.5, ac.locDev));
    diamond(ctx, cx + dv * dot, ly, 13, 7, Math.abs(ac.locDev) >= 2.5);
  }
  // glideslope scale
  if (ac.gsDev !== null) {
    const gx = bx + bw + 16;
    const dot = 34;
    ctx.strokeStyle = COL.white;
    ctx.lineWidth = 1.5;
    for (const d of [-2, -1, 1, 2]) {
      ctx.beginPath();
      ctx.arc(gx, cy + d * dot, 4.5, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.beginPath();
    ctx.moveTo(gx - 9, cy);
    ctx.lineTo(gx + 9, cy);
    ctx.stroke();
    const dv = Math.max(-2.5, Math.min(2.5, ac.gsDev));
    // positive = fly up = beam is above
    diamond(ctx, gx, cy - dv * dot, 7, 13, Math.abs(ac.gsDev) >= 2.5);
  }

  // big PULL UP on the attitude display
  const pull = ac.warnings.some((w) => w === 'PULL UP');
  const terr = ac.warnings.some((w) => w === 'TERRAIN');
  if ((pull || terr) && Math.floor(ex.now / 350) % 2 === 0) {
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.font = f(30);
    const txt = pull ? 'PULL UP' : 'TERRAIN';
    const tw = ctx.measureText(txt).width;
    ctx.fillStyle = 'rgba(0,0,0,0.75)';
    ctx.fillRect(cx - tw / 2 - 10, cy - 70 - 20, tw + 20, 40);
    ctx.fillStyle = pull ? COL.red : COL.amber;
    ctx.fillText(txt, cx, cy - 70);
  }
}

function diamond(ctx: CanvasRenderingContext2D, x: number, y: number, rw: number, rh: number, pegged: boolean): void {
  ctx.beginPath();
  ctx.moveTo(x, y - rh);
  ctx.lineTo(x + rw, y);
  ctx.lineTo(x, y + rh);
  ctx.lineTo(x - rw, y);
  ctx.closePath();
  if (pegged) {
    ctx.strokeStyle = COL.magenta;
    ctx.lineWidth = 2;
    ctx.stroke();
  } else {
    ctx.fillStyle = COL.magenta;
    ctx.fill();
  }
}

function drawSpeedTape(ctx: CanvasRenderingContext2D, ac: OwnAircraft, ex: PfdExtras, x: number, cy: number): void {
  const w = 76;
  const half = 200;
  const PPK = 3.4;
  const top = cy - half;
  // selected speed
  ctx.font = f(17);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'bottom';
  ctx.fillStyle = COL.magenta;
  ctx.fillText(String(Math.round(ex.sel.spd)), x + w / 2, top - 6);

  ctx.save();
  ctx.beginPath();
  ctx.rect(x, top, w, half * 2);
  ctx.clip();
  ctx.fillStyle = COL.tape;
  ctx.fillRect(x, top, w, half * 2);
  const yOf = (kt: number) => cy - (kt - ac.ias) * PPK;
  // low speed bands
  const lo = ex.flapMin;
  ctx.fillStyle = COL.amber;
  ctx.fillRect(x + w - 6, yOf(lo), 4, yOf(lo - 15) - yOf(lo));
  barber(ctx, x + w - 8, yOf(lo - 15), 8, 600);
  // overspeed (250 below 10 000)
  barber(ctx, x + w - 8, yOf(250) - 600, 8, 600);
  ctx.strokeStyle = COL.white;
  ctx.fillStyle = COL.white;
  ctx.lineWidth = 2;
  ctx.font = f(15);
  ctx.textAlign = 'right';
  ctx.textBaseline = 'middle';
  const lo10 = Math.floor((ac.ias - 70) / 10) * 10;
  for (let v = Math.max(0, lo10); v <= ac.ias + 70; v += 10) {
    const y = yOf(v);
    ctx.beginPath();
    ctx.moveTo(x + w - 14, y);
    ctx.lineTo(x + w, y);
    ctx.stroke();
    if (v % 20 === 0) ctx.fillText(String(v), x + w - 18, y);
  }
  // selected speed bug
  const sy = Math.max(top + 6, Math.min(top + half * 2 - 6, yOf(ex.sel.spd)));
  ctx.strokeStyle = COL.magenta;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.moveTo(x + w, sy - 9);
  ctx.lineTo(x + w - 9, sy - 9);
  ctx.lineTo(x + w - 9, sy - 4);
  ctx.lineTo(x + w - 4, sy);
  ctx.lineTo(x + w - 9, sy + 4);
  ctx.lineTo(x + w - 9, sy + 9);
  ctx.lineTo(x + w, sy + 9);
  ctx.stroke();
  ctx.restore();

  // readout box
  ctx.fillStyle = '#000';
  ctx.strokeStyle = COL.white;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(x + 2, cy - 18);
  ctx.lineTo(x + w - 14, cy - 18);
  ctx.lineTo(x + w - 14, cy - 8);
  ctx.lineTo(x + w - 2, cy);
  ctx.lineTo(x + w - 14, cy + 8);
  ctx.lineTo(x + w - 14, cy + 18);
  ctx.lineTo(x + 2, cy + 18);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  ctx.fillStyle = ac.ias < lo - 2 ? COL.amber : COL.white;
  ctx.font = f(22);
  ctx.textAlign = 'right';
  ctx.textBaseline = 'middle';
  ctx.fillText(String(Math.round(ac.ias)), x + w - 18, cy + 1);

  ctx.font = f(11, 'normal');
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  ctx.fillStyle = COL.dim;
  ctx.fillText('IAS KT', x + w / 2, top + half * 2 + 6);
  ctx.fillStyle = COL.white;
  ctx.fillText(`F${ac.flaps} MIN ${lo}`, x + w / 2, top + half * 2 + 20);
}

function barber(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
  ctx.save();
  ctx.beginPath();
  ctx.rect(x, y, w, h);
  ctx.clip();
  ctx.fillStyle = '#000';
  ctx.fillRect(x, y, w, h);
  ctx.fillStyle = COL.red;
  for (let yy = y - 20; yy < y + h; yy += 12) ctx.fillRect(x, yy, w, 6);
  ctx.restore();
}

function drawAltTape(ctx: CanvasRenderingContext2D, ac: OwnAircraft, ex: PfdExtras, x: number, cy: number): void {
  const w = 84;
  const half = 200;
  const PPF = 0.3;
  const top = cy - half;
  const yOf = (ft: number) => cy - (ft - ac.indAlt) * PPF;

  // selected altitude
  ctx.font = f(17);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'bottom';
  ctx.fillStyle = COL.magenta;
  ctx.fillText(String(Math.round(ex.sel.alt)), x + w / 2, top - 6);

  ctx.save();
  ctx.beginPath();
  ctx.rect(x, top, w, half * 2);
  ctx.clip();
  ctx.fillStyle = COL.tape;
  ctx.fillRect(x, top, w, half * 2);
  // ground (from the radio altimeter)
  if (ac.radAlt !== null) {
    const gy = yOf(ac.indAlt - ac.radAlt);
    ctx.fillStyle = '#5a3d1c';
    ctx.fillRect(x, gy, w, 800);
    ctx.strokeStyle = COL.amber;
    ctx.lineWidth = 1.5;
    for (let i = -40; i < 60; i++) {
      ctx.beginPath();
      ctx.moveTo(x + i * 10, gy);
      ctx.lineTo(x + i * 10 - 40, gy + 40);
      ctx.stroke();
    }
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(x, gy);
    ctx.lineTo(x + w, gy);
    ctx.stroke();
  }
  ctx.strokeStyle = COL.white;
  ctx.fillStyle = COL.white;
  ctx.lineWidth = 2;
  ctx.font = f(14);
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  const lo = Math.floor((ac.indAlt - 800) / 100) * 100;
  for (let a = lo; a <= ac.indAlt + 800; a += 100) {
    const y = yOf(a);
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + (a % 500 === 0 ? 14 : 9), y);
    ctx.stroke();
    if (a % 200 === 0) ctx.fillText(String(a), x + 18, y);
    if (a % 1000 === 0) {
      ctx.beginPath();
      ctx.moveTo(x + 16, y - 9);
      ctx.lineTo(x + w - 4, y - 9);
      ctx.moveTo(x + 16, y + 9);
      ctx.lineTo(x + w - 4, y + 9);
      ctx.stroke();
    }
  }
  // minimums marker
  const my = yOf(ex.daFt);
  ctx.strokeStyle = COL.green;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.moveTo(x, my);
  ctx.lineTo(x + 30, my);
  ctx.stroke();
  // selected altitude bug
  const sy = Math.max(top + 6, Math.min(top + half * 2 - 6, yOf(ex.sel.alt)));
  ctx.strokeStyle = COL.magenta;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.moveTo(x, sy - 11);
  ctx.lineTo(x + 12, sy - 11);
  ctx.lineTo(x + 12, sy - 5);
  ctx.lineTo(x + 6, sy);
  ctx.lineTo(x + 12, sy + 5);
  ctx.lineTo(x + 12, sy + 11);
  ctx.lineTo(x, sy + 11);
  ctx.stroke();
  ctx.restore();

  // readout box
  const alt = Math.round(ac.indAlt / 20) * 20;
  const neg = alt < 0;
  const abs = Math.abs(alt);
  const big = Math.floor(abs / 1000);
  const small = String(abs % 1000).padStart(3, '0');
  ctx.fillStyle = '#000';
  ctx.strokeStyle = COL.white;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(x + w - 2, cy - 20);
  ctx.lineTo(x + 14, cy - 20);
  ctx.lineTo(x + 14, cy - 8);
  ctx.lineTo(x + 2, cy);
  ctx.lineTo(x + 14, cy + 8);
  ctx.lineTo(x + 14, cy + 20);
  ctx.lineTo(x + w - 2, cy + 20);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  const altWarn = ac.radAlt !== null && ac.radAlt < 500 && !ac.gearDown;
  ctx.fillStyle = altWarn ? COL.amber : COL.white;
  ctx.textBaseline = 'middle';
  ctx.textAlign = 'right';
  ctx.font = f(16);
  ctx.fillText(small, x + w - 6, cy + 2);
  const sw = ctx.measureText(small).width;
  ctx.font = f(22);
  ctx.fillText(`${neg ? '-' : ''}${big > 0 ? big : ''}`, x + w - 6 - sw, cy + 1);

  // baro setting
  ctx.font = f(15);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  ctx.fillStyle = COL.green;
  ctx.fillText(ac.altSetting === 1013 ? 'STD' : `${ac.altSetting} HPA`, x + w / 2, top + half * 2 + 6);
  ctx.font = f(11, 'normal');
  ctx.fillStyle = COL.dim;
  ctx.fillText('IND ALT FT', x + w / 2, top + half * 2 + 24);
}

function vsiY(vs: number, half: number): number {
  const a = Math.abs(vs);
  let n: number;
  if (a <= 1000) n = (a / 1000) * 0.5;
  else if (a <= 2000) n = 0.5 + ((a - 1000) / 1000) * 0.25;
  else n = 0.75 + (Math.min(a - 2000, 4000) / 4000) * 0.25;
  return Math.sign(vs) * n * half;
}

function drawVsi(ctx: CanvasRenderingContext2D, ac: OwnAircraft, x: number, cy: number): void {
  const half = 150;
  const w = 44;
  ctx.fillStyle = COL.tape;
  ctx.beginPath();
  ctx.moveTo(x, cy - half + 20);
  ctx.lineTo(x + 12, cy - half);
  ctx.lineTo(x + w, cy - half);
  ctx.lineTo(x + w, cy + half);
  ctx.lineTo(x + 12, cy + half);
  ctx.lineTo(x, cy + half - 20);
  ctx.closePath();
  ctx.fill();
  ctx.strokeStyle = COL.white;
  ctx.fillStyle = COL.white;
  ctx.lineWidth = 1.5;
  ctx.font = f(11);
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  for (const v of [500, 1000, 1500, 2000, 6000]) {
    for (const s of [-1, 1]) {
      const y = cy - vsiY(v * s, half - 10);
      const major = v === 1000 || v === 2000 || v === 6000;
      ctx.beginPath();
      ctx.moveTo(x + 4, y);
      ctx.lineTo(x + (major ? 14 : 9), y);
      ctx.stroke();
      if (major) ctx.fillText(String(v / 1000), x + 17, y);
    }
  }
  ctx.beginPath();
  ctx.moveTo(x + 2, cy);
  ctx.lineTo(x + 16, cy);
  ctx.stroke();
  // needle from a virtual pivot to the right
  const ny = cy - vsiY(ac.vs, half - 10);
  ctx.strokeStyle = COL.white;
  ctx.lineWidth = 3;
  ctx.save();
  ctx.beginPath();
  ctx.rect(x, cy - half, w, half * 2);
  ctx.clip();
  ctx.beginPath();
  ctx.moveTo(x + w + 30, cy);
  ctx.lineTo(x + 4, ny);
  ctx.stroke();
  ctx.restore();
  if (Math.abs(ac.vs) >= 400) {
    ctx.font = f(13);
    ctx.textAlign = 'center';
    ctx.fillStyle = COL.white;
    const txt = String(Math.round(Math.abs(ac.vs) / 50) * 50);
    ctx.fillText(txt, x + w / 2 + 2, ac.vs > 0 ? cy - half - 12 : cy + half + 12);
  }
}

function drawHeadingTape(ctx: CanvasRenderingContext2D, ac: OwnAircraft, ex: PfdExtras, cx: number, y: number): void {
  const w = 300;
  const hgt = 44;
  const PPD = 5;
  const x0 = cx - w / 2;
  ctx.save();
  ctx.beginPath();
  ctx.rect(x0, y, w, hgt);
  ctx.clip();
  ctx.fillStyle = COL.tape;
  ctx.fillRect(x0, y, w, hgt);
  ctx.strokeStyle = COL.white;
  ctx.fillStyle = COL.white;
  ctx.lineWidth = 2;
  ctx.font = f(14);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  const base = Math.floor((ac.hdg - 40) / 5) * 5;
  for (let d = base; d <= ac.hdg + 40; d += 5) {
    const x = cx + angleDiff(ac.hdg, d) * PPD;
    const major = norm360(d) % 10 === 0;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x, y + (major ? 12 : 7));
    ctx.stroke();
    if (major) {
      const n = Math.round(norm360(d) / 10);
      ctx.fillText(String(n === 0 ? 36 : n).padStart(2, '0'), x, y + 16);
    }
  }
  // selected heading bug
  const dh = angleDiff(ac.hdg, ex.sel.hdg);
  const bx = cx + Math.max(-w / 2 + 6, Math.min(w / 2 - 6, dh * PPD));
  ctx.strokeStyle = COL.magenta;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.moveTo(bx - 10, y);
  ctx.lineTo(bx - 10, y + 9);
  ctx.lineTo(bx - 4, y + 9);
  ctx.lineTo(bx, y + 3);
  ctx.lineTo(bx + 4, y + 9);
  ctx.lineTo(bx + 10, y + 9);
  ctx.lineTo(bx + 10, y);
  ctx.stroke();
  ctx.restore();
  // current heading box
  ctx.fillStyle = '#000';
  ctx.strokeStyle = COL.white;
  ctx.lineWidth = 2;
  ctx.fillRect(cx - 26, y - 26, 52, 24);
  ctx.strokeRect(cx - 26, y - 26, 52, 24);
  ctx.beginPath();
  ctx.moveTo(cx, y - 2);
  ctx.lineTo(cx, y + 10);
  ctx.strokeStyle = COL.yellow;
  ctx.stroke();
  ctx.fillStyle = COL.white;
  ctx.font = f(17);
  ctx.textBaseline = 'middle';
  ctx.textAlign = 'center';
  ctx.fillText(hdgText(ac.hdg), cx, y - 13);
  ctx.font = f(14);
  ctx.textAlign = 'right';
  ctx.fillStyle = COL.magenta;
  ctx.fillText(`${hdgText(ex.sel.hdg)}`, x0 - 8, y + 22);
  ctx.fillStyle = COL.green;
  ctx.font = f(11, 'normal');
  ctx.fillText('MAG HDG', x0 - 8, y + 6);
}

// ------------------------------------------------------------------ HSI / ND
export const HSI_W = 420;
export const HSI_H = 420;

export function drawHsi(ctx: CanvasRenderingContext2D, ac: OwnAircraft, selHdg: number, ilsCourse: number): void {
  ctx.fillStyle = COL.bg;
  ctx.fillRect(0, 0, HSI_W, HSI_H);
  const cx = HSI_W / 2;
  const cy = HSI_H / 2 + 14;
  const R = 150;
  // header
  ctx.font = f(13);
  ctx.textBaseline = 'top';
  ctx.textAlign = 'left';
  ctx.fillStyle = COL.green;
  ctx.fillText('HDG', 10, 8);
  ctx.fillStyle = COL.white;
  ctx.fillText(hdgText(ac.hdg), 44, 8);
  ctx.fillStyle = COL.green;
  ctx.fillText('MAG', 82, 8);
  ctx.fillStyle = COL.dim;
  ctx.font = f(11, 'normal');
  ctx.fillText(`IAS ${Math.round(ac.ias)}`, 10, 26);
  ctx.textAlign = 'right';
  ctx.font = f(13);
  ctx.fillStyle = COL.white;
  ctx.fillText(`FTW  ${ac.dme.toFixed(1)} NM`, HSI_W - 10, 8);
  ctx.fillStyle = COL.cyan;
  ctx.font = f(11, 'normal');
  ctx.fillText(`BRG ${hdgText(ac.bearingToStation)}°  VOR/DME`, HSI_W - 10, 26);
  ctx.textAlign = 'left';
  ctx.textBaseline = 'bottom';
  ctx.fillStyle = COL.magenta;
  ctx.fillText(`ILS 27  CRS ${hdgText(ilsCourse)}`, 10, HSI_H - 8);
  ctx.textAlign = 'right';
  ctx.fillStyle = ac.locDev === null ? COL.dim : COL.green;
  ctx.fillText(ac.locDev === null ? 'LOC ----' : ac.apMode === 'HDG' ? 'LOC ALIVE' : 'LOC CAPT', HSI_W - 10, HSI_H - 8);

  ctx.save();
  ctx.translate(cx, cy);
  // rose (rotates, heading up)
  ctx.save();
  ctx.rotate(-ac.hdg * D2R);
  ctx.strokeStyle = COL.white;
  ctx.fillStyle = COL.white;
  ctx.lineWidth = 1.5;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  for (let d = 0; d < 360; d += 5) {
    const a = d * D2R;
    const len = d % 10 === 0 ? 14 : 7;
    ctx.beginPath();
    ctx.moveTo(Math.sin(a) * R, -Math.cos(a) * R);
    ctx.lineTo(Math.sin(a) * (R - len), -Math.cos(a) * (R - len));
    ctx.stroke();
    if (d % 30 === 0) {
      ctx.save();
      ctx.translate(Math.sin(a) * (R - 28), -Math.cos(a) * (R - 28));
      ctx.rotate(a);
      ctx.font = f(d % 90 === 0 ? 17 : 14);
      const lab = d === 0 ? 'N' : d === 90 ? 'E' : d === 180 ? 'S' : d === 270 ? 'W' : String(d / 10);
      ctx.fillText(lab, 0, 0);
      ctx.restore();
    }
  }
  // selected heading bug
  {
    const a = selHdg * D2R;
    ctx.save();
    ctx.rotate(a);
    ctx.strokeStyle = COL.magenta;
    ctx.lineWidth = 2.5;
    ctx.beginPath();
    ctx.moveTo(-11, -R);
    ctx.lineTo(-11, -R - 9);
    ctx.lineTo(-4, -R - 9);
    ctx.lineTo(0, -R - 3);
    ctx.lineTo(4, -R - 9);
    ctx.lineTo(11, -R - 9);
    ctx.lineTo(11, -R);
    ctx.stroke();
    ctx.restore();
  }
  // course pointer + CDI
  {
    ctx.save();
    ctx.rotate(ilsCourse * D2R);
    ctx.strokeStyle = COL.magenta;
    ctx.fillStyle = COL.magenta;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(0, -R + 18);
    ctx.lineTo(0, -60);
    ctx.moveTo(0, 60);
    ctx.lineTo(0, R - 18);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(0, -R + 6);
    ctx.lineTo(-8, -R + 22);
    ctx.lineTo(8, -R + 22);
    ctx.closePath();
    ctx.fill();
    // deviation dots
    const dot = 26;
    ctx.strokeStyle = COL.white;
    ctx.lineWidth = 1.5;
    for (const d of [-2, -1, 1, 2]) {
      ctx.beginPath();
      ctx.arc(d * dot, 0, 4, 0, Math.PI * 2);
      ctx.stroke();
    }
    if (ac.locDev !== null) {
      const dv = Math.max(-2.5, Math.min(2.5, ac.locDev));
      ctx.strokeStyle = COL.magenta;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.moveTo(dv * dot, -56);
      ctx.lineTo(dv * dot, 56);
      ctx.stroke();
    } else {
      ctx.fillStyle = COL.red;
      ctx.font = f(12);
      ctx.fillText('LOC', -40, -30);
    }
    ctx.restore();
  }
  // bearing pointer to the station
  {
    ctx.save();
    ctx.rotate(ac.bearingToStation * D2R);
    ctx.strokeStyle = COL.cyan;
    ctx.fillStyle = COL.cyan;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(-3, R - 4);
    ctx.lineTo(-3, R - 38);
    ctx.moveTo(3, R - 4);
    ctx.lineTo(3, R - 38);
    ctx.moveTo(-3, -R + 40);
    ctx.lineTo(-3, -R + 4);
    ctx.moveTo(3, -R + 40);
    ctx.lineTo(3, -R + 4);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(0, -R + 2);
    ctx.lineTo(-9, -R + 18);
    ctx.lineTo(9, -R + 18);
    ctx.closePath();
    ctx.stroke();
    ctx.restore();
  }
  ctx.restore(); // rose rotation
  ctx.restore(); // centre translation

  // aircraft symbol and lubber line (fixed)
  ctx.save();
  ctx.translate(cx, cy);
  ctx.strokeStyle = COL.yellow;
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(0, -16);
  ctx.lineTo(0, 18);
  ctx.moveTo(-16, -2);
  ctx.lineTo(16, -2);
  ctx.moveTo(-7, 14);
  ctx.lineTo(7, 14);
  ctx.stroke();
  ctx.fillStyle = COL.white;
  ctx.beginPath();
  ctx.moveTo(0, -R + 2);
  ctx.lineTo(-9, -R - 14);
  ctx.lineTo(9, -R - 14);
  ctx.closePath();
  ctx.strokeStyle = COL.white;
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.restore();
}
