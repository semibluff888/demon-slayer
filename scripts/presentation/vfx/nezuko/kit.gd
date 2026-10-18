extends RefCounted
## Shared constants for Nezuko's effects after the Hinokami Chronicles 爆血: pink
## blood flame with a white-hot core and deep crimson, torn edges; claw strokes in
## threes; flakes of burning blood; white air arcs and manga impact stars; dark
## dust, black rock and scorched floors. In her normal form the fire is the pink
## of 血鬼术·爆血; in her demon form (鬼化) it turns a redder, darker crimson.

## Layers in draw order. FLOOR and SIGIL sit under both fighters (craters, claw
## scratches and scorch marks; floor glow and the demon form's flame outline
## showing round her body); GLOW is soft additive light one z under EffectsView so
## a struck fighter stays readable; FRONT carries the solid shapes (flame, claws,
## ink, air arcs, stars, dust, rock); LIGHT is additive light over everything
## (cores, embers, cross flashes, the start-up glow).
enum {FLOOR, SIGIL, GLOW, FRONT, LIGHT}

const WHITE := Color(1.0, 0.98, 0.99)
## Blood flame: body and deep edge, normal form (爆血).
const PINK := Color(0.96, 0.32, 0.64)
const PINK_DEEP := Color(0.62, 0.06, 0.3)
## The same in her demon form (爆血·猛击): redder and darker.
const CRIMSON := Color(1.0, 0.2, 0.36)
const CRIMSON_DEEP := Color(0.5, 0.02, 0.1)
## Pale hot core shared by both forms.
const BLUSH := Color(1.0, 0.8, 0.92)
## The yellow-white cross flash of a clean hit.
const FLASH := Color(1.0, 0.95, 0.68)
## Blood gathering for a special: dark crimson glow and black-red ink.
const BLOOD := Color(0.55, 0.04, 0.12)
const INK := Color(0.12, 0.01, 0.04)
## Rock, multiplied over the grey chunks of art/effects/akaza/rocks.png: dark
## stone, and the same lit pink from below by the fire.
const ROCK := Color(0.3, 0.27, 0.28)
const ROCK_LIT := Color(0.9, 0.42, 0.58)
const DUST := Color(0.25, 0.23, 0.24)
const CRATER := Color(0.1, 0.05, 0.05)
## Floor scorch left by claws and fire.
const SCORCH := Color(0.3, 0.02, 0.08)
## Floor ellipses (rings, craters) are seen from the side, this flat.
const FLOOR_SQUASH := 0.26

## Flame colour: pink normally, crimson in the demon form.
static func tone(awakened: bool) -> Color:
	return CRIMSON if awakened else PINK

## The deep outer edge of the flame.
static func deep(awakened: bool) -> Color:
	return CRIMSON_DEEP if awakened else PINK_DEEP
