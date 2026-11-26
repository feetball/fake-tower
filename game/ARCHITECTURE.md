# Fake Tower (Godot) — architecture and contract

Standalone Godot 4.5 game (GDScript, Forward+). Game rules are in `../DESIGN.md`
and are unchanged; this file defines how the Godot project is put together. The
TypeScript version in the repo root is the reference implementation of the
simulation and its tests.

Everything below is a contract between independently written parts. Do not
change names or shapes here without updating this file.

## Layout

```
game/
  project.godot
  core/        world.gd, session.gd, sim/ (pure simulation), net glue, shot_helper.gd
  voice/       voice.gd (autoload) + codec + radio DSP
  scenes/
    main.tscn            root: swaps screens on Session.phase / role, hosts the HUD
    menu/                main menu + lobby
    pilot/               pilot_view.tscn  — 3D cockpit, outside world, instruments
    controller/          controller_view.tscn — radar room and scope
    hud/                 radio_hud.tscn — PTT, radio state, role banner (shared overlay)
    end/                 end_screen.tscn
  assets/      CC0 textures/HDRIs/models/sounds + LICENSES.md + CATALOG.md
  tests/       headless tests (run_tests.gd, voice_test.gd, net_test.sh, ws_net_test.sh, smoke_test.sh)
  tools/       shot.sh (off-screen screenshot), export scripts
```

## Units and coordinates

Simulation units are aviation units, identical to the TypeScript version:
distance nm, altitude ft MSL, speed kt, heading degrees true (0–359), time s,
pressure hPa. Sim coordinates: `x` = nm east, `y` = nm north of the runway 27
threshold.

3D scenes use metres, Godot axes (Y up, −Z forward). Mapping, used everywhere:

```
godot.x =  sim.x * 1852.0        (east)
godot.z = -sim.y * 1852.0        (north is −Z)
godot.y =  alt_ft * 0.3048       (MSL; the runway surface is at field elevation)
heading h (deg true) -> rotation.y = -deg_to_rad(h)   (0 = north = −Z)
```

`World.to_3d(x_nm, y_nm, alt_ft) -> Vector3` implements this.

## Data shapes (Dictionaries, snake_case keys)

Same fields as `src/shared/protocol.ts`, snake_cased.

`world` — `World.DATA` (see `core/world.gd`).

`atis` — `{letter, runway, qnh, wind_dir, wind_kt, visibility_m, ceiling_ft, text}`

`player` (lobby) — `{id:int, name:String, host:bool, connected:bool}`
(`host` marks the lobby leader: the player-host, or on a dedicated server the
first-joined player. The `room` payload around the list is `{phase, players}` plus
`dedicated: true` when the host is a dedicated server.)

`round_player` — `{id:int, name, role:"controller"|"pilot", callsign:String}` (callsign "" for controllers)

