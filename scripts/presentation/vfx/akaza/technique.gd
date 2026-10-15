extends RefCounted
## One of Akaza's rebuilt techniques. AkazaVfx calls these hooks; shapes are
## drawn from the move clock, particles are emitted once per combat tick.
const Kit = preload("res://scripts/presentation/vfx/akaza/kit.gd")
## Centrelines shared with Tanjiro's effects (Sweep, Arc...).
const Paths = preload("res://scripts/presentation/vfx/tanjiro/paths.gd")
const Ribbon = preload("res://scripts/presentation/vfx/vfx_ribbon.gd")
const Arena = preload("res://scripts/arena_rules.gd")
## Frames the red start-up of a special lasts.
const ACTIVATION := 7.0

## The owning AkazaVfx: pools, textures, drawing helpers.
var vfx: Node2D
## World point where a dash began, by slot: {"instance", "x", "y", "facing"}.
var _origins: Dictionary = {}
## Where a shape stays once the move's active frames end, by slot.
var _anchors: Dictionary = {}

## Particles for combat tick `tick` of the fighter's move.
func emit(_f: RefCounted, _actor: Node2D, _tick: int) -> void:
	pass

## Shapes for one layer, with the canvas already in fighter-local units.
func draw(_canvas: Node2D, _layer: int, _f: RefCounted, _actor: Node2D) -> void:
	pass

## A hit or block event from this move.
func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var scale: float = 1.0 if move.kind in ["skill", "super", "max"] else (0.75 if move.kind == "heavy" else 0.5)
	vfx.strike(event, attacker, scale, awakened)

## A projectile of this move moved one tick: `shot` is a copy of its combat state.
func emit_shot(_shot: Dictionary, _awakened: bool) -> void:
	pass

## A projectile of this move vanished without striking anyone (floor, range, clash).
func shot_ended(_shot: Dictionary, _awakened: bool) -> void:
	pass

## A live projectile, with the canvas in its local units (+x along its facing).
func draw_shot(_canvas: Node2D, _layer: int, _shot: Dictionary, _awakened: bool) -> void:
	pass

## A burst this technique added with "technique": self, at age fraction `k`.
func draw_burst(_canvas: Node2D, _layer: int, _burst: Dictionary, _k: float) -> void:
	pass

func reset() -> void:
	_origins.clear()
	_anchors.clear()

## Every presentation step, after emission: effects that outlive their move.
func linger(_fighters: Array, _actors: Array) -> void:
	pass

## Shapes that outlive their move, drawn on every layer with no base set.
func draw_lingering(_canvas: Node2D, _layer: int) -> void:
	pass

static func heavy(move: Resource) -> bool:
	return move.id.ends_with("C") or move.id.ends_with("D")

## Move time in frames, with the sub-tick fraction when interpolating.
func clock(f: RefCounted) -> float:
	return float(f.move_frame) + vfx.frac

## Frames since a super began, counting the super freeze (during which the move
## clock holds at 0 while combat ticks on), so the charge keeps moving.
func charge_age(f: RefCounted) -> float:
	var held: int = f.move.freeze_frames
	var waiting: int = mini(int(vfx.combat.super_freeze), held) if f.move_frame == 0 else 0
	return float(held - waiting) + clock(f)

## Records where this attack's dash starts (the first emitted tick at or past `from_tick`).
func mark_origin(f: RefCounted, tick: int, from_tick: int = 0) -> void:
	var held: Dictionary = _origins.get(f.slot, {})
	if tick >= from_tick and int(held.get("instance", -1)) != f.attack_instance:
		_origins[f.slot] = {"instance": f.attack_instance, "x": f.x, "y": f.y, "facing": f.facing}

## The dash origin in the fighter's local frame (falls back to the fighter itself).
func origin_local(f: RefCounted, height: float) -> Vector2:
	var held: Dictionary = _origins.get(f.slot, {})
	if int(held.get("instance", -1)) != f.attack_instance:
		return Vector2(0.0, height)
	return Vector2((float(held.x) - f.x) * f.facing, float(held.y) - f.y + height)

## Records the anchor on the last active tick, so the shape stops following.
func anchor(f: RefCounted, tick: int) -> void:
	if tick == f.move.startup + f.move.active - 1:
		_anchors[f.slot] = {"instance": f.attack_instance, "x": f.x, "y": f.y, "facing": f.facing}

## Fighter-local frame for drawing and emitting: the fighter while active, the
## recorded anchor afterwards.
func frame(f: RefCounted, t: float) -> Dictionary:
	var held: Dictionary = _anchors.get(f.slot, {})
	if t >= f.move.startup + f.move.active and int(held.get("instance", -1)) == f.attack_instance:
		return held
	return {"x": f.x, "y": f.y, "facing": f.facing}

## The opponent's chest in this fighter's local frame when it stands within
## `reach` in front of him, else `fallback`: blows burst on the target, not past it.
func target_local(f: RefCounted, fallback: Vector2, reach: float) -> Vector2:
	var other = vfx.combat.fighters[1 - f.slot]
	var dx: float = (other.x - f.x) * f.facing
	if dx > 0.0 and dx <= reach:
		return Vector2(dx, other.y - f.y - 38.0)
	return fallback

## A world point in this fighter's local frame.
static func local_of(f: RefCounted, world_point: Vector2) -> Vector2:
	return Vector2((world_point.x - f.x) * f.facing, world_point.y - f.y)

## Start indices of the move's hit segments.
func starts(move: Resource) -> Array:
	return Array(move.hit_frames) if not move.hit_frames.is_empty() else [move.startup]

## The red start-up flash (a short 0..1 envelope over the first frames).
func activation_strength(t: float) -> float:
	if t >= ACTIVATION:
		return 0.0
	return smoothstep(0.0, 1.5, t + 1.0) * (1.0 - smoothstep(ACTIVATION * 0.45, ACTIVATION, t))

## Red sparks and ink flung off the start-up, on its first ticks.
func emit_activation(f: RefCounted, tick: int, centre: Vector2 = Vector2(0.0, -40.0)) -> void:
	if tick > 1:
		return
	var seed: int = f.attack_instance * 211 + f.slot * 7919 + tick * 13
	vfx.spark_burst(vfx.world(f, centre), 10, Vector2(0.0, -0.4), 60.0, 170.0, seed, Kit.RED_HOT)
