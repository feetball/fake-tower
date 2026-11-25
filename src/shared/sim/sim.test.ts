import { describe, expect, it } from 'vitest';
import { WORLD } from '../world';
import { Aircraft, type AircraftInit } from './aircraft';
import { dist, glidepathAlt, ilsDeviation, msaAt, terrainElevAt } from './geo';
import { mulberry32 } from './rng';
import { Round, directApproachMinutes } from './round';

const DT = 0.1;
const QNH = 1003;

function ac(over: Partial<AircraftInit> = {}): AircraftInit {
  return { callsign: 'TST1', playerId: 'p1', x: 20, y: 0, alt: 3000, hdg: 270, ias: 180, fuelMin: 30, altSetting: QNH, ...over };
}

function round(inits: AircraftInit[], qnh = QNH): Round {
  return new Round([], { rng: mulberry32(1), qnh, aircraft: inits });
}

/** Step until predicate or timeout; returns seconds simulated. */
function run(r: Round, maxSec: number, until: () => boolean = () => r.finished, each?: () => void): number {
  for (let t = 0; t < maxSec; t += DT) {
    each?.();
    r.step(DT);
    if (until()) return t;
  }
  return maxSec;
}

describe('geo', () => {
  it('terrain, MSA and glidepath', () => {
    expect(terrainElevAt(WORLD, 9, 9)).toBe(4200);
    expect(terrainElevAt(WORLD, 30, 0)).toBe(WORLD.fieldElevFt);
    expect(msaAt(WORLD, 10, 10)).toBe(5200); // bearing 045
    expect(msaAt(WORLD, 10, -10)).toBe(4400); // 135
    expect(msaAt(WORLD, -10, 10)).toBe(5900); // 315
    expect(glidepathAlt(WORLD, WORLD.ils.faf.x)).toBeCloseTo(3000, -2); // FAF is published to 0.1 nm
  });

  it('ILS needles: sense, scaling and coverage', () => {
    const north = ilsDeviation(WORLD, 10, 0.1, 1000); // 0.57° north, centreline to the left
    expect(north.loc).toBeLessThan(0);
    expect(north.loc).toBeCloseTo(-0.57, 1);
    expect(ilsDeviation(WORLD, 10, -0.1, 1000).loc).toBeGreaterThan(0);
    expect(ilsDeviation(WORLD, 10, 0, glidepathAlt(WORLD, 10)).gs).toBeCloseTo(0, 1);
    expect(ilsDeviation(WORLD, 10, 0, 2000).gs).toBe(2.5); // well below: fly up, pegged
    expect(ilsDeviation(WORLD, 26, 0, 3000).loc).toBeNull(); // beyond range
    expect(ilsDeviation(WORLD, -1, 0, 1000).loc).toBeNull(); // behind threshold
    expect(ilsDeviation(WORLD, 10, 8, 3000).loc).toBeNull(); // 38.7° off
  });
});

describe('altimetry', () => {
  it('a wrong altimeter setting puts the aircraft 27 ft/hPa off its indicated altitude', () => {
    // Pilot left 1013 set with QNH 1003 and was told 4000: indicated 4000, true 3730.
    const r = round([ac({ alt: 5000, altSetting: 1013, selAlt: 4000, x: 40 })]);
    const a = r.aircraft[0]!;
    run(r, 120, () => false);
    expect(r.ownView('p1')!.indAlt).toBeCloseTo(4000, -1);
    expect(a.alt).toBeCloseTo(4000 - 10 * 27, -1);
    a.apply({ altSetting: 1003 });
    expect(r.ownView('p1')!.indAlt).toBeCloseTo(3730, -1); // instantly reads true altitude
    run(r, 60, () => false);
    expect(a.alt).toBeCloseTo(4000, -1);
  });
});

describe('approach and landing', () => {
  function flyApproach(cfg: { gear: boolean }): Round {
    // Downwind-ish start north-east, vectored: heading 210 descending to 3000, then a
    // 30° intercept heading 240 with APP armed, configure on the glideslope.
    const r = round([ac({ x: 24, y: 12, alt: 6000, hdg: 210, ias: 220, selAlt: 6000 })]);
    const a = r.aircraft[0]!;
    a.apply({ hdg: 210, alt: 3000, spd: 200 });
    let phase = 0;
    run(r, 1200, undefined, () => {
      if (phase === 0 && a.y < 3) {
        a.apply({ hdg: 240, app: true, flaps: 1, spd: 180 });
        phase = 1;
      } else if (phase === 1 && a.apMode === 'LOC') {
        a.apply({ flaps: 2, spd: 160 });
        phase = 2;
      } else if (phase === 2 && a.gsCaptured) {
        a.apply({ gear: cfg.gear, flaps: 3, spd: 140 });
        phase = 3;
      }
    });
    return r;
  }

  it('vectored onto the ILS, configured, lands', () => {
    const r = flyApproach({ gear: true });
    const a = r.aircraft[0]!;
    expect(a.outcome).toBe('landed');
    expect(a.status).toBe('landed');
    expect(Math.abs(a.y)).toBeLessThan(0.05);
    expect(r.allEvents().map((e) => e.kind)).toEqual(['landed']);
  });

  it('gear-up landing is a runway accident', () => {
    const r = flyApproach({ gear: false });
    expect(r.aircraft[0]!.outcome).toBe('runway');
  });

  it('glideslope does not capture from above', () => {
    const r = round([ac({ x: 8, y: 0, alt: 4500, hdg: 270, ias: 160 })]);
    const a = r.aircraft[0]!;
    a.apply({ app: true });
    run(r, 20, () => false);
    expect(a.apMode).toBe('LOC');
    expect(a.gsCaptured).toBe(false);
  });

  it('TOO LOW GEAR on short final with gear up', () => {
    const r = round([ac({ x: 1, y: 0, alt: glidepathAlt(WORLD, 1), ias: 140, flaps: 3 })]);
    r.step(DT);
    expect(r.aircraft[0]!.warnings).toContain('TOO LOW GEAR');
  });
});

