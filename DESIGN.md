# Fake Tower — design

Two voices on the frequency both claim to be the tower. One is real. One wants
you dead. You are flying an instrument approach in fog and cannot see anything.

4–8 players online. Realistic procedures, minimal art: a radar scope and an
instrument panel.

## Roles

Assigned at random when the host starts the round.

- **Real controller (1)** — sees the radar scope. Wins with the pilots.
- **Impostor controller (1)** — sees the identical scope. Wins alone.
- **Pilots (2–6)** — each flies one aircraft on instruments. No outside view,
  no traffic display.

Everyone knows which two players are controllers. Nobody but the controllers
knows which one is real. The server never sends the impostor flag to pilots.

## Win condition

The round ends when no aircraft is still flying.

- **Tower wins** (real controller + pilots) if strictly more than half of the
  aircraft landed.
- **Impostor wins** otherwise.

The end screen reveals the impostor and each aircraft's outcome.

## The frequency

One shared VHF frequency, push-to-talk (Space). This is the only way anyone
communicates during a round.

- Exactly one player keying: everyone hears them through a radio filter.
- Two or more keying: the frequency is blocked. Everyone hears a heterodyne
  squeal and no speech, exactly like real VHF AM.
- The server is authoritative on who is keying (`radio` message).
- Crashed aircraft cannot transmit. Landed aircraft can still listen.

The lobby and end screen use open-mic clean audio.

## What makes it deducible

Pilots can catch the impostor only by knowing procedure. They have, in the
cockpit:

- **ATIS** (button): the true QNH, runway, weather.
- **Approach plate** (button): ILS 27 course and frequency, platform altitude
  3000, FAF, glide angle, DA, MSA sectors, terrain, hold, missed approach.
- **Instruments**: heading, IAS, indicated altitude, VS, radio altimeter,
  DME + bearing to the field, ILS localizer/glideslope needles, fuel minutes.
- **GPWS**: TERRAIN / PULL UP warnings (late — a few seconds of margin).

An instruction that puts them below the MSA, gives the wrong QNH, clears two
aircraft for the approach together, or holds them past their fuel is a tell.
The real controller's counter is to call it out. The pilots decide who to obey.

Controllers do not see fuel. Pilots must declare "minimum fuel" by voice.

## Simulation (server authoritative, 10 Hz)

- Aircraft are flown through an autopilot panel: selected heading, altitude,
  speed, APP arm, gear, flaps, altimeter setting.
- Generic twin jet: 140–250 KIAS (250 max below 10 000), standard-rate turns
  (3°/s), climb/descent about 1800 fpm (up to 2500 in descent), ~1.5 kt/s
  speed change. Minimum speed depends on flaps (clean 200, F1 180, F2 160,
  F3 135). Selected speed is clamped to the current flap minimum.
- No wind in the flight model. ATIS reports light wind for flavour.
- **Altimetry**: indicated = true + (setting − QNH) × 27 ft. The autopilot
  holds *indicated* altitude. Aircraft spawn with 1013 set.
- **ILS**: with APP armed, localizer captures inside 25 nm when within the
  beam and intercept angle ≤ 90°; glideslope captures from below once on the
  localizer. Captured aircraft track the beam automatically.
- **Landing**: crossing the threshold with LOC+GS captured, gear down, flaps 3
  and IAS ≤ 155 = landed. Crossing it captured but misconfigured = `runway`
  outcome. Touching the ground anywhere else = `terrain`.
- **Terrain**: obstacles in `world.ts` are cylinders. Below the top inside the
  radius = `terrain`. Below field elevation anywhere = `terrain`.
- **Collision**: two aircraft within 0.15 nm and 200 ft = both `collision`.
- **Fuel**: minutes remaining, 1 min per min. Zero = `fuel`. Each aircraft
  starts with enough for a direct approach plus roughly 8–14 minutes.
- **Spawns**: at the arrival gates, 25–35 nm out, 7000–10 000 ft, 250 kt,
  pointed roughly at the field, vertically or laterally separated.
- **Controller alerts**: conflict alert when two aircraft are inside 3 nm and
  1000 ft; MSAW when an aircraft not established on the ILS is below the MSA
  for its sector.

## Scope (controller view)

2D radar updated every 2 s: range rings, runway and extended centreline, fixes,
terrain with elevations, MSA sectors, targets with history trail and data tag
(callsign, altitude in hundreds with trend arrow, ground speed). Range/bearing
measuring tool, zoom/pan. A role banner states plainly whether you are the real
tower or the impostor, with the impostor's objective.

## Architecture

- `src/shared` — protocol, world definition, pure simulation (no I/O).
- `src/server` — Node + `ws`. Rooms, role assignment, tick loop, radio
  arbitration, WebRTC signalling relay. Serves `dist/client` in production.
- `src/client` — Vite + TypeScript + canvas, no framework.
- `src/client/voice` — WebRTC audio mesh and the radio DSP, behind `api.ts`.
- Steam packaging (Electron shell + Steamworks lobbies replacing room codes)
  is a later step; nothing in the game depends on the browser beyond WebRTC.
