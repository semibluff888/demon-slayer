extends "res://scripts/presentation/vfx/zenitsu/technique.gd"
## Sword normals and 稻魂 (5A/5C, 2A/2C, jA/jC, 5A > A > C): a thin cyan-white
## electric crescent along the authored cut, gold with a lightning fringe on
## heavies and while awakened, gold sparks thrown off the edge as it lands.
## 稻魂's last stage cuts twice: the second crescent sweeps back the other way.

func starts(move: Resource) -> Array:
	return Array(move.hit_frames) if not move.hit_frames.is_empty() else [move.startup]

func sweep(move: Resource, segment: int) -> Paths.Sweep:
	var curve: Array = vfx.cut_curves.get(move.effect(), [Vector2(10, -45), Vector2(45, -60), Vector2(60, -30)])
	var a: Vector2 = curve[0]
	var c: Vector2 = curve[1]
	var b: Vector2 = curve[2]
	var thickness := 12.0 if move.kind == "heavy" else 8.0
	if segment % 2 == 1:
		# The return cut runs from the end back to the start, bowed the other way.
		var mid := (a + b) * 0.5
		return Paths.Sweep.new(b + Vector2(0.0, -6.0), mid - (c - mid) * 0.7, a + Vector2(6.0, 4.0), thickness)
	return Paths.Sweep.new(a, c, b, thickness)

func head(t: float, start: int) -> float:
	return clampf((t - start + 1.0) / 2.6, 0.0, 1.0)

func tail(t: float, start: int) -> float:
	return clampf((t - start - 2.0) / 7.0, 0.0, 1.25)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var big: bool = move.kind == "heavy"
	var awake: bool = actor.form_active()
	var list := starts(move)
	for index in range(list.size()):
		if tick != int(list[index]):
			continue
		var seed: int = f.attack_instance * 167 + f.slot * 7919 + tick * 37
		var path := sweep(move, index)
		# Sparks flung off the outer edge as the cut lands.
		for n in range(12 if big else 7):
			var u: float = 0.35 + 0.65 * vfx.rand(seed, n)
			var along: Vector2 = path.point(minf(u + 0.02, 1.0), 0.0) - path.point(maxf(u - 0.02, 0.0), 0.0)
			var velocity: Vector2 = along.normalized() * lerpf(70.0, 180.0, vfx.rand(seed, n + 20)) + Vector2(0.0, -lerpf(10.0, 60.0, vfx.rand(seed, n + 40)))
			vfx.sparks.spawn(vfx.world(f, path.point(u, path.width(u) * 0.4)), vfx.world_dir(f, velocity), lerpf(0.18, 0.34, vfx.rand(seed, n + 60)),
				lerpf(1.4, 2.6, vfx.rand(seed, n + 80)), 0, Kit.GOLD_HOT, 260.0, 1.2, 0.0, 0.0, 0.6, 2.0)
		if big or awake:
			vfx.mote_burst(vfx.world(f, path.point(0.8, 0.0)), 4, 40.0, seed + 3, awake)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var list := starts(move)
	for index in range(list.size()):
		var start: int = int(list[index])
		var lead := head(t, start)
		var erosion := tail(t, start)
		if lead <= 0.0 or erosion >= 1.0:
			continue
		# The fringe re-strikes once per combat tick.
		var seed: int = f.attack_instance * 31 + index * 7 + f.move_frame
		vfx.crescent(canvas, layer, sweep(move, index), lead, erosion, "gold" if move.kind == "heavy" else "electric", awake, seed)
