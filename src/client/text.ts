import type { Outcome, RoundEvent } from '../shared/protocol';

export const OUTCOME_TEXT: Record<Outcome, string> = {
  landed: 'Landed safely',
  terrain: 'Controlled flight into terrain',
  collision: 'Mid-air collision',
  fuel: 'Fuel exhaustion — engines flamed out',
  runway: 'Runway accident — unstable landing',
  flying: 'Still airborne when the round ended',
};

export const OUTCOME_SHORT: Record<Outcome, string> = {
  landed: 'LANDED',
  terrain: 'CFIT',
  collision: 'MID-AIR',
  fuel: 'FUEL',
  runway: 'RWY ACCIDENT',
  flying: 'AIRBORNE',
};

export function mmss(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}

export function eventText(e: RoundEvent): string {
  const cs = e.callsigns.join(' and ');
  switch (e.kind) {
    case 'landed':
      return `${cs} landed runway 27`;
    case 'terrain':
      return `${cs} impacted terrain`;
    case 'collision':
      return `MID-AIR COLLISION: ${cs}`;
    case 'fuel':
      return `${cs} ran out of fuel`;
    case 'runway':
      return `${cs} crashed on the runway (unstable approach)`;
    case 'flying':
      return `${cs} still airborne`;
  }
}

/** Phraseology cheat-sheet for controllers (and shown to pilots for readback). */
export const PHRASEOLOGY: { title: string; lines: string[] }[] = [
  {
    title: 'First contact / identification',
    lines: [
      'SKW412, Fallow Approach, radar contact, information Alpha is current, QNH 1003.',
      'SKW412, descend and maintain 6000, QNH 1003, expect ILS approach runway 27.',
    ],
  },
  {
    title: 'Vectors',
    lines: [
      'SKW412, turn left heading 180, descend and maintain 4000, QNH 1003.',
      'SKW412, fly heading 300, vectors ILS runway 27.',
      'SKW412, reduce speed 180 knots.',
    ],
  },
  {
    title: 'Approach clearance',
    lines: [
      'SKW412, 5 miles from FALOW, turn left heading 300, maintain 3000 until established, cleared ILS approach runway 27.',
      'SKW412, cleared ILS approach runway 27.',
      'SKW412, runway 27, wind 250 at 6, cleared to land.',
    ],
  },
  {
    title: 'Holding',
    lines: [
      'SKW412, hold at HOLDR as published, maintain 6000, expect further clearance in 10 minutes.',
    ],
  },
  {
    title: 'Safety',
    lines: [
      'SKW412, go around, climb and maintain 3000, fly heading 060.',
      'SKW412, low altitude alert, check your altitude immediately, QNH 1003. The MSA is 5200.',
      'SKW412, traffic alert, turn right immediately heading 360, climb and maintain 6000.',
    ],
  },
  {
    title: 'Pilot calls',
    lines: [
      'Fallow Approach, SKW412, descending 7000, information Alpha.',
      'Descend and maintain 4000, QNH 1003, left heading 180, SKW412.',
      'SKW412, minimum fuel.',
      'MAYDAY MAYDAY MAYDAY, SKW412, fuel, 3 minutes remaining.',
      'Unable, SKW412 — that is below the MSA.',
    ],
  },
];
