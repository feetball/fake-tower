// Pure text/logic used by the canvas and DOM views (scope data blocks, flight
// strip, cockpit readouts and autopilot knobs, end screen). No DOM: unit-tested.

import type { EndResult, FlapSetting, PlayerId, RadarTarget } from '../shared/protocol';
import { norm360 } from './geo';
import { mmss } from './text';

// ---------------------------------------------------------------- radar scope

export type AlertTag = 'CA' | 'LA';

/** Conflict alert wins over low-altitude (MSAW) alert. */
export function alertTag(t: Pick<RadarTarget, 'conflict' | 'msaw'>): AlertTag | null {
  return t.conflict ? 'CA' : t.msaw ? 'LA' : null;
}

export function trendArrow(vsTrend: RadarTarget['vsTrend']): string {
  return vsTrend > 0 ? '↑' : vsTrend < 0 ? '↓' : ' ';
}

/**
 * Data block text, top to bottom: [alert], callsign, "AAA↑ GG" (altitude in
 * hundreds of feet, trend, ground speed in tens of knots), [scratchpad, 7 chars].
 */
export function dataBlock(t: RadarTarget, scratch: string | undefined): { alert: AlertTag | null; lines: string[] } {
  const alert = alertTag(t);
  const altHund = String(Math.max(0, Math.round(t.alt / 100))).padStart(3, '0');
  const gsTens = String(Math.max(0, Math.round(t.gs / 10))).padStart(2, '0');
  const lines: string[] = [];
  if (alert) lines.push(alert);
  lines.push(t.callsign, `${altHund}${trendArrow(t.vsTrend)} ${gsTens}`);
  const sp = (scratch ?? '').trim().toUpperCase().slice(0, 7);
  if (sp) lines.push(sp);
  return { alert, lines };
}

/** Flight strip altitude: "5200 ft ↑" ('=' when level). */
export function stripAltText(t: Pick<RadarTarget, 'alt' | 'vsTrend'>): string {
  return `${Math.round(t.alt)} ft ${t.vsTrend > 0 ? '↑' : t.vsTrend < 0 ? '↓' : '='}`;
}

/** Flight strip status cell: LANDED/CRASHED, else CA/LA, else blank; plus its CSS class. */
export function stripStatus(t: Pick<RadarTarget, 'status' | 'conflict' | 'msaw'>): { text: string; cls: string } {
  const text = t.status !== 'flying' ? t.status.toUpperCase() : (alertTag(t) ?? '');
  return { text, cls: `strip-status ${t.conflict ? 'ca' : t.msaw ? 'la' : t.status}` };
}

/** Traffic list altitude column: hundreds of feet while flying, else the status. */
export function trafficAltText(t: Pick<RadarTarget, 'status' | 'alt'>): string {
  return t.status === 'flying' ? String(Math.round(t.alt / 100)).padStart(3, '0') : t.status.toUpperCase();
}

// ---------------------------------------------------------------- cockpit

export const FLAP_MIN: Record<FlapSetting, number> = { 0: 200, 1: 180, 2: 160, 3: 135 };

/** Fuel as "M:SS MIN" with a colour class: red below 5 minutes, amber below 10. */
export function fuelText(fuelMin: number): { text: string; cls: '' | 'amber' | 'red' } {
  const fm = Math.max(0, fuelMin);
  const text = `${Math.floor(fm)}:${String(Math.floor((fm % 1) * 60)).padStart(2, '0')} MIN`;
  return { text, cls: fm < 5 ? 'red' : fm < 10 ? 'amber' : '' };
}

export function baroText(altSetting: number): string {
  return altSetting === 1013 ? '1013 STD' : `${altSetting} hPa`;
}

export function flapsText(flaps: FlapSetting): string {
  return `${flaps} · ${FLAP_MIN[flaps]} kt`;
}

export type Knob = 'hdg' | 'alt' | 'spd' | 'baro';

export const KNOB_LIMITS: Record<Knob, { min: number; max: number; step: number; big: number }> = {
  hdg: { min: 0, max: 359, step: 1, big: 10 },
  alt: { min: 0, max: 20000, step: 100, big: 1000 },
  spd: { min: 140, max: 250, step: 1, big: 10 },
  baro: { min: 950, max: 1050, step: 1, big: 5 },
};

/** The value the panel sends for a raw knob input: headings wrap, the rest clamp (altitude to 100 ft). */
export function clampKnob(k: Knob, raw: number): number {
  const L = KNOB_LIMITS[k];
  let v = Math.round(raw);
  if (k === 'hdg') v = norm360(v);
  else if (k === 'alt') v = Math.max(L.min, Math.min(L.max, Math.round(v / 100) * 100));
  else v = Math.max(L.min, Math.min(L.max, v));
  return v;
}

/** One click/key of a knob from `base` (before clampKnob): ±step, or ±big with Shift; altitude snaps to the step. */
export function nudgeKnob(k: Knob, base: number, dir: number, big: boolean): number {
  const L = KNOB_LIMITS[k];
  const step = big ? L.big : L.step;
  let v = base + dir * step;
  if (k === 'alt') v = Math.round(v / step) * step;
  return v;
}

// ---------------------------------------------------------------- end screen

export function endSummary(r: EndResult, selfId: PlayerId | null): { towerWon: boolean; landed: number; banner: string; sub: string; youWon: boolean } {
  const towerWon = r.winner === 'tower';
  const landed = r.outcomes.filter((o) => o.outcome === 'landed').length;
  return {
    towerWon,
    landed,
    banner: towerWon ? 'THE TOWER WINS' : 'THE IMPOSTOR WINS',
    sub: `${landed} of ${r.outcomes.length} aircraft landed${towerWon ? ' — more than half made it down.' : ' — not more than half made it down.'}  Round time ${mmss(r.durationSec)}.`,
    youWon: (towerWon && selfId !== r.impostorId) || (!towerWon && selfId === r.impostorId),
  };
}
