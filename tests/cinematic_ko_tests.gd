extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
var game: Node
var passed := 0
var failures: Array[String] = []
class HeldRouter extends "res://scripts/input_router.gd":
	func sample(_device: String) -> Dictionary:
		return {"x":1, "y":-1, "buttons":15}
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label); printerr("FAIL: ", label)
func trigger(cid: String, kind: String, slot: int, facing: int, hp: int, awakened: bool = false) -> void:
	game.mode = "local"
	game.characters.assign([cid, "akaza"] if slot == 0 else ["tanjiro", cid])
	game.start_match()
	game.combat.phase = "fight"
	var a = game.combat.fighters[slot]
	var d = game.combat.fighters[1-slot]
	a.x = 480; d.x = a.x + facing * 35; a.facing = facing; d.facing = -facing
	a.meter = 300; d.hp = hp
	if awakened:
		a.awakening_ticks = 500; a.awakening_duration = 600
	for f in game.combat.fighters:
		f.previous_x = f.x; f.input.last_facing = f.facing
	game.combat.cinematic_moves = game.view.cinematic.available_moves()
	game.combat._begin_move(a, game.combat.definition(a).motions[kind])
	for n in range(130):
		game.combat.step([Combat.neutral(), Combat.neutral()])
		if not game.combat.cinematic.is_empty(): break
	check(not game.combat.cinematic.is_empty(), "capture " + cid + kind)
	game.view.cinematic.begin()
	game.view.cinematic.movie.stop()
	game.view.cinematic.soundtrack.stop()
func seed_frame() -> void:
	var frame := Image.create(8, 8, false, Image.FORMAT_RGB8)
	frame.fill(Color("844848"))
	game.view.cinematic.freeze_texture = ImageTexture.create_from_image(frame)
