extends SceneTree

func _initialize() -> void:
	for directory in ["res://scripts", "res://tests", "res://tools", "res://demo/round-presentation"]:
		if not _load_scripts(directory):
			quit(1)
			return
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		quit(1)
		return
	var game := scene.instantiate()
	root.add_child.call_deferred(game)
	await process_frame
	await process_frame
	print("COMPILE / SCENE LOAD OK")
	game.queue_free()
	await process_frame
	quit(0)

func _load_scripts(directory: String) -> bool:
	for name in ResourceLoader.list_directory(directory):
		var path := directory.path_join(name)
		if name.ends_with("/"):
			if not _load_scripts(path.trim_suffix("/")):
				return false
		elif name.ends_with(".gd"):
			var script := load(path) as GDScript
			if script == null or not script.can_instantiate():
				printerr("Cannot compile script: ", path)
				return false
	return true
