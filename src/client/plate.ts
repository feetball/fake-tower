// Instrument approach chart (ILS RWY 27) drawn from the WorldDef, in the
// style of a real approach plate: briefing strip, MSA, plan view, profile
// view, minimums and missed approach.

import type { WorldDef } from '../shared/world';
import { D2R, fafDist, hdgText, holdPath, pointAt } from './geo';
import { SANS } from './dom';

export const PLATE_W = 800;
export const PLATE_H = 1100;

/** Invented: WorldDef carries no navaid frequencies. Display-only. */
export const ILS_IDENT = 'IFTW';
export const ILS_FREQ = '109.90';

const INK = '#141414';
const PAPER = '#fbfaf4';
const TERR = '#d9c29a';
const TERR_INK = '#7a5a26';
const GREY = '#666';

const font = (px: number, w = 'normal') => `${w} ${px}px ${SANS}`;

function wrap(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, maxW: number, lh: number): number {
  const words = text.split(/\s+/);
  let line = '';
  for (const w of words) {
    const t = line ? `${line} ${w}` : w;
    if (ctx.measureText(t).width > maxW && line) {
      ctx.fillText(line, x, y);
      y += lh;
      line = w;
    } else line = t;
  }
  if (line) {
    ctx.fillText(line, x, y);
    y += lh;
  }
  return y;
}

function box(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
  ctx.strokeStyle = INK;
  ctx.lineWidth = 1.2;
  ctx.strokeRect(x, y, w, h);
}

function fixTriangle(ctx: CanvasRenderingContext2D, x: number, y: number, filled: boolean, s = 7): void {
  ctx.beginPath();
  ctx.moveTo(x, y - s);
  ctx.lineTo(x + s * 0.9, y + s * 0.65);
  ctx.lineTo(x - s * 0.9, y + s * 0.65);
  ctx.closePath();
  ctx.lineWidth = 1.4;
  ctx.strokeStyle = INK;
  if (filled) {
    ctx.fillStyle = INK;
    ctx.fill();
  } else {
    ctx.fillStyle = PAPER;
    ctx.fill();
    ctx.stroke();
  }
}

function maltese(ctx: CanvasRenderingContext2D, x: number, y: number, s: number): void {
  ctx.fillStyle = INK;
  for (let i = 0; i < 4; i++) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate((i * Math.PI) / 2);
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(-s * 0.45, -s);
    ctx.lineTo(s * 0.45, -s);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }
}

function arrowHead(ctx: CanvasRenderingContext2D, x: number, y: number, ang: number, s = 9): void {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(ang);
  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.lineTo(-s, -s * 0.45);
  ctx.lineTo(-s, s * 0.45);
  ctx.closePath();
  ctx.fill();
  ctx.restore();
}

