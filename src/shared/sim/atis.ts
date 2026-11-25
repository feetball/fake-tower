import type { Atis } from '../protocol';
import type { WorldDef } from '../world';
import { type Rng, randInt } from './rng';

const PHONETIC = [
  'ALFA', 'BRAVO', 'CHARLIE', 'DELTA', 'ECHO', 'FOXTROT', 'GOLF', 'HOTEL', 'INDIA', 'JULIETT', 'KILO', 'LIMA', 'MIKE',
  'NOVEMBER', 'OSCAR', 'PAPA', 'QUEBEC', 'ROMEO', 'SIERRA', 'TANGO', 'UNIFORM', 'VICTOR', 'WHISKEY', 'XRAY', 'YANKEE', 'ZULU',
];

/** True QNH for a round: never within 4 hPa of standard, so a wrong setting is a real hazard (≥ 108 ft). */
export function randomQnh(rng: Rng): number {
  for (;;) {
    const q = randInt(rng, 996, 1030);
    if (Math.abs(q - 1013) >= 4) return q;
  }
}

const pad3 = (n: number) => String(n).padStart(3, '0');

/** Fog over the field: CAT I conditions, light wind roughly down the runway. */
export function makeAtis(world: WorldDef, qnh: number, rng: Rng): Atis {
  const idx = randInt(rng, 0, 25);
  const letter = String.fromCharCode(65 + idx);
  const word = PHONETIC[idx] ?? 'ALFA';
  const windDir = (Math.round((world.runway.headingDeg + randInt(rng, -40, 40)) / 10) * 10 + 360) % 360 || 360;
  const windKt = randInt(rng, 3, 9);
  const visibilityM = randInt(rng, 6, 12) * 100;
  const ceilingFt = randInt(rng, 2, 4) * 100;
  const temp = randInt(rng, 2, 9);
  const time = `${String(randInt(rng, 0, 23)).padStart(2, '0')}${String(randInt(rng, 0, 5) * 10 + 0).padStart(2, '0')}`;
  const text = [
    `${world.name.toUpperCase()} INFORMATION ${word}, TIME ${time} ZULU.`,
    `EXPECT ILS APPROACH RUNWAY ${world.runway.name}. RUNWAY IN USE ${world.runway.name}.`,
    `WIND ${pad3(windDir)} DEGREES ${windKt} KNOTS.`,
    `VISIBILITY ${visibilityM} METRES, FOG. OVERCAST ${ceilingFt} FEET.`,
    `TEMPERATURE ${temp}, DEW POINT ${temp}.`,
    `QNH ${qnh}.`,
    `TRANSITION ALTITUDE ${world.transitionAltFt}.`,
    `ACKNOWLEDGE RECEIPT OF INFORMATION ${word} AND ADVISE AIRCRAFT TYPE ON FIRST CONTACT.`,
  ].join(' ');
  return { letter, runway: world.runway.name, qnh, windDir, windKt, visibilityM, ceilingFt, text };
}
