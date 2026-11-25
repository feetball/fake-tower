import { describe, expect, it } from 'vitest';
import type { EndResult, Outcome, RadarTarget } from '../shared/protocol';
import {
  FLAP_MIN,
  KNOB_LIMITS,
  alertTag,
  baroText,
  clampKnob,
  dataBlock,
  endSummary,
  flapsText,
  fuelText,
  nudgeKnob,
  stripAltText,
  stripStatus,
  trafficAltText,
  trendArrow,
} from './format';

function tgt(over: Partial<RadarTarget> = {}): RadarTarget {
  return { callsign: 'SKW412', x: 10, y: 5, alt: 5200, gs: 250, track: 270, vsTrend: 0, status: 'flying', conflict: false, msaw: false, ...over };
}

describe('scope data block', () => {
  it('callsign, altitude in hundreds with trend, ground speed in tens', () => {
    expect(dataBlock(tgt(), undefined)).toEqual({ alert: null, lines: ['SKW412', '052  25'] });
    expect(dataBlock(tgt({ alt: 12340, gs: 186, vsTrend: 1 }), '').lines[1]).toBe('123↑ 19');
    expect(dataBlock(tgt({ alt: 49, gs: 4, vsTrend: -1 }), '').lines[1]).toBe('000↓ 00');
    // negative values never produce "-1"
    expect(dataBlock(tgt({ alt: -300, gs: -10 }), '').lines[1]).toBe('000  00');
  });

  it('alert line first: conflict beats MSAW', () => {
    expect(dataBlock(tgt({ msaw: true }), '').lines).toEqual(['LA', 'SKW412', '052  25']);
    expect(dataBlock(tgt({ msaw: true, conflict: true }), '')).toMatchObject({ alert: 'CA', lines: ['CA', 'SKW412', '052  25'] });
  });

  it('scratchpad: trimmed, upper-case, first 7 characters, omitted when blank', () => {
    expect(dataBlock(tgt(), '  ils27 cleared ').lines.at(-1)).toBe('ILS27 C');
    expect(dataBlock(tgt(), '   ').lines).toHaveLength(2);
  });

  it('alert tag and trend helpers', () => {
    expect(alertTag({ conflict: false, msaw: false })).toBeNull();
    expect(alertTag({ conflict: false, msaw: true })).toBe('LA');
    expect(alertTag({ conflict: true, msaw: true })).toBe('CA');
    expect([trendArrow(1), trendArrow(0), trendArrow(-1)]).toEqual(['↑', ' ', '↓']);
  });

  it('flight strip and traffic list cells', () => {
    expect(stripAltText(tgt({ alt: 3000.4, vsTrend: 0 }))).toBe('3000 ft =');
    expect(stripAltText(tgt({ vsTrend: -1 }))).toBe('5200 ft ↓');
    expect(stripStatus(tgt())).toEqual({ text: '', cls: 'strip-status flying' });
    expect(stripStatus(tgt({ msaw: true }))).toEqual({ text: 'LA', cls: 'strip-status la' });
    expect(stripStatus(tgt({ msaw: true, conflict: true }))).toEqual({ text: 'CA', cls: 'strip-status ca' });
    expect(stripStatus(tgt({ status: 'crashed' }))).toEqual({ text: 'CRASHED', cls: 'strip-status crashed' });
    expect(stripStatus(tgt({ status: 'landed' })).text).toBe('LANDED');
    expect(trafficAltText(tgt({ alt: 3000 }))).toBe('030');
    expect(trafficAltText(tgt({ status: 'landed' }))).toBe('LANDED');
  });
});

