extends RefCounted
# Explicit command-line check for packaged builds: DemonSlayer.exe --headless -- --verify-release
static func run(game: Node) -> void:
	var failures: Array[String] = []
	var catalog = game.catalog
	if catalog.characters.size() != 4 or catalog.stages.size() != 4:
		failures.append("Expected four playable characters and four stages")
	for id in catalog.characters:
		var visual = catalog.characters[id]
		visual.load_local_assets()
		if not visual.art_ready or not visual.missing_clips().is_empty():
			failures.append("Character assets missing: " + id)
		for clip in visual.clip_metadata:
			if visual.frames.get_frame_count(clip) != visual.clip_metadata[clip].frames.size():
				failures.append("Animation frames missing: " + id + "/" + clip)
		if visual.awakening_frames != null:
			for clip in visual.frames.get_animation_names():
				if visual.awakening_frames.get_frame_count(clip) != visual.frames.get_frame_count(clip):
					failures.append("Awakening animation frames missing: " + id + "/" + clip)
			if visual.awakening_frames.get_frame_count(visual.awakening.start_clip) != 6:
				failures.append("Awakening activation frames missing: " + id)
		if id != "akaza":
			for asset in ["portrait","fx-aura","fx-wisp","fx-sweep","fx-burst"]:
				if not ResourceLoader.exists("res://art/characters/%s/awakening/%s.png" % [id,asset]):
					failures.append("Packaged awakening artwork missing: " + id + "/" + asset)
		visual.release_combat_assets()
		var model = game.Combat.new()
		model.new_match(id,id)
		model.phase = "fight"
		model.fighters[0].meter = 300
		for tick in range(3): model.step([{"buttons":6} if tick == 0 else game.Combat.neutral(),game.Combat.neutral()])
		if model.fighters[0].awakening_ticks != 600 or model.fighters[0].meter != 100 or model.super_freeze != 12:
			failures.append("Packaged awakening input/resource failure: " + id)
		for tick in range(30): model.step([game.Combat.neutral(),game.Combat.neutral()])
		if model.fighters[0].awakening_ticks != 582 or model.fighters[0].awakening_startup != 0:
			failures.append("Packaged awakening timing failure: " + id)
	for id in catalog.stages:
		var stage = catalog.stages[id]
		stage.load_local_assets()
		if not stage.art_ready or stage.thumbnail == null:
			failures.append("Stage assets missing: " + id)
		stage.release_assets()
	if game.screen != "title" or catalog.body_font == null or catalog.title_font == null:
		failures.append("Title screen or fonts did not initialize")
	game.view.cinematic.prepare(["tanjiro", "zenitsu", "nezuko", "akaza"])
	if game.view.cinematic.available_moves().size() != 8:
		failures.append("Packaged cinematic videos missing")
	if game.view.cinematic.profiles.get("akaza_max", {}).get("video", "") != game.view.cinematic.profiles.get("akaza_super", {}).get("video", ""):
		failures.append("Akaza should share one cinematic for both supers")
	# Validate these rules inside the exported PCK, not only in the source checkout.
	var expected_keys := [
		[KEY_A, KEY_D, KEY_S, KEY_W, KEY_U, KEY_I, KEY_J, KEY_K],
		[KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_UP, KEY_KP_5, KEY_KP_6, KEY_KP_2, KEY_KP_3]]
	if game.InputRouter.KEYS != expected_keys:
		failures.append("Packaged default keyboard layout is outdated")
	game.set_physics_process(false)
	game.mode = "local"
	game.start_match()
	game.combat.phase = "fight"
	game.combat.remaining = 1800
	game.combat.fighters[0].hp = 400
	game.combat.fighters[1].hp = 0
	game.combat._finish_round()
	for n in range(game.Combat.Flow.OUTRO): game._physics_process(1.0/60)
	if game.combat.phase != "intro" or game.combat.fighters[0].hp != 550 or game.combat.fighters[1].hp != 1000:
		failures.append("Packaged winner health recovery is incorrect")
	if game.view.hud.trailing != [550.0,1000.0]:
		failures.append("Packaged opening HUD shows false damage")
	failures.append_array(preload("res://scripts/combat_verifier.gd").new().run(not OS.has_feature("editor")))
	for failure in failures:
		printerr("FAIL: ", failure)
	print("RELEASE SMOKE: %d failed" % failures.size())
	game.get_tree().quit(0 if failures.is_empty() else 1)
