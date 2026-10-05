extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Support = preload("res://tests/combat_test_support.gd")
const Combat = preload("res://scripts/combat.gd")
const OUT := "res://artifacts/roster-v1"
var game: Node2D
var helper := Support.new()
var frames: int = 0
var audio_events: Array[Dictionary] = []
var video_tick: int = 0
var captures: Array[String] = []
var video_folder: String = OUT + "/video"
var chapters: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view, game.view.effects, game.view.hud, game.view.stage, game.view.super_view]:
		node.set_process(false)
	await process_frame
	if "--stages-video" in OS.get_cmdline_user_args():
		video_folder = OUT + "/stage-video"
		await _stage_video()
	elif "--video" in OS.get_cmdline_user_args():
		await _video()
	else:
		await _menus()
		if "--menus" not in OS.get_cmdline_user_args():
			await _battles()
	var report := FileAccess.open(video_folder + "/capture.json" if frames > 0 else OUT + "/captures.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"captures": captures, "video_frames": frames, "method": "Actual Godot rendering; combat uses held direction/button inputs."}, "  "))
	game.queue_free()
	await process_frame
	print("ROSTER CAPTURE COMPLETE: ", captures.size(), " screenshots, ", frames, " video frames")
	quit()

func _menus() -> void:
	for resolution in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3840,2160),Vector2i(1600,1000)]:
		root.size = resolution
		game.show_title()
		await _save("%dx%d-title" % [resolution.x,resolution.y])
		game.choose_mode("local")
		game.select_character(0, "nezuko")
		game.select_character(1, "akaza")
		await _save("%dx%d-select" % [resolution.x,resolution.y])
		game.selection.confirm(0)
		game.selection.confirm(1)
		await _save("%dx%d-stages" % [resolution.x,resolution.y])
	root.size = Vector2i(1280,720)

func _battles() -> void:
	for stage_id: String in game.catalog.stages:
		game.stage_id = stage_id
		game.mode = "practice"
		game.characters.assign(["nezuko","akaza"])
		game.start_match()
		_step()
		await _save("stage-" + stage_id)
		for edge in [Combat.LEFT, Combat.RIGHT]:
			for f in game.combat.fighters:
				f.x = edge + (70 if edge == Combat.LEFT else -70) * f.slot
				f.previous_x = f.x
			game.view.camera.reset(game.combat.fighters)
			_step()
			await _save("stage-%s-%s" % [stage_id, "left" if edge == Combat.LEFT else "right"])

func _step(command: Dictionary = {}, second_command: Dictionary = {}) -> void:
	var held := Combat.neutral()
	held.merge(command,true)
	var second := Combat.neutral()
	second.merge(second_command,true)
	game.combat.step([held,second])
	if game.mode == "practice": game.practice_controller.after_step(game.combat)
	game.view.consume(game.combat.events)
	for cue in game.sound.cues(game.combat.events,game.combat):
		audio_events.append({"tick":video_tick,"kind":cue.kind,"gain":cue.gain})
	game.view._process(1.0/60)
	game.view.effects._process(1.0/60)
	game.view.hud._process(1.0/60)
	game.view.super_view._process(1.0/60)
	game.view.stage._process(1.0/60)
	video_tick += 1

func _save(name: String) -> void:
	await create_timer(0.28).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/" + name + ".png")
	captures.append(name + ".png")

func _video() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(video_folder + "/audio")
	for key: String in game.sound.streams:
		game.sound.streams[key].save_to_wav(video_folder + "/audio/" + key + ".wav")
	for cid in ["nezuko","akaza"]:
		chapters.append({"character":cid,"start_seconds":frames/30.0})
		for notation in ["5A","5B","5C","5D","2A","2B","2C","2D","jA","jB","jC","jD","6D","4D","4AB","236A","236C","623A","623C","214B","214D","236236A","236236AC"]:
			game.mode = "practice"
			game.characters.assign([cid,"akaza" if cid == "nezuko" else "nezuko"])
			game.stage_id = "entertainment_district" if cid == "nezuko" else "infinity_castle"
			game.start_match()
			var a = game.combat.fighters[0]
			var b = game.combat.fighters[1]
			a.x=465; b.x=500; a.facing=1; b.facing=-1
			for f in game.combat.fighters:
				f.previous_x=f.x; f.input.last_facing=f.facing
			game.view.camera.reset(game.combat.fighters)
			var digits := ""
			var mask := 0
			for c in notation:
				if c in "123456789": digits += c
				elif c in "ABCD": mask |= 1 << "ABCD".find(c)
			if digits.is_empty(): digits = "5"
			for tick in range(150):
				var command := Combat.neutral()
				if notation.begins_with("j") and tick == 12: command.y = -1
				if tick >= 24 and tick < 24+digits.length():
					command = helper.relative(int(digits[tick-24]),1,mask if tick==23+digits.length() else 0)
				_step(command)
				if tick%2==0:
					await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_jpg(video_folder + "/frame-%05d.jpg" % frames,0.91)
					frames += 1
			print("CAPTURE ",cid," ",notation)
		await _round_clip(cid)
	_write_video_metadata()

func _write_video_metadata() -> void:
	var cue_file := FileAccess.open(video_folder + "/cues.json",FileAccess.WRITE)
	cue_file.store_string(JSON.stringify({"frames":frames,"fps":30,"audio_events":audio_events,"chapters":chapters,"audio_method":"Godot PCM mixed at recorded 60 Hz combat-event timestamps"}))

func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(video_folder + "/frame-%05d.jpg" % frames,0.91)
	frames += 1

func _round_clip(cid: String) -> void:
	game.mode = "local"
	game.characters.assign([cid,"akaza" if cid=="nezuko" else "nezuko"])
	game.start_match()
	for tick in range(Combat.Flow.OPENING + 30):
		_step()
		if tick % 2 == 0: await _frame()
	game.combat.fighters[0].x = 465
	game.combat.fighters[1].x = 500
	game.combat.fighters[0].meter = 300
	game.combat.fighters[1].hp = 50
	for fighter in game.combat.fighters:
		fighter.previous_x = fighter.x
		fighter.input.last_facing = fighter.facing
	for tick in range(260):
		_step(helper.relative(int("236236"[tick]),1,5 if tick==5 else 0) if tick<6 else {})
		if tick % 2 == 0: await _frame()
	print("CAPTURE intro / MAX KO / victory ",cid)

func _stage_video() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(video_folder + "/audio")
	for key: String in game.sound.streams:
		game.sound.streams[key].save_to_wav(video_folder + "/audio/" + key + ".wav")
	for sid in ["infinity_castle","entertainment_district"]:
		game.mode = "practice"
		game.characters.assign(["nezuko","akaza"])
		game.stage_id = sid
		game.start_match()
		game.combat.fighters[0].x = 65
		game.combat.fighters[1].x = 125
		for fighter in game.combat.fighters: fighter.previous_x = fighter.x
		game.view.camera.reset(game.combat.fighters)
		chapters.append({"stage":sid,"start_seconds":frames/30.0})
		for tick in range(900):
			var direction := 1 if tick < 450 else -1
			_step({"x":direction},{"x":direction})
			if tick % 2 == 0: await _frame()
		print("CAPTURE stage scroll ",sid)
	_write_video_metadata()
