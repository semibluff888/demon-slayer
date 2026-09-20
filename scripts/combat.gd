class_name DuelCombat
extends RefCounted
## Pure frame-stepped combat. No scene nodes, rendering delta, wall clocks or
## Input calls are used here. Both contacts are captured before either resolves.

const Fighter = preload("res://scripts/fighter_state.gd")
const Move = preload("res://scripts/move_data.gd")
const Arena = preload("res://scripts/arena_rules.gd")
const FLOOR_Y: float = Arena.FLOOR_Y
const LEFT: float = Arena.LEFT
const RIGHT: float = Arena.RIGHT
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
var throw_link: Dictionary = {}

func _init() -> void:
	for id in ["stand_light", "stand_heavy", "crouch_light", "crouch_heavy",
		"air_light", "air_heavy", "throw", "water_slash", "water_wheel", "iai", "thunder"]:
		moves[id] = load("res://moves/%s.tres" % id)
	new_match("tanjiro", "zenitsu")

static func neutral() -> Dictionary:
	return {"x": 0, "down": false, "jump": false, "light": false,
		"heavy": false, "skill": false, "throw": false, "dash": 0}

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
		fresh.x = Arena.CENTER + (-114.0 if i == 0 else 114.0)
		fresh.previous_x = fresh.x
		fresh.facing = 1 if i == 0 else -1
		fighters[i] = fresh
	remaining = ROUND_TICKS
	throw_link.clear()
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
			f.previous_x = f.x
			_integrate(f)
		_constrain_separation()
		phase_frames -= 1
		if phase_frames <= 0:
			if wins.max() >= 2:
				match_winner = 0 if wins[0] >= 2 else 1
				phase = "match_end"
			else:
				start_round()
		return
	if not throw_link.is_empty():
		if hitstop > 0:
			hitstop -= 1
			return
		remaining = maxi(0, remaining - 1)
		_advance_throw()
		return
	_face_opponent()
	for i in range(2):
		_read_command(fighters[i], commands[i])
	if hitstop > 0:
		hitstop -= 1
		return
	remaining = maxi(0, remaining - 1)
	for f in fighters:
		_advance(f)
	_resolve_push()
	_constrain_separation()
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
		# Strikes collected on this frame interrupt a grab, independent of slot order.
		var struck: Array[int] = []
		for contact in contacts:
			if contact.move.kind != "throw":
				struck.append(1 - int(contact.attacker))
				_resolve_contact(contact)
		for contact in contacts:
			if contact.move.kind == "throw" and not int(contact.attacker) in struck:
				_start_throw(contact)
	if not throw_link.is_empty():
		return
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
		if f.move == null and f.stun == 0 and f.throw_role.is_empty() and f.dash_ticks == 0:
			var difference: float = fighters[1 - i].x - f.x
			if absf(difference) > 0.01:
				f.facing = 1 if difference > 0 else -1

func _read_command(f: Fighter, command: Dictionary) -> void:
	f.axis = clampi(int(command.get("x", 0)), -1, 1)
	f.down = command.get("down", false)
	f.dash_request = clampi(int(command.get("dash", 0)), -1, 1)
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
		_stop_dash(f)
		f.stun -= 1
		if f.stun == 0:
			f.state = "idle" if f.grounded else "air"
		_integrate(f)
		return
	if f.dash_ticks > 0 and (f.down or (f.axis != 0 and f.axis != f.dash_direction)):
		_stop_dash(f)
	if f.move == null and f.grounded and f.jump_buffer > 0:
		_stop_dash(f)
		f.air_ticks = 0
		f.air_used_move = false
		f.flip_jump = true
		f.jump_facing = f.facing
		f.jump_back = f.axis * f.facing < 0
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
	if f.move == null and f.grounded and not f.down and f.dash_ticks == 0 and f.dash_request != 0:
		f.dash_direction = f.dash_request
		f.dash_back = f.dash_direction * f.facing < 0
		f.dash_ticks = Arena.DASH_BACK_TICKS if f.dash_back else Arena.DASH_FORWARD_TICKS
		f.dash_frame = 0
		f.vx = 0
	f.dash_request = 0
	if f.move != null:
		if f.move_frame >= f.move.startup and f.move_frame < f.move.startup + f.move.active:
			f.x += f.move.travel * f.facing
	elif f.dash_ticks > 0:
		f.state = "dash"
		f.x += f.dash_direction * (Arena.DASH_BACK_SPEED if f.dash_back else Arena.DASH_FORWARD_SPEED)
		f.dash_frame += 1
		f.dash_ticks -= 1
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
		f.air_ticks += 1
		if f.state == "hit":
			f.vx *= 0.94
		f.vy += 0.42
		f.y += f.vy
		if f.y >= FLOOR_Y:
			f.y = FLOOR_Y
			f.vy = 0.0
			f.vx = 0.0
			f.grounded = true
			f.flip_jump = false
			if f.move != null and f.move.id.begins_with("air_"):
				f.move = null
				f.stun = maxi(f.stun, 5)
				f.state = "landing"
			elif f.stun == 0 and f.move == null:
				f.state = "idle"
	var bounded := clampf(f.x, LEFT, RIGHT)
	if not is_equal_approx(bounded, f.x):
		_stop_dash(f)
		f.vx = 0
	f.x = bounded

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
	_stop_dash(f)
	f.move = selected
	if not f.grounded:
		f.air_used_move = true
	f.move_frame = 0
	f.connected = false
	f.buffer_left = 0
	f.buffer = ""
	f.state = "attack"
	if f.grounded:
		f.vx = 0.0
	if selected.lift != 0:
		f.flip_jump = false
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
	_stop_dash(left)
	_stop_dash(right)
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
	if attack.level == "throw" or not f.grounded or f.move != null or f.hp <= 0 or f.dash_ticks > 0 or f.state == "dash":
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
	_stop_dash(d)
	d.air_used_move = true
	d.throw_frame = 0
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
	throw_link.clear()
	for f in fighters:
		_stop_dash(f)
		f.throw_role = ""
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
			f.stun, f.move.id if f.move != null else "", f.move_frame, f.buffer_left,
			f.dash_direction, f.dash_ticks, f.dash_frame, f.dash_back,
			f.air_ticks, f.air_used_move, f.jump_facing, f.jump_back, f.flip_jump,
			f.throw_role, f.throw_frame, f.throw_facing])
	return {"fighters": data, "phase": phase, "remaining": remaining,
		"wins": wins.duplicate(), "hitstop": hitstop, "ticks": ticks, "throw_link": throw_link.duplicate(true)}

