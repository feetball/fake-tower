// Hub/Room regression tests over fake connections: deterministic and fast.
// The WebSocket transport itself is covered in server.test.ts.

import { afterEach, describe, expect, it } from 'vitest';
import { MAX_PLAYERS, type ServerMsg, TICK_HZ } from '../shared/protocol';
import { mulberry32 } from '../shared/sim/rng';
import { type Conn, Hub, MAX_TIME_SCALE, assignRoles, clampTimeScale } from './rooms';
import { parseClientMsg } from './validate';

type Msg<T extends ServerMsg['t']> = Extract<ServerMsg, { t: T }>;
type Fake = Conn & { msgs: ServerMsg[]; of<T extends ServerMsg['t']>(t: T): Msg<T>[]; last<T extends ServerMsg['t']>(t: T): Msg<T> | undefined; errors(): string[] };

function fake(): Fake {
  const msgs: ServerMsg[] = [];
  const of = <T extends ServerMsg['t']>(t: T) => msgs.filter((m): m is Msg<T> => m.t === t);
  return { msgs, send: (m) => msgs.push(m), of, last: (t) => of(t).at(-1), errors: () => of('error').map((e) => e.msg) };
}

const hubs: Hub[] = [];
afterEach(() => {
  for (const h of hubs.splice(0)) h.close();
});

/** A hub whose game timer never fires on its own (tests call game.tick()). */
function makeHub(opts: ConstructorParameters<typeof Hub>[0] = {}): Hub {
  const hub = new Hub({ rng: mulberry32(11), tickMs: 1e9, ...opts });
  hubs.push(hub);
  return hub;
}

function send(hub: Hub, c: Fake, msg: unknown): void {
  hub.handle(c, typeof msg === 'string' ? msg : JSON.stringify(msg));
}

/** n connected players in one room, first is host. */
function lobby(hub: Hub, n: number): { cs: Fake[]; code: string; ids: string[] } {
  const cs = Array.from({ length: n }, fake);
  const ids = cs.map((c) => hub.connect(c));
  send(hub, cs[0]!, { t: 'create', name: 'Host' });
  const code = cs[0]!.last('room')!.room.code;
  for (let i = 1; i < n; i++) send(hub, cs[i]!, { t: 'join', code, name: `P${i}` });
  return { cs, code, ids };
}

describe('time scale', () => {
  it('clamps settings to [1, MAX_TIME_SCALE]; junk means real time', () => {
    expect(clampTimeScale(undefined)).toBe(1);
    expect(clampTimeScale('')).toBe(1);
    expect(clampTimeScale('abc')).toBe(1);
    expect(clampTimeScale(Number.NaN)).toBe(1);
    expect(clampTimeScale(0)).toBe(1);
    expect(clampTimeScale(-5)).toBe(1);
    expect(clampTimeScale('10')).toBe(10);
    expect(clampTimeScale(' 2.5 ')).toBe(2.5);
    expect(clampTimeScale(1000)).toBe(MAX_TIME_SCALE);
    expect(clampTimeScale(Infinity)).toBe(1);
    expect(makeHub({ timeScale: 50 }).timeScale).toBe(MAX_TIME_SCALE);
    expect(makeHub().timeScale).toBe(1);
  });

  function started(timeScale: number) {
    const hub = makeHub({ timeScale, rng: mulberry32(5) });
    const { cs } = lobby(hub, 4);
    send(hub, cs[0]!, { t: 'start' });
    const room = [...hub.rooms.values()][0]!;
    return { hub, cs, room, game: room.game! };
  }

  it('a scaled tick is N fixed sub-steps: identical physics to N real-time ticks', () => {
    const slow = started(1);
    const fast = started(4);
    for (const g of [slow, fast]) {
      for (const id of g.game.roles.pilots) g.game.round.applyAp(id, { hdg: 123, alt: 3000, spd: 200 });
    }
    for (let i = 0; i < 400; i++) slow.game.tick();
    for (let i = 0; i < 100; i++) fast.game.tick();
    expect(fast.game.round.time).toBeCloseTo(40, 9);
    expect(fast.game.round.time).toBe(slow.game.round.time);
    // bit-for-bit the same aircraft state (no dt multiplication)
    expect(JSON.parse(JSON.stringify(fast.game.round.aircraft))).toEqual(JSON.parse(JSON.stringify(slow.game.round.aircraft)));
    // views go out once per real tick; radar once per 2 s of simulated time
    const pilot = (g: typeof slow) => g.cs.find((c) => c.of('begin')[0]!.you.role === 'pilot')!;
    const ctl = (g: typeof slow) => g.cs.find((c) => c.of('begin')[0]!.you.role === 'controller')!;
    expect(pilot(slow).of('own')).toHaveLength(401); // + the one at start
    expect(pilot(fast).of('own')).toHaveLength(101);
    expect(ctl(slow).of('radar').map((m) => m.time)).toEqual(ctl(fast).of('radar').map((m) => m.time));
    expect(ctl(fast).of('radar')).toHaveLength(1 + 40 / 2);
  });

  it('fractional scales carry the remainder', () => {
    const { game } = started(2.5);
    for (let i = 0; i < 4; i++) game.tick();
    expect(game.round.time).toBeCloseTo(1.0, 9); // 10 sub-steps of 0.1 s
    game.tick();
    expect(game.round.time).toBeCloseTo(1.2, 9);
  });

  it('sub-steps stop at the end of the round and the round ends once', () => {
    const { cs, room, game } = started(MAX_TIME_SCALE);
    for (const ac of game.round.aircraft) ac.alt = 400; // below the field: crash on the next sub-step
    game.tick();
    expect(room.phase).toBe('ended');
    expect(game.round.time).toBeCloseTo(1 / TICK_HZ, 9);
    expect(cs[0]!.of('end')).toHaveLength(1);
    expect(cs[0]!.of('event').flatMap((e) => e.event.callsigns)).toHaveLength(2);
  });
});

