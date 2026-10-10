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
const WIN_RECOVERY_BASE := 100
const WIN_RECOVERY_TIME_BONUS := 100
const BUFFER_TICKS := 6
const SUPER_BUFFER_TICKS := 10
const Flow = preload("res://scripts/round_flow.gd")
var catalog := Catalog.new()
var fighters: Array = []
var moves: Dictionary = {}
var wins: Array[int] = [0, 0]
var phase: String = "intro"
var phase_frames: int = Flow.OPENING
var go_frames: int = 0
var outro_ticks: int = 0
var outro_landed_at: Array[float] = [0.0, 0.0]
var outro_paths: Array[Dictionary] = [{}, {}]
var victory_at: int = Flow.RESULT_AT
var outro_tail_until: float = 0.0
# Starts at a lethal throw's impact, while scoring still waits for the linked landing.
var lethal_throw_ticks: int = -1
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
var round_open_hp: Array[int] = [1000, 1000]
var practice: bool = false
var awakening_infinite: bool = false
var pending_healing: Array[int] = [0, 0]
# The application supplies only playable assets; headless combat stays opt-in.
var cinematic_moves: Dictionary = {}
var cinematic: Dictionary = {}
var cinematic_victory_form_slot: int = -1
const AWAKENING_COST := 200
const AWAKENING_FREEZE := 12

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
	var continuing := meters.is_empty() and not reason.is_empty() and not practice
	var opening_hp: Array[int] = [1000, 1000]
	if continuing and round_winner >= 0:
		# KOF-style survival recovery: 10% base plus up to 10% for time left.
		var recovery := WIN_RECOVERY_BASE + floori(float(WIN_RECOVERY_TIME_BONUS * clampi(remaining, 0, ROUND_TICKS)) / ROUND_TICKS)
		opening_hp[round_winner] = clampi(fighters[round_winner].hp + recovery, 1, 1000)
	elif continuing:
		carry = round_open_meter.duplicate()
		opening_hp = round_open_hp.duplicate()
	for i in range(2):
		var fresh := Fighter.new()
		fresh.character = fighters[i].character
		fresh.slot = i
		fresh.x = Arena.CENTER + (-114.0 if i == 0 else 114.0)
		fresh.previous_x = fresh.x
		fresh.facing = 1 if i == 0 else -1
		fresh.input.last_facing = fresh.facing
		fresh.meter = clampi(int(carry[i]), 0, 300)
		fresh.hp = opening_hp[i]
		round_open_meter[i] = fresh.meter
		round_open_hp[i] = fresh.hp
		fighters[i] = fresh
	cinematic.clear()
	cinematic_victory_form_slot = -1
	remaining = ROUND_TICKS
	throw_link.clear()
	projectiles.clear()
	hitstop = 0
	super_freeze = 0
	phase = "fight" if practice else "intro"
	phase_frames = Flow.OPENING if not practice else 0
	go_frames = 0
	outro_ticks = 0
	outro_landed_at.assign([0.0, 0.0])
	outro_paths.assign([{}, {}])
	victory_at = Flow.RESULT_AT
	outro_tail_until = 0.0
	lethal_throw_ticks = -1
	round_winner = -1
	reason = ""
	round_number = wins[0] + wins[1] + 1
	pending_healing.assign([0, 0])
	events.clear()

func clear_inputs(held: Array = []) -> void:
	for i in range(fighters.size()):
		fighters[i].input.reset(held[i] if held.size() > i else {})
		fighters[i].clear_buffer()

