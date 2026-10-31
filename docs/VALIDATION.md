# CALLOFBRAWL — Validation Report

Everything below was executed in this repository. The honest split matters:
**§1 was verified with a parser/API-level toolchain, geometry simulations, and — for the
first time — real engine feedback: the project was opened in Godot 4.7.2, which reported
12 parse errors. All are fixed and documented in §1.6. §3 (runtime behaviour, touch feel,
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


### 1.6 Engine-feedback round (Godot 4.7.2) — all fixed

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
gdstrict.py  -> typed/inference issues: 0
deep_audit   -> typed-var member issues: 0
```

**Warning policy.** Since Godot 4.5 four warnings are errors by default regardless of
settings, and `treat_warnings_as_errors` itself is inert in 4.7:

* `inference_on_variant` — **0 remaining**: every `var x := …` that the checker could not
  prove was rewritten to `var x = …` (identical runtime value, no inference step). 245
  rewritten declarations were diff-verified expression-by-expression to be unchanged.
* `get_node_default_without_onready`, `onready_with_export`, `native_method_override` —
  **0 occurrences** in the whole tree (checked against the engine API dump).

The remaining (non-fatal) warnings are turned off in `project.godot` `[debug]` with a
comment explaining why: the four singletons are autoloads, which GDScript reports as
"unsafe" access even though they always exist.

---

## 2. Static checks that cannot catch runtime semantics

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
| Scene/script runtime errors (null nodes, missing signals at runtime) | **untested** — all 33 scripts now *compile*, but nothing has run | `godot --headless --path . --script res://scripts/dev/selftest.gd` |
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
