class_name DuelCombat
extends RefCounted
## Pure, deterministic 60 Hz model. Contacts are collected before resolution.
const Fighter = preload("res://scripts/fighter_state.gd")
const Move = preload("res://scripts/move_data.gd")
const Catalog = preload("res://scripts/combat_catalog.gd")
const Commands = preload("res://scripts/command_recognizer.gd")
const Arena = preload("res://scripts/arena_rules.gd")
const FLOOR_Y: float = Arena.FLOOR_Y
const LEFT: float = Arena.LEFT
const RIGHT: float = Arena.RIGHT
const ROUND_TICKS := 3600
const BUFFER_TICKS := 6
var catalog := Catalog.new()
var fighters: Array = []
var moves: Dictionary = {}
var wins: Array[int] = [0, 0]
var phase: String = "intro"
var phase_frames: int = 90
var remaining: int = ROUND_TICKS
var hitstop: int = 0
var super_freeze: int = 0
var round_number: int = 1
var round_winner: int = -1
var match_winner: int = -1
var reason: String = ""
var events: Array[Dictionary] = []
var ticks: int = 0
var throw_link: Dictionary = {}
var projectiles: Array[Dictionary] = []
var next_instance: int = 1
var round_open_meter: Array[int] = [0, 0]
var practice: bool = false

func _init() -> void:
	moves = catalog.moves
	var ids: Array = catalog.characters.keys()
	assert(not ids.is_empty(), "No character definitions registered")
	new_match(ids[0], ids[mini(1, ids.size() - 1)])

static func neutral() -> Dictionary:
	return {"x": 0, "y": 0, "buttons": 0}

func definition(f: Fighter) -> Resource:
	return catalog.characters[f.character]

func new_match(p1: String, p2: String) -> void:
	assert(catalog.characters.has(p1) and catalog.characters.has(p2))
	wins = [0, 0]
	match_winner = -1
	fighters = [Fighter.new(), Fighter.new()]
	fighters[0].character = p1
	fighters[1].character = p2
	ticks = 0
	next_instance = 1
	reason = ""
	start_round([0, 0])

func start_round(meters: Array = []) -> void:
	var carry: Array = meters.duplicate() if not meters.is_empty() else [fighters[0].meter, fighters[1].meter]
	if meters.is_empty() and not reason.is_empty() and round_winner < 0:
		carry = round_open_meter.duplicate()
	for i in range(2):
		var fresh := Fighter.new()
		fresh.character = fighters[i].character
		fresh.slot = i
		fresh.x = Arena.CENTER + (-114.0 if i == 0 else 114.0)
		fresh.previous_x = fresh.x
		fresh.facing = 1 if i == 0 else -1
		fresh.input.last_facing = fresh.facing
		fresh.meter = clampi(int(carry[i]), 0, 300)
		round_open_meter[i] = fresh.meter
		fighters[i] = fresh
	remaining = ROUND_TICKS
	throw_link.clear()
	projectiles.clear()
	hitstop = 0
	super_freeze = 0
	phase = "fight" if practice else "intro"
	phase_frames = 90
	round_winner = -1
	reason = ""
	round_number = wins[0] + wins[1] + 1
	events.clear()

func clear_inputs(held: Array = []) -> void:
	for i in range(fighters.size()):
		fighters[i].input.reset(held[i] if held.size() > i else {})
		fighters[i].clear_buffer()

