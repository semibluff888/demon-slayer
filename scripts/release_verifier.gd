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
		visual.release_combat_assets()
	for id in catalog.stages:
		var stage = catalog.stages[id]
		stage.load_local_assets()
		if not stage.art_ready or stage.thumbnail == null:
			failures.append("Stage assets missing: " + id)
		stage.release_assets()
	if game.screen != "title" or catalog.body_font == null or catalog.title_font == null:
		failures.append("Title screen or fonts did not initialize")
	for failure in failures:
		printerr("FAIL: ", failure)
	print("RELEASE SMOKE: %d failed" % failures.size())
	game.get_tree().quit(0 if failures.is_empty() else 1)