describe('lobby and host', () => {
  it('host migrates in the lobby, and the new host can start', () => {
    const hub = makeHub({ minPlayers: 2 });
    const { cs, ids } = lobby(hub, 3);
    hub.disconnect(cs[0]!);
    const st = cs[1]!.last('room')!.room;
    expect(st.players.map((p) => p.id)).toEqual([ids[1], ids[2]]);
    expect(st.players.find((p) => p.host)?.id).toBe(ids[1]);
    send(hub, cs[2]!, { t: 'start' });
    expect(cs[2]!.errors().at(-1)).toMatch(/host/i);
    send(hub, cs[1]!, { t: 'start' });
    expect(cs[1]!.of('begin')).toHaveLength(1);
  });

  it('host migrates mid-round; the disconnected host stays listed and their aircraft keeps flying', () => {
    const hub = makeHub();
    const { cs, ids } = lobby(hub, 4);
    send(hub, cs[0]!, { t: 'start' });
    const room = [...hub.rooms.values()][0]!;
    hub.disconnect(cs[0]!);
    const st = cs[1]!.last('room')!.room;
    expect(st.phase).toBe('playing');
    expect(st.players).toHaveLength(4);
    expect(st.players[0]).toMatchObject({ id: ids[0], connected: false, host: false });
    expect(st.players.find((p) => p.host)?.id).toBe(ids[1]);
    expect(room.game!.round.aircraft).toHaveLength(2);
    room.game!.tick();
    expect(room.game!.round.aircraft.every((a) => a.flying)).toBe(true);
  });

  it('a player who left the lobby can rejoin by code with the same name', () => {
    const hub = makeHub();
    const { cs, code } = lobby(hub, 3);
    hub.disconnect(cs[2]!);
    expect(cs[0]!.last('room')!.room.players).toHaveLength(2);
    const again = fake();
    hub.connect(again);
    send(hub, again, { t: 'join', code: ` ${code.toLowerCase()} `, name: 'P2' });
    expect(again.errors()).toEqual([]);
    expect(again.last('room')!.room.players.map((p) => p.name)).toEqual(['Host', 'P1', 'P2']);
  });

  it('the last player leaving deletes the room; its code is then unknown', () => {
    const hub = makeHub();
    const { cs, code } = lobby(hub, 2);
    hub.disconnect(cs[0]!);
    hub.disconnect(cs[1]!);
    expect(hub.rooms.size).toBe(0);
    const late = fake();
    hub.connect(late);
    send(hub, late, { t: 'join', code, name: 'x' });
    expect(late.errors()).toEqual(['No such room']);
    hub.disconnect(late); // never in a room: no-op
    hub.disconnect(fake()); // unknown connection: no-op
  });

  it('joins are refused mid-round and after the round until back in the lobby', () => {
    const hub = makeHub({ minPlayers: 1 });
    const { cs, code } = lobby(hub, 1);
    send(hub, cs[0]!, { t: 'start' });
    const late = fake();
    hub.connect(late);
    send(hub, late, { t: 'join', code, name: 'Late' });
    expect(late.errors().at(-1)).toMatch(/in progress/);
    const room = hub.rooms.get(code)!;
    room.game!.round.aircraft[0]!.alt = 0;
    room.game!.tick();
    expect(room.phase).toBe('ended');
    send(hub, late, { t: 'join', code, name: 'Late' });
    expect(late.errors()).toHaveLength(2);
    send(hub, cs[0]!, { t: 'lobby' });
    send(hub, late, { t: 'join', code, name: 'Late' });
    expect(late.errors()).toHaveLength(2);
    expect(late.last('room')!.room.players).toHaveLength(2);
  });

  it(`max ${MAX_PLAYERS} players; a slot frees up when someone leaves`, () => {
    const hub = makeHub();
    const { cs, code } = lobby(hub, MAX_PLAYERS);
    expect(cs.every((c) => c.errors().length === 0)).toBe(true);
    const ninth = fake();
    hub.connect(ninth);
    send(hub, ninth, { t: 'join', code, name: 'Nine' });
    expect(ninth.errors()).toEqual(['Room is full']);
    hub.disconnect(cs[3]!);
    send(hub, ninth, { t: 'join', code, name: 'Nine' });
    expect(ninth.last('room')!.room.players).toHaveLength(MAX_PLAYERS);
    send(hub, ninth, { t: 'join', code, name: 'Nine' });
    expect(ninth.errors().at(-1)).toBe('Already in a room');
  });

  it('start errors: not host, too few players, already started', () => {
    const hub = makeHub();
    const { cs } = lobby(hub, 3);
    send(hub, cs[1]!, { t: 'start' });
    expect(cs[1]!.errors()).toEqual(['Only the host can start']);
    send(hub, cs[0]!, { t: 'start' });
    expect(cs[0]!.errors()).toEqual(['Need at least 4 players']);
    const hub2 = makeHub({ minPlayers: 1 });
    const { cs: one } = lobby(hub2, 1);
    send(hub2, one[0]!, { t: 'start' });
    send(hub2, one[0]!, { t: 'start' });
    expect(one[0]!.errors()).toEqual(['Round already started']);
    send(hub2, one[0]!, { t: 'lobby' });
    expect(one[0]!.errors().at(-1)).toBe('Round not ended');
  });

  it("'lobby' resets the room: drops disconnected players, clears the game, allows a new round", () => {
    const hub = makeHub({ minPlayers: 3 });
    const { cs, ids, code } = lobby(hub, 4);
    send(hub, cs[0]!, { t: 'start' });
    const room = hub.rooms.get(code)!;
    hub.disconnect(cs[3]!);
    for (const ac of room.game!.round.aircraft) ac.alt = 0;
    room.game!.tick();
    expect(room.phase).toBe('ended');
    send(hub, cs[1]!, { t: 'lobby' });
    expect(cs[1]!.errors()).toEqual(['Only the host can return to the lobby']);
    send(hub, cs[0]!, { t: 'lobby' });
    expect(room.phase).toBe('lobby');
    expect(room.game).toBeNull();
    expect(room.tx).toEqual([]);
    expect(cs[0]!.last('room')!.room).toMatchObject({ phase: 'lobby', players: ids.slice(0, 3).map((id) => ({ id, connected: true })) });
    send(hub, cs[0]!, { t: 'ap', hdg: 90 });
    expect(cs[0]!.errors().at(-1)).toBe('No round in progress');
    send(hub, cs[0]!, { t: 'start' });
    expect(cs[0]!.of('begin')).toHaveLength(2);
    expect(room.game!.round.aircraft).toHaveLength(1);
    expect(room.game!.round.time).toBe(0);
  });
});