func step(commands: Array) -> void:
	events.clear()
	ticks += 1
	if phase == "match_end":
		return
	if phase == "intro":
		phase_frames -= 1
		if phase_frames <= 0:
			phase = "fight"
			clear_inputs(commands)
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
	_face_opponent()
	var samples: Array[Dictionary] = []
	for i in range(2):
		samples.append(fighters[i].input.sample(commands[i], fighters[i].facing))
		_read_command(fighters[i], samples[i])
	if not throw_link.is_empty():
		var victim: int = 1 - int(throw_link.attacker)
		if int(throw_link.frame) < 7 and (int(samples[victim].pressed) & Commands.D) != 0:
			_tech_throw()
			return
		if hitstop > 0:
			hitstop -= 1
			return
		if not practice:
			remaining = maxi(0, remaining - 1)
		_advance_throw()
		return
	if super_freeze > 0:
		super_freeze -= 1
		return
	if hitstop > 0:
		hitstop -= 1
		return
	if not practice:
		remaining = maxi(0, remaining - 1)
	_update_sequences()
	for f in fighters:
		_advance(f)
	_resolve_push()
	_constrain_separation()
	_face_opponent()
	if super_freeze > 0:
		return
	_advance_projectiles()
	var contacts: Array[Dictionary] = []
	for i in range(2):
		var a: Fighter = fighters[i]
		var d: Fighter = fighters[1 - i]
		if a.move == null or not a.hitbox().has_area():
			continue
		var segment: int = a.move.segment(a.move_frame)
		if segment in a.hit_registry or not a.hitbox().intersects(d.hurtbox()):
			continue
		if a.move.kind == "throw":
			if not _throwable(d):
				continue
		elif not _can_be_struck(d, a, a.move, a.attack_instance, false):
			continue
		a.hit_registry.append(segment)
		contacts.append(_contact(a, d, a.move, a.attack_instance, segment, false))
	for projectile in projectiles:
		if projectile.life <= 0:
			continue
		var a: Fighter = fighters[projectile.owner]
		var d: Fighter = fighters[1 - int(projectile.owner)]
		var move: Move = moves[projectile.move]
		var bounds := projectile_box(projectile)
		bounds = bounds.merge(Rect2(bounds.position - Vector2(projectile.vx, 0), bounds.size))
		if bounds.intersects(d.hurtbox()) and _can_be_struck(d, a, move, projectile.instance, true):
			contacts.append(_contact(a, d, move, projectile.instance, 0, true, projectile.facing))
			projectile.life = 0
	var struck: Array[int] = []
	for contact in contacts:
		if contact.move.kind != "throw":
			struck.append(1 - int(contact.attacker))
			_resolve_contact(contact)
	var grabs: Array[Dictionary] = []
	for contact in contacts:
		if contact.move.kind == "throw" and not int(contact.attacker) in struck and _throwable(fighters[1 - int(contact.attacker)]):
			grabs.append(contact)
	if grabs.size() == 2:
		_tech_throw()
	elif grabs.size() == 1:
		_start_throw(grabs[0])
	projectiles = projectiles.filter(func(p: Dictionary) -> bool: return int(p.life) > 0)
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
	if not practice and (fighters[0].hp <= 0 or fighters[1].hp <= 0 or remaining <= 0):
		_finish_round()

func _update_sequences() -> void:
	for i in range(2):
		var a: Fighter = fighters[i]
		var d: Fighter = fighters[1 - i]
		if d.stun == 0 and d.throw_role.is_empty():
			a.combo_active = false
			a.combo_instances.clear()
			a.chain_instances.clear()
			a.chain_normals.clear()
			a.chain_counts.clear()
			d.juggle_instances.clear()

func _face_opponent() -> void:
	for i in range(2):
		var f: Fighter = fighters[i]
		if f.move == null and f.stun == 0 and f.throw_role.is_empty() and f.dash_ticks == 0 and f.roll_frame < 0:
			var difference: float = fighters[1 - i].x - f.x
			if absf(difference) > 0.01:
				f.facing = 1 if difference > 0 else -1

func _read_command(f: Fighter, command: Dictionary) -> void:
	f.axis = command.x
	f.down = command.y > 0
	f.dash_request = command.dash
	if not f.throw_role.is_empty():
		f.clear_buffer()
		return
	if f.grounded and f.move == null and f.roll_frame < 0 and (f.stun == 0 or f.state == "block"):
		f.crouching = f.down
	if command.jump:
		f.jump_buffer = BUFFER_TICKS
	if not command.action.is_empty():
		f.buffer_action = command.action.duplicate()
		f.buffer = command.action.type
		f.buffer_left = BUFFER_TICKS

