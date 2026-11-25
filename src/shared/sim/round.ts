// A round: spawn the pilots' aircraft, step the world, detect outcomes, and
// produce the pilot and controller views plus the final result.

import type { Atis, EndResult, Outcome, OwnAircraft, PlayerId, RadarTarget, RoundEvent } from '../protocol';
import { WORLD, type WorldDef } from '../world';
import { Aircraft, type AircraftInit, type ApCommand } from './aircraft';
import { makeAtis, randomQnh } from './atis';
import { bearing, dist, headingVec, msaAt } from './geo';
import { type Rng, pick, randInt, randRange, shuffle } from './rng';

export const COLLISION_NM = 0.15;
export const COLLISION_FT = 200;
const SPAWN_LATERAL_NM = 5; // margin above the 3 nm minimum at t=0
const SPAWN_LEVELS = [7000, 8000, 9000, 10000]; // indicated with 1013 set: FL070-FL100
const AIRLINES = ['SKW', 'DAL', 'UAL', 'AAL', 'ASA', 'JBU', 'SWA', 'FFT', 'ENY', 'RPA', 'NKS', 'QXE'];
const GATES = ['NORBY', 'SOLEY', 'EASTO', 'WHISK'];

export interface RoundOptions {
  rng: Rng;
  world?: WorldDef;
  /** Override the random QNH (tests). */
  qnh?: number;
  /** Place aircraft explicitly instead of spawning one per pilot (tests). */
  aircraft?: AircraftInit[];
}

/**
 * Fuel for a "competent direct approach": direct to the intermediate fix at
 * ~220 kt average groundspeed, then the final from there at ~150 kt.
 */
export function directApproachMinutes(world: WorldDef, x: number, y: number): number {
  const ifx = world.fixes.find((f) => f.name === 'RIDGE') ?? { x: 14, y: 0 };
  const finalNm = Math.hypot(ifx.x, ifx.y);
  return (dist(x, y, ifx.x, ifx.y) / 220) * 60 + (finalNm / 150) * 60;
}

/** Loss of separation used by the controller's conflict alert. */
function inConflict(a: Aircraft, b: Aircraft, world: WorldDef): boolean {
  return dist(a.x, a.y, b.x, b.y) < world.separation.lateralNm && Math.abs(a.alt - b.alt) < world.separation.verticalFt;
}

export class Round {
  readonly world: WorldDef;
  readonly qnh: number;
  readonly atis: Atis;
  readonly aircraft: Aircraft[];
  time = 0;
  private events: RoundEvent[] = [];

  constructor(pilotIds: PlayerId[], opts: RoundOptions) {
    this.world = opts.world ?? WORLD;
    this.qnh = opts.qnh ?? randomQnh(opts.rng);
    this.atis = makeAtis(this.world, this.qnh, opts.rng);
    const inits = opts.aircraft ?? this.spawn(pilotIds, opts.rng);
    this.aircraft = inits.map((i) => new Aircraft(i, this.qnh));
    for (const ac of this.aircraft) ac.updateWarnings(this.world);
  }

  private spawn(pilotIds: PlayerId[], rng: Rng): AircraftInit[] {
    const world = this.world;
    const gates = shuffle(rng, GATES)
      .map((n) => world.fixes.find((f) => f.name === n))
      .filter((f) => f !== undefined);
    const used = new Set<string>();
    const out: AircraftInit[] = [];
    pilotIds.forEach((playerId, i) => {
      let callsign: string;
      do callsign = pick(rng, AIRLINES) + randInt(rng, 100, 2999);
      while (used.has(callsign));
      used.add(callsign);

      for (let attempt = 0; attempt < 1000; attempt++) {
        // Prefer spreading across gates; fall back to any gate if one fills up.
        const gate = attempt < 200 ? gates[i % gates.length] : pick(rng, gates);
        if (!gate) break;
        const r = randRange(rng, 25, 35);
        const brg = bearing(0, 0, gate.x, gate.y) + randRange(rng, -6, 6);
        const { dx, dy } = headingVec(brg);
        const x = dx * r;
        const y = dy * r;
        const level = pick(rng, SPAWN_LEVELS);
        const alt = level - (1013 - this.qnh) * 27; // true altitude for that pressure level
        const separated = out.every((o) => dist(x, y, o.x, o.y) >= SPAWN_LATERAL_NM || Math.abs(alt - o.alt) >= 1000);
        if (!separated || alt <= msaAt(world, x, y) + 500) continue;
        const hdg = bearing(x, y, 0, 0) + randRange(rng, -10, 10);
        const init: AircraftInit = {
          callsign, playerId, x, y, alt, hdg, ias: 250, selAlt: level,
          fuelMin: Math.round((directApproachMinutes(world, x, y) + randRange(rng, 8, 14)) * 10) / 10,
        };
        const probe = new Aircraft(init, this.qnh);
        probe.updateWarnings(world);
        if (probe.warnings.length > 0) continue;
        out.push(init);
        return;
      }
      throw new Error('could not find a separated spawn');
    });
    return out;
  }

