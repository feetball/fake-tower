// Fake Tower browser client: wires the socket, the store, the voice module and
// the views together.

import { PROTOCOL_VERSION, type ClientMsg, type PlayerId, type ServerMsg } from '../shared/protocol';
import type { Actions } from './actions';
import { setAlertVolume, setSiren, unlockAudio } from './alerts';
import { createCockpit } from './cockpit';
import { h, show, storageGet, storageSet, toast } from './dom';
import { createEnd } from './end';
import { createLobby } from './lobby';
import { connect } from './net';
import { createRoundBar } from './roundbar';
import { createScope } from './scope';
import { HISTORY, state, subscribe, update, type LogEntry, type State } from './store';
import { eventText } from './text';
import type { Voice, VoiceMode } from './voice/api';
import { createVoice } from './voice/index';

declare global {
  interface Window {
    __ft: { readonly state: State };
  }
}
Object.defineProperty(window, '__ft', { value: Object.freeze({ state }), writable: false, configurable: false });

// ---------------------------------------------------------------- voice
let voice: Voice | null = null;
let wantInit = false;
let initStarted = false;
const pendingSignals: { from: PlayerId; data: unknown }[] = [];
let voiceMode: VoiceMode = 'open';
let lastPeers = '';

function safe(fn: () => void): void {
  try {
    fn();
  } catch (e) {
    console.error('[voice]', e);
  }
}

function ensureVoice(): void {
  if (voice || !state.selfId) return;
  try {
    voice = createVoice({
      selfId: state.selfId,
      sendSignal: (to, data) => net.send({ t: 'rtc', to, data }),
    });
  } catch (e) {
    console.error('voice unavailable', e);
    return;
  }
  const v = voice;
  safe(() =>
    v.onStatus((st) =>
      update((s) => {
        s.mic.ok = st.micOk;
        s.mic.connected = [...st.connected];
      }),
    ),
  );
  safe(() => v.setVolume(state.volume));
  safe(() => v.setMode(voiceMode));
  lastPeers = '';
  syncPeers();
  for (const sig of pendingSignals.splice(0)) safe(() => v.handleSignal(sig.from, sig.data));
  if (wantInit) startInit();
}

function startInit(): void {
  if (!voice || initStarted) return;
  initStarted = true;
  const v = voice;
  void v
    .init()
    .then((ok) =>
      update((s) => {
        s.mic.ok = ok || s.mic.ok;
        s.mic.initDone = true;
        try {
          const st = v.status();
          s.mic.ok = st.micOk;
          s.mic.connected = [...st.connected];
        } catch {
          /* ignore */
        }
      }),
    )
    .catch((e) => {
      console.error('voice init', e);
      update((s) => {
        s.mic.initDone = true;
      });
    });
}

function syncPeers(): void {
  if (!voice) return;
  const ids = (state.room?.players ?? []).filter((p) => p.connected && p.id !== state.selfId).map((p) => p.id).sort();
  const key = ids.join(',');
  if (key === lastPeers) return;
  lastPeers = key;
  const v = voice;
  safe(() => v.setPeers(ids));
}

function setVoiceMode(m: VoiceMode): void {
  if (voiceMode === m) return;
  voiceMode = m;
  const v = voice;
  if (v) safe(() => v.setMode(m));
}

// ---------------------------------------------------------------- actions
const actions: Actions = {
  send: (m: ClientMsg) => net.send(m),
  initAudio() {
    unlockAudio();
    wantInit = true;
    if (voice) startInit();
  },
  create(name) {
    update((s) => {
      s.name = name;
    });
    net.send({ t: 'create', name });
  },
  join(code, name) {
    update((s) => {
      s.name = name;
    });
    net.send({ t: 'join', code, name });
  },
  setPtt(on) {
    if (on && state.view !== 'round') return;
    if (state.localPtt === on) return;
    update((s) => {
      s.localPtt = on;
    });
    net.send({ t: 'ptt', on });
    const v = voice;
    if (v) safe(() => v.setLocalPtt(on));
  },
  setVolume(v) {
    const vol = Math.max(0, Math.min(1, v));
    storageSet('ft.volume', String(vol));
    setAlertVolume(vol);
    update((s) => {
      s.volume = vol;
    });
    const vv = voice;
    if (vv) safe(() => vv.setVolume(vol));
  },
  reload() {
    const code = state.room?.code;
    const url = new URL(location.href);
    url.search = code ? `?room=${code}` : '';
    location.href = url.toString();
  },
};

{
  const v = Number(storageGet('ft.volume'));
  if (storageGet('ft.volume') !== null && Number.isFinite(v)) state.volume = Math.max(0, Math.min(1, v));
  setAlertVolume(state.volume);
}

// ---------------------------------------------------------------- messages
function log(s: State, text: string, kind: LogEntry['kind'] = 'info', time: number | null = s.serverTime): void {
  s.log.push({ time, text, kind });
  if (s.log.length > 200) s.log.splice(0, s.log.length - 200);
}

function setTime(s: State, t: number): void {
  if (!Number.isFinite(t)) return;
  s.serverTime = t;
  s.serverTimeAt = performance.now();
}

function enterView(s: State, v: State['view']): void {
  if (s.view === v) return;
  s.view = v;
  if (v !== 'round' && s.localPtt) {
    s.localPtt = false;
    net.send({ t: 'ptt', on: false });
    const vv = voice;
    if (vv) safe(() => vv.setLocalPtt(false));
  }
  if (v !== 'round') setSiren(false);
  setVoiceMode(v === 'round' ? 'radio' : 'open');
}

