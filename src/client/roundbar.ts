// The strip across the top of both in-round views: role banner, clock,
// radio indicator, push-to-talk and volume. Also owns the PTT key handling.

import type { Actions } from './actions';
import { h, isTyping, setClass, setText } from './dom';
import { roundPlayer, roundTime, state, type State } from './store';
import { mmss } from './text';

export function radioLabel(s: State): { text: string; cls: 'idle' | 'rx' | 'tx' | 'blocked' } {
  const tx = s.radio;
  if (tx.length >= 2) return { text: 'BLOCKED', cls: 'blocked' };
  if (tx.length === 1) {
    const id = tx[0]!;
    if (id === s.selfId) return { text: 'TX', cls: 'tx' };
    const rp = roundPlayer(id);
    const nm = rp?.name ?? s.room?.players.find((p) => p.id === id)?.name ?? '?';
    const tag = rp?.role === 'pilot' && rp.callsign ? `${rp.callsign} · ${nm}` : rp?.role === 'controller' ? `${nm} · CTL` : nm;
    return { text: `RX ${tag}`, cls: 'rx' };
  }
  if (s.localPtt) return { text: 'TX', cls: 'tx' };
  return { text: 'IDLE', cls: 'idle' };
}

export function createRoundBar(actions: Actions): { el: HTMLElement; render: (s: State) => void } {
  const banner = h('div', { id: 'role-banner', class: 'role-banner' });
  const clock = h('div', { class: 'rb-clock', title: 'Round time' });
  const freq = h('div', { class: 'rb-freq' }, h('span', { class: 'dim' }, 'APP '), '119.850');
  const indicator = h('div', { id: 'radio-indicator', class: 'radio-ind idle' }, 'IDLE');
  const ptt = h('button', { id: 'ptt-btn', class: 'ptt-btn', title: 'Hold to transmit (or hold Space)' }, 'PTT', h('small', {}, 'hold SPACE'));
  const vol = h('input', { type: 'range', min: 0, max: 1, step: 0.01, class: 'vol', 'aria-label': 'Radio volume', title: 'Radio volume' });
  vol.addEventListener('input', () => actions.setVolume(Number(vol.value)));

  // ---- mouse PTT
  let mouseHeld = false;
  ptt.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    mouseHeld = true;
    try {
      ptt.setPointerCapture(e.pointerId);
    } catch {
      /* ignore */
    }
    actions.setPtt(true);
  });
  const mouseUp = () => {
    if (!mouseHeld) return;
    mouseHeld = false;
    if (!keyHeld) actions.setPtt(false);
  };
  ptt.addEventListener('pointerup', mouseUp);
  ptt.addEventListener('pointercancel', mouseUp);
  ptt.addEventListener('lostpointercapture', mouseUp);
  ptt.addEventListener('contextmenu', (e) => e.preventDefault());

  // ---- keyboard PTT (Space)
  let keyHeld = false;
  window.addEventListener('keydown', (e) => {
    if (e.code !== 'Space') return;
    if (state.view !== 'round') return;
    if (isTyping(e.target)) return;
    e.preventDefault();
    if (e.repeat || keyHeld) return;
    keyHeld = true;
    actions.setPtt(true);
  });
  window.addEventListener('keyup', (e) => {
    if (e.code !== 'Space' || !keyHeld) return;
    e.preventDefault();
    keyHeld = false;
    if (!mouseHeld) actions.setPtt(false);
  });
  const releaseAll = () => {
    keyHeld = false;
    mouseHeld = false;
    actions.setPtt(false);
  };
  window.addEventListener('blur', releaseAll);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) releaseAll();
  });
  // Space on a focused button would "click" it; stop that while in the round.
  window.addEventListener(
    'keyup',
    (e) => {
      if (e.code === 'Space' && state.view === 'round' && !isTyping(e.target)) e.preventDefault();
    },
    true,
  );

  const el = h(
    'header',
    { class: 'roundbar' },
    banner,
    h('div', { class: 'rb-right' }, clock, freq, indicator, ptt, h('label', { class: 'rb-vol' }, h('span', { class: 'dim' }, 'VOL'), vol)),
  );

  const render = (s: State) => {
    const r = s.round;
    if (r) {
      let text: string;
      let cls: string;
      if (r.you.role === 'controller') {
        if (r.you.impostor) {
          text =
            'YOU ARE THE IMPOSTOR — the tower wins only if more than half the aircraft land. Crash them, starve them of fuel, collide them — without being disbelieved.';
          cls = 'impostor';
        } else {
          text = 'YOU ARE THE REAL TOWER — get them down safely. The other controller is the impostor: call out their bad instructions.';
          cls = 'real';
        }
      } else {
        const ctl = r.players.filter((p) => p.role === 'controller').map((p) => p.name);
        text = `PILOT · ${r.you.callsign ?? s.own?.ac.callsign ?? ''} — ${ctl.join(' and ')} both claim to be Approach. One is lying. Fly the plate.`;
        cls = 'pilot';
      }
      setText(banner, text);
      banner.className = `role-banner ${cls}`;
    }
    const t = roundTime();
    setText(clock, mmss(t));
    const rl = radioLabel(s);
    setText(indicator, rl.text);
    indicator.className = `radio-ind ${rl.cls}`;
    setClass(ptt, 'active', s.localPtt);
    if (document.activeElement !== vol) vol.value = String(s.volume);
  };
  return { el, render };
}
