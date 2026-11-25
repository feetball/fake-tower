// The tower-wins e2e scenario flies both aircraft with e2e/autopilot.mjs through
// the browser. This runs the very same pilot logic directly against the sim, over
// many seeds and with e2e-like command latency, so the e2e scenario cannot be
// flaky because of the flying (and the approach procedure itself stays landable).

import { describe, expect, it } from 'vitest';
import { ApproachPilot, type PanelDiff, assignSequence, panelDiff } from '../../../e2e/autopilot.mjs';
import { mulberry32 } from './rng';
import { Round } from './round';

/** Decisions every `pollTicks` sim ticks; applied `latencyPolls` polls later (UI + network delay). */
function fly(seed: number, pollTicks: number, latencyPolls: number) {
  const r = new Round(['a', 'b'], { rng: mulberry32(seed) });
  const ids = ['a', 'b'] as const;
  const views = () => ids.map((id) => r.ownView(id)!) as [ReturnType<Round['ownView']> & object, ReturnType<Round['ownView']> & object];
  const roles = assignSequence(views());
  const pilots = roles.map((role) => new ApproachPilot(role, r.qnh));
  const lead = pilots[roles.indexOf('lead')]!;
  const queue: (PanelDiff | null)[][] = [];
  let fail = '';
  let minGapNm = Infinity;
  for (let tick = 0; tick < 40 * 60 * 10 && !r.finished; tick++) {
    if (tick % pollTicks === 0) {
      const vs = views();
      queue.push(
        vs.map((v, i) => {
          const d = pilots[i]!.decide(v, lead.established);
          if (d.fail && !fail) fail = `${pilots[i]!.role}: ${d.fail}`;
          return d.panel ? panelDiff(v, d.panel) : null;
        }),
      );
      if (queue.length > latencyPolls) queue.shift()!.forEach((d, i) => d && r.applyAp(ids[i]!, d));
      const [p, q] = r.aircraft as [(typeof r.aircraft)[0], (typeof r.aircraft)[0]];
      if (p.flying && q.flying && Math.abs(p.alt - q.alt) < 1000) minGapNm = Math.min(minGapNm, Math.hypot(p.x - q.x, p.y - q.y));
    }
    r.step(0.1);
  }
  return { r, fail, minGapNm };
}

describe('e2e scripted approach pilot', () => {
  it('lands both aircraft for every seed, sequenced, with fuel to spare (x20 time scale, 100 ms polls, 2-poll latency)', () => {
    for (let seed = 1; seed <= 60; seed++) {
      const { r, fail, minGapNm } = fly(seed * 104729, 20, 2);
      const why = `seed ${seed * 104729}: ${fail} ${r.aircraft.map((a) => `${a.callsign}=${a.outcome} fuel ${a.fuelMin.toFixed(1)}`).join(', ')}`;
      expect(fail, why).toBe('');
      expect(r.aircraft.map((a) => a.outcome), why).toEqual(['landed', 'landed']);
      expect(Math.min(...r.aircraft.map((a) => a.fuelMin)), why).toBeGreaterThan(1.5);
      expect(minGapNm, why).toBeGreaterThan(0.3); // never close to the 0.15 nm collision radius
      expect(r.time, why).toBeLessThan(25 * 60); // fits the e2e flight timeout at x20
    }
  });
});
