# Exporting CALLOFBRAWL to Android

The project is already configured for mobile (landscape, GLES3/Compatibility renderer,
touch emulation from mouse for desktop testing). What remains is engine-side setup that
can only be done in the editor.

## 1. Requirements

| Item | Version / notes |
|---|---|
| Godot | **4.3 or newer** (project targets 4.3 features; 4.4/4.5 also open it) |
| Export templates | matching your exact engine version |
| JDK | **17** (Godot 4 requirement) |
| Android SDK | Command-line tools + Platform 34 + Build-Tools 34 |
| Device | Android 7.0 (API 24) or newer, 2 GB RAM recommended |

Install export templates from **Editor → Manage Export Templates → Download and Install**.

## 2. Configure the Android SDK path

**Editor → Editor Settings → Export → Android**:

* `Android Sdk Path` → your SDK directory (contains `platform-tools/`)
* `Java Sdk Path` → your JDK 17 directory
* `Debug Keystore` → leave the default (`~/.android/debug.keystore`) for testing

If `adb` is required, point `adb` to `platform-tools/adb`.

## 3. Create the export preset

1. **Project → Export… → Add… → Android**
2. Set the package name — the project already declares `com.callofbrawl.fps` in
   `project.godot` (`[android]`); keep the preset name `Android`.
3. **Options tab** (recommended values, already reflected in `project.godot`):

| Option | Value | Why |
|---|---|---|
| Architecture | `arm64-v8a` **and** `armeabi-v7a` | covers modern and budget devices |
| Export format | `APK` (`.apk`) | direct install; use AAB only for Play Store |
| Screen / Orientation | `Landscape` | the game also calls `DisplayServer.screen_set_orientation(SCREEN_LANDSCAPE)` at runtime |
| Renderer | `gl_compatibility` | set in `project.godot`; required for old GPUs |
| Texture format | `ETC2/ASTC` | `textures/vram_compression/import_etc2_astc=true` is already set |
| XR Mode | `Regular` | — |
| Version code / name | `1` / `1.0.0` | declared in `project.godot` |

4. **Resources tab** — keep the default *Export all resources in the project*; the three
   GLB files and `resources/navigation/navmesh_dust2.json` must be included.
5. Click **Export Project…**, choose `build/CALLOFBRAWL.apk`.

## 4. Install and run

```bash
# from the project root, with the device connected and USB debugging on
adb install -r build/CALLOFBRAWL.apk
adb shell am start -n com.callofbrawl.fps/com.godot.game.GodotApp
adb logcat -s godot:V   # watch engine output / errors
```

On-device checks worth doing first:

1. Menu → **PLAY**, confirm landscape and that the HUD fits (try a 20:9 and a 4:3 device).
2. Left stick moves, right thumb drags the camera.
3. Hold the fire button and drag — the camera must keep turning while bullets continue.
4. ADS toggle, reload, jump while moving, pause → Settings → change sensitivity, resume.
5. Watch `adb logcat` for the frame time at 60 FPS; if it drops, switch Settings →
   Graphics quality to **Low** and Render scale to 0.7.

## 5. Performance tuning for low-end devices

Already applied: Compatibility renderer, no MSAA, FXAA only above Low, shadows off at Low,
one directional light, no SSAO/glow/SSAO/volumetric fog, pooled particles, baked navmesh,
throttled AI.

If a device still struggles:

* Settings → **Render scale** 0.6–0.7 (largest single win, 3D only).
* Settings → **Graphics quality: Low** (disables shadows, specular and decals' extra
  lighting).
* Settings → **FPS limit: 45** (smoother than an unstable 60 on a throttling phone).

## 6. Release build (optional)

```bash
# create a keystore once
keytool -genkey -v -keystore release.keystore -alias callofbrawl \
        -keyalg RSA -keysize 2048 -validity 10000

# in the editor: Export… → Android preset → Options → Keystore →
#   Release, release.keystore, alias callofbrawl, your password
# then Export Project… → build/CALLOFBRAWL-release.apk
```

Keep `release.keystore` **out of version control** (add it to your local ignore list).

## 7. Known mobile limitations

* `army_character_1.glb` has no skeleton, so character animation is procedural
  (whole-model bob, lean, recoil, death fall). See `docs/ASSET_NOTES.md` §2.
* The bot AI uses the shipped navigation lattice; areas the bake rejected (low
  overhangs, steep ledges) are not patrolled.
* Vibration (haptics) is not implemented.
* The game has no network/multiplayer layer — all opponents are AI.
