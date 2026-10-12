extends RefCounted
## Shared constants for Tanjiro's effects: layer order, sprite-sheet cells, the
## water strand bundle and the Hinokami Kagura flame woven into it while awakened.

## Layers in draw order. BACK sits under both fighters (the far side of wrapped
## shapes); WATER and SOLID sit one z below EffectsView so a struck fighter
## (raised to the effects z) stays readable over the body of the water; FRONT
## carries contact splashes and spray, which belong in front of everyone.
enum {BACK, WATER, SOLID, FRONT, FLAME, LIGHT}

## Foam sheet cells.
const CURL_CELLS := [0, 2, 7, 8, 12, 15]
const SPRAY_CELLS := [1, 3, 5, 6, 10, 11]
const CLOUD_CELLS := [4, 14]
## Crimson flame sheet cells: torn flame pieces, and clusters of small chips.
const PETAL_CELLS := [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15]
const SPARK_CELLS := [4, 12]
const FLAME_CELLS := PETAL_CELLS + SPARK_CELLS
## Sun flame sheet (yellow-white cores) for pure Hinokami Kagura.
const SUN_TONGUE_CELLS := [0, 2, 4, 9, 10, 11, 13]
const SUN_SPARK_CELLS := [1, 5, 14, 15]

## Strand bundle of a water body, inner to outer: offset and width (fractions
## of the body thickness), tail/head trims, tint, texture rows, flow speed.
const STRANDS := [
	{"offset": -0.40, "width": 0.34, "from": 0.10, "to": 0.92, "tint": Color(0.74, 0.8, 1.0), "rows": [0.5, 0.82], "flow": 1.4},
	{"offset": -0.16, "width": 0.46, "from": 0.00, "to": 0.97, "tint": Color(0.9, 0.94, 1.0), "rows": [0.38, 0.74], "flow": 1.05},
	{"offset": 0.10, "width": 0.5, "from": 0.05, "to": 1.0, "tint": Color(1, 1, 1), "rows": [0.28, 0.64], "flow": 0.85},
	{"offset": 0.36, "width": 0.42, "from": 0.2, "to": 1.0, "tint": Color(1.06, 1.06, 1.06), "rows": [0.04, 0.5], "flow": 0.7},
]
## Frayed threads trailing off the tail.
const FRAYS := [{"offset": -0.62, "width": 0.13, "to": 0.34}, {"offset": -0.05, "width": 0.11, "to": 0.28}, {"offset": 0.58, "width": 0.12, "to": 0.4}]
## Flame woven into the water while awakened. `after` is the water strand each
## one is drawn over (braided between strands); `after` equal to the strand
## count lays the flame on top of all the water.
const FLAMES := [
	{"after": 0, "offset": -0.24, "width": 0.66, "from": 0.14, "to": 0.9, "flow": 1.9},
	{"after": 1, "offset": 0.0, "width": 0.66, "from": 0.06, "to": 0.95, "flow": 2.1},
	{"after": 2, "offset": 0.24, "width": 0.6, "from": 0.12, "to": 0.98, "flow": 1.7},
	{"after": 4, "offset": -0.34, "width": 0.4, "from": 0.0, "to": 0.5, "flow": 2.4},
	{"after": 4, "offset": 0.1, "width": 0.3, "from": 0.56, "to": 0.88, "flow": 2.0},
	{"after": 4, "offset": 0.52, "width": 0.38, "from": 0.28, "to": 1.0, "flow": 2.2},
]
## Torn flame pieces clinging to the water: position along it and across it.
const FLAME_PATCHES := [[0.12, -0.2], [0.24, 0.3], [0.36, -0.05], [0.47, 0.45], [0.58, -0.3], [0.68, 0.15], [0.8, -0.1], [0.9, 0.38]]

const WATER_GLOW := Color(0.22, 0.52, 1.0)
const FIRE_GLOW := Color(1.0, 0.24, 0.12)
const SUN_GLOW := Color(1.0, 0.55, 0.16)
const WATER_MIST := Color(0.85, 0.95, 1.0, 0.3)
