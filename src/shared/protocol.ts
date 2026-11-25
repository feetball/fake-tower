// Wire protocol between client and server. This file is the contract: server,
// client and voice code are written against it independently.
//
// Units everywhere: distance nm, altitude ft MSL, speed kt, heading degrees
// (0-359, 360 shown as 360 in UI), time seconds, pressure hPa.
// World coordinates: x = nm east, y = nm north of the runway 27 threshold.

import type { WorldDef } from './world';

export const PROTOCOL_VERSION = 1;
export const MIN_PLAYERS = 4; // 2 controllers + at least 2 pilots
export const MAX_PLAYERS = 8;

export type PlayerId = string;
export type Phase = 'lobby' | 'playing' | 'ended';
export type Role = 'controller' | 'pilot';

export interface LobbyPlayer {
  id: PlayerId;
  name: string;
  host: boolean;
  connected: boolean;
}

export interface RoomState {
  code: string; // 4 uppercase letters
  phase: Phase;
  players: LobbyPlayer[];
}

/** Public info about a player once a round starts. Never reveals the impostor. */
export interface RoundPlayer {
  id: PlayerId;
  name: string;
  role: Role;
  /** Pilots only, e.g. "SKW412". */
  callsign?: string;
}

export interface Atis {
  letter: string; // "A".."Z" information identifier
  runway: string; // "27"
  qnh: number; // true QNH, hPa
  windDir: number;
  windKt: number;
  visibilityM: number;
  ceilingFt: number;
  /** Full ATIS text, real phraseology, ready to display. */
  text: string;
}

export type FlapSetting = 0 | 1 | 2 | 3; // 0 up, 3 = landing
export type ApMode = 'HDG' | 'LOC' | 'APP'; // lateral/approach state actually engaged
export type AircraftStatus = 'flying' | 'landed' | 'crashed';
export type Outcome =
  | 'landed'
  | 'terrain' // controlled flight into terrain or ground away from runway
  | 'collision' // mid-air
  | 'fuel' // fuel exhaustion
  | 'runway' // unstable landing: gear up, too fast, not on the ILS
  | 'flying'; // still airborne when the round ended

/** Full state of the pilot's own aircraft. Sent only to that pilot. */
export interface OwnAircraft {
  callsign: string;
  status: AircraftStatus;
  outcome?: Outcome;
  // --- instruments ---
  hdg: number;
  ias: number;
  /** Indicated altitude: depends on the pilot's altimeter setting. */
  indAlt: number;
  /** Radio altimeter, ft above terrain, only valid (non-null) below 2500 ft AGL. */
  radAlt: number | null;
  vs: number; // ft/min
  fuelMin: number; // minutes of fuel remaining
  // --- navaids: DME and bearing to the field VOR/DME (at the threshold) ---
  dme: number; // nm
  bearingToStation: number; // degrees, the course to fly direct to the station
  /** ILS deviation in dots, -2.5..2.5, null when out of range / no signal. Positive loc = fly right; positive gs = fly up. */
  locDev: number | null;
  gsDev: number | null;
  // --- autopilot / configuration ---
  selHdg: number;
  selAlt: number;
  selSpd: number;
  appArmed: boolean;
  apMode: ApMode;
  gsCaptured: boolean;
  gearDown: boolean;
  flaps: FlapSetting;
  altSetting: number; // hPa set on the altimeter
  /** GPWS / master warnings currently active, e.g. "TERRAIN", "PULL UP", "LOW FUEL", "TOO LOW GEAR". */
  warnings: string[];
}

/** What a controller sees for each aircraft on the scope. */
export interface RadarTarget {
  callsign: string;
  x: number;
  y: number;
  /** Mode C altitude in ft (pressure altitude corrected to QNH = true altitude). */
  alt: number;
  gs: number; // ground speed kt
  track: number; // degrees
  vsTrend: -1 | 0 | 1; // descending / level / climbing
  status: AircraftStatus;
  /** Short-term conflict alert: this target is in loss of separation with another. */
  conflict: boolean;
  /** Minimum safe altitude warning: below the MSA for its position. */
  msaw: boolean;
}

export interface RoundEvent {
  time: number; // seconds since round start
  kind: Outcome;
  callsigns: string[];
}

export interface EndResult {
  winner: 'tower' | 'impostor';
  realControllerId: PlayerId;
  impostorId: PlayerId;
  outcomes: { callsign: string; playerId: PlayerId; outcome: Outcome }[];
  durationSec: number;
}

// ---------------------------------------------------------------- client -> server

export type ClientMsg =
  | { t: 'create'; name: string }
  | { t: 'join'; code: string; name: string }
  | { t: 'start' } // host only, from lobby
  | { t: 'lobby' } // host only, from ended: return everyone to the lobby
  | {
      // pilot only: change autopilot targets / configuration. Omitted fields are unchanged.
      t: 'ap';
      hdg?: number;
      alt?: number;
      spd?: number;
      app?: boolean; // arm / disarm approach mode
      gear?: boolean;
      flaps?: FlapSetting;
      altSetting?: number;
    }
  | { t: 'ptt'; on: boolean }
  | { t: 'rtc'; to: PlayerId; data: unknown }; // WebRTC signalling relay

// ---------------------------------------------------------------- server -> client

export type ServerMsg =
  | { t: 'welcome'; id: PlayerId; protocol: number }
  | { t: 'room'; room: RoomState }
  | {
      t: 'begin';
      you: {
        role: Role;
        /** True only for the impostor controller. The real controller gets false and can infer the other controller is fake. */
        impostor: boolean;
        callsign?: string;
      };
      players: RoundPlayer[];
      world: WorldDef;
      atis: Atis;
    }
  | { t: 'own'; time: number; ac: OwnAircraft } // pilots, 10 Hz
  | { t: 'radar'; time: number; targets: RadarTarget[] } // controllers, one sweep every RADAR_SWEEP_SEC
  | { t: 'radio'; tx: PlayerId[] } // who is keying the frequency right now; 2+ = blocked
  | { t: 'event'; event: RoundEvent } // everyone
  | { t: 'end'; result: EndResult }
  | { t: 'rtc'; from: PlayerId; data: unknown }
  | { t: 'error'; msg: string };

export const TICK_HZ = 10;
export const RADAR_SWEEP_SEC = 2;
export const WS_PATH = '/ws';
export const SERVER_PORT = 8080;
