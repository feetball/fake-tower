// Simulation regression suite: invariants over many seeds, ILS/landing edge
// cases, alert thresholds and a golden master of a scripted round.

import { describe, expect, it } from 'vitest';
import type { OwnAircraft, RadarTarget } from '../protocol';
import { WORLD } from '../world';
import { Aircraft, type AircraftInit, type ApCommand, PERF } from './aircraft';
import { ILS_NEAR_NM, glidepathAlt, ilsDeviation, msaAt } from './geo';
import { type Rng, mulberry32, randInt, randRange } from './rng';
import { COLLISION_FT, COLLISION_NM, Round } from './round';

const DT = 0.1;
const QNH = 1013;

function ac(over: Partial<AircraftInit> = {}): AircraftInit {
  return { callsign: 'TST1', playerId: 'p1', x: 20, y: 0, alt: 3000, hdg: 270, ias: 180, fuelMin: 30, ...over };
}
function round(inits: AircraftInit[], qnh = QNH): Round {
  return new Round([], { rng: mulberry32(1), qnh, aircraft: inits });
}
/** Aircraft already established on the ILS (LOC + G/S captured). */
function established(over: Partial<AircraftInit> = {}): Round {
  const x = over.x ?? 3;
  const r = round([ac({ x, y: 0, alt: glidepathAlt(WORLD, x), ias: 140, gearDown: true, flaps: 3, ...over })]);
  const a = r.aircraft[0]!;
  a.appArmed = true;
  a.locCaptured = true;
  a.gsCaptured = true;
  return r;
}
function runUntil(r: Round, maxSec: number, until: () => boolean, each?: (t: number) => void): number {
  for (let t = 0; t < maxSec; t += DT) {
    each?.(t);
    r.step(DT);
    if (until()) return t + DT;
  }
  return Number.POSITIVE_INFINITY;
}

const KNOWN_WARNINGS = new Set(['TERRAIN', 'PULL UP', 'TOO LOW GEAR', 'LOW FUEL']);
const fin = (v: number) => Number.isFinite(v);
const int = (v: number) => Number.isInteger(v);

/** Names of the OwnAircraft fields that are out of range (plain checks: this runs ~10^6 times). */
function badOwn(o: OwnAircraft): string[] {
  const bad: string[] = [];
  const chk = (ok: boolean, what: string) => ok || bad.push(what);
  chk(o.hdg >= 0 && o.hdg < 360, 'hdg');
  chk(o.ias >= PERF.minSpd[3] - 0.05 && o.ias <= PERF.maxSpd + 0.05, 'ias');
  chk(fin(o.indAlt) && int(o.indAlt), 'indAlt');
  chk(o.radAlt === null || (int(o.radAlt) && o.radAlt >= 0 && o.radAlt < 2500), 'radAlt');
  chk(o.vs >= -PERF.maxDescentFpm && o.vs <= PERF.climbFpm, 'vs');
  chk(o.fuelMin >= 0 && fin(o.fuelMin), 'fuel');
  chk(o.dme >= 0 && fin(o.dme), 'dme');
  chk(int(o.bearingToStation) && o.bearingToStation >= 0 && o.bearingToStation < 360, 'brg');
  chk(o.locDev === null || (o.locDev >= -2.5 && o.locDev <= 2.5), 'locDev');
  chk(o.gsDev === null || (o.gsDev >= -2.5 && o.gsDev <= 2.5), 'gsDev');
  chk(int(o.selHdg) && o.selHdg >= 0 && o.selHdg <= 359, 'selHdg');
  chk(o.selAlt % 100 === 0 && o.selAlt >= PERF.minAltSel && o.selAlt <= PERF.maxAltSel, 'selAlt');
  chk(int(o.selSpd) && o.selSpd >= PERF.minSpd[o.flaps] && o.selSpd <= PERF.maxSpd, 'selSpd');
  chk(int(o.altSetting) && o.altSetting >= PERF.minAltSetting && o.altSetting <= PERF.maxAltSetting, 'altSetting');
  chk(o.flaps === 0 || o.flaps === 1 || o.flaps === 2 || o.flaps === 3, 'flaps');
  chk(o.apMode === 'HDG' || o.apMode === 'LOC' || o.apMode === 'APP', 'apMode');
  chk(o.gsCaptured === (o.apMode === 'APP'), 'gs/mode');
  chk(o.warnings.every((w) => KNOWN_WARNINGS.has(w)), 'warnings');
  chk((o.status === 'flying') === (o.outcome === undefined), 'outcome');
  chk(o.status === 'flying' || o.warnings.length === 0, 'warnings after finish');
  return bad;
}

