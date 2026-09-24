extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const AI = preload("res://scripts/ai_controller.gd")
var model := Combat.new()
var a := AI.new(49)
var b := AI.new(12)
var ticks: int = 0
var draw_ticks: int = 0
var scripted := Combat.new()
var finishing := Combat.new()
var lethal_throw := Combat.new()
var polish_trace := HashingContext.new()

func _initialize() -> void:
	polish_trace.start(HashingContext.HASH_SHA256)

func _polish_step() -> void:
	# Hash the entire KO history, including the impact before throw settlement.
	if ticks % 450 == 0:
		var index := int(ticks / 450)
		var cid := "zenitsu" if index % 2 == 0 else "tanjiro"
		for c in [finishing, lethal_throw]:
			c.new_match(cid, "tanjiro" if cid == "zenitsu" else "zenitsu")
			c.phase = "fight"
			c.fighters[0].x = 480
			c.fighters[1].x = 514
			c.fighters[0].meter = 300
			c.fighters[1].hp = 1
		finishing._begin_move(finishing.fighters[0], finishing.moves["zenitsu_super" if cid == "zenitsu" else "tanjiro_623C"])
		lethal_throw.fighters[0].throw_back = index % 2 == 0
		lethal_throw._start_throw(lethal_throw._contact(lethal_throw.fighters[0], lethal_throw.fighters[1], lethal_throw.definition(lethal_throw.fighters[0]).throw_move, 1, 0, false))
	for c in [finishing, lethal_throw]:
		c.step([Combat.neutral(), Combat.neutral()])
		polish_trace.update(JSON.stringify(c.snapshot()).to_utf8_buffer())

func _process(_delta: float) -> bool:
	draw_ticks += 1
	return false

func _physics_process(_delta: float) -> bool:
	model.step([a.command(model.fighters[0].observable(), model.fighters[1].observable()),
		b.command(model.fighters[1].observable(), model.fighters[0].observable())])
	var cycle := ticks % 90
	var scenario := int(ticks / 90) % 4
	if cycle == 0:
		scripted.new_match("tanjiro", "zenitsu")
		scripted.phase = "fight"
		scripted.fighters[0].x = 400
		scripted.fighters[1].x = 432 if scenario == 3 else 480
		scripted.fighters[0].meter = 300
	var held := Combat.neutral()
	if scenario in [0,1] and cycle >= 5 and cycle <= (10 if scenario == 0 else 7):
		var digits := "236236" if scenario == 0 else "236"
		var index := cycle - 5
		var direction := int(digits[index])
		held.x = (direction - 1) % 3 - 1
		held.y = 1 - int((direction - 1) / 3)
		held.buttons = (5 if scenario == 0 else 1) if index == digits.length() - 1 else 0
	elif scenario == 2:
		if cycle == 5:
			held.buttons = 3
		if cycle == 45:
			held.y = -1
		if cycle == 65:
			held.buttons = 4
	elif scenario == 3 and cycle == 5:
		held.x = -1
		held.buttons = 8
	scripted.step([held, Combat.neutral()])
	_polish_step()
	ticks += 1
	if ticks == 1800:
		print("FRAME RATE RESULT: physics=", ticks, " render=", draw_ticks,
			" hash=", JSON.stringify([model.snapshot(),scripted.snapshot(),polish_trace.finish().hex_encode()]).sha256_text())
		quit(0)
	return false