func step(commands: Array) -> void:
	events.clear()
	if cinematic_blocks_combat():
		return
	ticks += 1
	if phase == "match_end":
		return
	if go_frames > 0:
		go_frames -= 1
	if phase == "intro":
		phase_frames -= 1
		if phase_frames > 0:
			clear_inputs(commands)
			if phase_frames == Flow.READY:
				events.append({"type": "ready"})
			return
		# The previous locked tick seeded held buttons. A NEW edge on GO works.
		phase = "fight"
		go_frames = Flow.GO
		events.append({"type": "fight"})
	if phase == "round_end":
		_advance_outro()
		return
	if lethal_throw_ticks >= 0:
		clear_inputs(commands)
		_advance_lethal_throw()
		return
	_face_opponent()
	var samples: Array[Dictionary] = []
	for i in range(2):
		samples.append(fighters[i].input.sample(commands[i], fighters[i].facing))
		if cinematic_holds_victim(i):
			fighters[i].clear_buffer()
		else:
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
		_tick_awakenings()
		return
	if super_freeze > 0:
		super_freeze -= 1
		return
	if hitstop > 0:
		hitstop -= 1
		return
	# Resolve both activation requests before either fighter advances.
	var activated := false
	for f in fighters:
		if f.buffer_left > 0 and f.buffer_action.get("type", "") == "awaken":
			activated = _try_awaken(f) or activated
	if activated:
		return
	if not practice:
		remaining = maxi(0, remaining - 1)
	_update_sequences()
	for f in fighters:
		if not cinematic_holds_victim(f.slot):
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
			contacts.append(_contact(a, d, move, projectile.instance, 0, true, projectile.facing, int(projectile.get("damage_percent", 100))))
			projectile.life = 0
	var struck: Array[int] = []
	for contact in contacts:
		if contact.move.kind != "throw":
			struck.append(1 - int(contact.attacker))
			_resolve_contact(contact)
	_flush_awakening_healing()
	var grabs: Array[Dictionary] = []
	for contact in contacts:
		if contact.move.kind == "throw" and not int(contact.attacker) in struck and _throwable(fighters[1 - int(contact.attacker)]):
			grabs.append(contact)
	if grabs.size() == 2:
		_tech_throw()
	elif grabs.size() == 1:
		_start_throw(grabs[0])
	projectiles = projectiles.filter(func(p: Dictionary) -> bool: return int(p.life) > 0)
	# Resolve trades first. Interrupted or defeated attackers cannot capture a victim.
	for contact in contacts:
		var actor: Fighter = fighters[contact.attacker]
		if not contact.blocked and contact.move.is_super() and cinematic_moves.has(contact.move.id) and actor.hp > 0 and actor.move == contact.move and actor.attack_instance == contact.instance:
			_begin_cinematic(contact)
			return
	if not throw_link.is_empty():
		_tick_awakenings()
		return
	for f in fighters:
		if f.move != null:
			f.move_frame += 1
			if f.move_frame >= f.move.total_frames():
				f.move = null
				_restore_stance(f)
		if f.awakening_startup == 0:
			f.buffer_left = maxi(0, f.buffer_left - 1)
		f.jump_buffer = maxi(0, f.jump_buffer - 1)
		f.combo_display = maxi(0, f.combo_display - 1)
	_tick_awakenings()
	if cinematic.is_empty() and not practice and (fighters[0].hp <= 0 or fighters[1].hp <= 0 or remaining <= 0):
		_finish_round()

func _begin_cinematic(contact: Dictionary) -> void:
	cinematic = {"contact":contact.duplicate(), "attacker":int(contact.attacker), "move":str(contact.move.id),
		"next_segment":int(contact.segment) + 1, "facing":int(contact.facing), "tail":false,
		"awakened":fighters[contact.attacker].awakening_ticks > 0, "ko_announced":false}
	hitstop = 0
	super_freeze = 0
	clear_inputs()
	events.append({"type":"cinematic_start", "attacker":contact.attacker, "move":contact.move.id})

func advance_cinematic(progress: float) -> void:
	events.clear()
	if cinematic.is_empty() or cinematic.tail:
		return
	var attack: Move = moves[cinematic.move]
	var target := mini(attack.hit_count() - 1, floori(clampf(progress, 0, 1) * (attack.hit_count() - 1) / 0.9))
	var actor: Fighter = fighters[cinematic.attacker]
	var victim: Fighter = fighters[1 - int(cinematic.attacker)]
	while int(cinematic.next_segment) <= target:
		var segment: int = cinematic.next_segment
		cinematic.next_segment += 1
		if victim.hp <= 0:
			continue
		var contact: Dictionary = cinematic.contact.duplicate()
		contact.segment = segment
		contact.position = Vector2(victim.x, victim.y - 36)
		_resolve_contact(contact)
		if not segment in actor.hit_registry:
			actor.hit_registry.append(segment)
	hitstop = 0
	super_freeze = 0

func begin_cinematic_tail(face_away: bool) -> void:
	if cinematic.is_empty() or cinematic.tail:
		return
	advance_cinematic(1.0)
	cinematic.tail = true
	var actor: Fighter = fighters[cinematic.attacker]
	var victim: Fighter = fighters[1 - int(cinematic.attacker)]
	var direction: int = cinematic.facing
	var center := clampf((actor.x + victim.x) * 0.5, LEFT + 95, RIGHT - 95)
	actor.x = center - direction * 60
	victim.x = center + direction * 70
	actor.facing = -direction if face_away else direction
	victim.facing = -direction
	for f in fighters:
		f.previous_x = f.x
		f.y = FLOOR_Y
		f.grounded = true
		f.vx = 0
		f.vy = 0
		f.move = null
		f.stun = 0
		f.knockdown_pending = false
		f.roll_frame = -1
		f.flip_jump = false
		f.crouching = false
		f.axis = 0
		f.down = false
		_stop_dash(f)
	actor.state = "idle"
	victim.state = "knockdown"
	victim.reaction = "cinematic_landed"
	victim.stun = 24
	projectiles.clear()
	clear_inputs()

func cinematic_blocks_combat() -> bool:
	return not cinematic.is_empty() and not bool(cinematic.get("released", false))