  byPlayer(playerId: PlayerId): Aircraft | undefined {
    return this.aircraft.find((a) => a.playerId === playerId);
  }

  /** Apply an autopilot command from a pilot. Returns false if they have no flying aircraft. */
  applyAp(playerId: PlayerId, cmd: ApCommand): boolean {
    const ac = this.byPlayer(playerId);
    if (!ac || !ac.flying) return false;
    ac.apply(cmd);
    return true;
  }

  get finished(): boolean {
    return !this.aircraft.some((a) => a.flying);
  }

  /** Advance the world. Returns the events that happened during this step. */
  step(dt: number): RoundEvent[] {
    if (this.finished) return [];
    this.time += dt;
    const out: RoundEvent[] = [];
    const time = Math.round(this.time * 10) / 10;
    const flying = this.aircraft.filter((a) => a.flying);
    for (const ac of flying) {
      const o = ac.step(dt, this.world, this.qnh);
      if (o) out.push({ time, kind: o, callsigns: [ac.callsign] });
    }
    const still = flying.filter((a) => a.flying);
    const collided = new Set<Aircraft>();
    for (let i = 0; i < still.length; i++) {
      for (let j = i + 1; j < still.length; j++) {
        const a = still[i]!;
        const b = still[j]!;
        if (dist(a.x, a.y, b.x, b.y) < COLLISION_NM && Math.abs(a.alt - b.alt) < COLLISION_FT) {
          collided.add(a);
          collided.add(b);
        }
      }
    }
    if (collided.size > 0) {
      for (const ac of collided) ac.finish('collision');
      out.push({ time, kind: 'collision', callsigns: [...collided].map((a) => a.callsign) });
    }
    for (const ac of this.aircraft) ac.updateWarnings(this.world);
    this.events.push(...out);
    return out;
  }

  ownView(playerId: PlayerId): OwnAircraft | null {
    return this.byPlayer(playerId)?.ownView(this.world, this.qnh) ?? null;
  }

  /** MSAW: flying, not established on the localizer/ILS, and below the sector MSA. */
  msaw(ac: Aircraft): boolean {
    return ac.flying && !ac.locCaptured && ac.alt < msaAt(this.world, ac.x, ac.y);
  }

  conflict(ac: Aircraft): boolean {
    return ac.flying && this.aircraft.some((o) => o !== ac && o.flying && inConflict(ac, o, this.world));
  }

  radar(): RadarTarget[] {
    return this.aircraft.map((a) => a.radarView(this.conflict(a), this.msaw(a)));
  }

  allEvents(): readonly RoundEvent[] {
    return this.events;
  }

  /** Tower wins if strictly more than half of the aircraft landed. */
  static winner(outcomes: readonly Outcome[]): 'tower' | 'impostor' {
    const landed = outcomes.filter((o) => o === 'landed').length;
    return landed * 2 > outcomes.length ? 'tower' : 'impostor';
  }

  result(realControllerId: PlayerId, impostorId: PlayerId): EndResult {
    const outcomes = this.aircraft.map((a) => ({ callsign: a.callsign, playerId: a.playerId, outcome: a.outcome }));
    return {
      winner: Round.winner(outcomes.map((o) => o.outcome)),
      realControllerId,
      impostorId,
      outcomes,
      durationSec: Math.round(this.time),
    };
  }
}
