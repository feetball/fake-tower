import type { PlayerId } from '../../shared/protocol';
import type { Voice, VoiceDeps, VoiceMode, VoiceStatus } from './api';
import { backoffMs, computeAudibility, isOfferer, micEnabled, parseSignal, type Audibility } from './logic';
import {
  createRadioChain, createSqueal, createStatic, playSquelchBurst, setGain,
  type RadioChain, type Toggle,
} from './radio-dsp';

// STUN only, public Google server. The Steam build will replace this whole
// transport (Steam networking), so no TURN/relay is configured here.
const ICE_SERVERS: RTCIceServer[] = [{ urls: 'stun:stun.l.google.com:19302' }];

interface Peer {
  id: PlayerId;
  pc: RTCPeerConnection;
  offerer: boolean;
  /** Session id chosen by the offerer; guards against signals from a previous connection. */
  s: string | null;
  makingOffer: boolean;
  ignoreOffer: boolean;
  pendingIce: RTCIceCandidateInit[];
  attempts: number;
  timer: ReturnType<typeof setTimeout> | null;
  audio: { el: HTMLAudioElement; source: MediaStreamAudioSourceNode; gain: GainNode } | null;
}

const NOOP_STATUS: VoiceStatus = { micOk: false, connected: [] };

export function createVoice(deps: VoiceDeps): Voice {
  const { selfId } = deps;
  const hasRtc = typeof RTCPeerConnection !== 'undefined';
  const peers = new Map<PlayerId, Peer>();
  const streams = new Map<PlayerId, MediaStream>();
  const listeners: Array<(s: VoiceStatus) => void> = [];
  let wanted: PlayerId[] = [];
  let mode: VoiceMode = 'open';
  let tx: PlayerId[] = [];
  let ptt = false;
  let volume = 1;
  let disposed = false;

  let ctx: AudioContext | null = null;
  let master: GainNode | null = null;
  let clean: GainNode | null = null;
  let radio: RadioChain | null = null;
  let squeal: Toggle | null = null;
  let hiss: Toggle | null = null;
  let mic: MediaStream | null = null;
  let micTrack: MediaStreamTrack | null = null;
  let prevSquelch = false;
  let lastStatus = '';

  const safe = <A extends unknown[]>(fn: (...a: A) => void) => (...a: A): void => {
    try { fn(...a); } catch (e) { console.warn('[voice]', e); }
  };

  // ---- status ----
  function status(): VoiceStatus {
    if (disposed) return { ...NOOP_STATUS };
    const connected = [...peers.values()].filter((p) => p.pc.connectionState === 'connected').map((p) => p.id).sort();
    return { micOk: micTrack !== null && micTrack.readyState === 'live', connected };
  }
  function emit(): void {
    const s = status();
    const key = JSON.stringify(s);
    if (key === lastStatus) return;
    lastStatus = key;
    for (const cb of listeners) { try { cb(s); } catch (e) { console.warn('[voice]', e); } }
  }

  // ---- audio ----
  function applyMic(): void {
    if (micTrack) micTrack.enabled = micEnabled(mode, ptt);
  }

  function route(p: Peer): void {
    if (!p.audio || !clean || !radio) return;
    p.audio.gain.disconnect();
    p.audio.gain.connect(mode === 'open' ? clean : radio.input);
  }

  function applyAudibility(): void {
    if (!ctx || !radio) return;
    const a: Audibility = computeAudibility(mode, selfId, tx, [...peers.keys()]);
    for (const p of peers.values()) {
      if (p.audio) { route(p); setGain(ctx, p.audio.gain, a.gains[p.id] ?? 0); }
    }
    radio.setBed(a.bed);
    squeal?.setOn(a.squeal);
    hiss?.setOn(a.staticNoise);
    if (mode === 'radio' && a.squelchOpen !== prevSquelch && master) {
      playSquelchBurst(ctx, master, a.squelchOpen ? 'open' : 'close');
    }
    prevSquelch = mode === 'radio' && a.squelchOpen;
  }

  function detachAudio(p: Peer): void {
    if (!p.audio) return;
    p.audio.gain.disconnect();
    p.audio.source.disconnect();
    p.audio.el.srcObject = null;
    p.audio.el.remove();
    p.audio = null;
  }

  function attachAudio(p: Peer): void {
    const stream = streams.get(p.id);
    if (!ctx || !stream || p.audio || typeof document === 'undefined') return;
    // Chrome quirk: a remote WebRTC stream only feeds a MediaStreamAudioSourceNode
    // if it is also attached to a media element. Keep that element muted so the
    // sound is heard only once, through the graph.
    const el = document.createElement('audio');
    el.muted = true;
    el.autoplay = true;
    el.srcObject = stream;
    el.style.display = 'none';
    document.body.appendChild(el);
    el.play().catch(() => { /* muted autoplay; harmless */ });
    const source = ctx.createMediaStreamSource(stream);
    const gain = ctx.createGain();
    gain.gain.value = 0;
    source.connect(gain);
    p.audio = { el, source, gain };
    applyAudibility();
  }

  // ---- peers ----
  function sendSignal(to: PlayerId, data: unknown): void {
    try { deps.sendSignal(to, data); } catch (e) { console.warn('[voice]', e); }
  }

  function clearTimer(p: Peer): void {
    if (p.timer) { clearTimeout(p.timer); p.timer = null; }
  }

  function scheduleReconnect(p: Peer, delay = backoffMs(p.attempts++) + Math.random() * 500): void {
    clearTimer(p);
    p.timer = setTimeout(() => {
      p.timer = null;
      if (disposed || peers.get(p.id) !== p) return;
      const st = p.pc.connectionState;
      if (st === 'connected') return;
      if (p.offerer) rebuild(p);
      else { sendSignal(p.id, { k: 'reset' }); scheduleReconnect(p); }
    }, delay);
  }

  function createPeer(id: PlayerId, s: string | null, attempts = 0): Peer {
    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
    const offerer = isOfferer(selfId, id);
    const p: Peer = {
      id, pc, offerer, s: s ?? (offerer ? Math.random().toString(36).slice(2) : null),
      makingOffer: false, ignoreOffer: false, pendingIce: [], attempts, timer: null, audio: null,
    };
    peers.set(id, p);

    if (micTrack && mic) pc.addTrack(micTrack, mic);
    else pc.addTransceiver('audio', { direction: 'recvonly' });

    pc.ontrack = (ev) => {
      const stream = ev.streams[0] ?? new MediaStream([ev.track]);
      streams.set(id, stream);
      safe(() => { detachAudio(p); attachAudio(p); })();
    };
    pc.onicecandidate = (ev) => {
      if (ev.candidate && p.s) sendSignal(id, { k: 'ice', s: p.s, c: ev.candidate.toJSON() });
    };
    pc.onnegotiationneeded = () => {
      // The non-offerer never opens the first negotiation; it only renegotiates once connected.
      if (!p.offerer && !pc.remoteDescription) return;
      void (async () => {
        try {
          p.makingOffer = true;
          await pc.setLocalDescription();
          const d = pc.localDescription;
          if (d && p.s) sendSignal(id, { k: 'desc', s: p.s, d: { type: d.type, sdp: d.sdp } });
        } catch (e) { console.warn('[voice] offer', e); } finally { p.makingOffer = false; }
      })();
    };
    pc.onconnectionstatechange = () => {
      const st = pc.connectionState;
      if (st === 'connected') { p.attempts = 0; clearTimer(p); }
      else if (st === 'failed') scheduleReconnect(p);
      else if (st === 'disconnected') scheduleReconnect(p, 4000);
      emit();
    };
    return p;
  }

  function teardown(p: Peer): void {
    clearTimer(p);
    detachAudio(p);
    p.pc.ontrack = p.pc.onicecandidate = p.pc.onnegotiationneeded = p.pc.onconnectionstatechange = null;
    try { p.pc.close(); } catch { /* already closed */ }
  }

  /** Replace the connection with a fresh one (new session id when we are the offerer). */
  function rebuild(p: Peer, s: string | null = null): Peer {
    teardown(p);
    const n = createPeer(p.id, s, p.attempts);
    if (!n.offerer && n.s === null) scheduleReconnect(n); // in case the offerer never shows up
    emit();
    return n;
  }

  function removePeer(id: PlayerId): void {
    const p = peers.get(id);
    if (p) { teardown(p); peers.delete(id); }
    streams.delete(id);
  }

  async function onDesc(p: Peer, d: { type: 'offer' | 'answer'; sdp?: string }): Promise<void> {
    const pc = p.pc;
    const collision = d.type === 'offer' && (p.makingOffer || pc.signalingState !== 'stable');
    p.ignoreOffer = p.offerer && collision; // impolite (the offerer) ignores colliding offers
    if (p.ignoreOffer) return;
    await pc.setRemoteDescription(d); // implicitly rolls back our pending offer when polite
    for (const c of p.pendingIce.splice(0)) await pc.addIceCandidate(c).catch(() => undefined);
    if (d.type === 'offer') {
      await pc.setLocalDescription();
      const l = pc.localDescription;
      if (l && p.s) sendSignal(p.id, { k: 'desc', s: p.s, d: { type: l.type, sdp: l.sdp } });
    }
  }

  function handleSignal(from: PlayerId, data: unknown): void {
    if (disposed || !hasRtc || !wanted.includes(from)) return;
    const m = parseSignal(data);
    let p = peers.get(from);
    if (!m || !p) return;
    if (m.k === 'reset') {
      if (p.offerer) rebuild(p);
      return;
    }
    if (m.k === 'desc' && m.d.type === 'offer' && !p.offerer && p.s !== m.s) p = rebuild(p, m.s);
    if (p.s !== m.s) return; // stale signal from a previous connection
    const peer = p;
    if (m.k === 'ice') {
      if (!peer.pc.remoteDescription) peer.pendingIce.push(m.c);
      else peer.pc.addIceCandidate(m.c).catch((e) => { if (!peer.ignoreOffer) console.warn('[voice] ice', e); });
      return;
    }
    onDesc(peer, m.d).catch((e) => console.warn('[voice] signal', e));
  }

  // ---- public API ----
  async function init(): Promise<boolean> {
    if (disposed) return false;
    try {
      if (!ctx && typeof AudioContext !== 'undefined') {
        ctx = new AudioContext();
        master = ctx.createGain();
        master.gain.value = volume;
        master.connect(ctx.destination);
        clean = ctx.createGain();
        clean.connect(master);
        radio = createRadioChain(ctx);
        radio.output.connect(master);
        squeal = createSqueal(ctx, master);
        hiss = createStatic(ctx, master);
        for (const p of peers.values()) attachAudio(p);
        applyAudibility();
      }
      await ctx?.resume();
    } catch (e) { console.warn('[voice] audio', e); }
    let ok = false;
    try {
      if (typeof navigator !== 'undefined' && navigator.mediaDevices?.getUserMedia) {
        const s = await navigator.mediaDevices.getUserMedia({
          audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 },
        });
        const track = s.getAudioTracks()[0];
        if (disposed || !track) { s.getTracks().forEach((t) => t.stop()); }
        else {
          mic = s;
          micTrack = track;
          track.onended = () => emit();
          applyMic();
          // Peers created before the mic existed have a recvonly transceiver: upgrade it.
          for (const p of peers.values()) {
            const t = p.pc.getTransceivers().find((x) => x.receiver.track.kind === 'audio');
            if (t) { t.direction = 'sendrecv'; await t.sender.replaceTrack(track); t.sender.setStreams(s); }
          }
          ok = true;
        }
      }
    } catch (e) { console.warn('[voice] mic unavailable', e); }
    emit();
    return ok;
  }

  function setPeers(ids: PlayerId[]): void {
    if (disposed) return;
    wanted = [...new Set(ids)].filter((id) => id !== selfId);
    if (!hasRtc) return;
    for (const id of [...peers.keys()]) if (!wanted.includes(id)) removePeer(id);
    for (const id of wanted) if (!peers.has(id)) createPeer(id, null);
    applyAudibility();
    emit();
  }

  return {
    init,
    setPeers: safe(setPeers),
    handleSignal: safe(handleSignal),
    setMode: safe((m: VoiceMode) => { mode = m; applyMic(); applyAudibility(); }),
    setTransmitting: safe((ids: PlayerId[]) => { tx = [...ids]; applyAudibility(); }),
    setLocalPtt: safe((on: boolean) => { ptt = on; applyMic(); }),
    setVolume: safe((v: number) => {
      volume = Math.min(1, Math.max(0, Number.isFinite(v) ? v : 1));
      if (ctx && master) setGain(ctx, master, volume);
    }),
    status,
    onStatus: (cb) => { listeners.push(cb); },
    dispose: safe(() => {
      if (disposed) return;
      for (const id of [...peers.keys()]) removePeer(id);
      mic?.getTracks().forEach((t) => t.stop());
      mic = micTrack = null;
      void ctx?.close().catch(() => undefined);
      ctx = null;
      disposed = true;
      listeners.length = 0;
    }),
  };
}
