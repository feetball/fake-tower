// How server messages change the client store. Pure state transitions (no DOM,
// socket or audio): main.ts applies the returned effects. Unit-tested.

import type { ServerMsg } from '../shared/protocol';
import { HISTORY, type LogEntry, type State, type View } from './store';
import { eventText } from './text';

/** Side effects main.ts must perform after a transition. */
export type Effect =
  /** The view changed: stop the GPWS siren when leaving the round, switch voice mode. */
  | { k: 'view'; from: View; to: View }
  /** Local PTT was released because we left the round: tell the server and the voice module. */
  | { k: 'pttOff' };

const MAX_LOG = 200;

export function log(s: State, text: string, kind: LogEntry['kind'] = 'info', time: number | null = s.serverTime): void {
  s.log.push({ time, text, kind });
  if (s.log.length > MAX_LOG) s.log.splice(0, s.log.length - MAX_LOG);
}

export function setTime(s: State, t: number, now: number): void {
  if (!Number.isFinite(t)) return;
  s.serverTime = t;
  s.serverTimeAt = now;
}

export function enterView(s: State, v: View, fx: Effect[]): void {
  if (s.view === v) return;
  const from = s.view;
  s.view = v;
  if (v !== 'round' && s.localPtt) {
    s.localPtt = false;
    fx.push({ k: 'pttOff' });
  }
  fx.push({ k: 'view', from, to: v });
}

/** Apply one server message to the store. `now` is performance.now(). */
export function applyServerMsg(s: State, m: ServerMsg, now: number): Effect[] {
  const fx: Effect[] = [];
  switch (m.t) {
    case 'welcome':
      s.selfId = m.id;
      s.protocol = m.protocol;
      break;
    case 'room': {
      const prevPhase = s.room?.phase;
      s.room = m.room;
      if (m.room.phase === 'lobby') {
        if (s.view !== 'lobby') {
          if (prevPhase && prevPhase !== 'lobby') {
            s.lastRoundPlayers = s.round?.players ?? s.lastRoundPlayers;
          }
          s.round = null;
          s.own = null;
          s.radar = null;
          s.end = null;
          s.radio = [];
          s.selected = null;
        }
        enterView(s, 'lobby', fx);
      } else if (m.room.phase === 'playing') {
        if (s.view === 'menu' || s.view === 'lobby' || s.view === 'end') enterView(s, s.round && !s.end ? 'round' : 'waiting', fx);
      } else if (m.room.phase === 'ended') {
        if (s.end) enterView(s, 'end', fx);
        else if (s.view === 'menu' || s.view === 'lobby') enterView(s, 'waiting', fx);
      }
      break;
    }
    case 'begin':
      s.round = { you: m.you, players: m.players, world: m.world, atis: m.atis, beganAt: now };
      s.own = null;
      s.radar = null;
      s.events = [];
      s.log = [];
      s.end = null;
      s.selected = null;
      s.radio = [];
      s.scratch = {};
      setTime(s, 0, now);
      log(s, `Round started. ATIS information ${m.atis.letter}, QNH ${m.atis.qnh}, runway ${m.atis.runway}.`, 'info', 0);
      if (m.you.role === 'controller') {
        log(s, m.you.impostor ? 'You are the IMPOSTOR controller.' : 'You are the REAL controller.', m.you.impostor ? 'bad' : 'good', 0);
      }
      enterView(s, 'round', fx);
      break;
    case 'own':
      s.own = { time: m.time, ac: m.ac, receivedAt: now };
      setTime(s, m.time, now);
      break;
    case 'radar': {
      const prev = s.radar;
      const history = prev?.history ?? new Map<string, { x: number; y: number }[]>();
      const seen = new Set<string>();
      for (const t of m.targets) {
        seen.add(t.callsign);
        const old = prev?.targets.find((p) => p.callsign === t.callsign);
        const hist = history.get(t.callsign) ?? [];
        if (old && (old.x !== t.x || old.y !== t.y)) {
          hist.push({ x: old.x, y: old.y });
          while (hist.length > HISTORY) hist.shift();
        }
        history.set(t.callsign, hist);
        // alert transitions into the log
        if (t.conflict && !old?.conflict) log(s, `CONFLICT ALERT ${t.callsign}`, 'bad', m.time);
        if (t.msaw && !old?.msaw) log(s, `LOW ALTITUDE ALERT ${t.callsign} ${Math.round(t.alt)} ft`, 'bad', m.time);
      }
      for (const k of [...history.keys()]) if (!seen.has(k)) history.delete(k);
      s.radar = { time: m.time, targets: m.targets, history, receivedAt: now };
      setTime(s, m.time, now);
      break;
    }
    case 'radio':
      s.radio = [...m.tx];
      break;
    case 'event':
      s.events.push(m.event);
      s.events.sort((a, b) => a.time - b.time);
      log(s, eventText(m.event), m.event.kind === 'landed' ? 'good' : 'bad', m.event.time);
      break;
    case 'end':
      s.end = m.result;
      if (s.round) s.lastRoundPlayers = s.round.players;
      enterView(s, 'end', fx);
      break;
    case 'rtc':
    case 'error':
      break;
  }
  return fx;
}
