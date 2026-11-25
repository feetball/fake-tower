# Asset catalog

All assets are CC0 1.0 from Poly Haven. See LICENSES.md for sources. Totals: 4 HDRIs, 13 PBR texture sets, 28 models.

## HDRIs (`hdri/`)

All 1k equirectangular Radiance .hdr (~1.4-1.7 MB each). Use as `PanoramaSkyMaterial` panorama, scale `Environment.background_energy_multiplier`/`ambient_light_energy` down (about 0.1-0.4) for dark night.

### night_overcast_fog_a
- File: `hdri/night_overcast_fog_a_1k.hdr` (1024x512 equirect HDR)
- What: Night, heavy overcast with mist/fog, low contrast, faint moon glow.
- Use: Primary ambient/reflection source for the foggy night approach (cockpit exterior, airport).

### night_overcast_b
- File: `hdri/night_overcast_b_1k.hdr` (1024x512 equirect HDR)
- What: Night, overcast, low contrast, soft moon glow behind cloud.
- Use: Alternate night sky for variety / mountain scenes.

### dusk_overcast_mist
- File: `hdri/dusk_overcast_mist_1k.hdr` (1024x512 equirect HDR)
- What: Dusk, overcast with mist, low contrast, brighter horizon.
- Use: Early-evening variant or lobby/ended-state background; darken via Environment energy.

### airport_dusk_apron
- File: `hdri/airport_dusk_apron_1k.hdr` (1024x512 equirect HDR)
- What: Real airport apron/runway backplate at dusk, low contrast; includes ground detail.
- Use: Reflection probe for apron/tower scenes; too bright for night, scale down energy or use only for reflections.

## PBR texture sets (`textures/<set>/`)

All 2048x2048 JPG (quality 82-85). Files: `<set>_albedo_2k.jpg` (sRGB), `<set>_normal_gl_2k.jpg` (OpenGL/Y+ normal, correct for Godot), `<set>_arm_2k.jpg` (R=ambient occlusion, G=roughness, B=metallic). In Godot StandardMaterial3D set `ao_texture` channel Red, `roughness_texture` channel Green, `metallic_texture` channel Blue, all from the ARM file; enable Normal Map. A separate roughness map and displacement were skipped to save space (roughness is in ARM.G).

### asphalt_runway
- Source: Poly Haven `asphalt_02`
- What: Clean dark runway asphalt, ~3 m tile.
- Files: `asphalt_runway_albedo_2k.jpg`, `asphalt_runway_normal_gl_2k.jpg`, `asphalt_runway_arm_2k.jpg`
- Use: Runway surface base; add painted markings via decals/overlay.

### asphalt_worn
- Source: Poly Haven `worn_asphalt`
- What: Worn asphalt with wear/cracks, 2 m tile.
- Files: `asphalt_worn_albedo_2k.jpg`, `asphalt_worn_normal_gl_2k.jpg`, `asphalt_worn_arm_2k.jpg`
- Use: Taxiways, runway touchdown zone variation, rubber-streak look with a darkening overlay.

### concrete_apron
- Source: Poly Haven `concrete_floor_worn_001`
- What: Worn concrete slab floor, 3 m tile.
- Files: `concrete_apron_albedo_2k.jpg`, `concrete_apron_normal_gl_2k.jpg`, `concrete_apron_arm_2k.jpg`
- Use: Apron, hardstanding, tower base.

### grass_field
- Source: Poly Haven `sparse_grass`
- What: Sparse grass ground, 2 m tile.
- Files: `grass_field_albedo_2k.jpg`, `grass_field_normal_gl_2k.jpg`, `grass_field_arm_2k.jpg`
- Use: Airfield fields and verges (darken heavily for night).

### rock_cliff
- Source: Poly Haven `rock_face`
- What: Rock face, 2.4 m tile.
- Files: `rock_cliff_albedo_2k.jpg`, `rock_cliff_normal_gl_2k.jpg`, `rock_cliff_arm_2k.jpg`
- Use: Mountain cliffs/steep slopes (triplanar).

### forest_ground
- Source: Poly Haven `forest_ground_04`
- What: Forest floor with leaves/needles, 3 m tile.
- Files: `forest_ground_albedo_2k.jpg`, `forest_ground_normal_gl_2k.jpg`, `forest_ground_arm_2k.jpg`
- Use: Lower mountain slopes, tree-line ground.

### scree_rocky
- Source: Poly Haven `rocky_terrain_02`
- What: Rocky terrain/scree, large tile.
- Files: `scree_rocky_albedo_2k.jpg`, `scree_rocky_normal_gl_2k.jpg`, `scree_rocky_arm_2k.jpg`
- Use: Mountain terrain mid-slopes, scree.

