# CALLOFBRAWL

A **mobile-first, 5 v 5 Team Deathmatch FPS** built with **Godot 4 / GDScript 2.0**, played
inside the provided `de_dust2` map, with the provided soldier and AK-47 assets.

Open `project.godot` in Godot 4.3 or newer and press **F5**.

---

## 1. Gameplay at a glance

| Rule | Value |
|---|---|
| Mode | Team Deathmatch, Alpha vs Bravo |
| Team size | 5 v 5 — you + 4 friendly bots vs 5 enemy bots |
| Score limit | 50 kills (configurable 10–100 in Settings) |
| Match time | 10 minutes (configurable 3–20) |
| Respawn | 3 s (configurable 0–8 s), at a clear team spawn |
| Friendly fire | **off** — blocked in the damage path, not just "counted as 0" |
| Score source | enemy eliminations only |
| Stats | kills, deaths, headshots per combatant + MVP on the results screen |
| Match end | results overlay with the winner, final score, MVP and **PLAY AGAIN** |

## 2. Controls

### Mobile (landscape) — primary target
| Control | Where | Behaviour |
|---|---|---|
| Move stick | bottom-left | dynamic-origin virtual joystick, 8-direction, push past the outer ring to sprint |
| Look | anywhere on the right / centre | drag to turn, per-axis sensitivity, vertical clamp ±85° |
| **Fire** | bottom-right corner, large | hold to auto-fire; **keep the finger down and drag to aim while firing**; release stops firing |
| ADS | right edge, in the strip **above** the fire button | toggle, lowers sensitivity and zooms the FOV |
| Reload | right edge, lowest of the strip | starts the reload sequence, drops ADS |
| Jump | right edge, in the strip | only on the floor |
| Pause | right edge, top of the strip | pause / restart / settings / main menu |

The four action buttons form a diagonal strip along the right edge that ends **above** the
fire button, so no button is ever underneath the thumb that fires. Positions come from
named constants at the top of `scripts/mobile/mobile_input_controller.gd`
(`_EDGE`, `_STICK_BOX`, `_FIRE_BOX`, `_BUTTON`, `_BUTTON_GAP`, `_ACTION_STACK_GAP`) — change
those to re-tune the whole layout. The HUD reads the resulting rects through
`stick_rect()` / `action_strip_rect()`, so the health bar, ammo counter, kill feed and
scoreboard automatically stay clear of the controls at any aspect ratio.

All controls are independent per finger (each tracks its own `InputEventScreenTouch.index`),
so moving, aiming and firing simultaneously works. Touches that start on a button never
also fire the weapon.

### Desktop (falls back automatically)
`WASD` / arrows move, `Shift` sprint, mouse looks, left click fires, right click ADS,
`R` reload, `Space` jump, `Esc`/`P` pause, `Tab` scoreboard.

## 3. What is implemented

* **Rules** — `CBMatchManager` (5v5 roster, clock, score limit, respawn queue, elimination
  attribution) + `GameManager` autoload (authoritative scores, stats, kill feed, results).
* **Bot AI** — `CBBotController`, a seven-state machine (IDLE / PATROL / SEARCH / ENGAGE /
  RELOAD / RETREAT / RESPAWN) with FOV + raycast vision (no wallhacks), A* pathfinding over
  the baked navmesh, squad alerts when a teammate is shot, cover seeking, controlled
  accuracy, 7 Hz perception and 2 Hz repathing. Bots never shoot through teammates and
  never damage them.
* **AK-47** — data-driven (`resources/weapons/ak47.tres`): 600 RPM automatic, 30/120 rounds,
  25 body / 100 head / 18 limb damage, falloff past 45 m, recoil, spread, ADS, reload
  animation stages, hit markers, muzzle flash, tracers. The same controller and asset drive
  every bot rifle.
* **Mobile input** — see the table above; `CBMobileInputController` owns touch routing and
  the UI is drawn with custom controls sized from the live viewport. Supports **left-handed**
  mirroring (stick and fire cluster swap sides), releases every held touch when the app
  loses focus (Android never sends the matching event), and re-lays out on rotation.
  `scripts/dev/ui_layout_sim.py` measures every control and HUD readout over 9 resolutions
  x 3 HUD scales x 2 handednesses and currently reports 0 off-screen / 0 covered.
* **Aim assist** — `CBAimAssist`: cone + range gate, line-of-sight check, enemies only,
  gentle rotational pull capped per frame, sensitivity slowdown while tracking, toggle and
  strength in Settings.
* **HUD** — team scores, timer, alive counters, personal K/D, kill feed with team colours
  and headshot marks, health bar, ammo/reserve, weapon name, reload state, hit marker,
  directional damage indicators, respawn countdown, toasts, scoreboard, pause and results
  panels.
* **Settings** — camera/ADS sensitivity, aim assist (toggle, strength, radius, cone),
  graphics quality, render scale, FPS limit, HUD scale, FPS overlay, volumes, player name,
  match length, score limit, respawn delay, bot difficulty and handedness. Persisted to
  `user://settings.cfg`; every numeric key is clamped to a legal range on load **and** on
  write, so a stale or hand-edited config cannot produce an unusable camera or a broken UI.
