# Local anime presentation assets

All game artwork is local. CPA generation is an offline production step using
`gpt-image-2` through the installed imagegen CLI. The game never reads API keys.

Each character has a transparent full-body portrait, a 192px avatar, and 25 motion
clips containing 168 original poses. `atlas.json` defines a shared 1024x640
reference canvas, feet/root anchor, physical scale, phase boundaries and packed
texture regions. One scale is used across each source clip; crouches and rotated
poses are never scaled individually to their bounding boxes. AtlasTexture margins
restore each trimmed region to its common anchor canvas at runtime.

`tools/process_anime_art.py` performs chroma cleanup, connected-component sprite
isolation, registered stage compositing, packing and contact-sheet/GIF previews.
Measured crops and anchors are retained in `output/imagegen/anime-v2/imports/`.
Art does not create collision shapes or change gameplay timing.

The stage uses one 4608x1152 continuous painting (`stages/wisteria/panorama.png`).
The moon, lake reflection, architecture and pavement share a single Sprite2D and
world transform. Old sky and foreground cutouts are retained as historical art,
but are no longer drawn. Ambient petals and fog remain independent effects.
Four black-backed combat VFX textures use additive compositing.

Fonts are Noto Sans SC and Noto Serif SC under SIL OFL 1.1. Full license texts are
in `fonts/`; `tools/subset_fonts.py` rebuilds glyph coverage from game text.

Originals, prompts, request records and unknown billing status are recorded under
`output/imagegen/anime-v2/`. Refer to `output/imagegen/manifest.json` for final
acceptance and to `artifacts/` for actual Godot screenshots and performance.


Movement revision (September 2026): forward/back dashes, forward/back somersaults,
grab whiff, linked shoulder throw and victim poses use versioned CPA sources.
Rotating poses register to an anatomical pelvis anchor, not their lowest visible
pixel. Source-wide scale and measured anchor corrections live in calibration.json.
The visual-polish revision replaces the three-panel courtyard with one coherent
panorama. `tools/build_continuous_stage.py` reproducibly finishes the accepted
source locally and registers the terrace to the fighting lane. The original CPA
output remains unchanged; its real dimensions and SHA-256 are recorded in stage.json.

Head/hand/limb comparisons establish corrected clip-wide anatomy scales for runs,
flips, jump recovery, aerial strikes and forward skills. `calibrate()` preserves
these measured overrides on rebuild. The calm idle drawing breathes continuously
at runtime (3.2 seconds, +/-0.3% vertically) around its fixed feet anchor; the six
source idle drawings remain available as source artwork.

Rebuild with python tools/build_movement_art.py (offline). Current visual review:
artifacts/visual-polish/review.md and preview.mp4. Finalize the current evidence
with tools/finalize_visual_polish.py after checks and capture.