### metal_plate_painted
- Source: Poly Haven `metal_plate_02`
- What: Painted/worn metal plate, 2 m tile.
- Files: `metal_plate_painted_albedo_2k.jpg`, `metal_plate_painted_normal_gl_2k.jpg`, `metal_plate_painted_arm_2k.jpg`
- Use: Cockpit panels, console housings, tower structure.

### metal_plate_blue
- Source: Poly Haven `blue_metal_plate`
- What: Blue painted metal plate, 2.5 m tile.
- Files: `metal_plate_blue_albedo_2k.jpg`, `metal_plate_blue_normal_gl_2k.jpg`, `metal_plate_blue_arm_2k.jpg`
- Use: Accent panel, equipment cabinets (albedo can be darkened).

### rubber_dark_trim
- Source: Poly Haven `rubber_tiles`
- What: Dark grained rubber floor tiles, 2 m tile.
- Files: `rubber_dark_trim_albedo_2k.jpg`, `rubber_dark_trim_normal_gl_2k.jpg`, `rubber_dark_trim_arm_2k.jpg`
- Use: Stand-in for dark grained plastic: cockpit/console trim, mats. Closest CC0 match; ambientCG plastics could not be downloaded.

### leather_seat_brown
- Source: Poly Haven `fabric_leather_01`
- What: Brown leather, 0.4 m tile.
- Files: `leather_seat_brown_albedo_2k.jpg`, `leather_seat_brown_normal_gl_2k.jpg`, `leather_seat_brown_arm_2k.jpg`
- Use: Seat, glareshield padding (darken albedo for night).

### leather_seat_02
- Source: Poly Haven `fabric_leather_02`
- What: Leather variant, 0.5 m tile.
- Files: `leather_seat_02_albedo_2k.jpg`, `leather_seat_02_normal_gl_2k.jpg`, `leather_seat_02_arm_2k.jpg`
- Use: Alternate seat/armrest leather.

### carpet_dirty
- Source: Poly Haven `dirty_carpet`
- What: Dirty dark carpet, 0.6 m tile.
- Files: `carpet_dirty_albedo_2k.jpg`, `carpet_dirty_normal_gl_2k.jpg`, `carpet_dirty_arm_2k.jpg`
- Use: Control room floor.

## Models (`models/<name>/`)

glTF 2.0 (`<name>.gltf` + `.bin` + `textures/*.jpg` at 1k). Dimensions in metres are as authored by Poly Haven (scale 1 unit = 1 m). Textures reference relative paths; keep folder structure intact.

### binoculars
- Source: Poly Haven `binoculars`; ~19248 tris; approx dims 0.17 x 0.29 x 0.08 m
- Files: `binoculars.gltf`, `binoculars.bin`, `textures/` (binoculars_arm_1k.jpg, binoculars_diff_1k.jpg, binoculars_nor_gl_1k.jpg)
- Use: Atmosphere prop for tower/control room desk.

### classic_laptop
- Source: Poly Haven `classic_laptop`; ~14450 tris; approx dims 0.65 x 0.49 x 0.54 m
- Files: `classic_laptop.gltf`, `classic_laptop.bin`, `textures/` (classic_laptop_arm_1k.jpg, classic_laptop_diff_1k.jpg, classic_laptop_nor_gl_1k.jpg)
- Use: Controller laptop / small display prop (screen surface can take a ViewportTexture).

### clipboard
- Source: Poly Haven `clipboard`; ~6176 tris; approx dims 0.23 x 0.34 x 0.04 m
- Files: `clipboard.gltf`, `clipboard.bin`, `textures/` (clipboard_arm_1k.jpg, clipboard_diff_1k.jpg, clipboard_nor_gl_1k.jpg)
- Use: Control-room desk prop.

### concrete_road_barrier
- Source: Poly Haven `concrete_road_barrier`; ~80776 tris; approx dims 1.55 x 0.64 x 0.84 m
- Files: `concrete_road_barrier.gltf`, `concrete_road_barrier.bin`, `textures/` (concrete_road_barrier_arm_1k.jpg, concrete_road_barrier_diff_1k.jpg, concrete_road_barrier_nor_gl_1k.jpg)
- Use: Airfield perimeter barrier (81k tris, heavy; use few).

