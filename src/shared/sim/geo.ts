// Geometry and airspace lookups. Coordinates: x = nm east, y = nm north of the
// runway 27 threshold. Headings/bearings are true degrees, 0 = north.

import type { WorldDef } from '../world';

export const FT_PER_NM = 6076.12;
export const DEG = Math.PI / 180;

export function norm360(deg: number): number {
  const d = deg % 360;
  return d < 0 ? d + 360 : d;
}

/** Signed shortest angle from a to b, in (-180, 180]. */
export function angleDiff(a: number, b: number): number {
  const d = norm360(b - a);
  return d > 180 ? d - 360 : d;
}

export function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v;
}

export function dist(x1: number, y1: number, x2: number, y2: number): number {
  return Math.hypot(x2 - x1, y2 - y1);
}

/** True bearing from (x1,y1) to (x2,y2). */
export function bearing(x1: number, y1: number, x2: number, y2: number): number {
  return norm360(Math.atan2(x2 - x1, y2 - y1) / DEG);
}

/** Unit displacement per nm along a heading. */
export function headingVec(hdg: number): { dx: number; dy: number } {
  return { dx: Math.sin(hdg * DEG), dy: Math.cos(hdg * DEG) };
}

/** MSA for the sector containing the bearing FROM the station (threshold) to the point. */
export function msaAt(world: WorldDef, x: number, y: number): number {
  const brg = bearing(0, 0, x, y);
  for (const s of world.msa) {
    const inSector =
      s.fromDeg <= s.toDeg ? brg >= s.fromDeg && brg < s.toDeg : brg >= s.fromDeg || brg < s.toDeg;
    if (inSector) return s.altFt;
  }
  return Math.max(...world.msa.map((s) => s.altFt));
}

/** Ground/obstacle elevation under a point: the highest obstacle top containing it, else field elevation. */
export function terrainElevAt(world: WorldDef, x: number, y: number): number {
  let elev = world.fieldElevFt;
  for (const t of world.terrain) {
    if (t.elevFt > elev && dist(x, y, t.x, t.y) < t.radiusNm) elev = t.elevFt;
  }
  return elev;
}

/** Highest obstacle top containing the point, or null (ignores the field elevation). */
export function obstacleElevAt(world: WorldDef, x: number, y: number): number | null {
  let elev: number | null = null;
  for (const t of world.terrain) {
    if (dist(x, y, t.x, t.y) < t.radiusNm && (elev === null || t.elevFt > elev)) elev = t.elevFt;
  }
  return elev;
}

/** Glidepath altitude ft MSL at distance d nm from the threshold. */
export function glidepathAlt(world: WorldDef, dNm: number): number {
  return world.fieldElevFt + world.ils.tchFt + dNm * FT_PER_NM * Math.tan(world.ils.glideDeg * DEG);
}

export interface IlsDeviation {
  loc: number | null; // dots, positive = fly right
  gs: number | null; // dots, positive = fly up
}

const LOC_DEG_PER_DOT = 1;
const GS_DEG_PER_DOT = 0.35;
const FULL_SCALE = 2.5;
/** Inside this distance from the threshold the ±35° coverage cone is not applied. */
export const ILS_NEAR_NM = 0.5;

/** ILS needles for an aircraft at (x, y, alt). Antennas are modelled at the threshold. */
export function ilsDeviation(world: WorldDef, x: number, y: number, alt: number): IlsDeviation {
  const d = Math.hypot(x, y);
  const backCourse = norm360(world.ils.courseDeg + 180); // bearing from threshold out along the final
  const brg = bearing(0, 0, x, y);
  const off = angleDiff(backCourse, brg); // >0: clockwise of the final approach course from the field
  // Coverage: ±35° of the course out to the range. The antennas are modelled at the
  // threshold, but a real localizer sits past the far end, so close in (where a few
  // feet of lateral error is a large angle) only "behind the threshold" (> 90° off
  // the back course) loses the signal. Without this, an aircraft established a few
  // dozen feet off the centreline lost LOC in the last step and went missed.
  if (d > world.ils.rangeNm || d < 1e-6 || Math.abs(off) > 90) return { loc: null, gs: null };
  if (Math.abs(off) > 35 && d > ILS_NEAR_NM) return { loc: null, gs: null };
  // Course 270, aircraft south of the centreline (bearing > 090): centreline is to the right.
  const loc = clamp(off / LOC_DEG_PER_DOT, -FULL_SCALE, FULL_SCALE);
  const angle = Math.atan2(alt - world.fieldElevFt - world.ils.tchFt, d * FT_PER_NM) / DEG;
  const gs = clamp((world.ils.glideDeg - angle) / GS_DEG_PER_DOT, -FULL_SCALE, FULL_SCALE);
  return { loc, gs };
}
