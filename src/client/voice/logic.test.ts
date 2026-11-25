import { describe, expect, it } from 'vitest';
import { backoffMs, computeAudibility, isOfferer, micEnabled, parseSignal } from './logic';

const peers = ['a', 'b', 'c'];

describe('computeAudibility', () => {
  it('open mode: everyone audible, no effects', () => {
    const r = computeAudibility('open', 'me', ['a', 'b'], peers);
    expect(r.gains).toEqual({ a: 1, b: 1, c: 1 });
    expect(r).toMatchObject({ radio: false, squeal: false, staticNoise: false, bed: false });
  });
  it('radio, one remote transmitter: only that peer, via radio chain', () => {
    const r = computeAudibility('radio', 'me', ['b'], peers);
    expect(r.gains).toEqual({ a: 0, b: 1, c: 0 });
    expect(r).toMatchObject({ radio: true, squeal: false, staticNoise: false, bed: true, squelchOpen: true });
  });
  it('radio, self transmitting: silence, no sidetone', () => {
    const r = computeAudibility('radio', 'me', ['me'], peers);
    expect(Object.values(r.gains).every((g) => g === 0)).toBe(true);
    expect(r).toMatchObject({ squeal: false, staticNoise: false, bed: false, squelchOpen: true });
  });
  it('radio, two or more: squeal and no voices (even with self among them)', () => {
    for (const tx of [['a', 'b'], ['me', 'c'], ['a', 'b', 'c']]) {
      const r = computeAudibility('radio', 'me', tx, peers);
      expect(Object.values(r.gains).every((g) => g === 0)).toBe(true);
      expect(r).toMatchObject({ squeal: true, staticNoise: false, bed: false });
    }
  });
  it('radio, empty: squelch closed, static only', () => {
    const r = computeAudibility('radio', 'me', [], peers);
    expect(r.gains).toEqual({ a: 0, b: 0, c: 0 });
    expect(r).toMatchObject({ squeal: false, staticNoise: true, squelchOpen: false });
  });
  it('duplicate ids count once; unknown transmitter gives no voice gain', () => {
    expect(computeAudibility('radio', 'me', ['a', 'a'], peers).squeal).toBe(false);
    expect(computeAudibility('radio', 'me', ['zzz'], peers).gains).toEqual({ a: 0, b: 0, c: 0 });
  });
});

describe('negotiation helpers', () => {
  it('exactly one side offers', () => {
    expect(isOfferer('a', 'b')).toBe(true);
    expect(isOfferer('b', 'a')).toBe(false);
    expect(isOfferer('a', 'a')).toBe(false);
  });
  it('backoff grows and is capped', () => {
    expect(backoffMs(0)).toBe(1000);
    expect(backoffMs(2)).toBe(4000);
    expect(backoffMs(30)).toBe(15000);
  });
  it('mic gating', () => {
    expect(micEnabled('open', false)).toBe(true);
    expect(micEnabled('radio', false)).toBe(false);
    expect(micEnabled('radio', true)).toBe(true);
  });
  it('parseSignal validates payloads', () => {
    expect(parseSignal(null)).toBeNull();
    expect(parseSignal({ k: 'desc', s: 'x', d: { type: 'bogus' } })).toBeNull();
    expect(parseSignal({ k: 'ice', c: {} })).toBeNull();
    expect(parseSignal({ k: 'reset' })).toEqual({ k: 'reset' });
    expect(parseSignal({ k: 'desc', s: 'x', d: { type: 'offer', sdp: 'v=0' } })).toEqual({
      k: 'desc', s: 'x', d: { type: 'offer', sdp: 'v=0' },
    });
    expect(parseSignal({ k: 'ice', s: 'x', c: { candidate: 'c' } })?.k).toBe('ice');
  });
});