function onMsg(m: ServerMsg): void {
  switch (m.t) {
    case 'welcome':
      update((s) => {
        s.selfId = m.id;
        s.protocol = m.protocol;
      });
      if (m.protocol !== PROTOCOL_VERSION) toast(`Protocol mismatch: server ${m.protocol}, client ${PROTOCOL_VERSION}. Reload the page.`);
      ensureVoice();
      break;
    case 'room':
      update((s) => {
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
          enterView(s, 'lobby');
        } else if (m.room.phase === 'playing') {
          if (s.view === 'menu' || s.view === 'lobby' || s.view === 'end') enterView(s, s.round && !s.end ? 'round' : 'waiting');
        } else if (m.room.phase === 'ended') {
          if (s.end) enterView(s, 'end');
          else if (s.view === 'menu' || s.view === 'lobby') enterView(s, 'waiting');
        }
      });
      syncPeers();
      break;
    case 'begin':
      update((s) => {
        s.round = { you: m.you, players: m.players, world: m.world, atis: m.atis, beganAt: performance.now() };
        s.own = null;
        s.radar = null;
        s.events = [];
        s.log = [];
        s.end = null;
        s.selected = null;
        s.radio = [];
        s.scratch = {};
        setTime(s, 0);
        log(s, `Round started. ATIS information ${m.atis.letter}, QNH ${m.atis.qnh}, runway ${m.atis.runway}.`, 'info', 0);
        if (m.you.role === 'controller') {
          log(s, m.you.impostor ? 'You are the IMPOSTOR controller.' : 'You are the REAL controller.', m.you.impostor ? 'bad' : 'good', 0);
        }
        enterView(s, 'round');
      });
      break;
    case 'own':
      update((s) => {
        s.own = { time: m.time, ac: m.ac, receivedAt: performance.now() };
        setTime(s, m.time);
      });
      break;
    case 'radar':
      update((s) => {
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
        s.radar = { time: m.time, targets: m.targets, history, receivedAt: performance.now() };
        setTime(s, m.time);
      });
      break;
    case 'radio':
      update((s) => {
        s.radio = [...m.tx];
      });
      if (voice) {
        const v = voice;
        safe(() => v.setTransmitting([...m.tx]));
      }
      break;
    case 'event':
      update((s) => {
        s.events.push(m.event);
        s.events.sort((a, b) => a.time - b.time);
        log(s, eventText(m.event), m.event.kind === 'landed' ? 'good' : 'bad', m.event.time);
      });
      break;
    case 'end':
      update((s) => {
        s.end = m.result;
        if (s.round) s.lastRoundPlayers = s.round.players;
        enterView(s, 'end');
      });
      break;
    case 'rtc':
      if (voice) {
        const v = voice;
        safe(() => v.handleSignal(m.from, m.data));
      } else {
        pendingSignals.push({ from: m.from, data: m.data });
        if (pendingSignals.length > 200) pendingSignals.shift();
      }
      break;
    case 'error':
      toast(m.msg);
      break;
    default:
      console.warn('unknown message', m);
  }
}

const net = connect(
  onMsg,
  () =>
    update((s) => {
      s.conn = 'open';
    }),
  (reason) => {
    update((s) => {
      s.conn = 'closed';
      s.closeReason = reason;
      if (s.localPtt) s.localPtt = false;
    });
    setSiren(false);
    const v = voice;
    if (v) safe(() => v.setTransmitting([]));
  },
);

// ---------------------------------------------------------------- DOM
const app = document.getElementById('app') ?? document.body;
createLobbyAndViews();

function createLobbyAndViews(): void {
  const renderLobby = createLobby(app, actions);
  const bar = createRoundBar(actions);
  const scope = createScope();
  const cockpit = createCockpit(actions);
  const waitingNote = h('div', { class: 'round-waiting' }, 'Waiting for round data…');
  const round = h('section', { id: 'screen-round', class: 'screen screen-round' }, bar.el, h('div', { class: 'round-body' }, scope.el, cockpit.el, waitingNote));
  const end = createEnd(actions);
  app.append(round, end.el);

  // disconnected overlay
  const discReason = h('div', { class: 'disc-reason' });
  const discBtn = h('button', { class: 'btn primary big', id: 'rejoin-btn' }, 'Reload and rejoin');
  discBtn.addEventListener('click', () => actions.reload());
  const disc = h(
    'div',
    { id: 'disconnected', class: 'disconnected', hidden: true },
    h('div', { class: 'disc-card card' }, h('div', { class: 'disc-title' }, 'DISCONNECTED'), discReason, discBtn),
  );
  document.body.append(disc);

  const render = (s: State) => {
    renderLobby(s);
    show(round, s.view === 'round');
    show(waitingNote, s.view === 'round' && !s.round);
    bar.render(s);
    scope.render(s);
    cockpit.render(s);
    end.render(s);
    show(disc, s.conn === 'closed');
    if (s.conn === 'closed') {
      discReason.textContent = `${s.closeReason}.${s.room ? ` Room ${s.room.code}.` : ''} The game server may have restarted.`;
      discBtn.textContent = s.room ? `Reload and rejoin ${s.room.code}` : 'Reload';
    }
    document.body.dataset.view = s.view;
  };
  subscribe(render);
  render(state);
}

// Keep the round clock ticking between 2 s radar sweeps.
setInterval(() => {
  if (state.view === 'round') update(() => {});
}, 250);

// Any later gesture also unlocks audio (autoplay policies).
const unlockOnce = () => unlockAudio();
window.addEventListener('pointerdown', unlockOnce);
window.addEventListener('keydown', unlockOnce);
