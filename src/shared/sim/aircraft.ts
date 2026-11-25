// One aircraft: kinematic state, autopilot, altimetry, ILS, fuel and GPWS.
// Pure and deterministic: everything advances only through step(dt).

import type { AircraftStatus, ApMode, FlapSetting, Outcome, OwnAircraft, RadarTarget } from '../protocol';
import type { WorldDef } from '../world';
import {
  DEG,
  FT_PER_NM,
  angleDiff,
  bearing,
  clamp,
  glidepathAlt,
  headingVec,
  ilsDeviation,
  norm360,
  obstacleElevAt,
  terrainElevAt,
} from './geo';

/** Generic twin-jet performance (DESIGN.md "Simulation"). */
export const PERF = {
  minSpd: [200, 180, 160, 135] as const, // by flap setting
  maxSpd: 250, // 250 kt below 10 000 ft; the whole game happens there
  turnRateDegS: 3,
  climbFpm: 1800,
  descentFpm: 1800,
  maxDescentFpm: 2500, // used for long descents and on the glideslope
  accelKtS: 1.5,
  vsAccelFpmS: 400, // how fast the vertical speed itself changes
  minAltSel: 0,
  maxAltSel: 20000,
  minAltSetting: 950,
  maxAltSetting: 1050,
} as const;

/** Altimeter error: ft of indicated altitude per hPa of setting error. */
export const FT_PER_HPA = 27;

const LANDING_MAX_IAS = 155;
const GPWS_LOOKAHEAD_S = 30;
const GPWS_PULLUP_S = 12;
const RADALT_MAX = 2500;
const LOC_GAIN_DEG_PER_NM = 80;
const LOC_MAX_CUT_DEG = 30;
const GS_GAIN_FPM_PER_FT = 6;

export interface ApCommand {
  hdg?: number;
  alt?: number;
  spd?: number;
  app?: boolean;
  gear?: boolean;
  flaps?: FlapSetting;
  altSetting?: number;
}

export interface AircraftInit {
  callsign: string;
  playerId: string;
  x: number;
  y: number;
  /** True altitude ft MSL. */
  alt: number;
  hdg: number;
  ias: number;
  fuelMin: number;
  selAlt?: number; // indicated; defaults to the current indicated altitude rounded to 100
  altSetting?: number; // default 1013
  gearDown?: boolean;
  flaps?: FlapSetting;
}

export class Aircraft {
  readonly callsign: string;
  readonly playerId: string;
  x: number;
  y: number;
  alt: number; // true altitude ft MSL
  hdg: number;
  ias: number;
  vs = 0;
  fuelMin: number;
  selHdg: number;
  selAlt: number;
  selSpd: number;
  appArmed = false;
  locCaptured = false;
  gsCaptured = false;
  /** Glideslope has been seen above the aircraft since the localizer was captured (capture from below only). */
  private gsBelowSeen = false;
  gearDown: boolean;
  flaps: FlapSetting;
  altSetting: number;
  status: AircraftStatus = 'flying';
  outcome: Outcome = 'flying';
  warnings: string[] = [];

  constructor(init: AircraftInit, qnh: number) {
    this.callsign = init.callsign;
    this.playerId = init.playerId;
    this.x = init.x;
    this.y = init.y;
    this.alt = init.alt;
    this.hdg = norm360(init.hdg);
    this.ias = init.ias;
    this.fuelMin = init.fuelMin;
    this.altSetting = init.altSetting ?? 1013;
    this.gearDown = init.gearDown ?? false;
    this.flaps = init.flaps ?? 0;
    this.selHdg = Math.round(this.hdg) % 360;
    this.selAlt = init.selAlt ?? Math.round(this.indicatedAlt(qnh) / 100) * 100;
    this.selSpd = clamp(Math.round(init.ias), PERF.minSpd[this.flaps], PERF.maxSpd);
  }

  get flying(): boolean {
    return this.status === 'flying';
  }

  /** Indicated = true + (setting − QNH) × 27 ft. */
  indicatedAlt(qnh: number): number {
    return this.alt + (this.altSetting - qnh) * FT_PER_HPA;
  }

  /** True airspeed (= ground speed, no wind): +2 % per 1000 ft. */
  tas(): number {
    return this.ias * (1 + 0.02 * Math.max(0, this.alt) / 1000);
  }

  get apMode(): ApMode {
    return this.gsCaptured ? 'APP' : this.locCaptured ? 'LOC' : 'HDG';
  }