func _advance(f: Fighter) -> void:
	f.previous_x = f.x
	f.throw_invulnerable = maxi(0, f.throw_invulnerable - 1)
	if f.stun > 0:
		_stop_dash(f)
		f.stun -= 1
		if f.stun == 0:
			f.reaction = ""
			if f.state == "knockdown":
				f.throw_invulnerable = 8
			f.state = "idle" if f.grounded else "air"
		_integrate(f)
		return
	if f.roll_frame >= 0:
		if f.roll_frame < 20:
			f.x += f.roll_direction * 4.4
		f.roll_frame += 1
		if f.roll_frame >= 28:
			f.roll_frame = -1
			f.state = "idle"
		f.clear_buffer()
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
		f.vx = f.axis * definition(f).walk_speed
		f.jump_buffer = 0
		f.state = "air"
	if f.buffer_left > 0 and not f.buffer_action.is_empty():
		_try_action(f)
	if f.roll_frame >= 0:
		_integrate(f)
		return
	if f.move == null and f.grounded and not f.down and f.dash_ticks == 0 and f.dash_request != 0:
		f.dash_direction = f.dash_request
		f.dash_back = f.dash_direction * f.facing < 0
		f.dash_ticks = Arena.DASH_BACK_TICKS if f.dash_back else Arena.DASH_FORWARD_TICKS
		f.dash_frame = 0
		f.vx = 0
	f.dash_request = 0
	if f.move != null:
		if f.move_frame < f.move.startup:
			f.x += f.move.startup_travel * f.facing
		elif f.move_frame < f.move.startup + f.move.active:
			var segment := f.move.segment(f.move_frame)
			if segment >= 0 and f.move_frame == f.move.segment_start(segment):
				events.append({"type":"strike", "attacker":f.slot, "move":f.move.id, "instance":f.attack_instance, "segment":segment})
			f.x += f.move.travel * f.facing
			if f.move.projectile_speed != 0 and not f.projectile_spawned:
				_spawn_projectile(f)
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
			f.x += f.axis * definition(f).walk_speed
			f.state = "walk" if f.axis != 0 else "idle"
	_integrate(f)

func _try_action(f: Fighter) -> void:
	var request: Dictionary = f.buffer_action
	if request.type == "roll":
		if f.move == null and f.grounded:
			_stop_dash(f)
			f.roll_frame = 0
			f.roll_direction = f.facing * (-1 if request.x < 0 else 1)
			f.state = "roll"
			f.crouching = false
			f.vx = 0
			f.input.last_action = "后滚" if request.x < 0 else "前滚"
			f.clear_buffer()
			events.append({"type": "roll", "attacker": f.slot})
		return
	var selected: Move = _choose_move(f)
	if selected == null:
		return
	if f.move != null:
		if not f.connected or selected.kind not in f.move.cancel_targets:
			return
		if f.move_frame > f.move.startup + f.move.active + f.move.cancel_window:
			return
		if selected.is_super() and not f.confirmed:
			return
		if selected.kind == "skill" and not f.grounded:
			return
	if not f.grounded and selected.stance != "air" and not (selected.is_super() and f.move != null and f.confirmed):
		return
	if selected.stance != "air":
		if selected.id in f.chain_normals:
			return
		if selected.kind == "light" and int(f.chain_counts.get("light", 0)) >= 2:
			return
		if selected.kind in ["heavy", "skill", "super", "max"] and int(f.chain_counts.get(selected.kind, 0)) >= 1:
			return
	if selected.projectile_speed != 0:
		for p in projectiles:
			if int(p.owner) == f.slot:
				return
	if f.meter < selected.meter_cost:
		events.append({"type": "meter_empty", "attacker": f.slot, "cost": selected.meter_cost})
		f.clear_buffer()
		return
	_begin_move(f, selected)

func _choose_move(f: Fighter) -> Move:
	var request: Dictionary = f.buffer_action
	var data: Resource = definition(f)
	if request.type == "max":
		return data.motions.get("max")
	if request.type == "motion":
		return data.motions.get("super" if request.motion == "236236" else str(request.motion) + str(request.button))
	if request.type == "normal":
		var d: Fighter = fighters[1 - f.slot]
		if request.button == "D" and int(request.x) != 0 and int(request.y) == 0 and f.grounded and f.move == null and _throwable(d) and absf(f.x - d.x) <= 40:
			f.throw_back = request.x < 0
			return data.throw_move
		var stance := "j" if not f.grounded else ("2" if int(request.y) > 0 else "5")
		return data.normals.get(stance + str(request.button))
	return null

