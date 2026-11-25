// Contract between the game client and the voice/radio module.
// Implemented by ./index.ts (createVoice). The game client only imports
// from this file and from ./index.

import type { PlayerId } from '../../shared/protocol';

export type VoiceMode =
  /** Lobby and end screen: open mic, clean audio, everyone hears everyone. */
  | 'open'
  /** In a round: one shared VHF frequency with push-to-talk. */
  | 'radio';

export interface VoiceDeps {
  selfId: PlayerId;
  /** Send a WebRTC signalling payload to another player via the game server ({t:'rtc'}). */
  sendSignal(to: PlayerId, data: unknown): void;
}

export interface VoiceStatus {
  /** Microphone permission granted and capturing. */
  micOk: boolean;
  /** Peers with an established audio connection. */
  connected: PlayerId[];
}

export interface Voice {
  /**
   * Ask for the microphone and set up audio. Must be called from a user
   * gesture. Resolves false if the mic is unavailable; the module then still
   * works receive-only and never throws.
   */
  init(): Promise<boolean>;
  /** The full set of other players in the room. Connects to new ids, drops missing ones. */
  setPeers(ids: PlayerId[]): void;
  /** Feed a signalling payload received from the server ({t:'rtc', from, data}). */
  handleSignal(from: PlayerId, data: unknown): void;
  setMode(mode: VoiceMode): void;
  /**
   * Radio mode only. The server's authoritative list of who is keying the
   * frequency ({t:'radio'}). Exactly one id: that voice is heard through the
   * radio filter. Two or more: nobody is intelligible, everyone (including the
   * transmitters, as with a real blocked frequency they would not know) hears
   * the heterodyne squeal. Empty: squelch closed, faint static only.
   */
  setTransmitting(ids: PlayerId[]): void;
  /** Radio mode only. Local push-to-talk state; gates the outgoing mic track. */
  setLocalPtt(on: boolean): void;
  /** 0..1 master volume. */
  setVolume(v: number): void;
  status(): VoiceStatus;
  onStatus(cb: (s: VoiceStatus) => void): void;
  dispose(): void;
}
