class_name DuelCombat
extends RefCounted
## Pure frame-stepped combat. No scene nodes, rendering delta, wall clocks or
## Input calls are used here. Both contacts are captured before either resolves.

const Fighter = preload("res://scripts/fighter_state.gd")
const Move = preload("res://scripts/move_data.gd")
const FLOOR_Y: float = 286.0
const LEFT: float = 28.0
const RIGHT: float = 612.0
const ROUND_TICKS: int = 3600
const BUFFER_TICKS: int = 6
var fighters: Array = []
var moves: Dictionary = {}
var wins: Array[int] = [0, 0]
var phase: String = "intro"
var phase_frames: int = 90
var remaining: int = ROUND_TICKS
var hitstop: int = 0
var round_number: int = 1
var round_winner: int = -1
var match_winner: int = -1
var reason: String = ""
var events: Array[Dictionary] = []
var ticks: int = 0

func _init() -> void:
	for id in ["stand_light", "stand_heavy", "crouch_light", "crouch_heavy",
		"air_light", "air_heavy", "throw", "water_slash", "water_wheel", "iai", "thunder"]:
		moves[id] = load("res://moves/%s.tres" % id)
	new_match("tanjiro", "zenitsu")

static func neutral() -> Dictionary:
	return {"x": 0, "down": false, "jump": false, "light": false,
		"heavy": false, "skill": false, "throw": false}

func new_match(p1: String, p2: String) -> void:
	wins = [0, 0]
	match_winner = -1
	fighters = [Fighter.new(), Fighter.new()]
	fighters[0].character = p1
	fighters[1].character = p2
	ticks = 0
	start_round()

func start_round() -> void:
	for i in range(2):
		var old_character: String = fighters[i].character
		var fresh := Fighter.new()
		fresh.character = old_character
		fresh.slot = i
		fresh.x = 206.0 if i == 0 else 434.0
		fresh.previous_x = fresh.x
		fresh.facing = 1 if i == 0 else -1
		fighters[i] = fresh
	remaining = ROUND_TICKS
	hitstop = 0
	phase = "intro"
	phase_frames = 90
	round_winner = -1
	reason = ""
	round_number = wins[0] + wins[1] + 1
	events.clear()

func step(commands: Array) -> void:
	events.clear()
	ticks += 1
	if phase == "match_end":
		return
	if phase == "intro":
		phase_frames -= 1
		if phase_frames <= 0:
			phase = "fight"
			events.append({"type": "fight"})
		return
	if phase == "round_end":
		for f in fighters:
			_integrate(f)
		phase_frames -= 1
		if phase_frames <= 0:
			if wins.max() >= 2:
				match_winner = 0 if wins[0] >= 2 else 1
				phase = "match_end"
			else:
				start_round()
		return
	_face_opponent()
	for i in range(2):
		_read_command(fighters[i], commands[i])
	if hitstop > 0:
		hitstop -= 1
		return
	remaining -= 1
	for f in fighters:
		_advance(f)
	_resolve_push()
	_face_opponent()
	var contacts: Array[Dictionary] = []
	for i in range(2):
		var a: Fighter = fighters[i]
		var d: Fighter = fighters[1 - i]
		if a.move == null or a.connected or not a.hitbox().has_area():
			continue
		if not a.hitbox().intersects(d.hurtbox()):
			continue
		if a.move.kind == "throw" and (not d.grounded or d.stun > 0):
			continue
		contacts.append({"attacker": i, "move": a.move, "facing": a.facing,
			"blocked": _can_block(d, a.move), "was_stunned": d.state == "hit" or d.state == "knockdown",
			"position": Vector2(d.x, d.y - 36)})
		# Mark before resolution so interruption cannot erase a collected strike.
		a.connected = true
	if contacts.size() == 2 and contacts[0].move.kind == "throw" and contacts[1].move.kind == "throw":
		for f in fighters:
			f.move = null
			f.state = "block"
			f.stun = 16
			f.vx = -f.facing * 3.0
		hitstop = 5
		events.append({"type": "clash", "position": Vector2((fighters[0].x + fighters[1].x) / 2, FLOOR_Y - 35)})
	else:
		for contact in contacts:
			_resolve_contact(contact)
	for f in fighters:
		if f.move != null:
			f.move_frame += 1
			if f.move_frame >= f.move.total_frames():
				f.move = null
				f.state = "idle" if f.grounded else "air"
		f.buffer_left = maxi(0, f.buffer_left - 1)
		f.jump_buffer = maxi(0, f.jump_buffer - 1)
		f.combo_display = maxi(0, f.combo_display - 1)
	if fighters[0].hp <= 0 or fighters[1].hp <= 0 or remaining <= 0:
		_finish_round()

