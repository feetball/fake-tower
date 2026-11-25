// Rooms, roles, the game loop and radio arbitration. Transport-agnostic: a
// connection is anything with send(); main.ts plugs in WebSockets.

import {
  type ClientMsg,
  MAX_PLAYERS,
  MIN_PLAYERS,
  type Phase,
  type PlayerId,
  PROTOCOL_VERSION,
  RADAR_SWEEP_SEC,
  type Role,
  type RoomState,
  type RoundPlayer,
  type ServerMsg,
  TICK_HZ,
} from '../shared/protocol';
import { WORLD } from '../shared/world';
import { type Rng, shuffle } from '../shared/sim/rng';
import { Round } from '../shared/sim/round';
import { dedupeName, parseClientMsg, sanitizeName } from './validate';

export interface Conn {
  send(msg: ServerMsg): void;
}

export interface HubOptions {
  minPlayers?: number;
  rng?: Rng;
  /** Real-time tick interval; tests may shorten it. Sim always advances 1/TICK_HZ s per tick. */
  tickMs?: number;
}

interface Player {
  id: PlayerId;
  name: string;
  conn: Conn | null; // null = disconnected
}

export interface Roles {
  realControllerId: PlayerId; // '' if none
  impostorId: PlayerId; // '' if none
  pilots: PlayerId[];
}

/**
 * Random roles. Normal game (>= 3 players): 1 real controller, 1 impostor, rest
 * pilots. Reduced test games (FT_MIN_PLAYERS < 4): 2 players = 1 real
 * controller + 1 pilot, no impostor; 1 player = a lone pilot (both ids '').
 */
export function assignRoles(ids: readonly PlayerId[], rng: Rng): Roles {
  const s = shuffle(rng, ids);
  if (s.length >= 3) return { realControllerId: s[0]!, impostorId: s[1]!, pilots: s.slice(2) };
  if (s.length === 2) return { realControllerId: s[0]!, impostorId: '', pilots: s.slice(1) };
  return { realControllerId: '', impostorId: '', pilots: s };
}

const CODE_LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I/O: easy to read out loud

class Game {
  readonly round: Round;
  private timer: ReturnType<typeof setInterval> | null = null;
  private ticks = 0;
  private readonly sweepTicks = Math.round(RADAR_SWEEP_SEC * TICK_HZ);

  constructor(
    readonly room: Room,
    readonly roles: Roles,
    rng: Rng,
  ) {
    this.round = new Round(roles.pilots, { rng, world: WORLD });
  }

  role(id: PlayerId): Role | null {
    if (id === this.roles.realControllerId || id === this.roles.impostorId) return 'controller';
    return this.roles.pilots.includes(id) ? 'pilot' : null;
  }

  start(tickMs: number): void {
    this.broadcastViews();
    this.timer = setInterval(() => this.tick(), tickMs);
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  private tick(): void {
    const events = this.round.step(1 / TICK_HZ);
    this.ticks++;
    for (const event of events) {
      this.room.broadcast({ t: 'event', event });
      // Crashed pilots lose their transmitter.
      if (event.kind !== 'landed')
        for (const cs of event.callsigns) {
          const ac = this.round.aircraft.find((a) => a.callsign === cs);
          if (ac) this.room.setPtt(ac.playerId, false);
        }
    }
    this.broadcastViews();
    if (this.round.finished) this.room.endRound();
  }

  /** 'own' to each pilot every tick; 'radar' to the controllers once per sweep. */
  private broadcastViews(): void {
    const time = Math.round(this.round.time * 10) / 10;
    for (const id of this.roles.pilots) {
      const ac = this.round.ownView(id);
      if (ac) this.room.sendTo(id, { t: 'own', time, ac });
    }
    if (this.ticks % this.sweepTicks === 0) {
      const msg: ServerMsg = { t: 'radar', time, targets: this.round.radar() };
      for (const id of [this.roles.realControllerId, this.roles.impostorId]) if (id) this.room.sendTo(id, msg);
    }
  }

  canTransmit(id: PlayerId): boolean {
    const ac = this.round.byPlayer(id);
    return !ac || ac.status !== 'crashed';
  }
}

export class Room {
  phase: Phase = 'lobby';
  players: Player[] = [];
  hostId: PlayerId = '';
  game: Game | null = null;
  /** Keying order on the frequency. */
  tx: PlayerId[] = [];