describe('terrain and GPWS', () => {
  it('flying level into Mt Carrow warns TERRAIN then PULL UP, then crashes', () => {
    // 3000 ft heading west toward the 4200 ft cylinder centred (9,9) r3.5.
    const r = round([ac({ x: 20, y: 9, alt: 3000, hdg: 270, ias: 200 })]);
    const a = r.aircraft[0]!;
    const seen = new Set<string>();
    run(r, 600, undefined, () => a.warnings.forEach((w) => seen.add(w)));
    expect(seen.has('TERRAIN')).toBe(true);
    expect(seen.has('PULL UP')).toBe(true);
    expect(a.outcome).toBe('terrain');
    expect(a.x).toBeCloseTo(12.5, 0);
  });

  it('descending into the ground away from the runway is terrain', () => {
    const r = round([ac({ x: 20, y: -20, alt: 3000, hdg: 90, selAlt: 0 })]);
    run(r, 600);
    expect(r.aircraft[0]!.outcome).toBe('terrain');
  });

  it('no terrain warning when established on the ILS', () => {
    const r = round([ac({ x: 5, y: 0, alt: glidepathAlt(WORLD, 5) - 150, ias: 140, gearDown: true, flaps: 3 })]);
    const a = r.aircraft[0]!;
    a.apply({ app: true });
    let warned = false;
    run(r, 600, undefined, () => (warned ||= a.gsCaptured && a.warnings.some((w) => w === 'TERRAIN' || w === 'PULL UP')));
    expect(a.outcome).toBe('landed');
    expect(warned).toBe(false);
  });
});

describe('collision, fuel, alerts', () => {
  it('head-on at the same altitude: both collision, one event', () => {
    const r = round([
      ac({ callsign: 'AAA1', playerId: 'a', x: 30, y: 15, hdg: 270, alt: 6000 }),
      ac({ callsign: 'BBB2', playerId: 'b', x: 20, y: 15, hdg: 90, alt: 6000 }),
    ]);
    run(r, 300);
    expect(r.aircraft.map((a) => a.outcome)).toEqual(['collision', 'collision']);
    expect(r.allEvents()).toHaveLength(1);
    expect(r.allEvents()[0]!.callsigns.sort()).toEqual(['AAA1', 'BBB2']);
  });

  it('1000 ft apart they pass safely but trigger no collision', () => {
    const r = round([
      ac({ playerId: 'a', x: 30, y: 15, hdg: 270, alt: 6000 }),
      ac({ playerId: 'b', x: 20, y: 15, hdg: 90, alt: 7000 }),
    ]);
    let conflict = false;
    run(r, 200, () => false, () => (conflict ||= r.radar().some((t) => t.conflict)));
    expect(r.aircraft.every((a) => a.flying)).toBe(true);
    expect(conflict).toBe(false);
  });

  it('conflict alert inside 3 nm and 1000 ft', () => {
    const r = round([
      ac({ playerId: 'a', x: 30, y: 15, alt: 6000 }),
      ac({ playerId: 'b', x: 32, y: 15, alt: 6500 }),
      ac({ playerId: 'c', x: 30, y: 25, alt: 6000 }),
    ]);
    expect(r.radar().map((t) => t.conflict)).toEqual([true, true, false]);
  });

  it('MSAW below the sector MSA unless established', () => {
    const r = round([
      ac({ playerId: 'a', x: 20, y: 5, alt: 3000 }), // sector 000-090, MSA 5200
      ac({ playerId: 'b', x: 20, y: 5, alt: 6000 }),
    ]);
    expect(r.radar().map((t) => t.msaw)).toEqual([true, false]);
    const est = round([ac({ x: 12, y: 0, alt: 3000 })]);
    est.aircraft[0]!.apply({ app: true });
    est.step(DT);
    expect(est.aircraft[0]!.apMode).toBe('LOC');
    expect(est.radar()[0]!.msaw).toBe(false);
  });

  it('fuel exhaustion with LOW FUEL warning first', () => {
    const r = round([ac({ x: 30, y: 30, alt: 8000, fuelMin: 6 })]);
    const a = r.aircraft[0]!;
    let low = false;
    run(r, 3600, undefined, () => (low ||= a.warnings.includes('LOW FUEL')));
    expect(low).toBe(true);
    expect(a.outcome).toBe('fuel');
    expect(r.time).toBeCloseTo(360, 0);
  });
});