func _begin_move(f: Fighter, selected: Move) -> void:
	_stop_dash(f)
	f.move = selected
	f.attack_instance = next_instance
	next_instance += 1
	f.hit_registry.clear()
	f.projectile_spawned = false
	if not f.grounded:
		f.air_used_move = true
	f.move_frame = 0
	f.connected = false
	f.confirmed = false
	f.clear_buffer()
	f.state = "attack"
	f.crouching = selected.stance == "crouch"
	f.last_move = selected.id
	f.input.last_action = selected.display_name
	if f.grounded:
		f.vx = 0
	if selected.lift != 0:
		f.flip_jump = false
		f.grounded = false
		f.crouching = false
		f.vy = selected.lift
	if selected.meter_cost > 0:
		_change_meter(f, -selected.meter_cost)
		super_freeze = maxi(super_freeze, selected.freeze_frames)
		events.append({"type": "super", "attacker": f.slot, "move": selected.id})
	events.append({"type": "swing", "attacker": f.slot, "move": selected.id, "effect": selected.effect()})


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
			f.vy = 0
			f.vx = 0
			f.grounded = true
			f.flip_jump = false
			if f.knockdown_pending:
				f.knockdown_pending = false
				f.move = null
				f.state = "knockdown"
				f.stun = maxi(24, f.stun)
			elif f.move != null and f.move.stance == "air":
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

func _resolve_push() -> void:
	var a: Fighter = fighters[0]
	var b: Fighter = fighters[1]
	if not a.pushbox().has_area() or not b.pushbox().has_area() or not a.pushbox().intersects(b.pushbox()):
		return
	var left: Fighter = a if a.x < b.x or (a.x == b.x and a.previous_x <= b.previous_x) else b
	var right: Fighter = b if left == a else a
	_stop_dash(left)
	_stop_dash(right)
	var overlap: float = 26.0 - (right.x - left.x)
	left.x -= overlap / 2
	right.x += overlap / 2
	if left.x < LEFT:
		right.x += LEFT - left.x
		left.x = LEFT
	if right.x > RIGHT:
		left.x -= right.x - RIGHT
		right.x = RIGHT

func _can_block(f: Fighter, attack: Move) -> bool:
	if attack.level == "throw" or not f.grounded or f.move != null or f.hp <= 0 or f.dash_ticks > 0 or f.state == "dash" or f.roll_frame >= 0:
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

func _throwable(f: Fighter) -> bool:
	return f.grounded and f.stun == 0 and f.hp > 0 and f.throw_role.is_empty() and f.throw_invulnerable == 0

func _can_be_struck(d: Fighter, a: Fighter, _move: Move, instance: int, projectile: bool) -> bool:
	if d.strike_invulnerable():
		return false
	if d.move != null and d.move_frame < d.move.anti_air_until and not a.grounded and not projectile:
		return false
	if not d.grounded and not instance in d.juggle_instances and d.juggle_instances.size() >= 3:
		return false
	return true

func _contact(a: Fighter, d: Fighter, move: Move, instance: int, segment: int, projectile: bool, facing_override: int = 0) -> Dictionary:
	return {"attacker": a.slot, "move": move, "instance": instance, "segment": segment,
		"facing": a.facing if facing_override == 0 else facing_override,
		"blocked": _can_block(d, move), "projectile": projectile, "airborne": not d.grounded,
		"position": Vector2(d.x, d.y - 36)}

func _record_chain(a: Fighter, attack: Move, instance: int) -> void:
	if instance in a.chain_instances:
		return
	a.chain_instances.append(instance)
	if attack.stance != "air":
		a.chain_counts[attack.kind] = int(a.chain_counts.get(attack.kind, 0)) + 1
		if attack.kind in ["light", "heavy"]:
			a.chain_normals.append(attack.id)

