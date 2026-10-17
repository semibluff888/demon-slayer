# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

「鬼灭之刃：宿命对决」 is a 2D fighting game built with **Godot 4.7.1 stable** (GL Compatibility renderer, 1280×720 canvas, 60 Hz physics) on Windows. Docs, UI text and commit messages are in Chinese; commits follow `type(scope): 中文说明`, e.g. `feat(vfx): …`, `fix(ui): …`.

## Commands

Godot is located by `tools/find-godot.ps1`: the `-Godot` argument, then `$env:GODOT`, `godot` on PATH, `build/engine/`, then `.godot/engine-path.txt`. Use the console build (`*_console.exe`) for scripted runs.

```powershell
# Run the game (picks the windowless Godot next to the console build)
launch.cmd
# Full regression: every Godot test suite, the 30/60/144 FPS determinism check, then the Python art tests
powershell -ExecutionPolicy Bypass -File tests/run_tests.ps1 -Godot <path\to\Godot_console.exe>
# Same plus real OpenGL screenshots (needs a window)
powershell -ExecutionPolicy Bypass -File tests/run_tests.ps1 -Capture
# Release: fetch the official editor and export templates once, then build dist/<zip> (refuses to overwrite an existing version)
powershell -ExecutionPolicy Bypass -File tools/install-export-tools.ps1
powershell -ExecutionPolicy Bypass -File tools/build-release.ps1 -Version 0.1.3
# Report removable local files; -Apply deletes them (Git-tracked files are always skipped)
powershell -ExecutionPolicy Bypass -File tools/clean-local.ps1
```

Run a single suite headless:

```powershell
& $godot --headless --path . --script res://tests/combat_tests.gd
```

Each test script `extends SceneTree`, prints a summary such as `COMBAT TESTS: 460 passed, 0 failed`, and exits non-zero on failure. `run_tests.ps1` also fails a run whose output contains `SCRIPT ERROR`, `ERROR:`, `FAIL:` or leaked instances/RIDs, so a draw call that errors counts as a failure even if every check passes. A new suite must be added to `run_tests.ps1` together with its expected summary regex. The Python tests run with the project venv: `.venv\Scripts\python.exe tests/art_pipeline_tests.py` (also `roster_`, `uppercut_`, `awakening_`, `guard_fist_`, `motion_`, `fate_art_tests.py`, plus `capture_storage_tests.py` for capture storage and retention). Python (`requirements-art.txt`) is needed for art production, those tests, and the default video output of the capture tools, which also needs `ffmpeg`/`ffprobe` on PATH. The game itself never needs Python.

Visual review tools (`tools/capture_*.gd`) must run **with a window** and a fixed clock, e.g. `& $godot --path . --fixed-fps 60 --script res://tools/capture_tanjiro_vfx.gd -- --moves=236A --hd`. They write to `artifacts/` (Git-ignored and regenerable). `capture_moves.gd`, `capture_idle_loop.gd`, and `capture_tanjiro_vfx.gd` now default to `capture.mp4`: `capture_output.gd`/`.py` encode and verify bounded batches before removing PNG intermediates. Add `--keep-frames` for lossless PNGs consumed by contact-sheet tools (512 MiB per sequence; `--max-raw-mib=1024` may raise it, up to 2048). Test startup and these captures automatically run `clean-local.ps1 -Apply -RetainRecent` (7 days / 2 GiB; captures from the last 24 h are never evicted for size; active captures and tracked files protected). Do not copy frame directories into numbered review archives. See `docs/capture-storage.md`. Do not run two Godot instances at the same time; they both write the import cache.

## Architecture

**Combat is a pure, deterministic model.** `scripts/combat.gd` (`DuelCombat`, a `RefCounted`) advances one 60 Hz tick per `step([p1_command, p2_command])`. A command is `{"x": -1..1, "y": -1..1, "buttons": A=1|B=2|C=4|D=8}` in world directions. Keyboard, gamepad (`input_router.gd`), AI (`ai_controller.gd`) and practice dummy (`practice_controller.gd`) all produce these raw commands; `command_recognizer.gd` detects motions such as 236, 623 and double-236 inside the model. Each step fills `combat.events` (hit, block, super, meter, round_end, …), which `scripts/main.gd` forwards to the view and the audio. Rendering, render frame rate and presentation must never change combat state. `tests/frame_rate_tests.gd` compares full `snapshot()` hashes at 30/60/144 FPS, and the presentation tests assert that the snapshot is unchanged after drawing.

