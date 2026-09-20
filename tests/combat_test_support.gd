extends RefCounted
const Combat = preload("res://scripts/combat.gd")
const Commands = preload("res://scripts/command_recognizer.gd")
var events: Array[Dictionary] = []
var before_instance: int = -1

func duel(character: String = "tanjiro", facing: int = 1, corner: bool = false) -> Combat:
	var model := Combat.new()
	model.new_match(character, "zenitsu" if character == "tanjiro" else "tanjiro")
	model.phase = "fight"
	model.fighters[0].x = (840 if facing > 0 else 120) if corner else 480
	model.fighters[1].x = model.fighters[0].x + facing * 34
	model.fighters[0].facing = facing
	model.fighters[1].facing = -facing
	for f in model.fighters:
		f.input.last_facing = f.facing
		f.previous_x = f.x
	events.clear()
	return model

func tick(model: Combat, a: Dictionary = {}, b: Dictionary = {}) -> void:
	var first := Combat.neutral()
	var second := Combat.neutral()
	first.merge(a, true)
	second.merge(b, true)
	model.step([first, second])
	for event in model.events:
		events.append(event.duplicate(true))

func advance(model: Combat, count: int, a: Dictionary = {}, b: Dictionary = {}) -> void:
	for n in range(count):
		tick(model, a, b)

func relative(direction: int, facing: int, buttons: int = 0) -> Dictionary:
	return {"x": ((direction - 1) % 3 - 1) * facing, "y": 1 - int((direction - 1) / 3), "buttons": buttons}

func input(model: Combat, notation: String, defender: Dictionary = {}) -> void:
	before_instance = model.fighters[0].attack_instance
	var motion := ""
	var mask := 0
	for token in notation:
		if token in "123456789":
			motion += token
		elif token in "ABCD":
			mask |= 1 << "ABCD".find(token)
	if motion.is_empty():
		motion = "5"
	var facing: int = model.fighters[0].facing
	tick(model, {}, defender)
	for n in range(motion.length()):
		tick(model, relative(int(motion[n]), facing, mask if n == motion.length() - 1 else 0), defender)
	advance(model, 2, relative(int(motion[-1]), facing), defender)

func wait_contact(model: Combat, max_frames: int = 100, defender: Dictionary = {}) -> bool:
	for n in range(max_frames):
		var f = model.fighters[0]
		if f.move != null and f.confirmed and f.attack_instance != before_instance:
			return true
		tick(model, {}, defender)
	return false
