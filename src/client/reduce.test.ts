import { afterEach, describe, expect, it, vi } from 'vitest';
import type { EndResult, OwnAircraft, RadarTarget, RoomState, RoundPlayer, ServerMsg } from '../shared/protocol';
import { WORLD } from '../shared/world';
import { applyServerMsg, log } from './reduce';
import { radioLabel } from './roundbar';
import { HISTORY, createState, isHost, playerName, roundTime, state, subscribe, update, type State } from './store';

const room = (phase: RoomState['phase'], ids = ['me', 'p2', 'p3', 'p4']): RoomState => ({
  code: 'ABCD',
  phase,
  players: ids.map((id, i) => ({ id, name: `N-${id}`, host: i === 0, connected: true })),
});

const PLAYERS: RoundPlayer[] = [
  { id: 'me', name: 'Me', role: 'pilot', callsign: 'SKW1' },
  { id: 'p2', name: 'Two', role: 'controller' },
  { id: 'p3', name: 'Three', role: 'controller' },
  { id: 'p4', name: 'Four', role: 'pilot', callsign: 'DAL2' },
];
const ATIS = { letter: 'C', runway: '27', qnh: 1003, windDir: 250, windKt: 5, visibilityM: 800, ceilingFt: 200, text: 'x' };

function begin(role: 'pilot' | 'controller' = 'pilot', impostor = false): ServerMsg {
  return { t: 'begin', you: { role, impostor, ...(role === 'pilot' ? { callsign: 'SKW1' } : {}) }, players: PLAYERS, world: WORLD, atis: ATIS };
}

function target(over: Partial<RadarTarget> = {}): RadarTarget {
  return { callsign: 'SKW1', x: 20, y: 5, alt: 6000, gs: 250, track: 270, vsTrend: 0, status: 'flying', conflict: false, msaw: false, ...over };
}

const own = (ac: Partial<OwnAircraft> = {}): ServerMsg => ({ t: 'own', time: 12.3, ac: { callsign: 'SKW1', status: 'flying', ...ac } as OwnAircraft });

const END: EndResult = { winner: 'tower', realControllerId: 'p2', impostorId: 'p3', outcomes: [], durationSec: 100 };

/** Run a sequence of messages through a fresh state; returns state and all effects. */
function play(msgs: ServerMsg[], s: State = createState()) {
  const fx = msgs.flatMap((m, i) => applyServerMsg(s, m, 1000 + i));
  return { s, fx };
}

afterEach(() => {
  Object.assign(state, createState());
});