### desk_lamp_arm_01
- Source: Poly Haven `desk_lamp_arm_01`; ~25710 tris; approx dims 0.62 x 0.41 x 0.88 m
- Files: `desk_lamp_arm_01.gltf`, `desk_lamp_arm_01.bin`, `textures/` (desk_lamp_arm_01_arm_1k.jpg, desk_lamp_arm_01_diff_1k.jpg, desk_lamp_arm_01_nor_gl_1k.jpg)
- Use: Desk lamp for control room consoles (low-power warm light).

### hanging_industrial_lamp
- Source: Poly Haven `hanging_industrial_lamp`; ~9530 tris; approx dims 0.55 x 0.55 x 1.36 m
- Files: `hanging_industrial_lamp.gltf`, `hanging_industrial_lamp.bin`, `textures/` (hanging_industrial_lamp_arm_1k.jpg, hanging_industrial_lamp_diff_1k.jpg, hanging_industrial_lamp_emissive_1k.jpg, hanging_industrial_lamp_glass_nor_gl_1k.jpg, hanging_industrial_lamp_nor_gl_1k.jpg)
- Use: Hangar/apron overhead lamp.

### industrial_wall_lamp
- Source: Poly Haven `industrial_wall_lamp`; ~4446 tris; approx dims 0.27 x 0.14 x 0.43 m
- Files: `industrial_wall_lamp.gltf`, `industrial_wall_lamp.bin`, `textures/` (industrial_wall_lamp_arm_1k.jpg, industrial_wall_lamp_diff_1k.jpg, industrial_wall_lamp_emissive_1k.jpg, industrial_wall_lamp_glass_arm_1k.jpg, industrial_wall_lamp_glass_diff_1k.jpg, industrial_wall_lamp_glass_nor_gl_1k.jpg, industrial_wall_lamp_nor_gl_1k.jpg)
- Use: Wall lamp for tower base/hangar.

### lateral_sea_marker
- Source: Poly Haven `lateral_sea_marker`; ~13014 tris; approx dims 3.00 x 3.00 x 6.84 m
- Files: `lateral_sea_marker.gltf`, `lateral_sea_marker.bin`, `textures/` (lateral_sea_marker_arm_1k.jpg, lateral_sea_marker_diff_1k.jpg, lateral_sea_marker_nor_gl_1k.jpg)
- Use: Navigation marker; with emission added, a rough stand-in for a beacon/mast near the airfield.

### metal_jerrycan
- Source: Poly Haven `metal_jerrycan`; ~20022 tris; approx dims 0.35 x 0.17 x 0.46 m
- Files: `metal_jerrycan.gltf`, `metal_jerrycan.bin`, `textures/` (metal_jerrycan_arm_1k.jpg, metal_jerrycan_diff_1k.jpg, metal_jerrycan_nor_gl_1k.jpg)
- Use: Fuel/utility prop on apron.

### metal_office_desk
- Source: Poly Haven `metal_office_desk`; ~6898 tris; approx dims 2.00 x 0.95 x 0.79 m
- Files: `metal_office_desk.gltf`, `metal_office_desk.bin`, `textures/` (metal_office_desk_arm_1k.jpg, metal_office_desk_diff_1k.jpg, metal_office_desk_nor_gl_1k.jpg)
- Use: Control room desk/console base; place monitors on top.

### metal_stool_01
- Source: Poly Haven `metal_stool_01`; ~8334 tris; approx dims 0.35 x 0.35 x 0.88 m
- Files: `metal_stool_01.gltf`, `metal_stool_01.bin`, `textures/` (metal_stool_01_arm_1k.jpg, metal_stool_01_diff_1k.jpg, metal_stool_01_nor_gl_1k.jpg)
- Use: Stool for control room.

### modern_arm_chair_01
- Source: Poly Haven `modern_arm_chair_01`; ~8916 tris; approx dims 0.82 x 0.99 x 1.02 m
- Files: `modern_arm_chair_01.gltf`, `modern_arm_chair_01.bin`, `textures/` (modern_arm_chair_01_legs_arm_1k.jpg, modern_arm_chair_01_legs_diff_1k.jpg, modern_arm_chair_01_legs_nor_gl_1k.jpg, modern_arm_chair_01_pillow_arm_1k.jpg, modern_arm_chair_01_pillow_diff_1k.jpg, modern_arm_chair_01_pillow_nor_gl_1k.jpg)
- Use: Seat prop; closest CC0 office chair for the control room.

### mountainside
- Source: Poly Haven `mountainside`; ~287755 tris; approx dims 10.21 x 5.25 x 10.53 m
- Files: `mountainside.gltf`, `mountainside.bin`, `textures/` (mountainside_arm_1k.jpg, mountainside_diff_1k.jpg, mountainside_nor_gl_1k.jpg)
- Use: Large photoscanned mountainside (288k tris) as a distant mountain backdrop (fog hides detail).

