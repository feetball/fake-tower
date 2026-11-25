// Synthesised cockpit aural alerts (WebAudio, no assets).
// GPWS "whoop whoop" siren for TERRAIN / PULL UP and a caution chime for others.

let ctx: AudioContext | null = null;
let master: GainNode | null = null;
let volume = 0.8;
let sirenTimer: number | null = null;

/** Create / resume the AudioContext. Call from a user gesture. */
export function unlockAudio(): void {
  try {
    if (!ctx) {
      const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!AC) return;
      ctx = new AC();
      master = ctx.createGain();
      master.gain.value = volume * 0.5;
      master.connect(ctx.destination);
    }
    if (ctx.state === 'suspended') void ctx.resume();
  } catch {
    ctx = null;
  }
}

export function setAlertVolume(v: number): void {
  volume = v;
  if (master && ctx) master.gain.setTargetAtTime(v * 0.5, ctx.currentTime, 0.05);
}

function whoop(at: number): void {
  if (!ctx || !master) return;
  const osc = ctx.createOscillator();
  const g = ctx.createGain();
  osc.type = 'square';
  osc.frequency.setValueAtTime(420, at);
  osc.frequency.exponentialRampToValueAtTime(1100, at + 0.32);
  g.gain.setValueAtTime(0.0001, at);
  g.gain.exponentialRampToValueAtTime(0.35, at + 0.03);
  g.gain.setValueAtTime(0.35, at + 0.28);
  g.gain.exponentialRampToValueAtTime(0.0001, at + 0.36);
  const lp = ctx.createBiquadFilter();
  lp.type = 'lowpass';
  lp.frequency.value = 2400;
  osc.connect(lp).connect(g).connect(master);
  osc.start(at);
  osc.stop(at + 0.4);
}

function sirenCycle(): void {
  if (!ctx) return;
  const t = ctx.currentTime + 0.02;
  whoop(t);
  whoop(t + 0.45);
}

/** Start or stop the GPWS siren. Idempotent. */
export function setSiren(on: boolean): void {
  if (on && sirenTimer === null) {
    sirenCycle();
    sirenTimer = window.setInterval(sirenCycle, 1500);
  } else if (!on && sirenTimer !== null) {
    clearInterval(sirenTimer);
    sirenTimer = null;
  }
}

/** Single two-tone caution chime. */
export function chime(): void {
  if (!ctx || !master) return;
  const t = ctx.currentTime + 0.02;
  for (const [f, dt] of [
    [880, 0],
    [660, 0.22],
  ] as const) {
    const osc = ctx.createOscillator();
    const g = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.value = f;
    g.gain.setValueAtTime(0.0001, t + dt);
    g.gain.exponentialRampToValueAtTime(0.3, t + dt + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dt + 0.5);
    osc.connect(g).connect(master);
    osc.start(t + dt);
    osc.stop(t + dt + 0.55);
  }
}