describe('input handling', () => {
  it('rejects malformed messages with a reason and never throws', () => {
    const hub = makeHub();
    const c = fake();
    hub.connect(c);
    const bad = [
      'not json',
      '',
      '42',
      '"str"',
      'null',
      '[]',
      '{}',
      '{"t":5}',
      '{"t":"nope"}',
      '{"t":"create"}',
      '{"t":"create","name":5}',
      JSON.stringify({ t: 'create', name: 'x'.repeat(201) }),
      '{"t":"join","code":"ABCD"}',
      JSON.stringify({ t: 'join', code: 'A'.repeat(17), name: 'x' }),
      '{"t":"ptt"}',
      '{"t":"ptt","on":"yes"}',
      '{"t":"rtc","data":1}',
      JSON.stringify({ t: 'rtc', to: 'x'.repeat(65), data: 1 }),
      '{"t":"ap","alt":null}',
      '{"t":"ap","spd":"200"}',
      '{"t":"ap","gear":1}',
      '{"t":"ap","app":"true"}',
      '{"t":"ap","flaps":1.5}',
      '{"t":"ap","flaps":-1}',
      '{"t":"ap","altSetting":1e400}',
      '{"t":"__proto__"}',
    ];
    for (const raw of bad) {
      expect(parseClientMsg(raw).ok, raw).toBe(false);
      expect(() => hub.handle(c, raw)).not.toThrow();
    }
    expect(c.errors()).toHaveLength(bad.length);
    // well-formed but out of place
    send(hub, c, { t: 'start' });
    send(hub, c, { t: 'ptt', on: true });
    send(hub, c, { t: 'ap', hdg: 1 });
    send(hub, c, { t: 'rtc', to: 'p1', data: null });
    send(hub, c, { t: 'join', code: 'ZZZZ', name: 'x' });
    expect(c.errors().slice(bad.length)).toEqual(['Not in a room', 'Not in a room', 'Not in a room', 'Not in a room', 'No such room']);
    // messages from an unknown connection are ignored
    const ghost = fake();
    hub.handle(ghost, '{"t":"create","name":"x"}');
    expect(ghost.msgs).toEqual([]);
    expect(hub.rooms.size).toBe(0);
  });

  it('accepts the documented shapes, strips unknown fields', () => {
    expect(parseClientMsg('{"t":"ap","hdg":90,"alt":3000,"spd":180,"app":true,"gear":false,"flaps":3,"altSetting":1003,"x":1}')).toEqual({
      ok: true,
      msg: { t: 'ap', hdg: 90, alt: 3000, spd: 180, app: true, gear: false, flaps: 3, altSetting: 1003 },
    });
    expect(parseClientMsg('{"t":"rtc","to":"p1"}')).toEqual({ ok: true, msg: { t: 'rtc', to: 'p1', data: undefined } });
    expect(parseClientMsg('{"t":"lobby","junk":true}')).toEqual({ ok: true, msg: { t: 'lobby' } });
  });

  it('rate limit: at most 120 messages per second per connection, excess dropped silently', () => {
    const hub = makeHub();
    const c = fake();
    hub.connect(c);
    const t0 = 1_000_000;
    for (let i = 0; i < 150; i++) hub.handle(c, '{"t":"start"}', t0 + i); // all inside one 1 s window
    expect(c.errors()).toHaveLength(120);
    hub.handle(c, '{"t":"start"}', t0 + 999);
    expect(c.errors()).toHaveLength(120);
    hub.handle(c, '{"t":"start"}', t0 + 1000); // new window
    expect(c.errors()).toHaveLength(121);
    // another connection has its own budget
    const d = fake();
    hub.connect(d);
    hub.handle(d, '{"t":"start"}', t0 + 1);
    expect(d.errors()).toHaveLength(1);
  });

  it('a handler exception is reported as an internal error, not thrown', () => {
    const hub = makeHub({ minPlayers: 1 });
    const { cs } = lobby(hub, 1);
    send(hub, cs[0]!, { t: 'start' });
    const room = [...hub.rooms.values()][0]!;
    room.game!.round.applyAp = () => {
      throw new Error('boom');
    };
    const orig = console.error;
    console.error = () => {};
    try {
      expect(() => send(hub, cs[0]!, { t: 'ap', hdg: 10 })).not.toThrow();
    } finally {
      console.error = orig;
    }
    expect(cs[0]!.errors().at(-1)).toBe('Internal error');
  });
});