  /** Apply an already type-checked autopilot command, clamping every field to what the panel can set. */
  apply(cmd: ApCommand): void {
    if (!this.flying) return;
    if (cmd.flaps !== undefined) this.flaps = clamp(Math.round(cmd.flaps), 0, 3) as FlapSetting;
    if (cmd.gear !== undefined) this.gearDown = cmd.gear;
    if (cmd.hdg !== undefined) this.selHdg = Math.round(norm360(cmd.hdg)) % 360;
    if (cmd.alt !== undefined) this.selAlt = clamp(Math.round(cmd.alt / 100) * 100, PERF.minAltSel, PERF.maxAltSel);
    if (cmd.spd !== undefined) this.selSpd = Math.round(cmd.spd);
    if (cmd.altSetting !== undefined)
      this.altSetting = clamp(Math.round(cmd.altSetting), PERF.minAltSetting, PERF.maxAltSetting);
    if (cmd.app !== undefined) {
      this.appArmed = cmd.app;
      if (!cmd.app) this.disconnectApproach();
    }
    // Re-clamp after any flap change too: retracting flaps raises the minimum.
    this.selSpd = clamp(this.selSpd, PERF.minSpd[this.flaps], PERF.maxSpd);
  }

  private disconnectApproach(): void {
    this.locCaptured = false;
    this.gsCaptured = false;
    this.gsBelowSeen = false;
  }

  /** Advance dt seconds. Returns an outcome if the aircraft stopped flying (except collisions, handled by the round). */
  step(dt: number, world: WorldDef, qnh: number): Outcome | null {
    if (!this.flying) return null;

    // --- lateral ---
    let targetHdg = this.selHdg;
    if (this.locCaptured) {
      // Steer to the centreline with a cut proportional to cross-track error, capped at 30°.
      const back = norm360(world.ils.courseDeg + 180);
      const off = angleDiff(back, bearing(0, 0, this.x, this.y));
      const xtk = Math.hypot(this.x, this.y) * Math.sin(off * DEG); // nm, >0 = left of the inbound course
      targetHdg = norm360(world.ils.courseDeg + clamp(xtk * LOC_GAIN_DEG_PER_NM, -LOC_MAX_CUT_DEG, LOC_MAX_CUT_DEG));
    }
    const turnErr = angleDiff(this.hdg, targetHdg);
    const turnRate = clamp(turnErr * 1.0, -PERF.turnRateDegS, PERF.turnRateDegS); // proportional roll-out
    this.hdg = norm360(this.hdg + turnRate * dt);

    // --- speed ---
    const targetSpd = clamp(this.selSpd, PERF.minSpd[this.flaps], PERF.maxSpd);
    this.ias += clamp(targetSpd - this.ias, -PERF.accelKtS * dt, PERF.accelKtS * dt);

    // --- vertical ---
    let vsCmd: number;
    if (this.gsCaptured) {
      const d = Math.hypot(this.x, this.y);
      const nominal = -(this.tas() / 60) * FT_PER_NM * Math.tan(world.ils.glideDeg * DEG);
      vsCmd = clamp(nominal + GS_GAIN_FPM_PER_FT * (glidepathAlt(world, d) - this.alt), -PERF.maxDescentFpm, PERF.climbFpm);
    } else {
      // The autopilot holds INDICATED altitude, so a wrong setting puts the aircraft at the wrong true altitude.
      const err = this.selAlt - this.indicatedAlt(qnh);
      const maxDesc = err < -3000 ? PERF.maxDescentFpm : PERF.descentFpm;
      vsCmd = clamp(err * 5, -maxDesc, PERF.climbFpm);
    }
    this.vs += clamp(vsCmd - this.vs, -PERF.vsAccelFpmS * dt, PERF.vsAccelFpmS * dt);

    // --- move ---
    const prevX = this.x;
    const { dx, dy } = headingVec(this.hdg);
    const nm = (this.tas() / 3600) * dt;
    this.x += dx * nm;
    this.y += dy * nm;
    this.alt += (this.vs / 60) * dt;
    this.fuelMin = Math.max(0, this.fuelMin - dt / 60);

    // --- threshold crossing, judged on the approach state we arrived with ---
    if (prevX > 0 && this.x <= 0 && Math.abs(this.y) < 0.5 && this.locCaptured && this.gsCaptured) {
      const stable = this.gearDown && this.flaps === 3 && this.ias <= LANDING_MAX_IAS;
      return this.finish(stable ? 'landed' : 'runway');
    }

    // --- ILS capture (on the new position) ---
    const now = ilsDeviation(world, this.x, this.y, this.alt);
    if (this.locCaptured && now.loc === null) this.disconnectApproach(); // flew out of coverage
    if (this.appArmed && !this.locCaptured && now.loc !== null) {
      const intercept = Math.abs(angleDiff(this.hdg, world.ils.courseDeg));
      if (Math.abs(now.loc) < 2.5 && intercept <= 90) this.locCaptured = true;
    }
    if (this.locCaptured && !this.gsCaptured && now.gs !== null) {
      if (now.gs > 0.05) this.gsBelowSeen = true;
      else if (this.gsBelowSeen) this.gsCaptured = true;
    }

    // --- outcomes ---
    if (this.alt < terrainElevAt(world, this.x, this.y)) return this.finish('terrain');
    if (this.fuelMin <= 0) return this.finish('fuel');
    return null;
  }

