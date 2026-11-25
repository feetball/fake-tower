// The one client-side store. Every server message lands here; views read from
// it. The object identity never changes (window.__ft.state is a live reference).

import type {
  Atis,
  EndResult,
  OwnAircraft,
  PlayerId,
  RadarTarget,
  RoomState,
  Role,
  RoundEvent,
  RoundPlayer,
} from '../shared/protocol';
import type { WorldDef } from '../shared/world';

export type ConnState = 'connecting' | 'open' | 'closed';
export type View = 'menu' | 'lobby' | 'round' | 'waiting' | 'end';

export interface RoundInfo {
  you: { role: Role; impostor: boolean; callsign?: string };
  players: RoundPlayer[];
  world: WorldDef;
  atis: Atis;
  /** performance.now() at begin, for a local clock until server time arrives. */
  beganAt: number;
}

export interface RadarState {
  time: number;
  targets: RadarTarget[];
  /** Per callsign, positions of previous sweeps, oldest first (max HISTORY). */
  history: Map<string, { x: number; y: number }[]>;
  receivedAt: number;
}

export interface LogEntry {
  time: number | null;
  text: string;
  kind: 'info' | 'good' | 'bad';
}

export interface State {
  conn: ConnState;
  closeReason: string;
  selfId: PlayerId | null;
  protocol: number | null;
  name: string;
  view: View;
  room: RoomState | null;
  round: RoundInfo | null;
  own: { time: number; ac: OwnAircraft; receivedAt: number } | null;
  radar: RadarState | null;
  radio: PlayerId[];
  events: RoundEvent[];
  log: LogEntry[];
  end: EndResult | null;
  /** Players of the round that just ended (kept for the end screen names). */
  lastRoundPlayers: RoundPlayer[];
  localPtt: boolean;
  mic: { ok: boolean; connected: PlayerId[]; initDone: boolean };
  volume: number;
  /** Controller scratchpads, per callsign, local only. */
  scratch: Record<string, string>;
  selected: string | null;
  /** Last server round time we saw (own/radar/event). */
  serverTime: number;
}

export const HISTORY = 5;

export const state: State = {
  conn: 'connecting',
  closeReason: '',
  selfId: null,
  protocol: null,
  name: '',
  view: 'menu',
  room: null,
  round: null,
  own: null,
  radar: null,
  radio: [],
  events: [],
  log: [],
  end: null,
  lastRoundPlayers: [],
  localPtt: false,
  mic: { ok: false, connected: [], initDone: false },
  volume: 0.8,
  scratch: {},
  selected: null,
  serverTime: 0,
};

type Listener = (s: State) => void;
const listeners = new Set<Listener>();
let scheduled = false;

export function subscribe(fn: Listener): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

/** Mutate the store, then notify subscribers (batched per microtask). */
export function update(fn: (s: State) => void): void {
  fn(state);
  if (scheduled) return;
  scheduled = true;
  queueMicrotask(() => {
    scheduled = false;
    for (const l of listeners) {
      try {
        l(state);
      } catch (e) {
        console.error(e);
      }
    }
  });
}

export function playerName(id: PlayerId): string {
  const rp =
    state.round?.players.find((p) => p.id === id) ?? state.lastRoundPlayers.find((p) => p.id === id);
  if (rp) return rp.name;
  return state.room?.players.find((p) => p.id === id)?.name ?? id.slice(0, 6);
}

export function roundPlayer(id: PlayerId): RoundPlayer | undefined {
  return state.round?.players.find((p) => p.id === id);
}

export function isHost(): boolean {
  return !!state.room?.players.find((p) => p.id === state.selfId)?.host;
}
