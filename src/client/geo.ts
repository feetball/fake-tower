// Geometry helpers shared by the scope and the approach plate.
// World: x = nm east, y = nm north. Bearings: degrees true, clockwise from north.

import type { WorldDef } from '../shared/world';

export const D2R = Math.PI / 180;

export function norm360(d: number): number {
  return ((d % 360) + 360) % 360;
}

/** Heading for display: 1..360 (000 is shown as 360). */
export function hdgText(d: number): string {
  const v = Math.round(norm360(d));
  return String(v === 0 ? 360 : v).padStart(3, '0');
}

export function bearingTo(x0: number, y0: number, x1: number, y1: number): number {
  return norm360(Math.atan2(x1 - x0, y1 - y0) / D2R);
}

export function pointAt(x: number, y: number, brg: number, dist: number): { x: number; y: number } {
  return { x: x + dist * Math.sin(brg * D2R), y: y + dist * Math.cos(brg * D2R) };
}

/** Shortest signed angle from a to b, -180..180. */
export function angleDiff(a: number, b: number): number {
  return ((((b - a) % 360) + 540) % 360) - 180;
}

/**
 * Racetrack hold as a world-coordinate polyline. Inbound leg ends at the fix;
 * 1-minute legs at the given speed, standard-rate turns.
 */
export function holdPath(world: WorldDef, speedKt = 210): { x: number; y: number }[] {
  const fix = world.fixes.find((f) => f.name === world.hold.fix);
  if (!fix) return [];
  const inb = world.hold.inboundCourseDeg;
  const r = speedKt / (60 * Math.PI); // standard rate turn radius nm
  const leg = speedKt / 60; // one minute
  const side = world.hold.turn === 'R' ? 90 : -90;
  const pts: { x: number; y: number }[] = [];
  const start = pointAt(fix.x, fix.y, inb + 180, leg); // start of inbound leg
  // inbound leg
  pts.push(start, { x: fix.x, y: fix.y });
  // turn at the fix: centre is abeam the fix on the holding side
  const c1 = pointAt(fix.x, fix.y, inb + side, r);
  const a0 = norm360(inb - side); // bearing from c1 to fix
  for (let i = 1; i <= 24; i++) {
    const a = a0 + (side > 0 ? 1 : -1) * (180 * i) / 24;
    pts.push(pointAt(c1.x, c1.y, a, r));
  }
  // outbound leg
  const outEnd = pointAt(start.x, start.y, inb + side, 2 * r);
  pts.push(outEnd);
  const c2 = pointAt(start.x, start.y, inb + side, r);
  const b0 = norm360(inb + side);
  for (let i = 1; i <= 24; i++) {
    const a = b0 + (side > 0 ? 1 : -1) * (180 * i) / 24;
    pts.push(pointAt(c2.x, c2.y, a, r));
  }
  return pts;
}

/** MSA sector for a position (bearing from the station at the origin). */
export function msaAt(world: WorldDef, x: number, y: number): number | null {
  const b = bearingTo(0, 0, x, y);
  for (const s of world.msa) {
    const inSector = s.fromDeg <= s.toDeg ? b >= s.fromDeg && b < s.toDeg : b >= s.fromDeg || b < s.toDeg;
    if (inSector) return s.altFt;
  }
  return null;
}

/** Distance of the FAF from the threshold. */
export function fafDist(world: WorldDef): number {
  return Math.hypot(world.ils.faf.x, world.ils.faf.y);
}
