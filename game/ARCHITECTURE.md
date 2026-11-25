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
  tests/       headless tests (run_tests.gd)
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
radar or the impostor flag).

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
host_game(player_name: String, port: int = DEFAULT_PORT) -> Error
join_game(player_name: String, address: String, port: int = DEFAULT_PORT) -> Error
leave() -> void                      back to "menu"
start_round() -> void                host only
return_to_lobby() -> void            host only
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
`DEFAULT_PORT = 27270`. Transport is ENet for now (LAN / direct IP);
`SteamMultiplayerPeer` replaces it for release without touching views.

Command-line user args (after `--`): `--demo=<role>` starts `start_demo(role)`
at launch; `--host`, `--join=<ip>`, `--name=<n>`, `--autostart` for scripted
multi-instance tests; `--shot=<png>` `--shot-after=<sec>` (core/shot_helper.gd).

## Autoload `Voice` (voice/voice.gd)

Self-contained. Listens to `Session` (phase, radio_tx, my_id) and uses its own
RPCs. API for the HUD:
```
mic_ok: bool
set_volume(v: float) -> void          0..1
input_level: float                    0..1, for a mic meter
signal status_changed()
```
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
`core/shot_helper.gd`.

## Visual direction

Night / heavy overcast, low visibility. Realistic, restrained, cinematic:
physically based materials, volumetric fog, bloom on lights and displays,
filmic tonemapping. No cartoon styling, no flat UI over the 3D where a diegetic
display can do the job. Reference mood: an airliner on a CAT I approach at
night breaking out at 200 ft into the approach lights; a dark TRACON room lit
only by scopes.
