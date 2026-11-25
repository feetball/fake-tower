// Generates game/tests/fixtures/parity.json from the TypeScript reference sim.
// Run from the repo root:  npx tsx game/tests/tools/gen_parity.ts
// The GDScript parity test (game/tests/test_parity.gd) replays the same scenarios
// (defined here and stored in the fixture) and compares the trajectories.

import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { type AircraftInit, type ApCommand } from '../../../src/shared/sim/aircraft';
import { mulberry32 } from '../../../src/shared/sim/rng';
import { Round } from '../../../src/shared/sim/round';

type SnakeCmd = Record<string, number | boolean>;
type SnakeInit = Record<string, number | string | boolean>;

interface Scenario {
  name: string;
  qnh: number;
  steps: number; // 0.1 s steps
  sampleEvery: number; // steps
  inits: SnakeInit[];
  /** Commands applied before the step with this index, to aircraft[ac]. */
  schedule: { step: number; ac: number; cmd: SnakeCmd }[];
}

const camel = (k: string) => k.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());
function toCamel<T>(o: Record<string, unknown>): T {
  return Object.fromEntries(Object.entries(o).map(([k, v]) => [camel(k), v])) as T;
}

const SCENARIOS: Scenario[] = [
  {
    // Vectored ILS: descend on a 210 heading, 30° intercept, configure, land.
    name: 'vectored_ils',
    qnh: 1003,
    steps: 7000,
    sampleEvery: 100,
    inits: [{ callsign: 'TST1', player_id: 1, x: 24, y: 12, alt: 6000, hdg: 210, ias: 220, fuel_min: 30, alt_setting: 1003, sel_alt: 6000 }],
    schedule: [
      { step: 0, ac: 0, cmd: { hdg: 210, alt: 3000, spd: 200 } },
      { step: 1300, ac: 0, cmd: { hdg: 240, app: true, flaps: 1, spd: 180 } },
      { step: 3400, ac: 0, cmd: { flaps: 2, spd: 160 } },
      { step: 4500, ac: 0, cmd: { gear: true, flaps: 3, spd: 140 } },
    ],
  },
  {
    // Wrong altimeter setting, then corrected; turns through north; speed changes.
    name: 'altimetry_turns',
    qnh: 1021,
    steps: 2400,
    sampleEvery: 40,
    inits: [{ callsign: 'TST2', player_id: 2, x: -25, y: 20, alt: 9000, hdg: 350, ias: 250, fuel_min: 40, alt_setting: 1013 }],
    schedule: [
      { step: 0, ac: 0, cmd: { hdg: 95, alt: 6000, spd: 210 } },
      { step: 700, ac: 0, cmd: { alt_setting: 1021, hdg: 181.4 } },
      { step: 1200, ac: 0, cmd: { alt: 11000, spd: 250, hdg: 359.6 } },
      { step: 1800, ac: 0, cmd: { flaps: 2, spd: 100, hdg: -45 } },
    ],
  },
  {
    // Two aircraft: one flies into Mt Carrow, the other descends into the ground.
    name: 'terrain_pair',
    qnh: 998,
    steps: 3000,
    sampleEvery: 25,
    inits: [
      { callsign: 'AAA1', player_id: 3, x: 20, y: 9, alt: 3000, hdg: 270, ias: 200, fuel_min: 30, alt_setting: 998 },
      { callsign: 'BBB2', player_id: 4, x: 20, y: -20, alt: 3000, hdg: 90, ias: 180, fuel_min: 30, alt_setting: 998, sel_alt: 0 },
    ],
    schedule: [],
  },
];

function sample(r: Round) {
  return r.aircraft.map((a) => ({
    x: a.x, y: a.y, alt: a.alt, hdg: a.hdg, ias: a.ias, vs: a.vs, fuel_min: a.fuelMin,
    status: a.status, outcome: a.outcome, ap_mode: a.apMode, warnings: [...a.warnings],
  }));
}

function runScenario(s: Scenario) {
  const inits = s.inits.map((i) => toCamel<AircraftInit>(i));
  const r = new Round([], { rng: mulberry32(1), qnh: s.qnh, aircraft: inits });
  const samples: { step: number; time: number; ac: ReturnType<typeof sample>; radar: unknown; own: unknown }[] = [];
  const events: unknown[] = [];
  for (let n = 0; n <= s.steps; n++) {
    for (const c of s.schedule) if (c.step === n) r.aircraft[c.ac]!.apply(toCamel<ApCommand>(c.cmd));
    if (n % s.sampleEvery === 0 || n === s.steps || r.finished) {
      samples.push({ step: n, time: r.time, ac: sample(r), radar: r.radar(), own: r.aircraft.map((a) => r.ownView(a.playerId)) });
    }
    if (n === s.steps || r.finished) break;
    events.push(...r.step(0.1));
  }
  return { ...s, samples, events };
}

function rngSeqs() {
  return [1, 42, 123456789, 4294967295].map((seed) => {
    const g = mulberry32(seed);
    // Exact integers (value * 2^32): decimal floats do not survive every JSON parser bit for bit.
    return { seed, u32: Array.from({ length: 16 }, () => g() * 4294967296) };
  });
}

function spawns() {
  return [7, 42, 1234].map((seed) => {
    const r = new Round(['a', 'b', 'c', 'd', 'e', 'f'], { rng: mulberry32(seed) });
    return {
      seed,
      pilots: 6,
      qnh: r.qnh,
      atis: r.atis,
      aircraft: r.aircraft.map((a) => ({ callsign: a.callsign, x: a.x, y: a.y, alt: a.alt, hdg: a.hdg, fuel_min: a.fuelMin, sel_alt: a.selAlt })),
    };
  });
}

const out = { generated_by: 'game/tests/tools/gen_parity.ts', rng: rngSeqs(), spawns: spawns(), scenarios: SCENARIOS.map(runScenario) };
const here = dirname(fileURLToPath(import.meta.url));
const path = join(here, '..', 'fixtures', 'parity.json');
writeFileSync(path, JSON.stringify(out, null, 1) + '\n');
console.log(`wrote ${path}`);
