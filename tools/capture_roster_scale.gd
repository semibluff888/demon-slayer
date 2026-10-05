extends "res://tools/capture_roster_expansion.gd"
## Diagnostic capture uses the production renderer and real combat inputs.
const REVIEW_OUT := "res://artifacts/scale-fix/engine"
var caption: Label
var sequences: Array[Dictionary] = []
var observed: Dictionary = {}

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(REVIEW_OUT)
	root.size = Vector2i(1280,720)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view,game.view.effects,game.view.hud,game.view.stage,game.view.super_view]:
		node.set_process(false)
	caption = Label.new()
	caption.position = Vector2(24,118)
	caption.add_theme_font_size_override("font_size",21)
	caption.z_index = 100
	game.add_child(caption)
	await process_frame
	if "--video" in OS.get_cmdline_user_args():
		video_folder = REVIEW_OUT + "/video"
		DirAccess.make_dir_recursive_absolute(video_folder)
		await _continuous()
	else:
		await _gallery()
	game.queue_free()
	await process_frame
	print("SCALE REVIEW CAPTURE COMPLETE")
	quit()

func _reset(cid: String, close_pair: bool = false) -> void:
	game.mode = "practice"
	game.characters.assign([cid,cid])
	game.stage_id = "infinity_castle"
	game.start_match()
	for i in range(2):
		var f = game.combat.fighters[i]
		f.x = (465.0 if i == 0 else 500.0) if close_pair else (350.0 if i == 0 else 600.0)
		f.facing = 1 if i == 0 else -1
		f.input.last_facing = f.facing
		f.previous_x = f.x
		f.meter = 300
	game.view.camera.reset(game.combat.fighters)
	game.view._process(0)
	game.view.hud._process(0)

func _gallery() -> void:
	var shots: Array[Dictionary] = []
	for cid in ["akaza","nezuko"]:
		_reset(cid)
		var actor = game.view.fighters[0]
		var visual = game.catalog.characters[cid]
		for clip_name in visual.frames.get_animation_names():
			var count: int = visual.frames.get_frame_count(clip_name)
			for index in [0,count/2,count-1]:
				actor.clip = clip_name
				actor.frame_index = index
				actor.clock_ticks = 0
				actor.texture = visual.frames.get_frame_texture(clip_name,index)
				actor.queue_redraw()
				caption.text = "%s / %s / %02d    |    P2: IDLE REFERENCE" % [cid,clip_name,index]
				await process_frame
				await RenderingServer.frame_post_draw
				var filename := "%s-%s-%02d.jpg" % [cid,clip_name,index]
				root.get_texture().get_image().save_jpg(REVIEW_OUT+"/"+filename,.94)
				shots.append({"character":cid,"clip":clip_name,"frame":index,"file":filename})
	var file := FileAccess.open(REVIEW_OUT+"/gallery.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(shots,"  "))

func _continuous() -> void:
	var actions := ["crouch","guard_low","walk","jump","roll_forward","roll_back","5A","5B","5C","5D","2A","2B","2C","2D","jA","jB","jC","jD","236A","236C","623A","623C","214B","214D","236236A","236236AC","victim_forward","victim_back"]
	for cid in ["akaza","nezuko"]:
		for action: String in actions:
			_reset(cid,action.begins_with("victim"))
			sequences.append({"character":cid,"action":action,"first_frame":frames,"seconds":frames/20.0})
			caption.text = "%s / %s    |    REAL INPUT / FIXED CAMERA SCALE" % [cid,action]
			var digits := ""
			var mask := 0
			for token in action:
				if token in "123456789":digits += token
				elif token in "ABCD":mask |= 1 << "ABCD".find(token)
			if digits.is_empty():digits = "5"
			var ticks := 180 if action.begins_with("236236") else 120
			for tick in range(ticks):
				var command := Combat.neutral()
				var other := Combat.neutral()
				if action in ["crouch","guard_low","walk"] and tick >= 18 and tick < 72:
					command.y = 0 if action == "walk" else 1
					command.x = -1 if action == "guard_low" else (1 if action == "walk" else 0)
				elif action == "jump" and tick == 18:command.y = -1
				elif action.begins_with("roll") and tick == 18:
					command.x = 1 if action == "roll_forward" else -1
					command.buttons = 3
				elif action.begins_with("victim") and tick == 18:
					other = helper.relative(6 if action == "victim_forward" else 4,-1,8)
				elif mask > 0:
					if action.begins_with("j") and tick == 12:command.y = -1
					if tick >= 24 and tick < 24+digits.length():
						command = helper.relative(int(digits[tick-24]),1,mask if tick == 23+digits.length() else 0)
				_step(command,other)
				var key: String = cid+"/"+action
				if not observed.has(key):observed[key] = []
				var clip_name: String = game.view.fighters[0].clip
				if clip_name not in observed[key]:observed[key].append(clip_name)
				if tick % 3 == 0:await _frame()
			print("SCALE INPUT ",cid," ",action," -> ",observed[cid+"/"+action])
	var file := FileAccess.open(REVIEW_OUT+"/sequences.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"fps":20,"frames":frames,"sequences":sequences,"observed_clips":observed},"  "))