  constructor(
    readonly code: string,
    private readonly hub: Hub,
  ) {}

  get connected(): Player[] {
    return this.players.filter((p) => p.conn !== null);
  }

  state(): RoomState {
    return {
      code: this.code,
      phase: this.phase,
      players: this.players.map((p) => ({ id: p.id, name: p.name, host: p.id === this.hostId, connected: p.conn !== null })),
    };
  }

  sendTo(id: PlayerId, msg: ServerMsg): void {
    this.players.find((p) => p.id === id)?.conn?.send(msg);
  }

  broadcast(msg: ServerMsg): void {
    for (const p of this.players) p.conn?.send(msg);
  }

  broadcastState(): void {
    this.broadcast({ t: 'room', room: this.state() });
  }

  add(id: PlayerId, rawName: string, conn: Conn): void {
    const name = dedupeName(sanitizeName(rawName), this.players.map((p) => p.name));
    this.players.push({ id, name, conn });
    if (!this.hostId) this.hostId = id;
    this.broadcastState();
  }

  /** Connection lost. In the lobby the player leaves; mid-round they stay (their aircraft keeps flying). */
  disconnect(id: PlayerId): void {
    const p = this.players.find((q) => q.id === id);
    if (!p) return;
    p.conn = null;
    this.setPtt(id, false);
    if (this.phase === 'lobby') this.players = this.players.filter((q) => q !== p);
    if (this.connected.length === 0) {
      this.hub.removeRoom(this);
      return;
    }
    if (this.hostId === id) this.hostId = this.connected[0]!.id;
    this.broadcastState();
  }

  start(byId: PlayerId): string | null {
    if (byId !== this.hostId) return 'Only the host can start';
    if (this.phase !== 'lobby') return 'Round already started';
    const n = this.connected.length;
    if (n < this.hub.minPlayers) return `Need at least ${this.hub.minPlayers} players`;
    if (n > MAX_PLAYERS) return `At most ${MAX_PLAYERS} players`;

    const roles = assignRoles(this.connected.map((p) => p.id), this.hub.rng);
    const game = new Game(this, roles, this.hub.rng);
    this.game = game;
    this.phase = 'playing';
    this.clearPtt();
    this.broadcastState();

    // Listed in join order so position in the list never hints at a role.
    const players: RoundPlayer[] = this.players.map((p) => {
      const role = game.role(p.id) ?? 'pilot';
      const rp: RoundPlayer = { id: p.id, name: p.name, role };
      const cs = game.round.byPlayer(p.id)?.callsign;
      if (cs) rp.callsign = cs;
      return rp;
    });
    for (const p of this.players) {
      const role = game.role(p.id) ?? 'pilot';
      const you: { role: Role; impostor: boolean; callsign?: string } = { role, impostor: p.id === roles.impostorId };
      const cs = game.round.byPlayer(p.id)?.callsign;
      if (cs) you.callsign = cs;
      p.conn?.send({ t: 'begin', you, players, world: WORLD, atis: game.round.atis });
    }
    game.start(this.hub.tickMs);
    return null;
  }

  endRound(): void {
    const game = this.game;
    if (!game || this.phase !== 'playing') return;
    game.stop();
    this.phase = 'ended';
    this.clearPtt();
    this.broadcast({ t: 'end', result: game.round.result(game.roles.realControllerId, game.roles.impostorId) });
    this.broadcastState();
  }

  backToLobby(byId: PlayerId): string | null {
    if (byId !== this.hostId) return 'Only the host can return to the lobby';
    if (this.phase !== 'ended') return 'Round not ended';
    this.phase = 'lobby';
    this.game = null;
    this.players = this.players.filter((p) => p.conn !== null);
    this.broadcastState();
    return null;
  }

  setPtt(id: PlayerId, on: boolean): void {
    const keyed = this.tx.includes(id);
    if (on) {
      if (keyed || this.phase !== 'playing' || !this.game?.canTransmit(id)) return;
      if (!this.players.some((p) => p.id === id && p.conn)) return;
      this.tx = [...this.tx, id];
    } else {
      if (!keyed) return;
      this.tx = this.tx.filter((x) => x !== id);
    }
    this.broadcast({ t: 'radio', tx: [...this.tx] });
  }

  private clearPtt(): void {
    if (this.tx.length === 0) return;
    this.tx = [];
    this.broadcast({ t: 'radio', tx: [] });
  }

