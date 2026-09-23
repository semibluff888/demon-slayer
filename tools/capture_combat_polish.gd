extends SceneTree
## Before/after evidence from identical held input, fixed simulation and real OpenGL.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Support = preload("res://tests/combat_test_support.gd")
var game: Node2D
var helper := Support.new()
var folder: String
var label := "after"
var video := false
var video_frame := 0
var captures: Array[Dictionary] = []
var scenarios: Array[Dictionary] = []
var caption: Label

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	video = "--video" in OS.get_cmdline_user_args()
	_run.call_deferred()

func _setup(cid: String, facing: int, distance: float = 115, mirror: bool = false) -> void:
	game.mode = "local"
	game.characters.assign([cid, cid if mirror else ("zenitsu" if cid == "tanjiro" else "tanjiro")])
	game.start_match()
	game.combat.phase = "fight"
	for i in range(2):
		var f = game.combat.fighters[i]
		f.x = 480 if i == 0 else 480 + facing * distance
		f.previous_x = f.x
		f.facing = facing if i == 0 else -facing
		f.input.last_facing = f.facing
		f.meter = 300
	game.view.reset_effects()

func _step(a: Dictionary, b: Dictionary) -> void:
	game.combat.step([a, b])
	game.view.consume(game.combat.events)
	game.view._process(1.0 / 60)
	game.view.effects._process(1.0 / 60)
	game.view.hud._process(1.0 / 60)
	game.view.super_view._process(1.0 / 60)
	game.view.stage._process(1.0 / 60)

func _image(name: String, metadata: Dictionary) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%d-%s.png" % [folder, root.size.x, name]
	root.get_texture().get_image().save_png(path)
	metadata["path"] = path
	metadata["resolution"] = [root.size.x, root.size.y]
	captures.append(metadata)

func _run() -> void:
	folder = "res://artifacts/combat-polish/" + label
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open("res://artifacts/combat-polish/.gdignore", FileAccess.WRITE).close()
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view, game.view.effects, game.view.hud, game.view.stage, game.view.super_view]:
		node.set_process(false)
	caption = Label.new()
	caption.position = Vector2(420, 190)
	caption.add_theme_font_override("font", game.catalog.body_font)
	caption.add_theme_font_size_override("font_size", 18)
	caption.z_index = 50
	game.add_child(caption)
	for width in [1280, 1920]:
		root.size = Vector2i(width, width * 9 / 16)
		for cid in ["tanjiro", "zenitsu"]:
			for facing in [1, -1]:
				for notation in (["236A", "236C", "623A", "623C", "236236A", "236236AC"] if cid == "tanjiro" else ["236A", "236C", "623A", "623C", "214B", "214D", "236236A", "236236AC"]):
					await _move(cid, notation, facing, width)
			await _meter(cid)
			await _jump(cid, false, width)
			await _jump(cid, true, width)
		await _dual(width)
	var file := FileAccess.open(folder + "/captures.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"label":label, "fps":30, "video_frames":video_frame,
		"captures":captures, "scenarios":scenarios,
		"method":"Identical held commands, 60Hz Combat.step, real Godot OpenGL at 720p and 1080p."}, "  "))
	game.queue_free()
	await process_frame
	print("COMBAT POLISH CAPTURE: ", captures.size(), " images, ", video_frame, " video frames")
	quit()

func _move(cid: String, notation: String, facing: int, width: int) -> void:
	_setup(cid, facing)
	var motion := notation.trim_suffix("AC").trim_suffix("A").trim_suffix("B").trim_suffix("C").trim_suffix("D")
	var mask := 0
	for token in notation:
		if token in "ABCD": mask |= 1 << "ABCD".find(token)
	caption.text = "%s · %s · %s" % [game.catalog.characters[cid].display_name, notation, "朝右" if facing > 0 else "朝左"]
	var saved := {}
	var states: Array[String] = []
	var record_video: bool = video and width == 1280 and facing == 1 and notation in ["236A", "623C", "214D", "236236A", "236236AC"]
	for tick in range(128):
		var held := Combat.neutral()
		if tick >= 10 and tick < 10 + motion.length():
			held = helper.relative(int(motion[tick - 10]), facing, mask if tick == 9 + motion.length() else 0)
		_step(held, Combat.neutral())
		states.append(JSON.stringify(game.combat.snapshot()).sha256_text())
		var f = game.combat.fighters[0]
		var phase := ""
		if f.move != null:
			if f.move_frame < f.move.startup: phase = "startup"
			elif f.move_frame < f.move.startup + f.move.active:
				phase = "active-%d" % f.move.segment(f.move_frame)
				if f.move_frame < f.move.segment_start(f.move.segment(f.move_frame)) + 2: phase = ""
			else: phase = "recovery"
		elif tick > 70: phase = "idle"
		if not game.combat.projectiles.is_empty() and tick > 30: phase = "projectile"
		if not phase.is_empty() and not saved.has(phase):
			saved[phase] = true
			await _image("%s-%s-%d-%s" % [cid, notation, facing, phase], {
				"character":cid, "notation":notation, "facing":facing, "phase":phase,
				"clip":game.view.fighters[0].clip, "frame":game.view.fighters[0].frame_index,
				"ghosts":game.view.fighters[0].afterimages.size(), "tick":tick})
		if record_video and tick % 2 == 0:
			await _video_frame()
	scenarios.append({"id":"%d-%s-%s-%d" % [width,cid,notation,facing], "hashes":states})
	print("CAPTURE ", width, " ", cid, " ", notation, " ", facing)

func _meter(cid: String) -> void:
	_setup(cid, 1, 140, true)
	caption.text = game.catalog.characters[cid].display_name + " · 呼吸槽"
	for value in [299, 300, 200]:
		game.combat.fighters[0].meter = value
		for tick in range(35): _step(Combat.neutral(), Combat.neutral())
		await _image("%s-meter-%d" % [cid,value], {"character":cid,"meter":value,"mirror":true})

func _jump(cid: String, running: bool, width: int) -> void:
	_setup(cid, 1, 260)
	caption.text = game.catalog.characters[cid].display_name + (" · 冲刺跳跃" if running else " · 普通前跳")
	var positions: Array = []
	for tick in range(76):
		var held := Combat.neutral()
		if running and tick in [5,7,8,9]: held.x = 1
		if tick == 10:
			held.x = 0 if running else 1
			held.y = -1
		_step(held, Combat.neutral())
		var f = game.combat.fighters[0]
		if tick >= 10: positions.append([f.x,f.y])
		if tick in [10,28,47]:
			await _image("%s-%s-%d" % [cid,"dash-jump" if running else "jump",tick], {"character":cid,"dash":running,"tick":tick})
		if video and width == 1280 and tick % 2 == 0: await _video_frame()
	scenarios.append({"id":"%d-%s-%s" % [width,cid,"dash-jump" if running else "jump"], "positions":positions})

func _dual(width: int) -> void:
	_setup("tanjiro", 1, 150)
	caption.text = "双方同时释放 MAX"
	for tick in range(90):
		var held := Combat.neutral()
		var other := Combat.neutral()
		if tick >= 10 and tick < 16:
			held = helper.relative(int("236236"[tick-10]),1,5 if tick == 15 else 0)
			other = helper.relative(int("236236"[tick-10]),-1,5 if tick == 15 else 0)
		_step(held, other)
		if tick in [25,44,49]:
			await _image("dual-max-%d" % tick, {"tick":tick,"dual":true})
		if video and width == 1280 and tick % 2 == 0: await _video_frame()

func _video_frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(folder + "/frame-%05d.jpg" % video_frame, 0.91)
	video_frame += 1