func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	game = Main.instantiate()
	game.settings.path = "res://artifacts/cinematic-ko-settings.cfg"
	root.add_child(game)
	game.set_physics_process(false)
	game.view.set_process(false)
	game.view.cinematic.set_process(false)
	game.sound.muted = true
	game.router = HeldRouter.new()
	for cid in ["tanjiro", "nezuko", "zenitsu", "akaza"]:
		for kind in ["super", "max"]:
			for slot in [0, 1]:
				for facing in [-1, 1]:
					for hp in [1, 160]:
						trigger(cid, kind, slot, facing, hp, cid == "nezuko")
						var m = game.combat
						var c = game.view.cinematic
						var a = m.fighters[slot]
						var d = m.fighters[1-slot]
						var label := "%s %s P%d facing%d hp%d" % [cid, kind, slot+1, facing, hp]
						check(m.phase == "fight" and m.wins == [0,0], label + " no early scoring")
						seed_frame()
						c._video_finished()
						game.view._process(0.0)
						check(d.hp == 0 and c.phase == "ko_freeze" and c.is_video_visible(), label + " final damage before freeze")
						check(m.events.filter(func(e): return e.type == "ko_announce").size() == 1, label + " one KO cue")
						m.announce_cinematic_ko()
						c._video_finished()
						check(m.events.filter(func(e): return e.type == "ko_announce").size() == 1, label + " repeated callbacks cannot repeat cue")
						check(not game.view.stage.visible and game.view.hud.cinematic_mode and not game.gui.visible, label + " freeze visibility")
						var snapshot: Dictionary = m.snapshot()
						for n in range(10): game._physics_process(1.0/60)
						check(m.snapshot() == snapshot, label + " held input cannot advance capture")
						game.set_paused(true); c._process(0.4)
						check(c.ko_time == 0 and game.gui.visible, label + " paused freeze")
						game.set_paused(false); c._process(0.4)
						check(is_equal_approx(c.ko_time, 0.4) and not game.gui.visible, label + " resumes freeze")
						c._process(0.34)
						check(c.tail_prepared and game.view.stage.visible and c.tail_time == 0, label + " map prepared under crossfade")
						check(c.ko_overlay.modulate.a > 0 and c.ko_overlay.modulate.a < 1, label + " overlay crossfade")
						c._process(0.07)
						check(c.phase == "tail" and c.freeze_texture == null and not c.ko_overlay.visible, label + " freeze released before tail")
						c._process(0.66)
						var x: float = a.x
						var end_texture: Texture2D = game.view.fighters[slot].texture
						m.release_cinematic_actor()
						for n in range(10): game._physics_process(1.0/60)
						check(c.blocks_combat() and a.x == x and a.move == null and a.grounded, label + " no early KO unlock")
						game.view._process(0.0)
						check(not game.view.fighters[slot].cinematic_pose.is_empty() and end_texture != null, label + " held recovery drawing")
						game.set_paused(true); c._process(0.5)
						check(is_equal_approx(c.tail_time, 0.66), label + " paused landing")
						game.set_paused(false); c._process(0.50)
						check(not c.active and m.cinematic.is_empty() and m.phase == "round_end", label + " completes landing")
						check(m.outro_ticks == m.victory_at and m.round_cue().text == "P%d WINS" % (slot+1), label + " immediate victory")
						check(m.wins[slot] == 1 and m.wins[1-slot] == 0, label + " score once")
						check(game.view.fighters[slot].clip == "round_victory" and game.view.fighters[slot].frame_index == 0, label + " first victory frame with no idle")
						check(game.view.fighters[1-slot].texture != null and game.view.fighters[1-slot].frame_index == 11, label + " defeated stays down")
						if cid == "nezuko":
							check(a.awakening_ticks == 0 and game.view.fighters[slot].form_active(), label + " visual awakening retained only for victory")
							var visual = game.view.fighters[slot].visual
							check(game.view.fighters[slot].texture == visual.awakening_frames.get_frame_texture("idle", 0), label + " victory uses actual transformed artwork")
						var dx: float = d.x
						for n in range(30):
							game._physics_process(1.0/60)
							check(not m.events.any(func(e): return e.type == "ko_announce"), label + " no second announce")
						check(a.x == x and d.x == dx and d.grounded and a.move == null, label + " result input locked and no relaunch")
						m.finish_cinematic()
						check(m.wins[slot] == 1, label + " completion idempotent")
						for n in range(95): game._physics_process(1.0/60)
						check(m.phase == "intro" and m.cinematic_victory_form_slot == -1 and not game.view.fighters[slot].form_active(), label + " next round resets form")
	# The profile swap must leave real move damage and meter costs untouched.
	for awakened in [false, true]:
		for kind in ["super", "max"]:
			trigger("nezuko", kind, 0, 1, 1000, awakened)
			var c = game.view.cinematic
			var m = game.combat
			var expected := "nezuko_max" if awakened or kind == "max" else "nezuko_super"
			check(c.profile_id == expected and c.move_id == "nezuko_" + kind, "separate presentation identity")
			check(c.movie.stream == c.streams[expected] and c.soundtrack.stream == c.audio_streams[expected], "matching video and soundtrack")
			check(c.profile.duration == c.profiles[expected].duration, "matching alternate duration")
			c._video_finished()
			var attack = m.moves["nezuko_" + kind]
			var damage: int = int(attack.damage * 110 / 100) if awakened and kind == "super" else attack.damage
			var cost: int = 100 if awakened else attack.meter_cost
			check(m.fighters[1].hp == 1000 - damage and m.fighters[0].meter == 300 - cost, "profile uses actual move damage and one-stock awakening cost")
			check((m.fighters[0].awakening_ticks > 0) == (awakened and kind == "super"), "only enhanced ordinary super retains mode")
			c._process(0.66)
			check(not c.blocks_combat() and c.phase == "tail", "nonlethal release unchanged")
	# A consumed awakening remains visual through recovery for every character.
	for cid in ["tanjiro", "zenitsu", "nezuko", "akaza"]:
		trigger(cid, "max", 0, 1, 1000, true)
		var c = game.view.cinematic
		check(game.combat.fighters[0].awakening_ticks == 0, cid + " cinematic MAX already consumed mode")
		c._video_finished(); c._process(0.2)
		check(game.view.fighters[0].form_active(), cid + " cinematic recovery preserves launch form")
		c._process(0.5)
		check(not game.view.fighters[0].form_active(), cid + " playable actor returns to ordinary form")
		c._process(0.6)
	for cid in ["tanjiro", "zenitsu", "nezuko", "akaza"]:
		trigger(cid, "super", 0, 1, 1000, true)
		var c = game.view.cinematic
		var a = game.combat.fighters[0]
		var time: int = a.awakening_ticks
		c._video_finished(); c._process(0.2)
		check(a.awakening_ticks == time and a.meter == 200, cid + " video freezes enhanced super mode without refund")
		check(game.view.fighters[0].form_active(), cid + " enhanced super tail keeps form")
		c._process(1.0)
		check(a.awakening_ticks == time and game.view.fighters[0].form_active(), cid + " enhanced super handoff retains remaining mode")
	# Decoder fallback, pause/settings, cancellation and practice never strand locks.
	trigger("nezuko", "super", 0, 1, 1, true)
	game.view.cinematic._process(3.0)
	game.view.cinematic._process(3.0)
	check(game.view.cinematic.phase == "tail" and game.view.cinematic.map_ko, "stalled decoder announces on map")
	game.view.cinematic._process(1.2)
	check(game.combat.round_cue().text == "P1 WINS", "fallback settles directly")
	trigger("nezuko", "super", 0, 1, 1, true)
	seed_frame(); game.view.cinematic._video_finished()
	game.view.cinematic._process(0.2)
	game.show_settings()
	game.settings.muted = true
	game.settings.cinematic_enabled = false
	game.view.cinematic._process(0.4)
	check(is_equal_approx(game.view.cinematic.ko_time, 0.2) and game.view.cinematic.phase == "ko_freeze", "settings pauses without cancelling current KO")
	check(game.view.cinematic.movie.volume == 0 and game.gui.visible, "settings mute applied and menu accessible")
	game.close_settings(); game.set_paused(false)
	game.view.cinematic._process(0.61)
	check(game.view.cinematic.phase == "tail", "settings toggle only affects next cinematic")
	game.settings.cinematic_enabled = true
	trigger("nezuko", "super", 0, 1, 1, true)
	game.view.cinematic.streams.erase("nezuko_max")
	check(not game.view.cinematic.available_moves().has("nezuko_super"), "missing alternate cannot substitute normal form movie")
	game.view.cinematic.active = false
	game.view.cinematic.begin()
	check(game.view.cinematic.phase == "tail" and game.view.cinematic.map_ko, "missing selected stream falls back to map")
	game.view.cinematic._process(1.2)
	check(game.combat.round_cue().text == "P1 WINS", "missing stream still settles once")
	for destination in ["title", "setup", "restart", "practice"]:
		trigger("nezuko", "super", 0, 1, 1, true)
		seed_frame(); game.view.cinematic._video_finished()
		match destination:
			"title": game.show_title()
			"setup": game.show_setup()
			"restart": game.start_match()
			"practice": game.mode = "practice"; game.reset_practice()
		check(not game.view.cinematic.active and game.view.cinematic.freeze_texture == null and game.combat.cinematic.is_empty(), "cancel clears " + destination)
	trigger("nezuko", "super", 0, 1, 1, true)
	game.mode = "practice"; game.combat.practice = true
	seed_frame(); game.view.cinematic._video_finished()
	check(game.view.cinematic.phase == "tail" and not game.view.cinematic.map_ko, "practice does not announce KO")
	game.view.cinematic._process(1.2)
	check(game.combat.phase == "fight" and game.combat.wins == [0,0], "practice does not score round")
	game.sound.reset_audio(); game.queue_free(); await process_frame
	print("CINEMATIC KO: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)
