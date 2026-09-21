extends SceneTree
## Input-driven scale review: same-character duels, both facings and two resolutions.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Support = preload("res://tests/combat_test_support.gd")
const OUT = "res://artifacts/character-scale/engine"
const CASES = {
	"tanjiro": {"2A":"crouch_light", "2D":"body_crouch_heavy", "jD":"body_air_heavy",
		"236236AC":"sun_arc", "5AB":"roll_forward", "hit2D":"knockdown",
		"hit5A":"hit", "hit5C":"hit"},
	"zenitsu": {"5D":"body_stand_heavy", "2D":"body_crouch_heavy", "jC":"air_heavy",
		"214B":"iai_return", "236A":"thunder", "5AB":"roll_forward", "4AB":"roll_back",
		"6D":"throw_forward", "hit6D":"thrown_forward"}
}
var game: Node2D
var helper := Support.new()
var captures: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# --hit-only keeps follow-up hit-reaction checks separate from the full matrix.
	var hit_only := "--hit-only" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(OUT)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view, game.view.effects, game.view.hud, game.view.stage, game.view.super_view]:
		node.set_process(false)
	for width in [1280, 1920]:
		root.size = Vector2i(width, width * 9 / 16)
		for cid: String in CASES:
			for facing in [-1, 1]:
				for notation: String in CASES[cid]:
					if hit_only and CASES[cid][notation] != "hit":
						continue
					await _case(width, cid, facing, notation, CASES[cid][notation])
	var report := FileAccess.open(OUT + ("/captures-hit.json" if hit_only else "/captures.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"method":"Godot OpenGL with held combat inputs; same-character duels at fixed camera scale", "captures":captures, "failures":failures}, "  "))
	game.queue_free()
	await process_frame
	for failure: String in failures:
		printerr("FAIL: ", failure)
	print("CHARACTER SCALE CAPTURE: %d images, %d failed" % [captures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func _case(width: int, cid: String, facing: int, notation: String, expected: String) -> void:
	game.mode = "practice"
	game.characters.assign([cid, cid])
	game.start_match()
	var model = game.combat
	var a = model.fighters[0]
	var b = model.fighters[1]
	var receive := notation.begins_with("hit")
	var attack := notation.trim_prefix("hit")
	var close_range := receive or attack == "6D"
	a.x = 480 - facing * (17 if close_range else 75)
	b.x = 480 + facing * (17 if close_range else 75)
	a.facing = facing
	b.facing = -facing
	for f in model.fighters:
		f.previous_x = f.x
		f.input.last_facing = f.facing
		f.meter = 300
	game.view.reset_effects()
	var motion := ""
	var buttons := 0
	for token in attack:
		if token in "123456789":
			motion += token
		if token in "ABCD":
			buttons |= 1 << "ABCD".find(token)
	var airborne := attack.begins_with("j")
	if airborne:
		motion = "5"
	var start_tick := 15 if airborne else 8
	var saved := {}
	for tick in range(180):
		var held := Combat.neutral()
		var attacker_facing: int = b.facing if receive else a.facing
		if airborne and tick == 6:
			held = helper.relative(8, attacker_facing)
		elif tick >= start_tick and tick < start_tick + motion.length():
			held = helper.relative(int(motion[tick-start_tick]), attacker_facing, buttons if tick == start_tick + motion.length() - 1 else 0)
		model.step([Combat.neutral(), held] if receive else [held, Combat.neutral()])
		game.view.consume(model.events)
		for node in [game.view, game.view.effects, game.view.hud, game.view.super_view, game.view.stage]:
			node._process(1.0/60)
		var actor = game.view.fighters[0]
		var phase := ""
		if tick == 3:
			phase = "idle"
		elif actor.clip == expected:
			var cuts: Array = actor.visual.phases[expected]
			phase = "startup" if actor.frame_index < cuts[0] else ("active" if actor.frame_index < cuts[1] else "recovery")
		elif saved.has("recovery") and actor.clip == "idle":
			phase = "return"
		# The initial grab uses its own preparation clip before the linked throw.
		elif attack == "6D" and not receive and actor.clip == "throw":
			phase = "grab"
		if phase.is_empty() or saved.has(phase):
			continue
		saved[phase] = true
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		var name := "%d-%s-%s-%s-%s.png" % [width, cid, "left" if facing < 0 else "right", notation, phase]
		if picture.get_size() != root.size or picture.save_png(OUT + "/" + name) != OK:
			failures.append(name + " capture failed")
		captures.append({"path":name, "character":cid, "notation":notation, "facing":facing,
			"width":width, "phase":phase, "clip":actor.clip, "drawing":actor.frame_index,
			"feet":[a.x, a.y], "camera_zoom":game.view.camera.zoom})
	for phase in ["idle", "startup", "active", "recovery", "return"]:
		if not saved.has(phase):
			failures.append("%s/%s/%s missing %s" % [cid, notation, facing, phase])
	print("SCALE ", width, " ", cid, " ", facing, " ", notation, " ", saved.keys())

