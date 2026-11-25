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
import { applyServerMsg, type Effect } from './reduce';
import { state, subscribe, update, type State } from './store';
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
// State transitions live in reduce.ts (pure, unit-tested); this runs their effects.
function runEffects(fx: Effect[]): void {
  for (const e of fx) {
    if (e.k === 'pttOff') {
      net.send({ t: 'ptt', on: false });
      const vv = voice;
      if (vv) safe(() => vv.setLocalPtt(false));
    } else {
      if (e.to !== 'round') setSiren(false);
      setVoiceMode(e.to === 'round' ? 'radio' : 'open');
    }
  }
}

function onMsg(m: ServerMsg): void {
  let fx: Effect[] = [];
  update((s) => {
    fx = applyServerMsg(s, m, performance.now());
  });
  runEffects(fx);
  switch (m.t) {
    case 'welcome':
      if (m.protocol !== PROTOCOL_VERSION) toast(`Protocol mismatch: server ${m.protocol}, client ${PROTOCOL_VERSION}. Reload the page.`);
      ensureVoice();
      break;
    case 'room':
      syncPeers();
      break;
    case 'radio':
      if (voice) {
        const v = voice;
        safe(() => v.setTransmitting([...m.tx]));
      }
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
    case 'begin':
    case 'own':
    case 'radar':
    case 'event':
    case 'end':
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
