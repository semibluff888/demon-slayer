extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
const Support = preload("res://tests/combat_test_support.gd")
const Actor = preload("res://scripts/presentation/fighter_view.gd")
const AI = preload("res://scripts/ai_controller.gd")
var helper := Support.new()
var passed := 0
var failures: Array[String] = []
var game: Node2D

class Pads extends "res://scripts/input_router.gd":
	var present: bool = true
	func connected(device: String) -> bool:
		return present if device.begins_with("pad:") else super.connected(device)
	func available_devices() -> Array[Dictionary]:
		var devices := super.available_devices()
		if present:
			devices.append({"id":"pad:98","label":"Test P1"})
			devices.append({"id":"pad:99","label":"Test P2"})
		return devices

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: passed += 1
	else: failures.append(message)

func _run() -> void:
	_test_catalog()
	_test_pairings()
	_test_new_moves()
	await _test_selection()
	for failure in failures: printerr("FAIL: ",failure)
	print("ROSTER EXPANSION: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_catalog() -> void:
	var catalog := Catalog.new(false)
	check(catalog.characters.keys() == ["tanjiro","zenitsu","nezuko","akaza"],"stable authored roster order")
	check(catalog.stages.keys() == ["wisteria","infinity_castle","entertainment_district","corps_courtyard"],"four ordered stages")
	for visual in catalog.characters.values():
		check(visual.frames == null and visual.avatar != null and visual.portrait != null,"menu uses portraits without animation atlas")
	for stage in catalog.stages.values():
		check(not stage.art_ready and stage.thumbnail != null,"menu uses only stage thumbnails")
	catalog.prepare_match(["nezuko","akaza"],"infinity_castle")
	for cid: String in catalog.characters:
		check(catalog.characters[cid].art_ready == (cid in ["nezuko","akaza"]),"only selected characters load: "+cid)
	for sid: String in catalog.stages:
		check(catalog.stages[sid].art_ready == (sid == "infinity_castle"),"only chosen stage loads: "+sid)
	for cid in ["nezuko","akaza"]:
		var visual = catalog.characters[cid]
		check(visual.frames.get_animation_names().size() == 42,"42 independent motion clips: "+cid)
		check(visual.missing_clips().is_empty(),"all authored normal, motion and state clips exist: "+cid)
		for move in catalog.data.characters[cid].all_moves():
			check(visual.frames.has_animation(move.clip_id()),"resource points to own frame sequence: "+move.id)
	catalog.prepare_match(["tanjiro","tanjiro"],"entertainment_district")
	check(catalog.characters.nezuko.frames == null and catalog.characters.akaza.frames == null,"changing selection releases previous atlases")
	check(catalog.stages.infinity_castle.layers.is_empty(),"switching stages releases prior textures")
	check(catalog.stages.entertainment_district.art_ready,"second new stage loads")
	var snapshot := catalog.data.characters.keys()
	check(snapshot.size() == 4,"render loading does not mutate combat catalog")

func _test_pairings() -> void:
	var model := Combat.new()
	for first: String in model.catalog.characters:
		for second: String in model.catalog.characters:
			model.new_match(first,second)
			model.phase = "fight"
			var left := AI.new(193)
			var right := AI.new(311)
			var count := 0
			while model.phase != "match_end" and count < 40000:
				model.step([left.command(model.fighters[0].observable(),model.fighters[1].observable()),right.command(model.fighters[1].observable(),model.fighters[0].observable())])
				count += 1
			check(model.phase == "match_end" and model.wins.max() == 2,"complete matchup including mirrors: "+first+"/"+second)
			check(model.fighters.all(func(f): return f.hp >= 0 and f.meter >= 0 and f.meter <= 300),"bounded HP and meter for "+first+"/"+second)
			print("ROSTER MATCH ",first," / ",second," : ",count," ticks")

func _test_new_moves() -> void:
	var art := Catalog.new()
	for cid in ["nezuko","akaza"]:
		for facing in [-1,1]:
			for corner in [false,true]:
				for notation in ["236A","236C","623A","623C","214B","214D","236236A","236236AC"]:
					var model = helper.duel(cid,facing,corner)
					var a = model.fighters[0]
					var b = model.fighters[1]
					a.meter = 300
					var key: String = "max" if notation.ends_with("AC") else "super" if notation.begins_with("236236") else notation
					var move = model.definition(a).motions[key]
					helper.input(model,notation)
					check(a.move == move,"motion recognized "+cid+"/"+notation)
					helper.advance(model,180)
					var hits: Array = helper.events.filter(func(e): return e.type == "hit" and e.get("move","") == move.id)
					check(hits.size() == move.hit_count(),"all real hits land "+cid+"/"+notation)
					check(1000-b.hp == move.damage,"whole move damage "+cid+"/"+notation)
					if move.is_super():
						check(move.damage == (445 if key == "max" else 280),"super/MAX authored damage")
						check(a.meter == 300-move.meter_cost,"super meter spent once")
					var blocked = helper.duel(cid,facing,corner)
					blocked.fighters[0].meter = 300
					helper.input(blocked,notation,{"x":facing})
					helper.advance(blocked,180,{},{"x":facing})
					check(not helper.events.any(func(e): return e.type == "hit"),"guard prevents real hit "+cid+"/"+notation)
					check(helper.events.any(func(e): return e.type == "block"),"guard contact observed "+cid+"/"+notation)
		# MAX uses its own body/cut-in and releases it on natural end, interruption, KO and reset.
		for end_kind in ["complete","interrupt","ko","reset"]:
			var model = helper.duel(cid)
			model.fighters[0].meter = 300
			var actor := Actor.new()
			actor.combat = model
			actor.fighter = model.fighters[0]
			actor.visual = art.characters[cid]
			helper.input(model,"236236AC")
			actor.sync(0,false)
			check(actor.clip == model.definition(actor.fighter).motions.max.clip_id(),"MAX pose entered "+cid)
			if end_kind == "interrupt":
				var enemy = model.fighters[1]
				var move = model.definition(enemy).normals["5C"]
				model._resolve_contact(model._contact(enemy,actor.fighter,move,99,0,false))
				actor.consume(model.events,0)
			elif end_kind == "ko":
				actor.fighter.hp = 1
				var enemy = model.fighters[1]
				model._resolve_contact(model._contact(enemy,actor.fighter,model.definition(enemy).normals["5C"],99,0,false))
				helper.advance(model,90)
			elif end_kind == "reset":
				model.new_match(cid,"tanjiro")
				actor.fighter = model.fighters[0]
			else:
				helper.advance(model,210)
			actor.sync(0,false)
			check(actor.clip != model.definition(actor.fighter).motions.max.clip_id(),"MAX appearance cleared on "+end_kind+"/"+cid)
			actor.free()
		# True hit-confirm route, holding guard after the first hit.
		var model = helper.duel(cid)
		model.fighters[0].meter = 300
		for notation in ["5A","5C","214B","236236A"]:
			helper.input(model,notation,{} if notation=="5A" else {"x":1})
			check(helper.wait_contact(model,100,{} if notation=="5A" else {"x":1}),"true cancel route contact "+cid+"/"+notation)
		helper.advance(model,160,{},{"x":1})
		check(not helper.events.any(func(e): return e.type=="block"),"complete route remains a true combo "+cid)

func _key(key: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	game._input(event)

func _pad(device: int, button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = true
	game._input(event)
	event.pressed = false
	game._input(event)

func _test_selection() -> void:
	game = Main.instantiate()
	game.settings.path = "res://artifacts/roster_expansion_tests-settings.cfg"
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	game.settings.save_config()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	await process_frame
	check(game.stage_id == "wisteria","first default stage")
	for mode in ["cpu","practice","local"]:
		game.devices.assign(["keyboard:0","keyboard:1"])
		game.choose_mode(mode)
		game.select_character(0,"nezuko")
		game.select_character(1,"akaza")
		game.selection.active_slot = 0
		_key(KEY_T)
		check(game.screen == "setup" and game.selection.ready == [true,false],"P1 locks before stage: "+mode)
		_key(KEY_KP_4 if mode == "local" else KEY_T)
		check(game.screen == "stage","both locked opens stage: "+mode)
		var selected: Array = game.characters.duplicate()
		game.gui.actions.back.pressed.emit()
		check(game.screen == "setup" and game.characters == selected and game.selection.ready == [false,false],"stage back preserves picks and unlocks: "+mode)
		game.gui.actions.start.pressed.emit()
		game.gui.actions.start.pressed.emit()
		game.gui.actions.stage_infinity_castle.pressed.emit()
		check(game.screen == "stage" and game.stage_id == "infinity_castle","mouse selects stage without starting")
		if mode == "local":
			_key(KEY_KP_4)
			check(game.screen == "stage","P2 cannot start stage")
		_key(KEY_T)
		check(game.screen == "battle" and game.view.stage.visual.id == "infinity_castle","P1 starts selected stage: "+mode)
		game.start_match()
		check(game.stage_id == "infinity_castle","rematch retains stage")
		if mode == "practice":
			game.reset_practice()
			check(game.view.stage.visual.id == "infinity_castle","practice reset retains map")
	# Independent keyboards, mirrored cursor rendering and lock ownership.
	game.choose_mode("local")
	game.characters.assign(["tanjiro","tanjiro"])
	game.gui.refresh_setup()
	_key(KEY_D)
	check(game.characters == ["zenitsu","tanjiro"],"P1 direction only changes P1")
	_key(KEY_RIGHT)
	check(game.characters == ["zenitsu","zenitsu"],"P2 direction is independent, mirrors allowed")
	check(game.gui.roster_cards.zenitsu.cursors == [0,1],"mirror card displays both cursors")
	_key(KEY_T)
	_key(KEY_D)
	check(game.characters[0] == "zenitsu" and game.selection.ready[0],"locked cursor cannot move")
	_key(KEY_Y)
	check(not game.selection.ready[0],"owner can unlock")
	game.devices[1] = game.devices[0]
	game._validate_setup()
	_key(KEY_T)
	check(game.start_button.disabled and not game.selection.ready[0],"conflicting assignment blocks locking")
	# Real joypad event types, deterministic virtual device presence.
	game.router = Pads.new()
	game.show_title()
	_pad(98,JOY_BUTTON_A)
	game.choose_mode("local")
	check(game.devices == ["pad:98","pad:99"],"title pad becomes P1 and second pad is assigned automatically")
	game.devices.assign(["pad:98","pad:99"])
	game.show_setup()
	game.characters.assign(["tanjiro","tanjiro"])
	game.gui.refresh_setup()
	_pad(98,JOY_BUTTON_DPAD_RIGHT)
	_pad(99,JOY_BUTTON_DPAD_LEFT)
	check(game.characters == ["zenitsu","akaza"],"two pad events control independent cursors")
	_pad(98,JOY_BUTTON_Y)
	check(not game.selection.modal and not game.gui.actions.has("devices"),"selection has no device popup or shortcut")
	_pad(98,JOY_BUTTON_A)
	_pad(99,JOY_BUTTON_A)
	check(game.screen == "stage","two pads confirm setup")
	_pad(99,JOY_BUTTON_DPAD_RIGHT)
	check(game.stage_id == "infinity_castle","P2 cannot change stage")
	game.router.present = false
	game._on_joy_connection(98,false)
	check(not game._devices_ready() and game.start_button.disabled,"disconnect blocks start")
	check(game.selection.ready == [false,false],"disconnect clears locks")
	game.router.present = true
	game._on_joy_connection(98,true)
	game.show_setup()
	_pad(98,JOY_BUTTON_A)
	_pad(99,JOY_BUTTON_A)
	_pad(98,JOY_BUTTON_A)
	check(game.screen == "battle","reconnected controllers complete menu")
	# Resource-only registrations exercise the same roster generation used by real fighters.
	game.devices.assign(["keyboard:0","keyboard:1"])
	for count in [4,12,24]:
		var originals: Dictionary = game.catalog.characters.duplicate()
		for n in range(4,count):
			var id := "test_%02d" % n
			var visual: Resource = originals.tanjiro.duplicate()
			visual.character_id = id
			visual.display_name = "Test %d" % n
			game.catalog.characters[id] = visual
		game.show_setup()
		await process_frame
		await process_frame
		check(game.gui.roster_cards.size()==count,"directory-only extension to %d" % count)
		for card: Button in game.gui.roster_cards.values():
			check(card.size == Vector2(96,88),"fixed avatar dimensions at %d" % count)
		var ids: Array = game.catalog.characters.keys()
		game.select_character(0,ids[-1])
		await process_frame
		await process_frame
		var card: Control = game.gui.roster_cards[ids[-1]]
		var view_rect: Rect2 = game.gui.roster_scroll.get_global_rect()
		check(view_rect.encloses(card.get_global_rect()),"selected last row automatically visible at %d" % count)
		game.select_character(1,ids[0])
		await process_frame
		await process_frame
		check(game.characters == [ids[-1],ids[0]],"independent picks across pages at %d" % count)
		check(game.gui.fighter_names[0].text == game.catalog.characters[ids[-1]].display_name,"offscreen P1 portrait remains selected")
		game.characters.assign(["tanjiro","zenitsu"])
		game.catalog.characters = originals
	game.queue_free()
	await process_frame
