extends "res://scripts/presentation/vfx/tanjiro/technique.gd"
## 捌之型 泷壶 (j236A/C): a waterfall. As the dive begins a column of water
## strands pours from above the screen onto the blade and rides down with
## Tanjiro; at touchdown it slams into the floor, throws up spray and piles a
## wide bank of white foam, pours a moment longer where it landed, then thins
## from the top and breaks into spray while the foam settles.
const Arena = preload("res://scripts/arena_rules.gd")

## The column's top, in world units: well above the view, so its tapered tail
## is never on screen.
const TOP_Y := Arena.FLOOR_Y - 300.0
## Column centre in front of Tanjiro, where the blade comes down.
const COLUMN_X := 24.0
## After touchdown, in ticks: full pour, then the column erodes from the top;
## the foam bank holds, then settles. Records end at LIFE.
const POUR := 8.0
const ERODE := 10.0
const BANK_HOLD := 18.0
const BANK_END := 34.0
const LIFE := 44.0

## Columns by "slot:instance": where the move left the fighter and when.
## `since` is the presentation time of touchdown (or of an interrupted dive).
var _columns: Dictionary = {}

func reset() -> void:
	super()
	_columns.clear()

func thickness(big: bool) -> float:
	return 46.0 if big else 38.0

func pour(t: float, move: Resource) -> float:
	return clampf((t - move.startup + 4.0) / 4.0, 0.0, 1.0)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var big := heavy(move)
	var seed: int = f.attack_instance * 211 + f.slot * 7919 + tick * 23
	var start: int = move.startup
	if tick >= 2 and tick < start - 3:
		gather_beads(f, actor, tick, seed)
	if tick == maxi(0, start - 4):
		_columns["%d:%d" % [f.slot, f.attack_instance]] = {"slot": f.slot, "instance": f.attack_instance, "move": move.id, "big": big,
			"x": f.x, "y": f.y, "facing": f.facing, "since": -1.0, "landed": false, "hybrid": false, "emitted": 0}
	if tick >= start:
		# Spray shed by the falling head of the column.
		var head := Vector2(COLUMN_X, -8.0)
		for n in range(3 if big else 2):
			var side := 1.0 if n % 2 == 0 else -1.0
			vfx.drops.spawn(vfx.world(f, head + Vector2(side * thickness(big) * 0.45, 0.0)),
				vfx.world_dir(f, Vector2(side * lerpf(40.0, 110.0, vfx.rand(seed, n)), -lerpf(20.0, 90.0, vfx.rand(seed, n + 10)))),
				lerpf(0.25, 0.42, vfx.rand(seed, n + 20)), lerpf(1.5, 3.0, vfx.rand(seed, n + 30)), 0, Color.WHITE, 420.0, 0.6, 0.0, 0.0, 0.7, 0.8)
		if tick % 3 == 0:
			vfx.foam.spawn(vfx.world(f, head), vfx.world_dir(f, Vector2(lerpf(-30.0, 30.0, vfx.rand(seed, 40)), -40.0)), 0.26, lerpf(6.0, 9.0, vfx.rand(seed, 41)),
				Kit.SPRAY_CELLS[tick % Kit.SPRAY_CELLS.size()], Color.WHITE, 220.0, 1.5, vfx.rand(seed, 42) * TAU, 3.0, 0.8)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, hybrid: bool) -> void:
	vfx.water_contact(event, attacker, 1.25 if heavy(move) else 1.1, hybrid)

## Touchdown, an interrupted dive and the pour after the move has ended.
func linger(fighters: Array, actors: Array) -> void:
	for key: String in _columns.keys():
		var column: Dictionary = _columns[key]
		var f: RefCounted = fighters[int(column.slot)]
		if column.since < 0.0:
			var current: Resource = f.move
			if current != null and current.id == column.move and f.attack_instance == column.instance:
				column.x = f.x
				column.y = f.y
				column.facing = f.facing
				continue
			column.since = vfx.time
			column.landed = f.state == "landing" and f.landing_move == column.move and f.attack_instance == column.instance
			column.hybrid = int(column.slot) < actors.size() and actors[int(column.slot)] != null and actors[int(column.slot)].form_active()
			if column.landed:
				column.x = f.x
				column.y = f.y
				_touchdown(column)
		var age: float = (vfx.time - float(column.since)) * 60.0
		if age > LIFE:
			_columns.erase(key)
			continue
		while column.landed and int(column.emitted) <= int(age):
			_pour(column, int(column.emitted))
			column.emitted = int(column.emitted) + 1

