extends "res://scripts/presentation/vfx/akaza/technique.gd"
## 术式展开·罗针 (Akaza's awakening). On activation the compass is cast round his
## feet through the awakening freeze and start-up: drawn outward in red with the
## red start-up on his body, then it turns blue, shafts of light rise
## from its rim and flakes fly. While he stays awakened a fainter compass turns
## under him (it brightens for a moment whenever he lands a hit) and a
## flickering royal-blue flame outline clings to his body, shedding wisps; when
## the awakening ends the compass fades. Driven by the fighters' awakening state
## and events, not by a move.

## Frames from the awakening event to the settled compass (freeze 12 + start-up 18).
const CAST := 30
## Activation milestones, in frames from the awakening event.
const REVEAL := 12.0
const TURN := 18.0
const RADIUS := 46.0
const FADE := 0.35
## How long a hit makes the compass flare (seconds).
const PULSE := 0.25
## The awakened compass glows a clear cyan-blue over lines painted in a deep navy
## ink (an additive glow alone reads pale on the dark floor). Second review: the
## violet of the first version read as a washed-out lilac; the reference's compass
## is cyan-blue and its Infinity Castle flames royal blue (Kit.AZURE).
const GLOW := Color(0.37, 0.63, 1.0)
const INK := Color(0.04, 0.15, 0.5, 0.8)

## Awakened Akaza fighters by slot: {"age": frames since the awakening began}.
var _awake: Dictionary = {}
## Presentation time of the last hit landed while awakened, by slot.
var _pulse: Dictionary = {}
## Compasses fading out: {"x", "born", "spin"}.
var _fading: Array[Dictionary] = []

func reset() -> void:
	super()
	_awake.clear()
	_pulse.clear()
	_fading.clear()

func spin() -> float:
	return vfx.time * 0.25

func consume(events: Array, fighters: Array, actors: Array) -> void:
	for event: Dictionary in events:
		if not event.has("attacker") or int(event.attacker) >= fighters.size():
			continue
		var f = fighters[int(event.attacker)]
		if str(f.character) != "akaza":
			continue
		if event.type == "awakening_start":
			_awake[f.slot] = {"age": 0}
			var seed: int = f.slot * 131 + 7
			vfx.spark_burst(vfx.world(f, Vector2(0.0, -40.0)), 16, Vector2(0.0, -0.4), 70.0, 200.0, seed, Kit.RED_HOT)
		elif event.type == "hit" and _awake.has(f.slot):
			_pulse[f.slot] = vfx.time
	for f in fighters:
		if str(f.character) != "akaza":
			continue
		var on: bool = f.awakening_ticks > 0 and f.hp > 0
		if not on:
			if _awake.has(f.slot):
				_fading.append({"x": f.x, "born": vfx.time, "spin": spin()})
				_awake.erase(f.slot)
			continue
		if not _awake.has(f.slot):
			# Already awake (a restored round, a test): no casting, just the compass.
			_awake[f.slot] = {"age": CAST}
		var state: Dictionary = _awake[f.slot]
		state.age = int(state.age) + 1
		var age: int = state.age
		var awake_now: bool = f.slot < actors.size() and actors[f.slot] != null
		var seed: int = f.slot * 977 + age * 13
		if age == int(REVEAL) + 1:
			# The compass turns: flakes and dust fly off its rim.
			for n in range(6):
				var a := TAU * n / 6.0
				var rim: Vector2 = Vector2(f.x, Arena.FLOOR_Y) + Vector2(cos(a), sin(a) * Kit.FLOOR_SQUASH) * RADIUS * vfx.body_scale()
				vfx.flake_burst(rim, 2, 50.0, seed + n, true, 70.0)
			vfx.dust_burst(Vector2(f.x, Arena.FLOOR_Y), 6, Vector2.ZERO, seed + 9, 1.1)
		var frozen: bool = int(vfx.combat.hitstop) > 0 or int(vfx.combat.super_freeze) > 0
		if age % 2 == 0 and not frozen and awake_now and actors[f.slot].texture != null:
			# Wisps of blue flame drifting off his body (none pile up through a freeze).
			var bounds: Rect2 = actors[f.slot].visual_bounds()
			var at := Vector2(f.x, f.y) + bounds.position + Vector2(vfx.rand(seed, 1) * bounds.size.x, vfx.rand(seed, 2) * bounds.size.y * 0.8)
			vfx.flakes.spawn(at, Vector2((vfx.rand(seed, 3) - 0.5) * 14.0, -lerpf(26.0, 48.0, vfx.rand(seed, 4))), lerpf(0.35, 0.6, vfx.rand(seed, 5)),
				lerpf(2.0, 3.4, vfx.rand(seed, 6)), 0, Kit.AZURE.lerp(Kit.ICE, 0.3 * vfx.rand(seed, 7)), -20.0, 1.0, 0.0, 0.0, 0.6)
	_fading = _fading.filter(func(c: Dictionary) -> bool: return vfx.time - float(c.born) < FADE)

