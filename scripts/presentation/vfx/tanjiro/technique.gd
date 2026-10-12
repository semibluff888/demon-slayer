extends RefCounted
## One of Tanjiro's rebuilt techniques. TanjiroVfx calls these hooks; shapes are
## drawn from the move clock, particles are emitted once per combat tick.
const Kit = preload("res://scripts/presentation/vfx/tanjiro/kit.gd")
const Paths = preload("res://scripts/presentation/vfx/tanjiro/paths.gd")
const Ribbon = preload("res://scripts/presentation/vfx/vfx_ribbon.gd")

## The owning TanjiroVfx: pools, textures, drawing helpers.
var vfx: Node2D
## Where a detached shape stays once the move's active frames end, by slot.
var _anchors: Dictionary = {}

## Particles for combat tick `tick` of the fighter's move.
func emit(_f: RefCounted, _actor: Node2D, _tick: int) -> void:
	pass

## Shapes for one layer, with the canvas already in fighter-local units.
func draw(_canvas: Node2D, _layer: int, _f: RefCounted, _actor: Node2D) -> void:
	pass

## A hit or block event from this move.
func contact(_event: Dictionary, _move: Resource, _attacker: RefCounted, _hybrid: bool) -> void:
	pass

func reset() -> void:
	clear_anchors()

# Released projectiles (only the water slash has one).
func emit_projectile(_p: Dictionary, _move: Resource, _tick: int, _age: int) -> void:
	pass

func draw_projectile(_canvas: Node2D, _layer: int, _p: Dictionary, _move: Resource) -> void:
	pass

func release_projectile(_record: Dictionary) -> void:
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

func clear_anchors() -> void:
	_anchors.clear()

## Beads of water drawn in toward the raised blade during startup.
func gather_beads(f: RefCounted, actor: Node2D, tick: int, seed: int, tint: Color = Color(1, 1, 1, 0.95)) -> void:
	var held: PackedVector2Array = vfx.blade(actor, actor.move_clip_frame(tick) if actor.clip == f.move.clip_id() else actor.frame_index)
	if held.size() != 2:
		return
	for n in range(3):
		var target := held[0].lerp(held[1], 0.3 + 0.65 * vfx.rand(seed, n))
		var offset: Vector2 = Vector2.from_angle(vfx.rand(seed, n + 3) * TAU) * (10.0 + 8.0 * vfx.rand(seed, n + 5))
		vfx.drops.spawn(vfx.world(f, target + offset), vfx.world_dir(f, -offset) / 0.2, 0.2, lerpf(1.4, 2.4, vfx.rand(seed, n + 7)), 0, tint)
