// Scripted "competent pilot" used by the tower-wins e2e scenario. Pure: it reads
// only the pilot's own instruments (OwnAircraft from protocol.ts) and returns the
// panel settings it wants. The e2e test applies them through the cockpit UI; a
// vitest test runs the same logic against the sim over many seeds so the e2e
// scenario cannot be flaky because of the flying.
//
// Plan (runway 27, ILS 270, field at the origin, final approach east, x > 0):
//  - altimeter to the ATIS QNH, so indicated altitude = true altitude;
//  - stay at 6000 west of x = 13 nm (clears Mt Carrow 4200 / West Ridge 4900);
//  - fly direct to an entry point abeam the final on the side we spawned:
//    lead (20, ±5) at the 3000 ft platform, trail (24, ±5) at 4000 ft;
//  - turn in only when low enough to meet the glideslope from below (and, for
//    the trail, once the lead is established); otherwise extend (lead: outward,
//    trail: east) and come back;
//  - the trail waits until the lead is established on the localizer, so the two
//    are sequenced on the final with ~7+ nm between them;
//  - intercept leg aimed 7 nm inside the entry point (30-45° cut) with APP
//    armed, flaps 1 / 180 kt; on the localizer the trail descends to the
//    3000 platform; glideslope captured from
//    below: gear down, flaps 3, 140 kt; the autopilot flies it to touchdown.

export const PLATFORM_FT = 3000;
const SAFE_WEST_FT = 6000;
const EAST_OF_TERRAIN_X = 13;
const ENTRY = { lead: { x: 20, alt: PLATFORM_FT }, trail: { x: 24, alt: 4000 } };
/** The intercept leg aims at the centreline this far inside the entry point. */
const AIM_INSIDE_NM = 7;
const D2R = Math.PI / 180;
const GS_FT_PER_NM = 6076.12 * Math.tan(3 * D2R);
/** Glidepath altitude (ft MSL, field 512 + TCH 50) at d nm. */
const glidepath = (d) => 562 + d * GS_FT_PER_NM;

/** Position (nm east/north of the threshold) from DME and bearing to the station. */
export function position(ac) {
  const from = (ac.bearingToStation + 180) * D2R;
  return { x: ac.dme * Math.sin(from), y: ac.dme * Math.cos(from) };
}

function bearingTo(x0, y0, x1, y1) {
  return ((Math.atan2(x1 - x0, y1 - y0) / D2R) % 360 + 360) % 360;
}

export class ApproachPilot {
  /** role: 'lead' | 'trail'. qnh: ATIS QNH. */
  constructor(role, qnh) {
    this.role = role;
    this.qnh = qnh;
    this.phase = 'enroute';
    this.side = 0;
    this.extending = false;
    this.entry = null;
  }

  /** Lead is on the localizer (or no longer flying): the trail may turn in. */
  get established() {
    return this.phase === 'loc' || this.phase === 'gs' || this.phase === 'done';
  }

  /**
   * One decision from the latest own-aircraft view. leadEstablished only matters
   * for the trail. Returns { panel, fail? } where panel is the full desired
   * { altSetting, hdg, alt, spd, flaps, gear, app }.
   */
  decide(ac, leadEstablished = true) {
    const { x, y } = position(ac);
    if (ac.status !== 'flying') {
      this.phase = 'done';
      return { panel: null };
    }
    const cfg = ENTRY[this.role];
    if (!this.side) {
      this.side = y >= 0 ? 1 : -1;
      this.entry = { x: cfg.x, y: 5 * this.side };
    }
    const aim = { x: cfg.x - AIM_INSIDE_NM, y: 0 };
    // Heading to the aim point, but never cutting the 270 course at more than 45° or less than 20°.
    const cut = Math.max(20, Math.min(45, Math.abs(((bearingTo(x, y, aim.x, aim.y) - 270 + 540) % 360) - 180)));
    const intercept = Math.round(270 - this.side * cut);
    const panel = { altSetting: this.qnh, hdg: ac.selHdg, alt: cfg.alt, spd: 250, flaps: 0, gear: false, app: false };
    let fail;

    if (this.phase === 'enroute') {
      const e = this.entry;
      const d = Math.hypot(e.x - x, e.y - y);
      const east = x >= EAST_OF_TERRAIN_X;
      panel.alt = east ? cfg.alt : SAFE_WEST_FT;
      // Low enough to be under the glideslope at the aim point even if still descending.
      const lowEnough = east && ac.indAlt <= glidepath(aim.x) - 700 && ac.altSetting === this.qnh;
      const ready = lowEnough && (this.role === 'lead' || leadEstablished);
      if (d < 2 && ready) {
        this.phase = 'intercept';
        this.extending = false;
        this.interceptHdg = intercept;
      } else {
        if (d < 2 && !ready) this.extending = true;
        if (this.extending && (d > 5 || (ready && d > 3))) this.extending = false;
        const extendHdg = this.role === 'lead' ? (this.side > 0 ? 0 : 180) : 90;
        panel.hdg = Math.round(this.extending ? extendHdg : bearingTo(x, y, e.x, e.y)) % 360;
        panel.spd = d < 10 || this.extending ? 210 : 250;
      }
    }
    if (this.phase !== 'enroute') panel.hdg = this.interceptHdg ?? intercept;
    if (this.phase === 'intercept') {
      Object.assign(panel, { app: true, flaps: 1, spd: 180 });
      if (ac.apMode !== 'HDG') this.phase = 'loc';
      else if (x < 8) fail = `still not on the localizer at x=${x.toFixed(1)} nm`;
    }
    if (this.phase === 'loc') {
      Object.assign(panel, { app: true, flaps: 1, spd: 180, alt: PLATFORM_FT });
      if (ac.gsCaptured) this.phase = 'gs';
      else if (x < 5) fail = `glideslope not captured by x=${x.toFixed(1)} nm (indAlt ${ac.indAlt}, gsDev ${ac.gsDev})`;
    }
    if (this.phase === 'gs') {
      Object.assign(panel, { app: true, flaps: 3, gear: true, spd: 140, alt: PLATFORM_FT });
    }
    return { panel, fail };
  }
}

/** Pick lead/trail: the aircraft closer to the lead entry point goes first. */
export function assignSequence(acs) {
  const d = acs.map((ac) => {
    const { x, y } = position(ac);
    return Math.hypot(ENTRY.lead.x - x, 5 * (y >= 0 ? 1 : -1) - y);
  });
  return d[0] <= d[1] ? ['lead', 'trail'] : ['trail', 'lead'];
}

/** Panel fields that differ between what the pilot wants and what the server has. */
export function panelDiff(ac, panel) {
  const out = {};
  if (ac.altSetting !== panel.altSetting) out.altSetting = panel.altSetting;
  if (ac.flaps !== panel.flaps) out.flaps = panel.flaps;
  if (ac.gearDown !== panel.gear) out.gear = panel.gear;
  if (ac.appArmed !== panel.app) out.app = panel.app;
  if (Math.abs(((ac.selHdg - panel.hdg + 540) % 360) - 180) >= 2) out.hdg = panel.hdg;
  if (ac.selAlt !== panel.alt) out.alt = panel.alt;
  if (ac.selSpd !== panel.spd) out.spd = panel.spd;
  return out;
}
