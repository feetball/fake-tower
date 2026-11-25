// Web Audio graph builders for the VHF AM radio sound. All take a
// BaseAudioContext so they work with OfflineAudioContext or a mock.

const SMOOTH = 0.03; // setTargetAtTime time constant (s)

function ramp(p: AudioParam, v: number, ctx: BaseAudioContext, tc = SMOOTH): void {
  p.setTargetAtTime(v, ctx.currentTime, tc);
}

export function makeNoiseBuffer(ctx: BaseAudioContext, seconds: number): AudioBuffer {
  const n = Math.max(1, Math.floor(ctx.sampleRate * seconds));
  const buf = ctx.createBuffer(1, n, ctx.sampleRate);
  const d = buf.getChannelData(0);
  for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1;
  return buf;
}

function loopedNoise(ctx: BaseAudioContext): AudioBufferSourceNode {
  const src = ctx.createBufferSource();
  src.buffer = makeNoiseBuffer(ctx, 2);
  src.loop = true;
  src.start();
  return src;
}

function biquad(ctx: BaseAudioContext, type: BiquadFilterType, freq: number, q = Math.SQRT1_2): BiquadFilterNode {
  const f = ctx.createBiquadFilter();
  f.type = type;
  f.frequency.value = freq;
  f.Q.value = q;
  return f;
}

function chain(nodes: AudioNode[]): void {
  for (let i = 0; i < nodes.length - 1; i++) nodes[i]!.connect(nodes[i + 1]!);
}

function saturationCurve(amount: number): Float32Array<ArrayBuffer> {
  const n = 1024;
  const c = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const x = (i / (n - 1)) * 2 - 1;
    c[i] = Math.tanh(x * amount) / Math.tanh(amount);
  }
  return c;
}

export interface RadioChain {
  input: AudioNode;
  output: AudioNode;
  /** Fade the under-voice noise bed in/out. */
  setBed(on: boolean): void;
}

/** Voice -> HP 300 Hz (x2) -> LP 3 kHz (x3, steep) -> saturation -> compressor, plus noise bed. */
export function createRadioChain(ctx: BaseAudioContext): RadioChain {
  const input = ctx.createGain();
  const shaper = ctx.createWaveShaper();
  shaper.curve = saturationCurve(2.5);
  const comp = ctx.createDynamicsCompressor();
  comp.threshold.value = -28;
  comp.knee.value = 12;
  comp.ratio.value = 6;
  comp.attack.value = 0.003;
  comp.release.value = 0.15;
  const makeup = ctx.createGain();
  makeup.gain.value = 1.4;
  const output = ctx.createGain();
  chain([
    input,
    biquad(ctx, 'highpass', 300), biquad(ctx, 'highpass', 300),
    biquad(ctx, 'lowpass', 3000), biquad(ctx, 'lowpass', 3000), biquad(ctx, 'lowpass', 3000),
    shaper, comp, makeup, output,
  ]);

  const bed = ctx.createGain();
  bed.gain.value = 0;
  chain([loopedNoise(ctx), biquad(ctx, 'highpass', 300), biquad(ctx, 'lowpass', 3000), bed, output]);
  return { input, output, setBed: (on) => ramp(bed.gain, on ? 0.035 : 0, ctx, 0.05) };
}

export interface Toggle {
  setOn(on: boolean): void;
}

/** Blocked-frequency heterodyne: two detuned carriers with slow wobble plus noise. */
export function createSqueal(ctx: BaseAudioContext, dest: AudioNode): Toggle {
  const out = ctx.createGain();
  out.gain.value = 0;
  const lfo = ctx.createOscillator();
  lfo.frequency.value = 0.9;
  lfo.start();
  for (const f of [1480, 1870]) {
    const osc = ctx.createOscillator();
    osc.type = 'sine';
    osc.frequency.value = f;
    const depth = ctx.createGain();
    depth.gain.value = 35;
    lfo.connect(depth);
    depth.connect(osc.frequency);
    const level = ctx.createGain();
    level.gain.value = 0.5;
    osc.connect(level);
    level.connect(out);
    osc.start();
  }
  const hiss = ctx.createGain();
  hiss.gain.value = 0.25;
  chain([loopedNoise(ctx), biquad(ctx, 'bandpass', 2000, 0.7), hiss, out]);
  const shaper = ctx.createWaveShaper(); // gentle clipping gives the beat its harsh edge
  shaper.curve = saturationCurve(1.8);
  chain([out, shaper, dest]);
  return { setOn: (on) => ramp(out.gain, on ? 0.16 : 0, ctx, 0.02) };
}

/** Squelch-closed hiss. */
export function createStatic(ctx: BaseAudioContext, dest: AudioNode): Toggle {
  const g = ctx.createGain();
  g.gain.value = 0;
  chain([loopedNoise(ctx), biquad(ctx, 'bandpass', 1800, 0.5), g, dest]);
  return { setOn: (on) => ramp(g.gain, on ? 0.012 : 0, ctx, 0.08) };
}

/** One-shot decaying noise burst: a short click on squelch open, a longer tail on close. */
export function playSquelchBurst(ctx: BaseAudioContext, dest: AudioNode, kind: 'open' | 'close'): void {
  const dur = kind === 'open' ? 0.08 : 0.11;
  const src = ctx.createBufferSource();
  src.buffer = makeNoiseBuffer(ctx, dur);
  const bp = biquad(ctx, 'bandpass', 1500, 0.6);
  const env = ctx.createGain();
  const t = ctx.currentTime;
  const peak = kind === 'open' ? 0.18 : 0.12;
  env.gain.setValueAtTime(peak, t);
  env.gain.exponentialRampToValueAtTime(0.001, t + dur);
  chain([src, bp, env, dest]);
  src.start(t);
  src.stop(t + dur + 0.02);
}

export function setGain(ctx: BaseAudioContext, g: GainNode, v: number): void {
  ramp(g.gain, v, ctx);
}
