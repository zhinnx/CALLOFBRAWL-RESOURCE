# Credits & Attribution

## 3D assets — CC-BY-4.0

All three models shipped in this repository are licensed **Creative Commons
Attribution 4.0 International (CC-BY-4.0)**. They are used unmodified except for the
numeric transforms (scale / rotation / position) documented in
[`ASSET_NOTES.md`](ASSET_NOTES.md). Attribution is required and provided below.

| File | Title | Author | Source |
|---|---|---|---|
| `de_dust2_-_cs_map.glb` | de_dust2 - CS map | **vrchris** | Sketchfab — <https://sketchfab.com/3d-models/de_dust2-cs-map> |
| `army_character_1.glb` | Army Character 1 | **Muhamad Mirza Arrafi** | Sketchfab — <https://sketchfab.com/3d-models/army-character-1> |
| `ak47_with_scope.glb` | AK47 with scope | **Wolf Schevelenbos** | Sketchfab — <https://sketchfab.com/3d-models/ak47-with-scope> |

The map was originally authored by *vrchris* and exported with Sketchfab's exporter
(`Sketchfab-12.67.0`). "de_dust2" is a map layout originally created by Valve for
Counter-Strike; this project is a non-commercial fan homage and is not affiliated with
or endorsed by Valve.

License text: <https://creativecommons.org/licenses/by/4.0/legalcode>

### How to comply when redistributing

1. Keep this file (`docs/CREDITS.md`) with the build.
2. Keep the in-game credits panel (main menu → **CREDITS**), which lists the same
   authors.
3. Do not add restrictions that prevent others from using the assets under CC-BY-4.0.

## Audio

**No third-party audio files are shipped.** Every sound effect and the looping menu
ambience are synthesised at runtime by `scripts/core/sfx_synth.gd` (filtered noise
bursts, pitched sines, envelopes) into 22 050 Hz 16-bit mono `AudioStreamWAV` buffers.
They are original works produced by this project's code and may be reused under the
same MIT license as the code.

## Engine

Built with **Godot Engine 4** — © Godot Engine contributors, MIT licensed.
<https://godotengine.org/license>

## Fonts

No font files are bundled. The UI renders with Godot's built-in fallback font
(`ThemeDB.fallback_font`), which is part of the engine.
