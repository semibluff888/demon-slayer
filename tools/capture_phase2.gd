extends SceneTree
## Real OpenGL frames, real held commands, 60Hz model / 30fps recording.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Support = preload("res://tests/combat_test_support.gd")
var game: Node2D
var directory: String
var video_frame := 0
var helper := Support.new()
var cues: Array[Dictionary] = []
var special := false
var audio_events: Array[Dictionary] = []
var global_tick := 0
var audio_pauses: Array[Dictionary] = []

func _initialize() -> void:
	special = "--specials" in OS.get_cmdline_user_args()
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280,720)
	directory = "res://artifacts/phase2/" + ("specials" if special else "basics")
	DirAccess.make_dir_recursive_absolute(directory)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view, game.view.effects, game.view.hud, game.view.stage, game.view.super_view]:
		node.set_process(false)
	DirAccess.make_dir_recursive_absolute(directory+"/audio")
	for kind: String in game.sound.streams:
		game.sound.streams[kind].save_to_wav(directory+"/audio/"+kind+".wav")
	var labels := Label.new()
	labels.position = Vector2(430,200)
	labels.add_theme_font_override("font",game.catalog.body_font)
	labels.add_theme_font_size_override("font_size",18)
	labels.z_index = 50
	game.add_child(labels)
	for cid in ["tanjiro", "zenitsu"]:
		var cases: Array = ["5B","5D","2B","2D","jB","jD","AB","4AB","6D","4D","tech","cancel","pause"]
		if special:
			cases = ["236A","236C","623A","623C","214B","214D","236236A","236236AC","block","whiff","empty","pause"]
		for n in range(cases.size()):
			var scenario: String = cases[n]
			var facing := -1 if n % 2 else 1
			var corner := n % 3 == 1
			var mirror := n % 4 == 2
			game.mode = "practice"
			game.characters.assign([cid, cid if mirror else ("zenitsu" if cid == "tanjiro" else "tanjiro")])
			game.start_match()
			var model = game.combat
			var a = model.fighters[0]
			var b = model.fighters[1]
			a.x = (850 if facing > 0 else 110) if corner else 480
			b.x = a.x + facing * (150 if scenario == "whiff" else 36)
			if special and scenario.begins_with("236") and scenario.length() < 6:
				b.x = a.x + facing * 100
			a.facing = facing
			b.facing = -facing
			a.input.last_facing = facing
			b.input.last_facing = -facing
			a.meter = 0 if scenario == "empty" else 300
			game.view.reset_effects()
			var notation := scenario
			if scenario == "tech": notation = "6D"
			if scenario == "cancel": notation = "5B"
			if scenario == "pause": notation = "236236A" if special else "5D"
			if scenario == "block": notation = "214D"
			if scenario == "whiff": notation = "5D"
			if scenario == "empty": notation = "236236AC"
			var motion := ""
			var mask := 0
			for token in notation:
				if token in "123456789": motion += token
				if token in "ABCD": mask |= 1 << "ABCD".find(token)
			if motion.is_empty(): motion = "5"
			labels.text = "%s / %s / %s%s" % [game.catalog.characters[cid].display_name, scenario,
				"朝左" if facing < 0 else "朝右", " · 版边" if corner else " · 中场"]
			var cue := {"character":cid,"scenario":scenario,"facing":facing,"corner":corner,"mirror":mirror,"start_frame":video_frame,"hits":[],"phases":[]}
			var saved := {}
			var sent_cancel := false
			var duration := 156 if special else 96
			if scenario == "pause": audio_pauses.append({"start_tick":global_tick+22,"end_tick":global_tick+34})
			for tick in range(duration):
				var held := Combat.neutral()
				var other := Combat.neutral()
				var begin := 29 if notation.begins_with("j") else 12
				if notation.begins_with("j") and tick == 6: held.y = -1
				if tick >= begin and tick < begin + motion.length():
					held = helper.relative(int(motion[tick-begin]), facing, mask if tick == begin+motion.length()-1 else 0)
				elif notation.begins_with("2") and motion.length() == 1:
					held.y = 1
				if scenario == "tech" and not model.throw_link.is_empty() and model.throw_link.frame == 2:
					other.buttons = 8
				if scenario == "cancel" and a.confirmed and not sent_cancel and model.hitstop == 0:
					held.buttons = 4
					sent_cancel = true
				if scenario == "block": other.x = facing
				game.view.paused = scenario == "pause" and tick >= 22 and tick < 34
				if not game.view.paused:
					model.step([held,other])
					game.practice_controller.after_step(model)
					game.view.consume(model.events)
					for sound_cue: Dictionary in game.sound.cues(model.events,model):
						audio_events.append({"tick":global_tick,"kind":sound_cue.kind,"gain":sound_cue.gain})
					for event in model.events:
						if event.type in ["hit","block","throw","throw_tech","meter_empty"]:
							cue.hits.append({"tick":tick,"type":event.type,"segment":event.get("segment",-1)})
				game.view._process(1.0/60)
				game.view.effects._process(1.0/60)
				game.view.hud._process(1.0/60)
				game.view.super_view._process(1.0/60)
				game.view.stage._process(1.0/60)
				await process_frame
				await RenderingServer.frame_post_draw
				var phase := ""
				if a.move != null:
					phase = "startup" if a.move_frame < a.move.startup else ("active" if a.move_frame < a.move.startup+a.move.active else "recovery")
				elif a.roll_frame >= 0: phase = "roll" if a.roll_frame < 18 else "recovery"
				elif not a.throw_role.is_empty(): phase = "grab" if a.throw_frame < 7 else ("throw" if a.throw_frame < 20 else "slam")
				elif a.reaction == "throw_tech": phase = "tech"
				var render: Image
				if tick % 2 == 0 or (not phase.is_empty() and not saved.has(phase)):
					render = root.get_texture().get_image()
				if tick % 2 == 0:
					render.save_jpg(directory+"/frame-%05d.jpg" % video_frame,0.90)
					video_frame += 1
				if not phase.is_empty() and not saved.has(phase):
					saved[phase] = true
					render.save_png(directory+"/%s-%s-%s.png" % [cid,scenario,phase])
					cue.phases.append({"phase":phase,"tick":tick,"clip":game.view.fighters[0].clip,"frame":game.view.fighters[0].frame_index})
				global_tick += 1
			cues.append(cue)
			print("CAPTURED ",cid," ",scenario)
	var file := FileAccess.open(directory+"/cues.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"fps":30,"resolution":[1280,720],"frames":video_frame,"method":"Godot OpenGL; simulated held commands via Combat.step; 60Hz model","cues":cues,"audio_events":audio_events,"audio_pauses":audio_pauses,"audio_method":"Godot-generated PCM mixed offline from these exact 60Hz event timestamps, preserving audio pause intervals"},"  "))
	game.queue_free()
	await process_frame
	print("PHASE TWO CAPTURE COMPLETE ", video_frame)
	quit()
