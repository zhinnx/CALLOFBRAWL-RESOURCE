# CALLOFBRAWL — Architecture

## 1. Layers

```
autoloads (always alive)                 scene tree (per match)
─────────────────────────                ───────────────────────
Settings  ── options + persistence       Gameplay (Node3D, scenes/gameplay)
Game      ── scores, stats, kill feed      ├─ CBMapLoader        map + collision + nav
Audio     ── synth + voice pool            ├─ CBPlayerController local player
Fx        ── pooled visual effects         ├─ CBMobileInputController touch UI
                                           ├─ CBAimAssist
                                           ├─ CBMatchManager    rules + 9 bots
                                           └─ CBHudController   HUD + pause/results
```

Autoloads are used only for state that must survive a scene change (settings, scoreboard,
audio/FX playback). Everything that belongs to a match lives in the match scene and is
freed with it.

## 2. Systems and responsibilities

| Script | Class | Responsibility | Emits |
|---|---|---|---|
| `scripts/core/settings_manager.gd` | `Settings` (autoload) | 20 typed options, `user://settings.cfg` persistence, graphics/audio application | `changed(key, value)`, `graphics_changed` |
| `scripts/core/game_manager.gd` | `Game` (autoload) | match config, scores, per-combatant stats, kill feed, results, scene transitions | `score_changed`, `kill_feed`, `match_started/ended`, `stats_changed` |
| `scripts/core/audio_manager.gd` | `Audio` (autoload) | synthesised streams, 20-voice 3D pool, music bus | — |
| `scripts/core/effects_manager.gd` | `Fx` (autoload) | pooled decals / sparks / blood / tracers / muzzle flashes | — |
| `scripts/core/sfx_synth.gd` | `SfxSynth` | pure functions returning `AudioStreamWAV` | — |
| `scripts/core/navmesh_data.gd` | `CBNavMeshData` | loads the baked lattice, adjacency, nearest-polygon lookup, A* | — |
| `scripts/core/team.gd` | `CBTeam` | team ids, colours, names, friend/foe test | — |
| `scripts/world/map_loader.gd` | `CBMapLoader` | instantiates the GLB, builds trimesh collision, safety floor, nav region, spawn resolution | `map_ready` |
| `scripts/world/navmesh_builder.gd` | `CBNavMeshBuilder` | turns the lattice into a `NavigationMesh`/`NavigationRegion3D` | — |
| `scripts/player/player_controller.gd` | `CBPlayerController` | movement, camera, viewmodel, recoil, death cam, desktop input | `damaged`, `died`, `respawned`, `ammo_updated`, `ads_changed` |
| `scripts/characters/character_visual.gd` | `CBCharacterVisual` | body model, team tint, rifle rig, procedural animation | — |
| `scripts/combat/health_component.gd` | `CBHealthComponent` | health, friendly-fire rejection, death | `damaged`, `died`, `health_changed` |
| `scripts/weapons/weapon_data.gd` | `CBWeaponData` | all weapon stats (Resource) | — |
| `scripts/weapons/weapon_controller.gd` | `CBWeaponController` | fire logic, recoil, spread, reload, hitscan, effects | `ammo_changed`, `fired`, `hit_confirmed`, `reload_started/finished` |
| `scripts/weapons/weapon_model_factory.gd` | `CBWeaponModelFactory` | builds the AK-47 rig from the GLB | — |
| `scripts/bots/bot_controller.gd` | `CBBotController` | perception, state machine, pathing, shooting | `bot_eliminated` |
| `scripts/teams/match_manager.gd` | `CBMatchManager` | roster, clock, score, respawns | `match_started`, `eliminated`, `match_finished`, `respawn_countdown` |
| `scripts/mobile/mobile_input_controller.gd` | `CBMobileInputController` | per-finger touch routing | — |
| `scripts/mobile/fire_button.gd` | `CBFireButton` | hold-to-fire + drag-to-aim | `fire_started/stopped`, `aim_delta` |
| `scripts/mobile/virtual_joystick.gd` | `CBVirtualJoystick` | dynamic-origin stick with sprint ring | `move_changed` |
| `scripts/mobile/touch_look_area.gd` | `CBTouchLookArea` | drag look | `look_delta` |
| `scripts/mobile/aim_assist.gd` | `CBAimAssist` | target selection + rotational assist | — |
| `scripts/ui/hud_controller.gd` | `CBHudController` | drawing + pause/results routing | `restart_requested`, `menu_requested`, `settings_requested`, `pause_toggled` |

