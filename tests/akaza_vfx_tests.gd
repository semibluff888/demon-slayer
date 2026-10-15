extends SceneTree
## Regression for Akaza's rebuilt 破坏杀 effects: routing, freeze and expiry
## semantics, deterministic emission, projectiles (trail and floor burst), the
## blows that lead his body, the awakening compass, and that presentation never
## touches combat.
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
	create_timer(180).timeout.connect(func(): printerr("Akaza VFX watchdog expired"); quit(1))
	game = Main.instantiate()
	game.settings.path = "res://artifacts/akaza_vfx_tests-settings.cfg"
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.add_child(game)
	game.settings.cinematic_enabled = false
	game.set_physics_process(false)
	game.sound.muted = true
	game.mode = "local"
	await process_frame
	_check_routing()
	for id in ["5A", "5C", "2A", "2C", "jA", "jC", "5AA", "5B", "5D", "2B", "2D", "jB", "jD", "236A", "236C", "623A", "623C",
			"214B", "214D", "5AAC", "6B", "6C", "j214B", "j214D", "super", "max"]:
		for awakened in [false, true]:
			await _check_technique(id, awakened)
	await _check_throw()
	await _check_shot("236A", 0.0)
	await _check_shot("j236A", 80.0)
	_check_lead()
	await _check_compass()
	await _check_determinism()
	game.queue_free()
	await process_frame
	for failure in failures:
		printerr("FAIL: ", failure)
	print("AKAZA VFX TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_routing() -> void:
	var akaza = game.view.effects.akaza
	check(akaza != null and akaza.layers.size() == 5, "Akaza effects mount five layers")
	for id in akaza.MOVES:
		check(game.combat.moves.has(id) and akaza.handles(game.combat.moves[id]), "rebuilt effect owns " + id)
	var definition: Resource = game.combat.catalog.characters.akaza
	for move in definition.all_moves():
		check(akaza.handles(move), "every Akaza move is drawn by the rebuilt effects: " + move.id)
	for id in ["tanjiro_236A", "zenitsu_5A", "zenitsu_super", "nezuko_super", "nezuko_5B"]:
		check(not akaza.handles(game.combat.moves[id]), "other fighters keep their effects: " + id)
	check(not game.view.effects.tanjiro.handles(game.combat.moves["akaza_236A"]) and not game.view.effects.zenitsu.handles(game.combat.moves["akaza_236A"]),
		"the other rebuilt layers leave Akaza alone")
	check(akaza.layers[0].z_index == -9 and akaza.layers[1].z_index == -9 and akaza.layers[2].z_index == -1, "floor, compass and glow layers sit under the fighters")
	var cues = game.view.super_view
	check(cues._owns_charge(game.combat.moves["akaza_super"]) and cues._owns_charge(game.combat.moves["akaza_max"]),
		"rebuilt supers draw their own charge instead of the shared energy sphere")
	check(not game.view.effects.FLAVORS.has("akaza"), "the old compass impact flavour is gone")
	check(not game.view.fighters[0].has_method("_draw_awakening"), "the fighter view no longer draws the old compass")

func _start(move_id: String, awakened: bool, height: float = 0.0, gap: float = 180.0) -> Resource:
	game.characters.assign(["akaza", "tanjiro"])
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
	game.view.effects.akaza.interpolate = false
	var move: Resource = model.moves[move_id]
	model._begin_move(attacker, move)
	game.view.consume(model.events)
	return move

func _tick() -> void:
	game.combat.step([Combat.neutral(), Combat.neutral()])
	game.view.consume(game.combat.events)
	game.view._process(1.0 / 60)
	game.view.effects._process(1.0 / 60)

func _particles(akaza) -> int:
	return akaza.sparks.count() + akaza.flakes.count() + akaza.debris.count() + akaza.dust.count()

func _check_technique(id: String, awakened: bool) -> void:
	var air := id.begins_with("j")
	var move := _start("akaza_" + id, awakened, 70.0 if air else 0.0)
	var model = game.combat
	var akaza = game.view.effects.akaza
	var attacker = model.fighters[0]
	var label := "%s %s" % [id, "awakened" if awakened else "normal"]
	var guard := 0
	var shed := 0
	while attacker.move == move and attacker.move_frame < move.startup + 2 and guard < 200:
		_tick()
		shed = maxi(shed, _particles(akaza))
		guard += 1
		if guard % 6 == 0:
			await process_frame
	await process_frame
	check(shed > 0, label + " sheds particles")
	var held := [akaza.sparks.pos.duplicate(), akaza.flakes.pos.duplicate(), akaza.dust.pos.duplicate(), akaza.time]
	game.view.effects.freeze = true
	game.view.effects._process(0.5)
	check([akaza.sparks.pos, akaza.flakes.pos, akaza.dust.pos, akaza.time] == held, label + " freeze holds particles")
	game.view.effects.freeze = false
	var snapshot: Dictionary = model.snapshot()
	akaza.advance(0.05)
	akaza.bursts.clear()
	akaza.consume([{"type": "hit", "attacker": 0, "move": move.id, "segment": 0, "position": Vector2(500, 250), "instance": attacker.attack_instance}])
	check(model.snapshot() == snapshot, label + " effects never mutate combat")
	check(not akaza.bursts.is_empty(), label + " a hit adds its contact bursts")
	for n in range(move.total_frames() + 40):
		_tick()
		if n % 9 == 0:
			await process_frame
	for n in range(150):
		game.view.effects._process(1.0 / 60)
	var compass_bursts: Array = akaza.bursts
	check(_particles(akaza) == 0 and compass_bursts.is_empty(), label + " every particle, burst and floor mark expires within two and a half seconds")
	_start("akaza_" + id, awakened, 70.0 if air else 0.0)
	for n in range(move.startup + move.freeze_frames + 2):
		_tick()
	game.view.reset_effects()
	var cleared := true
	for each in akaza.techniques.values():
		cleared = cleared and each._origins.is_empty() and each._anchors.is_empty()
	check(cleared and akaza._ticks.is_empty() and akaza._shots.is_empty() and _particles(akaza) == 0 and akaza.bursts.is_empty(), label + " reset clears effect state")

## The throw: a slam on the floor bursts once the victim lands (the combat event).
func _check_throw() -> void:
	_start("akaza_throw", false, 0.0, 30.0)
	var akaza = game.view.effects.akaza
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
	check(akaza.bursts.any(func(b: Dictionary) -> bool: return b.kind == "crater"), "the slam leaves a crater")
	check(_particles(akaza) > 0, "the slam throws up rock and dust")
	for n in range(200):
		_tick()
	check(_particles(akaza) == 0 and akaza.bursts.is_empty(), "the slam clears")

## 空式 shots: the comet is tracked and sheds a trail; the air shot bursts on the
## floor exactly once; the ground shot disperses at the end of its range.
func _check_shot(id: String, height: float) -> void:
	var move := _start("akaza_" + id, false, height, 600.0)
	var akaza = game.view.effects.akaza
	var model = game.combat
	var flew := false
	var trail := 0
	for n in range(move.startup + 6):
		_tick()
		if not akaza._shots.is_empty():
			flew = true
			trail = maxi(trail, akaza.sparks.count())
	check(flew, id + " shot is tracked while it flies")
	check(trail > 0, id + " shot sheds a trail")
	var spikes := 0
	var rings := 0
	for n in range(160):
		_tick()
		spikes = maxi(spikes, akaza.bursts.filter(func(b: Dictionary) -> bool: return b.kind == "spikes").size())
		rings = maxi(rings, akaza.bursts.filter(func(b: Dictionary) -> bool: return b.kind == "ring").size())
		if model.projectiles.is_empty() and n > 4:
			break
	if height > 0.0:
		check(spikes == 1, id + " bursts on the floor exactly once (got %d)" % spikes)
		check(akaza.bursts.any(func(b: Dictionary) -> bool: return b.kind == "crater"), id + " leaves a crater where it lands")
	else:
		check(spikes == 0 and rings >= 1, id + " disperses at the end of its range without a floor burst")
	for n in range(160):
		_tick()
	check(_particles(akaza) == 0 and akaza.bursts.is_empty() and akaza._shots.is_empty(), id + " shot clears")

## The step punch's needle and 灭式's blast reach well past the front of the hit
## box while the blow is out, so the flash lands before he does.
func _check_lead() -> void:
	for spec in [["6C", 36.0], ["super", 20.0]]:
		var move := _start("akaza_" + str(spec[0]), false)
		var akaza = game.view.effects.akaza
		var technique = akaza.technique(move)
		var attacker = game.combat.fighters[0]
		var ahead := INF
		var guard := 0
		while guard < 200:
			_tick()
			guard += 1
			if attacker.move != move:
				break
			if attacker.move_frame >= move.startup + 2 and attacker.move_frame < move.startup + move.active:
				var shape: Dictionary = technique.shape(attacker, float(attacker.move_frame))
				ahead = minf(ahead, shape.head.x - move.box.end.x)
		check(ahead >= float(spec[1]) and ahead < INF, "%s flash leads the blow by %s (got %s)" % [spec[0], spec[1], ahead])

## 术式展开·罗针: the compass is cast through the awakening freeze and start-up,
## stays while he is awake (in blue-violet), and fades when it ends.
func _check_compass() -> void:
	game.characters.assign(["akaza", "tanjiro"])
	game.start_match()
	var model = game.combat
	model.phase = "fight"
	model.remaining = 5400
	var akaza = game.view.effects.akaza
	game.view.reset_effects()
	var f = model.fighters[0]
	f.meter = 300
	f.buffer_action = {"type": "awaken", "x": 0, "y": 0}
	f.buffer_left = 6
	model.step([Combat.neutral(), Combat.neutral()])
	check(f.awakening_ticks > 0 and model.super_freeze > 0, "awakening starts with its freeze")
	game.view.consume(model.events)
	check(akaza.compass.showing(0), "the compass appears when the awakening starts")
	var first: int = akaza.compass._awake[0].age
	for n in range(6):
		_tick()
	check(int(akaza.compass._awake[0].age) == first + 6, "the cast advances once per combat tick, through the freeze")
	var snapshot: Dictionary = model.snapshot()
	for n in range(3):
		game.view.effects.akaza.redraw()
		await process_frame
	check(model.snapshot() == snapshot, "drawing the compass never touches combat")
	for n in range(40):
		_tick()
	check(akaza.compass.showing(0) and int(akaza.compass._awake[0].age) > akaza.compass.CAST, "the compass settles under him while awake")
	check(akaza.flakes.count() > 0, "wisps and flakes rise while awake")
	f.awakening_ticks = 1
	model.step([Combat.neutral(), Combat.neutral()])
	game.view.consume(model.events)
	check(not akaza.compass.showing(0) and akaza.compass._fading.size() == 1, "the compass fades when the awakening ends")
	for n in range(40):
		_tick()
	check(akaza.compass._fading.is_empty(), "the fading compass clears")
	f.awakening_ticks = 600
	f.awakening_duration = 600
	_tick()
	check(akaza.compass.showing(0), "an awakening without its event still shows the compass")
	game.view.reset_effects()
	check(not akaza.compass.showing(0) and akaza.compass._fading.is_empty(), "reset clears the compass")

func _check_determinism() -> void:
	for id in ["akaza_214B", "akaza_236A"]:
		var results := []
		for batched in [false, true]:
			var move := _start(id, false)
			var akaza = game.view.effects.akaza
			# Every combat step is consumed (as main.gd does); only the render steps
			# between them differ: one per tick, or one for the whole batch.
			for n in range(move.startup + 10):
				game.combat.step([Combat.neutral(), Combat.neutral()])
				game.view.consume(game.combat.events)
				if not batched:
					game.view._process(0.0)
					akaza.advance(0.0)
			game.view._process(0.0)
			akaza.advance(0.0)
			var positions: Array = Array(akaza.sparks.pos) + Array(akaza.flakes.pos) + Array(akaza.dust.pos)
			positions.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
			results.append([akaza.sparks.count(), akaza.flakes.count(), akaza.debris.count(), akaza.dust.count(), akaza.bursts.size(), positions])
		check(results[0] == results[1], id + " particles are identical whether ticks are sampled one by one or in a batch")