describe('rtc relay', () => {
  it('only to connected players in the same room, never to self, sender id stamped by the server', () => {
    const hub = makeHub({ minPlayers: 2 });
    const a = lobby(hub, 3);
    const b = lobby(hub, 2);
    const [a0, a1, a2] = a.cs as [Fake, Fake, Fake];
    const [b0] = b.cs as [Fake, Fake];
    send(hub, a0, { t: 'rtc', to: a.ids[1], data: { k: 'desc', s: 'x' }, from: 'spoofed' });
    expect(a1.of('rtc')).toEqual([{ t: 'rtc', from: a.ids[0], data: { k: 'desc', s: 'x' } }]);
    send(hub, a0, { t: 'rtc', to: b.ids[0], data: 'cross-room' });
    send(hub, b0, { t: 'rtc', to: a.ids[2], data: 'cross-room' });
    send(hub, a0, { t: 'rtc', to: a.ids[0], data: 'self' });
    send(hub, a0, { t: 'rtc', to: 'nobody', data: 'x' });
    expect(b0.of('rtc')).toEqual([]);
    expect(a2.of('rtc')).toEqual([]);
    expect(a0.of('rtc')).toEqual([]);
    expect([a0, a1, a2, b0].flatMap((c) => c.errors())).toEqual([]);
    // mid-round: a disconnected player gets nothing (and nothing throws)
    send(hub, a0, { t: 'start' });
    hub.disconnect(a2);
    send(hub, a0, { t: 'rtc', to: a.ids[2], data: 'x' });
    expect(a2.of('rtc')).toEqual([]);
  });
});