func cinematic_is_lethal() -> bool:
	return not practice and not cinematic.is_empty() and fighters[1 - int(cinematic.attacker)].hp <= 0

func announce_cinematic_ko() -> void:
	if not cinematic_is_lethal() or cinematic.get("ko_announced", false):
		return
	cinematic.ko_announced = true
	events.append({"type":"ko_announce"})

func cinematic_holds_victim(slot: int) -> bool:
	return not cinematic.is_empty() and bool(cinematic.get("tail", false)) and slot != int(cinematic.attacker)

func release_cinematic_actor() -> void:
	if cinematic.is_empty() or not cinematic.tail or bool(cinematic.get("released", false)) or cinematic_is_lethal():
		return
	cinematic.released = true
	# The attacker can start a fresh action while the victim finishes landing.
	var actor: Fighter = fighters[cinematic.attacker]
	actor.quick_awakening_used = false
	actor.combo_active = false
	actor.combo_instances.clear()
	actor.chain_instances.clear()
	actor.chain_normals.clear()
	actor.chain_counts.clear()
	clear_inputs()

func finish_cinematic() -> void:
	if cinematic.is_empty():
		return
	if not cinematic.tail:
		begin_cinematic_tail(false)
	var victim_slot: int = 1 - int(cinematic.attacker)
	var released := bool(cinematic.get("released", false))
	var presented_ko := cinematic_is_lethal() and bool(cinematic.get("ko_announced", false))
	var actor_slot: int = cinematic.attacker
	var victory_form: bool = fighters[actor_slot].character == "nezuko" and (cinematic.get("awakened", false) or cinematic.move == "nezuko_max")
	cinematic.clear()
	events.clear()
	if not released:
		hitstop = 0
		super_freeze = 0
		clear_inputs()
	if not practice and (fighters[0].hp <= 0 or fighters[1].hp <= 0 or remaining <= 0):
		_finish_round()
		if fighters[victim_slot].hp <= 0:
			outro_paths[victim_slot]["settled"] = true
			outro_landed_at[victim_slot] = 0.0
			if presented_ko:
				# Video and local landing already presented the entire knockout.
				outro_ticks = victory_at
				phase_frames = Flow.RESULT
				if victory_form:
					cinematic_victory_form_slot = actor_slot

func _restore_stance(f: Fighter) -> void:
	# Resolve held input on the completion tick, before presentation reads state.
	f.crouching = f.grounded and f.down
	f.state = ("crouch" if f.crouching else "idle") if f.grounded else "air"

func _update_sequences() -> void:
	for i in range(2):
		var a: Fighter = fighters[i]
		var d: Fighter = fighters[1 - i]
		if d.stun == 0 and d.throw_role.is_empty():
			a.quick_awakening_used = false
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
		if command.action.type == "awaken" and not can_awaken(f):
			f.clear_buffer()
			events.append({"type":"awakening_denied", "attacker":f.slot})
			return
		f.buffer_action = command.action.duplicate()
		f.buffer = command.action.type
		f.buffer_left = SUPER_BUFFER_TICKS if command.action.type == "max" or command.action.get("motion", "") == "236236" else BUFFER_TICKS

