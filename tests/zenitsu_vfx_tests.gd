extends SceneTree
## Regression for Zenitsu's rebuilt thunder effects: routing, freeze and expiry
## semantics, deterministic emission, the air dash's touchdown hand-off, and
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
	create_timer(120).timeout.connect(func(): printerr("Zenitsu VFX watchdog expired"); quit(1))
	game = Main.instantiate()
	game.settings.path = "res://artifacts/zenitsu_vfx_tests-settings.cfg"
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.add_child(game)
	game.settings.cinematic_enabled = false
	game.set_physics_process(false)
	game.sound.muted = true
	game.mode = "local"
	await process_frame
	_check_routing()
	for id in ["5A", "5C", "2A", "2C", "jA", "jC", "5AA", "5AAC", "236A", "236C", "3C", "623A", "623C", "6C", "214B", "214D", "super", "max"]:
		for awakened in [false, true]:
			await _check_technique(id, awakened)
	for id in ["j236A", "j236C", "j214B", "j214D"]:
		await _check_air(id)
	_check_beam_lead()
	await _check_determinism()
	game.queue_free()
	await process_frame
	for failure in failures:
		printerr("FAIL: ", failure)
	print("ZENITSU VFX TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_routing() -> void:
	var zenitsu = game.view.effects.zenitsu
	check(zenitsu != null and zenitsu.layers.size() == 4, "Zenitsu effects mount four layers")
	for id in zenitsu.MOVES:
		check(game.combat.moves.has(id) and zenitsu.handles(game.combat.moves[id]), "rebuilt effect owns " + id)
	for id in ["zenitsu_5B", "zenitsu_5D", "zenitsu_2B", "zenitsu_2D", "zenitsu_jB", "zenitsu_jD", "zenitsu_throw", "tanjiro_236A", "nezuko_super"]:
		check(not zenitsu.handles(game.combat.moves[id]), "keeps the shared effect: " + id)
	check(not game.view.effects.tanjiro.handles(game.combat.moves["zenitsu_236A"]), "Tanjiro's layer leaves Zenitsu alone")
	check(zenitsu.layers[0].z_index == -9 and zenitsu.layers[1].z_index == -1, "floor and glow layers sit under the fighters")
	var cues = game.view.super_view
	check(cues._owns_charge(game.combat.moves["zenitsu_super"]) and cues._owns_charge(game.combat.moves["zenitsu_max"]),
		"rebuilt supers draw their own charge instead of the shared energy sphere")

func _start(move_id: String, awakened: bool, height: float = 0.0) -> Resource:
	game.characters.assign(["zenitsu", "tanjiro"])
	game.start_match()
	var model = game.combat
	model.phase = "fight"
	model.remaining = 5400
	var attacker = model.fighters[0]
	attacker.x = 380.0
	model.fighters[1].x = 560.0
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
	game.view.effects.zenitsu.interpolate = false
	var move: Resource = model.moves[move_id]
	model._begin_move(attacker, move)
	game.view.consume(model.events)
	return move

func _tick() -> void:
	game.combat.step([Combat.neutral(), Combat.neutral()])
	game.view.consume(game.combat.events)
	game.view._process(1.0 / 60)
	game.view.effects._process(1.0 / 60)

func _particles(zenitsu) -> int:
	return zenitsu.sparks.count() + zenitsu.motes.count() + zenitsu.debris.count()

func _check_technique(id: String, awakened: bool) -> void:
	var air := id.begins_with("j")
	var move := _start("zenitsu_" + id, awakened, 70.0 if air else 0.0)
	var model = game.combat
	var zenitsu = game.view.effects.zenitsu
	var attacker = model.fighters[0]
	var label := "%s %s" % [id, "awakened" if awakened else "normal"]
	var guard := 0
	var shed := 0
	while attacker.move == move and attacker.move_frame < move.startup + 2 and guard < 200:
		_tick()
		shed = maxi(shed, _particles(zenitsu))
		guard += 1
		if guard % 6 == 0:
			await process_frame
	await process_frame
	# Emission is per combat tick; a slow real-time frame (the first draw uploads the
	# atlas pages) can already have aged a light cut's short sparks out by now.
	check(shed > 0, label + " sheds particles")
	var held := [zenitsu.sparks.pos.duplicate(), zenitsu.motes.pos.duplicate(), zenitsu.time]
	game.view.effects.freeze = true
	game.view.effects._process(0.5)
	check([zenitsu.sparks.pos, zenitsu.motes.pos, zenitsu.time] == held, label + " freeze holds particles")
	game.view.effects.freeze = false
	var snapshot: Dictionary = model.snapshot()
	zenitsu.advance(0.05)
	zenitsu.bursts.clear()
	zenitsu.consume([{"type": "hit", "attacker": 0, "move": move.id, "segment": 0, "position": Vector2(500, 250)}])
	check(model.snapshot() == snapshot, label + " effects never mutate combat")
	check(not zenitsu.bursts.is_empty(), label + " a hit adds its contact bursts")
	for n in range(move.total_frames() + 40):
		_tick()
		if n % 9 == 0:
			await process_frame
	for n in range(90):
		game.view.effects._process(1.0 / 60)
	check(_particles(zenitsu) == 0 and zenitsu.bursts.is_empty(), label + " every particle expires within a second and a half")
	_start("zenitsu_" + id, awakened, 70.0 if air else 0.0)
	for n in range(move.startup + move.freeze_frames + 2):
		_tick()
	game.view.reset_effects()
	var cleared := true
	for each in zenitsu.techniques.values():
		cleared = cleared and each._origins.is_empty() and each._anchors.is_empty()
	check(cleared and zenitsu._ticks.is_empty() and _particles(zenitsu) == 0, label + " reset clears effect state")

## Air dashes end on touchdown: the beam keeps eroding after the move is gone,
## a landing burst fires once, and everything clears.
func _check_air(id: String) -> void:
	var move := _start("zenitsu_" + id, false, 60.0)
	var model = game.combat
	var zenitsu = game.view.effects.zenitsu
	var attacker = model.fighters[0]
	var technique = zenitsu.techniques[zenitsu.MOVES[move.id]]
	var landed := false
	for n in range(160):
		_tick()
		if attacker.grounded and attacker.move == null:
			landed = true
			break
	check(landed, id + " lands")
	check(technique._beams.size() == 1, id + " hands its beam over on touchdown")
	var stars: int = zenitsu.bursts.filter(func(b: Dictionary) -> bool: return b.kind == "star").size()
	_tick()
	check(zenitsu.bursts.filter(func(b: Dictionary) -> bool: return b.kind == "star").size() <= stars, id + " lands only once")
	for n in range(30):
		_tick()
	check(technique._beams.is_empty(), id + " beam finishes eroding")
	for n in range(90):
		_tick()
	check(_particles(zenitsu) == 0 and zenitsu.bursts.is_empty(), id + " clears after landing")

## Dash beams lead him: through the dash the head (with its star and lance) stays
## clear of the front of his body, about 24 units ahead in the dash poses, and
## air dashes lead along their dive; 低身斩 barely travels but still streaks.
func _check_beam_lead() -> void:
	for id in ["236A", "236C", "3C", "j236A", "j236C", "j214B", "j214D"]:
		var move := _start("zenitsu_" + id, false, 70.0 if id.begins_with("j") else 0.0)
		var technique = game.view.effects.zenitsu.technique(move)
		var attacker = game.combat.fighters[0]
		var ahead := INF
		var lead := INF
		var span := INF
		var guard := 0
		while attacker.move == move and attacker.move_frame < move.startup + move.active and guard < 200:
			_tick()
			guard += 1
			if attacker.move == move and attacker.move_frame > move.startup and attacker.move_frame < move.startup + move.active:
				var beam: Dictionary = technique.shape(attacker, float(attacker.move_frame))
				var head: Vector2 = beam.head
				ahead = minf(ahead, head.x)
				lead = minf(lead, (head - Vector2(0.0, technique.height(move))).dot(beam.dir))
				span = minf(span, beam.from.distance_to(beam.tip))
		check(ahead > 28.0 and ahead < INF, id + " beam head clears his body")
		check(lead >= 40.0, id + " beam head leads along the dash")
		if id == "3C":
			check(span >= 84.0, "3C streak is long despite the short travel")

func _check_determinism() -> void:
	var results := []
	for batched in [false, true]:
		var move := _start("zenitsu_236A", false)
		var zenitsu = game.view.effects.zenitsu
		# Every combat step is consumed (as main.gd does); only the render steps
		# between them differ: one per tick, or one for the whole batch.
		for n in range(move.startup + 4):
			game.combat.step([Combat.neutral(), Combat.neutral()])
			game.view.consume(game.combat.events)
			if not batched:
				game.view._process(0.0)
				zenitsu.advance(0.0)
		game.view._process(0.0)
		zenitsu.advance(0.0)
		var positions: Array = Array(zenitsu.sparks.pos) + Array(zenitsu.motes.pos)
		positions.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		results.append([zenitsu.sparks.count(), zenitsu.motes.count(), zenitsu.debris.count(), positions])
	check(results[0] == results[1], "particles are identical whether ticks are sampled one by one or in a batch")