### mounted_fluorescent_lights
- Source: Poly Haven `mounted_fluorescent_lights`; ~17820 tris; approx dims 0.91 x 0.65 x 0.04 m
- Files: `mounted_fluorescent_lights.gltf`, `mounted_fluorescent_lights.bin`, `textures/` (mounted_fluorescent_lights_arm_1k.jpg, mounted_fluorescent_lights_diff_1k.jpg, mounted_fluorescent_lights_emission_1k.jpg, mounted_fluorescent_lights_nor_gl_1k.jpg)
- Use: Ceiling light strip for control room (assign dim emissive).

### namaqualand_boulder_02
- Source: Poly Haven `namaqualand_boulder_02`; ~183681 tris; approx dims 2.53 x 1.23 x 0.88 m
- Files: `namaqualand_boulder_02.gltf`, `namaqualand_boulder_02.bin`, `textures/` (namaqualand_boulder_02_arm_1k.jpg, namaqualand_boulder_02_diff_1k.jpg, namaqualand_boulder_02_nor_gl_1k.jpg)
- Use: Boulder (184k tris; heavy, use sparingly).

### namaqualand_cliff_01
- Source: Poly Haven `namaqualand_cliff_01`; ~176938 tris; approx dims 8.28 x 4.39 x 4.96 m
- Files: `namaqualand_cliff_01.gltf`, `namaqualand_cliff_01.bin`, `textures/` (namaqualand_cliff_01_arm_1k.jpg, namaqualand_cliff_01_diff_1k.jpg, namaqualand_cliff_01_nor_gl_1k.jpg)
- Use: Mountain cliff chunk (177k tris; use sparingly, distant, or with LOD).

### plastic_monobloc_chair_01
- Source: Poly Haven `plastic_monobloc_chair_01`; ~3356 tris; approx dims 0.64 x 0.63 x 0.88 m
- Files: `plastic_monobloc_chair_01.gltf`, `plastic_monobloc_chair_01.bin`, `textures/` (plastic_monobloc_chair_01_arm_1k.jpg, plastic_monobloc_chair_01_diff_1k.jpg, plastic_monobloc_chair_01_nor_gl_1k.jpg)
- Use: Cheap chair for control room or apron.

### plastic_thermos
- Source: Poly Haven `plastic_thermos`; ~5514 tris; approx dims 0.14 x 0.11 x 0.32 m
- Files: `plastic_thermos.gltf`, `plastic_thermos.bin`, `textures/` (plastic_thermos_arm_1k.jpg, plastic_thermos_diff_1k.jpg, plastic_thermos_nor_gl_1k.jpg)
- Use: Control-room desk clutter.

### portable_searchlight
- Source: Poly Haven `portable_searchlight`; ~18802 tris; approx dims 0.17 x 0.25 x 0.19 m
- Files: `portable_searchlight.gltf`, `portable_searchlight.bin`, `textures/` (portable_searchlight_arm_1k.jpg, portable_searchlight_diff_1k.jpg, portable_searchlight_nor_gl_1k.jpg)
- Use: Apron/utility light prop.

### power_box_01
- Source: Poly Haven `power_box_01`; ~21272 tris; approx dims 0.38 x 0.42 x 0.50 m
- Files: `power_box_01.gltf`, `power_box_01.bin`, `textures/` (power_box_01_arm_1k.jpg, power_box_01_diff_1k.jpg, power_box_01_nor_gl_1k.jpg)
- Use: Electrical cabinet; airfield equipment.

### propane_tank
- Source: Poly Haven `propane_tank`; ~5238 tris; approx dims 0.34 x 0.34 x 0.55 m
- Files: `propane_tank.gltf`, `propane_tank.bin`, `textures/` (propane_tank_arm_1k.jpg, propane_tank_diff_1k.jpg, propane_tank_nor_gl_1k.jpg)
- Use: Utility prop at airfield.

### rock_07
- Source: Poly Haven `rock_07`; ~27830 tris; approx dims 0.17 x 0.32 x 0.14 m
- Files: `rock_07.gltf`, `rock_07.bin`, `textures/` (rock_07_arm_1k.jpg, rock_07_diff_1k.jpg, rock_07_nor_gl_1k.jpg)
- Use: Small rock for mountain slopes (28k tris).