func _advance(f: Fighter) -> void:
	f.previous_x = f.x
	if f.state == "awakening" and f.awakening_startup == 0:
		_restore_stance(f)
	f.throw_invulnerable = maxi(0, f.throw_invulnerable - 1)
	if f.stun > 0:
		_stop_dash(f)
		f.stun -= 1
		if f.stun == 0:
			f.reaction = ""
			if f.state == "knockdown":
				f.throw_invulnerable = 8
			_restore_stance(f)
		_integrate(f)
		return
	if f.awakening_startup > 0:
		f.state = "awakening"
		f.crouching = false
		f.jump_buffer = 0
		if f.awakening_quick:
			var gap: float = (fighters[1 - f.slot].x - f.x) * f.facing - 26.0
			f.x += f.facing * minf(4.0, maxf(0.0, gap))
		f.awakening_startup -= 1
		_integrate(f)
		return
	if f.roll_frame >= 0:
		if f.roll_frame < 20:
			f.x += f.roll_direction * 4.4
		f.roll_frame += 1
		if f.roll_frame >= 28:
			f.roll_frame = -1
			_restore_stance(f)
		f.clear_buffer()
		_integrate(f)
		return
	if f.dash_ticks > 0 and (f.down or (f.axis != 0 and f.axis != f.dash_direction)):
		_stop_dash(f)
	if f.move == null and f.grounded and f.jump_buffer > 0:
		# Capture the established forward dash before clearing its state. Neutral-up
		# preserves momentum; reversing/crouching already cancelled the dash above.
		var forward_dash: bool = f.dash_ticks > 0 and not f.dash_back
		var jump_axis: int = f.dash_direction if forward_dash and f.axis == 0 else f.axis
		var jump_speed: float = definition(f).walk_speed * (Arena.DASH_JUMP_MULTIPLIER if forward_dash else 1.0)
		_stop_dash(f)
		f.air_ticks = 0
		f.air_used_move = false
		f.flip_jump = true
		f.jump_facing = f.facing
		f.jump_back = f.axis * f.facing < 0
		f.grounded = false
		f.crouching = false
		f.vy = -7.8
		f.vx = jump_axis * jump_speed
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
		if f.move.lift != 0 and f.move.lift_frame > 0 and f.move_frame == f.move.lift_frame:
			_take_off(f, f.move.lift)
		if f.move_frame < f.move.startup:
			f.x += f.move.startup_travel * f.facing
		elif f.move_frame < f.move.startup + f.move.active:
			var segment := f.move.segment(f.move_frame)
			if segment >= 0 and f.move_frame == f.move.segment_start(segment):
				events.append({"type":"strike", "attacker":f.slot, "move":f.move.id, "instance":f.attack_instance, "segment":segment})
			var travel: float = f.move.travel
			var target: Fighter = fighters[1 - f.slot]
			# Connected multihit supers must not dash beneath their airborne target.
			# Keep natural forward movement until contact spacing is reached; no warp.
			if f.move.is_super() and f.confirmed and f.move.hit_count() > 1 and target.stun > 0 and f.attack_instance in target.juggle_instances:
				travel = minf(travel, maxf(0, (target.x - f.x) * f.facing - 26))
			f.x += travel * f.facing
			if f.move.projectile_speed != 0 and not f.projectile_spawned:
				_spawn_projectile(f)
	elif f.dash_ticks > 0:
		f.state = "dash"
		f.x += f.dash_direction * (Arena.DASH_BACK_SPEED if f.dash_back else Arena.DASH_FORWARD_SPEED) * awakening_movement(f, true)
		f.dash_frame += 1
		f.dash_ticks -= 1
	elif f.grounded:
		f.crouching = f.down
		if f.crouching:
			f.state = "crouch"
		else:
			f.x += f.axis * definition(f).walk_speed * awakening_movement(f, false)
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
		if f.move_frame > f.move.startup + f.move.active + f.move.cancel_window:
			# An expired uppercut cancel must not linger until landing and spend
			# meter on an unintended standalone super at the end of recovery.
			if f.move.lift != 0 and selected.is_super():
				f.clear_buffer()
			return
		if not f.connected or selected.kind not in f.move.cancel_targets:
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
	# A hit-confirmed uppercut cancel arrests ascent; the ground super falls naturally
	# into its stance instead of carrying a standing animation through the whole arc.
	if selected.is_super() and f.move != null and f.move.lift != 0 and not f.grounded:
		f.vy = maxf(0, f.vy)
		# A late hit-confirm must not let the launched victim land during the
		# ground super's startup. Carry only the still-stunned airborne victim;
		# this cannot pick up an already grounded knockdown or grant a new juggle.
		var victim: Fighter = fighters[1 - f.slot]
		if victim.state == "hit" and victim.stun > 0 and not victim.grounded:
			victim.vy = minf(victim.vy, -3.2)
	f.move = selected
	f.attack_damage_percent = int(definition(f).awakening.damage_percent) if f.awakening_ticks > 0 and selected.kind in ["light", "heavy", "skill"] else 100
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
	if selected.lift != 0 and selected.lift_frame == 0:
		_take_off(f, selected.lift)
	if selected.meter_cost > 0:
		_change_meter(f, -selected.meter_cost)
		super_freeze = maxi(super_freeze, selected.freeze_frames)
		events.append({"type": "super", "attacker": f.slot, "move": selected.id})
	events.append({"type": "swing", "attacker": f.slot, "move": selected.id, "effect": selected.effect()})


func _take_off(f: Fighter, velocity: float) -> void:
	f.flip_jump = false
	f.grounded = false
	f.crouching = false
	f.air_ticks = 0
	f.vy = velocity

func _integrate(f: Fighter, delta_ticks: float = 1.0, air_tick_step: int = 1) -> void:
	f.x += f.vx * delta_ticks
	if f.grounded:
		f.vx *= pow(0.76, delta_ticks)
	else:
		f.air_ticks += air_tick_step
		if f.state == "hit":
			f.vx *= pow(0.94, delta_ticks)
		f.vy += 0.42 * delta_ticks
		f.y += f.vy * delta_ticks
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
				_restore_stance(f)
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
	if cinematic_holds_victim(left.slot):
		right.x += overlap
	elif cinematic_holds_victim(right.slot):
		left.x -= overlap
	else:
		left.x -= overlap / 2
		right.x += overlap / 2
	if left.x < LEFT:
		right.x += LEFT - left.x
		left.x = LEFT
	if right.x > RIGHT:
		left.x -= right.x - RIGHT
		right.x = RIGHT

