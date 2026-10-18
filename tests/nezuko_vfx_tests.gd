extends SceneTree
## Regression for Nezuko's rebuilt 爆血 effects: routing, freeze and expiry
## semantics, deterministic emission, the dashes that lead her body, the dive's
## single floor burst, the supers' fire line, whirl and dome, the demon form, and
## that presentation never touches combat.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
var passed := 0
var failures: Array[String] = []
var game: Node2D

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)

func _run() -> void:
	create_timer(240).timeout.connect(func(): printerr("Nezuko VFX watchdog expired"); quit(1))
	game = Main.instantiate()
	game.settings.path = "res://artifacts/nezuko_vfx_tests-settings.cfg"
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.add_child(game)
	game.settings.cinematic_enabled = false
	game.set_physics_process(false)
	game.sound.muted = true
	game.mode = "local"
	await process_frame
	_check_routing()
	for id in ["5A", "5C", "2A", "2C", "jA", "jC", "5B", "5D", "2B", "2D", "jB", "jD", "5BB", "5BBD", "6B", "3D", "236A", "236C", "623A", "623C",
			"214B", "214D", "j236A", "j236C", "j214B", "j214D", "super", "max"]:
		for awakened in [false, true]:
			await _check_technique(id, awakened)
	await _check_throw()
	await _check_dive()
	_check_lead()
	_check_finishers()
	await _check_demon()
	await _check_determinism()
	game.queue_free()
	await process_frame
	for failure in failures:
		printerr("FAIL: ", failure)
	print("NEZUKO VFX TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_routing() -> void:
	var nezuko = game.view.effects.nezuko
	check(nezuko != null and nezuko.layers.size() == 5, "Nezuko effects mount five layers")
	for id in nezuko.MOVES:
		check(game.combat.moves.has(id) and nezuko.handles(game.combat.moves[id]), "rebuilt effect owns " + id)
	var definition: Resource = game.combat.catalog.characters.nezuko
	for move in definition.all_moves():
		check(nezuko.handles(move), "every Nezuko move is drawn by the rebuilt effects: " + move.id)
	for id in ["tanjiro_236A", "zenitsu_5A", "zenitsu_super", "akaza_super", "akaza_5B"]:
		check(not nezuko.handles(game.combat.moves[id]), "other fighters keep their effects: " + id)
	for other in [game.view.effects.tanjiro, game.view.effects.zenitsu, game.view.effects.akaza]:
		check(not other.handles(game.combat.moves["nezuko_236A"]) and not other.handles(game.combat.moves["nezuko_super"]), "the other rebuilt layers leave Nezuko alone: " + other.name)
	check(nezuko.layers[0].z_index == -9 and nezuko.layers[1].z_index == -9 and nezuko.layers[2].z_index == -1, "floor, sigil and glow layers sit under the fighters")
	var cues = game.view.super_view
	check(cues._owns_charge(game.combat.moves["nezuko_super"]) and cues._owns_charge(game.combat.moves["nezuko_max"]),
		"rebuilt supers draw their own charge instead of the shared energy sphere")
	check(not game.view.effects.FLAVORS.has("nezuko"), "the old blood impact flavour is gone")
	for path in ["blaze-pink", "blaze-crimson", "flame-strip", "claw-strip", "flakes", "star"]:
		check(ResourceLoader.exists("res://art/effects/nezuko/%s.png" % path), "baked texture imported: " + path)

func _start(move_id: String, awakened: bool, height: float = 0.0, gap: float = 180.0) -> Resource:
	game.characters.assign(["nezuko", "tanjiro"])
	game.start_match()
	var model = game.combat
	model.phase = "fight"
	model.remaining = 5400
	var attacker = model.fighters[0]
	attacker.x = 380.0
	model.fighters[1].x = 380.0 + gap
	attacker.facing = 1
	model.fighters[1].facing = -1
	if awakened:
		attacker.awakening_ticks = 900
		attacker.awakening_duration = 900
	if height > 0.0:
		attacker.y = model.FLOOR_Y - height
		attacker.grounded = false
		attacker.state = "air"
		attacker.vy = 0.0
	game.view.reset_effects()
	game.view.effects.nezuko.interpolate = false
	var move: Resource = model.moves[move_id]
	model._begin_move(attacker, move)
	game.view.consume(model.events)
	return move

func _tick() -> void:
	game.combat.step([Combat.neutral(), Combat.neutral()])
	game.view.consume(game.combat.events)
	game.view._process(1.0 / 60)
	game.view.effects._process(1.0 / 60)

func _particles(nezuko) -> int:
	return nezuko.embers.count() + nezuko.flakes.count() + nezuko.debris.count() + nezuko.dust.count()

func _check_technique(id: String, awakened: bool) -> void:
	var air := id.begins_with("j")
	var move := _start("nezuko_" + id, awakened, 70.0 if air else 0.0)
	var model = game.combat
	var nezuko = game.view.effects.nezuko
	var attacker = model.fighters[0]
	var label := "%s %s" % [id, "awakened" if awakened else "normal"]
	var guard := 0
	var shed := 0
	while attacker.move == move and attacker.move_frame < move.startup + 2 and guard < 200:
		_tick()
		shed = maxi(shed, _particles(nezuko))
		guard += 1
		if guard % 6 == 0:
			await process_frame
	await process_frame
	check(shed > 0, label + " sheds particles")
	var held := [nezuko.embers.pos.duplicate(), nezuko.flakes.pos.duplicate(), nezuko.dust.pos.duplicate(), nezuko.time]
	game.view.effects.freeze = true
	game.view.effects._process(0.5)
	check([nezuko.embers.pos, nezuko.flakes.pos, nezuko.dust.pos, nezuko.time] == held, label + " freeze holds particles")
	game.view.effects.freeze = false
	var snapshot: Dictionary = model.snapshot()
	nezuko.advance(0.05)
	nezuko.bursts.clear()
	nezuko.consume([{"type": "hit", "attacker": 0, "move": move.id, "segment": 0, "position": Vector2(500, 250), "instance": attacker.attack_instance}])
	check(model.snapshot() == snapshot, label + " effects never mutate combat")
	check(not nezuko.bursts.is_empty(), label + " a hit adds its contact bursts")
	for n in range(move.total_frames() + 40):
		_tick()
		if n % 9 == 0:
			await process_frame
	for n in range(150):
		game.view.effects._process(1.0 / 60)
	check(_particles(nezuko) == 0 and nezuko.bursts.is_empty(), label + " every particle, burst and floor mark expires within two and a half seconds")
	_start("nezuko_" + id, awakened, 70.0 if air else 0.0)
	for n in range(move.startup + move.freeze_frames + 2):
		_tick()
	game.view.reset_effects()
	var cleared := true
	for each in nezuko.techniques.values():
		cleared = cleared and each._origins.is_empty() and each._anchors.is_empty()
	check(cleared and nezuko._ticks.is_empty() and _particles(nezuko) == 0 and nezuko.bursts.is_empty(), label + " reset clears effect state")

## The throw (抓技): the floor breaks once the victim is slammed into it.
func _check_throw() -> void:
	_start("nezuko_throw", false, 0.0, 30.0)
	var nezuko = game.view.effects.nezuko
	var model = game.combat
	var slammed := false
	for n in range(80):
		_tick()
		for event in model.events:
			if event.type == "throw":
				slammed = true
		if slammed:
			break
	check(slammed, "throw reaches its slam")
	check(nezuko.bursts.any(func(b: Dictionary) -> bool: return b.kind == "crater") and nezuko.bursts.any(func(b: Dictionary) -> bool: return b.kind == "eruption"),
		"the slam breaks the floor and leaves a crater")
	check(_particles(nezuko) > 0, "the slam throws up rock and dust")
	for n in range(200):
		_tick()
	check(_particles(nezuko) == 0 and nezuko.bursts.is_empty(), "the slam clears")

## 爆血飞踢·落: the floor breaks exactly once where she lands, and only there.
func _check_dive() -> void:
	for id in ["j236A", "j236C"]:
		var move := _start("nezuko_" + id, false, 90.0, 600.0)
		var nezuko = game.view.effects.nezuko
		var attacker = game.combat.fighters[0]
		var eruptions := 0
		var before_landing := 0
		for n in range(120):
			_tick()
			var count: int = nezuko.bursts.filter(func(b: Dictionary) -> bool: return b.kind == "eruption").size()
			if not attacker.grounded:
				before_landing = maxi(before_landing, count)
			eruptions = maxi(eruptions, count)
			if attacker.grounded and attacker.move == null and attacker.stun == 0:
				break
		check(before_landing == 0 and eruptions == 1, id + " breaks the floor once, on landing (got %d, %d before)" % [eruptions, before_landing])
		check(nezuko.bursts.any(func(b: Dictionary) -> bool: return b.kind == "crater"), id + " leaves a crater where she lands")
		check(move.stance == "air", id + " is an air move")
		for n in range(160):
			_tick()
		check(_particles(nezuko) == 0 and nezuko.bursts.is_empty(), id + " landing clears")

## The flying kick and the slide: the fire's head runs past the front of the hit
## box while the blow is out, so the flash lands before she does.
func _check_lead() -> void:
	for id in ["236A", "236C", "3D"]:
		var move := _start("nezuko_" + id, false)
		var nezuko = game.view.effects.nezuko
		var technique = nezuko.technique(move)
		var attacker = game.combat.fighters[0]
		var ahead := INF
		var guard := 0
		while guard < 200:
			_tick()
			guard += 1
			if attacker.move != move:
				break
			if attacker.move_frame >= move.startup + 1 and attacker.move_frame < move.startup + move.active:
				var head: Vector2 = technique.head(attacker, float(attacker.move_frame))
				ahead = minf(ahead, head.x - move.box.end.x)
		check(ahead >= 0.0 and ahead < INF, "%s fire leads the blow past its hit box (got %s)" % [id, ahead])

## The supers' last hits: 爆炎裂's fire line and whirl, the MAX's dome.
func _check_finishers() -> void:
	for spec in [["super", ["fire_line", "whirl", "scorch"]], ["max", ["dome", "eruption", "crater", "star"]]]:
		var move := _start("nezuko_" + str(spec[0]), false)
		var nezuko = game.view.effects.nezuko
		var attacker = game.combat.fighters[0]
		nezuko.bursts.clear()
		nezuko.consume([{"type": "hit", "attacker": 0, "move": move.id, "segment": move.hit_count() - 1, "position": Vector2(520, 250), "instance": attacker.attack_instance}])
		for kind in spec[1]:
			check(nezuko.bursts.any(func(b: Dictionary) -> bool: return b.kind == kind), "%s last hit adds its %s" % [spec[0], kind])
		nezuko.bursts.clear()
		nezuko.consume([{"type": "hit", "attacker": 0, "move": move.id, "segment": 0, "position": Vector2(520, 250), "instance": attacker.attack_instance}])
		check(not nezuko.bursts.any(func(b: Dictionary) -> bool: return b.kind in spec[1].slice(0, 2)), "%s earlier hits stay plain" % spec[0])
		nezuko.bursts.clear()

## 鬼化·爆血: the demon form's start-up runs through the awakening freeze, a flame
## outline stays while she is in it, and fades when it ends. The old aura layers
## (awakening_effects) are hidden for her.
func _check_demon() -> void:
	game.characters.assign(["nezuko", "tanjiro"])
	game.start_match()
	var model = game.combat
	model.phase = "fight"
	model.remaining = 5400
	var nezuko = game.view.effects.nezuko
	game.view.reset_effects()
	var f = model.fighters[0]
	f.meter = 300
	f.buffer_action = {"type": "awaken", "x": 0, "y": 0}
	f.buffer_left = 6
	model.step([Combat.neutral(), Combat.neutral()])
	check(f.awakening_ticks > 0 and model.super_freeze > 0, "awakening starts with its freeze")
	game.view.consume(model.events)
	check(nezuko.demon.showing(0), "the demon form's effects start with the awakening")
	var first: int = nezuko.demon._awake[0].age
	for n in range(6):
		_tick()
	check(int(nezuko.demon._awake[0].age) == first + 6, "the start-up advances once per combat tick, through the freeze")
	var snapshot: Dictionary = model.snapshot()
	for n in range(3):
		nezuko.redraw()
		await process_frame
	check(model.snapshot() == snapshot, "drawing the demon form never touches combat")
	for n in range(40):
		_tick()
	check(nezuko.demon.showing(0) and int(nezuko.demon._awake[0].age) > nezuko.demon.CAST, "the flame outline settles while she stays in the demon form")
	check(nezuko.embers.count() + nezuko.flakes.count() > 0, "embers and flakes rise off her in the demon form")
	game.view._process(1.0 / 60)
	check(not game.view.fighters[0].awakening_effects.visible, "the old aura layers stay hidden for her")
	f.awakening_ticks = 1
	model.step([Combat.neutral(), Combat.neutral()])
	game.view.consume(model.events)
	check(not nezuko.demon.showing(0) and nezuko.demon._fading.size() == 1, "the outline fades when the demon form ends")
	for n in range(40):
		_tick()
	check(nezuko.demon._fading.is_empty(), "the fading outline clears")
	f.awakening_ticks = 600
	f.awakening_duration = 600
	_tick()
	check(nezuko.demon.showing(0), "a demon form without its event still shows its outline")
	game.view.reset_effects()
	check(not nezuko.demon.showing(0) and nezuko.demon._fading.is_empty(), "reset clears the demon form")

func _check_determinism() -> void:
	for id in ["nezuko_214B", "nezuko_236A", "nezuko_5BBD"]:
		var results := []
		for batched in [false, true]:
			var move := _start(id, false)
			var nezuko = game.view.effects.nezuko
			# Every combat step is consumed (as main.gd does); only the render steps
			# between them differ: one per tick, or one for the whole batch.
			for n in range(move.startup + 10):
				game.combat.step([Combat.neutral(), Combat.neutral()])
				game.view.consume(game.combat.events)
				if not batched:
					game.view._process(0.0)
					nezuko.advance(0.0)
			game.view._process(0.0)
			nezuko.advance(0.0)
			var positions: Array = Array(nezuko.embers.pos) + Array(nezuko.flakes.pos) + Array(nezuko.dust.pos)
			positions.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
			results.append([nezuko.embers.count(), nezuko.flakes.count(), nezuko.debris.count(), nezuko.dust.count(), nezuko.bursts.size(), positions])
		check(results[0] == results[1], id + " particles are identical whether ticks are sampled one by one or in a batch")