function checkOwn(o: OwnAircraft, where: string): void {
  const bad = badOwn(o);
  if (bad.length) expect.fail(`${where}: bad ${bad.join(', ')} in ${JSON.stringify(o)}`);
}

function checkRadar(t: RadarTarget, where: string): void {
  const ok =
    fin(t.x) && fin(t.y) && fin(t.alt) && t.alt % 100 === 0 && t.gs >= 0 && int(t.gs) && int(t.track) && t.track >= 0 && t.track < 360 &&
    (t.vsTrend === -1 || t.vsTrend === 0 || t.vsTrend === 1) && (t.status === 'flying' || (!t.conflict && !t.msaw && t.gs === 0));
  if (!ok) expect.fail(`${where}: bad radar target ${JSON.stringify(t)}`);
}

function randomCommand(rng: Rng): ApCommand {
  const cmd: ApCommand = {};
  if (rng() < 0.5) cmd.hdg = randRange(rng, -720, 720);
  if (rng() < 0.5) cmd.alt = randRange(rng, -2000, 30000);
  if (rng() < 0.4) cmd.spd = randRange(rng, -50, 500);
  if (rng() < 0.3) cmd.flaps = randInt(rng, 0, 3) as 0 | 1 | 2 | 3;
  if (rng() < 0.2) cmd.gear = rng() < 0.5;
  if (rng() < 0.3) cmd.app = rng() < 0.7;
  if (rng() < 0.3) cmd.altSetting = randRange(rng, 900, 1100);
  return cmd;
}

describe('properties over many seeds', () => {
  it('spawns: separated, no warnings, no alerts, valid views (1000 rounds)', () => {
    for (let seed = 1000; seed < 2000; seed++) {
      const n = 1 + (seed % 8);
      const r = new Round(Array.from({ length: n }, (_, i) => `p${i}`), { rng: mulberry32(seed) });
      for (const a of r.aircraft) {
        expect(a.warnings, `seed ${seed}`).toEqual([]);
        checkOwn(r.ownView(a.playerId)!, `seed ${seed}`);
      }
      for (const t of r.radar()) {
        checkRadar(t, `seed ${seed}`);
        expect(t.conflict || t.msaw, `seed ${seed}`).toBe(false);
      }
      expect(Math.abs(r.qnh - 1013)).toBeGreaterThanOrEqual(4);
    }
  });

  it('random valid command sequences: views stay finite and in range, fuel never increases, statuses only finish once', () => {
    for (let seed = 1; seed <= 40; seed++) {
      const rng = mulberry32(seed * 7919);
      const ids = Array.from({ length: 1 + (seed % 6) }, (_, i) => `p${i}`);
      const r = new Round(ids, { rng: mulberry32(seed) });
      const fuel = new Map(r.aircraft.map((a) => [a.playerId, a.fuelMin]));
      const finished = new Map<string, string>();
      let lastTime = 0;
      for (let k = 0; k < 4000 && !r.finished; k++) {
        if (k % 15 === 0) for (const id of ids) if (rng() < 0.5) r.applyAp(id, randomCommand(rng));
        r.step(DT);
        expect(r.time).toBeGreaterThan(lastTime);
        lastTime = r.time;
        const where = `seed ${seed} t=${r.time.toFixed(1)}`;
        for (const a of r.aircraft) {
          checkOwn(r.ownView(a.playerId)!, where);
          if (!(a.hdg >= 0 && a.hdg < 360 && fin(a.x) && fin(a.y) && fin(a.alt) && fin(a.vs))) expect.fail(`${where}: raw state ${JSON.stringify(a)}`);
          if (a.fuelMin > fuel.get(a.playerId)!) expect.fail(`${where}: fuel increased`);
          fuel.set(a.playerId, a.fuelMin);
          if (finished.has(a.playerId)) {
            if (a.outcome !== finished.get(a.playerId)) expect.fail(`${where}: outcome changed after finishing`);
          } else if (!a.flying) finished.set(a.playerId, a.outcome);
        }
        for (const t of r.radar()) checkRadar(t, where);
      }
      // every event names aircraft that really finished with that outcome
      for (const e of r.allEvents()) for (const cs of e.callsigns) expect(r.aircraft.find((a) => a.callsign === cs)!.outcome).toBe(e.kind);
    }
  });
});

