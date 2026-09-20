class_name DuelAI
extends RefCounted
## Reacts to 12-tick-old visible opponent state. Produces real held inputs.
const Combat = preload("res://scripts/combat.gd")
const Catalog = preload("res://scripts/combat_catalog.gd")
var catalog := Catalog.new()
var history: Array[Dictionary] = []
var queue: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var cooldown: int = 20
var direction: int = 0
var crouch: bool = false
var think: int = 0
var cancelled_move: String = ""

func _init(seed_value: int = 713) -> void:
	rng.seed = seed_value

func reset() -> void:
	history.clear()
	queue.clear()
	cooldown = 20
	direction = 0
	crouch = false
	think = 0
	cancelled_move = ""

func _enqueue(notation: String, facing: int) -> void:
	queue.append(Combat.neutral())
	var digits := ""
	var mask := 0
	for token in notation:
		if token in "123456789":
			digits += token
		elif token in "ABCD":
			mask |= 1 << "ABCD".find(token)
	if digits.is_empty():
		digits = "5"
	for i in range(digits.length()):
		var number := int(digits[i])
		queue.append({"x": ((number - 1) % 3 - 1) * facing, "y": 1 - int((number - 1) / 3),
			"buttons": mask if i == digits.length() - 1 else 0})
	queue.append(Combat.neutral())
	queue.append(Combat.neutral())

func command(self_state: Dictionary, opponent: Dictionary) -> Dictionary:
	history.append(opponent.duplicate())
	if history.size() <= 12:
		return Combat.neutral()
	var observed: Dictionary = history.pop_front()
	var facing := int(self_state.facing)
	var distance: float = absf(observed.x - self_state.x)
	cooldown -= 1
	think -= 1
	if self_state.state in ["hit", "block", "knockdown", "thrown"]:
		queue.clear()
	if not queue.is_empty():
		return queue.pop_front()
	if self_state.state != "attack":
		cancelled_move = ""
	var current: String = self_state.get("move", "")
	if not current.is_empty() and current != cancelled_move and self_state.get("connected", false):
		var move: Resource = catalog.moves.get(current)
		if move != null:
			cancelled_move = current
			if move.kind == "light" and move.stance != "air":
				_enqueue("5C", facing)
			elif move.kind == "heavy" and not move.knockdown and move.stance != "air":
				_enqueue("236A" if rng.randf() < 0.7 else "214B", facing)
			elif move.kind == "skill" and self_state.get("confirmed", false) and int(self_state.meter) >= 100 and rng.randf() < 0.7:
				_enqueue("236236AC" if int(self_state.meter) >= 300 and rng.randf() < 0.6 else "236236A", facing)
	if not queue.is_empty():
		return queue.pop_front()
	if think <= 0:
		think = rng.randi_range(6, 11)
		crouch = false
		if observed.state == "attack" and distance < 145 and rng.randf() < 0.72:
			direction = -facing
			crouch = observed.crouching and observed.grounded
		elif distance > 55:
			direction = facing
		elif distance < 32 and rng.randf() < 0.22:
			direction = -facing
		else:
			direction = 0
	var result := {"x": direction, "y": 1 if crouch else 0, "buttons": 0}
	if cooldown <= 0 and self_state.state not in ["attack", "hit", "block", "knockdown", "thrown", "roll"]:
		cooldown = rng.randi_range(15, 28)
		var roll := rng.randf()
		if not observed.grounded and distance < 80:
			_enqueue("623A", facing)
		elif observed.state == "attack" and distance < 100 and roll < 0.18:
			_enqueue("4AB", facing)
		elif distance < 37 and roll < 0.16:
			_enqueue("6D" if rng.randf() < 0.5 else "4D", facing)
		elif distance < 66:
			_enqueue("2B" if roll < 0.35 else ("5A" if roll < 0.78 else "5C"), facing)
		elif distance < 210 and roll < 0.72:
			_enqueue("236A", facing)
		elif distance > 80 and roll > 0.83:
			result.y = -1
			result.x = facing
	if not queue.is_empty():
		return queue.pop_front()
	return result
