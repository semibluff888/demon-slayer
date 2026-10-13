extends RefCounted
## Measures real frame advantage by stepping the deterministic model.
## A side counts as free from the step that ends its move, stun or landing
## recovery; both sides can act on the following step, so the difference of
## those steps is the advantage (positive favours the attacker, P1).
const Combat = preload("res://scripts/combat.gd")
const Arena = preload("res://scripts/arena_rules.gd")
const JUMP_VY := -7.8
const GRAVITY := 0.42

static func duel(character: String, opponent: String = "") -> Combat:
	var model := Combat.new()
	model.new_match(character, opponent if not opponent.is_empty() else ("zenitsu" if character == "tanjiro" else "tanjiro"))
	model.phase = "fight"
	model.fighters[0].facing = 1
	model.fighters[1].facing = -1
	for f in model.fighters:
		f.input.last_facing = f.facing
	return model

static func guard_command(guard: String) -> Dictionary:
	if guard.is_empty():
		return Combat.neutral()
	return {"x": 1, "y": 1 if guard == "crouch" else 0, "buttons": 0}

## Starts `move` for P1 on the ground at `distance` feet-to-feet from P2.
static func ground(character: String, move: Resource, guard: String = "", distance: float = 34.0) -> Dictionary:
	var model := duel(character)
	_place(model, distance)
	var defend := guard_command(guard)
	for n in range(2):
		model.step([Combat.neutral(), Combat.neutral()])
	model._begin_move(model.fighters[0], move)
	return measure(model, defend)

## Starts `move` for P1 `jump_tick` ticks into a forward jump.
static func air(character: String, move: Resource, jump_tick: int, guard: String = "stand", distance: float = 30.0) -> Dictionary:
	var model := duel(character)
	_place(model, distance)
	var defend := guard_command(guard)
	for n in range(2):
		model.step([Combat.neutral(), Combat.neutral()])
	var a = model.fighters[0]
	a.grounded = false
	a.flip_jump = true
	a.state = "air"
	a.air_ticks = jump_tick
	a.vy = JUMP_VY + GRAVITY * jump_tick
	a.y = Arena.FLOOR_Y - (-JUMP_VY * jump_tick - GRAVITY * 0.5 * jump_tick * (jump_tick + 1))
	a.vx = float(model.definition(a).walk_speed)
	model._begin_move(a, move)
	return measure(model, defend)

static func _place(model: Combat, distance: float) -> void:
	model.fighters[0].x = 480.0
	model.fighters[1].x = 480.0 + distance
	for f in model.fighters:
		f.previous_x = f.x

static func measure(model: Combat, defend: Dictionary) -> Dictionary:
	var a = model.fighters[0]
	var d = model.fighters[1]
	var hit := false
	var blocked := false
	var last_contact := -1
	var attacker: Array[bool] = []
	var defender: Array[bool] = []
	for tick in range(260):
		# Holding back walks away, so the defender guards only from the tick
		# before the attack becomes active (projectiles: from launch).
		var guarding: bool = a.move == null or a.move_frame + 1 >= a.move.startup
		model.step([Combat.neutral(), defend if guarding else Combat.neutral()])
		for event in model.events:
			if int(event.get("attacker", -1)) == 0 and event.type in ["hit", "block"]:
				hit = hit or event.type == "hit"
				blocked = blocked or event.type == "block"
				last_contact = tick
		attacker.append(a.move == null and a.stun == 0 and a.grounded and a.state != "landing")
		defender.append(d.stun == 0 and d.move == null and d.state not in ["hit", "block", "knockdown", "landing"])
		if tick > 60 and tick > last_contact + 40 and attacker[tick] and defender[tick]:
			break
	var result := {"contact": "hit" if hit else ("block" if blocked else ""), "advantage": null,
		"attacker_free": _settled(attacker, 0), "defender_free": _settled(defender, maxi(0, last_contact))}
	if last_contact >= 0 and int(result.attacker_free) >= 0 and int(result.defender_free) >= 0:
		result.advantage = int(result.defender_free) - int(result.attacker_free)
	return result

## First index from which every later flag is true, or -1.
static func _settled(flags: Array[bool], from: int) -> int:
	if flags.is_empty() or not flags.back():
		return -1
	var start := flags.size() - 1
	while start > from and flags[start - 1]:
		start -= 1
	return start

## Formula advantage for a single grounded contact on the first active frame.
static func formula(move: Resource, blocked: bool) -> int:
	return (move.blockstun if blocked else move.hitstun) + 1 - (move.active + move.recovery)