func _touchdown(column: Dictionary) -> void:
	var big: bool = column.big
	var seed: int = int(column.instance) * 389 + int(column.slot) * 7919
	var base_at: Vector2 = vfx.world(column, Vector2(COLUMN_X, -2.0))
	var scale := 1.15 if big else 1.0
	vfx.bursts.append({"kind": "splash", "at": base_at + Vector2(0, -6), "age": 0.0, "life": 0.42, "size": 68.0 * scale, "facing": float(column.facing), "spin": 0.0})
	vfx.bursts.append({"kind": "ring", "at": base_at, "age": 0.0, "life": 0.26, "size": 40.0 * scale, "tone": Color(1.0, 0.45, 0.3) if column.hybrid else Color(0.8, 0.95, 1.0)})
	# Spray thrown up both sides of the impact.
	for n in range(int(28 * scale)):
		var side := 1.0 if n % 2 == 0 else -1.0
		vfx.drops.spawn(base_at + Vector2(side * lerpf(4.0, 20.0, vfx.rand(seed, n)), -lerpf(0.0, 8.0, vfx.rand(seed, n + 300))),
			Vector2(side * lerpf(25.0, 120.0, vfx.rand(seed, n + 50)), -lerpf(110.0, 280.0, vfx.rand(seed, n + 100))),
			lerpf(0.4, 0.7, vfx.rand(seed, n + 150)), lerpf(1.8, 3.8, vfx.rand(seed, n + 200)), 0, Color.WHITE, 520.0, 0.5, 0.0, 0.0, 0.7, 0.8)
	# Splash crowns climbing the foot of the column, foam rolling out along the floor.
	for n in range(4):
		vfx.foam.spawn(base_at + Vector2((vfx.rand(seed, n + 400) - 0.5) * 24.0, -6.0), Vector2((vfx.rand(seed, n + 410) - 0.5) * 60.0, -lerpf(90.0, 170.0, vfx.rand(seed, n + 420))),
			lerpf(0.4, 0.55, vfx.rand(seed, n + 430)), lerpf(13.0, 19.0, vfx.rand(seed, n + 440)) * scale, [1, 6, 11][n % 3], Color.WHITE, 260.0, 1.2, 0.0, 0.0, 1.0)
	for n in range(6):
		var side := 1.0 if n % 2 == 0 else -1.0
		vfx.foam.spawn(base_at + Vector2(side * 8.0, -4.0), Vector2(side * lerpf(45.0, 100.0, vfx.rand(seed, n + 500)), -lerpf(10.0, 40.0, vfx.rand(seed, n + 510))),
			lerpf(0.4, 0.55, vfx.rand(seed, n + 520)), lerpf(8.0, 13.0, vfx.rand(seed, n + 530)) * scale, Kit.CLOUD_CELLS[n % 2], Color.WHITE, 60.0, 2.4,
			0.0, 0.0, 1.2)
	vfx.mist_burst(base_at + Vector2(0, -10), 5, 34.0, seed + 7)
	if column.hybrid:
		vfx.petal_burst(base_at + Vector2(0, -16), int(26 * scale), 150.0, seed + 9)

