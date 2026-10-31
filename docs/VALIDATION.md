# CALLOFBRAWL — Validation Report

Everything below was executed in this repository. The honest split matters:
**§1 was verified with a parser/API-level toolchain, geometry simulations, and — for the
first time — real engine feedback: the project was opened in Godot 4.7.2, which reported
12 parse errors. All are fixed and documented in §1.8b. §3 (runtime behaviour, touch feel,
on-device FPS, APK export) is still NOT executed, because only the parse/compile stage
could be reached in the build environment.**

---

## 1. Verified

### 1.1 GDScript parse + API validation — `PASS (0 issues)`

A custom validator was written for this task (it parses each `.gd` file with `gdtoolkit`,
builds per-file symbol tables, and checks every call against a Godot 4.7.2 API index
extracted from the engine's own type definitions):

```
scripts: 33   scenes/resources: 4   autoloads: 4
issues: {}
```

It verifies, for all 33 scripts:

* the file **parses** as GDScript 2.0 (no syntax errors),
* every **engine method call is called with a valid argument count** (positional and
  optional; varargs handled),
* every **engine property/menum/enum** referenced on a typed value exists,
* every **`.tscn`** references an existing script/scene and its declared node paths and
  `ext_resource` ids resolve,
* every **autoload** and `res://` resource path in `project.godot` exists.

### 1.2 Cross-system API audit — `PASS (0 real issues)`

A second tool resolves every `Class.member` access between project classes (including the
four autoloads and inheritance chains) against the actual definition:

```
unresolved member accesses: 40   -> 2 unique, both false positives
```

The two reported items are tooling artefacts, checked by hand:

* `CBTeam.ALPHA` — a nested `enum` member, not a class member.
* `CBEffectsManager` — text inside a doc comment.

### 1.3 Typed-variable member audit — `PASS (0 issues)`

```
files scanned: 33
typed-var member issues: 0
```

Every `some_typed_variable.member` access (`CBPlayerController`, `CBBotController`,
`CBHudController`, `CBWeaponController`, … including inherited engine members) resolves.

### 1.4 Signals and callbacks — `PASS`

* every `signal` declared in a project class is emitted somewhere: **0 orphans**
* every `connect(target)` name is defined in the connecting file: **0 missing**
* every `Class.signal.connect(...)`, `Class.CONSTANT` and enum member reference resolves:
  **0 missing**

### 1.5 Navmesh — `PASS` (baked offline, then simulated)

The navmesh was baked from the map's own triangles and then verified by re-reading the
shipped JSON and re-running the runtime algorithms in Python:

| Check | Result |
|---|---|
| Polygons / vertices | 6 657 / 7 644 (0.5 m lattice) |
| Isolated polygons | 0 |
| Average adjacency degree | 7.21 |
| Largest connected component | 6 348 polygons (1 587 m²) |
| Spawns on mesh (height mismatch) | 12/12, max 0.00 m |
| Spawn spacing (same team) | 2.03 m (A) / 2.27 m (B) |
| Team spawn separation | 49.9 m minimum, 58.3 m between team centres |
| Cross-map A* success | 6/6 spawn pairs |
| Path length | 77.5 – 97.4 m (median 88.4 m) |
| A* node expansions | median 3 631, max 4 606 (binary heap) |
| Points of interest reachable | 35/37 from the first spawn point, 37/37 from the spawn the bake validated |
| Adjacency blocking test (12 214 pairs, capsule sweep against raw triangles) | 8 pairs, all sub-0.4 m ledge seams; **no wall-crossing links** |
| Cells with < 1.75 m headroom | removed at bake time (114) |
| Cells straddling a > 1.85 m ledge | removed at bake time (100) |

### 1.6 Asset rigs — `PASS` (measured from the binaries)

All constants were derived by parsing the GLB chunks and transforming vertices with the
node matrices, then re-checking the transform the scripts apply:

| Asset | Measured | Constant applied | Verified result |
|---|---|---|---|
| `ak47_with_scope.glb` | 970 × 86.6 × 386.2 units, muzzle at **+X** | `GUN_SCALE 0.00102`, yaw **+90°**, offset `(0, -0.152, 0.051)` | 0.99 m rifle, muzzle at `(0, 0, -0.438)`, grip at origin, stock behind |
| `army_character_1.glb` | 2.5 m tall, faces **−X** (sunglasses at the extreme −X of the head), 0 skins/0 animations | scale `1.8/2.5`, yaw **−90°** | 1.80 m tall, feet at y = 0, 0.94 m shoulders, head anchor at `(0.04, 1.60, −0.06)` |
| `de_dust2_-_cs_map.glb` | 9 294 tris, floor y ≈ 1008.0, bounds 60 × 71 m | trimesh collision per mesh using **global** transforms | spawn/floor heights agree with the baked navmesh to 0.00 m |

The character's facing axis was confirmed by rendering all four yaws from the vertex data
and locating the sunglasses mesh, not assumed from an axis convention.

### 1.7 Rules and data — `PASS`

* `ak47.tres` → 600 RPM (0.1 s interval), 30/120 rounds, 25 body / 100 head / 18 limb,
  45 m effective / 120 m max with 55 % falloff, automatic, 2.45 s reload.
* 5 v 5 roster (local player + 4 Alpha bots vs 5 Bravo bots), score limit 50, 10 min,
  3 s respawn — all read from `Settings` with the documented defaults.
* Friendly fire is rejected inside `CBHealthComponent.apply_damage()` and again in the
  bot hit resolution, so it cannot score even if a bullet somehow reaches a teammate.
* Damage path verified by reading every call site: player hitscan → `apply_damage`,
  bot hitscan → `apply_damage`, both keyed on team.

### 1.8 Bug sweep (fixed during this pass)

Real defects found by the audits above and fixed in the code:

1. Rifle scale `0.103` produced a **100 m rifle** (asset is 970 units, not 9.7 m).
2. Rifle muzzle direction and grip offset were inverted (+90° needed, not −90°).
3. Character was rotated as if it faced +Z; it faces **−X**.
4. GLB collision shapes used **local** transforms — every wall would have been misplaced.
5. **Bots never respawned** (`begin_respawn_timer` was never called for bots).
6. Aim assist pushed the crosshair **away** from the target (sign error).
7. Damage indicators used a bearing convention that mirrored left/right.
8. ADS sensitivity setting was never applied to the camera.
9. WASD movement did not exist despite being advertised on the menu.
10. Settings panel sized its frame from a 0×0 rect during `_ready`.
11. Navmesh lost ~77 % of polygons on a second bake pass (component filter regression) —
    final bake keeps the full surface and ships the adjacency graph.
12. Tracers allocated a `Tween` per shot and mis-indexed their expiry slot.
13. Dead bodies stayed hittable; respawns could land inside another combatant.
14. Restart/menu from the pause screen left `get_tree().paused == true`.


### 1.8b Engine-feedback round 1 (Godot 4.7.2) — all fixed

The project was opened in **Godot 4.7.2** and the console reported 12 parse errors across
five scripts. This is the most valuable validation this project received, because it
exposed a class of error the static toolchain above could not see. Every one is fixed.

| # | Where | Engine message | Root cause | Fix |
|---|---|---|---|---|
| 1 | `core/game_manager.gd:101` | inferred from a Variant value | `var attacker := stats.get(...)` — `Dictionary.get()` returns `Variant` | explicit `Dictionary` |
| 2 | `bots/bot_controller.gd:174-175` | cannot infer type | `var base_acc := [..][i]` — array subscript is `Variant` | typed const tables + `int` index |
| 3 | `bots/bot_controller.gd:411,415` | cannot infer type | `var best := pois[i]` on an untyped `Array` | explicit `Vector3` / `float` |
| 4 | `gameplay/gameplay.gd:131` | `CBHudController` cannot be assigned to `Control` | `mobile_input.hud: Control` but a **CanvasLayer** was passed | `hud: CanvasLayer` |
| 5 | `weapons/weapon_controller.gd:210,211,354,380` | `global_position` not declared | the controller is a plain `Node`, not `Node3D` | `_holder_position()` / `basis_from_holder()` |
| 6 | `ui/hud_controller.gd:324` | cannot infer type of `vp` | `CanvasItem` has no `size` (only `Control` does) | `paint(canvas: Control)` |

While fixing these, a **strict type checker** was built and calibrated against that
console output: replayed on the original commit it reproduces the engine's line numbers
(`game_manager:101`, `hud:324`, `gameplay:131`, `bot_controller:174/175/411/415`) plus
three further errors the engine never reached because it stopped after five files:
`'Control' has no member 'closed'/'open'` (a `CBSettingsPanel` typed as `Control`) and
`'InputEvent' has no member 'echo'` (only `InputEventKey` has it).

Final state on the current tree:

```
gdcheck.py   -> scripts: 33   scenes/resources: 4   autoloads: 4      issues: {}
gdstrict.py  -> typed/inference issues: 0 (advisory only, see the note below)
deep_audit   -> typed-var member issues: 0
stringcalls  -> string-call arity problems: 0
arity        -> typed-receiver call arity problems: 0
syncheck     -> syntax hazards: 0
ui_sim       -> layout problems: 0 over 9 resolutions x 3 hud scales
```

The three checkers that were written *because* of the engine feedback, plus the layout
simulator, are committed so the numbers above can be reproduced without the original
scratch files:

```
python3 scripts/dev/ui_layout_sim.py      # mobile layout sweep
python3 scripts/dev/checks/stringcalls.py .
python3 scripts/dev/checks/arity.py .
python3 scripts/dev/checks/syncheck.py .
```

**Warning policy.** Since Godot 4.5 four warnings are errors by default regardless of
settings, and `treat_warnings_as_errors` itself is inert in 4.7:

* `inference_on_variant` — **0 engine-reported occurrences**. ⚠️ **Correction:** an earlier
  pass rewrote 245 declarations to `var x = …` because a local checker claimed they were
  `INFER` violations. That pass was wrong: those `:=` lines were accepted by Godot 4.7.2,
  and three of the rewrites introduced real compile errors (`Vector2` annotated onto
  `length()`). The pass was rolled back to the engine-accepted baseline and replaced by
  12 targeted patches at the lines the engine actually reported. Treat the local
  `gdstrict.py` INFER count as advisory only — **the engine is the authority.**
* `get_node_default_without_onready`, `onready_with_export`, `native_method_override` —
  **0 occurrences** in the whole tree (checked against the engine API dump).

The remaining (non-fatal) warnings are turned off in `project.godot` `[debug]` with a
comment explaining why: the four singletons are autoloads, which GDScript reports as
"unsafe" access even though they always exist.

### 1.9 Engine-feedback round 2 (Godot 4.7.2) — `FIXED`

| Reported by the engine | Root cause | Fix |
|---|---|---|
| `audio_manager.gd` — `_build_music(): called with 1 argument, expects 0` | `call_deferred("_build_music", null)` | dropped the argument |
| `navmesh_data.gd:120` — type mismatch in `var step := …length()` | a bulk `:=` rewrite annotated `Vector2` onto a **float** result | restored `float` |
| `navmesh_data.gd:205/206` — invalid operands (`+`) | same rewrite, `Vector2` on a scalar distance | restored scalar types |
| cascading *"Failed to compile depended scripts"* in `navmesh_builder.gd`, `map_loader.gd`, `bot_controller.gd` | all three `preload`/use `navmesh_data.gd` | resolved by the fixes above |

Two new static checks were added for the failure modes that the existing audits could not
see, and both were validated against a deliberately broken fixture before being trusted:

* **`stringcalls`** — argument count of `call()/call_deferred()/callv()/call_group()` with a
  literal method name. These resolve at **runtime**, so a wrong count is a console error
  rather than a parse error (exactly how `_build_music` broke). Result: **0**.
* **`arity`** — argument count for `expr.method(...)` where the receiver's static type is
  known from a typed `var`/parameter/return. Result: **0**.
* **`syncheck`** — hazards no AST checker sees: backslash line continuation (**not valid
  GDScript**; this was introduced and caught during this pass), mixed tab/space indentation.
  Result: **0**.

### 1.10 Mobile UI — measured with a layout simulator, `PASS` after fixes

The stretch mode is `canvas_items` + `expand` on a 1280×720 base, so the visible play area
is **always 720 units tall** and its width follows the device aspect ratio (a 20:9 phone
renders 1600×720). `/tmp/analyze/ui_sim.py` reproduces that mapping and the *actual*
drawing maths of `hud_controller`, `mobile_input_controller`, `main_menu` and
`CBModalMenu`, then measures every control and readout at 9 resolutions
(1280×720, 2392×1080, 2400×1080, 2340×1080, 1920×1080, 1600×720, 1024×768, 2000×1200, 2560×1440)
with `hud_scale` at 0.75 / 1.0 / 1.4.

Measured **before** the fix — this is the user's "controls cannot be touched" report:

| Element | Result at every resolution |
|---|---|
| `JUMP` button | **100 % covered** by the fire button |
| `ADS` button | **96 % covered** by the fire button |
| `PAUSE` button | **88 % covered** by the fire button |
| Health bar | behind the joystick at 5/5 resolutions |
| `EXIT` on the main menu | **52 units below the bottom edge** (4 buttons at a fixed 118 pitch starting at 42 % height) |
| Ammo counter | underneath the fire button |

Measured **after** the fixes: off-screen 0, covered 0, HUD/menu/modal content problems 0
across the full sweep. What changed:

1. `_layout_controls()` was rewritten around named constants (`_EDGE`, `_STICK_BOX`,
   `_FIRE_BOX`, `_BUTTON`, `_BUTTON_GAP`, `_ACTION_STACK_GAP`). The action buttons now form a
   diagonal strip along the right edge **above** the fire button instead of underneath it,
   with a wide-screen/narrow-screen fallback.
2. `action_strip_rect()` / `stick_rect()` expose the areas the thumbs own. `gameplay.gd`
   forwards them to the HUD (`touch_exclusion`, `touch_left_block`) on start-up **and** on
   `layout_changed` (emitted after every re-layout, including rotation), so the HUD never
   has to guess.
3. The health bar starts after the joystick block and is width-capped; the ammo counter is
   right-aligned to the control cluster instead of the screen edge; the kill feed stops
   before the cluster; the scoreboard is fitted into the free band between stick and
   buttons; the toast is clamped to the viewport.
4. The main menu derives its button pitch from the space actually available, so all four
   buttons (PLAY / SETTINGS / CREDITS / EXIT) fit a 720-unit-tall screen and stay ≥ 64 units.
5. Pause/play state is now idempotent: hiding the controls no longer re-fires
   `trigger(false)` mid-burst.

Additional mobile-only defect found and fixed in this pass: when the app loses focus
(incoming call, notification shade, app switch) Android never delivers the
"finger released" event, so the fire button stayed pressed and the character kept walking.
`_notification()` now clears every claimed touch on
`NOTIFICATION_APPLICATION_(FOCUS_OUT|PAUSED)` and `NOTIFICATION_WM_WINDOW_FOCUS_OUT`.

---

## 2. Static checks that cannot catch runtime semantics

**The simulator is not the engine.** It proves geometry, not rendering: it cannot show
whether a control is *visible* (draw order, alpha, `CanvasLayer` ordering), whether the
font actually looks readable on a 6" screen, or whether the touch hit-test agrees with the
drawn circle. It catches "off screen" and "covered", which is what the user reported — it
does not replace holding the phone.

The validator is a parser, not an engine. It cannot prove that:

* a `NodePath`, signal connection or resource loads at **runtime** with the exact import
  settings of a given engine build,
* `CharacterBody3D` movement feels right against the trimesh (slope/step tuning),
* the navmesh `NavigationRegion3D` reports the same connectivity the A* graph has,
* shaders compile on a specific GPU.

The in-engine self test (`scripts/dev/selftest.gd`) exists for exactly those points —
see below.

---

## 3. NOT verified (no Godot binary or device available)

| Item | Status | How to verify |
|---|---|---|
| Engine import of the 3 GLBs (`project.godot` open, import step) | **untested** | open the project in Godot 4.3+; the Import dock should show 3 scenes + textures with no errors. *(The 4.7.2 run reached the script-compile stage, which is after import — the GLBs did load, but their visual result has not been reviewed.)* |
| Scene/script runtime errors (null nodes, missing signals at runtime) | **untested** — all 33 scripts pass the static suite and the two engine rounds found only the errors listed in §1.8b/§1.9, but nothing has *run* | `godot --headless --path . --script res://scripts/dev/selftest.gd` |
| Touch feel (button size vs. thumb, drag-to-aim responsiveness, multitouch) | **untested** — geometry is verified by the simulator, ergonomics are not | play on the phone and report; `_BUTTON` etc. are single constants in `mobile_input_controller.gd` |
| Actual gameplay feel (speed, recoil, TTK, bot difficulty) | **untested** | play a match on desktop, then a phone |
| Touch input on a real touchscreen (multi-finger routing) | **untested** | `adb install` + play; specifically hold-fire-and-drag |
| Frame rate on Android hardware | **untested** | `adb logcat`, or the built-in FPS limit setting |
| Android export (`export_presets.cfg` is intentionally not committed) | **untested** | follow `docs/ANDROID_EXPORT.md` §3 |
| Character animation quality | **known limitation** | the GLB has no skeleton; motion is procedural |

Commands the user can run to convert §3 into verified results:

```bash
# 1. full in-engine self test (headless, no window)
godot --headless --path . --script res://scripts/dev/selftest.gd
#    exit code 0 = every check passed

# 2. normal run on desktop
godot --path . --resolution 1280x720

# 3. Android
godot --headless --path . --export-debug "Android" build/CALLOFBRAWL.apk
adb install -r build/CALLOFBRAWL.apk
```

The self test checks: all 33 scripts load, all GLBs instantiate with the expected mesh
counts, the navmesh builds a region with valid polygon indices, A* returns paths for every
spawn pair and ≥ 80 % of the points of interest, the weapon resource matches the documented
stats, settings round-trip through `user://settings.cfg`, and the team rules reject
friendly fire.