## 3. Data flow of one shot (player)

```
touch hold on CBFireButton
  → fire_started → CBMobileInputController.set_trigger(true)
  → CBPlayerController.weapon.set_trigger(true)
  → CBWeaponController._process: _try_fire() (respects 600 RPM cooldown)
      → ammo_changed → HUD ammo counter
      → _do_shot(): camera ray + spread → PhysicsDirectSpaceState3D.intersect_ray
          → hitbox Area3D in group "hitbox" → _find_combatant()
          → CBHealthComponent.apply_damage(dmg, ...)   [friendly fire rejected here]
              → damaged → CBPlayerController.damaged → HUD damage indicator
              → died    → CBMatchManager.on_player_died / bot death
                            → Game.report_elimination (legal kills only)
                                → score_changed → HUD + Game.finish_match at 50
          → hit_confirmed → CBCrosshair hit marker
      → Fx.fire_muzzle_flash / spawn_tracer / spawn_impact
      → Audio.play_ui("rifle")
      → fired(recoil) → CBPlayerController._update_camera_rotation (decaying offset)
```

Bots resolve their own hitscan (`fire_bot_hitscan`) so the AI owns hit probability;
the player's `CBWeaponController` stays authoritative for the local weapon only.

## 4. Respawn pipeline

`CBMatchManager.begin_respawn_timer(node)` queues the combatant. Every frame the queue
counts down; on completion `CBMapLoader.pick_spawn(team, avoid)` returns a spawn that

1. snaps to the floor with a downward raycast (layer = world),
2. is at least 1.6 m from every living combatant,
3. passes a `CapsuleShape3D` overlap test (no spawning inside a wall or under a ledge).

Dead bodies are removed from physics (shape disabled, hitboxes not monitorable), so a
corpse can never block a spawn or absorb bullets.

## 5. Navigation decisions

The map's trimesh is baked offline into a 0.5 m lattice (`resources/navigation/
navmesh_dust2.json`, see `ASSET_NOTES.md` §4). Two consumers:

* `CBNavMeshBuilder` produces a real `NavigationRegion3D` (each quad split into two
  triangles so polygons stay convex).
* Bot AI uses `CBNavMeshData.find_path()` — A* over the shipped adjacency list with a
  binary heap and a 4 m spatial lookup for the start/goal polygon.

Why not `NavigationAgent3D` alone? Each path search at 2 Hz per bot would have to be
built from a 6 657-polygon mesh whose connectivity depends on the engine's exact edge
matching. Shipping the adjacency makes behaviour deterministic and the cost measurable
(≤ 3 500 expansions for a full cross-map path).

## 6. Touch routing (why the input controller is a `Node`, not a `Control`)

Controls receive `_gui_input` **before** `_input`. A full-screen look pad as a `Control`
would swallow every touch, including the ones over the fire button. `CBMobileInputController`
is therefore a plain `Node` that receives `_input` first and dispatches each event by
finger index to exactly one control:

```
pause → reload → jump → ADS → fire+drag → joystick → look area
```

Sizing comes from `get_viewport().get_visible_rect()` with a `size_changed` hook, so the
layout adapts to any landscape resolution without anchors.

## 7. Extending

* **New weapon**: duplicate `resources/weapons/ak47.tres`, change `CBWeaponData` fields,
  point `weapon.data` at it. No code changes.
* **New bot behaviour**: add a `State` member and a `_tick_<state>()` branch; tuning lives
  in `retune(difficulty)`.
* **New map**: bake a lattice with the same JSON schema (version 2 + `links`), point
  `CBMapLoader.MAP_SCENE_PATH` at the new scene.
