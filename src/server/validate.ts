// Defensive parsing of inbound client messages. Anything that does not match
// protocol.ts exactly is rejected with a reason; nothing here throws.

import type { ClientMsg, FlapSetting } from '../shared/protocol';

export type Parsed = { ok: true; msg: ClientMsg } | { ok: false; error: string };

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const isStr = (v: unknown, max: number): v is string => typeof v === 'string' && v.length <= max;

export function parseClientMsg(raw: string): Parsed {
  let v: unknown;
  try {
    v = JSON.parse(raw);
  } catch {
    return { ok: false, error: 'Malformed JSON' };
  }
  if (!isObj(v) || typeof v.t !== 'string') return { ok: false, error: 'Bad message' };
  const bad = (what: string): Parsed => ({ ok: false, error: `Bad ${v.t as string}: ${what}` });
  switch (v.t) {
    case 'create':
      return isStr(v.name, 200) ? { ok: true, msg: { t: 'create', name: v.name } } : bad('name');
    case 'join':
      if (!isStr(v.code, 16)) return bad('code');
      return isStr(v.name, 200) ? { ok: true, msg: { t: 'join', code: v.code, name: v.name } } : bad('name');
    case 'start':
    case 'lobby':
      return { ok: true, msg: { t: v.t } };
    case 'ptt':
      return typeof v.on === 'boolean' ? { ok: true, msg: { t: 'ptt', on: v.on } } : bad('on');
    case 'rtc':
      if (!isStr(v.to, 64)) return bad('to');
      return { ok: true, msg: { t: 'rtc', to: v.to, data: v.data } };
    case 'ap': {
      const msg: Extract<ClientMsg, { t: 'ap' }> = { t: 'ap' };
      for (const k of ['hdg', 'alt', 'spd', 'altSetting'] as const) {
        if (v[k] === undefined) continue;
        const n = v[k];
        if (!isNum(n)) return bad(k);
        msg[k] = n;
      }
      for (const k of ['app', 'gear'] as const) {
        if (v[k] === undefined) continue;
        const b = v[k];
        if (typeof b !== 'boolean') return bad(k);
        msg[k] = b;
      }
      if (v.flaps !== undefined) {
        if (v.flaps !== 0 && v.flaps !== 1 && v.flaps !== 2 && v.flaps !== 3) return bad('flaps');
        msg.flaps = v.flaps as FlapSetting;
      }
      return { ok: true, msg };
    }
    default:
      return { ok: false, error: 'Unknown message type' };
  }
}

/** Display name: printable, single-spaced, 1-16 characters. */
export function sanitizeName(raw: string): string {
  const clean = raw
    .normalize('NFKC')
    .replace(/[\p{C}\p{Zl}\p{Zp}]/gu, '') // control, format (bidi overrides, zero-width), separators
    .replace(/\s+/g, ' ')
    .trim();
  const name = [...clean].slice(0, 16).join('').trim();
  return name || 'Player';
}

/** Append " 2", " 3"... until the name is unique (case-insensitive) among `taken`. */
export function dedupeName(name: string, taken: readonly string[]): string {
  const lower = new Set(taken.map((n) => n.toLowerCase()));
  if (!lower.has(name.toLowerCase())) return name;
  for (let i = 2; ; i++) {
    const suffix = ` ${i}`;
    const candidate = [...name].slice(0, 16 - suffix.length).join('').trimEnd() + suffix;
    if (!lower.has(candidate.toLowerCase())) return candidate;
  }
}
