import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { WebSocket } from 'ws';
import type { ServerMsg } from '../shared/protocol';
import { mulberry32 } from '../shared/sim/rng';
import { type Conn, Hub, assignRoles } from './rooms';
import { type RunningServer, startServer } from './main';
import { dedupeName, parseClientMsg, sanitizeName } from './validate';

type Msg<T extends ServerMsg['t']> = Extract<ServerMsg, { t: T }>;

class Client {
  readonly msgs: ServerMsg[] = [];
  readonly raw: string[] = [];
  id = '';
  private waiters: (() => void)[] = [];
  constructor(readonly ws: WebSocket) {
    ws.on('message', (d) => {
      const s = d.toString();
      this.raw.push(s);
      const m = JSON.parse(s) as ServerMsg;
      if (m.t === 'welcome') this.id = m.id;
      this.msgs.push(m);
      for (const w of this.waiters.splice(0)) w();
    });
  }
  static async open(port: number): Promise<Client> {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
    const c = new Client(ws);
    await new Promise<void>((res, rej) => (ws.once('open', () => res()), ws.once('error', rej)));
    await c.next('welcome');
    return c;
  }
  send(m: unknown): void {
    this.ws.send(typeof m === 'string' ? m : JSON.stringify(m));
  }
  of<T extends ServerMsg['t']>(t: T): Msg<T>[] {
    return this.msgs.filter((m): m is Msg<T> => m.t === t);
  }
  last<T extends ServerMsg['t']>(t: T): Msg<T> | undefined {
    return this.of(t).at(-1);
  }
  /** Wait for a message of type t (after index `from`) matching pred. */
  async next<T extends ServerMsg['t']>(t: T, pred: (m: Msg<T>) => boolean = () => true, from = 0, ms = 3000): Promise<Msg<T>> {
    const deadline = Date.now() + ms;
    for (;;) {
      const hit = this.msgs.slice(from).find((m): m is Msg<T> => m.t === t && pred(m as Msg<T>));
      if (hit) return hit;
      if (Date.now() > deadline) throw new Error(`timeout waiting for ${t}`);
      await new Promise<void>((res) => {
        this.waiters.push(res);
        setTimeout(res, 50);
      });
    }
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

let server: RunningServer | null = null;
const clients: Client[] = [];
afterEach(async () => {
  for (const c of clients.splice(0)) c.ws.terminate();
  await server?.close();
  server = null;
});

async function lobby(n: number, opts: Parameters<typeof startServer>[0] = {}): Promise<{ cs: Client[]; code: string }> {
  server = await startServer({ port: 0, staticRoot: null, ...opts });
  const cs: Client[] = [];
  for (let i = 0; i < n; i++) cs.push(await Client.open(server.port));
  clients.push(...cs);
  cs[0]!.send({ t: 'create', name: 'P0' });
  const code = (await cs[0]!.next('room')).room.code;
  for (let i = 1; i < n; i++) {
    cs[i]!.send({ t: 'join', code: code.toLowerCase(), name: `P${i}` });
    await cs[i]!.next('room');
  }
  await cs[0]!.next('room', (m) => m.room.players.length === n);
  return { cs, code };
}

describe('validation helpers', () => {
  it('parses defensively', () => {
    expect(parseClientMsg('{').ok).toBe(false);
    expect(parseClientMsg('null').ok).toBe(false);
    expect(parseClientMsg('[]').ok).toBe(false);
    expect(parseClientMsg('{"t":"nope"}').ok).toBe(false);
    expect(parseClientMsg('{"t":"ap","hdg":"90"}').ok).toBe(false);
    expect(parseClientMsg('{"t":"ap","hdg":1e999}').ok).toBe(false); // Infinity
    expect(parseClientMsg('{"t":"ap","flaps":4}').ok).toBe(false);
    expect(parseClientMsg('{"t":"ptt","on":1}').ok).toBe(false);
    expect(parseClientMsg('{"t":"ap","hdg":90,"gear":true,"evil":1}')).toEqual({ ok: true, msg: { t: 'ap', hdg: 90, gear: true } });
  });

  it('sanitises and de-duplicates names', () => {
    expect(sanitizeName('  Bob‮\u0000  the   pilot  ')).toBe('Bob the pilot');
    expect(sanitizeName('​\n')).toBe('Player');
    expect([...sanitizeName('x'.repeat(50))]).toHaveLength(16);
    expect(dedupeName('bob', ['Bob', 'Bob 2'])).toBe('bob 3');
    expect(dedupeName('ABCDEFGHIJKLMNOP', ['ABCDEFGHIJKLMNOP'])).toBe('ABCDEFGHIJKLMN 2');
  });

  it('assigns roles for every player count', () => {
    const rng = mulberry32(3);
    for (let n = 1; n <= 8; n++) {
      const ids = Array.from({ length: n }, (_, i) => `p${i}`);
      const r = assignRoles(ids, rng);
      const all = [r.realControllerId, r.impostorId, ...r.pilots].filter(Boolean).sort();
      expect(all).toEqual(ids.slice().sort());
      expect(r.pilots).toHaveLength(n >= 3 ? n - 2 : n === 2 ? 1 : 1);
      expect(r.impostorId === '').toBe(n < 3);
      expect(r.realControllerId === '').toBe(n < 2);
    }
  });
});

describe('server', () => {
  it('assigns roles secretly: pilots never see the impostor flag, radar or other aircraft', async () => {
    const { cs } = await lobby(6);
    cs[0]!.send({ t: 'start' });
    const begins = await Promise.all(cs.map((c) => c.next('begin')));
    await sleep(700);

    const controllers = begins.filter((b) => b.you.role === 'controller');
    const pilots = cs.filter((_, i) => begins[i]!.you.role === 'pilot');
    expect(controllers).toHaveLength(2);
    expect(controllers.filter((b) => b.you.impostor)).toHaveLength(1);
    expect(pilots).toHaveLength(4);
    // Same public player list for everyone, in join order, with no hidden-role field.
    for (const b of begins) {
      expect(b.players).toEqual(begins[0]!.players);
      expect(b.players.map((p) => p.id)).toEqual(cs.map((c) => c.id));
      for (const p of b.players) expect(Object.keys(p).sort()).toEqual(p.role === 'pilot' ? ['callsign', 'id', 'name', 'role'] : ['id', 'name', 'role']);
      expect(b.atis.qnh).toBe(begins[0]!.atis.qnh);
    }
    for (const p of pilots) {
      const b = p.last('begin')!;
      expect(b.you.impostor).toBe(false);
      expect(p.raw.some((r) => r.includes('"impostor":true'))).toBe(false);
      expect(p.of('radar')).toHaveLength(0);
      const own = p.of('own');
      expect(own.length).toBeGreaterThan(3);
      expect(new Set(own.map((o) => o.ac.callsign))).toEqual(new Set([b.you.callsign]));
      expect(p.raw.some((r) => r.includes('"targets"'))).toBe(false);
    }
    for (const c of cs.filter((_, i) => begins[i]!.you.role === 'controller')) {
      expect(c.of('own')).toHaveLength(0);
      const radar = await c.next('radar');
      expect(radar.targets).toHaveLength(4);
      expect(JSON.stringify(radar)).not.toContain('fuel');
    }
    const real = cs.find((_, i) => begins[i]!.you.role === 'controller' && !begins[i]!.you.impostor)!;
    expect(real.raw.some((r) => r.includes('"impostor":true'))).toBe(false);
  });

  it('arbitrates the radio and rejects bad input', async () => {
    const { cs } = await lobby(4);
    const [a, b, c, d] = cs as [Client, Client, Client, Client];
    a.send({ t: 'ptt', on: true }); // lobby: open mic, ignored
    b.send({ t: 'start' }); // not host
    await b.next('error', (m) => /host/i.test(m.msg));
    a.send('not json');
    await a.next('error');
    a.send({ t: 'start' });
    const begins = await Promise.all(cs.map((x) => x.next('begin')));
    expect(cs.every((x) => x.of('radio').length === 0)).toBe(true);

    const mark = d.msgs.length;
    a.send({ t: 'ptt', on: true });
    await d.next('radio', (m) => m.tx.join() === a.id, mark);
    b.send({ t: 'ptt', on: true });
    await d.next('radio', (m) => m.tx.join() === [a.id, b.id].join(), mark);
    b.send({ t: 'ptt', on: true }); // no change, no broadcast
    a.send({ t: 'ptt', on: false });
    await d.next('radio', (m) => m.tx.join() === b.id, mark);
    c.send({ t: 'ptt', on: true });
    await d.next('radio', (m) => m.tx.join() === [b.id, c.id].join(), mark);
    b.ws.close(); // disconnect clears their key
    await d.next('radio', (m) => m.tx.join() === c.id, mark);
    expect(d.of('radio').slice(-5).map((m) => m.tx.length)).toEqual([1, 2, 1, 2, 1]);
    // Every client saw the same sequence.
    expect(c.of('radio').map((m) => m.tx)).toEqual(d.of('radio').map((m) => m.tx));

    // Controllers cannot fly.
    const ctrl = cs.find((_, i) => begins[i]!.you.role === 'controller' && cs[i] !== b)!;
    ctrl.send({ t: 'ap', hdg: 90 });
    await ctrl.next('error', (m) => /pilot/i.test(m.msg));
    // Room shows b as disconnected mid-round, still listed.
    const room = await d.next('room', (m) => m.room.players.some((p) => p.id === b.id && !p.connected));
    expect(room.room.phase).toBe('playing');
    // Oversized frame: that socket is dropped, the server keeps going.
    const closed = new Promise((r) => c.ws.once('close', r));
    c.send('x'.repeat(70 * 1024));
    await closed;
    d.send({ t: 'ptt', on: false });
    await d.next('radio', (m) => m.tx.length === 0, mark);
  });

  it('pilot autopilot commands are applied with clamping', async () => {
    const { cs } = await lobby(4);
    cs[0]!.send({ t: 'start' });
    const begins = await Promise.all(cs.map((x) => x.next('begin')));
    const pilot = cs.find((_, i) => begins[i]!.you.role === 'pilot')!;
    pilot.send({ t: 'ap', hdg: 400, alt: 3049, spd: 100, altSetting: 999 });
    const own = await pilot.next('own', (m) => m.ac.selHdg === 40);
    expect(own.ac).toMatchObject({ selHdg: 40, selAlt: 3000, selSpd: 200, altSetting: 999 });
  });

  it('relays rtc only within a room', async () => {
    const { cs } = await lobby(2, { minPlayers: 2 });
    const outsider = await Client.open(server!.port);
    clients.push(outsider);
    outsider.send({ t: 'create', name: 'X' });
    await outsider.next('room');
    cs[0]!.send({ t: 'rtc', to: cs[1]!.id, data: { sdp: 'offer' } });
    const got = await cs[1]!.next('rtc');
    expect(got).toEqual({ t: 'rtc', from: cs[0]!.id, data: { sdp: 'offer' } });
    outsider.send({ t: 'rtc', to: cs[1]!.id, data: 'spy' });
    cs[1]!.send({ t: 'rtc', to: outsider.id, data: 'leak' });
    await sleep(200);
    expect(cs[1]!.of('rtc')).toHaveLength(1);
    expect(outsider.of('rtc')).toHaveLength(0);
  });

  it('dedupes names, migrates host, refuses joins mid-round and when full', async () => {
    server = await startServer({ port: 0, staticRoot: null, minPlayers: 2 });
    const cs: Client[] = [];
    for (let i = 0; i < 9; i++) cs.push(await Client.open(server.port));
    clients.push(...cs);
    cs[0]!.send({ t: 'create', name: 'Bob' });
    const code = (await cs[0]!.next('room')).room.code;
    expect(code).toMatch(/^[A-Z]{4}$/);
    for (let i = 1; i < 8; i++) {
      cs[i]!.send({ t: 'join', code, name: 'bob' });
      await cs[i]!.next('room');
    }
    cs[8]!.send({ t: 'join', code, name: 'late' });
    await cs[8]!.next('error', (m) => /full/i.test(m.msg));
    const names = (await cs[1]!.next('room', (m) => m.room.players.length === 8)).room.players.map((p) => p.name);
    expect(names.slice(0, 3)).toEqual(['Bob', 'bob 2', 'bob 3']);
    const mark = cs[1]!.msgs.length;
    cs[0]!.ws.close();
    const after = await cs[1]!.next('room', (m) => m.room.players.length === 7, mark);
    expect(after.room.players.find((p) => p.host)?.id).toBe(cs[1]!.id);
    for (let i = 3; i < 8; i++) cs[i]!.ws.close();
    await cs[1]!.next('room', (m) => m.room.players.length === 2);
    cs[1]!.send({ t: 'start' });
    await cs[1]!.next('begin');
    cs[8]!.send({ t: 'join', code, name: 'late' });
    await cs[8]!.next('error', (m) => /progress/i.test(m.msg));
  });
});

describe('hub game flow (fake connections)', () => {
  function fake(): Conn & { msgs: ServerMsg[] } {
    const msgs: ServerMsg[] = [];
    return { msgs, send: (m) => msgs.push(m) };
  }

  it('2-player test game: controller + pilot, no impostor; ends, then back to lobby', async () => {
    const hub = new Hub({ minPlayers: 2, rng: mulberry32(9), tickMs: 5 });
    const a = fake();
    const b = fake();
    hub.connect(a);
    hub.connect(b);
    hub.handle(a, JSON.stringify({ t: 'create', name: 'A' }));
    const code = [...hub.rooms.keys()][0]!;
    hub.handle(b, JSON.stringify({ t: 'join', code, name: 'B' }));
    hub.handle(a, JSON.stringify({ t: 'start' }));
    const room = hub.rooms.get(code)!;
    expect(room.phase).toBe('playing');
    const roles = [a, b].map((c) => c.msgs.find((m): m is Msg<'begin'> => m.t === 'begin')!.you);
    expect(roles.map((r) => r.role).sort()).toEqual(['controller', 'pilot']);
    expect(roles.every((r) => !r.impostor)).toBe(true);
    const pilotConn = roles[0]!.role === 'pilot' ? a : b;

    // Crash the only aircraft to end the round quickly.
    const ac = room.game!.round.aircraft[0]!;
    ac.alt = 0;
    await sleep(100);
    expect(room.phase).toBe('ended');
    const end = a.msgs.find((m): m is Msg<'end'> => m.t === 'end')!;
    expect(end.result.winner).toBe('impostor');
    expect(end.result.impostorId).toBe('');
    expect(end.result.outcomes[0]!.outcome).toBe('terrain');
    expect(b.msgs.some((m) => m.t === 'event' && m.event.kind === 'terrain')).toBe(true);
    // A crashed pilot cannot key.
    const before = pilotConn.msgs.length;
    hub.handle(pilotConn, JSON.stringify({ t: 'ptt', on: true }));
    expect(pilotConn.msgs.slice(before).some((m) => m.t === 'radio')).toBe(false);

    hub.handle(b, JSON.stringify({ t: 'lobby' }));
    expect(room.phase).toBe('ended'); // b is not host
    hub.handle(a, JSON.stringify({ t: 'lobby' }));
    expect(room.phase).toBe('lobby');
    hub.disconnect(a);
    hub.disconnect(b);
    expect(hub.rooms.size).toBe(0);
  });

  it('crash while keying releases the frequency', async () => {
    const hub = new Hub({ minPlayers: 1, rng: mulberry32(2), tickMs: 5 });
    const a = fake();
    hub.connect(a);
    hub.handle(a, JSON.stringify({ t: 'create', name: 'Solo' }));
    hub.handle(a, JSON.stringify({ t: 'start' }));
    hub.handle(a, JSON.stringify({ t: 'ptt', on: true }));
    const room = [...hub.rooms.values()][0]!;
    expect(room.tx).toHaveLength(1);
    room.game!.round.aircraft[0]!.alt = 0;
    await sleep(60);
    expect(room.tx).toHaveLength(0);
    const radios = a.msgs.filter((m): m is Msg<'radio'> => m.t === 'radio').map((m) => m.tx.length);
    expect(radios).toEqual([1, 0]);
    hub.close();
  });
});

describe('static files', () => {
  it('serves dist files with types and SPA fallback, blocks traversal', async () => {
    const root = mkdtempSync(join(tmpdir(), 'ft-static-'));
    mkdirSync(join(root, 'assets'));
    writeFileSync(join(root, 'index.html'), '<!doctype html><title>FT</title>');
    writeFileSync(join(root, 'assets', 'app.js'), 'console.log(1)');
    server = await startServer({ port: 0, staticRoot: root });
    const base = `http://127.0.0.1:${server.port}`;
    const js = await fetch(`${base}/assets/app.js`);
    expect(js.headers.get('content-type')).toContain('text/javascript');
    const spa = await fetch(`${base}/room/ABCD`);
    expect(spa.status).toBe(200);
    expect(spa.headers.get('content-type')).toContain('text/html');
    expect(await spa.text()).toContain('<title>FT</title>');
    expect((await fetch(`${base}/missing.png`)).status).toBe(404);
    expect((await fetch(`${base}/..%2f..%2f..%2fetc%2fpasswd`)).status).toBe(403);
    expect(await (await fetch(`${base}/%2e%2e/%2e%2e/etc/passwd`)).text()).toContain('<title>FT</title>'); // URL-normalised, stays in root
  });
});