### security_camera_01
- Source: Poly Haven `security_camera_01`; ~13571 tris; approx dims 0.17 x 0.55 x 0.29 m
- Files: `security_camera_01.gltf`, `security_camera_01.bin`, `textures/` (security_camera_01_arm_1k.jpg, security_camera_01_diff_1k.jpg, security_camera_01_nor_gl_1k.jpg)
- Use: Tower / building exterior prop.

### steel_frame_shelves_01
- Source: Poly Haven `steel_frame_shelves_01`; ~4348 tris; approx dims 1.10 x 0.50 x 2.14 m
- Files: `steel_frame_shelves_01.gltf`, `steel_frame_shelves_01.bin`, `textures/` (steel_frame_shelves_01_arm_1k.jpg, steel_frame_shelves_01_diff_1k.jpg, steel_frame_shelves_01_nor_gl_1k.jpg)
- Use: Control room equipment shelving.

### street_lamp_01
- Source: Poly Haven `street_lamp_01`; ~30610 tris; approx dims 0.70 x 0.39 x 3.87 m
- Files: `street_lamp_01.gltf`, `street_lamp_01.bin`, `textures/` (street_lamp_01_arm_1k.jpg, street_lamp_01_diff_1k.jpg, street_lamp_01_nor_gl_1k.jpg)
- Use: Apron/perimeter lamp post (3.9 m tall), emissive head for night.

### television_01
- Source: Poly Haven `Television_01`; ~1918 tris; approx dims 0.60 x 0.47 x 0.46 m
- Files: `television_01.gltf`, `television_01.bin`, `textures/` (Television_01_arm_1k.jpg, Television_01_diff_1k.jpg, Television_01_nor_gl_1k.jpg)
- Use: CRT-style monitor body; screen mesh can host a SubViewport scope display.

### utility_box_01
- Source: Poly Haven `utility_box_01`; ~4404 tris; approx dims 0.52 x 0.43 x 1.12 m
- Files: `utility_box_01.gltf`, `utility_box_01.bin`, `textures/` (utility_box_01_arm_1k.jpg, utility_box_01_diff_1k.jpg, utility_box_01_nor_gl_1k.jpg)
- Use: Airfield utility cabinet.

### wetfloorsign_01
- Source: Poly Haven `WetFloorSign_01`; ~228 tris; approx dims 0.30 x 0.36 x 0.63 m
- Files: `wetfloorsign_01.gltf`, `wetfloorsign_01.bin`, `textures/` (WetFloorSign_01_arm_1k.jpg, WetFloorSign_01_diff_1k.jpg, WetFloorSign_01_nor_gl_1k.jpg)
- Use: Control room or terminal prop (228 tris).

## Not found as CC0 (build procedurally)

Searched Poly Haven (all 522 models) and ambientCG (materials only; it has no models) for these; none exist. Do not substitute non-CC0 sources.

- Aircraft / airliner exterior: none on Poly Haven. Build procedurally (or leave invisible: the pilot sees only the cockpit view).
- Cockpit, yoke, sidestick, throttle quadrant, instrument panel: none. Build from boxes/CSG with the metal/rubber/leather textures; displays are diegetic SubViewports.
- Runway lights, approach light bars, PAPI/ALS, taxiway edge lights: none. Build as small emissive meshes + OmniLight/fog glow sprites (multimesh instancing).
- Control tower / terminal / hangar buildings: none suitable (only `modular_factory_facade`, apartments facade; not downloaded). Build procedurally.
- Orange traffic cones/barriers: none (only `concrete_road_barrier`, `WetFloorSign_01`).
- Trees: Poly Haven has `pine_tree_01`, `fir_tree_01`, `fir_sapling_medium`, `tree_small_02`, `island_tree_01` etc. but their glTF payloads are 22 MB to 900 MB (4k geometry bin), exceeding the size budget; not included. Use procedural cone/billboard trees or MultiMesh.
- Computer monitor (flat), keyboard, headset, microphone, mug: none exist on Poly Haven (only `television_01/02`, `classic_laptop`, `Megaphone_01`). Build monitors as boxes with a screen quad; headset/mic procedurally. `Megaphone_01` and `television_02` exist on Poly Haven but were not downloaded (tool error/skipped).
- ambientCG textures (glass fingerprints/smears/scratches, plastic, acoustic foam, wet asphalt): the ambientCG API is reachable but its download CDN (acg-download.struffelproductions.com) is blocked in this environment, so no ambientCG textures were obtained. Generate display glass smudge/scratch overlays procedurally (noise) and wet look by lowering roughness/adding specular on the asphalt materials (no CC0 wet-asphalt set from Poly Haven). Acoustic panel/foam: none downloaded.
- Kenney.nl: returns 403, skipped.
