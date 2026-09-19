extends SceneTree

func _initialize() -> void:
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
