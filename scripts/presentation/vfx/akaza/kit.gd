extends RefCounted
## Shared constants for Akaza's effects after the Hinokami Chronicles look:
## spiky cyan shock bursts with a white-hot core, white air-pressure arcs and
## rings, comet-like air fists, a six-fold snowflake compass on the floor,
## crystal eruptions, dark dust and black rock. In his normal form the shock is
## the cyan of the Mugen Train arc; awakened (术式展开·罗针) it turns the blue-violet
## of the Infinity Castle arc, while the white-hot cores stay.

## Layers in draw order. FLOOR and SIGIL sit under both fighters (craters,
## trenches and floor cracks; the compass, floor light and the awakened flame
## outline showing round his body); GLOW is soft additive light one z under
## EffectsView so a struck fighter stays readable; FRONT carries the solid
## shapes (pressure arcs, dust, rock, crystal slabs, ink); LIGHT is additive
## light over everything (burst cores, sparks, flakes, rays, the red start-up).
enum {FLOOR, SIGIL, GLOW, FRONT, LIGHT}

const WHITE := Color(0.95, 0.99, 1.0)
## Shock body and its deep outer edge (Mugen Train).
const CYAN := Color(0.47, 0.88, 0.98)
const CYAN_DEEP := Color(0.13, 0.36, 0.86)
## The same while awakened (Infinity Castle).
const VIOLET := Color(0.58, 0.5, 0.97)
const VIOLET_DEEP := Color(0.28, 0.17, 0.82)
## Pale core tint shared by both forms.
const ICE := Color(0.72, 0.96, 1.0)
## Crystal slabs of a floor eruption, their grain lines and outlines.
const CRYSTAL := Color(0.36, 0.8, 0.97)
const CRYSTAL_LIGHT := Color(0.66, 0.95, 1.0)
const CRYSTAL_LINE := Color(0.05, 0.14, 0.45)
## The red start-up of every special: glow, hot core, deep blood and black ink.
const RED := Color(0.86, 0.3, 0.4)
const RED_HOT := Color(1.0, 0.64, 0.72)
const BLOOD := Color(0.6, 0.1, 0.12)
const INK := Color(0.14, 0.02, 0.04)
const DUST := Color(0.25, 0.26, 0.29)
const CRATER := Color(0.09, 0.07, 0.07)
## 青银乱残光's afterglow.
const SILVER := Color(0.88, 0.92, 1.0)
## Floor ellipses (compass, rings, craters) are seen from the side, this flat.
const FLOOR_SQUASH := 0.26

## Shock and arc colour: cyan normally, blue-violet while awakened.
static func tone(awakened: bool) -> Color:
	return VIOLET if awakened else CYAN

## The deep outer edge of a shock.
static func deep(awakened: bool) -> Color:
	return VIOLET_DEEP if awakened else CYAN_DEEP
