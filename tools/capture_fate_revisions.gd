extends "res://tools/capture_roster_expansion.gd"
## Captures the real menus, input-driven combat, and continuous courtyard camera.
const FATE_OUT := "res://artifacts/fate-revisions"
var evidence: Array[Dictionary] = []

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(FATE_OUT)
	root.size = Vector2i(1280,720)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view,game.view.effects,game.view.hud,game.view.stage,game.view.super_view]:
		node.set_process(false)
	await process_frame
	if "--stage-only" in OS.get_cmdline_user_args():
		await _courtyard_video()
		game.queue_free()
		await process_frame
		print("FATE STAGE CAPTURE COMPLETE")
		quit()
		return
	await _menus()
	await _sizes()
	await _effects()
	await _pain_video()
	await _courtyard_video()
	var file := FileAccess.open(FATE_OUT + "/capture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"screenshots":captures,"combat":evidence,"method":"Godot production rendering and real held combat inputs; 30 FPS silent videos."},"  "))
	game.queue_free()
	await process_frame
	print("FATE CAPTURE COMPLETE: ",captures.size()," screenshots")
	quit()

func _save(name: String) -> void:
	await create_timer(0.4).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(FATE_OUT + "/" + name + ".png")
	captures.append(name + ".png")

func _reset_demo(first: String, second: String, facing: int = 1, close_pair: bool = true) -> void:
	game.mode = "local"
	game.stage_id = "corps_courtyard"
	game.characters.assign([first,second])
	game.start_match()
	game.combat.phase = "fight"
	var a = game.combat.fighters[0]
	var b = game.combat.fighters[1]
	a.x = 480.0
	b.x = a.x + facing * (34.0 if close_pair else 180.0)
	a.facing = facing; b.facing = -facing
	for f in game.combat.fighters:
		f.previous_x = f.x; f.input.last_facing = f.facing; f.meter = 300
	game.view.camera.reset(game.combat.fighters)
	game.view._process(0)
	game.view.hud._process(0)

func _sizes() -> void:
	for other: String in ["tanjiro","zenitsu","akaza"]:
		_reset_demo("nezuko",other,1,false)
		await _save("size-nezuko-" + other)
		if other == "tanjiro":
			game.catalog.characters.nezuko.model_scale = 1.0
			game.view.fighters[0].queue_redraw()
			await _save("size-before")
			game.catalog.characters.nezuko.model_scale = 0.85
			game.view.fighters[0].queue_redraw()

func _effects() -> void:
	for facing in [-1,1]:
		for notation: String in ["236A","236C","623A","623C","214B","214D","236236A","236236AC"]:
			_reset_demo("nezuko","akaza",facing,false)
			var digits := ""
			var buttons := 0
			for token in notation:
				if token in "123456789": digits += token
				elif token in "ABCD": buttons |= 1 << "ABCD".find(token)
			var captured := false
			for tick in range(180):
				var command := Combat.neutral()
				if tick >= 8 and tick < 8 + digits.length():
					command = helper.relative(int(digits[tick-8]),facing,buttons if tick == 7 + digits.length() else 0)
				_step(command)
				var a = game.combat.fighters[0]
				if not captured and a.move != null and a.move.segment(a.move_frame) >= 0 and a.move.segment_progress(a.move_frame) >= 0.4:
					var name := "effect-%s-%s" % [notation,"right" if facing>0 else "left"]
					await _save(name)
					if notation == "236C" and facing == 1:
						var profile = a.move.presentation
						profile.texture_flip_h = false
						game.view.effects.queue_redraw(); game.view.effects.body_layer.queue_redraw()
						await _save("effect-before")
						profile.texture_flip_h = true
					captured = true
			if not captured: push_error("No effect captured: " + notation)
			print("FATE EFFECT ",notation," / ",facing)

func _pain_video() -> void:
	frames = 0
	video_folder = FATE_OUT + "/pain-video"
	DirAccess.make_dir_recursive_absolute(video_folder)
	for pair in [["tanjiro","nezuko"],["zenitsu","akaza"]]:
		for facing in [-1,1]:
			for kind: String in ["super","max"]:
				var attacker: String = "akaza" if kind == "max" else pair[0]
				_reset_demo(attacker,pair[1],facing)
				var hits := 0
				var poses: Array[int] = []
				for tick in range(180):
					var command := Combat.neutral()
					if tick >= 12 and tick < 18:
						command = helper.relative(int("236236"[tick-12]),facing,(5 if kind=="max" else 1) if tick==17 else 0)
					_step(command)
					var victim = game.combat.fighters[1]
					var actor = game.view.fighters[1]
					for event: Dictionary in game.combat.events:
						if event.type == "hit":
							hits += 1
							if victim.state == "hit":
								poses.append(actor.frame_index)
								if hits == 2:
									await _save("pain-%s-%s-%s" % [pair[1],kind,"right" if facing>0 else "left"])
					if tick % 2 == 0: await _frame()
				evidence.append({"attacker":attacker,"victim":pair[1],"move":kind,"facing":facing,"hits":hits,"impact_frames":poses})
				print("FATE PAIN ",pair[1]," ",kind," hits=",hits," poses=",poses)

func _courtyard_video() -> void:
	frames = 0
	video_folder = FATE_OUT + "/courtyard-video"
	DirAccess.make_dir_recursive_absolute(video_folder)
	_reset_demo("nezuko","akaza",1,false)
	for name in ["left","center","right"]:
		var center: float = {"left":Combat.LEFT+50,"center":(Combat.LEFT + Combat.RIGHT) * 0.5,"right":Combat.RIGHT-50}[name]
		game.view.camera.center_x = center
		game.view.stage.sync_camera()
		# Actual fighter locations follow the camera for edge/ground reference.
		for f in game.combat.fighters:
			f.x = center + (-40 if f.slot==0 else 40)
			f.previous_x = f.x
		game.view._process(0)
		await _save("courtyard-" + name)
	_reset_demo("nezuko","akaza",1,false)
	game.view.fighters[0].visible = false
	game.view.fighters[1].visible = false
	game.view.hud.visible = false
	game.view.shadow_layer.visible = false
	game.gui.visible = false
	var scroll_edges: Array[float] = []
	for edge in [Combat.LEFT, Combat.RIGHT]:
		for f in game.combat.fighters: f.x = edge
		game.view.camera.reset(game.combat.fighters)
		scroll_edges.append(game.view.camera.center_x)
	for frame in range(180):
		game.view.camera.center_x = lerpf(scroll_edges[0],scroll_edges[1],frame/179.0)
		game.view.stage.sync_camera()
		game.view.stage._process(1.0/30)
		await _frame()