describe('client store: server message reducer', () => {
  it('welcome and lobby join', () => {
    const { s, fx } = play([{ t: 'welcome', id: 'me', protocol: 1 }, { t: 'room', room: room('lobby') }]);
    expect(s).toMatchObject({ selfId: 'me', protocol: 1, view: 'lobby' });
    expect(s.room?.code).toBe('ABCD');
    expect(fx).toEqual([{ k: 'view', from: 'menu', to: 'lobby' }]);
  });

  it('begin resets round state, logs the ATIS and enters the round', () => {
    const s = createState();
    s.events = [{ time: 1, kind: 'terrain', callsigns: ['OLD'] }];
    s.scratch = { OLD: 'x' };
    s.end = END;
    s.radio = ['p2'];
    const { fx } = play([{ t: 'room', room: room('lobby') }, { t: 'room', room: room('playing') }, begin('controller', true)], s);
    expect(s.view).toBe('round');
    expect(s.round?.you).toEqual({ role: 'controller', impostor: true });
    expect(s.round?.beganAt).toBe(1002);
    expect(s).toMatchObject({ events: [], scratch: {}, end: null, radio: [], own: null, radar: null, serverTime: 0, serverTimeAt: 1002 });
    expect(s.log.map((l) => l.text)).toEqual(['Round started. ATIS information C, QNH 1003, runway 27.', 'You are the IMPOSTOR controller.']);
    expect(s.log.map((l) => l.kind)).toEqual(['info', 'bad']);
    // 'playing' room before begin: a waiting view until round data arrives
    expect(fx.map((f) => f.k === 'view' && f.to)).toEqual(['lobby', 'waiting', 'round']);
  });

  it('real controller and pilot begin logs', () => {
    expect(play([begin('controller', false)]).s.log.at(-1)).toMatchObject({ text: 'You are the REAL controller.', kind: 'good' });
    expect(play([begin('pilot')]).s.log).toHaveLength(1);
  });

  it('own updates the aircraft and the round clock', () => {
    const { s } = play([begin(), own({ hdg: 90 })]);
    expect(s.own).toMatchObject({ time: 12.3, receivedAt: 1001, ac: { hdg: 90 } });
    expect(s.serverTime).toBe(12.3);
    // non-finite times never move the clock
    applyServerMsg(s, { t: 'own', time: Number.NaN, ac: s.own!.ac }, 5000);
    expect(s.serverTime).toBe(12.3);
    expect(s.serverTimeAt).toBe(1001);
  });

  it('radar: history trail of previous sweeps, capped, dropped with the target', () => {
    const s = createState();
    applyServerMsg(s, begin('controller'), 0);
    for (let i = 0; i < HISTORY + 3; i++) {
      applyServerMsg(s, { t: 'radar', time: 2 * i, targets: [target({ x: 20 - i }), target({ callsign: 'DAL2', x: 30, y: 0 })] }, i);
    }
    expect(s.radar?.history.get('SKW1')).toHaveLength(HISTORY);
    expect(s.radar?.history.get('SKW1')?.at(-1)).toEqual({ x: 20 - (HISTORY + 1), y: 5 });
    expect(s.radar?.history.get('DAL2')).toEqual([]); // did not move: no trail dots
    applyServerMsg(s, { t: 'radar', time: 100, targets: [target()] }, 99);
    expect([...s.radar!.history.keys()]).toEqual(['SKW1']);
    expect(s.serverTime).toBe(100);
  });

  it('radar: conflict / low-altitude alerts are logged on onset only', () => {
    const { s } = play([
      begin('controller'),
      { t: 'radar', time: 2, targets: [target()] },
      { t: 'radar', time: 4, targets: [target({ msaw: true, alt: 3012 })] },
      { t: 'radar', time: 6, targets: [target({ msaw: true, conflict: true })] },
      { t: 'radar', time: 8, targets: [target({ msaw: true, conflict: true })] },
      { t: 'radar', time: 10, targets: [target()] },
      { t: 'radar', time: 12, targets: [target({ conflict: true })] },
    ]);
    expect(s.log.slice(2).map((l) => `${l.time} ${l.text}`)).toEqual([
      '4 LOW ALTITUDE ALERT SKW1 3012 ft',
      '6 CONFLICT ALERT SKW1',
      '12 CONFLICT ALERT SKW1',
    ]);
  });

  it('events are kept in time order and logged', () => {
    const { s } = play([
      begin(),
      { t: 'event', event: { time: 30, kind: 'terrain', callsigns: ['DAL2'] } },
      { t: 'event', event: { time: 20, kind: 'landed', callsigns: ['SKW1'] } },
    ]);
    expect(s.events.map((e) => e.time)).toEqual([20, 30]);
    expect(s.log.slice(1).map((l) => [l.kind, l.text])).toEqual([
      ['bad', 'DAL2 impacted terrain'],
      ['good', 'SKW1 landed runway 27'],
    ]);
  });

  it('radio copies the transmitter list', () => {
    const tx = ['p2', 'p3'];
    const { s } = play([{ t: 'radio', tx }]);
    expect(s.radio).toEqual(tx);
    expect(s.radio).not.toBe(tx);
  });

  it('end: shows the end screen, keeps the round players, drops local PTT', () => {
    const s = createState();
    play([begin()], s);
    s.localPtt = true;
    const { fx } = play([{ t: 'end', result: END }, { t: 'room', room: room('ended') }], s);
    expect(s.view).toBe('end');
    expect(s.localPtt).toBe(false);
    expect(s.lastRoundPlayers).toBe(PLAYERS);
    expect(fx).toEqual([{ k: 'pttOff' }, { k: 'view', from: 'round', to: 'end' }]);
  });

  it('back to the lobby clears the round but remembers its players', () => {
    const s = createState();
    play([{ t: 'room', room: room('lobby') }, { t: 'room', room: room('playing') }, begin(), own(), { t: 'radio', tx: ['p2'] }, { t: 'end', result: END }, { t: 'room', room: room('ended') }], s);
    s.selected = 'SKW1';
    const { fx } = play([{ t: 'room', room: room('lobby') }], s);
    expect(s).toMatchObject({ view: 'lobby', round: null, own: null, radar: null, end: null, radio: [], selected: null });
    expect(s.lastRoundPlayers).toBe(PLAYERS);
    expect(fx).toEqual([{ k: 'view', from: 'end', to: 'lobby' }]);
  });

  it('joining while a round is running or has ended waits', () => {
    expect(play([{ t: 'room', room: room('playing') }]).s.view).toBe('waiting');
    expect(play([{ t: 'room', room: room('ended') }]).s.view).toBe('waiting');
    // a waiting client that then sees 'ended' without an end result stays waiting
    expect(play([{ t: 'room', room: room('playing') }, { t: 'room', room: room('ended') }]).s.view).toBe('waiting');
  });

  it('room updates mid-round do not leave the round', () => {
    const { s, fx } = play([begin(), { t: 'room', room: room('playing') }]);
    expect(s.view).toBe('round');
    expect(fx).toEqual([{ k: 'view', from: 'menu', to: 'round' }]);
  });

  it('rtc and error messages do not touch state', () => {
    const s = createState();
    const before = JSON.stringify(s);
    play([{ t: 'rtc', from: 'p2', data: {} }, { t: 'error', msg: 'nope' }], s);
    expect(JSON.stringify(s)).toBe(before);
  });

  it('log is capped at 200 lines', () => {
    const s = createState();
    for (let i = 0; i < 250; i++) log(s, `l${i}`);
    expect(s.log).toHaveLength(200);
    expect(s.log[0]!.text).toBe('l50');
    expect(s.log[0]!.time).toBe(0);
  });
});

