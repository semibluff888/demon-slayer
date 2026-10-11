extends SceneTree
## Captures the redesigned menus, battle HUD states, callouts and effects for
## visual review: godot --path . --script res://tools/capture_ui_redesign.gd -- [--only=hud|menu|fx] [--hd]
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Support = preload("res://tests/combat_test_support.gd")
const OUT := "res://artifacts/ui-redesign"
var game: Node2D
var helper := Support.new()
var only: String = ""
var suffix: String = ""
var count: int = 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.get_slice("=", 1)
	if "--hd" in OS.get_cmdline_user_args():
		suffix = "-1080"
	_run.call_deferred()

func shot(id: String, settle: float = 0.35) -> void:
	await create_timer(settle).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s%s.png" % [OUT, id, suffix])
	count += 1

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1920, 1080) if suffix == "-1080" else Vector2i(1280, 720)
	game = Main.instantiate()
	game.settings.path = OUT + "/capture-settings.cfg"
	game.settings.cinematic_enabled = false
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	await process_frame
	if only in ["", "menu"]:
		await _menus()
	if only in ["", "hud"]:
		await _hud()
	if only in ["", "fx"]:
		await _effects()
	print("UI REDESIGN CAPTURE: %d screenshots" % count)
	game.queue_free()
	await process_frame
	quit(0)

func _menus() -> void:
	game.show_title()
	await shot("menu-01-title", 0.6)
	game.choose_mode("cpu")
	await shot("menu-02-select")
	game.selection.confirm(0)
	await shot("menu-03-select-ready")
	game.selection.confirm(1)
	await shot("menu-04-stage")
	game.mode = "local"
	game.show_setup()
	game.select_character(0, "nezuko")
	game.select_character(1, "akaza")
	await shot("menu-05-select-local")
	game.start_match()
	game.set_paused(true)
	await shot("menu-06-pause")
	game.show_help()
	await shot("menu-07-help-basics")
	game.gui._help_page("moves")
	await shot("menu-08-help-moves")
	game.gui._help_page("normals")
	await shot("menu-09-help-normals")
	game.close_help()
	game.show_settings()
	await shot("menu-10-settings")
	game.close_settings()
	game.choose_mode("practice")
	game.start_match()
	game.show_practice_options()
	await shot("menu-11-practice-options")
	game.set_paused(false)
	game.mode = "cpu"
	game.start_match()
	game.combat.phase = "match_end"
	game.combat.match_winner = 0
	game.combat.wins.assign([2, 1])
	game.show_result()
	await shot("menu-12-result", 1.2)

func _fight(p1: String, p2: String, mode: String = "cpu") -> void:
	game.mode = mode
	game.characters.assign([p1, p2])
	game.start_match()
	game.combat.phase = "fight"
	game.combat.go_frames = 0
	game.combat.fighters[0].x = 400
	game.combat.fighters[1].x = 560
	game.view.camera.reset(game.combat.fighters)