describe('push-to-talk', () => {
  function round(n = 4, minPlayers = 4) {
    const hub = makeHub({ minPlayers });
    const l = lobby(hub, n);
    send(hub, l.cs[0]!, { t: 'start' });
    const room = [...hub.rooms.values()][0]!;
    const game = room.game!;
    const pilots = l.cs.filter((_, i) => game.roles.pilots.includes(l.ids[i]!));
    const pilotIds = l.ids.filter((id) => game.roles.pilots.includes(id));
    return { h: hub, room, game, ...l, pilots, pilotIds };
  }

  it('ignored in the lobby and on the end screen (open mic there)', () => {
    const hub = makeHub({ minPlayers: 1 });
    const { cs } = lobby(hub, 2);
    send(hub, cs[0]!, { t: 'ptt', on: true });
    expect(cs[1]!.of('radio')).toEqual([]);
    send(hub, cs[0]!, { t: 'start' });
    const room = [...hub.rooms.values()][0]!;
    for (const ac of room.game!.round.aircraft) ac.alt = 0;
    room.game!.tick();
    send(hub, cs[0]!, { t: 'ptt', on: true });
    expect(cs[1]!.of('radio')).toEqual([]);
  });

  it('cleared when the keying pilot crashes', () => {
    const { h, game, room, pilots, pilotIds, cs } = round();
    send(h, pilots[0]!, { t: 'ptt', on: true });
    expect(room.tx).toEqual([pilotIds[0]]);
    game.round.byPlayer(pilotIds[0]!)!.alt = 0;
    game.tick();
    expect(room.tx).toEqual([]);
    expect(cs[0]!.last('radio')!.tx).toEqual([]);
    // and cannot key again, while the other pilot still can
    send(h, pilots[0]!, { t: 'ptt', on: true });
    expect(room.tx).toEqual([]);
    send(h, pilots[1]!, { t: 'ptt', on: true });
    expect(room.tx).toEqual([pilotIds[1]]);
  });

  it('a landed pilot can still transmit', () => {
    const { h, game, room, pilots, pilotIds } = round();
    game.round.byPlayer(pilotIds[0]!)!.finish('landed');
    send(h, pilots[0]!, { t: 'ptt', on: true });
    expect(room.tx).toEqual([pilotIds[0]]);
  });

  it('cleared on disconnect, and on round end for everyone', () => {
    const { h, game, room, cs, ids } = round();
    send(h, cs[0]!, { t: 'ptt', on: true });
    send(h, cs[1]!, { t: 'ptt', on: true });
    send(h, cs[2]!, { t: 'ptt', on: true });
    expect(room.tx).toEqual(ids.slice(0, 3));
    h.disconnect(cs[1]!);
    expect(room.tx).toEqual([ids[0], ids[2]]);
    expect(cs[3]!.last('radio')!.tx).toEqual([ids[0], ids[2]]);
    for (const ac of game.round.aircraft) ac.alt = 0;
    game.tick();
    expect(room.phase).toBe('ended');
    expect(room.tx).toEqual([]);
    expect(cs[3]!.last('radio')!.tx).toEqual([]);
    // the end message comes after the frequency is cleared
    const idx = (t: ServerMsg['t']) => cs[3]!.msgs.map((m) => m.t).lastIndexOf(t);
    expect(idx('radio')).toBeLessThan(idx('end'));
  });

  it('keying is idempotent: no broadcast without a change', () => {
    const { h, cs } = round();
    send(h, cs[0]!, { t: 'ptt', on: true });
    send(h, cs[0]!, { t: 'ptt', on: true });
    send(h, cs[1]!, { t: 'ptt', on: false });
    expect(cs[2]!.of('radio')).toHaveLength(1);
  });
});

