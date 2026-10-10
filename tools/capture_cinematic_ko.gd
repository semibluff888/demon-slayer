extends SceneTree
## Real Theora playback and rendered KO handoff. Supports Godot --write-movie.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
var game: Node
var passed := 0
var failures: Array[String] = []
var out := "res://artifacts/cinematics-ko"
var matrix := false
var character_filter := ""
var fps := 60
var cases: Array[Dictionary] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label); printerr("FAIL: ", label)
func pixel_hash(texture: Texture2D) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(texture.get_image().get_data())
	return digest.finish().hex_encode()
func shot(label: String) -> void:
	root.get_texture().get_image().save_png(out + "/" + label + ".png")
func trigger(cid: String, kind: String, slot: int, facing: int) -> void:
	game.characters.assign([cid, "akaza"] if slot == 0 else ["tanjiro", cid])
	game.start_match()
	game.combat.phase = "fight"
	var a = game.combat.fighters[slot]
	var d = game.combat.fighters[1-slot]
	a.x = 480; d.x = a.x + facing * 35; a.facing = facing; d.facing = -facing
	a.meter = 300; d.hp = 160
	if cid == "nezuko": a.awakening_ticks = 500; a.awakening_duration = 600
	for f in game.combat.fighters:
		f.previous_x = f.x; f.input.last_facing = f.facing
	game.combat.cinematic_moves = game.view.cinematic.available_moves()
	game.combat._begin_move(a, game.combat.definition(a).motions[kind])
	for n in range(130):
		game.combat.step([Combat.neutral(), Combat.neutral()])
		if not game.combat.cinematic.is_empty(): break
	check(not game.combat.cinematic.is_empty(), cid + kind + " capture")
	game.view.cinematic.begin()
func play_case(cid: String, kind: String, slot: int, facing: int, save_frames: bool) -> void:
	trigger(cid, kind, slot, facing)
	var c = game.view.cinematic
	var label := "%s_%s_p%d_f%d" % [cid, kind, slot+1, facing]
	var seen := {}
	var phases: Array[String] = []
	var freeze_started := -1.0
	var tail_started := -1.0
	var result_started := -1.0
	var clock := 0.0
	var limit := float(c.profile.duration) + 9.0
	var freeze_hash := ""
	var ko_cues := 0
	var frozen_x := 0.0
	var result_steps := 0.0
	while clock < limit:
		await process_frame
		await RenderingServer.frame_post_draw
		var delta := game.get_process_delta_time()
		clock += delta
		if phases.is_empty() or phases.back() != c.phase:
			phases.append(c.phase)
			if c.phase == "ko_freeze":
				freeze_started = clock
				check(c.freeze_texture != null, label + " decoded final texture exists")
				if c.freeze_texture != null:
					freeze_hash = pixel_hash(c.freeze_texture)
				ko_cues = game.combat.events.filter(func(e): return e.type == "ko_announce").size()
				check(not c.soundtrack.playing and not c.movie.is_playing(), label + " media stopped at freeze")
			if c.phase == "tail":
				tail_started = clock
				frozen_x = game.combat.fighters[slot].x
				check(c.tail_prepared and not c.ko_overlay.visible and c.freeze_texture == null, label + " tail cleans snapshot")
		if c.phase == "video" and c.elapsed > 0.5 and not seen.has("video"):
			seen.video = true
			check(c.movie.stream_position > 0.1, label + " decoder advancing")
			if save_frames: shot(label + "_video")
		if c.phase == "ko_freeze":
			if c.ko_time > 0.3 and not seen.has("ko"):
				seen.ko = true
				check(pixel_hash(c.freeze_texture) == freeze_hash, label + " immutable frozen image")
				check(game.view.hud.cinematic_mode and not game.gui.visible, label + " cinematic HUD in freeze")
				if save_frames: shot(label + "_ko")
			if c.ko_time > 0.73 and not seen.has("transition"):
				seen.transition = true
				check(c.tail_prepared and game.view.stage.visible and game.view.fighters[slot].texture != null, label + " rendered stage behind fade")
				if save_frames: shot(label + "_transition")
		if c.phase == "tail" and c.tail_time > 0.72 and not seen.has("tail"):
			seen.tail = true
			check(c.blocks_combat() and game.combat.fighters[slot].x == frozen_x, label + " locked beyond actor recovery")
			if save_frames: shot(label + "_tail")
		if not c.active:
			if result_started < 0:
				result_started = clock
				check(game.combat.phase == "round_end" and game.combat.outro_ticks == game.combat.victory_at, label + " direct result entry")
				check(game.view.fighters[slot].clip == "round_victory" and game.view.fighters[slot].frame_index == 0, label + " no idle or blank result frame")
				check(game.view.fighters[1-slot].frame_index == 11, label + " victim remains settled")
				if cid == "nezuko": check(game.view.fighters[slot].form_active(), label + " awakened victory")
				if save_frames: shot(label + "_victory_start")
			result_steps += delta * 60.0
			while result_steps >= 1.0:
				result_steps -= 1.0
				game.combat.step([{"x":1,"y":-1,"buttons":15}, {"x":-1,"y":-1,"buttons":15}])
				check(not game.combat.events.any(func(e): return e.type == "ko_announce"), label + " no repeated cue")
			if clock - result_started > 1.75:
				if save_frames: shot(label + "_victory_end")
				break
	check(seen.has("ko") and seen.has("transition") and seen.has("tail"), label + " all rendered phases reached")
	check(ko_cues == 1, label + " exactly one initial announcement")
	check(absf(tail_started - freeze_started - 0.8) < 2.1/fps, label + " 0.8 second freeze")
	check(absf(result_started - tail_started - 1.15) < 2.1/fps, label + " 1.15 second tail")
	cases.append({"case":label,"phases":phases,"freeze_seconds":tail_started-freeze_started,"tail_seconds":result_started-tail_started,"freeze_sha256":freeze_hash})
	print("RENDERED ", label, " freeze=", tail_started-freeze_started, " tail=", result_started-tail_started)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	matrix = args.has("--matrix")
	for arg: String in args:
		if arg.begins_with("--fps="): fps = int(arg.get_slice("=",1))
		if arg.begins_with("--character="): character_filter = arg.get_slice("=",1)
	out += "/%d" % fps
	if matrix: out += "/matrix"
	if not character_filter.is_empty(): out += "/" + character_filter
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280,720)
	game = Main.instantiate()
	game.settings.path = out + "/settings.cfg"
	root.add_child(game)
	game.set_physics_process(false)
	game.mode = "local"
	game.settings.muted = false
	game.settings.volume = 0.75
	game.sound.set_levels(game.settings.muted, game.settings.volume)
	await process_frame
	if matrix:
		for cid in ["tanjiro", "nezuko", "zenitsu", "akaza"]:
			if not character_filter.is_empty() and cid != character_filter: continue
			for kind in ["super", "max"]:
				for slot in [0,1]:
					for facing in [-1,1]:
						await play_case(cid,kind,slot,facing,true)
	else:
		await play_case("nezuko" if character_filter.is_empty() else character_filter,"super",0,1,true)
	check(cases.size() == ((32 if character_filter.is_empty() else 8) if matrix else 1), "all capture cases completed")
	var report := FileAccess.open(out + "/report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"fps":fps,"cases":cases,"passed":passed,"failures":failures}, "  "))
	report.close()
	game.sound.reset_audio(); game.queue_free(); await process_frame
	print("CINEMATIC KO CAPTURE: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)