**Data-driven roster.** `CombatCatalog` discovers `resources/characters/*.tres` (`CharacterDefinition`) and registers the moves they reference. Moves live in `moves/core/*.tres` (`DuelMove`, see `scripts/move_data.gd`). Frame data, boxes (authored facing right from the feet), `hit_frames`, `cancel_targets`, projectiles and meter costs are all defined there, and each move points to a display-only `MovePresentation` in `resources/presentation/`. Balance changes are made by editing the `.tres` files directly. `tools/build_combat_data.py` is an offline authoring tool; keep its parameters in sync if you ever rerun it. `docs/combat-system.md` documents the input windows, damage scaling and combo rules.

**Export pitfalls** (see `docs/distribution.md`). `project.godot` sets `editor/export/convert_text_resources_to_binary=false` because Godot 4.7.1's binary conversion empties `PackedStringArray cancel_targets`. Atlases load from JSON at runtime, so `export_presets.cfg` must keep `include_filter="*.json"`. `build-release.ps1` stages only `art/ moves/ resources/ scenes/ scripts/ project.godot`, writes a combat manifest, and verifies the exported EXE with `--headless -- --verify-release` (move properties plus 64 real-input combos) before it produces a ZIP.

**Presentation layering.** `scripts/world_view.gd` composes the battle scene: stage, fighters (`presentation/fighter_view.gd`, z 2), `EffectsView` (z 10), `SuperView` (super/MAX dimmer, cut-ins and titles, z 20), `CinematicView` (pre-rendered super videos from `art/cinematics/`, z 25) and the HUD (z 30). Views only read combat state. Freezes come from the model (hitstop, `super_freeze`, KO slow motion via `presentation_speed()`), and `world_view` passes them on as `effects.freeze` and `playback_speed`.

**Character art.** Each fighter has `art/characters/<id>/atlas.json` plus atlas pages, with a shared `feet_anchor`, per-clip `phase_breaks` (the startup/active/recovery boundaries that `FighterView.move_clip_frame` maps move frames onto) and an optional `awakening/` variant. `CharacterVisual` (`presentation/character_visual.gd`) and `visual_catalog.gd` load these files. Art is produced offline by the Python tools in `tools/`, and generation sources and provenance live in `output/`.

**Tanjiro's rebuilt VFX.** `scripts/presentation/vfx/tanjiro_vfx.gd` sits under `EffectsView`. Its `MOVES` table routes the moves it owns to per-technique scripts in `scripts/presentation/vfx/tanjiro/` (base class `technique.gd`, path shapes in `paths.gd`, constants in `kit.gd`); every other move and every other character still goes through `EffectsView`'s own drawing (`_rebuilt(move)` decides). Particles are emitted once per combat tick with seeded randomness and advance only with presentation time. Shapes follow the move clock and the drawn blade (`art/characters/tanjiro/blade-tracks.json`). Rebuilt supers draw their own charge, so `SuperView` skips its shared energy sphere for them. `docs/vfx/tanjiro.md` covers the layers, rules and tools, and `docs/vfx/tanjiro-reference.md` breaks down the reference video. New textures under `art/effects/` need `mipmaps/generate=true` in their `.import` file.

**Front-end UI** uses the 「大正墨金」 procedural kit (`scripts/ui/kit.gd`, shaders in `scripts/ui/shaders/`), described in `docs/ui-redesign.md`. Bundled fonts are subsets: after adding or changing UI text, re-run `.venv\Scripts\python.exe -X utf8 tools/subset_fonts.py`. `tests/ui_redesign_tests.gd` fails when a UI character is missing from the bundled fonts.

## Conventions

- Godot creates a `.uid` file next to every new script or shader; commit it along with the source file.
- GDScript cannot infer types for `:=` declarations whose value comes from untyped references (for example `vfx.` or `move.` inside the technique scripts), so give those variables explicit types.
- `artifacts/` and `tmp/` hold regenerable local output and are not source. `output/` holds generation sources and provenance. `demo/` holds historical candidate showcases (one demo verifier, `demo/round-presentation/verify.gd`, is part of the regression suite).
