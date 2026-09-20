extends SceneTree
## Real rendering at exact arena boundaries. Held commands, no forced move state.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Support = preload("res://tests/combat_test_support.gd")
var game: Node2D
var helper := Support.new()
var captures: Array[Dictionary] = []
var failures: Array[String] = []
const DIRECTORY := "res://artifacts/phase2/matrix"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view, game.view.effects, game.view.hud, game.view.stage]:
		node.set_process(false)
	for width in [960,1280,1920]:
		root.size = Vector2i(width,width*9/16)
		for cid in ["tanjiro","zenitsu"]:
			for facing in [-1,1]:
				for notation in ["5D","4AB","6D","236236A","236236AC"]:
					await _case(width,cid,facing,notation)
	var file := FileAccess.open(DIRECTORY+"/captures.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"method":"Actual Godot OpenGL; held commands; exact LEFT/RIGHT boundary; same-character duels","captures":captures,"failures":failures},"  "))
	game.queue_free()
	await process_frame
	for failure in failures: printerr("FAIL: ",failure)
	print("PHASE TWO MATRIX: %d screenshots, %d failed" % [captures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

func _case(width: int, cid: String, facing: int, notation: String) -> void:
	game.mode = "practice"
	game.characters.assign([cid,cid])
	game.start_match()
	var model = game.combat
	var a = model.fighters[0]
	var b = model.fighters[1]
	b.x = Combat.RIGHT if facing > 0 else Combat.LEFT
	a.x = b.x-facing*34
	a.facing = facing
	b.facing = -facing
	for f in model.fighters:
		f.previous_x = f.x
		f.input.last_facing = f.facing
	a.meter = 300
	game.view.camera.reset(model.fighters)
	var motion := ""
	var buttons := 0
	for token in notation:
		if token in "123456789": motion += token
		if token in "ABCD": buttons |= 1 << "ABCD".find(token)
	var saved := {}
	for tick in range(170):
		var held := Combat.neutral()
		if tick >= 6 and tick < 6+motion.length():
			held = helper.relative(int(motion[tick-6]),facing,buttons if tick==5+motion.length() else 0)
		model.step([held,Combat.neutral()])
		game.practice_controller.after_step(model)
		game.view.consume(model.events)
		game.view._process(1.0/60)
		game.view.effects._process(1.0/60)
		game.view.hud._process(1.0/60)
		game.view.stage._process(1.0/60)
		var phase := ""
		if a.move != null:
			if a.move_frame < a.move.startup: phase = "startup"
			elif a.move_frame >= a.move.startup+a.move.active: phase = "recovery"
			elif a.move.segment_progress(a.move_frame)>=0.5: phase = "active"
		elif a.roll_frame >= 0:
			phase = "tuck" if a.roll_frame >= 6 and a.roll_frame < 18 else ("recovery" if a.roll_frame>=20 else "startup")
		elif not a.throw_role.is_empty():
			phase = "grab" if a.throw_frame<7 else ("slam" if a.throw_frame>=20 else "throw")
		if phase.is_empty() or saved.has(phase): continue
		saved[phase] = true
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var name := "%d-%s-%s-%s-%s.png" % [width,cid,"left" if facing<0 else "right",notation,phase]
		if image.get_size()!=root.size or image.save_png(DIRECTORY+"/"+name)!=OK:
			failures.append(name+" capture failed")
		for f in model.fighters:
			var feet: Vector2 = game.view.camera.point(Vector2(f.x,f.y))-game.view.camera.shake
			if feet.x<83.99 or feet.x>1196.01: failures.append(name+" root outside safe viewport")
		captures.append({"path":name,"width":width,"character":cid,"facing":facing,"notation":notation,"phase":phase,"tick":tick,"clip":game.view.fighters[0].clip,"drawing":game.view.fighters[0].frame_index,"attacker_x":a.x,"defender_x":b.x,"boundary":Combat.RIGHT if facing>0 else Combat.LEFT})
	if saved.size()<3: failures.append("Missing three stages: "+cid+notation+str(facing))
	print("MATRIX ",width," ",cid," ",facing," ",notation)
