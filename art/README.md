# Local anime presentation assets

All game artwork is local. CPA generation is an offline production step using
`gpt-image-2` through the installed imagegen CLI. The game never reads API keys.

Each character has a transparent full-body portrait, a 192px avatar, and 19 motion
clips containing 112 original poses. `atlas.json` defines a shared 1024x640
reference canvas, feet/root anchor, physical scale, phase boundaries and packed
texture regions. One scale is used across each source clip; crouches and rotated
poses are never scaled individually to their bounding boxes. AtlasTexture margins
restore each trimmed region to its common anchor canvas at runtime.

`tools/process_anime_art.py` performs chroma cleanup, connected-component sprite
isolation, registered stage compositing, packing and contact-sheet/GIF previews.
Measured crops and anchors are retained in `output/imagegen/anime-v2/imports/`.
Art does not create collision shapes or change gameplay timing.

The five 2048x1152 stage layers share their source composition. Architecture and
floor use the same parallax offset to prevent a split at ground contact. Ambient
petals, lantern glow and fog are lightweight independent engine effects. Four
black-backed combat VFX textures use additive compositing.

Fonts are Noto Sans SC and Noto Serif SC under SIL OFL 1.1. Full license texts are
in `fonts/`; `tools/subset_fonts.py` rebuilds glyph coverage from game text.

Originals, prompts, request records and unknown billing status are recorded under
`output/imagegen/anime-v2/`. Refer to `output/imagegen/manifest.json` for final
acceptance and to `artifacts/` for actual Godot screenshots and performance.
