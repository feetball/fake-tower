// Actions the views can trigger. Implemented in main.ts (which owns the socket
// and the voice module) and injected, so views never import main.

import type { ClientMsg } from '../shared/protocol';

export interface Actions {
  send(msg: ClientMsg): void;
  /** Call from a user gesture: unlock audio, ask for the mic. */
  initAudio(): void;
  create(name: string): void;
  join(code: string, name: string): void;
  setPtt(on: boolean): void;
  setVolume(v: number): void;
  reload(): void;
}