## One tick of the pour after touchdown: splashes off the foot of the column,
## then drops shed where it erodes.
func _pour(column: Dictionary, age: int) -> void:
	var big: bool = column.big
	var seed: int = int(column.instance) * 523 + int(column.slot) * 7919 + age * 29
	var width := thickness(big)
	if age < POUR:
		for n in range(3 if big else 2):
			var side := 1.0 if n % 2 == 0 else -1.0
			vfx.drops.spawn(vfx.world(column, Vector2(COLUMN_X + side * width * lerpf(0.2, 0.5, vfx.rand(seed, n)), -4.0)),
				vfx.world_dir(column, Vector2(side * lerpf(40.0, 110.0, vfx.rand(seed, n + 10)), -lerpf(60.0, 170.0, vfx.rand(seed, n + 20)))),
				lerpf(0.3, 0.5, vfx.rand(seed, n + 30)), lerpf(1.5, 3.2, vfx.rand(seed, n + 40)), 0, Color.WHITE, 480.0, 0.6, 0.0, 0.0, 0.7, 0.8)
		if age % 2 == 0:
			vfx.foam.spawn(vfx.world(column, Vector2(COLUMN_X + (vfx.rand(seed, 50) - 0.5) * width * 0.6, -8.0)),
				Vector2((vfx.rand(seed, 51) - 0.5) * 50.0, -lerpf(60.0, 130.0, vfx.rand(seed, 52))), 0.4, lerpf(12.0, 18.0, vfx.rand(seed, 53)),
				[1, 6, 11][age % 3], Color.WHITE, 260.0, 1.2, 0.0, 0.0, 1.0)
		if age % 3 == 0:
			vfx.mist.spawn(vfx.world(column, Vector2(COLUMN_X, -14.0)), Vector2((vfx.rand(seed, 60) - 0.5) * 40.0, -18.0), 0.6, 16.0, 0, Kit.WATER_MIST, 0.0, 1.5, 0.0, 0.0, 1.6)
	var erosion := (age - POUR) / ERODE
	if erosion > 0.0 and erosion <= 1.0:
		var path := _path(column, true)
		var at: Vector2 = path.point(erosion, (vfx.rand(seed, 70) - 0.5) * width * 0.8)
		if at.y > TOP_Y - float(column.y) + 90.0:
			for n in range(3):
				vfx.drops.spawn(vfx.world(column, at + Vector2((vfx.rand(seed, n + 80) - 0.5) * width * 0.6, 0.0)),
					vfx.world_dir(column, Vector2((vfx.rand(seed, n + 90) - 0.5) * 50.0, lerpf(20.0, 80.0, vfx.rand(seed, n + 100)))),
					lerpf(0.3, 0.5, vfx.rand(seed, n + 110)), lerpf(1.3, 2.6, vfx.rand(seed, n + 120)), 0, Color.WHITE, 380.0, 0.5)

## The column in the frame of `column` (fighter-local units): from above the
## view down to the blade while diving, into the foam once landed.
func _path(column: Dictionary, landed: bool) -> Paths.Column:
	var top := TOP_Y - float(column.y)
	var bottom := 3.0 if landed else -8.0
	return Paths.Column.new(COLUMN_X, top, bottom, thickness(column.big), 1.6, float(column.instance))

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var hybrid: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	var gather := clampf((t - 1.0) / 4.0, 0.0, 1.0) * (1.0 - clampf(t - start + 3.0, 0.0, 1.0))
	if gather > 0.0:
		vfx.blade_water(canvas, layer, actor, gather, hybrid)
	if layer == Kit.LIGHT:
		var flash := sin(clampf((t - start + 5.0) / 6.0, 0.0, 1.0) * PI)
		if flash > 0.02:
			vfx.body_flash(canvas, f, actor, Color(0.30, 0.55, 1.0) * flash * 0.8)
	var lead := pour(t, move)
	if lead <= 0.0:
		return
	var column := {"x": f.x, "y": f.y, "facing": f.facing, "big": heavy(move), "instance": f.attack_instance}
	_draw_column(canvas, layer, column, _path(column, false), lead, 0.0, 1.0, hybrid)

## Landed and interrupted columns, after their move has ended.
func draw_lingering(canvas: Node2D, layer: int) -> void:
	for column: Dictionary in _columns.values():
		if column.since < 0.0:
			continue
		var age: float = (vfx.time - float(column.since)) * 60.0
		vfx.set_base(canvas, vfx.frame_transform(column.x, column.y, column.facing))
		if column.landed:
			var slam := 1.0 + 0.28 * (1.0 - clampf(age / 6.0, 0.0, 1.0))
			_draw_column(canvas, layer, column, _path(column, true), 1.0, (age - POUR) / ERODE, slam, column.hybrid)
			_draw_bank(canvas, layer, column, age)
		else:
			# Cut off mid-dive: the column falls apart where it was.
			_draw_column(canvas, layer, column, _path(column, false), 1.0, age / 8.0, 1.0, column.hybrid)

