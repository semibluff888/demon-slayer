extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("FAIL: expected output manifest path")
		quit(1)
		return
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		printerr("FAIL: cannot write combat manifest")
		quit(1)
		return
	file.store_string(preload("res://scripts/combat_verifier.gd").resource_snapshot())
	file.close()
	print("COMBAT MANIFEST OK")
	quit()