`own` (pilot's own aircraft, 10 Hz) —
```
callsign, status:"flying"|"landed"|"crashed", outcome:""|"landed"|"terrain"|"collision"|"fuel"|"runway",
hdg, ias, ind_alt, rad_alt (float, or null above 2500 ft AGL), vs, fuel_min,
dme, bearing_to_station, loc_dev (float dots or null), gs_dev (float dots or null),
sel_hdg, sel_alt, sel_spd, app_armed:bool, ap_mode:"HDG"|"LOC"|"APP", gs_captured:bool,
gear_down:bool, flaps:int 0..3, alt_setting, warnings:Array[String],
# added for the 3D view (not shown to the pilot as data):
x, y, alt_true, gs (ground speed kt), pitch_deg, bank_deg, on_ground:bool, time (round seconds)
```
After a successful landing the sim keeps moving the aircraft (flare, touchdown,
rollout to a stop on the runway) with `status == "landed"` so the view can show it.
After a crash the last state is frozen.

`radar target` (controllers, one sweep every 2 s) —
`{callsign, x, y, alt, gs, track, vs_trend:-1|0|1, status, conflict:bool, msaw:bool}`

`event` — `{time, kind (an outcome string), callsigns:Array[String]}`

`result` — `{winner:"tower"|"impostor", real_controller_id:int, impostor_id:int, outcomes:[{callsign, player_id, outcome}], duration_sec}`
(ids are 0 when the role does not exist in a reduced test game).

`ap` command — any subset of `{hdg, alt, spd, app:bool, gear:bool, flaps:int, alt_setting}`.

## Autoload `Session` (core/session.gd)

The only thing views talk to. Host-authoritative: the host's instance runs the
simulation; clients receive only what their role may see (pilots never receive
radar or the impostor flag). The host is either a player (`host_game`) or a
dedicated server that is not a player (`start_server`, `--server`, see SERVER.md).

State (read-only for views):
```
phase: String            "menu" | "lobby" | "playing" | "ended"
my_id: int
my_name: String
is_host: bool
players: Array[Dictionary]
round_players: Array[Dictionary]
my_role: String          "" | "controller" | "pilot"
i_am_impostor: bool
my_callsign: String
world: Dictionary
atis: Dictionary
own: Dictionary          latest own-aircraft state ({} if not a pilot)
radar: Array[Dictionary] latest sweep ([] if not a controller)
radio_tx: Array[int]     ids keying the frequency; size >= 2 means blocked
events: Array[Dictionary]
result: Dictionary
round_time: float
min_players: int
# added for transports / dedicated server (all read-only):
is_leader: bool          may start the round / return to the lobby (player-host, or the
                         dedicated server's leader: first-joined, handed on when they leave)
is_dedicated: bool       this instance is a dedicated server (is_host, not a player)
server_dedicated: bool   client: the host we joined is a dedicated server
transport: String        client "enet" | "ws"; host "enet+ws" (or one); "" offline
server_address: String   client: "host:port" or the ws(s):// URL joined
listen_port: int         host: ENet UDP port (0 = off)
listen_ws_port: int      host: WebSocket TCP port (0 = off)
autostart_at: int        dedicated: start when this many players are in (0 = leader starts)
lobby_after: float       dedicated + autostart_at: seconds from round end back to lobby
```
Signals:
```
lobby_changed()
round_began()
own_updated(ac: Dictionary)
radar_swept(targets: Array)
radio_changed(tx: Array)
round_event(event: Dictionary)
round_ended(result: Dictionary)
phase_changed(phase: String)
error(msg: String)
connection_lost()
```
Methods:
```
host_game(player_name: String, port: int = DEFAULT_PORT, ws_port: int = DEFAULT_WS_PORT) -> Error
                                     listens on ENet UDP `port` AND WebSocket TCP `ws_port`
                                     at once (0 turns one off); ERR_UNAVAILABLE on the web
join_game(player_name: String, address: String, port: int = DEFAULT_PORT,
          transport_pref: String = "auto") -> Error
                                     address: host | host:port | [v6]:port | ws://… | wss://…
                                     (http(s):// = ws(s)://, enet://host[:port] forces ENet);
                                     `port` applies when the address has none. A bare host
                                     goes over ENet on desktop/mobile, WebSocket on the web
                                     (port DEFAULT_WS_PORT while `port` is left at
                                     DEFAULT_PORT; on an https page wss://host, i.e. a TLS
                                     proxy on 443). transport_pref "enet" | "ws" forces one.
                                     Parsing: core/net/address.gd (pure, unit-tested).
start_server(port: int = DEFAULT_PORT, ws_port: int = DEFAULT_WS_PORT) -> Error
                                     dedicated server: runs the room, is not a player
leave() -> void                      back to "menu"
start_round() -> void                leader only (a dedicated server's leader asks the server)
return_to_lobby() -> void            leader only
send_ap(changes: Dictionary) -> void pilot only
set_ptt(on: bool) -> void
start_demo(role: String) -> void     offline round for development and screenshots:
                                     "pilot" = you fly one aircraft, starting established
                                     on a 12 nm final at the platform altitude, plus AI traffic;
                                     "controller" = scope with 4 scripted AI aircraft.
                                     "pilot_far" = pilot spawned normally at an arrival gate.
player_name(id: int) -> String
callsign_of(id: int) -> String
```
`DEFAULT_PORT = 27270` (ENet, UDP), `DEFAULT_WS_PORT = 27271` (WebSocket, TCP).

Transports. Browsers can only use WebSocket and cannot listen; phones usually
cannot accept inbound connections. So a host (player-host or dedicated server)
listens on both at once: `core/net/multi_server_peer.gd` is a
`MultiplayerPeerExtension` that wraps an `ENetMultiplayerPeer` server and a
`WebSocketMultiplayerPeer` server behind the one peer SceneMultiplayer takes,
passing peer ids through unchanged (an id clash across transports is refused), so
`get_remote_sender_id()`, Room ids and clients' `get_unique_id()` agree. Clients
use a plain `ENetMultiplayerPeer` or `WebSocketMultiplayerPeer`. Over WebSocket every
channel is reliable and ordered (TCP); the RPC channels/modes are unchanged.
`SteamMultiplayerPeer` can still replace either without touching views.

Dedicated server (`start_server`): `my_id` 1, `is_host` and `is_dedicated` true,
never in the room, so it has no role, aircraft or callsign and role assignment and
the result only cover players. Session mirrors the room into `phase`, `players`,
`radio_tx`, `round_players` and `result` (and emits the usual signals) so Voice's
relay rule and the server log work. The room resets when everyone has left.

Launch options. Command-line user args (after `--`): `--demo=<role>` starts
`start_demo(role)` at launch; `--host`, `--join=<addr>` (any join_game address),
`--name=<n>`, `--port=<p>` (ENet), `--ws-port=<p>` (default 27271, or `--port`+1
when only `--port` is given; 0 = off), `--min-players=<n>`, `--autostart` (the
leader starts once min-players are in) for scripted multi-instance tests;
`--server` [`--autostart-at=<n>`] [`--lobby-after=<sec>`] for the dedicated server
(SERVER.md; an export with the `dedicated_server` feature tag runs as one too);
`--net-test`, `--time-scale=<k>` (net tests only); `--shot=<png>`
`--shot-after=<sec>` (core/shot_helper.gd). On the web the page URL's query string
is read as well, e.g. `?demo=pilot&name=X&join=wss://host`; only `demo`, `join`,
`name`, `port`, `ws-port`, `autostart`, `min-players` are honoured there
(core/net/launch_args.gd, `LaunchArgs.current()`).

## Autoload `Voice` (voice/voice.gd)

Self-contained. Listens to `Session` (phase, radio_tx, my_id) and uses its own
RPCs. API for the HUD:
```
mic_ok: bool
set_volume(v: float) -> void          0..1
input_level: float                    0..1, for a mic meter
signal status_changed()
# added:
mic_state: String                     why the mic is (not) working: "ok" | "idle" | "starting" |
                                      "asking" | "denied" | "no_signal" | "no_signal_web" |
                                      "insecure" | "no_device" | "disabled" | "server"
mic_status: String                    the matching one-line text for the UI
rx_counts: Dictionary                 voice packets received per sender id (diagnostics/tests)
debug_send_tone(n: int) -> void       test hook: n tone packets through the normal send path
```
Capture never blocks play: with no device, input disabled, a denied permission, a
non-secure web page or no signal, `mic_ok` stays false and the player listens
only. Android asks for `RECORD_AUDIO` and iOS 17+ for record permission
(`OS.request_permission`) when capture first starts (entering the lobby); the
browser asks by itself on the first capture (getUserMedia, https or localhost
only). All Voice players use stream playback (web exports default to sample
playback, which bypasses bus effects). On a dedicated server Voice only relays.
Lobby/ended = open mic, clean. Playing = one VHF frequency, PTT, radio DSP,
squelch, heterodyne squeal when blocked (`Session.radio_tx.size() >= 2`).

## Input actions (registered in code by Session at startup)

`ptt` (Space) and, for the pilot: `hdg_left/right` (Left/Right, Shift = ×10),
`alt_up/down` (Up/Down, Shift = ×1000), `spd_up/down` (PageUp/PageDown),
`baro_down/up` ([ / ]), `baro_std` (B), `toggle_app` (A), `toggle_gear` (G),
`flaps_down` (F), `flaps_up` (Shift+F), `show_atis` (I), `show_plate` (P).

## Screenshots without a GPU

`tools/shot.sh out.png 4 res://scenes/pilot/pilot_view.tscn -- --demo=pilot`
runs Godot under Xvfb with software Vulkan (slow: several seconds per frame
with volumetric fog) and saves a 1920×1080 PNG. Every runnable scene includes
`core/shot_helper.gd`. `RENDERER=mobile|gl_compatibility tools/shot.sh ...` renders
with the other renderers (Compatibility through OpenGL/llvmpipe), and
`tools/platform_shots.sh` shoots every screen under all three into
`shots/plat_<renderer>_<scene>.png`.

## Platforms and renderers (`world3d/render_caps.gd`, class `RenderCaps`)

| Platform | Renderer | Default quality |
|---|---|---|
| Windows, Linux, macOS | Forward+ (`renderer/rendering_method`) | high |
| Android, iOS | Mobile (`rendering_method.mobile`) | low |
| Web (WebGL 2, single-threaded build) | Compatibility (`rendering_method.web`) | low |

Views never test renderer names: they ask `RenderCaps` (`has_volumetric_fog()`,
`has_fog_volumes()`, `has_ssr()`, `has_ssao()`, `has_compute_effects()`,
`is_compatibility()`, `quality()`). Without volumetric fog,
`RenderCaps.enable_volumetric_fog(env)` folds the medium into lit depth fog and
`FogGlow` (scenes/menu/backdrop) draws soft glow sprites for the lights that lit the
fog. Shaders branch on `CURRENT_RENDERER == RENDERER_COMPATIBILITY` where GLES3
differs (depth NDC z in −1..1, no screen-texture mipmaps, coarse 24-bit depth).
Quality tier: `--quality=low|medium|high` (or `--pilot-quality=`) overrides the
default. On the web the page URL carries launch args: session keys via
`core/net/launch_args.gd`, view/debug keys (`pilot-*`, `ctrl-*`, `ui-*`,
`quality`) via the HTML shell `tools/web/shell.html`. Exports: `tools/export_build.sh
<windows|linux|web|macos|android|ios>`.

## Visual direction

Night / heavy overcast, low visibility. Realistic, restrained, cinematic:
physically based materials, volumetric fog, bloom on lights and displays,
filmic tonemapping. No cartoon styling, no flat UI over the 3D where a diegetic
display can do the job. Reference mood: an airliner on a CAT I approach at
night breaking out at 200 ft into the approach lights; a dark TRACON room lit
only by scopes.