describe('autopilot clamping', () => {
  it('clamps and rounds panel inputs', () => {
    const a = new Aircraft(ac(), QNH);
    a.apply({ hdg: -10, alt: 123456, spd: 90, altSetting: 2000 });
    expect(a.selHdg).toBe(350);
    expect(a.selAlt).toBe(20000);
    expect(a.selSpd).toBe(200); // clean minimum
    expect(a.altSetting).toBe(1050);
    a.apply({ flaps: 3, spd: 90 });
    expect(a.selSpd).toBe(135);
    a.apply({ flaps: 0 });
    expect(a.selSpd).toBe(200);
    a.apply({ spd: 400, hdg: 360 });
    expect(a.selSpd).toBe(250);
    expect(a.selHdg).toBe(0);
  });
});

describe('spawns and win condition', () => {
  it('spawns are separated, above MSA, warning-free, at the gates with a fuel margin', () => {
    for (let seed = 1; seed <= 200; seed++) {
      const ids = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'].slice(0, 1 + (seed % 8));
      const r = new Round(ids, { rng: mulberry32(seed) });
      expect(r.aircraft).toHaveLength(ids.length);
      expect(new Set(r.aircraft.map((a) => a.callsign)).size).toBe(ids.length);
      for (const a of r.aircraft) {
        const d = Math.hypot(a.x, a.y);
        expect(d).toBeGreaterThanOrEqual(25);
        expect(d).toBeLessThanOrEqual(35);
        expect(a.alt).toBeGreaterThan(msaAt(WORLD, a.x, a.y));
        expect(a.alt).toBeGreaterThan(6400);
        expect(a.warnings).toEqual([]);
        expect(a.ias).toBe(250);
        expect(a.altSetting).toBe(1013);
        expect(a.fuelMin).toBeGreaterThanOrEqual(directApproachMinutes(WORLD, a.x, a.y) + 7.9);
        expect(a.fuelMin).toBeLessThanOrEqual(directApproachMinutes(WORLD, a.x, a.y) + 14.1);
      }
      expect(r.radar().some((t) => t.conflict || t.msaw)).toBe(false);
      for (const a of r.aircraft)
        for (const b of r.aircraft)
          if (a !== b) expect(dist(a.x, a.y, b.x, b.y) >= 3 || Math.abs(a.alt - b.alt) >= 1000).toBe(true);
    }
  });

  it('a direct approach from a spawn lands with fuel to spare', () => {
    const r = new Round(['p'], { rng: mulberry32(7) });
    const a = r.aircraft[0]!;
    // Competent pilot: correct QNH, straight to a 10 nm final, descend early, configure on the ILS.
    a.apply({ altSetting: r.qnh, alt: 3000, spd: 220 });
    let phase = 0;
    run(r, 3600, undefined, () => {
      const tgt = { x: 18, y: a.y > 0 ? 4 : -4 };
      if (phase === 0) {
        const brg = (Math.atan2(tgt.x - a.x, tgt.y - a.y) * 180) / Math.PI;
        a.apply({ hdg: brg });
        if (dist(a.x, a.y, tgt.x, tgt.y) < 1.5) {
          a.apply({ hdg: a.y > 0 ? 240 : 300, app: true, flaps: 1, spd: 180 });
          phase = 1;
        }
      } else if (phase === 1 && a.gsCaptured) {
        a.apply({ gear: true, flaps: 3, spd: 140 });
        phase = 2;
      }
    });
    expect(a.outcome).toBe('landed');
    expect(a.fuelMin).toBeGreaterThan(7);
  });

  it('tower needs strictly more than half landed', () => {
    expect(Round.winner(['landed', 'landed', 'terrain'])).toBe('tower');
    expect(Round.winner(['landed', 'terrain'])).toBe('impostor');
    expect(Round.winner(['landed', 'landed', 'fuel', 'collision'])).toBe('impostor');
    expect(Round.winner(['landed', 'landed', 'landed', 'collision'])).toBe('tower');
    expect(Round.winner(['landed'])).toBe('tower');
    expect(Round.winner(['runway'])).toBe('impostor');
  });

  it('EndResult carries ids and outcomes', () => {
    const r = round([ac({ playerId: 'p1', callsign: 'X1', alt: 520, selAlt: 0, x: 20, y: 20 })]);
    run(r, 60);
    expect(r.finished).toBe(true);
    expect(r.result('rc', 'imp')).toMatchObject({
      winner: 'impostor',
      realControllerId: 'rc',
      impostorId: 'imp',
      outcomes: [{ callsign: 'X1', playerId: 'p1', outcome: 'terrain' }],
    });
  });

  it('is deterministic for a seed', () => {
    const a = new Round(['a', 'b', 'c'], { rng: mulberry32(42) });
    const b = new Round(['a', 'b', 'c'], { rng: mulberry32(42) });
    expect(a.radar()).toEqual(b.radar());
    expect(a.atis).toEqual(b.atis);
  });
});
