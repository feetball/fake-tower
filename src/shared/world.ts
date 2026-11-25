// The airport and airspace. Fictional field, real-world procedure design:
// single runway 27 with an ILS, a published platform altitude, MSA sectors,
// terrain, a hold and a missed approach. Sent to every client at round start so
// both the radar scope and the pilot's approach plate are drawn from one source.
//
// Coordinates: x = nm east, y = nm north of the runway 27 threshold.
// Magnetic variation is zero: headings are true.

export interface Fix {
  name: string;
  x: number;
  y: number;
}

export interface TerrainObstacle {
  name: string;
  x: number;
  y: number;
  radiusNm: number;
  /** Top elevation ft MSL. Flying inside the radius below this = crash. */
  elevFt: number;
}

export interface MsaSector {
  /** Sector covers bearings FROM the station in [fromDeg, toDeg), clockwise. */
  fromDeg: number;
  toDeg: number;
  altFt: number;
}

export interface WorldDef {
  icao: string;
  name: string;
  fieldElevFt: number;
  runway: {
    name: string; // "27"
    headingDeg: number; // 270
    lengthNm: number;
    /** Threshold is the world origin. */
  };
  ils: {
    courseDeg: number; // 270: flown westbound, so final approach is east of the field (x > 0, y = 0)
    glideDeg: number; // 3.0
    /** Threshold crossing height ft above field. */
    tchFt: number;
    rangeNm: number; // localizer usable range
    /** Platform altitude at which the approach is normally intercepted. */
    platformAltFt: number;
    /** Final approach fix (glideslope intercept at platform altitude). */
    faf: Fix;
    /** Published minimum: decision altitude ft MSL. */
    daFt: number;
  };
  fixes: Fix[];
  hold: { fix: string; inboundCourseDeg: number; turn: 'R' | 'L'; minAltFt: number };
  missedApproach: string; // plate text
  terrain: TerrainObstacle[];
  msa: MsaSector[];
  transitionAltFt: number;
  /** Radar scope radius nm. Aircraft spawn inside this. */
  scopeRangeNm: number;
  /** Separation minima controllers must keep. */
  separation: { lateralNm: number; verticalFt: number };
}

const GLIDE_DEG = 3.0;
const FIELD_ELEV = 512;
const TCH = 50;
const PLATFORM = 3000;
// Glideslope intercept distance from threshold at the platform altitude.
const FAF_DME =
  (PLATFORM - FIELD_ELEV - TCH) / (Math.tan((GLIDE_DEG * Math.PI) / 180) * 6076.12);

export const WORLD: WorldDef = {
  icao: 'KFTW',
  name: 'Fallow Ridge Regional',
  fieldElevFt: FIELD_ELEV,
  runway: { name: '27', headingDeg: 270, lengthNm: 1.4 },
  ils: {
    courseDeg: 270,
    glideDeg: GLIDE_DEG,
    tchFt: TCH,
    rangeNm: 25,
    platformAltFt: PLATFORM,
    faf: { name: 'FALOW', x: Math.round(FAF_DME * 10) / 10, y: 0 },
    daFt: FIELD_ELEV + 200,
  },
  fixes: [
    { name: 'FALOW', x: Math.round(FAF_DME * 10) / 10, y: 0 }, // FAF
    { name: 'RIDGE', x: 14, y: 0 }, // intermediate fix on the extended centreline
    { name: 'NORBY', x: 16, y: 22 }, // north-east arrival gate
    { name: 'SOLEY', x: 14, y: -24 }, // south-east arrival gate
    { name: 'EASTO', x: 30, y: 2 }, // east arrival gate
    { name: 'WHISK', x: -20, y: 18 }, // north-west arrival gate
    { name: 'HOLDR', x: 20, y: 10 }, // holding fix
  ],
  hold: { fix: 'HOLDR', inboundCourseDeg: 240, turn: 'R', minAltFt: 6000 },
  missedApproach:
    'Climb straight ahead to 3000, then climbing right turn heading 060 to 6000 direct HOLDR and hold.',
  terrain: [
    { name: 'Mt Carrow', x: 9, y: 9, radiusNm: 3.5, elevFt: 4200 },
    { name: 'Saddleback', x: 3, y: -11, radiusNm: 3, elevFt: 3400 },
    { name: 'West Ridge', x: -14, y: -3, radiusNm: 4.5, elevFt: 4900 },
    { name: 'Tower Hill', x: 19, y: -7, radiusNm: 2, elevFt: 2300 },
  ],
  msa: [
    { fromDeg: 0, toDeg: 90, altFt: 5200 },
    { fromDeg: 90, toDeg: 180, altFt: 4400 },
    { fromDeg: 180, toDeg: 270, altFt: 5900 },
    { fromDeg: 270, toDeg: 360, altFt: 5900 },
  ],
  transitionAltFt: 6000,
  scopeRangeNm: 40,
  separation: { lateralNm: 3, verticalFt: 1000 },
};