func _face_opponent() -> void:
	for i in range(2):
		var f: Fighter = fighters[i]
		if f.move == null and f.stun == 0:
			var difference: float = fighters[1 - i].x - f.x
			if absf(difference) > 0.01:
				f.facing = 1 if difference > 0 else -1

func _read_command(f: Fighter, command: Dictionary) -> void:
	f.axis = clampi(int(command.get("x", 0)), -1, 1)
	f.down = command.get("down", false)
	if f.grounded and f.move == null and (f.stun == 0 or f.state == "block"):
		f.crouching = f.down
	if command.get("jump", false):
		f.jump_buffer = BUFFER_TICKS
	for action in ["throw", "skill", "heavy", "light"]:
		if command.get(action, false):
			f.buffer = action
			f.buffer_forward = f.axis == f.facing
			f.buffer_left = BUFFER_TICKS
			break

func _advance(f: Fighter) -> void:
	f.previous_x = f.x
	if f.stun > 0:
		f.stun -= 1
		if f.stun == 0:
			f.state = "idle" if f.grounded else "air"
		_integrate(f)
		return
	if f.move == null and f.grounded and f.jump_buffer > 0:
		f.grounded = false
		f.crouching = false
		f.vy = -7.8
		f.vx = f.axis * _walk_speed(f)
		f.jump_buffer = 0
		f.state = "air"
	if f.buffer_left > 0:
		var selected: Move = _choose_move(f)
		if selected != null:
			var can_start: bool = f.move == null
			if f.move != null:
				can_start = f.connected and selected.rank() == f.move.rank() + 1 and selected.kind != "throw" \
					and f.move_frame <= f.move.startup + f.move.active + f.move.cancel_window
			if can_start:
				_begin_move(f, selected)
	if f.move != null:
		if f.move_frame >= f.move.startup and f.move_frame < f.move.startup + f.move.active:
			f.x += f.move.travel * f.facing
	elif f.grounded:
		f.crouching = f.down
		if f.crouching:
			f.state = "crouch"
		else:
			f.x += f.axis * _walk_speed(f)
			f.state = "walk" if f.axis != 0 else "idle"
	_integrate(f)

func _integrate(f: Fighter) -> void:
	f.x += f.vx
	if f.grounded:
		f.vx *= 0.76
	else:
		if f.state == "hit":
			f.vx *= 0.94
		f.vy += 0.42
		f.y += f.vy
		if f.y >= FLOOR_Y:
			f.y = FLOOR_Y
			f.vy = 0.0
			f.vx = 0.0
			f.grounded = true
			if f.move != null and f.move.id.begins_with("air_"):
				f.move = null
				f.stun = maxi(f.stun, 5)
				f.state = "landing"
			elif f.stun == 0 and f.move == null:
				f.state = "idle"
	f.x = clampf(f.x, LEFT, RIGHT)

func _walk_speed(f: Fighter) -> float:
	return 2.15 if f.character == "tanjiro" else 2.45

func _choose_move(f: Fighter) -> Move:
	if f.buffer == "throw":
		return moves["throw"] if f.grounded and not f.crouching else null
	if f.buffer == "skill":
		if not f.grounded:
			return null
		if f.character == "tanjiro":
			return moves["water_wheel" if f.buffer_forward else "water_slash"]
		return moves["thunder" if f.buffer_forward else "iai"]
	if f.buffer in ["light", "heavy"]:
		var stance := "air" if not f.grounded else ("crouch" if f.crouching else "stand")
		return moves[stance + "_" + f.buffer]
	return null

