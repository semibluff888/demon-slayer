extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Support = preload("res://tests/combat_test_support.gd")
const SuperView = preload("res://scripts/presentation/super_view.gd")
var passed: int = 0
var failed: int = 0
var helper := Support.new()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL: ",message)

func _run() -> void:
	var game := Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	game.choose_mode("practice")
	for node in [game.view,game.view.effects,game.view.hud,game.view.stage,game.view.super_view]:
		node.set_process(false)
	for cid in ["tanjiro","zenitsu"]:
		for key in ["super","max"]:
			game.characters.assign([cid,cid])
			game.start_match()
			var model = game.combat
			model.fighters[0].x = 480
			model.fighters[1].x = 640
			helper.input(model,"236236AC" if key=="max" else "236236A")
			var starts: Array = helper.events.filter(func(e: Dictionary) -> bool: return e.type=="super")
			check(starts.size()==1,"real input starts one cinematic")
			game.view.consume(starts)
			var cue_view = game.view.super_view
			check(cue_view.active.size()==1,"one active cue")
			check(model.fighters[0].meter==(0 if key=="max" else 200),"meter spent once")
			var move: Resource = model.definition(model.fighters[0]).motions[key]
			check(move.freeze_frames==(18 if key=="max" else 12),"existing freeze retained")
			check(cue_view.active[0].move.display_name==move.display_name,"full canonical title")
			_check_title(cue_view, cue_view.active[0], cid, key)
			game.view.hud.practice_details = true
			check(not game.view.hud.practice_details_visible(), "cinematic suppresses expanded practice hints")
			game.view.consume(starts)
			check(cue_view.active.size()==1,"duplicate delivery does not restart")
			var pose_before: int = model.fighters[0].move_frame
			var age_before: float = cue_view.active[0].age
			helper.tick(model)
			cue_view._process(1.0/60)
			check(model.fighters[0].move_frame==pose_before,"logic pose frozen during charge")
			check(cue_view.active[0].age>age_before,"cinematic progresses during super freeze")
			var snapshot: Dictionary = model.snapshot()
			cue_view._process(0.6)
			check(model.snapshot()==snapshot,"presentation cannot advance or mutate model")
			cue_view.paused = true
			var age: float = cue_view.active[0].age
			cue_view._process(1.0)
			check(cue_view.active[0].age==age,"pause holds charge")
			cue_view.paused = false
			model.fighters[0].state = "hit"
			cue_view._process(0)
			check(cue_view.active.is_empty() and is_zero_approx(cue_view.dim_amount),"interruption clears darkening and title")
			check(game.view.hud.practice_details_visible(), "interruption restores requested practice hints")
			game.view.hud.practice_details = false
			game.start_match()
			model = game.combat
			model.fighters[0].meter = 0
			helper.events.clear()
			helper.input(model,"236236AC")
			game.view.consume(helper.events)
			check(game.view.super_view.active.is_empty(),"insufficient meter produces no cinematic")
			check(game.view.hud.meter_error[0]>0,"insufficient meter feedback retained")
	# A real super can whiff or be blocked without producing false hit feedback.
	for cid in ["tanjiro","zenitsu"]:
		for key in ["super","max"]:
			for blocked in [false,true]:
				game.characters.assign([cid,"zenitsu" if cid=="tanjiro" else "tanjiro"])
				game.start_match()
				var scenario_model = game.combat
				scenario_model.fighters[0].x = 300
				scenario_model.fighters[1].x = 350 if blocked else 660
				helper.events.clear()
				var defender := {"x":1} if blocked else {}
				helper.input(scenario_model,"236236AC" if key=="max" else "236236A",defender)
				game.view.consume(helper.events)
				check(game.view.super_view.active.size()==1,"block/whiff still presents actual activation")
				for tick in range(150):
					helper.tick(scenario_model,{},defender)
					game.view.consume(scenario_model.events)
					game.view.super_view._process(1.0/60)
				check(not helper.events.any(func(e: Dictionary) -> bool: return e.type=="hit"),"no false hit in block/whiff")
				if blocked:
					check(helper.events.any(func(e: Dictionary) -> bool: return e.type=="block"),"real guarded contact observed")
				check(game.view.super_view.active.is_empty() and is_zero_approx(game.view.super_view.dim_amount),"cinematic expires after block/whiff")
	# Simultaneous actual inputs: two independent headings, one maximum-strength dimmer.
	game.characters.assign(["tanjiro","zenitsu"])
	game.start_match()
	var model = game.combat
	model.fighters[0].x = 380
	model.fighters[1].x = 580
	model.fighters[1].meter = 300
	var motion := "236236"
	for tick in range(10):
		var commands: Array = [Combat.neutral(),Combat.neutral()]
		if tick<6:
			commands[0] = helper.relative(int(motion[tick]),1,5 if tick==5 else 0)
			commands[1] = helper.relative(int(motion[tick]),-1,5 if tick==5 else 0)
		model.step(commands)
		game.view.consume(model.events)
		game.view.super_view._process(1.0/60)
	check(game.view.super_view.active.size()==2,"both real simultaneous MAX starts are visible")
	if game.view.super_view.active.size() == 2:
		var first_bounds: Rect2 = game.view.super_view.title_bounds(game.view.super_view.active[0], true)
		var second_bounds: Rect2 = game.view.super_view.title_bounds(game.view.super_view.active[1], true)
		check(not first_bounds.intersects(second_bounds), "simultaneous illustrated titles never overlap")
	check(game.view.super_view.dim_amount<=0.80,"darkening is max-composited, not summed")
	game.reset_practice()
	check(game.view.super_view.active.is_empty(),"practice reset clears cinematic")
	game.view.super_view.consume([{"type":"round_end"}])
	check(game.view.super_view.active.is_empty(),"round end has no residual overlay")
	check(game.gui.actions.has("practice_options"),"practice settings remains reachable")
	game.show_practice_options()
	check(game.gui.actions.has("practice_details"),"details toggle reachable through existing settings")
	var details = game.gui.actions.practice_details
	details.button_pressed = true
	check(game.view.hud.practice_details,"details toggle updates HUD")
	_check_spatial_cutins(game)
	_check_hud(game)
	_check_battle_menu_scope(game)
	game.queue_free()
	await process_frame
	print("BATTLE VISUAL TESTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed==0 else 1)

func _check_title(cue_view: Node2D, cue: Dictionary, character: String, kind: String) -> void:
	var keys := {"tanjiro":{"super":"water_dragon", "max":"sun_arc"}, "zenitsu":{"super":"sixfold", "max":"godspeed"}}
	var texture: Texture2D = cue_view.title_texture(cue)
	check(texture != null, "supplied title texture loads: " + character + "/" + kind)
	if texture == null:
		return
	check(texture.resource_path == "res://art/ui/super-titles/%s.png" % keys[character][kind], "canonical move uses the correct supplied title")
	for both in [false, true]:
		var bounds: Rect2 = cue_view.title_bounds(cue, both)
		var limit := Vector2(560, 104) if both else Vector2(660, 152)
		check(bounds.size.x <= limit.x + 0.01 and bounds.size.y <= limit.y + 0.01, "title fits its single/dual slot")
		check(Rect2(24, 100, 1232, 260).encloses(bounds), "entering title stays inside safe screen bounds")
		check(is_equal_approx(bounds.size.x / bounds.size.y, texture.get_width() / float(texture.get_height())), "title art is not stretched")
		var face: Rect2 = cue_view.face_bounds(cue, both)
		check(not bounds.intersects(face), "title does not overlap its complete MAX face")
		check(Rect2(24, 100, 1232, 260).encloses(face), "complete face stays below HUD and on screen")
		check(is_equal_approx(face.get_center().y, bounds.get_center().y), "face follows its single/dual title row")
	var fallback: Dictionary = cue.duplicate()
	fallback.move = cue.move.duplicate(true)
	fallback.move.presentation.title_texture = null
	check(cue_view.title_texture(fallback) == null and cue_view.title_bounds(fallback).has_area(), "unillustrated moves retain a fitted text fallback")

func _check_hud(game: Node2D) -> void:
	var hud = game.view.hud
	for value in [0, 99, 100, 175, 299, 300]:
		var total := 0.0
		for cell in range(3):
			var first: Rect2 = hud.meter_fill_rect(0, value, cell)
			var second: Rect2 = hud.meter_fill_rect(1, value, 2 - cell)
			check(hud.meter_cell(0, cell).encloses(first) and hud.meter_cell(1, 2 - cell).encloses(second), "partial meter fill stays inside each cell")
			check(first.size.is_equal_approx(second.size) and is_equal_approx(first.position.x, 1280 - second.end.x), "P2 meter grows as the mirrored P1 meter")
			total += first.size.x
		check(is_equal_approx(total, value * 0.8), "meter fill represents exact resource at threshold " + str(value))
	hud.consume([{"type":"meter_empty", "attacker":0, "cost":300}, {"type":"meter", "attacker":1, "amount":-100}])
	check(hud.meter_error[0] > 0 and hud.meter_spent[1] == 100 and hud.spent_time[1] > 0, "bare meter keeps insufficient/spent feedback")
	hud.frozen = true
	var time_before: float = hud.time
	var feedback_before: float = hud.meter_error[0]
	hud._process(0.4)
	check(hud.time == time_before and hud.meter_error[0] == feedback_before, "pause holds HUD feedback animation")
	hud.frozen = false
	hud.reset_effects()
	check(hud.meter_error == [0.0, 0.0] and hud.spent_time == [0.0, 0.0], "HUD reset clears resource feedback")

func _check_battle_menu_scope(game: Node2D) -> void:
	game.set_paused(false)
	check(game.gui.actions.pause.battle_style and game.gui.actions.pause.text_only, "battle footer uses a text-only native button")
	game.set_paused(true)
	check(not game.gui.battle_style and not game.gui.actions.resume.battle_style and not game.gui.actions.resume.text_only, "pause controls use the original character-selection style")
	game.show_title()
	check(not game.gui.battle_style and not game.gui.actions.mode_cpu.battle_style, "return to main menu restores its original variant")
	game.choose_mode("practice")
	check(not game.gui.actions.start.battle_style, "character selection keeps original buttons")
	game.start_match()
	game.show_practice_options()
	var toggle = game.gui.actions.practice_details
	check(toggle is CheckButton and not game.gui.battle_style and not game.gui.actions.resume.battle_style, "practice settings restores the original menu style and native toggle")
	toggle.button_pressed = false
	toggle.button_pressed = true
	check(game.view.hud.practice_details, "native practice toggle still updates HUD")

func _check_spatial_cutins(game: Node2D) -> void:
	for cid in ["tanjiro", "zenitsu"]:
		for slot in [0, 1]:
			for side in [-1, 1]:
				game.characters.assign([cid, cid])
				game.start_match()
				var model = game.combat
				var attacker = model.fighters[slot]
				var defender = model.fighters[1 - slot]
				attacker.x = 480 + side * 90
				defender.x = 480 - side * 90
				attacker.facing = -side
				defender.facing = side
				attacker.input.last_facing = -side
				defender.input.last_facing = side
				attacker.meter = 300
				game.view.camera.reset(model.fighters)
				var motion := "236236"
				for tick in range(8):
					var commands: Array = [Combat.neutral(), Combat.neutral()]
					if tick < 6:
						commands[slot] = helper.relative(int(motion[tick]), -side, 5 if tick == 5 else 0)
					model.step(commands)
					game.view.consume(model.events)
				var view = game.view.super_view
				check(view.active.size() == 1, "swapped player positions still activate a MAX")
				if view.active.size() != 1:
					continue
				var cue: Dictionary = view.active[0]
				check(cue.side == side, "cut-in side follows spatial position, independent of player slot")
				for both in [false, true]:
					var title: Rect2 = view.title_bounds(cue, both)
					var face: Rect2 = view.face_bounds(cue, both)
					check(face.end.x < title.position.x if side < 0 else face.position.x > title.end.x, "MAX portrait flanks the title on activation side")
					var source: Rect2 = view.face_source(view.catalog.characters[cid].battle_portrait)
					check(is_equal_approx(face.size.x / face.size.y, source.size.x / source.size.y), "MAX face preserves portrait aspect ratio")
					check(source.encloses(Rect2(200, 30, 665, 640)), "source region retains the full hair-to-chin face")
				attacker.x = defender.x - side * 120
				view._process(0)
				check(view.active[0].side == side, "rushing across the opponent cannot swap an active cut-in")
				var before: Rect2 = view.face_bounds(cue, true)
				var other: Dictionary = cue.duplicate()
				other.slot = 1 - slot
				check(not before.intersects(view.face_bounds(other, true)), "dual MAX faces occupy separate rows even on the same side")
	# At a wall both actors may share one screen half; opponent order is insufficient.
	for side in [-1, 1]:
		game.start_match()
		var model = game.combat
		model.fighters[0].x = 65 if side < 0 else 895
		model.fighters[1].x = 105 if side < 0 else 855
		game.view.camera.reset(model.fighters)
		for slot in [0, 1]:
			check(game.view.super_view.activation_side(slot) == side, "wall cut-ins follow actual screen half even when both fighters share it")

	game.start_match()
