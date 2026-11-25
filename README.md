# Fake Tower

[![CI](https://github.com/feetball/fake-tower/actions/workflows/ci.yml/badge.svg)](https://github.com/feetball/fake-tower/actions/workflows/ci.yml)

Two voices claim to be the tower. One is lying.

Fake Tower is a multiplayer social-deduction game for 4 to 8 players. Two players are air traffic controllers on one shared radio frequency and both claim to be the tower; one is real and one is an impostor trying to get the aircraft killed. The rest are pilots flying instrument approaches in fog and must work out, from procedure knowledge alone, which controller to obey. Everyone talks over one push-to-talk radio.

The game is a standalone Godot 4.5 project in [`game/`](game/) (GDScript, Forward+ renderer, 3D cockpit and radar room, in-game voice). The original browser version at the repo root is kept as the reference implementation; see [Browser prototype](#browser-prototype-reference-implementation) below. Game rules are in [DESIGN.md](DESIGN.md); the Godot project structure and contracts are in [game/ARCHITECTURE.md](game/ARCHITECTURE.md).

## Get a build

Every CI run that touches `game/` exports a Windows and a Linux build:

1. Open the repository's **Actions** tab, pick a run of the **CI** workflow (on `main`, or on a branch or pull request).
2. Under **Artifacts** download `fake-tower-windows` (contains `FakeTower.exe`, a single file with the data embedded, and `README.txt`) or `fake-tower-linux` (`FakeTower.x86_64` + `FakeTower.pck`, keep them together).
3. Unzip and run. The Windows build is unsigned, so SmartScreen may need "More info" > "Run anyway".

Builds are about 340 MB zipped because the project carries roughly 117 MB of CC0 textures, HDRIs, models and sounds. Pushing a tag `v*` (or running the **Release** workflow by hand) builds both and attaches `fake-tower-<tag>-windows.zip` and `fake-tower-<tag>-linux.zip` to a GitHub Release.

## Run from source

Requires [Godot 4.5.1](https://godotengine.org/download/archive/4.5.1-stable/) (standard build, not .NET). A GPU with Vulkan is needed for the full look (volumetric fog, Forward+).

```
godot --path game --import     # once: imports the assets (about 40 s)
godot --path game              # run the game (or open game/ in the editor and press F5)
```

Useful launch arguments (after `--`): `--demo=pilot`, `--demo=pilot_far`, `--demo=controller` start an offline round straight away; `--host`, `--join=<ip>`, `--name=<name>`, `--port=<n>`, `--autostart` are for scripted multi-instance tests.

## Play

- **Host**: main menu > Host Game. Others join with your IP address. The default port is **27270 (UDP)**; allow it through your firewall, and forward it on your router when playing over the internet (direct IP only for now).
- **Join**: main menu > Join Game, enter the host's IP (and port if changed).
- **Start**: the host starts the round from the lobby once at least 4 players are connected. Roles are random; the real controller and the impostor both see the radar, pilots never receive the impostor flag.
- **Solo practice**: main menu > Solo Practice, an offline round.
- **Radio**: hold `Space` to talk. One transmitter is heard through a radio filter; two at once block the frequency.
- **Full guide**: [game/HOW_TO_PLAY.md](game/HOW_TO_PLAY.md) is the player manual for the Godot game: radio, pilot and controller controls, flying the ILS 27, spotting (or playing) the impostor. Builds ship it as `HOW_TO_PLAY.md` next to the executable.
- **Controls**: pilots use the keyboard autopilot panel (`Left`/`Right` heading, `Up`/`Down` altitude, `PageUp`/`PageDown` speed, `[`/`]` altimeter, `A` approach mode, `G` gear, `F`/`Shift+F` flaps, `I` ATIS, `P` plate); controllers use the mouse on the scope. The full key list is in [game/ARCHITECTURE.md](game/ARCHITECTURE.md#input-actions-registered-in-code-by-session-at-startup) and the in-game How to Play screen.

## Tests and CI

All commands run from the repo root; set `GODOT` if `godot` is not on your PATH (the scripts default to `/home/user/tools/godot/godot`).

```
godot --headless --path game --import                       # import cache (needed once)
godot --headless --path game -s res://tests/run_tests.gd    # simulation, server, regression, parity, demo tests
godot --headless --path game -s res://tests/voice_test.gd   # voice codec, jitter buffer, radio DSP
game/tests/net_test.sh                                      # 1 host + 3 clients on localhost
game/tests/smoke_test.sh                                    # real main scene headless: menu, pilot, pilot_far, controller
game/tools/ci_check_log.sh <log>                            # fail on SCRIPT ERROR / Parse Error / failed loads
pip install gdtoolkit==4.5.0 && gdlint game                 # config: game/gdlintrc
game/tools/export_build.sh all --zip                        # needs the 4.5.1 export templates; output in build/dist
```

`.github/workflows/ci.yml` is one workflow with a `changes` job that decides which half of the repo is affected. Browser jobs run for root package files, `src/**`, `e2e/**`; game jobs run for `game/**` and the CI definitions. Skipped jobs count as passing; the final **CI OK** job fails if any job failed or was cancelled, so make it the single required status check. It runs on pushes to `main` and `claude/**`, on every pull request, and by hand (`workflow_dispatch`, which runs everything).

| Job | What it does |
| --- | --- |
| Game - import and script check | `godot --headless --import`, fails on script errors, parse errors and failed loads |
| Game - unit and voice tests | `run_tests.gd` and `voice_test.gd` |
| Game - network test | `net_test.sh`, 4 headless instances over localhost |
| Game - smoke test | main scene headless for 240 frames in menu, `--demo=pilot`, `--demo=pilot_far`, `--demo=controller`; fails if a view scene is missing |
| Game - GDScript lint | `gdlint` (formatting is reported by `gdformat --check` but not enforced yet) |
| Game - export | Windows and Linux release exports with the pinned official templates; artifacts `fake-tower-windows`, `fake-tower-linux` |

Godot 4.5.1 and the export templates are downloaded from the official `godot-builds` release, checked against pinned SHA-256 values and cached (`.github/actions/setup-godot`). Everything runs headless, so CI proves logic, scripts, networking and the export, but not how the game looks.

## Status / not done yet

- No Steam integration yet. Planned: GodotSteam lobbies and Steam networking replacing direct IP.
- Voice is untested with real microphones across real networks (only logic and codec tests run headless).
- Single airport (one runway, one ILS approach).
- The cockpit is procedural: no CC0 cockpit model exists, so panels and instruments are built in code.
- Rendering has only been verified under software Vulkan so far (no GPU hardware test), so performance and visuals on real GPUs are unconfirmed.
- Windows builds are unsigned and have no embedded icon; the Windows and Linux exports have been built but only the Linux export has been run (headless).
- Direct IP over ENet only: no NAT traversal or relay.

---

## Browser prototype (reference implementation)

The original version of the game runs in the browser (TypeScript, Node server, canvas). It is kept as the reference implementation of the simulation, and its tests are the source of the parity fixtures used by the Godot tests. Everything below describes that version.

### How to play (browser version)

#### Roles

Roles are assigned at random when the host starts the round.

- Real controller (1): sees the radar scope. Wins with the pilots.
- Impostor controller (1): sees the identical scope. Wins alone.
- Pilots (2 to 6): each flies one aircraft on instruments.

Everyone knows which two players are controllers. Only the controllers know which one is real; the server never sends the impostor flag to pilots.

#### Win condition

The round ends when no aircraft is still flying. The tower side (real controller and pilots) wins if strictly more than half of the aircraft landed. Otherwise the impostor wins. The end screen reveals the impostor and each aircraft's outcome.

#### The radio

There is one VHF frequency, push-to-talk. Hold `Space` to transmit (or hold the PTT button with the mouse).

- One player keying: everyone hears them through a radio filter.
- Two or more keying: the frequency is blocked and nobody hears speech.
- Crashed aircraft cannot transmit. Landed aircraft can still listen.
- Lobby and end screen use open mic.

#### Controller controls

Mouse (from the on-screen hint): wheel zooms, drag pans, double-click resets the view, right-drag or Shift-drag measures range and bearing, click selects a target. The toolbar toggles map layers and zooms (RR, CL, FIX, TERR, MSA, HOLD, PTL, HIST; RNG -/+; RESET).

Keyboard:

| Key | Action |
| --- | --- |
| `Space` | push-to-talk (hold) |
| `1`-`4`, `6`-`9` | with a target selected, set its data-tag leader direction (numpad layout: 8 north, 6 east, 2 south, 4 west, diagonals on 9/3/1/7) |
| `Esc` | clear selection / measuring line |

#### Pilot controls

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

### Run in development

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

### Build and run in production

```
npm run build
npm start
```

`npm start` runs the game server, which serves `dist/client` itself. `PORT` sets the listen port (default 8080); `FT_MIN_PLAYERS` is honoured here too. `FT_TIME_SCALE=10` runs the simulation 10x faster (1-20; each tick runs that many fixed 0.1 s steps, so the physics are unchanged).

### Tests

- `npm test`: unit and server tests (vitest).
- `npm run test:coverage`: the same with v8 coverage (reports in `coverage/`; thresholds in `vitest.config.ts` act as a floor and fail the run on regression).
- `npm run typecheck`: `tsc --noEmit`.
- `npm run lint` / `npm run lint:fix`: ESLint 9 (typescript-eslint, type-aware).
- `npm run format:check` / `npm run format`: Prettier. Not yet enforced in CI.
- `npm run e2e`: runs four end-to-end scenarios (impostor-wins, tower-wins, lone-pilot, disconnect) in headless Chromium, each against its own server sped up with `FT_TIME_SCALE`, in about 2 minutes. `node e2e/smoke.mjs <name>` runs one, `--list` lists them. It needs Playwright with Chromium installed globally; Playwright is not a dependency of this project. Screenshots are written to `e2e/screenshots/` (gitignored), prefixed with the scenario name.

#### Browser CI jobs

The web jobs live in `.github/workflows/ci.yml` and run only when browser files change (root package/config files, `src/**`, `e2e/**`, the workflow itself): typecheck + lint, unit tests with coverage (Node 20 and 22, coverage summary in the job summary and a `coverage` artifact), production build (`dist` artifact), the Playwright e2e round (installs Playwright 1.63.0 globally; `e2e-screenshots` artifact), and `npm audit` on production dependencies. Dependabot updates npm and GitHub Actions weekly.

### Project layout

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

### Status / not done yet (browser version)

- Voice is untested with real microphones across real networks. The e2e test only uses Chromium's fake audio device on one machine.
- Voice uses a public STUN server and has no TURN relay, so players behind restrictive NATs or firewalls may not connect.
- No Steam packaging yet. Planned: an Electron shell with Steamworks lobbies replacing room codes.
- Single airport (one runway, one ILS approach).
- No AI traffic: only the pilots' aircraft exist.
- No mid-round reconnect: a player who drops during a round cannot rejoin that round.