func _resolve_contact(contact: Dictionary) -> void:
	var a: Fighter = fighters[contact.attacker]
	var d: Fighter = fighters[1 - int(contact.attacker)]
	var attack: Move = contact.move
	var instance: int = contact.instance
	var first_contact := not instance in a.chain_instances
	_record_chain(a, attack, instance)
	if a.attack_instance == instance:
		a.connected = true
		a.confirmed = a.confirmed or not bool(contact.blocked)
	_stop_dash(d)
	d.roll_frame = -1
	d.air_used_move = true
	d.throw_frame = 0
	d.reaction = ""
	d.move = null
	d.clear_buffer()
	if contact.blocked:
		d.state = "block"
		d.stun = attack.blockstun
		d.vx = contact.facing * attack.push * 0.55
		if attack.kind in ["skill", "super", "max"]:
			d.hp = maxi(1, d.hp - maxi(1, int(attack.segment_damage(contact.segment) * 0.08)))
		if first_contact:
			_change_meter(d, 3)
		events.append({"type": "block", "position": contact.position, "attacker": contact.attacker, "move":attack.id, "instance":instance, "segment":contact.segment})
	else:
		if not a.combo_active:
			a.combo = 0
			a.combo_damage = 0
			a.combo_instances.clear()
			a.combo_active = true
		if not a.combo_instances.has(instance):
			var index := a.combo_instances.size()
			var scale := 100 if attack.is_super() else maxi(40, 100 - index * 5)
			a.combo_instances[instance] = scale
		var damage := attack.segment_damage(contact.segment, int(a.combo_instances[instance]))
		damage = mini(d.hp, damage)
		d.hp = maxi(0, d.hp - damage)
		var knockdown := attack.knockdown and int(contact.segment) == attack.hit_count() - 1
		d.state = "knockdown" if knockdown and d.grounded else "hit"
		d.stun = 34 if d.state == "knockdown" else attack.hitstun
		d.knockdown_pending = knockdown and not d.grounded
		d.crouching = false
		d.vx = contact.facing * attack.push
		if not d.grounded:
			d.vy = minf(d.vy, -1.8)
			if not instance in d.juggle_instances:
				d.juggle_instances.append(instance)
		if d.hp == 0:
			d.state = "knockdown"
		a.combo += 1
		a.combo_damage += damage
		a.combo_display = 100
		if attack.kind in ["light", "heavy", "skill"]:
			_change_meter(a, int(damage * 0.25))
		_change_meter(d, int(damage * 0.15))
		events.append({"type": "hit", "position": contact.position, "attacker": contact.attacker,
			"damage": damage, "instance": instance, "segment": contact.segment, "move":attack.id})
	hitstop = maxi(hitstop, attack.hitstop)

func _change_meter(f: Fighter, amount: int) -> void:
	var old := f.meter
	f.meter = clampi(f.meter + amount, 0, 300)
	if f.meter != old:
		events.append({"type": "meter", "attacker": f.slot, "amount": f.meter - old, "value": f.meter})

func _spawn_projectile(f: Fighter) -> void:
	f.projectile_spawned = true
	projectiles.append({"owner": f.slot, "instance": f.attack_instance, "move": f.move.id,
		"x": f.x + f.facing * 27, "y": f.y - 32, "vx": f.move.projectile_speed * f.facing,
		"facing": f.facing, "life": f.move.projectile_lifetime})
	events.append({"type": "projectile", "attacker": f.slot, "move": f.move.id})

func projectile_box(projectile: Dictionary) -> Rect2:
	var rect: Rect2 = moves[projectile.move].projectile_box
	if int(projectile.facing) < 0:
		rect.position.x = -rect.end.x
	rect.position += Vector2(projectile.x, projectile.y)
	return rect

func _advance_projectiles() -> void:
	for p in projectiles:
		p.x += p.vx
		p.life -= 1
		if p.x < LEFT - 40 or p.x > RIGHT + 40:
			p.life = 0
	for i in range(projectiles.size()):
		for j in range(i + 1, projectiles.size()):
			var a: Dictionary = projectiles[i]
			var b: Dictionary = projectiles[j]
			if a.life > 0 and b.life > 0 and a.owner != b.owner and projectile_box(a).intersects(projectile_box(b)):
				a.life = 0
				b.life = 0
				events.append({"type": "clash", "position": Vector2((a.x + b.x) * 0.5, a.y)})

