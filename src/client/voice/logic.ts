// Pure decision logic for the voice module (no browser APIs; unit-tested).

import type { PlayerId } from '../../shared/protocol';
import type { VoiceMode } from './api';

export interface Audibility {
  /** Per-peer voice gain target (0 or 1). */
  gains: Record<PlayerId, number>;
  /** Route voices through the radio chain (radio mode) or the clean bus (open mode). */
  radio: boolean;
  /** Heterodyne squeal (blocked frequency). */
  squeal: boolean;
  /** Faint static (squelch closed). */
  staticNoise: boolean;
  /** Band-limited noise bed under a single audible voice. */
  bed: boolean;
  /** Squelch is open: somebody (possibly us) is keying. Drives click/tail sounds. */
  squelchOpen: boolean;
}

export function computeAudibility(
  mode: VoiceMode,
  selfId: PlayerId,
  txIds: readonly PlayerId[],
  peerIds: readonly PlayerId[],
): Audibility {
  const gains: Record<PlayerId, number> = {};
  const out: Audibility = {
    gains, radio: mode === 'radio', squeal: false, staticNoise: false, bed: false, squelchOpen: false,
  };
  if (mode === 'open') {
    for (const id of peerIds) gains[id] = 1;
    return out;
  }
  const tx = [...new Set(txIds)];
  for (const id of peerIds) gains[id] = 0;
  out.squelchOpen = tx.length > 0;
  if (tx.length === 0) out.staticNoise = true;
  else if (tx.length >= 2) out.squeal = true;
  else {
    const only = tx[0] as PlayerId;
    // Self keying: silence, no sidetone, and the bed noise stays off.
    if (only !== selfId) {
      if (only in gains) gains[only] = 1;
      out.bed = true;
    }
  }
  return out;
}

/** Deterministic glare avoidance: the lexicographically smaller id creates the offer. */
export function isOfferer(selfId: PlayerId, peerId: PlayerId): boolean {
  return selfId < peerId;
}

/** Reconnect delay in ms: exponential backoff from 1 s, capped at 15 s (jitter added by caller). */
export function backoffMs(attempt: number): number {
  return Math.min(15000, 1000 * 2 ** Math.max(0, attempt));
}

/** Whether the outgoing mic track should be enabled. */
export function micEnabled(mode: VoiceMode, ptt: boolean): boolean {
  return mode === 'open' || ptt;
}

export type Signal =
  | { k: 'desc'; s: string; d: { type: 'offer' | 'answer'; sdp?: string } }
  | { k: 'ice'; s: string; c: RTCIceCandidateInit }
  | { k: 'reset' };

/** Defensive parse of an untrusted signalling payload. */
export function parseSignal(data: unknown): Signal | null {
  if (typeof data !== 'object' || data === null) return null;
  const m = data as Record<string, unknown>;
  if (m.k === 'reset') return { k: 'reset' };
  if (typeof m.s !== 'string') return null;
  if (m.k === 'desc' && typeof m.d === 'object' && m.d !== null) {
    const d = m.d as Record<string, unknown>;
    if (d.type !== 'offer' && d.type !== 'answer') return null;
    return { k: 'desc', s: m.s, d: { type: d.type, sdp: typeof d.sdp === 'string' ? d.sdp : undefined } };
  }
  if (m.k === 'ice' && typeof m.c === 'object' && m.c !== null) {
    return { k: 'ice', s: m.s, c: m.c as RTCIceCandidateInit };
  }
  return null;
}
