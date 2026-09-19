class_name DuelAI
extends RefCounted
## Decisions use a 12-tick-old observable opponent snapshot, never queued inputs.
const Combat = preload("res://scripts/combat.gd")
var history: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var cooldown: int = 20
var direction: int = 0
var crouch: bool = false
var think: int = 0

func _init(seed_value: int = 713) -> void:
	rng.seed = seed_value

func reset() -> void:
	history.clear()
	cooldown = 20
	direction = 0
	crouch = false
	think = 0

func command(self_state: Dictionary, opponent: Dictionary) -> Dictionary:
	var result := Combat.neutral()
	history.append(opponent.duplicate())
	if history.size() <= 12:
		return result
	var observed: Dictionary = history.pop_front()
	cooldown -= 1
	think -= 1
	var facing := 1 if observed.x > self_state.x else -1
	var distance: float = absf(observed.x - self_state.x)
	if think <= 0:
		think = rng.randi_range(6, 11)
		crouch = false
		if observed.state == "attack" and distance < 125 and rng.randf() < 0.78:
			direction = -facing
			crouch = observed.crouching and observed.grounded
		elif distance > 57:
			direction = facing
		elif distance < 35 and rng.randf() < 0.25:
			direction = -facing
		else:
			direction = 0
	result.x = direction
	result.down = crouch
	if cooldown <= 0 and self_state.state not in ["hit", "block", "knockdown"]:
		cooldown = rng.randi_range(17, 31)
		var roll := rng.randf()
		if distance < 36 and roll < 0.19:
			result.throw = true
			result.down = false
		elif distance < 68:
			if roll < 0.43:
				result.light = true
			elif roll < 0.72:
				result.heavy = true
				result.down = rng.randf() < 0.3
			else:
				result.skill = true
		elif distance < 170 and roll < 0.65:
			result.skill = true
			result.x = facing
		elif distance > 85 and roll > 0.74:
			result.jump = true
	return result