func _begin_move(f: Fighter, selected: Move) -> void:
	f.move = selected
	f.move_frame = 0
	f.connected = false
	f.buffer_left = 0
	f.buffer = ""
	f.state = "attack"
	if f.grounded:
		f.vx = 0.0
	if selected.lift != 0:
		f.grounded = false
		f.crouching = false
		f.vy = selected.lift
	events.append({"type": "swing", "attacker": f.slot, "move": selected.id})

func _resolve_push() -> void:
	var a: Fighter = fighters[0]
	var b: Fighter = fighters[1]
	if not a.pushbox().intersects(b.pushbox()):
		return
	var left: Fighter = a if a.x < b.x or (a.x == b.x and a.previous_x <= b.previous_x) else b
	var right: Fighter = b if left == a else a
	var overlap: float = 26.0 - (right.x - left.x)
	left.x -= overlap / 2.0
	right.x += overlap / 2.0
	if left.x < LEFT:
		right.x += LEFT - left.x
		left.x = LEFT
	if right.x > RIGHT:
		left.x -= right.x - RIGHT
		right.x = RIGHT

func _can_block(f: Fighter, attack: Move) -> bool:
	if attack.level == "throw" or not f.grounded or f.move != null or f.hp <= 0:
		return false
	if f.stun > 0 and f.state != "block":
		return false
	if f.axis != -f.facing:
		return false
	if attack.level == "low":
		return f.crouching
	if attack.level == "high":
		return not f.crouching
	return true

func _resolve_contact(contact: Dictionary) -> void:
	var a: Fighter = fighters[contact.attacker]
	var d: Fighter = fighters[1 - contact.attacker]
	var attack: Move = contact.move
	var blocked: bool = contact.blocked
	d.move = null
	d.buffer_left = 0
	d.jump_buffer = 0
	if blocked:
		d.state = "block"
		d.stun = attack.blockstun
		d.vx = contact.facing * attack.push * 0.55
		if attack.kind == "skill":
			d.hp = maxi(1, d.hp - int(attack.damage * 0.08))
		events.append({"type": "block", "position": contact.position, "attacker": contact.attacker})
	else:
		d.hp = maxi(0, d.hp - attack.damage)
		d.state = "knockdown" if attack.knockdown and d.grounded else "hit"
		d.stun = 34 if d.state == "knockdown" else attack.hitstun
		d.crouching = false
		d.vx = contact.facing * attack.push
		if not d.grounded:
			d.vy = minf(d.vy, -1.8)
		if d.hp == 0:
			d.state = "knockdown"
		a.combo = a.combo + 1 if contact.was_stunned else 1
		a.combo_display = 85
		events.append({"type": "throw" if attack.kind == "throw" else "hit",
			"position": contact.position, "attacker": contact.attacker, "damage": attack.damage})
	hitstop = maxi(hitstop, attack.hitstop)

func _finish_round() -> void:
	phase = "round_end"
	phase_frames = 125
	hitstop = 0
	var a: int = fighters[0].hp
	var b: int = fighters[1].hp
	if a == b:
		round_winner = -1
		reason = "DOUBLE K.O." if a == 0 else "DRAW"
	else:
		round_winner = 0 if a > b else 1
		wins[round_winner] += 1
		reason = "K.O." if mini(a, b) == 0 else "TIME UP"
	events.append({"type": "round_end"})

func snapshot() -> Dictionary:
	var data: Array = []
	for f in fighters:
		data.append([f.character, f.x, f.y, f.vx, f.vy, f.hp, f.facing, f.state,
			f.stun, f.move.id if f.move != null else "", f.move_frame, f.buffer_left])
	return {"fighters": data, "phase": phase, "remaining": remaining,
		"wins": wins.duplicate(), "hitstop": hitstop, "ticks": ticks}