* **Restart-safe** — the HUD releases its connections into the autoloads on scene exit, the
  match freezes behind the results screen, and respawns on the same frame are de-duplicated,
  so match 2 behaves like match 1.
* **Audio** — every effect and the menu ambience are synthesised at start-up
  (`scripts/core/sfx_synth.gd`, 22 050 Hz mono), so no unlicensed audio ships. Rifle,
  distant rifle, impacts, flesh, reload stages, dry fire, footsteps, jump, land, respawn,
  elimination, hit marker, headshot ding, countdown, match end and UI clicks.
* **VFX** — pooled impact decals, spark and blood particle bursts, tracers, muzzle flash
  with a short-lived omni light.
* **Settings** — 20 options persisted to `user://settings.cfg` (sensitivities, aim assist,
  graphics quality, render scale, FPS limit, HUD scale, volumes, score limit, match length,
  respawn delay, bot difficulty, player name), applied live.

## 4. Project layout

```
project.godot                  main scene = scenes/main/main.tscn
icon.svg
de_dust2_-_cs_map.glb          provided map  (CC-BY-4.0)
army_character_1.glb           provided soldier (CC-BY-4.0)
ak47_with_scope.glb            provided rifle (CC-BY-4.0)

scenes/
  main/main.tscn               bootstrap -> main menu
  menus/main_menu.tscn         + menu_backdrop.tscn (live 3D dust2 backdrop)
  gameplay/gameplay.tscn       match scene (builds its own world at runtime)

scripts/
  core/        settings_manager, game_manager, audio_manager, sfx_synth,
               effects_manager, navmesh_data, team, boot
  player/      player_controller
  bots/        bot_controller
  combat/      health_component
  weapons/     weapon_data, weapon_controller, weapon_model_factory
  teams/       match_manager
  characters/  character_visual
  mobile/      mobile_input_controller, virtual_joystick, fire_button,
               touch_look_area, adaptive_icon_button, aim_assist
  ui/          hud_controller, crosshair, modal_menu, settings_panel, ui_theme
  world/       map_loader, navmesh_builder
  gameplay/    gameplay (match orchestrator)
  menus/       main_menu, menu_backdrop

resources/
  weapons/ak47.tres
  navigation/navmesh_dust2.json    baked navmesh + spawns + PoIs + adjacency

docs/
  README.md  ARCHITECTURE.md  ASSET_NOTES.md  CREDITS.md  ANDROID_EXPORT.md  VALIDATION.md
```

## 5. Assets

| Asset | How it is used |
|---|---|
| `de_dust2_-_cs_map.glb` | Playable map, original materials/textures. One `StaticBody3D` with a trimesh shape per mesh (scaled correctly through each mesh's **global** transform), plus a safety floor. Also used as the live 3D menu backdrop. |
| `army_character_1.glb` | Player body (death cam) and all nine bots. Measured, rotated and scaled to 1.8 m; team-tinted uniform/helmet slots. **No skeleton or animations exist in the file**, so motion is procedural (see limitations). |
| `ak47_with_scope.glb` | First-person viewmodel, all bot rifles, menu showcase. Measured at 970 units → `0.00102` scale, muzzle axis corrected, muzzle at `-0.438 m`. |

Full measurements: [`docs/ASSET_NOTES.md`](docs/ASSET_NOTES.md).
Attribution: [`docs/CREDITS.md`](docs/CREDITS.md).

## 6. Performance notes (Android low/mid)

* Compatibility (GLES3) renderer, 1280×720 base with `canvas_items` stretch, 3D render scale
  0.72 / 0.9 / 1.0 by quality preset, MSAA off, FXAA only above Low.
* One directional light with shadows (Low quality: shadows off), no SSAO, no glow, no
  volumetric fog, no real-time GI on any map mesh.
* Pooled effects (40 decals, 10 spark, 6 blood, 16 tracers) — no per-shot node allocation;
  tracers expire on a timer instead of per-shot tweens.
* Baked navmesh shipped as data: no runtime bake, integer A* with a binary heap, 2 Hz
  repathing for moving targets, 7 Hz perception, 10 Hz steer.
* Bot perception uses one raycast per candidate (max 6) and early-outs by distance/angle.
* Audio streams are generated once (0.8 MB total) and replayed from a 20-voice 3D pool; the
  12 s ambience is generated on the next idle frame after the first screen appears.

## 7. Documentation

* [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — systems, signals, data flow, decisions.
* [`docs/ASSET_NOTES.md`](docs/ASSET_NOTES.md) — every measurement behind the asset rigs.
* [`docs/VALIDATION.md`](docs/VALIDATION.md) — what was verified, how, and what was not.
* [`docs/ANDROID_EXPORT.md`](docs/ANDROID_EXPORT.md) — export template setup and APK steps.
* [`docs/CREDITS.md`](docs/CREDITS.md) — CC-BY-4.0 attribution.

## 8. License

Code: MIT. 3D assets: CC-BY-4.0, see `docs/CREDITS.md`.
