extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Camera = preload("res://scripts/presentation/duel_camera.gd")
const Visual = preload("res://scripts/presentation/character_visual.gd")
const Actor = preload("res://scripts/presentation/fighter_view.gd")
const Main = preload("res://scenes/main.tscn")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
const AI = preload("res://scripts/ai_controller.gd")
var passed: int = 0
var failures: Array[String] = []
var capture: bool = false
var game: Node2D

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(message)

func _run() -> void:
	_test_camera()
	_test_animation()
	_test_assets()
	await _test_freeze()
	if capture:
		await _render_checks()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("PRESENTATION TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_camera() -> void:
	var model := Combat.new()
	var camera := Camera.new()
	for positions in [[28,54], [906,932], [400,770], [594,366]]:
		model.fighters[0].x = positions[0]
		model.fighters[1].x = positions[1]
		for altitude in [286.0, 250.0, 217.42]:
			model.fighters[0].y = altitude
			camera.update(model.fighters, 1.0 / 144)
			check(camera.zoom == 3.0, "camera scale stays fixed at every distance and jump height")
			for f in model.fighters:
				var feet := camera.point(Vector2(f.x, f.y))
				check(feet.x >= 83.99 and feet.x <= 1196.01, "both bodies stay visible during camera motion")
	check(is_equal_approx(camera.point(Vector2(320, 286)).y, 594), "floor anchor remains stable")

func _test_animation() -> void:
	var model := Combat.new()
	var visual := Visual.new()
	visual.frames = SpriteFrames.new()
	visual.frames.remove_animation("default")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	for clip in ["idle", "stand_light", "walk_back", "guard_low", "knockdown", "victory", "jump", "hit", "guard", "crouch", "jump_forward", "jump_back", "dash_forward", "dash_back", "throw_success", "thrown", "air_light"]:
		visual.frames.add_animation(clip)
		visual.frames.set_animation_loop(clip, clip in ["idle", "walk_back"])
		visual.frames.set_animation_speed(clip, 12)
		for n in range(6):
			visual.frames.add_frame(clip, texture)
		visual.phases[clip] = [2, 4]
	var actor := Actor.new()
	actor.combat = model
	actor.fighter = model.fighters[0]
	actor.visual = visual
	root.add_child(actor)
	model.phase = "fight"
	actor.fighter.move = model.catalog.characters.tanjiro.normals["5A"]
	var move = actor.fighter.move
	for pair in [[0, 0], [move.startup - 1, 1], [move.startup, 2], [move.startup + move.active - 1, 3], [move.startup + move.active, 4], [move.total_frames() - 1, 5]]:
		actor.fighter.move_frame = pair[0]
		actor.sync(1.0 / 60, false)
		check(actor.frame_index == pair[1], "startup / active / recovery phase follows model frame")
	actor.fighter.move = null
	actor.fighter.state = "idle"
	actor.sync(0.1, false)
	var before: float = actor.clock_ticks
	var before_frame: int = actor.frame_index
	actor.sync(1, true)
	check(actor.clock_ticks == before and actor.frame_index == before_frame, "hitstop freezes idle pose")
	actor.fighter.state = "walk"
	actor.fighter.axis = -actor.fighter.facing
	actor.sync(0.1, false)
	check(actor.clip == "walk_back", "backward movement maps to backward animation")
	actor.fighter.state = "block"
	actor.fighter.crouching = true
	actor.sync(0.1, false)
	check(actor.clip == "guard_low", "crouching defense has its own pose")
	actor.fighter.state = "hit"
	actor.fighter.stun = 18
	actor.sync(0.20, false)
	actor.fighter.stun = 10
	actor.sync(0.04, false)
	actor.consume([{"type": "hit", "attacker": 1}], 0)
	actor.fighter.stun = 18
	actor.sync(0, true)
	check(actor.frame_index == 0 and actor.clock_ticks == 0, "a fresh hit restarts recoil during hitstop")
	actor.fighter.state = "knockdown"
	actor.sync(2, false)
	check(actor.frame_index == 5, "knockdown holds its final grounded pose")
	actor.fighter.state = "air"
	actor.fighter.grounded = false
	actor.fighter.vy = -7.8
	actor.sync(0.016, false)
	check(actor.frame_index == 1, "rising jump maps to ascending pose")
	actor.fighter.vy = 0
	actor.sync(0.016, false)
	check(actor.frame_index == 2, "apex has a dedicated jump pose")
	actor.fighter.vy = 6
	actor.sync(0.016, false)
	check(actor.frame_index == 3, "falling jump maps to descending pose")
	actor.fighter.grounded = true
	actor.fighter.state = "idle"
	actor.sync(0.016, false)
	check(actor.clip == "jump" and actor.frame_index == 4, "ordinary landing shows compression without extra gameplay stun")
	actor.sync(0.06, false)
	check(actor.frame_index == 5, "landing decompresses before returning to idle")
	actor.fighter.move = model.catalog.characters.tanjiro.normals["5A"]
	actor.fighter.move_frame = move.total_frames() - 1
	actor.sync(0.1, false)
	actor.consume([{"type": "swing", "attacker": 0}], 0)
	actor.fighter.move_frame = 0
	actor.sync(0, false)
	check(actor.frame_index == 0, "same move starts from its first frame on repeated use")
	var f = actor.fighter
	f.move = null
	f.grounded = false
	f.state = "air"
	f.flip_jump = true
	f.air_used_move = false
	f.jump_facing = 1
	f.facing = -1
	f.air_ticks = 18
	actor.sync(0, false)
	check(actor.clip == "jump_forward" and actor.pose_facing() == 1, "flip keeps takeoff orientation through cross-up")
	f.jump_back = true
	actor.sync(0, false)
	check(actor.clip == "jump_back", "back jump uses its own somersault drawings")
	f.move = model.catalog.characters.tanjiro.normals.jA
	f.move_frame = 0
	f.air_used_move = true
	actor.sync(0, false)
	check(actor.clip == "air_light" and actor.pose_facing() == -1, "air strike immediately uses combat facing and existing strike pose")
	f.move = null
	actor.sync(0, false)
	check(actor.clip == "jump" and actor.frame_index == 3, "air strike recovery descends without restarting flip")
	f.grounded = true
	f.state = "dash"
	f.dash_back = true
	f.dash_frame = 4
	actor.sync(0, false)
	check(actor.clip == "dash_back", "retreat dash keeps its dedicated running cycle")
	f.state = "thrown"
	f.throw_role = "victim"
	f.throw_frame = 12
	f.throw_facing = -1
	actor.sync(0, false)
	check(actor.clip == "thrown" and actor.pose_facing() == -1, "throw victim follows shared role and orientation")
	var throw_pose: int = actor.frame_index
	actor.sync(1, true)
	check(actor.frame_index == throw_pose, "pause freezes throw timeline pose")
	f.throw_role = ""
	f.state = "idle"
	actor.reset_pose()
	check(actor.clock_ticks == 0 and actor.afterimages.is_empty(), "rematch clears visual state")
	actor.queue_free()

func _test_assets() -> void:
	var catalog := Catalog.new()
	check(catalog.stage.art_ready and catalog.stage.layers.size() == 1, "one complete continuous stage painting exists")
	var counts := {"idle": 6, "walk": 8, "walk_back": 8, "crouch": 3, "jump": 6, "guard": 3, "guard_low": 3, "hit": 4, "knockdown": 5, "throw": 6, "victory": 6, "stand_light": 6, "stand_heavy": 6, "crouch_light": 6, "crouch_heavy": 6, "air_light": 6, "air_heavy": 6, "dash_forward": 8, "dash_back": 8, "jump_forward": 8, "jump_back": 8, "throw_success": 12, "thrown": 12}
	for character: String in catalog.characters:
		var visual = catalog.characters[character]
		check(visual.art_ready, "complete illustrated actor: " + character)
		check(visual.avatar != null and visual.portrait != null, "portrait and HUD avatar: " + character)
		var expected := counts.duplicate()
		for move in (["water_slash", "water_wheel"] if character == "tanjiro" else ["iai", "thunder"]):
			expected[move] = 9
		for clip: String in expected:
			var available: bool = visual.frames != null and visual.frames.has_animation(clip)
			check(available, "animation exists: " + character + "/" + clip)
			if not available:
				continue
			check(visual.frames.get_frame_count(clip) >= expected[clip], "frame coverage: " + character + "/" + clip)
			for n in range(visual.frames.get_frame_count(clip)):
				var frame: Texture2D = visual.frames.get_frame_texture(clip, n)
				check(frame != null and frame.get_size() == Vector2(1024, 640), "common anchor canvas for " + character + "/" + clip + "/" + str(n))
		_test_artwork_camera(visual)
		_test_calm_idle(visual)
	for id in ["water-slash", "water-wheel", "thunder", "impact"]:
		check(ResourceLoader.exists("res://art/effects/%s.png" % id), "real VFX texture: " + id)

func _test_artwork_camera(visual: Resource) -> void:
	var model := Combat.new()
	var actor := Actor.new()
	actor.visual = visual
	actor.fighter = model.fighters[0]
	var camera := Camera.new()
	for clip: String in visual.frames.get_animation_names():
		for frame in range(visual.frames.get_frame_count(clip)):
			actor.texture = visual.frames.get_frame_texture(clip, frame)
			var bounds := actor.visual_bounds()
			camera.update(model.fighters, 1.0/60, [bounds])
			check(camera.zoom == 3.0, "no animation silhouette changes camera scale: " + clip)
			check(bounds.size.x > 0 and bounds.size.y > 0, "artwork retains a measurable physical size")
	actor.free()

func _test_calm_idle(visual: Resource) -> void:
	var model := Combat.new()
	model.phase = "fight"
	var actor := Actor.new()
	actor.visual = visual
	actor.combat = model
	actor.fighter = model.fighters[0]
	actor.sync(0, false)
	var initial := actor.visual_bounds()
	var low: float = initial.size.y
	var high: float = low
	for tick in range(120):
		actor.sync(1.0 / 30, false)
		var bounds := actor.visual_bounds()
		low = minf(low, bounds.size.y)
		high = maxf(high, bounds.size.y)
		check(is_equal_approx(bounds.size.x, initial.size.x), "idle never sways or changes horizontal size")
		check(absf(bounds.end.y - initial.end.y) < 0.02, "idle keeps its ground contact planted")
	check((high - low) * 3.0 < 1.5, "idle breathing stays below 1.5 screen pixels peak to peak at 720p")
	check(high > low, "idle keeps a subtle breathing motion")
	var before := actor.visual_bounds()
	actor.sync(1.0, true)
	check(actor.visual_bounds() == before, "pause freezes the continuous idle breath")
	actor.free()

func _test_freeze() -> void:
	var instance := Main.instantiate()
	root.add_child(instance)
	instance.set_physics_process(false)
	instance.sound.muted = true
	instance.start_match()
	await process_frame
	# Check the relative screen displacement of a stationary fighter and the floor.
	var floor_before: float = instance.view.stage.layers[0].position.x
	var fighter_before: float = instance.view.camera.point(Vector2(instance.combat.fighters[0].x,286)).x
	instance.combat.fighters[1].x += 80
	for n in range(8):
		await process_frame
	var floor_after: float = instance.view.stage.layers[0].position.x
	var fighter_after: float = instance.view.camera.point(Vector2(instance.combat.fighters[0].x,286)).x
	check(is_equal_approx(floor_after-floor_before, fighter_after-fighter_before), "stationary feet and floor share identical camera displacement")
	check(instance.view.stage.layers.size() == 1 and instance.view.stage.visual.parallax_factors[0] == 1.0, "moon, reflection and architecture share the floor transform")
	instance.set_paused(true)
	await process_frame
	var stage_time: float = instance.view.stage.time
	var camera_center: float = instance.view.camera.center_x
	var effect_time: float = instance.view.effects.time
	var snapshot: Dictionary = instance.combat.snapshot()
	for n in range(4):
		await process_frame
	check(instance.view.stage.time == stage_time, "pause freezes scene atmosphere")
	check(instance.view.effects.time == effect_time, "pause freezes effects")
	check(instance.view.camera.center_x == camera_center, "pause freezes camera")
	check(instance.combat.snapshot() == snapshot, "visual pause leaves combat untouched")
	instance.start_match()
	check(instance.view.effects.rings.is_empty() and instance.view.effects.sparks.is_empty(), "rematch clears impact effects")
	instance.queue_free()
	await process_frame

func _render_checks() -> void:
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for resolution in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		game.show_title()
		await _save("title-%d" % resolution.x, resolution)
		game.choose_mode("local")
		await _save("select-%d" % resolution.x, resolution)
		game.show_help()
		await _save("help-%d" % resolution.x, resolution)
		game.start_match()
		game.set_paused(true)
		await _save("pause-%d" % resolution.x, resolution)
		game.set_paused(false)
		game.combat.phase = "fight"
		await _save("fight-%d" % resolution.x, resolution)
		game.choose_mode("practice")
		game.start_match()
		await _save("practice-%d" % resolution.x, resolution)
		game.combat.step([{"y": 1}, {}])
		for n in range(3):
			game.combat.step([{"x": 1, "y": 1, "buttons": 1}, {}])
		await _save("practice-input-hint-%d" % resolution.x, resolution)
		game.reset_practice()
		game.combat.fighters[0].facing = -1
		game.combat.fighters[0].x = 550
		await _save("practice-input-left-%d" % resolution.x, resolution)
		game.show_practice_options()
		await _save("practice-options-%d" % resolution.x, resolution)
		game.set_paused(false)
		game.show_help()
		game.gui._help_page("moves")
		await _save("moves-%d" % resolution.x, resolution)
		game.gui._help_page("normals")
		await _save("normals-%d" % resolution.x, resolution)
		game.close_help()
		game.mode = "local"
		game.start_match()
		game.combat.phase = "match_end"
		game.combat.match_winner = 0 if resolution.x == 960 else 1
		game.combat.wins.assign([2, 1] if resolution.x == 960 else [1, 2])
		game.show_result()
		await _save("result-%d" % resolution.x, resolution)
	root.size = Vector2i(1280, 720)
	game.start_match()
	game.combat.phase = "fight"
	game.combat.fighters[0].x = 285
	game.combat.fighters[1].x = 363
	await _save("duel-neutral", root.size)
	for character in game.combat.catalog.characters:
		for move in game.combat.catalog.characters[character].all_moves():
			game.combat.new_match(character, "zenitsu")
			game.view.reset_effects()
			game.combat.phase = "fight"
			var a = game.combat.fighters[0]
			var b = game.combat.fighters[1]
			a.x = 285
			b.x = 320 if move.kind == "throw" else 343
			a.meter = 300
			if move.stance == "air":
				a.y = 241
				a.grounded = false
				a.vy = -2
			game.combat._begin_move(a, move)
			game.view.consume(game.combat.events)
			check(a.move == move, "render case entered resource: " + move.id)
			for n in range(move.startup + move.freeze_frames + 1):
				game.combat.step([Combat.neutral(), Combat.neutral()])
				game.view.consume(game.combat.events)
			await _save("move-" + move.id, root.size)
	for character in ["tanjiro", "zenitsu"]:
		game.characters.assign([character, character])
		game.start_match()
		game.combat.phase = "fight"
		game.combat.fighters[0].x = 285
		game.combat.fighters[1].x = 363
		await _save("mirror-" + character, root.size)
	# Both fighters are active AI through the same public combat commands. Performance
	# sampling excludes PNG encoding and spans multiple rounds and real impacts.
	root.size = Vector2i(1920, 1080)
	game.characters.assign(["tanjiro", "zenitsu"])
	game.start_match()
	game.combat.phase = "fight"
	game.combat.fighters[0].x = 285
	game.combat.fighters[1].x = 360
	var first_ai := AI.new(193)
	var second_ai := AI.new(311)
	await create_timer(1).timeout
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for n in range(1800):
		if game.combat.phase == "match_end":
			game.start_match()
			first_ai.reset()
			second_ai.reset()
		game.combat.step([first_ai.command(game.combat.fighters[0].observable(), game.combat.fighters[1].observable()), second_ai.command(game.combat.fighters[1].observable(), game.combat.fighters[0].observable())])
		game.view.consume(game.combat.events)
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		previous = now
	samples.sort()
	var total: float = samples.reduce(func(a: float, b: float): return a + b, 0.0)
	var report := {"frames": samples.size(), "mean_frame_ms": total / samples.size(), "p95_frame_ms": samples[int(samples.size() * 0.95)], "p99_frame_ms": samples[int(samples.size() * 0.99)], "mean_fps": 1000 / (total / samples.size()), "scope": "final local anime art, 1080p, 1800 rendered AI-versus-AI combat frames", "gpu": RenderingServer.get_video_adapter_name(), "all_art_ready": game.catalog.characters.tanjiro.art_ready and game.catalog.characters.zenitsu.art_ready and game.catalog.stage.art_ready}
	check(report.all_art_ready, "performance uses final complete artwork")
	check(report.p95_frame_ms < 16.67, "1080p p95 render time meets 60 FPS budget")
	var file := FileAccess.open("res://artifacts/performance-hd.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("1080P PRESENTATION PERFORMANCE: ", report)
	game.queue_free()
	await process_frame

func _save(id: String, resolution: Vector2i) -> void:
	await create_timer(0.32).timeout
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size() == resolution, "render output size: " + id)
	check(image.save_png("res://artifacts/" + id + ".png") == OK, "render saved: " + id)
