extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## 鬼化·爆血 (Nezuko's awakening, her demon form). On activation, through the
## awakening freeze and start-up, her blood gathers in a ring of black-red ink,
## then fire bursts up round her in a pillar with flakes and embers flying and a
## ring of dust; while she stays in the demon form a flickering crimson flame
## outline clings to her body, shedding embers and torn flakes, with a faint
## glow on the floor under her; when the form ends it fades. Driven by the
## fighters' awakening state and events, not by a move.

## Frames from the awakening event to the settled form (freeze 12 + start-up 18).
const CAST := 30
## When the gathered blood bursts into the pillar of fire, in frames.
const BURST := 12.0
const FADE := 0.35

## Demon-form Nezuko fighters by slot: {"age": frames since the awakening began}.
var _awake: Dictionary = {}
## Outlines fading out: {"slot", "born"}.
var _fading: Array[Dictionary] = []

func reset() -> void:
	super()
	_awake.clear()
	_fading.clear()

func consume(events: Array, fighters: Array, actors: Array) -> void:
	for event: Dictionary in events:
		if event.type != "awakening_start" or not event.has("attacker") or int(event.attacker) >= fighters.size():
			continue
		var f = fighters[int(event.attacker)]
		if str(f.character) != "nezuko":
			continue
		_awake[f.slot] = {"age": 0}
		vfx.focus = f.slot
		vfx.ember_burst(vfx.world(f, Vector2(0.0, -40.0)), 14, Vector2(0.0, -0.4), 60.0, 180.0, f.slot * 131 + 7, true)
		vfx.focus = -1
	for f in fighters:
		if str(f.character) != "nezuko":
			continue
		var on: bool = f.awakening_ticks > 0 and f.hp > 0
		if not on:
			if _awake.has(f.slot):
				_fading.append({"slot": f.slot, "born": vfx.time})
				_awake.erase(f.slot)
			continue
		if not _awake.has(f.slot):
			# Already in the demon form (a restored round, a test): no casting.
			_awake[f.slot] = {"age": CAST}
		var state: Dictionary = _awake[f.slot]
		state.age = int(state.age) + 1
		var age: int = state.age
		var seed: int = f.slot * 977 + age * 13
		vfx.focus = f.slot
		if age == int(BURST) + 1:
			var feet := Vector2(f.x, Arena.FLOOR_Y)
			vfx.flake_burst(feet + Vector2(0.0, -30.0), 14, 120.0, seed, true, 90.0)
			vfx.ember_burst(feet + Vector2(0.0, -20.0), 20, Vector2(0.0, -1.0), 90.0, 260.0, seed + 1, true)
			vfx.dust_burst(feet, 7, Vector2.ZERO, seed + 2, 1.2)
			vfx.bursts.append({"kind": "ring", "at": feet + Vector2(0.0, -2.0), "age": 0.0, "life": 0.3, "size": 40.0, "squash": 0.45, "facing": float(f.facing),
				"seed": seed + 3, "awake": true})
		var frozen: bool = int(vfx.combat.hitstop) > 0 or int(vfx.combat.super_freeze) > 0
		var actor: Node2D = actors[f.slot] if f.slot < actors.size() else null
		if age > CAST and age % 3 == 0 and not frozen and actor != null and actor.texture != null:
			# Embers and torn flakes drifting up off her body (none pile up through a freeze).
			var bounds: Rect2 = actor.visual_bounds()
			var at := Vector2(f.x, f.y) + bounds.position + Vector2(vfx.rand(seed, 1) * bounds.size.x, vfx.rand(seed, 2) * bounds.size.y * 0.8)
			vfx.embers.spawn(at, Vector2((vfx.rand(seed, 3) - 0.5) * 14.0, -lerpf(26.0, 52.0, vfx.rand(seed, 4))), lerpf(0.35, 0.6, vfx.rand(seed, 5)),
				lerpf(1.6, 2.8, vfx.rand(seed, 6)), 0, Color(1.0, 0.8, 0.84), -20.0, 1.0, 0.0, 0.0, 0.6)
			if age % 9 == 0:
				vfx.flake_burst(at, 1, 20.0, seed + 7, true, 30.0)
		vfx.focus = -1
	_fading = _fading.filter(func(c: Dictionary) -> bool: return vfx.time - float(c.born) < FADE)

func draw_all(canvas: Node2D, layer: int, fighters: Array, actors: Array) -> void:
	for f in fighters:
		if not _awake.has(f.slot) or f.slot >= actors.size() or actors[f.slot] == null:
			continue
		var actor: Node2D = actors[f.slot]
		var age: float = float(_awake[f.slot].age) + vfx.frac
		vfx.focus = f.slot
		vfx.set_base(canvas, vfx.frame_transform(f.x, f.y, f.facing))
		if age < CAST:
			var gather := smoothstep(0.0, 4.0, age) * (1.0 - smoothstep(BURST - 2.0, BURST + 2.0, age))
			vfx.activation(canvas, layer, f, actor, gather, f.slot * 29 + 3, true)
			var rise := smoothstep(BURST - 1.0, BURST + 4.0, age) * (1.0 - smoothstep(float(CAST) - 8.0, float(CAST), age))
			vfx.pillar(canvas, layer, Vector2.ZERO, 120.0 * rise, 36.0, rise, true, f.slot * 31, age / 60.0)
			if layer == Kit.LIGHT:
				vfx.body_flash(canvas, f, actor, Color(Kit.CRIMSON, 0.45 * rise))
		var settle := smoothstep(BURST, float(CAST), age)
		var lift := 1.0 - clampf((Arena.FLOOR_Y - f.y) / 160.0, 0.0, 0.7)
		if layer == Kit.SIGIL:
			var flicker: int = floori(float(_awake[f.slot].age) / 3.0)
			vfx.aura(canvas, f, actor, Color(Kit.CRIMSON, 0.3 * settle), f.slot * 101 + flicker)
			if vfx.glow != null:
				vfx.set_base(canvas, vfx.world_transform(Vector2(f.x, Arena.FLOOR_Y)))
				canvas.draw_texture_rect(vfx.glow, Rect2(Vector2(-44.0, -12.0), Vector2(88.0, 24.0)), false, Color(Kit.CRIMSON_DEEP, 0.5 * settle * lift))
		vfx.focus = -1
	for held: Dictionary in _fading:
		var slot: int = held.slot
		if slot >= fighters.size() or slot >= actors.size() or actors[slot] == null:
			continue
		var k := clampf((vfx.time - float(held.born)) / FADE, 0.0, 1.0)
		if layer == Kit.SIGIL:
			vfx.focus = slot
			vfx.aura(canvas, fighters[slot], actors[slot], Color(Kit.CRIMSON, 0.3 * (1.0 - k)), slot * 101)
			vfx.focus = -1

## Whether the demon form's effects are shown for `slot` (tests).
func showing(slot: int) -> bool:
	return _awake.has(slot)