func _draw_column(canvas: Node2D, layer: int, column: Dictionary, path: Paths.Column, lead: float, erosion: float, swell: float, hybrid: bool) -> void:
	if erosion >= 1.2:
		return
	path.thick *= swell
	match layer:
		Kit.BACK:
			# Darker water behind the strands gives the column body and depth.
			vfx.strand(canvas, path, lead, erosion, 0.0, 0.82, 0.0, 1.0, Color(0.32, 0.56, 0.95, 0.7), [0.3, 0.7], path.length / 1.4,
				-vfx.time * 2.2 + float(column.instance))
		Kit.WATER:
			vfx.water_body(canvas, path, lead, erosion, hybrid, int(column.instance), 2.6, false)
		Kit.FLAME:
			# Bright sheen running down the face of the falling water.
			for offset in [-0.22, 0.18]:
				var line := PackedVector2Array()
				var widths := PackedFloat32Array()
				var tint := PackedColorArray()
				for n in range(24):
					var u := lead * n / 23.0
					line.append(path.point(u, path.thick * offset))
					widths.append(2.4 * sin(clampf(u, 0.02, 0.98) * PI))
					tint.append(Color(0.7, 0.85, 1.0, 0.55 * smoothstep(erosion - 0.3, erosion, u)))
				Ribbon.draw(canvas, line, widths, tint, vfx.band)
		Kit.LIGHT:
			vfx.glow_along(canvas, path, lead, erosion, Color(Kit.WATER_GLOW, 0.14 if hybrid else 0.2), 1.9)

## The bank of foam piled around the foot of the column: a back row under the
## fighters and a lower front row over their feet. Each mound swells in at
## touchdown, spreads a little and settles away at its own pace.
func _draw_bank(canvas: Node2D, layer: int, column: Dictionary, age: float) -> void:
	var front := layer == Kit.FRONT
	if not front and layer != Kit.SOLID:
		if layer == Kit.LIGHT and age < BANK_END:
			# Soft white glow over the foam, strongest at the slam.
			var glow_size: Vector2 = Vector2(110.0, 36.0) * (1.15 if column.big else 1.0)
			var bright := (0.5 * (1.0 - clampf(age / 10.0, 0.0, 1.0)) + 0.18) * (1.0 - smoothstep(BANK_HOLD, BANK_END, age))
			canvas.draw_texture_rect(vfx.glow, Rect2(Vector2(COLUMN_X, -14.0) - glow_size * 0.5, glow_size), false, Color(0.85, 0.95, 1.0, bright))
		return
	var sheet: Texture2D = vfx.textures.get("water-foam")
	if sheet == null:
		return
	var cell := sheet.get_size() / 4.0
	var scale: float = 1.15 if column.big else 1.0
	var count := 6 if front else 8
	var reach := (52.0 if front else 44.0) * scale * (1.0 + 0.12 * clampf(age / 24.0, 0.0, 1.0))
	var seed := int(column.instance) * 97 + (500 if front else 0)
	for n in range(count):
		var across: float = (n + 0.5) / count * 2.0 - 1.0 + (vfx.rand(seed, n) - 0.5) * 0.12
		var rise := 1.0 - pow(1.0 - clampf((age - absf(across) * 2.5) / 4.0, 0.0, 1.0), 3.0)
		var settle: float = 1.0 - smoothstep(BANK_HOLD - 6.0 + vfx.rand(seed, n + 10) * 10.0, BANK_END - 4.0 + vfx.rand(seed, n + 20) * 6.0, age)
		var presence := rise * settle
		if presence <= 0.02:
			continue
		var crown: float = 1.0 - 0.55 * across * across
		var size: float = lerpf(26.0, 38.0, vfx.rand(seed, n + 30)) * scale * crown * (0.55 + 0.45 * presence) * (0.85 if front else 1.0)
		var at := Vector2(COLUMN_X + across * reach, (2.0 if front else -4.0) - size * (0.3 if front else 0.42))
		var index: int = Kit.CLOUD_CELLS[(n + int(column.instance)) % 2] if front or n % 3 != 1 else [1, 6][n % 2]
		var origin := Vector2(index % 4, index / 4) * cell
		var flip: float = -1.0 if vfx.rand(seed, n + 40) < 0.5 else 1.0
		canvas.draw_set_transform_matrix(vfx.base * Transform2D(0.0, Vector2(flip, 1.0), 0.0, at))
		canvas.draw_texture_rect_region(sheet, Rect2(-size * 0.5, -size * 0.5, size, size), Rect2(origin, cell), Color(1, 1, 1, minf(1.0, presence * 1.4)))
	canvas.draw_set_transform_matrix(vfx.base)
