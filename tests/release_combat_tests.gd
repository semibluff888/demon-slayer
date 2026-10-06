extends SceneTree
func _initialize() -> void:
	var failures = preload("res://scripts/combat_verifier.gd").new().run()
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