  finish(outcome: Exclude<Outcome, 'flying'>): Outcome {
    this.status = outcome === 'landed' ? 'landed' : 'crashed';
    this.outcome = outcome;
    this.vs = 0;
    this.warnings = [];
    return outcome;
  }

  radAlt(world: WorldDef): number | null {
    const agl = this.alt - terrainElevAt(world, this.x, this.y);
    return agl < RADALT_MAX ? Math.max(0, agl) : null;
  }

  /** Seconds until the straight-line projected flight path hits terrain, or null within the look-ahead. */
  private secondsToImpact(world: WorldDef): number | null {
    // Established and descending to the runway: only obstacles count, not the ground ahead.
    const established = this.locCaptured && this.gsCaptured;
    const { dx, dy } = headingVec(this.hdg);
    const nmPerS = this.tas() / 3600;
    for (let t = 1; t <= GPWS_LOOKAHEAD_S; t++) {
      const px = this.x + dx * nmPerS * t;
      const py = this.y + dy * nmPerS * t;
      const pa = this.alt + (this.vs / 60) * t;
      const ground = established ? obstacleElevAt(world, px, py) : terrainElevAt(world, px, py);
      if (ground !== null && pa < ground) return t;
    }
    return null;
  }

  updateWarnings(world: WorldDef): void {
    if (!this.flying) {
      this.warnings = [];
      return;
    }
    const w: string[] = [];
    const tti = this.secondsToImpact(world);
    if (tti !== null) {
      w.push('TERRAIN');
      if (tti <= GPWS_PULLUP_S) w.push('PULL UP');
    }
    const ra = this.radAlt(world);
    if (ra !== null && ra < 500 && !this.gearDown) w.push('TOO LOW GEAR');
    if (this.fuelMin < 5) w.push('LOW FUEL');
    this.warnings = w;
  }

  ownView(world: WorldDef, qnh: number): OwnAircraft {
    const ils = this.flying ? ilsDeviation(world, this.x, this.y, this.alt) : { loc: null, gs: null };
    const r1 = (v: number) => Math.round(v * 10) / 10;
    const r2 = (v: number) => Math.round(v * 100) / 100;
    const ra = this.radAlt(world);
    const own: OwnAircraft = {
      callsign: this.callsign,
      status: this.status,
      hdg: r1(this.hdg) % 360,
      ias: r1(this.ias),
      indAlt: Math.round(this.indicatedAlt(qnh)),
      radAlt: ra === null ? null : Math.round(ra),
      vs: Math.round(this.vs / 10) * 10,
      fuelMin: r1(this.fuelMin),
      dme: r1(Math.hypot(this.x, this.y)),
      bearingToStation: Math.round(bearing(this.x, this.y, 0, 0)) % 360,
      locDev: ils.loc === null ? null : r2(ils.loc),
      gsDev: ils.gs === null ? null : r2(ils.gs),
      selHdg: this.selHdg,
      selAlt: this.selAlt,
      selSpd: this.selSpd,
      appArmed: this.appArmed,
      apMode: this.apMode,
      gsCaptured: this.gsCaptured,
      gearDown: this.gearDown,
      flaps: this.flaps,
      altSetting: this.altSetting,
      warnings: [...this.warnings],
    };
    if (this.outcome !== 'flying') own.outcome = this.outcome;
    return own;
  }

  radarView(conflict: boolean, msaw: boolean): RadarTarget {
    return {
      callsign: this.callsign,
      x: Math.round(this.x * 1000) / 1000,
      y: Math.round(this.y * 1000) / 1000,
      alt: Math.round(this.alt / 100) * 100, // Mode C: 100 ft resolution, QNH-corrected = true altitude
      gs: this.flying ? Math.round(this.tas()) : 0,
      track: Math.round(this.hdg) % 360,
      vsTrend: this.vs > 300 ? 1 : this.vs < -300 ? -1 : 0,
      status: this.status,
      conflict,
      msaw,
    };
  }
}