export function drawPlate(ctx: CanvasRenderingContext2D, world: WorldDef, qnh: number | null): void {
  const W = PLATE_W;
  ctx.fillStyle = PAPER;
  ctx.fillRect(0, 0, W, PLATE_H);
  ctx.fillStyle = INK;
  ctx.strokeStyle = INK;
  const M = 24;
  const fafD = fafDist(world);
  const fafAlt = world.ils.platformAltFt;
  const daH = world.ils.daFt - world.fieldElevFt;

  // ------------------------------------------------------------ title
  ctx.textBaseline = 'alphabetic';
  ctx.textAlign = 'left';
  ctx.font = font(24, 'bold');
  ctx.fillText(world.icao, M, 38);
  ctx.font = font(15);
  ctx.fillText(world.name.toUpperCase(), M + 82, 37);
  ctx.textAlign = 'right';
  ctx.font = font(26, 'bold');
  ctx.fillText(`ILS RWY ${world.runway.name}`, W - M, 40);
  ctx.font = font(11);
  ctx.fillStyle = GREY;
  ctx.fillText('AMDT 1   25 NOV 26', W - M, 56);
  ctx.textAlign = 'left';
  ctx.fillText('FAKE TOWER APPROACH CHART', M, 56);
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(M, 64);
  ctx.lineTo(W - M, 64);
  ctx.stroke();

  // ------------------------------------------------------------ briefing strip
  const cells: [string, string][] = [
    ['LOC', `${ILS_IDENT}  ${ILS_FREQ}`],
    ['Final Apch Crs', `${hdgText(world.ils.courseDeg)}°`],
    [`GS ${world.ils.faf.name}`, `${fafAlt}'`],
    ['ILS DA(H)', `${world.ils.daFt}' (${daH}')`],
    ['Apt Elev / TDZE', `${world.fieldElevFt}' / ${world.fieldElevFt}'`],
  ];
  const cw = (W - 2 * M) / cells.length;
  cells.forEach(([lab, val], i) => {
    const x = M + i * cw;
    box(ctx, x, 70, cw, 50);
    ctx.fillStyle = GREY;
    ctx.font = font(11);
    ctx.textAlign = 'left';
    ctx.fillText(lab, x + 6, 86);
    ctx.fillStyle = INK;
    ctx.font = font(17, 'bold');
    ctx.fillText(val, x + 6, 110);
  });

  // missed approach + notes, MSA diagram on the right
  box(ctx, M, 126, W - 2 * M - 170, 84);
  ctx.font = font(11, 'bold');
  ctx.fillStyle = INK;
  ctx.fillText('MISSED APPROACH:', M + 6, 142);
  ctx.font = font(12);
  let ty = wrap(ctx, world.missedApproach, M + 6, 158, W - 2 * M - 190, 15);
  ctx.font = font(11);
  ctx.fillStyle = GREY;
  wrap(
    ctx,
    `Alt set: hPa${qnh ? ` (QNH ${qnh} from ATIS)` : ''}.  Trans alt: ${world.transitionAltFt}'.  Radar required. Hold ${world.hold.fix}: ${hdgText(world.hold.inboundCourseDeg)}° inbound, ${world.hold.turn === 'R' ? 'right' : 'left'} turns, min ${world.hold.minAltFt}'.`,
    M + 6,
    ty + 2,
    W - 2 * M - 190,
    14,
  );
  // MSA inset
  {
    const bx = W - M - 164;
    box(ctx, bx, 126, 164, 84);
    const cx = bx + 116;
    const cy = 168;
    const r = 36;
    ctx.fillStyle = INK;
    ctx.font = font(10, 'bold');
    ctx.textAlign = 'left';
    ctx.fillText('MSA', bx + 6, 142);
    ctx.font = font(9);
    ctx.fillText('FTW DME', bx + 6, 156);
    ctx.fillText('25 NM', bx + 6, 168);
    ctx.lineWidth = 1.2;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
    for (const s of world.msa) {
      const a = s.fromDeg * D2R;
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx + Math.sin(a) * r, cy - Math.cos(a) * r);
      ctx.stroke();
    }
    ctx.font = font(10, 'bold');
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (const s of world.msa) {
      let span = s.toDeg - s.fromDeg;
      if (span <= 0) span += 360;
      const a = (s.fromDeg + span / 2) * D2R;
      ctx.fillText(String(s.altFt), cx + Math.sin(a) * r * 0.58, cy - Math.cos(a) * r * 0.58);
    }
    ctx.font = font(8);
    for (const s of world.msa) {
      const a = s.fromDeg * D2R;
      ctx.fillText(`${hdgText(s.fromDeg)}°`, cx + Math.sin(a) * (r + 9), cy - Math.cos(a) * (r + 9));
    }
    ctx.textBaseline = 'alphabetic';
  }

  // ------------------------------------------------------------ plan view
  const pv = { x: M, y: 218, w: W - 2 * M, h: 530 };
  box(ctx, pv.x, pv.y, pv.w, pv.h);
  {
    const xs: number[] = [];
    const ys: number[] = [];
    for (const f of world.fixes) {
      xs.push(f.x);
      ys.push(f.y);
    }
    for (const t of world.terrain) {
      xs.push(t.x - t.radiusNm, t.x + t.radiusNm);
      ys.push(t.y - t.radiusNm, t.y + t.radiusNm);
    }
    xs.push(0, -world.runway.lengthNm - 4);
    ys.push(0);
    const minX = Math.min(...xs) - 3;
    const maxX = Math.max(...xs) + 3;
    const minY = Math.min(...ys) - 3;
    const maxY = Math.max(...ys) + 3;
    const k = Math.min(pv.w / (maxX - minX), pv.h / (maxY - minY));
    const cxW = (minX + maxX) / 2;
    const cyW = (minY + maxY) / 2;
    const P = (x: number, y: number): [number, number] => [pv.x + pv.w / 2 + (x - cxW) * k, pv.y + pv.h / 2 - (y - cyW) * k];

    ctx.save();
    ctx.beginPath();
    ctx.rect(pv.x + 1, pv.y + 1, pv.w - 2, pv.h - 2);
    ctx.clip();

    // 10 NM ring around the field
    {
      const [x, y] = P(0, 0);
      ctx.strokeStyle = '#aaa';
      ctx.setLineDash([2, 4]);
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.arc(x, y, 10 * k, 0, Math.PI * 2);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = '#999';
      ctx.font = font(9);
      ctx.textAlign = 'left';
      ctx.fillText('10 NM', x + 10 * k * 0.71 + 3, y - 10 * k * 0.71);
    }

    // terrain
    for (const t of world.terrain) {
      const [x, y] = P(t.x, t.y);
      const g = ctx.createRadialGradient(x, y, 0, x, y, t.radiusNm * k);
      g.addColorStop(0, '#cfa86a');
      g.addColorStop(1, TERR);
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(x, y, t.radiusNm * k, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = TERR_INK;
      ctx.lineWidth = 1;
      ctx.stroke();
      ctx.fillStyle = INK;
      ctx.beginPath();
      ctx.moveTo(x, y - 5);
      ctx.lineTo(x + 4, y + 2);
      ctx.lineTo(x - 4, y + 2);
      ctx.closePath();
      ctx.fill();
      ctx.font = font(12, 'bold');
      ctx.textAlign = 'center';
      ctx.fillText(String(t.elevFt), x, y + 16);
      ctx.font = font(9);
      ctx.fillStyle = TERR_INK;
      ctx.fillText(t.name.toUpperCase(), x, y + 28);
    }

    // localizer feather
    {
      const back = world.ils.courseDeg + 180;
      const len = Math.min(world.ils.rangeNm, 18);
      const far = pointAt(0, 0, back, len);
      const sideA = pointAt(far.x, far.y, back + 90, 0.9);
      const sideB = pointAt(far.x, far.y, back - 90, 0.9);
      const [x0, y0] = P(0, 0);
      const [xa, ya] = P(sideA.x, sideA.y);
      const [xb, yb] = P(sideB.x, sideB.y);
      const [xf, yf] = P(far.x, far.y);
      ctx.fillStyle = 'rgba(20,20,20,0.08)';
      ctx.strokeStyle = INK;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.lineTo(xa, ya);
      ctx.lineTo(xb, yb);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.lineTo(xf, yf);
      ctx.stroke();
      ctx.fillStyle = INK;
      arrowHead(ctx, (x0 + xf) / 2, y0, Math.PI, 10);
      ctx.font = font(14, 'bold');
      ctx.textAlign = 'center';
      ctx.fillText(`${hdgText(world.ils.courseDeg)}°`, P(far.x * 0.6, 0)[0], y0 + 22);
      // ident box (bottom-right corner, with a leader to the localizer)
      const bxw = 128;
      const lx = pv.x + pv.w - bxw - 10;
      const ly = pv.y + pv.h - 46;
      ctx.strokeStyle = '#888';
      ctx.lineWidth = 0.8;
      ctx.beginPath();
      ctx.moveTo(lx + 20, ly);
      ctx.lineTo(xf - 20, yf + 4);
      ctx.stroke();
      ctx.fillStyle = PAPER;
      ctx.fillRect(lx, ly, bxw, 36);
      box(ctx, lx, ly, bxw, 36);
      ctx.fillStyle = INK;
      ctx.font = font(10);
      ctx.textAlign = 'left';
      ctx.fillText(`ILS/DME  ${hdgText(world.ils.courseDeg)}°`, lx + 6, ly + 13);
      ctx.font = font(13, 'bold');
      ctx.fillText(`${ILS_IDENT} ${ILS_FREQ}`, lx + 6, ly + 29);
    }

    // missed approach path (dashed): straight ahead, climbing right turn hdg 060, to hold fix
    {
      const hf = world.fixes.find((f) => f.name === world.hold.fix);
      const end = pointAt(0, 0, world.runway.headingDeg, world.runway.lengthNm);
      const straight = pointAt(end.x, end.y, world.runway.headingDeg, 3);
      const r = 2.2;
      const startHdg = world.runway.headingDeg;
      const centre = pointAt(straight.x, straight.y, startHdg + 90, r);
      const pts: { x: number; y: number }[] = [end, straight];
      const turnTo = 60;
      let turn = turnTo - startHdg;
      while (turn <= 0) turn += 360;
      for (let i = 1; i <= 20; i++) {
        const h = startHdg + (turn * i) / 20;
        pts.push(pointAt(centre.x, centre.y, h - 90, r));
      }
      const last = pts[pts.length - 1]!;
      const leg = pointAt(last.x, last.y, turnTo, 2.5);
      pts.push(leg);
      ctx.strokeStyle = INK;
      ctx.lineWidth = 1.5;
      ctx.setLineDash([7, 5]);
      ctx.beginPath();
      pts.forEach((p, i) => {
        const [x, y] = P(p.x, p.y);
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      });
      if (hf) {
        const [x, y] = P(hf.x, hf.y);
        ctx.lineTo(x, y);
      }
      ctx.stroke();
      ctx.setLineDash([]);
      const [lx, ly] = P(leg.x, leg.y);
      ctx.fillStyle = INK;
      ctx.font = font(10);
      ctx.textAlign = 'left';
      ctx.fillText(`MISSED APCH ${hdgText(turnTo)}°`, lx - 30, ly - 8);
    }

    // hold
    {
      const pts = holdPath(world, 200);
      ctx.strokeStyle = INK;
      ctx.lineWidth = 1.6;
      ctx.beginPath();
      pts.forEach((p, i) => {
        const [x, y] = P(p.x, p.y);
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      });
      ctx.stroke();
      const hf = world.fixes.find((f) => f.name === world.hold.fix);
      if (hf && pts[0]) {
        const [x0, y0] = P(pts[0].x, pts[0].y);
        const [x1, y1] = P(hf.x, hf.y);
        ctx.fillStyle = INK;
        arrowHead(ctx, (x0 + x1) / 2, (y0 + y1) / 2, Math.atan2(y1 - y0, x1 - x0), 9);
        ctx.font = font(11, 'bold');
        ctx.textAlign = 'center';
        ctx.fillText(`${hdgText(world.hold.inboundCourseDeg)}°`, (x0 + x1) / 2 - 18, (y0 + y1) / 2 + 18);
        ctx.font = font(10);
        ctx.fillText(`MHA ${world.hold.minAltFt}`, (x0 + x1) / 2 - 18, (y0 + y1) / 2 + 31);
      }
    }

    // fixes
    for (const f of world.fixes) {
      const [x, y] = P(f.x, f.y);
      const faf = f.name === world.ils.faf.name;
      if (faf) maltese(ctx, x, y, 8);
      else fixTriangle(ctx, x, y, false);
      ctx.fillStyle = INK;
      ctx.font = font(12, 'bold');
      ctx.textAlign = 'left';
      const d = Math.hypot(f.x, f.y);
      const lx = x + 9;
      const ly = faf ? y - 24 : y - 4;
      ctx.fillText(f.name, lx, ly);
      ctx.font = font(10);
      ctx.fillText(`D${d.toFixed(1)} ${ILS_IDENT}`, lx, ly + 13);
      if (f.name === world.hold.fix) ctx.fillText(`${world.hold.minAltFt}`, lx, ly + 25);
      else if (faf) ctx.fillText(`${world.ils.platformAltFt}  FAF`, lx, ly + 25);
    }

    // runway + VOR/DME
    {
      const end = pointAt(0, 0, world.runway.headingDeg, world.runway.lengthNm);
      const [x0, y0] = P(0, 0);
      const [x1, y1] = P(end.x, end.y);
      ctx.strokeStyle = INK;
      ctx.lineWidth = 6;
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.lineTo(x1, y1);
      ctx.stroke();
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      // VOR/DME symbol (hexagon in a square)
      const vx = x0;
      const vy = y0 + 22;
      for (let i = 0; i < 6; i++) {
        const a = (i * Math.PI) / 3;
        const px = vx + Math.cos(a) * 6;
        const py = vy + Math.sin(a) * 6;
        if (i === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.closePath();
      ctx.stroke();
      ctx.strokeRect(vx - 8, vy - 8, 16, 16);
      ctx.font = font(10, 'bold');
      ctx.fillStyle = INK;
      ctx.textAlign = 'right';
      ctx.fillText('FTW VOR/DME', vx - 12, vy + 4);
      ctx.font = font(10);
      ctx.fillText(`${world.fieldElevFt}`, x1 - 10, y1 - 10);
    }

    ctx.restore();

    // north arrow + scale bar
    {
      const nx = pv.x + 30;
      const ny = pv.y + 40;
      ctx.fillStyle = INK;
      ctx.beginPath();
      ctx.moveTo(nx, ny - 22);
      ctx.lineTo(nx + 7, ny);
      ctx.lineTo(nx, ny - 6);
      ctx.lineTo(nx - 7, ny);
      ctx.closePath();
      ctx.fill();
      ctx.font = font(12, 'bold');
      ctx.textAlign = 'center';
      ctx.fillText('N', nx, ny + 16);
      const sx = pv.x + 16;
      const sy = pv.y + pv.h - 18;
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = INK;
      ctx.beginPath();
      ctx.moveTo(sx, sy);
      ctx.lineTo(sx + 10 * k, sy);
      for (let i = 0; i <= 10; i += 5) {
        ctx.moveTo(sx + i * k, sy - 5);
        ctx.lineTo(sx + i * k, sy + 5);
      }
      ctx.stroke();
      ctx.font = font(10);
      ctx.fillText('0', sx, sy - 8);
      ctx.fillText('5', sx + 5 * k, sy - 8);
      ctx.fillText('10 NM', sx + 10 * k, sy - 8);
    }
  }

  // ------------------------------------------------------------ profile view
  const pf = { x: M, y: 756, w: W - 2 * M, h: 190 };
  box(ctx, pf.x, pf.y, pf.w, pf.h);
  {
    const ridge = world.fixes.find((f) => f.name === 'RIDGE');
    const ridgeD = ridge ? Math.hypot(ridge.x, ridge.y) : fafD + 6;
    const maxD = Math.ceil(ridgeD + 2);
    const gx0 = pf.x + 40; // far end (maxD)
    const gx1 = pf.x + pf.w - 150; // threshold
    const groundY = pf.y + pf.h - 34;
    const topY = pf.y + 30;
    const maxAlt = Math.max(fafAlt + 1500, 4000);
    const X = (d: number) => gx1 - (d / maxD) * (gx1 - gx0);
    const Y = (alt: number) => groundY - ((alt - world.fieldElevFt) / (maxAlt - world.fieldElevFt)) * (groundY - topY);

    // ground
    ctx.strokeStyle = INK;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(pf.x + 6, groundY);
    ctx.lineTo(pf.x + pf.w - 6, groundY);
    ctx.stroke();
    // runway
    ctx.lineWidth = 5;
    ctx.beginPath();
    ctx.moveTo(gx1, groundY);
    ctx.lineTo(gx1 + 50, groundY);
    ctx.stroke();
    ctx.font = font(10);
    ctx.fillStyle = INK;
    ctx.textAlign = 'center';
    ctx.fillText(`TDZE ${world.fieldElevFt}`, gx1 + 25, groundY + 16);
    ctx.fillText(`RWY ${world.runway.name}`, gx1 + 25, groundY + 28);

    // DME scale
    ctx.lineWidth = 1;
    for (let d = 0; d <= maxD; d++) {
      ctx.beginPath();
      ctx.moveTo(X(d), groundY);
      ctx.lineTo(X(d), groundY + (d % 5 === 0 ? 7 : 3));
      ctx.stroke();
    }
    ctx.font = font(9);
    ctx.fillStyle = GREY;
    for (let d = 0; d <= maxD; d += 2) ctx.fillText(String(d), X(d), groundY + 17);

    // platform segment
    ctx.strokeStyle = INK;
    ctx.fillStyle = INK;
    ctx.lineWidth = 2.2;
    ctx.beginPath();
    ctx.moveTo(X(ridgeD), Y(fafAlt));
    ctx.lineTo(X(fafD), Y(fafAlt));
    ctx.stroke();
    arrowHead(ctx, (X(ridgeD) + X(fafD)) / 2 + 6, Y(fafAlt), 0, 9);
    ctx.font = font(14, 'bold');
    ctx.fillText(`${fafAlt}`, (X(ridgeD) + X(fafD)) / 2, Y(fafAlt) - 10);
    ctx.font = font(11);
    ctx.fillText(`${hdgText(world.ils.courseDeg)}°`, (X(ridgeD) + X(fafD)) / 2, Y(fafAlt) + 18);
    // RIDGE
    if (ridge) {
      ctx.lineWidth = 1;
      ctx.setLineDash([3, 3]);
      ctx.beginPath();
      ctx.moveTo(X(ridgeD), topY - 6);
      ctx.lineTo(X(ridgeD), groundY);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.font = font(11, 'bold');
      ctx.fillText('RIDGE', X(ridgeD), topY - 12);
      ctx.font = font(10);
      ctx.fillText(`D${ridgeD.toFixed(1)}`, X(ridgeD), topY + 2);
    }
    // glidepath
    const thrAlt = world.fieldElevFt + world.ils.tchFt;
    ctx.lineWidth = 2.2;
    ctx.beginPath();
    ctx.moveTo(X(fafD), Y(fafAlt));
    ctx.lineTo(X(0), Y(thrAlt));
    ctx.stroke();
    // FAF
    ctx.lineWidth = 1;
    ctx.setLineDash([3, 3]);
    ctx.beginPath();
    ctx.moveTo(X(fafD), topY - 6);
    ctx.lineTo(X(fafD), groundY);
    ctx.stroke();
    ctx.setLineDash([]);
    maltese(ctx, X(fafD), Y(fafAlt), 8);
    ctx.font = font(11, 'bold');
    ctx.fillText(world.ils.faf.name, X(fafD), topY - 12);
    ctx.font = font(10);
    ctx.fillText(`D${fafD.toFixed(1)}`, X(fafD), topY + 2);
    ctx.font = font(11, 'bold');
    ctx.textAlign = 'left';
    const gmx = (X(fafD) + X(0)) / 2;
    const gmy = (Y(fafAlt) + Y(thrAlt)) / 2;
    ctx.fillText(`GS ${world.ils.glideDeg.toFixed(2)}°`, gmx + 8, gmy - 6);
    ctx.font = font(10);
    ctx.fillText(`TCH ${world.ils.tchFt}`, X(0) + 6, Y(thrAlt) - 8);
    // DA
    ctx.strokeStyle = INK;
    ctx.setLineDash([2, 3]);
    ctx.beginPath();
    const daD = (world.ils.daFt - thrAlt) / (Math.tan(world.ils.glideDeg * D2R) * 6076.12);
    ctx.moveTo(X(daD) - 30, Y(world.ils.daFt));
    ctx.lineTo(X(daD) + 30, Y(world.ils.daFt));
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.font = font(10, 'bold');
    ctx.textAlign = 'right';
    ctx.fillText(`DA ${world.ils.daFt}`, X(daD) - 34, Y(world.ils.daFt) + 4);
    // missed approach climb
    ctx.setLineDash([6, 4]);
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(X(0) + 50, groundY - 4);
    ctx.lineTo(pf.x + pf.w - 30, topY + 30);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = INK;
    arrowHead(ctx, pf.x + pf.w - 30, topY + 30, Math.atan2(topY + 30 - (groundY - 4), pf.x + pf.w - 30 - (X(0) + 50)), 9);
    ctx.font = font(10);
    ctx.textAlign = 'right';
    ctx.fillText('3000', pf.x + pf.w - 18, topY + 14);
    ctx.fillText('then 060° 6000', pf.x + pf.w - 18, topY + 52);
  }

  // ------------------------------------------------------------ minimums & tables
  const my = 952;
  box(ctx, M, my, W - 2 * M, 66);
  {
    const col = (W - 2 * M) / 3;
    for (let i = 1; i < 3; i++) {
      ctx.beginPath();
      ctx.moveTo(M + i * col, my);
      ctx.lineTo(M + i * col, my + 66);
      ctx.stroke();
    }
    ctx.textAlign = 'left';
    ctx.fillStyle = GREY;
    ctx.font = font(11);
    ctx.fillText('CATEGORY', M + 8, my + 16);
    ctx.fillText('S-ILS 27', M + col + 8, my + 16);
    ctx.fillText('CIRCLING', M + 2 * col + 8, my + 16);
    ctx.fillStyle = INK;
    ctx.font = font(16, 'bold');
    ctx.fillText('A  B  C  D', M + 8, my + 44);
    ctx.fillText(`DA ${world.ils.daFt}' (${daH}')`, M + col + 8, my + 40);
    ctx.font = font(12);
    ctx.fillText('RVR 550 m', M + col + 8, my + 60);
    ctx.font = font(13, 'bold');
    ctx.fillText('NOT AUTHORIZED', M + 2 * col + 8, my + 44);
  }
  // rate of descent table
  const ry = my + 72;
  box(ctx, M, ry, W - 2 * M, 50);
  {
    const gsList = [120, 140, 160, 180];
    const tan = Math.tan(world.ils.glideDeg * D2R);
    ctx.font = font(11);
    ctx.fillStyle = GREY;
    ctx.textAlign = 'left';
    ctx.fillText('Gnd speed-Kts', M + 8, ry + 20);
    ctx.fillText(`GS ${world.ils.glideDeg.toFixed(2)}°  ft/min`, M + 8, ry + 40);
    ctx.fillStyle = INK;
    ctx.textAlign = 'center';
    gsList.forEach((g, i) => {
      const x = M + 200 + i * 90;
      ctx.font = font(12, 'bold');
      ctx.fillText(String(g), x, ry + 20);
      ctx.font = font(12);
      ctx.fillText(String(Math.round((g * 6076.12 * tan) / 60 / 10) * 10), x, ry + 40);
    });
    ctx.textAlign = 'left';
    ctx.fillStyle = GREY;
    ctx.fillText(`${world.ils.faf.name} to THR ${fafD.toFixed(1)} NM`, M + 580, ry + 30);
  }
  ctx.font = font(10);
  ctx.fillStyle = GREY;
  ctx.textAlign = 'center';
  ctx.fillText(`${world.icao}  ·  ${world.name.toUpperCase()}  ·  ILS RWY ${world.runway.name}  ·  FICTIONAL — NOT FOR NAVIGATION`, W / 2, PLATE_H - 14);
}
