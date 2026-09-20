extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Router = preload("res://scripts/input_router.gd")
const AI = preload("res://scripts/ai_controller.gd")
var model := Combat.new()
var a := AI.new(49)
var b := AI.new(12)
var ticks: int = 0
var draw_ticks: int = 0
var scripted := Combat.new()
var router := Router.new()

func _process(_delta: float) -> bool:
	draw_ticks += 1
	return false

func _physics_process(_delta: float) -> bool:
	model.step([a.command(model.fighters[0].observable(), model.fighters[1].observable()),
		b.command(model.fighters[1].observable(), model.fighters[0].observable())])
	var cycle := ticks % 180
	if cycle == 0:
		scripted.new_match("tanjiro", "zenitsu")
		scripted.phase = "fight"
		scripted.fighters[0].x = 400
		scripted.fighters[1].x = 520
		router.reset(["keyboard:0","keyboard:1"])
	var held := Combat.neutral()
	if cycle in [4,8]:
		held.x = 1
	if cycle == 30:
		held.throw = true
	if cycle == 90:
		held.jump = true
		held.x = -1
	if cycle == 106:
		held.heavy = true
	scripted.step([router.command_from_held(0,held),Combat.neutral()])
	ticks += 1
	if ticks == 1800:
		print("FRAME RATE RESULT: physics=", ticks, " render=", draw_ticks,
			" hash=", JSON.stringify([model.snapshot(),scripted.snapshot()]).sha256_text())
		quit(0)
	return false
