extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
const Actor = preload("res://scripts/presentation/fighter_view.gd")
const Combat = preload("res://scripts/combat.gd")
const Support = preload("res://tests/combat_test_support.gd")
var passed := 0
var failures: Array[String] = []
var helper := Support.new()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: passed += 1
	else: failures.append(message)

func _run() -> void:
	var catalog = Catalog.new()
	_test_proportions(catalog)
	_test_pain(catalog)
	await _test_menu_and_stage()
	for failure in failures: printerr("FAIL: ", failure)
	print("FATE REVISIONS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_proportions(catalog: RefCounted) -> void:
	var heights := {}
	for cid: String in catalog.characters:
		var actor = Actor.new()
		actor.combat = helper.duel(cid)
		actor.fighter = actor.combat.fighters[0]
		actor.visual = catalog.characters[cid]
		actor.sync(0, true)
		var bounds: Rect2 = actor.visual_bounds()
		heights[cid] = bounds.size.y
		check(absf(bounds.end.y) < 0.5, "idle feet stay planted: " + cid)
		for clip_name in ["crouch", "air_heavy", "roll_forward", "thrown", "round_victory"]:
			actor.clip = clip_name
			actor.texture = actor.visual.frames.get_frame_texture(clip_name, actor.visual.frames.get_frame_count(clip_name) - 1)
			var right: Rect2 = actor.visual_bounds()
			actor.fighter.facing = -1
			var left: Rect2 = actor.visual_bounds()
			check(right.size.is_equal_approx(left.size), "mirror preserves body size: " + cid + "/" + clip_name)
			actor.fighter.facing = 1
		actor.free()
	check(heights.nezuko < heights.tanjiro * 0.95 and heights.nezuko > heights.tanjiro * 0.90, "Nezuko is visibly petite relative to Tanjiro")
	check(heights.nezuko < heights.zenitsu, "Nezuko is smaller than Zenitsu")
	check(heights.akaza > heights.tanjiro and heights.akaza > heights.zenitsu, "Akaza retains his larger build")
	catalog.prepare_match(["tanjiro", "zenitsu"], "wisteria")
	catalog.prepare_match(["nezuko", "akaza"], "corps_courtyard")
	var actor = Actor.new()
	actor.combat = helper.duel("nezuko")
	actor.fighter = actor.combat.fighters[0]
	actor.visual = catalog.characters.nezuko
	actor.sync(0, true)
	check(is_equal_approx(actor.visual_bounds().size.y, heights.nezuko), "reloading atlases never compounds character scale")
	actor.free()

func _test_pain(catalog: RefCounted) -> void:
	for attacker: String in ["tanjiro", "zenitsu", "nezuko", "akaza"]:
		for victim: String in ["nezuko", "akaza"]:
			for facing in [-1, 1]:
				for kind: String in ["super", "max"]:
					var model = Combat.new()
					model.new_match(attacker, victim)
					model.phase = "fight"
					var a = model.fighters[0]
					var b = model.fighters[1]
					a.x = 480; b.x = a.x + facing * 34
					a.facing = facing; b.facing = -facing
					for f in model.fighters:
						f.input.last_facing = f.facing
						f.previous_x = f.x
						f.meter = 300
					var actor = Actor.new()
					actor.combat = model; actor.fighter = b; actor.visual = catalog.characters[victim]
					var hits := 0
					var pain_ticks := 0
					var bad_frames := 0
					var frozen_frames := 0
					var move = model.catalog.characters[attacker].motions[kind]
					for tick in range(220):
						var command := Combat.neutral()
						if tick >= 8 and tick < 14:
							command = helper.relative(int("236236"[tick - 8]), facing, (5 if kind == "max" else 1) if tick == 13 else 0)
						model.step([command, Combat.neutral()])
						actor.consume(model.events, 1)
						var frozen: bool = model.hitstop > 0 or model.super_freeze > 0
						actor.sync(1.0 / 60.0, frozen)
						for event: Dictionary in model.events:
							if event.type == "hit" and event.attacker == 0:
								hits += 1
								if b.state == "hit" and actor.frame_index != 2: bad_frames += 1
						if b.state == "hit":
							pain_ticks += 1
							if actor.clip != "hit" or actor.frame_index not in [1, 2, 3]: bad_frames += 1
							if frozen: frozen_frames += 1
					var label := "%s %s -> %s (%d)" % [attacker, kind, victim, facing]
					check(hits == move.hit_count(), "all super contacts exercised: " + label)
					check(bad_frames == 0, "each impact and held stun use painful poses: " + label)
					if move.hit_count() > 1:
						check(pain_ticks > 10 and frozen_frames > 0, "pain stays visible through multihit and hitstop: " + label)
					actor.free()

func _test_menu_and_stage() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	await process_frame
	check(ProjectSettings.get_setting("application/config/name") == "\u9b3c\u706d\u4e4b\u5203\uff1a\u5bbf\u547d\u5bf9\u51b3", "new application title")
	check(game.gui.get_node_or_null("TitlePoster") is TextureRect, "generated poster is the title background")
	var labels: Array[String] = []
	for node in game.gui.get_children():
		if node is Label: labels.append(node.text)
	check(labels.is_empty(), "title menu has no duplicate title or decorative text")
	for mode: String in ["cpu", "local", "practice"]:
		game.choose_mode(mode)
		game.selection.confirm(0); game.selection.confirm(1)
		check(game.screen == "stage" and game.gui.stage_cards.size() == 4, "four maps available in " + mode)
		var bounds: Array[Rect2] = []
		for card in game.gui.stage_cards.values():
			var rect := Rect2(card.position, card.size)
			check(Rect2(36, 140, 1208, 476).encloses(rect), "map preview stays within safe menu area")
			for prior in bounds: check(not prior.intersects(rect), "map preview cards never overlap")
			bounds.append(rect)
		game.stage_id = "entertainment_district"
		game.selection.move_cursor(0, Vector2i.RIGHT)
		check(game.stage_id == "corps_courtyard", "direction input reaches courtyard")
		game.gui.actions.stage_corps_courtyard.pressed.emit()
		game.selection.confirm(0)
		check(game.screen == "battle" and game.view.stage.visual.id == "corps_courtyard", "courtyard launches in " + mode)
		check(game.view.stage.visual.art_ready and game.view.stage.layers.size() == 4, "complete tiled courtyard loads")
		game.start_match()
		check(game.stage_id == "corps_courtyard", "rematch keeps courtyard")
		if mode == "practice":
			game.reset_practice()
			check(game.view.stage.visual.id == "corps_courtyard", "practice reset keeps courtyard")
	var victim = game.combat.fighters[1]
	victim.state = "hit"; victim.stun = 20
	game.view._process(0)
	check(game.view.fighters[1].z_index > game.view.effects.z_index + game.view.effects.body_layer.z_index and game.view.fighters[1].z_index == game.view.effects.z_index, "pain renders over solid elemental ink while retaining additive impact light")
	victim.state = "idle"; victim.stun = 0
	game.view._process(0)
	check(game.view.fighters[1].z_index == 2, "normal depth returns after hitstun")
	game.queue_free()
	await process_frame