describe('client store helpers', () => {
  it('playerName: round players, then last round, then room, then a short id', () => {
    state.room = room('lobby', ['me', 'zz']);
    state.lastRoundPlayers = [{ id: 'old', name: 'Old', role: 'pilot' }];
    expect(playerName('zz')).toBe('N-zz');
    expect(playerName('old')).toBe('Old');
    expect(playerName('unknown-player-id')).toBe('unknow');
    state.round = { you: { role: 'pilot', impostor: false }, players: PLAYERS, world: WORLD, atis: ATIS, beganAt: 0 };
    expect(playerName('p2')).toBe('Two');
    expect(playerName('')).toBe('');
  });

  it('isHost', () => {
    expect(isHost()).toBe(false);
    state.room = room('lobby');
    state.selfId = 'p2';
    expect(isHost()).toBe(false);
    state.selfId = 'me';
    expect(isHost()).toBe(true);
  });

  it('roundTime advances locally between updates, at most 3 s, only in the round', () => {
    vi.spyOn(performance, 'now').mockReturnValue(10_000);
    state.serverTime = 40;
    state.serverTimeAt = 9_000;
    expect(roundTime()).toBe(40); // not in the round view
    state.view = 'round';
    expect(roundTime()).toBe(41);
    state.serverTimeAt = 1_000;
    expect(roundTime()).toBe(43);
    state.serverTimeAt = 0;
    expect(roundTime()).toBe(40);
    vi.restoreAllMocks();
  });

  it('update mutates synchronously and notifies once per microtask; a throwing listener does not stop others', async () => {
    const err = vi.spyOn(console, 'error').mockImplementation(() => {});
    const seen: number[] = [];
    const un1 = subscribe(() => {
      throw new Error('boom');
    });
    const un2 = subscribe((s) => seen.push(s.volume));
    update((s) => (s.volume = 0.1));
    update((s) => (s.volume = 0.2));
    expect(state.volume).toBe(0.2);
    expect(seen).toEqual([]);
    await Promise.resolve();
    expect(seen).toEqual([0.2]);
    expect(err).toHaveBeenCalledTimes(1);
    un1();
    un2();
    update((s) => (s.volume = 0.3));
    await Promise.resolve();
    expect(seen).toEqual([0.2]);
    err.mockRestore();
  });
});

describe('radio indicator', () => {
  function setup() {
    state.selfId = 'me';
    state.room = room('playing', ['me', 'p2', 'p3', 'p4', 'p5']);
    state.round = { you: { role: 'pilot', impostor: false, callsign: 'SKW1' }, players: PLAYERS, world: WORLD, atis: ATIS, beganAt: 0 };
  }

  it('idle, TX, RX with callsign / controller tag, BLOCKED', () => {
    setup();
    expect(radioLabel(state)).toEqual({ text: 'IDLE', cls: 'idle' });
    state.radio = ['me'];
    expect(radioLabel(state)).toEqual({ text: 'TX', cls: 'tx' });
    state.radio = ['p4'];
    expect(radioLabel(state)).toEqual({ text: 'RX DAL2 · Four', cls: 'rx' });
    state.radio = ['p2'];
    expect(radioLabel(state)).toEqual({ text: 'RX Two · CTL', cls: 'rx' });
    state.radio = ['p5']; // not in the round (only in the room list)
    expect(radioLabel(state)).toEqual({ text: 'RX N-p5', cls: 'rx' });
    state.radio = ['ghost'];
    expect(radioLabel(state)).toEqual({ text: 'RX ?', cls: 'rx' });
    state.radio = ['me', 'p2'];
    expect(radioLabel(state)).toEqual({ text: 'BLOCKED', cls: 'blocked' });
    state.radio = ['p2', 'p3', 'p4'];
    expect(radioLabel(state).text).toBe('BLOCKED');
  });

  it('local PTT before the server confirms: TX, or RADIO DEAD after a crash', () => {
    setup();
    state.localPtt = true;
    expect(radioLabel(state)).toEqual({ text: 'TX', cls: 'tx' });
    state.own = { time: 1, receivedAt: 0, ac: { status: 'crashed' } as OwnAircraft };
    expect(radioLabel(state)).toEqual({ text: 'RADIO DEAD', cls: 'idle' });
    // someone else on the air wins over our local key state
    state.radio = ['p2'];
    expect(radioLabel(state).cls).toBe('rx');
  });
});
