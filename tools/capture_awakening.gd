extends "res://tools/capture_roster_expansion.gd"
var awakening_out: String = "res://artifacts/awakening-v2" if "--v2" in OS.get_cmdline_user_args() else "res://artifacts/awakening"
var checks: int = 0
var failures: Array[String] = []
var motion_trace: Array[Dictionary] = []

func _check(value: bool, label: String) -> void:
	if value: checks += 1
	else: failures.append(label); printerr("FAIL: ",label)

func _run() -> void:
	var selected_characters: Array[String] = ["tanjiro", "zenitsu", "nezuko", "akaza"]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--character="):
			selected_characters.assign([argument.trim_prefix("--character=")])
		elif argument.begins_with("--output="):
			awakening_out = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(awakening_out)
	root.size = Vector2i(1280,720)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view,game.view.effects,game.view.hud,game.view.stage,game.view.super_view]:
		node.set_process(false)
	await process_frame
	for cid in selected_characters:
		game.mode = "practice"
		game.characters.assign([cid,cid])
		game.stage_id = "infinity_castle"
		game.start_match()
		game.combat.fighters[0].x = 405
		game.combat.fighters[1].x = 555
		for f in game.combat.fighters: f.previous_x = f.x
		game.view.camera.reset(game.combat.fighters)
		_step()
		var actor = game.view.fighters[0]
		var other = game.view.fighters[1]
		_check(game.catalog.characters[cid].art_ready,cid+" complete imported assets")
		var original = actor.texture
		var normal_scale: Vector2 = actor._pose_scale()
		_step({"buttons":6})
		_step()
		_step()
		_check(game.combat.fighters[0].awakening_ticks == 600, cid+" activated via BC")
		await _shot(cid+"-activation")
		for n in range(40): _step()
		_check(actor.form_active() and not other.form_active(),cid+" independent mirror state")
		if cid != "akaza": _check(actor.texture != original,cid+" uses new artwork")
		if cid == "nezuko": _check(is_equal_approx(actor._pose_scale().x/normal_scale.x,1.15),"Nezuko grows exactly 15 percent")
		_check(actor.texture != null and (not actor.texture is AtlasTexture or actor.texture.atlas != null),cid+" rendered texture is present")
		await _shot(cid+"-mirror")
		if cid == "nezuko":
			for resolution in [Vector2i(960,540),Vector2i(1920,1080)]:
				root.size = resolution
				await _shot("nezuko-mirror-%dx%d" % [resolution.x,resolution.y])
			root.size = Vector2i(1280,720)
		if "--pilot" in OS.get_cmdline_user_args():
			continue
		var saved_ticks: int = game.combat.fighters[0].awakening_ticks
		game.combat.fighters[0].awakening_ticks = 110
		game.view.hud.awakening_reveal[0] = 0
		game.view.hud.queue_redraw()
		await _shot(cid+"-warning")
		game.combat.fighters[0].awakening_ticks = saved_ticks
		var clock: float = actor.clock_ticks
		var snapshot: Dictionary = game.combat.snapshot()
		game.view.paused = true
		game.view._process(1.0)
		_check(actor.clock_ticks == clock and snapshot == game.combat.snapshot(),cid+" pause freezes pose and model")
		game.view.paused = false
		for n in range(12): _step({"y":-1} if n == 0 else {})
		_check(actor.form_active() and not game.combat.fighters[0].grounded,cid+" jump keeps form")
		await _shot(cid+"-jump")
		for n in range(50): _step()
		for n in range(9): _step({"x":-1,"y":1})
		await _shot(cid+"-crouch")
		for n in range(3): _step()
		game.combat.fighters[0].x = 460
		game.combat.fighters[1].x = 494
		for f in game.combat.fighters: f.previous_x = f.x
		_step({}, {"buttons":1})
		for n in range(12):
			_step()
			if game.combat.fighters[0].state == "hit": break
		_check(actor.form_active() and game.combat.fighters[0].state == "hit",cid+" hit reaction keeps form")
		await _shot(cid+"-hit")
		for n in range(50): _step()
		game.combat.fighters[0].x = 460
		game.combat.fighters[1].x = 494
		for f in game.combat.fighters: f.previous_x = f.x
		_step({}, {"x":-1,"buttons":8})
		for n in range(18): _step()
		_check(actor.form_active() and game.combat.fighters[0].throw_role == "victim",cid+" thrown reaction keeps form")
		await _shot(cid+"-thrown")
		for n in range(100): _step()
		if "--gallery" in OS.get_cmdline_user_args():
			await _gallery(cid)
		game.combat.fighters[0].awakening_ticks = 1
		_step()
		_check(not actor.form_active(),cid+" expires")
		game.practice_controller.reset(game.combat)
		game.view._process(0)
		_check(not actor.form_active(),cid+" reset clears appearance")
		if cid == "nezuko" and "--max-review" in OS.get_cmdline_user_args():
			await _nezuko_max_review()
	if "--motion-review" in OS.get_cmdline_user_args():
		await _nezuko_motion_review()
	game.show_practice_options()
	await _shot("practice-settings")
	game.close_help()
	game.show_title()
	game.help_return = "title"
	game.gui.clear()
	game.gui.help()
	await _shot("help")
	for cid in selected_characters:
		game.gui.clear()
		game.gui.help("moves",cid)
		await _shot(cid+"-moves")
	var report := FileAccess.open(awakening_out+"/captures.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures,"motion_trace":motion_trace},"  "))
	game.queue_free()
	await process_frame
	print("AWAKENING CAPTURE: %d checks, %d failed; %d screenshots" % [checks,failures.size(),captures.size()])
	quit(0 if failures.is_empty() else 1)

func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(awakening_out+"/"+name+".png")
	captures.append(name+".png")

func _gallery(cid: String) -> void:
	var actor = game.view.fighters[0]
	var visual = game.catalog.characters[cid]
	if visual.awakening_frames == null: return
	for clip_name in visual.awakening_frames.get_animation_names():
		var count: int = visual.awakening_frames.get_frame_count(clip_name)
		for index in [0,count/2,count-1]:
			actor.clip = clip_name
			actor.frame_index = index
			actor.texture = visual.awakening_frames.get_frame_texture(clip_name,index)
			actor.queue_redraw()
			await _shot("%s-%s-%02d" % [cid,clip_name,index])

func _nezuko_max_review() -> void:
	for facing in [1, -1]:
		for sustained in [false, true]:
			game.characters.assign(["nezuko", "nezuko"])
			game.start_match()
			var fighter = game.combat.fighters[0]
			var other = game.combat.fighters[1]
			fighter.x = 405 if facing == 1 else 555
			other.x = 555 if facing == 1 else 405
			fighter.facing = facing
			other.facing = -facing
			for item in game.combat.fighters:
				item.previous_x = item.x
				item.input.last_facing = item.facing
			game.view.camera.reset(game.combat.fighters)
			_step()
			if sustained:
				_step({"buttons": 6})
				for tick in range(40): _step()
			fighter.meter = 300
			_step()
			var motion := "236236"
			for index in range(motion.length()):
				_step(helper.relative(int(motion[index]), facing, 5 if index == motion.length() - 1 else 0))
			for tick in range(3): _step()
			var label := "nezuko-max-%s-%s" % ["left" if facing < 0 else "right", "sustained" if sustained else "ordinary"]
			var actor = game.view.fighters[0]
			_check(fighter.move != null and fighter.move.clip_id() == "awakened_combo", label + " real input starts MAX")
			_check(actor.form_active() and is_equal_approx(actor._pose_scale().x, 1.15), label + " single enlarged form")
			_check(not game.view.fighters[1].form_active(), label + " opponent remains ordinary")
			_check(game.view.super_view.cut_in_textures.get(fighter.move.id) == game.catalog.characters.nezuko.awakened_portrait, label + " cut-in uses revised portrait")
			await _shot(label + "-cut-in")
			for tick in range(35): _step()
			await _shot(label)
			for tick in range(230): _step()
			_check(fighter.move == null, label + " MAX completed")
			_check(actor.form_active() == sustained, label + " correct form after MAX")
			await _shot(label + "-finished")

# Real input through the simulation, sampled every three logic ticks for visual review.
func _prepare_nezuko_motion(facing: int) -> void:
	game.characters.assign(["nezuko", "nezuko"])
	game.start_match()
	var fighter = game.combat.fighters[0]
	fighter.x = 300 if facing > 0 else 660
	game.combat.fighters[1].x = 760 if facing > 0 else 200
	fighter.facing = facing
	game.combat.fighters[1].facing = -facing
	for item in game.combat.fighters:
		item.previous_x = item.x
		item.input.last_facing = item.facing
	game.view.camera.reset(game.combat.fighters)
	_step()
	_step({"buttons":6})
	for tick in range(42): _step()
	_check(game.view.fighters[0].form_active(), "motion review BC activation, facing %d" % facing)

func _nezuko_motion_review() -> void:
	var previous_infinite: bool = game.practice_controller.awakening_infinite
	game.practice_controller.awakening_infinite = true
	for facing in [1,-1]:
		_prepare_nezuko_motion(facing)
		await _motion_segment("idle", {}, 18)
		# Four full six-frame cycles at 20 fps, away from pushboxes and walls.
		await _motion_segment("walk", {"x":facing}, 72)
		await _motion_segment("walk_back", {"x":-facing}, 72)
		_step()
		_step({"x":facing})
		_step()
		await _motion_segment("dash_forward", {"x":facing}, 1)
		await _motion_segment("dash_forward", {}, 18)
		_step({"x":-facing})
		_step()
		await _motion_segment("dash_back", {"x":-facing}, 1)
		await _motion_segment("dash_back", {}, 18)
		await _motion_segment("crouch", {"y":1}, 18)
		await _motion_segment("stand", {}, 9)
		_step({"y":-1})
		await _motion_segment("jump", {}, 48)
		await _motion_segment("stand_light", {"buttons":1}, 1)
		await _motion_segment("stand_light", {}, 36)
		await _motion_segment("stand_heavy", {"buttons":4}, 1)
		await _motion_segment("stand_heavy", {}, 42)
		for attack in [["air_light",1],["body_air_light",2],["air_heavy",4],["body_air_heavy",8]]:
			_step({"y":-1})
			await _motion_segment("jump_to_"+attack[0], {}, 6)
			await _motion_segment(attack[0], {"buttons":attack[1]}, 1)
			await _motion_segment(attack[0], {}, 51)
		# Reset staging between skills so prior displacement cannot hit a wall.
		for skill in [["blood_kick","236",1,65],["rising_kick","623",1,80],["spinning_kick","214",2,100],["blood_burst","236236",1,135],["awakened_combo","236236",5,180]]:
			_prepare_nezuko_motion(facing)
			var fighter = game.combat.fighters[0]
			fighter.meter = 300
			_step()
			var motion: String = skill[1]
			for index in range(motion.length()):
				_step(helper.relative(int(motion[index]),facing,skill[2] if index==motion.length()-1 else 0))
			await _motion_segment(skill[0], {}, skill[3])
		var observed: Dictionary = {}
		for row in motion_trace:
			if row.facing == facing: observed[row.clip] = true
		for expected in ["idle","walk","walk_back","dash_forward","dash_back","crouch","jump","stand_light","stand_heavy","air_light","body_air_light","air_heavy","body_air_heavy","blood_kick","rising_kick","spinning_kick","blood_burst","awakened_combo"]:
			_check(observed.has(expected), "motion trace includes %s facing %d" % [expected,facing])
	game.practice_controller.awakening_infinite = previous_infinite

func _motion_segment(label: String, command: Dictionary, duration: int) -> void:
	var monotonic := true
	var seen: Dictionary = {}
	for tick in range(duration):
		var previous_x: float = game.combat.fighters[0].x
		_step(command)
		var actor = game.view.fighters[0]
		var fighter = game.combat.fighters[0]
		if label in ["walk","walk_back"]:
			monotonic = monotonic and (fighter.x-previous_x)*float(command.x)>0
			seen[actor.frame_index] = true
		if tick % 3 != 0: continue
		var number: int = motion_trace.size()
		motion_trace.append({"sample":number,"tick":video_tick,"label":label,"clip":actor.clip,"frame":actor.frame_index,"form":actor.form_active(),"scale":actor._pose_scale().x,"input":command,"x":fighter.x,"y":fighter.y,"facing":fighter.facing,"drawing_scale":actor.visual.drawing_scale()})
		await _shot("motion-%04d" % number)
	if label in ["walk","walk_back"]:
		_check(monotonic, label+" world movement stays monotonic")
		_check(seen.size()==6, label+" repeated cycle includes every pose")