describe('role assignment', () => {
  it('composition for 1-8 players', () => {
    const rng = mulberry32(99);
    for (let n = 1; n <= MAX_PLAYERS; n++) {
      const ids = Array.from({ length: n }, (_, i) => `p${i}`);
      for (let k = 0; k < 50; k++) {
        const r = assignRoles(ids, rng);
        expect([r.realControllerId, r.impostorId, ...r.pilots].filter(Boolean).sort()).toEqual([...ids].sort());
        expect(r.pilots).toHaveLength(n >= 3 ? n - 2 : n === 2 ? 1 : 1);
        if (n >= 3) expect(r.realControllerId).not.toBe(r.impostorId);
        expect(r.impostorId === '').toBe(n < 3);
        expect(r.realControllerId === '').toBe(n < 2);
      }
    }
  });

  it('every player is equally likely to get each role (4-8 players)', () => {
    const rng = mulberry32(2024);
    const N = 4000;
    for (let n = 4; n <= MAX_PLAYERS; n++) {
      const ids = Array.from({ length: n }, (_, i) => `p${i}`);
      const real = new Map<string, number>();
      const imp = new Map<string, number>();
      for (let k = 0; k < N; k++) {
        const r = assignRoles(ids, rng);
        real.set(r.realControllerId, (real.get(r.realControllerId) ?? 0) + 1);
        imp.set(r.impostorId, (imp.get(r.impostorId) ?? 0) + 1);
      }
      // expected N/n each; allow ±25 % (≈ 5-7 sigma), so this only catches a real bias
      for (const id of ids) {
        expect(real.get(id) ?? 0, `${n} players: ${id} real`).toBeGreaterThan((N / n) * 0.75);
        expect(real.get(id) ?? 0).toBeLessThan((N / n) * 1.25);
        expect(imp.get(id) ?? 0, `${n} players: ${id} impostor`).toBeGreaterThan((N / n) * 0.75);
        expect(imp.get(id) ?? 0).toBeLessThan((N / n) * 1.25);
      }
    }
  });

  it('the server roles match what each player is told; begin lists players in join order', () => {
    for (let n = 1; n <= MAX_PLAYERS; n++) {
      const hub = makeHub({ minPlayers: 1, rng: mulberry32(n) });
      const { cs, ids } = lobby(hub, n);
      send(hub, cs[0]!, { t: 'start' });
      const roles = [...hub.rooms.values()][0]!.game!.roles;
      cs.forEach((c, i) => {
        const b = c.last('begin')!;
        expect(b.players.map((p) => p.id)).toEqual(ids);
        expect(b.you.impostor).toBe(ids[i] === roles.impostorId);
        expect(b.you.role).toBe(roles.pilots.includes(ids[i]!) ? 'pilot' : 'controller');
        expect(!!b.you.callsign).toBe(b.you.role === 'pilot');
      });
      expect(cs[0]!.last('begin')!.players.filter((p) => p.role === 'controller')).toHaveLength(n >= 3 ? 2 : n === 2 ? 1 : 0);
    }
  });
});
