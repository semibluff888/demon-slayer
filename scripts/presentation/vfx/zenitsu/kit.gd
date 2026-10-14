extends RefCounted
## Shared constants for Zenitsu's effects after the Hinokami Chronicles look:
## gold iai light with a white-hot core, cyan-white lightning, comic starbursts
## with long thin rays, and thick dash beams. While awakened (雷之呼吸·神速) the
## lightning turns gold and strikes more often.

## Layers in draw order. BACK sits under both fighters (scorch on the floor, the
## far half of rings); GLOW is soft additive light one z under EffectsView so a
## struck fighter stays readable; FRONT carries the solid shapes (beams,
## crescents, stars, debris); LIGHT is additive light over everything.
enum {BACK, GLOW, FRONT, LIGHT}

const GOLD := Color(1.0, 0.76, 0.2)
const GOLD_HOT := Color(1.0, 0.92, 0.55)
const WHITE := Color(1.0, 0.99, 0.94)
const CYAN := Color(0.56, 0.93, 1.0)
const CYAN_DEEP := Color(0.2, 0.56, 1.0)
const NAVY := Color(0.12, 0.13, 0.38)
const EMBER := Color(1.0, 0.6, 0.16)
## Heat lightning (热界雷) glows orange instead of blue.
const HEAT := Color(1.0, 0.5, 0.2)
const SCORCH := Color(0.06, 0.05, 0.05)
const SPEED_LINE := Color(0.16, 0.15, 0.2)

## Bolt colour: cyan-white normally, gold while awakened.
static func bolt_tint(awakened: bool) -> Color:
	return GOLD_HOT if awakened else CYAN

## Outer glow of a bolt.
static func bolt_glow(awakened: bool) -> Color:
	return GOLD if awakened else CYAN_DEEP