  /** Stop timers without notifying anyone (room deleted / server shutdown). */
  dispose(): void {
    this.game?.stop();
  }
}

interface Session {
  id: PlayerId;
  conn: Conn;
  room: Room | null;
  windowStart: number;
  windowCount: number;
}

const RATE_WINDOW_MS = 1000;
const RATE_MAX = 120; // messages per second; excess is dropped

export class Hub {
  readonly rooms = new Map<string, Room>();
  private readonly sessions = new Map<Conn, Session>();
  readonly minPlayers: number;
  readonly rng: Rng;
  readonly tickMs: number;
  private nextId = 1;

  constructor(opts: HubOptions = {}) {
    this.minPlayers = Math.max(1, Math.min(MAX_PLAYERS, Math.floor(opts.minPlayers ?? MIN_PLAYERS)));
    this.rng = opts.rng ?? Math.random;
    this.tickMs = opts.tickMs ?? 1000 / TICK_HZ;
  }

  connect(conn: Conn): PlayerId {
    const rand = Math.floor(this.rng() * 0xffffff).toString(36);
    const id = `p${(this.nextId++).toString(36)}${rand}`;
    this.sessions.set(conn, { id, conn, room: null, windowStart: 0, windowCount: 0 });
    conn.send({ t: 'welcome', id, protocol: PROTOCOL_VERSION });
    return id;
  }

  disconnect(conn: Conn): void {
    const s = this.sessions.get(conn);
    if (!s) return;
    this.sessions.delete(conn);
    s.room?.disconnect(s.id);
  }

  removeRoom(room: Room): void {
    room.dispose();
    this.rooms.delete(room.code);
  }

  close(): void {
    for (const r of this.rooms.values()) r.dispose();
    this.rooms.clear();
  }

  private newCode(): string {
    for (;;) {
      let code = '';
      for (let i = 0; i < 4; i++) code += CODE_LETTERS[Math.floor(this.rng() * CODE_LETTERS.length)] ?? 'A';
      if (!this.rooms.has(code)) return code;
    }
  }

  /** Handle one raw inbound frame. Never throws. */
  handle(conn: Conn, raw: string, now = Date.now()): void {
    const s = this.sessions.get(conn);
    if (!s) return;
    if (now - s.windowStart >= RATE_WINDOW_MS) {
      s.windowStart = now;
      s.windowCount = 0;
    }
    if (++s.windowCount > RATE_MAX) return;
    const parsed = parseClientMsg(raw);
    if (!parsed.ok) return conn.send({ t: 'error', msg: parsed.error });
    try {
      const err = this.dispatch(s, parsed.msg);
      if (err) conn.send({ t: 'error', msg: err });
    } catch (e) {
      console.error('handler error', e);
      conn.send({ t: 'error', msg: 'Internal error' });
    }
  }

  private dispatch(s: Session, msg: ClientMsg): string | null {
    if (msg.t === 'create' || msg.t === 'join') {
      if (s.room) return 'Already in a room';
      let room: Room;
      if (msg.t === 'create') {
        room = new Room(this.newCode(), this);
        this.rooms.set(room.code, room);
      } else {
        const found = this.rooms.get(msg.code.trim().toUpperCase());
        if (!found) return 'No such room';
        if (found.phase !== 'lobby') return 'Round in progress, wait for it to end';
        if (found.players.length >= MAX_PLAYERS) return 'Room is full';
        room = found;
      }
      s.room = room;
      room.add(s.id, msg.name, s.conn);
      return null;
    }
    const room = s.room;
    if (!room) return 'Not in a room';
    switch (msg.t) {
      case 'start':
        return room.start(s.id);
      case 'lobby':
        return room.backToLobby(s.id);
      case 'ptt':
        room.setPtt(s.id, msg.on);
        return null;
      case 'ap': {
        const game = room.game;
        if (room.phase !== 'playing' || !game) return 'No round in progress';
        if (game.role(s.id) !== 'pilot') return 'Only pilots fly';
        const { t: _t, ...cmd } = msg;
        game.round.applyAp(s.id, cmd); // ignored silently once landed/crashed
        return null;
      }
      case 'rtc': {
        if (msg.to === s.id) return null;
        const target = room.players.find((p) => p.id === msg.to && p.conn);
        if (target) target.conn!.send({ t: 'rtc', from: s.id, data: msg.data });
        return null;
      }
    }
  }
}
