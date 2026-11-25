import { describe, expect, it, vi } from 'vitest';
import { createVoice } from './index';
import { createRadioChain, createSqueal, createStatic, makeNoiseBuffer, playSquelchBurst } from './radio-dsp';

/** Minimal BaseAudioContext fake: every create* returns a recording node proxy. */
function fakeCtx() {
  const created: string[] = [];
  const mkNode = (kind: string): unknown => {
    const store: Record<string, unknown> = {};
    const node: unknown = new Proxy(store, {
      get(t, k: string) {
        if (k === 'connect') return (d: unknown) => d;
        if (k === 'disconnect' || k === 'start' || k === 'stop') return () => undefined;
        if (!(k in t)) t[k] = { value: 0, setTargetAtTime: vi.fn(), setValueAtTime: vi.fn(), exponentialRampToValueAtTime: vi.fn() };
        return t[k];
      },
    });
    created.push(kind);
    return node;
  };
  const ctx = new Proxy({ sampleRate: 8000, currentTime: 0 }, {
    get(t, k: string) {
      if (k in t) return (t as Record<string, unknown>)[k];
      if (k === 'createBuffer') return (_c: number, n: number) => ({ getChannelData: () => new Float32Array(n) });
      if (k.startsWith('create')) return () => mkNode(k);
      return undefined;
    },
  }) as unknown as BaseAudioContext;
  return { ctx, created };
}

describe('radio-dsp', () => {
  it('builds a steep band-limited chain (2 HP, 3 LP biquads plus bed filters)', () => {
    const { ctx, created } = fakeCtx();
    const chain = createRadioChain(ctx);
    expect(created.filter((k) => k === 'createBiquadFilter').length).toBeGreaterThanOrEqual(5);
    expect(created).toContain('createWaveShaper');
    expect(created).toContain('createDynamicsCompressor');
    expect(() => chain.setBed(true)).not.toThrow();
  });
  it('builds squeal (2 carriers), static and bursts without throwing', () => {
    const { ctx, created } = fakeCtx();
    const dest = ctx.createGain();
    createSqueal(ctx, dest).setOn(true);
    createStatic(ctx, dest).setOn(false);
    playSquelchBurst(ctx, dest, 'open');
    playSquelchBurst(ctx, dest, 'close');
    expect(created.filter((k) => k === 'createOscillator').length).toBe(3); // 2 carriers + LFO
  });
  it('noise buffer has requested length', () => {
    const { ctx } = fakeCtx();
    expect(makeNoiseBuffer(ctx, 0.5).getChannelData(0).length).toBe(4000);
  });
});

describe('createVoice without browser APIs', () => {
  it('degrades to a safe no-op', async () => {
    const send = vi.fn();
    const v = createVoice({ selfId: 'a', sendSignal: send });
    const cb = vi.fn();
    v.onStatus(cb);
    expect(await v.init()).toBe(false);
    expect(() => {
      v.setPeers(['b', 'c']);
      v.handleSignal('b', { k: 'reset' });
      v.handleSignal('b', 42);
      v.setMode('radio');
      v.setTransmitting(['b']);
      v.setLocalPtt(true);
      v.setVolume(0.5);
    }).not.toThrow();
    expect(v.status()).toEqual({ micOk: false, connected: [] });
    expect(() => { v.dispose(); v.dispose(); }).not.toThrow();
    expect(send).not.toHaveBeenCalled();
  });
});
