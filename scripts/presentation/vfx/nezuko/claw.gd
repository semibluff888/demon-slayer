extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## Claws (5A/5C, 2A/2C, jA/jC), after 乱裂: three burning claw strokes rake
## across in front of her, each a little behind the one before, shedding torn
## flakes of blood; heavies are longer and wider, and on the ground they leave
## crimson scratches in the floor.

## Claw strokes (start, control, end) by clip, fighter-local, fitted to the drawn
## active frames: the light swipes rake down across the chest, 5C is a big
## diagonal, 2C rakes upward, jC down. STROKES fits the v3 drawing (the claw tips
## measured on the packed atlas, each stroke keeping its shape round the claw at the
## v3 body size), DEMON_STROKES the kept demon-form drawing (tools/build_vfx_fit_sheet.py).
const STROKES := {
	"stand_light": [Vector2(11, -52), Vector2(26, -47), Vector2(29, -29)],
	"stand_heavy": [Vector2(3, -67), Vector2(34, -53), Vector2(34, -16)],
	"crouch_light": [Vector2(15, -30), Vector2(30, -23), Vector2(33, -5)],
	"crouch_heavy": [Vector2(22, -10), Vector2(29, -48), Vector2(15, -84)],
	"air_light": [Vector2(21, -62), Vector2(37, -55), Vector2(38, -37)],
	"air_heavy": [Vector2(6, -54), Vector2(33, -37), Vector2(26, -4)],
}
const DEMON_STROKES := {
	"stand_light": [Vector2(20, -70), Vector2(38, -64), Vector2(42, -42)],
	"stand_heavy": [Vector2(10, -84), Vector2(46, -68), Vector2(46, -24)],
	"crouch_light": [Vector2(24, -50), Vector2(42, -42), Vector2(46, -18)],
	"crouch_heavy": [Vector2(34, -6), Vector2(44, -40), Vector2(28, -80)],
	"air_light": [Vector2(22, -66), Vector2(40, -58), Vector2(42, -36)],
	"air_heavy": [Vector2(10, -66), Vector2(42, -46), Vector2(34, -6)],
}
## Seconds the floor scratches of a grounded heavy stay.
const SCRATCH := 0.9

func stroke(f: RefCounted, move: Resource) -> Array:
	var table: Dictionary = fit(f, STROKES, DEMON_STROKES)
	return reaching(move, table.get(move.clip_id(), table["stand_light"]))

func big(move: Resource) -> bool:
	return move.kind == "heavy"

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	if tick != move.startup:
		return
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 173 + f.slot * 7919 + tick * 31
	var keys := stroke(f, move)
	var end: Vector2 = keys[2]
	var mid: Vector2 = keys[1]
	vfx.ember_burst(vfx.world(f, mid), 12 if big(move) else 6, vfx.world_dir(f, (end - Vector2(keys[0])).normalized()) * 0.8, 70.0, 190.0, seed, awake)
	vfx.flake_burst(vfx.world(f, mid), 5 if big(move) else 2, 60.0, seed + 1, awake, 20.0)
	if big(move) and f.grounded:
		vfx.bursts.append({"kind": "scratch", "technique": self, "at": vfx.world(f, Vector2(fit(f, 30.0, 40.0), 0.0)), "age": 0.0, "life": SCRATCH, "size": 34.0,
			"facing": float(f.facing), "seed": seed + 2, "awake": awake})

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var since := clock(f) - float(move.startup)
	if since < -1.5 or since > move.active + 10.0:
		return
	var head := clampf((since + 1.5) / 2.5, 0.0, 1.0)
	var tail := clampf((since - 1.5) / (8.0 if big(move) else 6.0), 0.0, 1.25)
	vfx.claws(canvas, layer, stroke(f, move), 3, 7.0 if big(move) else 5.0, head, tail, 1.0, awake, 9.0 if big(move) else 6.0, f.attack_instance)

func draw_burst(canvas: Node2D, layer: int, burst: Dictionary, k: float) -> void:
	if burst.kind == "scratch":
		vfx.scratches(canvas, layer, Vector2.ZERO, float(burst.size), 3, 1.0 - smoothstep(0.5, 1.0, k), int(burst.seed), burst.get("awake", false))