describe('ILS capture edge cases', () => {
  it('joining above the glideslope never captures it; the aircraft goes missed over the threshold', () => {
    const r = round([ac({ x: 12, y: 0, alt: 6000, ias: 160, selAlt: 6000 })]);
    const a = r.aircraft[0]!;
    a.apply({ app: true });
    let gs = false;
    let loc = false;
    runUntil(r, 600, () => a.x < -2, () => {
      gs ||= a.gsCaptured;
      loc ||= a.locCaptured;
    });
    expect(loc).toBe(true);
    expect(gs).toBe(false);
    expect(a.flying).toBe(true);
    expect(a.apMode).toBe('HDG'); // localizer lost behind the threshold
    expect(r.allEvents()).toEqual([]);
  });

  it('app:false drops LOC and G/S capture; re-arming recaptures the localizer', () => {
    const r = established({ x: 6 });
    const a = r.aircraft[0]!;
    r.step(DT);
    expect(a.apMode).toBe('APP');
    a.apply({ app: false });
    expect([a.appArmed, a.locCaptured, a.gsCaptured, a.apMode]).toEqual([false, false, false, 'HDG']);
    r.step(DT);
    expect(a.apMode).toBe('HDG');
    a.apply({ app: true });
    r.step(DT);
    expect(a.apMode).toBe('LOC');
    // other commands leave the approach alone
    a.apply({ hdg: 90, alt: 9000, spd: 140, gear: true, flaps: 3, altSetting: 1000 });
    expect(a.locCaptured).toBe(true);
  });

  it('localizer intercept angle: up to 90° captures, beyond does not', () => {
    const capture = (hdg: number) => {
      const r = round([ac({ x: 10, y: 0.05, hdg, ias: 180 })]);
      r.aircraft[0]!.apply({ app: true });
      r.step(DT);
      return r.aircraft[0]!.locCaptured;
    };
    expect(capture(270)).toBe(true);
    expect(capture(0)).toBe(true); // exactly 90°
    expect(capture(180)).toBe(true); // exactly 90° the other way
    expect(capture(359)).toBe(true);
    expect(capture(1)).toBe(false); // 91°
    expect(capture(179)).toBe(false);
    expect(capture(90)).toBe(false); // flying away
  });

  it('needs APP armed and the needle inside full scale', () => {
    const unarmed = round([ac({ x: 10, y: 0 })]);
    unarmed.step(DT);
    expect(unarmed.aircraft[0]!.locCaptured).toBe(false);
    const offside = round([ac({ x: 10, y: 0.5, hdg: 240 })]); // 2.9° off: needle pegged
    offside.aircraft[0]!.apply({ app: true });
    offside.step(DT);
    expect(offside.aircraft[0]!.locCaptured).toBe(false);
  });

  it(`no capture beyond the ${WORLD.ils.rangeNm} nm range; captures once inside`, () => {
    const r = round([ac({ x: WORLD.ils.rangeNm + 2, y: 0, hdg: 270, ias: 250, alt: 4000 })]);
    const a = r.aircraft[0]!;
    a.apply({ app: true });
    const tCap = runUntil(r, 120, () => a.locCaptured, () => {
      if (Math.hypot(a.x, a.y) > WORLD.ils.rangeNm) expect(a.locCaptured).toBe(false);
    });
    expect(tCap).toBeLessThan(120);
    expect(Math.hypot(a.x, a.y)).toBeLessThanOrEqual(WORLD.ils.rangeNm);
    expect(Math.hypot(a.x, a.y)).toBeGreaterThan(WORLD.ils.rangeNm - 0.1);
    expect(ilsDeviation(WORLD, WORLD.ils.rangeNm + 0.01, 0, 4000)).toEqual({ loc: null, gs: null });
  });

  it('flying out of localizer coverage disconnects the approach', () => {
    const r = round([ac({ x: 10, y: 0, hdg: 270 })]);
    const a = r.aircraft[0]!;
    a.apply({ app: true });
    r.step(DT);
    expect(a.locCaptured).toBe(true);
    a.x = 10;
    a.y = 8; // 38.7° off course, far from the threshold
    r.step(DT);
    expect(a.apMode).toBe('HDG');
    expect(a.appArmed).toBe(true); // still armed, can recapture later
  });
});