func _can_block(f: Fighter, attack: Move) -> bool:
	if f.awakening_startup > 0 or f.state == "awakening" or attack.level == "throw" or not f.grounded or f.move != null or f.hp <= 0 or f.dash_ticks > 0 or f.state == "dash" or f.roll_frame >= 0:
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
	if cinematic_holds_victim(d.slot) or d.strike_invulnerable():
		return false
	if d.move != null and d.move_frame < d.move.anti_air_until and not a.grounded and not projectile:
		return false
	if not d.grounded and not instance in d.juggle_instances and d.juggle_instances.size() >= 3:
		return false
	return true

func _contact(a: Fighter, d: Fighter, move: Move, instance: int, segment: int, projectile: bool, facing_override: int = 0, damage_percent: int = -1) -> Dictionary:
	return {"attacker": a.slot, "move": move, "instance": instance, "segment": segment,
		"facing": a.facing if facing_override == 0 else facing_override,
		"blocked": _can_block(d, move), "projectile": projectile, "airborne": not d.grounded,
		"damage_percent": a.attack_damage_percent if damage_percent < 0 else damage_percent,
		"received_percent": awakening_defense(d), "chip_percent": int(definition(d).awakening.chip_percent) if d.awakening_ticks > 0 else 100,
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
	d.awakening_startup = 0
	d.clear_buffer()
	if contact.blocked:
		d.state = "block"
		d.stun = attack.blockstun
		d.vx = contact.facing * attack.push * 0.55
		if attack.kind in ["skill", "super", "max"]:
			var chip := maxi(1, int(attack.segment_damage(contact.segment) * 0.08))
			chip = int(chip * int(contact.get("chip_percent", 100)) / 100)
			d.hp = maxi(1, d.hp - chip)
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
		var damage := attack.segment_damage(contact.segment, int(a.combo_instances[instance]), int(contact.get("damage_percent", 100)), int(contact.get("received_percent", 100)))
		damage = mini(d.hp, damage)
		d.hp = maxi(0, d.hp - damage)
		if a.awakening_ticks > 0 and attack.kind in ["light", "heavy", "skill"]:
			pending_healing[a.slot] += damage * int(definition(a).awakening.healing_percent)
		if attack.launch < 0:
			_take_off(d, attack.launch)
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
	if amount > 0 and f.awakening_ticks > 0:
		return
	var old := f.meter
	f.meter = clampi(f.meter + amount, 0, 300)
	if f.meter != old:
		events.append({"type": "meter", "attacker": f.slot, "amount": f.meter - old, "value": f.meter})

func _spawn_projectile(f: Fighter) -> void:
	f.projectile_spawned = true
	projectiles.append({"owner": f.slot, "instance": f.attack_instance, "move": f.move.id,
		"x": f.x + f.facing * 27, "y": f.y - 32, "vx": f.move.projectile_speed * f.facing,
		"facing": f.facing, "life": f.move.projectile_lifetime, "damage_percent": f.attack_damage_percent})
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
	if phase != "fight":
		return
	throw_link.clear()
	for f in fighters:
		_end_awakening(f)
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
	go_frames = 0
	outro_ticks = maxi(0, lethal_throw_ticks)
	lethal_throw_ticks = -1
	victory_at = Flow.RESULT_AT
	outro_tail_until = 0
	phase_frames = victory_at + Flow.RESULT - outro_ticks
	for f in fighters:
		outro_landed_at[f.slot] = 0.0 if f.grounded else -1.0
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
	if not is_knockout():
		projectiles.clear()
	_prepare_defeats()
	events.append({"type": "round_end", "knockout": is_knockout()})

func _prepare_defeats() -> void:
	for f in fighters:
		if f.hp > 0:
			continue
		# A lethal throw has already hit the floor before settlement. Never launch twice.
		var thrown: bool = f.throw_frame >= Arena.THROW_IMPACT_TICK
		var direction: int = -f.throw_facing if thrown else -f.facing
		var flight: float = 0.0 if thrown else Flow.KO_FLIGHT + clampf((FLOOR_Y - f.y) / 12.0, 0, 8)
		var separation: float = Arena.MAX_SEPARATION - Flow.KO_EDGE_MARGIN * 2
		var other: Fighter = fighters[1 - f.slot]
		var share: float = 2.0 if other.hp <= 0 else 1.0
		var distance: float = minf(Flow.KO_DISTANCE, maxf(0, (separation - absf(f.x - other.x)) / share - Flow.KO_SLIDE))
		var destination: float = f.x if thrown else clampf(f.x + direction * distance, LEFT, RIGHT)
		# Leave room for the horizontal body without changing the fixed camera scale.
		if direction > 0:
			destination = maxf(f.x, minf(destination, other.x + separation))
		else:
			destination = minf(f.x, maxf(destination, other.x - separation))
		outro_paths[f.slot] = {"x":f.x, "y":f.y, "end_x":destination,
			"flight":flight, "direction":direction, "thrown":thrown, "pose_facing":f.throw_facing if thrown else f.facing}
		outro_landed_at[f.slot] = 0.0 if thrown else -1.0

func actor_intro_ticks() -> int:
	return clampi(Flow.OPENING - phase_frames, 0, Flow.ACTOR_INTRO)

func defeat_frame(slot: int) -> int:
	var path: Dictionary = outro_paths[slot]
	if path.is_empty():
		return 0
	if path.thrown or path.get("settled", false):
		return 11 # The throw has already finished landing; never replay a second impact.
	var motion := Flow.motion_ticks(outro_ticks, is_knockout())
	if motion < float(path.flight):
		return mini(5, int(motion / float(path.flight) * 6))
	return mini(11, 6 + int((motion - float(path.flight)) / Flow.KO_SETTLE_DRAWING))

func _advance_defeat(f: Fighter, motion: float) -> void:
	var path: Dictionary = outro_paths[f.slot]
	if path.get("settled", false):
		return
	var flight: float = path.flight
	var progress := 1.0 if is_zero_approx(flight) else clampf(motion / flight, 0, 1)
	var travel := 1.0 - pow(1.0 - progress, 1.25)
	f.x = lerpf(path.x, path.end_x, travel)
	f.y = lerpf(path.y, FLOOR_Y, progress) - sin(progress * PI) * 26.0
	f.grounded = progress >= 1.0
	f.vx = 0
	f.vy = 0
	f.move = null
	f.flip_jump = false
	f.knockdown_pending = false
	f.state = "knockdown" if f.grounded else "hit"
	if f.grounded:
		outro_landed_at[f.slot] = flight
		var slide := (1.0 - pow(1.0 - clampf((motion - flight) / 12.0, 0, 1), 2)) * Flow.KO_SLIDE
		if not path.thrown:
			f.x = clampf(f.x + path.direction * slide, LEFT, RIGHT)
		f.y = FLOOR_Y

func is_knockout() -> bool:
	return reason in ["K.O.", "DOUBLE K.O."]

func presentation_speed() -> float:
	if lethal_throw_ticks >= 0:
		return Flow.speed(lethal_throw_ticks, true)
	return Flow.speed(outro_ticks, is_knockout()) if phase == "round_end" else 1.0

func presentation_time_ticks() -> float:
	var elapsed := lethal_throw_ticks if lethal_throw_ticks >= 0 else outro_ticks
	if lethal_throw_ticks >= 0 or (phase == "round_end" and is_knockout()):
		return float(ticks - elapsed) + Flow.motion_ticks(elapsed, true)
	return float(ticks)

func presents_attack(slot: int) -> bool:
	return phase == "fight" or (phase == "round_end" and is_knockout() and fighters[slot].hp > 0 and outro_ticks < victory_at)

func preserves_throw_pose(slot: int) -> bool:
	return not outro_paths[slot].is_empty() and bool(outro_paths[slot].thrown)

func outro_pose_ticks(slot: int) -> float:
	if outro_ticks >= victory_at and round_winner == slot:
		return float(outro_ticks - victory_at)
	var motion := Flow.motion_ticks(outro_ticks, is_knockout())
	return motion - maxf(0, outro_landed_at[slot]) if fighters[slot].hp == 0 else motion

func round_cue() -> Dictionary:
	if practice:
		return {}
	if lethal_throw_ticks >= 0:
		return {} if lethal_throw_ticks < Flow.FREEZE else {"text":"K.O.", "age":lethal_throw_ticks - Flow.FREEZE, "duration":Flow.RESULT_AT - Flow.FREEZE}
	if phase == "intro":
		if phase_frames > Flow.INTRO:
			return {}
		if phase_frames > Flow.READY:
			return {"text": "ROUND %d" % round_number, "age": Flow.INTRO - phase_frames, "duration": Flow.ROUND}
		return {"text": "READY", "age": Flow.READY - phase_frames, "duration": Flow.READY}
	if phase == "fight" and go_frames > 0:
		return {"text": "GO!", "age": Flow.GO - go_frames, "duration": Flow.GO}
	if phase == "round_end":
		if outro_ticks >= victory_at:
			return {"text": "DRAW" if round_winner < 0 else "P%d WINS" % (round_winner + 1),
				"subtitle": "" if round_winner < 0 else definition(fighters[round_winner]).display_name,
				"age": outro_ticks - victory_at, "duration": Flow.RESULT}
		if is_knockout():
			if outro_ticks < Flow.FREEZE:
				return {}
			return {"text": reason, "age": outro_ticks - Flow.FREEZE, "duration": victory_at - Flow.FREEZE}
		return {"text": "TIME UP", "age": outro_ticks, "duration": Flow.RESULT_AT}
	return {}

func _advance_lethal_throw() -> void:
	var before := Flow.motion_ticks(lethal_throw_ticks, true)
	lethal_throw_ticks += 1
	var after := Flow.motion_ticks(lethal_throw_ticks, true)
	if lethal_throw_ticks == Flow.FREEZE:
		events.append({"type":"ko_announce"})
	if int(floor(after) - floor(before)) > 0:
		_advance_throw()

func _outro_skill_motion(f: Fighter, delta_ticks: float, advance_tick: bool) -> void:
	if f.move == null or not is_knockout():
		return
	var move: Move = f.move
	if advance_tick and move.lift != 0 and move.lift_frame > 0 and f.move_frame == move.lift_frame:
		_take_off(f, move.lift)
	if f.move_frame < move.startup:
		f.x += move.startup_travel * f.facing * delta_ticks
	elif f.move_frame < move.startup + move.active:
		var segment := move.segment(f.move_frame)
		if advance_tick and segment >= 0 and f.move_frame == move.segment_start(segment):
			events.append({"type":"strike", "attacker":f.slot, "move":move.id, "instance":f.attack_instance, "segment":segment})
		f.x += move.travel * f.facing * delta_ticks
		if move.projectile_speed != 0 and not f.projectile_spawned:
			_spawn_projectile(f)

func _outro_ready() -> bool:
	if not is_knockout() or round_winner < 0:
		return true
	var winner: Fighter = fighters[round_winner]
	return winner.move == null and winner.grounded and projectiles.is_empty() and Flow.motion_ticks(outro_ticks, true) >= outro_tail_until

func _advance_outro() -> void:
	var before := Flow.motion_ticks(outro_ticks, is_knockout())
	outro_ticks += 1
	var after := Flow.motion_ticks(outro_ticks, is_knockout())
	var motion_delta := after - before
	var move_steps := int(floor(after) - floor(before))
	if outro_ticks == Flow.FREEZE and is_knockout():
		events.append({"type": "ko_announce"})
	if motion_delta > 0:
		for f in fighters:
			f.previous_x = f.x
			if not outro_paths[f.slot].is_empty():
				_advance_defeat(f, after)
				continue
			var airborne: bool = not f.grounded
			var previous_move: Move = f.move
			_outro_skill_motion(f, motion_delta, move_steps > 0)
			_integrate(f, motion_delta, move_steps)
			if airborne and f.grounded:
				outro_landed_at[f.slot] = after
			if f.move != null:
				f.move_frame += move_steps
				if f.move_frame >= f.move.total_frames():
					f.move = null
					_restore_stance(f)
			if previous_move != null and f.move == null and previous_move.presentation != null:
				var tail := maxf(0, previous_move.presentation.trail_lifetime * 60 - previous_move.recovery)
				outro_tail_until = maxf(outro_tail_until, after + tail)
		# Visual flight only. No contacts, damage, chip, meter, cancels or new input.
		for p in projectiles:
			p.x += p.vx * motion_delta
			p.life -= motion_delta
		projectiles = projectiles.filter(func(p: Dictionary) -> bool: return p.life > 0 and p.x >= LEFT - 40 and p.x <= RIGHT + 40)
		_constrain_separation()
	if outro_ticks >= victory_at and not _outro_ready():
		victory_at = outro_ticks + 1
	phase_frames = victory_at + Flow.RESULT - outro_ticks
	if phase_frames <= 0:
		if wins.max() >= 2:
			match_winner = 0 if wins[0] >= 2 else 1
			phase = "match_end"
		else:
			start_round()

func snapshot() -> Dictionary:
	var data: Array = []
	for f in fighters:
		data.append(f.snapshot())
	return {"fighters": data, "phase": phase, "phase_frames": phase_frames, "remaining": remaining,
		"go_frames": go_frames, "outro_ticks": outro_ticks, "outro_landed_at": outro_landed_at.duplicate(),
		"outro_paths": outro_paths.duplicate(true),
		"cinematic_victory_form_slot": cinematic_victory_form_slot, "victory_at": victory_at, "outro_tail_until": outro_tail_until, "lethal_throw_ticks": lethal_throw_ticks,
		"wins": wins.duplicate(), "hitstop": hitstop, "super_freeze": super_freeze, "ticks": ticks,
		"round_number": round_number, "round_winner": round_winner, "match_winner": match_winner,
		"reason": reason, "next_instance": next_instance, "practice": practice, "awakening_infinite": awakening_infinite,
		"round_open_hp": round_open_hp.duplicate(),
		"round_open_meter": round_open_meter.duplicate(), "projectiles": projectiles.duplicate(true),
		"throw_link": throw_link.duplicate(true), "cinematic": {"move":cinematic.get("move", ""), "next_segment":cinematic.get("next_segment", 0), "tail":cinematic.get("tail", false), "released":cinematic.get("released", false), "awakened":cinematic.get("awakened", false), "ko_announced":cinematic.get("ko_announced", false)}}

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
		f.awakening_startup = 0
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
		var damage := mini(d.hp, maxi(1, int(attack.damage * awakening_defense(d) / 100)))
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
		if d.hp <= 0:
			_end_awakening(d)
		if not practice and d.hp <= 0:
			_end_awakening(a)
			lethal_throw_ticks = 0
			hitstop = 0 # The shared KO clock freezes this exact impact, then slows the linked landing.
	if frame >= Arena.THROW_TICKS:
		a.x = throw_link.final_a
		d.x = throw_link.final_d
		_restore_stance(a)
		d.state = "knockdown"
		a.throw_role = ""
		d.throw_role = ""
		d.stun = 24
		throw_link.clear()
		_face_opponent()
		if not practice and (a.hp <= 0 or d.hp <= 0 or remaining <= 0):
			_finish_round()

func can_awaken(f: Fighter) -> bool:
	if phase != "fight" or f.hp <= 0 or definition(f).awakening == null or f.awakening_ticks > 0:
		return false
	if not f.grounded or f.stun > 0 or f.roll_frame >= 0 or not f.throw_role.is_empty() or not throw_link.is_empty():
		return false
	if f.move == null:
		return true
	var d: Fighter = fighters[1 - f.slot]
	return not f.quick_awakening_used and f.confirmed and f.move.kind in ["light", "heavy"] and f.move.stance != "air" and not f.move.knockdown and f.move.launch == 0 and d.grounded and d.stun > 0 and d.state == "hit" and f.move_frame <= f.move.startup + f.move.active + f.move.cancel_window

func _try_awaken(f: Fighter) -> bool:
	var allowed := can_awaken(f)
	f.clear_buffer()
	if not allowed:
		events.append({"type":"awakening_denied", "attacker":f.slot})
		return false
	if f.meter < AWAKENING_COST:
		events.append({"type":"meter_empty", "attacker":f.slot, "cost":AWAKENING_COST})
		return false
	var quick := f.move != null
	_change_meter(f, -AWAKENING_COST)
	_stop_dash(f)
	f.awakening_duration = 360 if quick else 600
	f.awakening_ticks = f.awakening_duration
	f.awakening_startup = 6 if quick else 18
	f.awakening_quick = quick
	f.awakening_heal_left = int(definition(f).awakening.healing_limit)
	f.awakening_heal_fraction = 0
	f.vx = 0
	f.crouching = false
	f.move = null
	f.state = "awakening"
	if quick:
		f.quick_awakening_used = true
		f.chain_normals.clear()
		f.chain_counts.erase("light")
		f.chain_counts.erase("heavy")
	f.input.last_action = ("快速觉醒 · " if quick else "觉醒 · ") + str(definition(f).awakening.display_name)
	super_freeze = maxi(super_freeze, AWAKENING_FREEZE)
	events.append({"type":"awakening_start", "attacker":f.slot, "quick":quick})
	return true

func awakening_movement(f: Fighter, dash: bool) -> float:
	if f.awakening_ticks <= 0:
		return 1.0
	var data: Resource = definition(f).awakening
	return float(data.dash_percent if dash else data.walk_percent) / 100.0

func awakening_defense(f: Fighter) -> int:
	return int(definition(f).awakening.received_percent) if f.awakening_ticks > 0 else 100

func _tick_awakenings() -> void:
	for f in fighters:
		if f.awakening_ticks <= 0:
			continue
		if f.hp <= 0:
			_end_awakening(f)
			continue
		if not (practice and awakening_infinite):
			f.awakening_ticks -= 1
			if f.awakening_ticks == 120:
				events.append({"type":"awakening_warning", "attacker":f.slot})
			if f.awakening_ticks == 0:
				_end_awakening(f)

func _end_awakening(f: Fighter) -> void:
	if f.awakening_duration > 0:
		events.append({"type":"awakening_end", "attacker":f.slot})
	f.awakening_ticks = 0
	f.awakening_duration = 0
	f.awakening_startup = 0
	f.awakening_heal_left = 0
	f.awakening_heal_fraction = 0
	if f.state == "awakening":
		f.state = "idle"

func _flush_awakening_healing() -> void:
	# Damage to BOTH fighters is resolved first: a trade cannot revive a KO.
	for f in fighters:
		var credit: int = pending_healing[f.slot]
		pending_healing[f.slot] = 0
		if f.hp <= 0 or f.awakening_ticks <= 0 or credit == 0 or f.awakening_heal_left <= 0:
			continue
		credit += f.awakening_heal_fraction
		f.awakening_heal_fraction = credit % 100
		var amount := mini(1000 - f.hp, mini(f.awakening_heal_left, int(credit / 100)))
		if amount > 0:
			f.hp += amount
			f.awakening_heal_left -= amount
			events.append({"type":"heal", "attacker":f.slot, "amount":amount, "value":f.hp})
