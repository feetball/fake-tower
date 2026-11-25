/** A seedable uniform [0, 1) generator. Inject Math.random or mulberry32(seed). */
export type Rng = () => number;

export function mulberry32(seed: number): Rng {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function randRange(rng: Rng, lo: number, hi: number): number {
  return lo + (hi - lo) * rng();
}

export function randInt(rng: Rng, lo: number, hiIncl: number): number {
  return lo + Math.floor(rng() * (hiIncl - lo + 1));
}

export function pick<T>(rng: Rng, items: readonly T[]): T {
  const v = items[Math.floor(rng() * items.length)];
  if (v === undefined) throw new Error('pick from empty list');
  return v;
}

export function shuffle<T>(rng: Rng, items: readonly T[]): T[] {
  const a = items.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    const tmp = a[i] as T;
    a[i] = a[j] as T;
    a[j] = tmp;
  }
  return a;
}
