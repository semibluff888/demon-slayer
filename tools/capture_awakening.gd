extends "res://tools/capture_roster_expansion.gd"
var awakening_out: String = "res://artifacts/awakening-v2" if "--v2" in OS.get_cmdline_user_args() else "res://artifacts/awakening"
var checks: int = 0
var failures: Array[String] = []

func _check(value: bool, label: String) -> void:
	if value: checks += 1
	else: failures.append(label); printerr("FAIL: ",label)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(awakening_out)
	root.size = Vector2i(1280,720)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view,game.view.effects,game.view.hud,game.view.stage,game.view.super_view]:
		node.set_process(false)
	await process_frame
	for cid in ["tanjiro","zenitsu","nezuko","akaza"]:
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
	game.show_practice_options()
	await _shot("practice-settings")
	game.close_help()
	game.show_title()
	game.help_return = "title"
	game.gui.clear()
	game.gui.help()
	await _shot("help")
	for cid in ["tanjiro","zenitsu","nezuko","akaza"]:
		game.gui.clear()
		game.gui.help("moves",cid)
		await _shot(cid+"-moves")
	var report := FileAccess.open(awakening_out+"/captures.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures},"  "))
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
