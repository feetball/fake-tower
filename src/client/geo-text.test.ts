import { describe, expect, it } from 'vitest';
import type { OwnAircraft, Outcome, RoundEvent } from '../shared/protocol';
import * as simGeo from '../shared/sim/geo';
import { WORLD } from '../shared/world';
import { angleDiff, bearingTo, fafDist, hdgText, holdPath, msaAt, norm360, pointAt } from './geo';
import { fmaFor } from './pfd';
import { OUTCOME_SHORT, OUTCOME_TEXT, eventText, mmss } from './text';

describe('client geometry', () => {
  it('norm360 / hdgText', () => {
    expect([norm360(0), norm360(360), norm360(-90), norm360(725)]).toEqual([0, 0, 270, 5]);
    expect(hdgText(0)).toBe('360');
    expect(hdgText(360)).toBe('360');
    expect(hdgText(359.6)).toBe('360');
    expect(hdgText(5)).toBe('005');
    expect(hdgText(-90)).toBe('270');
    expect(hdgText(89.4)).toBe('089');
  });

  it('bearings, angle differences and points agree with the sim geometry', () => {
    expect(bearingTo(0, 0, 0, 1)).toBeCloseTo(0);
    expect(bearingTo(0, 0, 1, 0)).toBeCloseTo(90);
    expect(bearingTo(0, 0, -1, -1)).toBeCloseTo(225);
    expect(angleDiff(350, 10)).toBe(20);
    expect(angleDiff(10, 350)).toBe(-20);
    expect(angleDiff(0, 180)).toBe(-180); // client convention: [-180, 180)
    for (let i = 0; i < 200; i++) {
      const a = (i * 37.3) % 400 - 20;
      const b = (i * 91.7) % 500 - 70;
      // same magnitude as the sim's (-180, 180] convention except exactly opposite
      expect(Math.abs(angleDiff(a, b))).toBeCloseTo(Math.abs(simGeo.angleDiff(a, b)), 9);
      const x = (i % 17) - 8;
      const y = (i % 11) - 5;
      if (x || y) expect(bearingTo(0, 0, x, y)).toBeCloseTo(simGeo.bearing(0, 0, x, y), 9);
    }
    const p = pointAt(2, 3, 90, 5);
    expect(p.x).toBeCloseTo(7);
    expect(p.y).toBeCloseTo(3);
  });

  it('MSA sectors match the sim; FAF distance', () => {
    for (const [x, y] of [[10, 10], [10, -10], [-10, -10], [-10, 10], [0, 5], [5, 0], [0, -5], [-5, 0]] as const) {
      expect(msaAt(WORLD, x, y)).toBe(simGeo.msaAt(WORLD, x, y));
    }
    expect(msaAt({ ...WORLD, msa: [] }, 1, 1)).toBeNull();
    expect(fafDist(WORLD)).toBeCloseTo(WORLD.ils.faf.x);
    expect(simGeo.glidepathAlt(WORLD, fafDist(WORLD))).toBeCloseTo(WORLD.ils.platformAltFt, -2);
  });

  it('hold racetrack: inbound leg ends at the fix, 1-minute legs, closed loop', () => {
    const pts = holdPath(WORLD, 210);
    const fix = WORLD.fixes.find((f) => f.name === WORLD.hold.fix)!;
    expect(pts).toHaveLength(2 + 24 + 1 + 24);
    expect(pts[1]).toEqual({ x: fix.x, y: fix.y });
    const leg = Math.hypot(pts[1]!.x - pts[0]!.x, pts[1]!.y - pts[0]!.y);
    expect(leg).toBeCloseTo(210 / 60, 6);
    expect(bearingTo(pts[0]!.x, pts[0]!.y, fix.x, fix.y)).toBeCloseTo(WORLD.hold.inboundCourseDeg, 6);
    const last = pts.at(-1)!;
    expect(Math.hypot(last.x - pts[0]!.x, last.y - pts[0]!.y)).toBeLessThan(1e-9);
    expect(holdPath({ ...WORLD, hold: { ...WORLD.hold, fix: 'NOPE' } })).toEqual([]);
    // right-hand hold: the outbound leg (pts[26]) is right of the inbound course; a left hold mirrors it
    const left = holdPath({ ...WORLD, hold: { ...WORLD.hold, turn: 'L' } }, 210);
    const side = (p: { x: number; y: number }) => angleDiff(WORLD.hold.inboundCourseDeg, bearingTo(fix.x, fix.y, p.x, p.y));
    expect(side(pts[26]!)).toBeGreaterThan(0);
    expect(side(left[26]!)).toBeLessThan(0);
  });
});

describe('text', () => {
  const ALL: Outcome[] = ['landed', 'terrain', 'collision', 'fuel', 'runway', 'flying'];

  it('mmss', () => {
    expect(mmss(0)).toBe('00:00');
    expect(mmss(59.9)).toBe('00:59');
    expect(mmss(754)).toBe('12:34');
    expect(mmss(6000)).toBe('100:00');
    expect(mmss(-5)).toBe('00:00');
  });

  it('every outcome has long and short text and an event line', () => {
    for (const o of ALL) {
      expect(OUTCOME_TEXT[o]).toBeTruthy();
      expect(OUTCOME_SHORT[o]).toBeTruthy();
      const e: RoundEvent = { time: 1, kind: o, callsigns: ['AAA1', 'BBB2'] };
      expect(eventText(e)).toContain('AAA1 and BBB2');
    }
    expect(Object.keys(OUTCOME_TEXT).sort()).toEqual([...ALL].sort());
    expect(eventText({ time: 0, kind: 'collision', callsigns: ['A', 'B'] })).toBe('MID-AIR COLLISION: A and B');
    expect(eventText({ time: 0, kind: 'landed', callsigns: ['A'] })).toBe('A landed runway 27');
  });
});

describe('PFD flight mode annunciator', () => {
  const ac = (o: Partial<OwnAircraft>): OwnAircraft =>
    ({ apMode: 'HDG', appArmed: false, gsCaptured: false, indAlt: 5000, selAlt: 5000, vs: 0, ...o }) as OwnAircraft;

  it('lateral, vertical and armed modes', () => {
    expect(fmaFor(ac({}))).toEqual({ spd: 'SPD', lat: 'HDG SEL', latArmed: '', vert: 'ALT HOLD', vertArmed: '' });
    expect(fmaFor(ac({ selAlt: 3000, indAlt: 5000, vs: -1800 })).vert).toBe('FLCH DES');
    expect(fmaFor(ac({ selAlt: 7000, indAlt: 5000, vs: 1800 })).vert).toBe('FLCH CLB');
    // within 60 ft but still moving fast: not yet ALT HOLD
    expect(fmaFor(ac({ selAlt: 5000, indAlt: 5040, vs: -400 })).vert).toBe('FLCH DES');
    expect(fmaFor(ac({ appArmed: true }))).toMatchObject({ lat: 'HDG SEL', latArmed: 'LOC', vertArmed: 'G/S' });
    expect(fmaFor(ac({ appArmed: true, apMode: 'LOC' }))).toMatchObject({ lat: 'LOC', latArmed: '', vertArmed: 'G/S' });
    expect(fmaFor(ac({ appArmed: true, apMode: 'APP', gsCaptured: true }))).toMatchObject({ lat: 'LOC', vert: 'G/S', vertArmed: '' });
  });
});