describe('cockpit readouts', () => {
  it('fuel as M:SS with red < 5 min and amber < 10 min', () => {
    expect(fuelText(12.5)).toEqual({ text: '12:30 MIN', cls: '' });
    expect(fuelText(10)).toEqual({ text: '10:00 MIN', cls: '' });
    expect(fuelText(9.99)).toEqual({ text: '9:59 MIN', cls: 'amber' });
    expect(fuelText(5)).toEqual({ text: '5:00 MIN', cls: 'amber' });
    expect(fuelText(4.95)).toEqual({ text: '4:57 MIN', cls: 'red' });
    expect(fuelText(0)).toEqual({ text: '0:00 MIN', cls: 'red' });
    expect(fuelText(-3)).toEqual({ text: '0:00 MIN', cls: 'red' });
  });

  it('altimeter, flaps', () => {
    expect(baroText(1013)).toBe('1013 STD');
    expect(baroText(998)).toBe('998 hPa');
    expect(flapsText(0)).toBe('0 · 200 kt');
    expect(flapsText(3)).toBe('3 · 135 kt');
    // the cockpit's flap minimums must match the sim (DESIGN.md: clean 200, F1 180, F2 160, F3 135)
    expect(FLAP_MIN).toEqual({ 0: 200, 1: 180, 2: 160, 3: 135 });
  });

  it('knob inputs clamp like the panel', () => {
    expect(clampKnob('hdg', 360)).toBe(0);
    expect(clampKnob('hdg', -10)).toBe(350);
    expect(clampKnob('hdg', 725.4)).toBe(5);
    expect(clampKnob('hdg', 359.6)).toBe(0);
    expect(clampKnob('alt', 3049)).toBe(3000);
    expect(clampKnob('alt', 3050)).toBe(3100);
    expect(clampKnob('alt', -500)).toBe(0);
    expect(clampKnob('alt', 99999)).toBe(20000);
    expect(clampKnob('spd', 90)).toBe(KNOB_LIMITS.spd.min);
    expect(clampKnob('spd', 300)).toBe(250);
    expect(clampKnob('spd', 180.6)).toBe(181);
    expect(clampKnob('baro', 900)).toBe(950);
    expect(clampKnob('baro', 1100)).toBe(1050);
    expect(clampKnob('baro', 1003.4)).toBe(1003);
  });

  it('knob nudges: step / big step, altitude snapped to the step', () => {
    expect(nudgeKnob('hdg', 359, 1, false)).toBe(360);
    expect(clampKnob('hdg', nudgeKnob('hdg', 359, 1, false))).toBe(0);
    expect(clampKnob('hdg', nudgeKnob('hdg', 5, -1, true))).toBe(355);
    expect(nudgeKnob('alt', 3000, 1, false)).toBe(3100);
    expect(nudgeKnob('alt', 3050, -1, true)).toBe(2000); // 2050 snapped to the 1000 step
    expect(nudgeKnob('spd', 180, -1, true)).toBe(170);
    expect(nudgeKnob('baro', 1013, 1, true)).toBe(1018);
  });
});

describe('end screen summary', () => {
  const result = (winner: 'tower' | 'impostor', outcomes: Outcome[]): EndResult => ({
    winner,
    realControllerId: 'rc',
    impostorId: 'imp',
    outcomes: outcomes.map((o, i) => ({ callsign: `C${i}`, playerId: `p${i}`, outcome: o })),
    durationSec: 754,
  });

  it('tower win: banner, count, round time, who won', () => {
    const r = result('tower', ['landed', 'landed', 'fuel']);
    const s = endSummary(r, 'p0');
    expect(s).toMatchObject({ towerWon: true, landed: 2, banner: 'THE TOWER WINS', youWon: true });
    expect(s.sub).toBe('2 of 3 aircraft landed — more than half made it down.  Round time 12:34.');
    expect(endSummary(r, 'rc').youWon).toBe(true);
    expect(endSummary(r, 'imp').youWon).toBe(false);
  });

  it('impostor win', () => {
    const r = result('impostor', ['landed', 'collision']);
    const s = endSummary(r, 'imp');
    expect(s).toMatchObject({ towerWon: false, landed: 1, banner: 'THE IMPOSTOR WINS', youWon: true });
    expect(s.sub).toMatch(/^1 of 2 aircraft landed — not more than half/);
    expect(endSummary(r, 'p0').youWon).toBe(false);
    expect(endSummary(r, null).youWon).toBe(false);
  });
});