describe('threshold: landing, runway accidents, missed approaches', () => {
  const finalOutcome = (over: Partial<AircraftInit>) => {
    const r = established({ x: 0.3, ...over });
    runUntil(r, 60, () => r.finished);
    return r.aircraft[0]!;
  };

  it('stable = gear down, flaps 3, IAS <= 155 at the threshold', () => {
    expect(finalOutcome({}).outcome).toBe('landed');
    expect(finalOutcome({ ias: 155 }).outcome).toBe('landed');
    expect(finalOutcome({ ias: 156 }).outcome).toBe('runway');
    expect(finalOutcome({ gearDown: false }).outcome).toBe('runway');
    expect(finalOutcome({ flaps: 2, ias: 160 }).outcome).toBe('runway');
    const l = finalOutcome({});
    expect([l.status, l.vs, l.warnings]).toEqual(['landed', 0, []]);
  });

  it('crossing the threshold without LOC+G/S is not a landing: the aircraft keeps flying', () => {
    for (const setup of ['none', 'loc-only'] as const) {
      const r = round([ac({ x: 1, y: 0, alt: 1500, hdg: 270, ias: 140, gearDown: true, flaps: 3, selAlt: 1500 })]);
      const a = r.aircraft[0]!;
      if (setup === 'loc-only') {
        a.appArmed = true;
        a.locCaptured = true;
      }
      runUntil(r, 120, () => a.x < -1);
      expect(a.flying, setup).toBe(true);
      expect(a.outcome).toBe('flying');
      expect(r.allEvents()).toEqual([]);
    }
  });

  it('regression: established a few dozen feet off the centreline just before the threshold still lands', () => {
    // 0.008 nm (49 ft) off at 0.01 nm (61 ft) out is > 35° off the course as seen from the
    // threshold antenna; the localizer used to drop out here and the aircraft went missed.
    const r = established({ x: 0.01, y: 0.008, alt: glidepathAlt(WORLD, 0.0128) });
    runUntil(r, 10, () => r.finished);
    expect(r.aircraft[0]!.outcome).toBe('landed');
  });

  it('regression: an aircraft ending a step a hair short of the threshold still lands', () => {
    const r = established({ x: 1e-12, y: 0, alt: glidepathAlt(WORLD, 0) });
    expect(ilsDeviation(WORLD, 1e-12, 0, 600)).toEqual({ loc: 0, gs: 0 });
    r.step(DT);
    expect(r.aircraft[0]!.outcome).toBe('landed');
  });

  it('near-threshold localizer coverage', () => {
    expect(ilsDeviation(WORLD, 0.01, 0.008, 600).loc).toBe(-2.5); // close in: still a signal, pegged
    const far = ILS_NEAR_NM + 0.1;
    expect(ilsDeviation(WORLD, far * Math.cos(0.7), far * Math.sin(0.7), 600).loc).toBeNull(); // 40° off, beyond 0.5 nm
    expect(ilsDeviation(WORLD, -0.01, 0, 600).loc).toBeNull(); // behind the threshold
    expect(ilsDeviation(WORLD, -0.001, 0.3, 600).loc).toBeNull(); // abeam, just behind
  });
});