func _stop_dash(f: Fighter) -> void:
	f.dash_ticks = 0
	f.dash_request = 0
	if f.state == "dash":
		f.state = "idle"

func _constrain_separation() -> void:
	var left: Fighter = fighters[0] if fighters[0].x <= fighters[1].x else fighters[1]
	var right: Fighter = fighters[1] if left == fighters[0] else fighters[0]
	var excess := right.x - left.x - Arena.MAX_SEPARATION
	if excess <= 0:
		return
	# Undo only outward displacement. A stationary opponent is never dragged.
	var outward_left := maxf(0, left.previous_x - left.x)
	var outward_right := maxf(0, right.x - right.previous_x)
	var take_left := minf(excess * 0.5, outward_left)
	var take_right := minf(excess * 0.5, outward_right)
	var rest := excess - take_left - take_right
	var extra := minf(rest, outward_left - take_left)
	take_left += extra
	rest -= extra
	extra = minf(rest, outward_right - take_right)
	take_right += extra
	rest -= extra
	# Only externally assigned invalid positions need symmetric projection.
	take_left += rest * 0.5
	take_right += rest * 0.5
	left.x += take_left
	right.x -= take_right
	if take_left > 0:
		_stop_dash(left)
		left.vx = maxf(0, left.vx)
	if take_right > 0:
		_stop_dash(right)
		right.vx = minf(0, right.vx)

func _start_throw(contact: Dictionary) -> void:
	var a: Fighter = fighters[contact.attacker]
	var d: Fighter = fighters[1 - contact.attacker]
	var direction: int = contact.facing
	var final_x := clampf(a.x, LEFT + (Arena.THROW_DISTANCE if direction > 0 else 0.0),
		RIGHT - (Arena.THROW_DISTANCE if direction < 0 else 0.0))
	throw_link = {"attacker": a.slot, "direction": direction, "frame": 0,
		"start_a": a.x, "start_d": d.x, "final_a": final_x,
		"final_d": final_x - direction * Arena.THROW_DISTANCE}
	for f in [a, d]:
		_stop_dash(f)
		f.move = null
		f.vx = 0
		f.vy = 0
		f.stun = 0
		f.buffer_left = 0
		f.buffer = ""
		f.jump_buffer = 0
		f.crouching = false
		f.flip_jump = false
		f.throw_frame = 0
		f.throw_facing = direction
	a.throw_role = "thrower"
	d.throw_role = "victim"
	a.state = "throwing"
	d.state = "thrown"
	events.append({"type": "grab", "attacker": a.slot, "position": Vector2(d.x, d.y - 35)})

func _advance_throw() -> void:
	throw_link.frame += 1
	var frame: int = throw_link.frame
	var a: Fighter = fighters[throw_link.attacker]
	var d: Fighter = fighters[1 - throw_link.attacker]
	var direction: int = throw_link.direction
	a.previous_x = a.x
	d.previous_x = d.x
	a.x = lerpf(throw_link.start_a, throw_link.final_a, minf(1, frame / 8.0))
	a.y = FLOOR_Y
	a.grounded = true
	for f in [a, d]:
		f.throw_frame = frame
	if frame <= 4:
		d.x = lerpf(throw_link.start_d, a.x + direction * 18, frame / 4.0)
		d.y = FLOOR_Y - frame * 5
	else:
		var progress := clampf((frame - 4) / 16.0, 0, 1)
		var start := Vector2(18 * direction, -20)
		var control := Vector2(-4 * direction, -124)
		var end := Vector2(-Arena.THROW_DISTANCE * direction, 0)
		var offset := start.lerp(control, progress).lerp(control.lerp(end, progress), progress)
		d.x = a.x + offset.x
		d.y = FLOOR_Y + offset.y
	d.grounded = frame >= Arena.THROW_IMPACT_TICK
	if frame == Arena.THROW_IMPACT_TICK:
		var attack: Move = moves.throw
		d.hp = maxi(0, d.hp - attack.damage)
		d.state = "knockdown"
		d.stun = 34
		hitstop = attack.hitstop
		a.combo = 1
		a.combo_display = 85
		events.append({"type": "throw", "attacker": a.slot, "damage": attack.damage,
			"position": Vector2(d.x, FLOOR_Y - 5)})
	if frame >= Arena.THROW_TICKS:
		a.x = throw_link.final_a
		d.x = throw_link.final_d
		a.state = "idle"
		d.state = "knockdown"
		a.throw_role = ""
		d.throw_role = ""
		d.stun = 24
		throw_link.clear()
		_face_opponent()
		if a.hp <= 0 or d.hp <= 0 or remaining <= 0:
			_finish_round()
