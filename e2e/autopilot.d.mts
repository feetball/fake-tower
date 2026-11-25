// Types for autopilot.mjs, so the vitest that exercises it typechecks.
import type { FlapSetting, OwnAircraft } from '../src/shared/protocol';

export const PLATFORM_FT: number;

export interface Panel {
  altSetting: number;
  hdg: number;
  alt: number;
  spd: number;
  flaps: FlapSetting;
  gear: boolean;
  app: boolean;
}

export type PanelDiff = Partial<{
  altSetting: number;
  hdg: number;
  alt: number;
  spd: number;
  flaps: FlapSetting;
  gear: boolean;
  app: boolean;
}>;

export function position(ac: OwnAircraft): { x: number; y: number };

export class ApproachPilot {
  constructor(role: 'lead' | 'trail', qnh: number);
  readonly role: 'lead' | 'trail';
  phase: 'enroute' | 'intercept' | 'loc' | 'gs' | 'done';
  readonly established: boolean;
  decide(ac: OwnAircraft, leadEstablished?: boolean): { panel: Panel | null; fail?: string };
}

export function assignSequence(acs: [OwnAircraft, OwnAircraft]): ['lead' | 'trail', 'lead' | 'trail'];
export function panelDiff(ac: OwnAircraft, panel: Panel): PanelDiff;