describe('autopilot command clamping (every ap field)', () => {
  it('hdg: wrapped, rounded to whole degrees', () => {
    const a = new Aircraft(ac(), QNH);
    const cases: [number, number][] = [[0, 0], [359.4, 359], [359.6, 0], [360, 0], [-0.4, 0], [-1, 359], [725, 5], [-725, 355], [1e9, 1e9 % 360]];
    for (const [cmd, want] of cases) {
      a.apply({ hdg: cmd });
      expect(a.selHdg, `hdg ${cmd}`).toBe(want);
    }
  });

  it('alt: nearest 100 ft, 0..20000', () => {
    const a = new Aircraft(ac(), QNH);
    const cases: [number, number][] = [[3049, 3000], [3050, 3100], [-49, 0], [-5000, 0], [20049, 20000], [1e9, 20000], [0, 0]];
    for (const [cmd, want] of cases) {
      a.apply({ alt: cmd });
      expect(a.selAlt + 0, `alt ${cmd}`).toBe(want); // + 0: -0 (from rounding -49) is fine, it serialises as 0
    }
  });

  it('spd: whole knots between the flap minimum and 250, re-clamped on flap changes', () => {
    const a = new Aircraft(ac({ flaps: 0 }), QNH);
    a.apply({ spd: 210.4 });
    expect(a.selSpd).toBe(210);
    a.apply({ spd: -100 });
    expect(a.selSpd).toBe(PERF.minSpd[0]);
    a.apply({ spd: 9999 });
    expect(a.selSpd).toBe(PERF.maxSpd);
    for (const f of [1, 2, 3] as const) {
      a.apply({ flaps: f, spd: 0 });
      expect(a.selSpd).toBe(PERF.minSpd[f]);
    }
    a.apply({ flaps: 0 }); // retracting raises the minimum
    expect(a.selSpd).toBe(PERF.minSpd[0]);
    a.apply({ spd: 135, flaps: 3 }); // flaps applied before speed in one command
    expect(a.selSpd).toBe(135);
  });

  it('altSetting: whole hPa, 950..1050; flaps 0..3; gear and app booleans', () => {
    const a = new Aircraft(ac(), QNH);
    const cases: [number, number][] = [[1003.4, 1003], [1003.5, 1004], [0, 950], [5000, 1050]];
    for (const [cmd, want] of cases) {
      a.apply({ altSetting: cmd });
      expect(a.altSetting).toBe(want);
    }
    a.apply({ flaps: 7 as never });
    expect(a.flaps).toBe(3);
    a.apply({ flaps: -2 as never });
    expect(a.flaps).toBe(0);
    a.apply({ flaps: 1.6 as never });
    expect(a.flaps).toBe(2);
    a.apply({ gear: true, app: true });
    expect([a.gearDown, a.appArmed]).toEqual([true, true]);
    a.apply({});
    expect([a.gearDown, a.appArmed, a.flaps, a.altSetting]).toEqual([true, true, 2, 1050]);
  });

  it('commands are ignored once the aircraft has landed or crashed', () => {
    const r = round([ac({ playerId: 'p1' })]);
    const a = r.aircraft[0]!;
    a.finish('terrain');
    const before = JSON.stringify(a);
    expect(r.applyAp('p1', { hdg: 10, alt: 0, gear: true })).toBe(false);
    a.apply({ hdg: 10 });
    expect(JSON.stringify(a)).toBe(before);
    expect(r.applyAp('nobody', { hdg: 10 })).toBe(false);
    r.step(DT);
    expect(r.time).toBe(0); // a finished round does not advance
  });
});

describe('GPWS', () => {
  function onsets(r: Round) {
    const a = r.aircraft[0]!;
    const first: Record<string, number> = {};
    const tEnd = runUntil(r, 900, () => !a.flying, (t) => {
      for (const w of a.warnings) first[w] ??= t;
    });
    return { first, tEnd };
  }

  it('flying level into a mountain: TERRAIN ~30 s before impact, PULL UP ~12 s before', () => {
    const { first, tEnd } = onsets(round([ac({ x: 20, y: 9, alt: 3000, hdg: 270, ias: 200, selAlt: 3000 })]));
    expect(first.TERRAIN).toBeLessThan(first['PULL UP']!);
    expect(tEnd - first.TERRAIN!).toBeGreaterThan(29);
    expect(tEnd - first.TERRAIN!).toBeLessThan(31.5);
    expect(tEnd - first['PULL UP']!).toBeGreaterThan(11);
    expect(tEnd - first['PULL UP']!).toBeLessThan(13.5);
  });

  it('descending into flat ground away from the field: same order, TOO LOW GEAR below 500 ft AGL', () => {
    const { first } = onsets(round([ac({ x: 20, y: -20, alt: 4000, hdg: 90, ias: 200, selAlt: 0 })]));
    expect(first.TERRAIN).toBeLessThan(first['PULL UP']!);
    expect(first['TOO LOW GEAR']).toBeDefined();
  });

  it('warnings clear when the pilot climbs away', () => {
    const r = round([ac({ x: 20, y: 9, alt: 3000, hdg: 270, ias: 200, selAlt: 3000 })]);
    const a = r.aircraft[0]!;
    runUntil(r, 300, () => a.warnings.includes('TERRAIN'));
    a.apply({ hdg: 90, alt: 6000 });
    runUntil(r, 300, () => a.warnings.length === 0);
    expect(a.flying).toBe(true);
    expect(a.warnings).toEqual([]);
  });
});