func draw_all(canvas: Node2D, layer: int, fighters: Array, actors: Array) -> void:
	for f in fighters:
		if not _awake.has(f.slot) or f.slot >= actors.size() or actors[f.slot] == null:
			continue
		var actor: Node2D = actors[f.slot]
		var age: float = float(_awake[f.slot].age) + vfx.frac
		var height: float = Arena.FLOOR_Y - f.y
		var lift := 1.0 - clampf(height / 160.0, 0.0, 0.6)
		var casting: bool = age < CAST
		var color := Kit.RED.lerp(GLOW, smoothstep(REVEAL, TURN, age)) if casting else GLOW
		var radius := lerpf(26.0, 58.0, smoothstep(0.0, REVEAL + 2.0, age)) if age < TURN else lerpf(58.0, RADIUS, smoothstep(TURN, float(CAST), age))
		var flare := 1.0 - clampf((vfx.time - float(_pulse.get(f.slot, -10.0))) / PULSE, 0.0, 1.0)
		var alpha := 1.0 if casting else 0.45 + 0.5 * flare
		vfx.set_base(canvas, vfx.world_transform(Vector2(f.x, Arena.FLOOR_Y)))
		var ink := Color(INK, INK.a * smoothstep(REVEAL, TURN, age))
		vfx.compass_shape(canvas, layer, Vector2.ZERO, radius, clampf(age / REVEAL, 0.0, 1.0), spin(), color, alpha * lift, ink)
		if casting and layer == Kit.LIGHT and age > REVEAL:
			# Shafts of light rising from the rim as the compass turns.
			var k := smoothstep(REVEAL, TURN, age) * (1.0 - smoothstep(TURN + 4.0, float(CAST), age))
			for n in range(6):
				var a := TAU * n / 6.0 + spin()
				var foot := Vector2(cos(a) * radius * 0.92, sin(a) * radius * 0.92 * Kit.FLOOR_SQUASH)
				var tall := lerpf(50.0, 100.0, vfx.rand(f.slot, n))
				Ribbon.draw(canvas, PackedVector2Array([foot, foot + Vector2(0.0, -tall * k)]), PackedFloat32Array([5.0, 0.0]),
					PackedColorArray([Color(Kit.ICE, 0.8 * k), Color(Kit.AZURE, 0.0)]), vfx.band)
		# The red start-up on his body, then the flame outline.
		vfx.set_base(canvas, vfx.frame_transform(f.x, f.y, f.facing))
		if casting:
			var red := 1.0 - smoothstep(4.0, REVEAL, age)
			vfx.activation(canvas, layer, f, actor, red, f.slot * 29 + 3)
			if layer == Kit.LIGHT:
				vfx.body_flash(canvas, f, actor, Color(Kit.AZURE, 0.4 * smoothstep(REVEAL, TURN, age) * (1.0 - smoothstep(TURN, float(CAST), age))))
		if layer == Kit.SIGIL:
			var flicker: int = floori(float(_awake[f.slot].age) / 3.0)
			vfx.aura(canvas, f, actor, Color(Kit.AZURE, 0.26 * smoothstep(REVEAL, TURN + 6.0, age)), f.slot * 101 + flicker)
	for held: Dictionary in _fading:
		var k := clampf((vfx.time - float(held.born)) / FADE, 0.0, 1.0)
		vfx.set_base(canvas, vfx.world_transform(Vector2(float(held.x), Arena.FLOOR_Y)))
		vfx.compass_shape(canvas, layer, Vector2.ZERO, RADIUS, 1.0, float(held.spin), GLOW, 0.45 * (1.0 - k), Color(INK, INK.a * (1.0 - k)))

## Whether the compass is shown for `slot` (tests).
func showing(slot: int) -> bool:
	return _awake.has(slot)
