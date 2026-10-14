extends SceneTree
## Regression for Tanjiro's rebuilt effects: routing, blade tracks, freeze and
## expiry semantics, deterministic emission, and that presentation never
## touches combat.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Blade = preload("res://scripts/presentation/vfx/blade_track.gd")
var passed := 0
var failures: Array[String] = []
var game: Node2D

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)

func _run() -> void:
	create_timer(120).timeout.connect(func(): printerr("Tanjiro VFX watchdog expired"); quit(1))
	_check_tracks()
	game = Main.instantiate()
	game.settings.path = "res://artifacts/tanjiro_vfx_tests-settings.cfg"
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	game.settings.cinematic_enabled = false
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	game.mode = "local"
	await process_frame
	_check_routing()
	for spec in [["236A", false], ["236C", true]]:
		await _check_slash(spec[0], spec[1])
	for id in ["623A", "623C", "214B", "214D", "super", "max", "5A", "5C", "2A", "2C"]:
		for awakened in [false, true]:
			await _check_technique(id, awakened)
	for spec in [["j236A", false], ["j236C", true]]:
		await _check_waterfall(spec[0], spec[1])
	await _check_determinism()
	game.queue_free()
	await process_frame
	for failure in failures:
		printerr("FAIL: ", failure)
	print("TANJIRO VFX TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

## Every water slash drawing that holds the sword has a plausible blade.
func _check_tracks() -> void:
	for directory in ["res://art/characters/tanjiro/", "res://art/characters/tanjiro/awakening/"]:
		check(not Blade.clips(directory).is_empty(), "blade tracks load: " + directory)
		for index in [2, 3, 4, 6]:
			var pose := Blade.pose(directory, "water_slash", index)
			var length := pose[0].distance_to(pose[1]) if pose.size() == 2 else 0.0
			# The raised drawing foreshortens the blade behind the head.
			check(length > 60.0 and length < 260.0, "water slash drawing %d holds the blade: %s" % [index, directory])

func _check_routing() -> void:
	var tanjiro = game.view.effects.tanjiro
	check(tanjiro != null and tanjiro.layers.size() == 6, "Tanjiro effects mount six layers")
	for id in ["tanjiro_236A", "tanjiro_236C", "tanjiro_623A", "tanjiro_623C", "tanjiro_214B", "tanjiro_214D", "tanjiro_super", "tanjiro_max",
			"tanjiro_5A", "tanjiro_5C", "tanjiro_2A", "tanjiro_2C", "tanjiro_jA", "tanjiro_jC",
			"tanjiro_5AA", "tanjiro_5AAC", "tanjiro_6C", "tanjiro_j236A", "tanjiro_j236C", "tanjiro_j214B", "tanjiro_j214D"]:
		check(tanjiro.handles(game.combat.moves[id]), "rebuilt effect owns " + id)
	check(tanjiro.MOVES["tanjiro_j236A"] == "waterfall" and tanjiro.MOVES["tanjiro_j236C"] == "waterfall", "Waterfall Basin pours its own waterfall")
	for id in ["zenitsu_236A", "nezuko_super", "akaza_max", "tanjiro_5B", "tanjiro_2D", "tanjiro_6B"]:
		check(not tanjiro.handles(game.combat.moves[id]), "other fighters keep their effects: " + id)
	# EffectsView sits at z 10 and fighters at z 2: the far side of wrapped
	# shapes must land under both fighters.
	check(tanjiro.layers[0].z_index == -9, "far side of wrapped shapes draws behind the fighters")
	for layer: Node2D in tanjiro.layers.slice(1, 3):
		check(layer.z_index == -1, "solid water stays under a struck fighter: " + layer.name)
	var cues = game.view.super_view
	check(cues._owns_charge(game.combat.moves["tanjiro_super"]) and cues._owns_charge(game.combat.moves["tanjiro_max"]),
		"rebuilt supers draw their own charge instead of the shared energy sphere")
	check(not cues._owns_charge(game.combat.moves["nezuko_super"]) and not cues._owns_charge(game.combat.moves["tanjiro_236A"]),
		"other supers keep the shared energy sphere")

func _start(move_id: String, awakened: bool, height: float = 0.0) -> Resource:
	game.characters.assign(["tanjiro", "zenitsu"])
	game.start_match()
	var model = game.combat
	model.phase = "fight"
	model.remaining = 5400
	var attacker = model.fighters[0]
	attacker.x = 380.0
	model.fighters[1].x = 530.0
	attacker.facing = 1
	model.fighters[1].facing = -1
	if awakened:
		attacker.awakening_ticks = 900
		attacker.awakening_duration = 900
	if height > 0.0:
		attacker.y = model.FLOOR_Y - height
		attacker.grounded = false
		attacker.vy = 0.0
	game.view.reset_effects()
	game.view.effects.tanjiro.interpolate = false
	var move: Resource = model.moves[move_id]
	model._begin_move(attacker, move)
	game.view.consume(model.events)
	return move

func _tick() -> void:
	game.combat.step([Combat.neutral(), Combat.neutral()])
	game.view.consume(game.combat.events)
	game.view._process(1.0 / 60)
	game.view.effects._process(1.0 / 60)

func _check_slash(id: String, awakened: bool) -> void:
	var move := _start("tanjiro_" + id, awakened)
	var model = game.combat
	var tanjiro = game.view.effects.tanjiro
	var actor = game.view.fighters[0]
	var label := "%s %s" % [id, "awakened" if awakened else "normal"]
	for n in range(move.startup + 2):
		_tick()
	await process_frame # draws every layer once with the cut on screen
	check(actor.form_active() == awakened, label + " form matches")
	var arc = tanjiro.techniques.slash.sweep(actor, id.ends_with("C"))
	check(arc.a0 < -PI * 0.5 and arc.a1 > -PI * 0.5, label + " cut passes overhead")
	check(arc.r0 > 20.0 and arc.r1 < 90.0, label + " cut hugs the sword")
	check(tanjiro.drops.count() > 10 and tanjiro._projectiles.size() == 1, label + " cut sprays and the wave is tracked")
	check(tanjiro.petals.count() > 0 if awakened else tanjiro.petals.count() == 0, label + " flame petals only while awakened")
	# Hitstop, pause and KO speed hold every layer.
	var held := [tanjiro.drops.pos.duplicate(), tanjiro.foam.pos.duplicate(), tanjiro.mist.life.duplicate(), tanjiro.time]
	game.view.effects.freeze = true
	game.view.effects._process(0.5)
	check([tanjiro.drops.pos, tanjiro.foam.pos, tanjiro.mist.life, tanjiro.time] == held, label + " freeze holds particles")
	game.view.effects.freeze = false
	game.view.effects.playback_speed = 0.0
	game.view.effects._process(0.5)
	check([tanjiro.drops.pos, tanjiro.foam.pos, tanjiro.mist.life, tanjiro.time] == held, label + " zero presentation speed holds particles")
	game.view.effects.playback_speed = 1.0
	# Presentation never writes combat state.
	var snapshot: Dictionary = model.snapshot()
	tanjiro.advance(0.1)
	tanjiro.consume([{"type": "hit", "attacker": 0, "move": move.id, "segment": 0, "position": Vector2(500, 250)}])
	check(model.snapshot() == snapshot, label + " effects never mutate combat")
	check(tanjiro.bursts.size() == 3, label + " a hit adds splash, cross and ring")
	# Fly the wave until it lands or expires, then let everything settle.
	var hit := false
	for n in range(move.projectile_lifetime + 10):
		_tick()
		hit = hit or model.events.any(func(e: Dictionary) -> bool: return e.type == "hit")
		if n == 12:
			await process_frame # draws the travelling wave
	check(hit, label + " wave reaches the target")
	check(tanjiro._projectiles.is_empty(), label + " finished waves are released")
	await process_frame # draws the impact
	for n in range(90):
		game.view.effects._process(1.0 / 60)
	check(tanjiro.drops.count() == 0 and tanjiro.foam.count() == 0 and tanjiro.mist.count() == 0 and tanjiro.petals.count() == 0 and tanjiro.bursts.is_empty(),
		label + " every particle expires within a second and a half")
	_start("tanjiro_" + id, awakened)
	for n in range(move.startup + 1):
		_tick()
	game.view.reset_effects()
	check(tanjiro.drops.count() == 0 and tanjiro._ticks.is_empty() and tanjiro._projectiles.is_empty(), label + " reset clears effect state")

## 水车, 扭转漩涡, 生生流转, 碧罗之天 and the sword normals: drawing, emission,
## freeze, contact, expiry and reset, in both forms.
func _check_technique(id: String, awakened: bool) -> void:
	var move := _start("tanjiro_" + id, awakened)
	var model = game.combat
	var tanjiro = game.view.effects.tanjiro
	var attacker = model.fighters[0]
	var label := "%s %s" % [id, "awakened" if awakened else "normal"]
	var sun := id == "max"
	# Through any super freeze and into the active frames, drawing every layer.
	var guard := 0
	while attacker.move_frame < move.startup + 2 and guard < 200:
		_tick()
		guard += 1
		if guard % 6 == 0:
			await process_frame
	await process_frame
	check(tanjiro.drops.count() + tanjiro.embers.count() + tanjiro.foam.count() > 0, label + " sheds particles")
	if sun:
		check(tanjiro.embers.count() > 0, label + " is sun flame in either form")
	else:
		check(tanjiro.petals.count() > 0 if awakened else tanjiro.petals.count() == 0, label + " flame petals only while awakened")
	var held := [tanjiro.drops.pos.duplicate(), tanjiro.embers.pos.duplicate(), tanjiro.petals.pos.duplicate(), tanjiro.time]
	game.view.effects.freeze = true
	game.view.effects._process(0.5)
	check([tanjiro.drops.pos, tanjiro.embers.pos, tanjiro.petals.pos, tanjiro.time] == held, label + " freeze holds particles")
	game.view.effects.freeze = false
	var snapshot: Dictionary = model.snapshot()
	tanjiro.advance(0.05)
	tanjiro.bursts.clear()
	tanjiro.consume([{"type": "hit", "attacker": 0, "move": move.id, "segment": 0, "position": Vector2(500, 250)}])
	check(model.snapshot() == snapshot, label + " effects never mutate combat")
	# Light normals skip the gold X flash.
	check(tanjiro.bursts.size() == (2 if move.kind == "light" else 3), label + " a hit adds its contact bursts")
	# Play the move out, drawing as it goes, then let everything settle.
	var anchored := false
	for n in range(move.total_frames() + 40):
		_tick()
		if attacker.move == move and attacker.move_frame == move.startup + move.active + 2:
			anchored = tanjiro.techniques[tanjiro.MOVES[move.id]]._anchors.has(0)
			await process_frame
		elif n % 9 == 0:
			await process_frame
	if id in ["623A", "623C", "max"]:
		check(anchored, label + " leaves its shape where it was drawn")
	for n in range(90):
		game.view.effects._process(1.0 / 60)
	check(tanjiro.drops.count() == 0 and tanjiro.foam.count() == 0 and tanjiro.mist.count() == 0 and tanjiro.petals.count() == 0
		and tanjiro.embers.count() == 0 and tanjiro.bursts.is_empty(), label + " every particle expires within a second and a half")
	_start("tanjiro_" + id, awakened)
	for n in range(move.startup + move.freeze_frames + move.active + 1):
		_tick()
	game.view.reset_effects()
	var cleared := true
	for each in tanjiro.techniques.values():
		cleared = cleared and each._anchors.is_empty()
	check(cleared and tanjiro._ticks.is_empty() and tanjiro.drops.count() == 0, label + " reset clears effect state")

## 泷壶: the column rides the dive, slams into the floor, pours on after the
## move has ended (the move ends at touchdown) and clears; freezes hold it,
## an interrupted dive breaks it up, and combat is never touched.
func _check_waterfall(id: String, awakened: bool) -> void:
	var move := _start("tanjiro_" + id, awakened, 110.0)
	var model = game.combat
	var tanjiro = game.view.effects.tanjiro
	var waterfall = tanjiro.techniques.waterfall
	var attacker = model.fighters[0]
	var label := "%s %s" % [id, "awakened" if awakened else "normal"]
	var guard := 0
	while attacker.move == move and attacker.move_frame < move.startup + 1 and guard < 100:
		_tick()
		guard += 1
	await process_frame # draws the column riding the dive
	check(waterfall._columns.size() == 1 and float(waterfall._columns.values()[0].since) < 0.0, label + " column follows the dive")
	guard = 0
	while attacker.state != "landing" and guard < 120:
		_tick()
		guard += 1
		if guard % 5 == 0:
			await process_frame
	check(attacker.state == "landing" and attacker.move == null, label + " dive ends in its landing")
	var column: Dictionary = waterfall._columns.values()[0] if waterfall._columns.size() == 1 else {}
	check(bool(column.get("landed", false)) and float(column.get("since", -1.0)) >= 0.0, label + " column slams into the floor at touchdown")
	check(tanjiro.bursts.any(func(b: Dictionary) -> bool: return b.kind == "splash") and tanjiro.drops.count() > 20 and tanjiro.foam.count() > 5,
		label + " touchdown throws up spray and foam")
	check(tanjiro.petals.count() > 0 if awakened else tanjiro.petals.count() == 0, label + " flame petals only while awakened")
	await process_frame # draws the landed column and the foam bank
	var held := [tanjiro.drops.pos.duplicate(), tanjiro.foam.pos.duplicate(), tanjiro.time, column.get("emitted", 0)]
	game.view.effects.freeze = true
	game.view.effects._process(0.5)
	check([tanjiro.drops.pos, tanjiro.foam.pos, tanjiro.time, column.get("emitted", 0)] == held, label + " freeze holds the pour")
	game.view.effects.freeze = false
	var snapshot: Dictionary = model.snapshot()
	tanjiro.advance(0.05)
	check(model.snapshot() == snapshot, label + " effects never mutate combat")
	for n in range(30):
		_tick()
		if n % 8 == 0:
			await process_frame # the pour, the erosion and the settling foam
	check(waterfall._columns.size() == 1 and int(column.get("emitted", 0)) > 20, label + " pours on after the move has ended")
	for n in range(120):
		game.view.effects._process(1.0 / 60)
	check(waterfall._columns.is_empty() and tanjiro.drops.count() == 0 and tanjiro.foam.count() == 0 and tanjiro.mist.count() == 0
		and tanjiro.bursts.is_empty(), label + " waterfall and spray clear within two seconds")
	# Knocked out of the dive: the column breaks up where it was, without a slam.
	move = _start("tanjiro_" + id, awakened, 110.0)
	attacker = game.combat.fighters[0]
	while attacker.move == move and attacker.move_frame < move.startup + 2:
		_tick()
	attacker.move = null
	_tick()
	column = waterfall._columns.values()[0] if waterfall._columns.size() == 1 else {}
	check(not bool(column.get("landed", true)) and float(column.get("since", -1.0)) >= 0.0, label + " interrupted dive breaks the column up")
	await process_frame
	game.view.reset_effects()
	check(waterfall._columns.is_empty() and tanjiro._ticks.is_empty(), label + " reset clears the waterfall")

## Emission depends on combat ticks, not on how often frames sample them.
func _check_determinism() -> void:
	var results := []
	for batched in [false, true]:
		var move := _start("tanjiro_236A", false)
		var tanjiro = game.view.effects.tanjiro
		for n in range(move.startup + 3):
			game.combat.step([Combat.neutral(), Combat.neutral()])
			game.view.consume(game.combat.events)
			if not batched:
				game.view._process(0.0)
				tanjiro.advance(0.0)
		game.view._process(0.0)
		tanjiro.advance(0.0)
		# Spawn order differs (cut and wave interleave per tick), the set must not.
		var positions: Array = Array(tanjiro.drops.pos)
		positions.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		results.append([tanjiro.drops.count(), positions, tanjiro.foam.count(), tanjiro.mist.count()])
	check(results[0] == results[1], "particles are identical whether ticks are sampled one by one or in a batch")