describe('alert and collision thresholds (boundaries)', () => {
  const pair = (b: Partial<AircraftInit>) =>
    round([ac({ playerId: 'a', callsign: 'A1', x: 20, y: 10, alt: 6000 }), ac({ playerId: 'b', callsign: 'B2', x: 20, y: 10, alt: 6000, ...b })]);
  const conflict = (b: Partial<AircraftInit>) => pair(b).radar().map((t) => t.conflict);

  it('conflict alert: strictly inside 3 nm AND strictly inside 1000 ft', () => {
    const { lateralNm, verticalFt } = WORLD.separation;
    expect(conflict({ y: 10 + lateralNm - 1e-6 })).toEqual([true, true]);
    expect(conflict({ y: 10 + lateralNm + 1e-6 })).toEqual([false, false]);
    expect(conflict({ alt: 6000 + verticalFt - 1 })).toEqual([true, true]);
    expect(conflict({ alt: 6000 + verticalFt })).toEqual([false, false]);
    expect(conflict({ y: 11, alt: 5001 })).toEqual([true, true]);
    const r = pair({ y: 11 });
    r.aircraft[1]!.finish('terrain');
    expect(r.radar().map((t) => t.conflict)).toEqual([false, false]);
  });

  it('MSAW: strictly below the sector MSA, sectors from the station bearing', () => {
    const msaw = (x: number, y: number, alt: number) => round([ac({ x, y, alt })]).radar()[0]!.msaw;
    expect(msaw(10, 10, 5199)).toBe(true); // 045: 5200
    expect(msaw(10, 10, 5200)).toBe(false);
    expect(msaAt(WORLD, 10, 0)).toBe(4400); // exactly 090 belongs to 090-180
    expect(msaAt(WORLD, 0, 10)).toBe(5200); // exactly 000
    expect(msaAt(WORLD, 0, -10)).toBe(5900); // exactly 180
    expect(msaw(10, 0, 4399)).toBe(true);
    expect(msaw(10, 0, 4400)).toBe(false);
    const done = round([ac({ x: 10, y: 10, alt: 1000 })]);
    done.aircraft[0]!.finish('terrain');
    expect(done.radar()[0]!.msaw).toBe(false);
  });

  it(`collision: inside ${COLLISION_NM} nm and ${COLLISION_FT} ft`, () => {
    const outcomes = (b: Partial<AircraftInit>) => {
      const r = pair({ ...b });
      r.step(DT); // same heading and speed: the gap does not change
      return r.aircraft.map((a) => a.outcome);
    };
    expect(outcomes({ y: 10 + COLLISION_NM - 0.001 })).toEqual(['collision', 'collision']);
    expect(outcomes({ y: 10 + COLLISION_NM + 0.001 })).toEqual(['flying', 'flying']);
    expect(outcomes({ y: 10.1, alt: 6000 + COLLISION_FT - 1 })).toEqual(['collision', 'collision']);
    expect(outcomes({ y: 10.1, alt: 6000 + COLLISION_FT + 1 })).toEqual(['flying', 'flying']);
  });

  it('three-way collision is one event; a landed aircraft is never hit', () => {
    const r = round([
      ac({ playerId: 'a', callsign: 'A1', x: 20, y: 10 }),
      ac({ playerId: 'b', callsign: 'B2', x: 20, y: 10.05 }),
      ac({ playerId: 'c', callsign: 'C3', x: 20, y: 10.1 }),
      ac({ playerId: 'd', callsign: 'D4', x: 20, y: 10.02 }),
    ]);
    r.aircraft[3]!.finish('landed');
    const ev = r.step(DT);
    expect(ev).toHaveLength(1);
    expect(ev[0]!.callsigns.sort()).toEqual(['A1', 'B2', 'C3']);
    expect(r.aircraft[3]!.outcome).toBe('landed');
  });
});