func _finish_round() -> void:
	throw_link.clear()
	projectiles.clear()
	for f in fighters:
		_stop_dash(f)
		f.throw_role = ""
		f.roll_frame = -1
		f.clear_buffer()
		f.input.reset()
		f.juggle_instances.clear()
		f.chain_normals.clear()
		f.chain_counts.clear()
		f.chain_instances.clear()
		f.combo_active = false
		f.combo_instances.clear()
	phase = "round_end"
	phase_frames = 125
	hitstop = 0
	super_freeze = 0
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
		data.append(f.snapshot())
	return {"fighters": data, "phase": phase, "phase_frames": phase_frames, "remaining": remaining,
		"wins": wins.duplicate(), "hitstop": hitstop, "super_freeze": super_freeze, "ticks": ticks,
		"round_number": round_number, "round_winner": round_winner, "match_winner": match_winner,
		"reason": reason, "next_instance": next_instance, "practice": practice,
		"round_open_meter": round_open_meter.duplicate(), "projectiles": projectiles.duplicate(true),
		"throw_link": throw_link.duplicate(true)}

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
	var d: Fighter = fighters[1 - int(contact.attacker)]
	var direction: int = contact.facing
	var destination := direction * (-1 if a.throw_back else 1)
	var final_x := clampf(a.x, LEFT + (Arena.THROW_DISTANCE if destination < 0 else 0),
		RIGHT - (Arena.THROW_DISTANCE if destination > 0 else 0))
	throw_link = {"attacker": a.slot, "direction": direction, "destination": destination, "frame": 0,
		"move": contact.move.id, "start_a": a.x, "start_d": d.x, "final_a": final_x,
		"final_d": final_x + destination * Arena.THROW_DISTANCE}
	for f in [a, d]:
		_stop_dash(f)
		f.move = null
		f.roll_frame = -1
		f.vx = 0
		f.vy = 0
		f.stun = 0
		f.clear_buffer()
		f.input.pending.clear()
		f.crouching = false
		f.flip_jump = false
		f.knockdown_pending = false
		f.throw_frame = 0
		f.throw_facing = direction
		f.throw_back = a.throw_back
		f.reaction = ""
	a.throw_role = "thrower"
	d.throw_role = "victim"
	a.state = "throwing"
	d.state = "thrown"
	events.append({"type": "grab", "attacker": a.slot, "position": Vector2(d.x, d.y - 35)})

func _tech_throw() -> void:
	for f in fighters:
		_stop_dash(f)
		f.move = null
		f.throw_role = ""
		f.throw_frame = 0
		f.roll_frame = -1
		f.y = FLOOR_Y
		f.grounded = true
		f.vy = 0
		f.state = "block"
		f.reaction = "throw_tech"
		f.stun = 16
		f.throw_invulnerable = 8
		f.vx = -f.facing * 3.0
		f.clear_buffer()
		f.input.pending.clear()
	throw_link.clear()
	hitstop = 5
	events.append({"type": "clash", "position": Vector2((fighters[0].x + fighters[1].x) / 2, FLOOR_Y - 35)})
	events.append({"type": "throw_tech", "position": Vector2((fighters[0].x + fighters[1].x) / 2, FLOOR_Y - 35)})

func _advance_throw() -> void:
	throw_link.frame += 1
	var frame: int = throw_link.frame
	var a: Fighter = fighters[throw_link.attacker]
	var d: Fighter = fighters[1 - int(throw_link.attacker)]
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
		var control := Vector2(4 * throw_link.destination, -124)
		var end := Vector2(Arena.THROW_DISTANCE * throw_link.destination, 0)
		var offset := start.lerp(control, progress).lerp(control.lerp(end, progress), progress)
		d.x = a.x + offset.x
		d.y = FLOOR_Y + offset.y
	d.grounded = frame >= Arena.THROW_IMPACT_TICK
	if frame == Arena.THROW_IMPACT_TICK:
		var attack: Move = moves[throw_link.move]
		var damage := mini(d.hp, attack.damage)
		d.hp = maxi(0, d.hp - damage)
		d.state = "knockdown"
		d.stun = 34
		hitstop = attack.hitstop
		a.combo = 1
		a.combo_damage = damage
		a.combo_display = 100
		_change_meter(d, int(damage * 0.15))
		events.append({"type": "throw", "attacker": a.slot, "damage": damage,
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
		if not practice and (a.hp <= 0 or d.hp <= 0 or remaining <= 0):
			_finish_round()
