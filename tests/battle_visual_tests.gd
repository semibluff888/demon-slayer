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
			var width: float = game.catalog.title_font.get_string_size(move.display_name,HORIZONTAL_ALIGNMENT_LEFT,-1,SuperView.TITLE_SIZE).x
			check(SuperView.TITLE_SIZE==36 and width<1120,"same 36px size fits full title")
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
	game.queue_free()
	await process_frame
	print("BATTLE VISUAL TESTS: %d passed, %d failed" % [passed,failed])
	quit(0 if failed==0 else 1)