describe('golden master', () => {
  // Fixed state + fixed command script -> key state at fixed times. Any change to
  // the flight model, spawns, ATIS or capture logic shows up here. If a change is
  // intended, review the diff and update with `npx vitest run -u`.
  it('vectored ILS approach to a landing', () => {
    const r = round([ac({ x: 24, y: 12, alt: 6000, hdg: 210, ias: 220, selAlt: 6000, altSetting: 1013 })], 1003);
    const a = r.aircraft[0]!;
    a.apply({ altSetting: 1003, alt: 3000, spd: 200 });
    const lines: string[] = [];
    let phase = 0;
    for (let k = 0; k < 9000 && !r.finished; k++) {
      if (phase === 0 && a.y < 3) {
        a.apply({ hdg: 240, app: true, flaps: 1, spd: 180 });
        phase = 1;
      } else if (phase === 1 && a.apMode === 'LOC') {
        a.apply({ flaps: 2, spd: 160 });
        phase = 2;
      } else if (phase === 2 && a.gsCaptured) {
        a.apply({ gear: true, flaps: 3, spd: 140 });
        phase = 3;
      }
      if (k % 300 === 0) {
        const o = r.ownView('p1')!;
        lines.push(`t=${r.time.toFixed(0)} ${a.x.toFixed(2)},${a.y.toFixed(3)} alt ${a.alt.toFixed(0)} hdg ${a.hdg.toFixed(1)} ias ${a.ias.toFixed(1)} vs ${a.vs.toFixed(0)} ${o.apMode} loc ${o.locDev} gs ${o.gsDev} [${o.warnings.join(',')}]`);
      }
      r.step(DT);
    }
    lines.push(`end t=${r.time.toFixed(1)} ${a.outcome} y=${a.y.toFixed(4)} ias=${a.ias.toFixed(1)} fuel=${a.fuelMin.toFixed(2)}`);
    expect(lines).toMatchInlineSnapshot(`
      [
        "t=0 24.00,12.000 alt 6000 hdg 210.0 ias 220.0 vs 0 HDG loc null gs null []",
        "t=30 23.05,10.359 alt 5166 hdg 210.0 ias 200.0 vs -1800 HDG loc null gs null []",
        "t=60 22.14,8.779 alt 4266 hdg 210.0 ias 200.0 vs -1800 HDG loc -2.5 gs 2.5 []",
        "t=90 21.24,7.226 alt 3366 hdg 210.0 ias 200.0 vs -1800 HDG loc -2.5 gs 2.5 []",
        "t=120 20.36,5.692 alt 3030 hdg 210.0 ias 200.0 vs -150 HDG loc -2.5 gs 2.5 []",
        "t=150 19.47,4.162 alt 3002 hdg 210.0 ias 200.0 vs -12 HDG loc -2.5 gs 2.5 []",
        "t=180 18.54,2.689 alt 3000 hdg 231.6 ias 189.2 vs -1 HDG loc -2.5 gs 2.5 []",
        "t=210 17.16,1.879 alt 3000 hdg 240.0 ias 180.0 vs -0 HDG loc -2.5 gs 2.5 []",
        "t=240 15.78,1.084 alt 3000 hdg 240.0 ias 180.0 vs -0 HDG loc -2.5 gs 2.5 []",
        "t=270 14.44,0.313 alt 3000 hdg 243.3 ias 160.0 vs -0 LOC loc -1.24 gs 2.5 []",
        "t=300 13.06,0.039 alt 3000 hdg 266.7 ias 160.0 vs -0 LOC loc -0.17 gs 2.5 []",
        "t=330 11.65,0.005 alt 3000 hdg 269.6 ias 160.0 vs -0 LOC loc -0.02 gs 2.5 []",
        "t=360 10.24,0.001 alt 3000 hdg 270.0 ias 160.0 vs -0 LOC loc 0 gs 2.16 []",
        "t=390 8.82,0.000 alt 3000 hdg 270.0 ias 160.0 vs -0 LOC loc 0 gs 1.13 []",
        "t=420 7.42,0.000 alt 2925 hdg 270.0 ias 150.7 vs -853 APP loc 0 gs 0 []",
        "t=450 6.18,0.000 alt 2529 hdg 270.0 ias 140.0 vs -781 APP loc 0 gs 0 []",
        "t=480 4.96,0.000 alt 2140 hdg 270.0 ias 140.0 vs -775 APP loc 0 gs 0 []",
        "t=510 3.74,0.000 alt 1754 hdg 270.0 ias 140.0 vs -769 APP loc 0 gs 0 []",
        "t=540 2.54,0.000 alt 1371 hdg 270.0 ias 140.0 vs -763 APP loc 0 gs 0 []",
        "t=570 1.35,0.000 alt 991 hdg 270.0 ias 140.0 vs -758 APP loc 0 gs 0 []",
        "t=600 0.16,0.000 alt 613 hdg 270.0 ias 140.0 vs -752 APP loc 0 gs 0 []",
        "end t=604.1 landed y=0.0000 ias=140.0 fuel=19.93",
      ]
    `);
  });

  it('scripted 3-aircraft round from a seeded spawn', () => {
    const r = new Round(['a', 'b', 'c'], { rng: mulberry32(20261125) });
    const script: Record<number, [string, ApCommand][]> = {
      0: [['a', { altSetting: r.qnh, alt: 4000, spd: 220 }], ['b', { altSetting: r.qnh, alt: 5000 }], ['c', { alt: 3000, spd: 200 }]],
      600: [['a', { hdg: 240, app: true, flaps: 1, spd: 180 }], ['b', { hdg: 180, spd: 230 }], ['c', { altSetting: 1013, hdg: 90 }]],
      1500: [['a', { flaps: 3, gear: true, spd: 140 }], ['b', { alt: 3000, app: true, hdg: 300 }]],
      3000: [['c', { alt: 0 }]],
    };
    const lines = [`qnh ${r.qnh} atis ${r.atis.letter} ${r.aircraft.map((a) => a.callsign).join(' ')}`];
    const f = (v: number, d = 0) => v.toFixed(d);
    for (let k = 0; k <= 4800; k++) {
      for (const [id, cmd] of script[k] ?? []) r.applyAp(id, cmd);
      if (k % 600 === 0) {
        lines.push(
          `t=${f(r.time)} ` +
            r.aircraft
              .map((a) => `${a.callsign}:${a.status[0]}${f(a.x, 2)},${f(a.y, 2)},${f(a.alt)},${f(a.hdg, 1)},${f(a.ias, 1)},${f(a.vs)},${f(a.fuelMin, 2)},${a.apMode}${a.warnings.length ? `[${a.warnings.join('/')}]` : ''}`)
              .join(' '),
        );
      }
      r.step(DT);
    }
    lines.push(`events ${r.allEvents().map((e) => `${e.time}:${e.kind}:${e.callsigns.join('+')}`).join(' ')}`);
    expect(lines).toMatchInlineSnapshot(`
      [
        "qnh 1005 atis I AAL2529 SWA430 SKW1441",
        "t=0 AAL2529:f-23.79,22.46,9784,143.3,250.0,0,28.90,HDG SWA430:f21.47,25.60,9784,228.7,250.0,0,26.50,HDG SKW1441:f28.82,2.35,8784,269.6,250.0,0,18.30,HDG",
        "t=60 AAL2529:f-21.14,18.94,7412,143.0,220.0,-2500,27.90,HDG SWA430:f17.78,22.40,7567,229.0,250.0,-1800,25.50,HDG SKW1441:f24.71,2.35,6412,270.0,200.0,-2500,17.30,HDG",
        "t=120 AAL2529:f-22.77,16.42,5487,240.0,180.0,-1800,26.90,HDG SWA430:f17.28,18.16,5767,180.0,230.0,-1800,24.50,HDG SKW1441:f24.69,-0.00,4426,91.0,200.0,-1800,16.30,HDG",
        "t=180 AAL2529:f-25.44,14.88,4055,240.0,140.0,-278,25.90,HDG SWA430:f15.94,14.70,4227,270.0,230.0,-1800,23.50,HDG SKW1441:f28.26,-0.00,2869,90.0,200.0,-428,15.30,HDG",
        "t=240 AAL2529:f-27.62,13.62,4000,240.0,140.0,-2,24.90,HDG SWA430:f12.33,16.58,3027,300.0,230.0,-135,22.50,HDG SKW1441:f31.78,-0.00,2785,90.0,200.0,-3,14.30,HDG",
        "t=300 AAL2529:f-29.80,12.36,4000,240.0,140.0,-0,23.90,HDG SWA430:f8.81,18.61,3000,300.0,230.0,-1,21.50,HDG SKW1441:f35.30,-0.00,2784,90.0,200.0,-0,13.30,HDG",
        "t=360 AAL2529:f-31.99,11.10,4000,240.0,140.0,-0,22.90,HDG SWA430:f5.29,20.65,3000,300.0,230.0,-0,20.50,HDG SKW1441:f38.76,-0.00,1050,90.0,200.0,-1800,12.30,HDG[TERRAIN]",
        "t=420 AAL2529:f-34.17,9.84,4000,240.0,140.0,-0,21.90,HDG SWA430:f1.77,22.68,3000,300.0,230.0,-0,19.50,HDG SKW1441:c39.78,-0.00,510,90.0,200.0,0,12.00,HDG",
        "t=480 AAL2529:f-36.35,8.58,4000,240.0,140.0,-0,20.90,HDG SWA430:f-1.74,24.71,3000,300.0,230.0,-0,18.50,HDG SKW1441:c39.78,-0.00,510,90.0,200.0,0,12.00,HDG",
        "events 378:terrain:SKW1441",
      ]
    `);
  });
});