func _hud() -> void:
	_fight("tanjiro", "akaza")
	await shot("hud-01-neutral")
	var model = game.combat
	model.fighters[0].hp = 640
	model.fighters[1].hp = 180
	model.wins.assign([1, 0])
	model.fighters[0].meter = 175
	model.fighters[1].meter = 300
	model.remaining = 8 * 60
	model.fighters[0].combo = 12
	model.fighters[0].combo_damage = 495
	model.fighters[0].combo_display = 100
	game.view.hud.trailing[1] = 420
	await shot("hud-02-pressure")
	_fight("zenitsu", "nezuko")
	model = game.combat
	model.fighters[0].meter = 300
	helper.events.clear()
	model.fighters[0].awakening_ticks = 420
	model.fighters[0].awakening_duration = 600
	game.view.hud.consume([{"type":"awakening_start", "attacker":0}])
	model.fighters[1].combo = 23
	model.fighters[1].combo_damage = 812
	model.fighters[1].combo_display = 100
	game.view.hud.consume([{"type":"swing", "attacker":1, "move":model.definition(model.fighters[1]).motions["236A"].id}])
	await shot("hud-03-awakening", 0.2)
	for id in ["ROUND 1", "READY", "GO!", "K.O.", "P1 WINS", "TIME UP", "DRAW", "DOUBLE K.O."]:
		_fight("tanjiro", "zenitsu")
		await process_frame
		game.view.hud._process(0.0)
		game.view.hud.set_process(false)
		var cue := {"text": id, "age": 16, "duration": 60}
		if id == "P1 WINS":
			cue.subtitle = "灶门炭治郎"
		game.view.hud.round_banner.cue = cue
		await shot("hud-banner-" + id.replace(" ", "_").replace(".", "").replace("!", ""), 0.2)
		game.view.hud.set_process(true)
	_fight("tanjiro", "zenitsu", "practice")
	game.view.hud.practice_details = true
	for command in [{"y": 1}, {"x": 1, "y": 1}, {"x": 1}, {"x": 1, "buttons": 1}, {}, {"x": -1}, {"buttons": 4}, {}]:
		game.combat.step([command, {}])
	await shot("hud-04-practice")
	_fight("tanjiro", "zenitsu")
	model = game.combat
	model.fighters[0].meter = 300
	helper.events.clear()
	helper.input(model, "236236AC")
	game.view.consume(helper.events)
	for n in range(6):
		model.step([Combat.neutral(), Combat.neutral()])
		game.view.consume(model.events)
	await shot("hud-05-max-cutin", 0.05)
	_fight("nezuko", "akaza")
	model = game.combat
	model.fighters[0].meter = 300
	helper.events.clear()
	helper.input(model, "236236A")
	game.view.consume(helper.events)
	for n in range(4):
		model.step([Combat.neutral(), Combat.neutral()])
		game.view.consume(model.events)
	await shot("hud-06-super-cutin", 0.05)

func _effects() -> void:
	# A guarded heavy slash shows the shield shards and deflected sparks.
	_fight("tanjiro", "zenitsu")
	var guarded = game.combat
	guarded.fighters[0].x = 400
	guarded.fighters[1].x = 450
	var heavy: Resource = guarded.definition(guarded.fighters[0]).normals["5C"]
	guarded._begin_move(guarded.fighters[0], heavy)
	for n in range(heavy.startup + 4):
		guarded.step([Combat.neutral(), {"x": 1}])
		game.view.consume(guarded.events)
		if guarded.events.any(func(e: Dictionary) -> bool: return e.type == "block"):
			break
	game.view.effects.freeze = false
	game.view.effects._process(0.04)
	await shot("fx-guard", 0.0)
	for cid in ["tanjiro", "zenitsu", "nezuko", "akaza"]:
		for key in ["5A", "5C", "236A", "623C", "214D", "super", "max"]:
			_fight(cid, "zenitsu" if cid != "zenitsu" else "tanjiro")
			var model = game.combat
			var a = model.fighters[0]
			a.x = 400
			model.fighters[1].x = 450
			a.meter = 300
			var definition = model.definition(a)
			var move: Resource = definition.normals.get(key, definition.motions.get(key))
			if move == null:
				continue
			game.view.reset_effects()
			model._begin_move(a, move)
			game.view.consume(model.events)
			# Stop on the first real contact; hitstop then holds the impact frame.
			for n in range(move.startup + move.freeze_frames + 40):
				model.step([Combat.neutral(), Combat.neutral()])
				game.view.consume(model.events)
				if model.events.any(func(e: Dictionary) -> bool: return e.type == "hit"):
					break
			game.view.effects.freeze = false
			game.view.effects._process(0.035)
			game.view.hud._process(0)
			game.view.super_view._process(0)
			await shot("fx-%s-%s" % [cid, key], 0.0)
