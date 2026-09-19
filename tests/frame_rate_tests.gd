extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const AI = preload("res://scripts/ai_controller.gd")
var model := Combat.new()
var a := AI.new(49)
var b := AI.new(12)
var ticks: int = 0
var draw_ticks: int = 0

func _process(_delta: float) -> bool:
	draw_ticks += 1
	return false

func _physics_process(_delta: float) -> bool:
	model.step([a.command(model.fighters[0].observable(), model.fighters[1].observable()),
		b.command(model.fighters[1].observable(), model.fighters[0].observable())])
	ticks += 1
	if ticks == 1800:
		print("FRAME RATE RESULT: physics=", ticks, " render=", draw_ticks,
			" hash=", JSON.stringify(model.snapshot()).sha256_text())
		quit(0)
	return false
