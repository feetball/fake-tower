# Fake Tower

[![CI](https://github.com/feetball/fake-tower/actions/workflows/ci.yml/badge.svg)](https://github.com/feetball/fake-tower/actions/workflows/ci.yml)

A multiplayer social-deduction game for 4 to 8 players, played in the browser. Two players are air traffic controllers on one shared radio frequency and both claim to be the tower; one is real and one is an impostor trying to get the aircraft killed. The rest fly instrument approaches in fog with no outside view and must work out, from procedure knowledge alone, which controller to obey.

## How to play

### Roles

Roles are assigned at random when the host starts the round.

- Real controller (1): sees the radar scope. Wins with the pilots.
- Impostor controller (1): sees the identical scope. Wins alone.
- Pilots (2 to 6): each flies one aircraft on instruments.

Everyone knows which two players are controllers. Only the controllers know which one is real; the server never sends the impostor flag to pilots.

### Win condition

The round ends when no aircraft is still flying. The tower side (real controller and pilots) wins if strictly more than half of the aircraft landed. Otherwise the impostor wins. The end screen reveals the impostor and each aircraft's outcome.

### The radio

There is one VHF frequency, push-to-talk. Hold `Space` to transmit (or hold the PTT button with the mouse).

- One player keying: everyone hears them through a radio filter.
- Two or more keying: the frequency is blocked and nobody hears speech.
- Crashed aircraft cannot transmit. Landed aircraft can still listen.
- Lobby and end screen use open mic.

### Controller controls

Mouse (from the on-screen hint): wheel zooms, drag pans, double-click resets the view, right-drag or Shift-drag measures range and bearing, click selects a target. The toolbar toggles map layers and zooms (RR, CL, FIX, TERR, MSA, HOLD, PTL, HIST; RNG -/+; RESET).

Keyboard:

| Key | Action |
| --- | --- |
| `Space` | push-to-talk (hold) |
| `1`-`4`, `6`-`9` | with a target selected, set its data-tag leader direction (numpad layout: 8 north, 6 east, 2 south, 4 west, diagonals on 9/3/1/7) |
| `Esc` | clear selection / measuring line |

### Pilot controls

| Key | Action |
| --- | --- |
| `Space` | push-to-talk (hold) |
| `Left` / `Right` | selected heading -1 / +1 (Shift: 10) |
| `Up` / `Down` | selected altitude +100 / -100 ft (Shift: 1000) |
| `PageUp` / `PageDown` | selected speed +1 / -1 kt (Shift: 10) |
| `[` / `]` | altimeter setting -1 / +1 hPa (Shift: 5) |
| `B` | altimeter to standard 1013 |
| `A` | arm / disarm approach mode |
| `G` | gear up / down |
| `F` / `Shift+F` | flaps down / up one step |
| `I` | toggle ATIS |
| `P` | toggle approach plate (`Z` or click to zoom) |
| `Esc` | close ATIS / plate |

The autopilot panel fields (IAS, HDG, ALT, BARO) can also be clicked and typed into, and the mouse wheel changes them. To land: be established on the localizer and glideslope (arm APP), gear down, flaps 3, IAS 155 kt or less at the threshold.

Typing in a text field disables the keyboard shortcuts above, including push-to-talk.

## Run in development

```
npm install
npm run dev
```

This starts the game server on port 8080 and the Vite dev server on http://localhost:5173 (which proxies `/ws` to the game server). Open http://localhost:5173 in several browser windows: create a room in one, join by the 4-letter code (or the invite link) in the others.

To test alone or with fewer than 4 players, set `FT_MIN_PLAYERS`, for example:

```
FT_MIN_PLAYERS=2 npm run dev
```

With 3 players you get one real controller, one impostor and one pilot; with 2 players, one real controller and one pilot (no impostor); with 1 player, a lone pilot.

## Build and run in production

```
npm run build
npm start
```

`npm start` runs the game server, which serves `dist/client` itself. `PORT` sets the listen port (default 8080); `FT_MIN_PLAYERS` is honoured here too. `FT_TIME_SCALE=10` runs the simulation 10x faster (1-20; each tick runs that many fixed 0.1 s steps, so the physics are unchanged).

## Tests

- `npm test`: unit and server tests (vitest).
- `npm run test:coverage`: the same with v8 coverage (reports in `coverage/`; thresholds in `vitest.config.ts` act as a floor and fail the run on regression).
- `npm run typecheck`: `tsc --noEmit`.
- `npm run lint` / `npm run lint:fix`: ESLint 9 (typescript-eslint, type-aware).
- `npm run format:check` / `npm run format`: Prettier. Not yet enforced in CI.
- `npm run e2e`: runs four end-to-end scenarios (impostor-wins, tower-wins, lone-pilot, disconnect) in headless Chromium, each against its own server sped up with `FT_TIME_SCALE`, in about 2 minutes. `node e2e/smoke.mjs <name>` runs one, `--list` lists them. It needs Playwright with Chromium installed globally; Playwright is not a dependency of this project. Screenshots are written to `e2e/screenshots/` (gitignored), prefixed with the scenario name.

### Continuous integration

`.github/workflows/ci.yml` runs on pushes to `main` and on every pull request: typecheck + lint, unit tests with coverage (Node 20 and 22, coverage summary in the job summary and a `coverage` artifact), production build (`dist` artifact), the Playwright e2e round (installs Playwright 1.63.0 globally; `e2e-screenshots` artifact), and `npm audit` on production dependencies. The `CI OK` job aggregates all of them: make it the single required status check. Dependabot updates npm and GitHub Actions weekly.

## Project layout

```
src/shared/        wire protocol, world definition, pure simulation (no I/O)
src/server/        Node + ws: rooms, role assignment, 10 Hz tick loop, radio arbitration,
                   WebRTC signalling relay, static file serving of dist/client
src/client/        Vite + TypeScript + canvas, no framework: lobby, radar scope, cockpit
                   (PFD, HSI, autopilot panel), approach plate, round bar, end screen
src/client/voice/  WebRTC audio mesh and radio DSP, behind api.ts
e2e/               Playwright smoke test
DESIGN.md          game and architecture design
```

## Status / not done yet

- Voice is untested with real microphones across real networks. The e2e test only uses Chromium's fake audio device on one machine.
- Voice uses a public STUN server and has no TURN relay, so players behind restrictive NATs or firewalls may not connect.
- No Steam packaging yet. Planned: an Electron shell with Steamworks lobbies replacing room codes.
- Single airport (one runway, one ILS approach).
- No AI traffic: only the pilots' aircraft exist.
- No mid-round reconnect: a player who drops during a round cannot rejoin that round.
