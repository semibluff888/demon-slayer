extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Support = preload("res://tests/combat_test_support.gd")
const Commands = preload("res://scripts/command_recognizer.gd")
const Practice = preload("res://scripts/practice_controller.gd")
const AI = preload("res://scripts/ai_controller.gd")
var s := Support.new()
var passed := 0
var failures: Array[String] = []
var routes: Array[Dictionary] = []
var comparisons: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	if ok: passed += 1
	else: failures.append(message)

func _initialize() -> void:
	_input()
	_timing_and_constraints()
	_boundaries()
	_attributes()
	_healing_and_projectiles()
	_combo_matrix()
	_resource_comparison()
	_max_finishers()
	_ai_activation()
	_practice_and_rounds()
	var report := FileAccess.open("res://artifacts/awakening-balance.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"routes":routes, "comparisons":comparisons, "failures":failures}, "  "))
	for failure in failures: printerr("FAIL: ", failure)
	print("AWAKENING TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _input() -> void:
	for delay in [0, 1, 2]:
		var c := Commands.new()
		var actions: Array[String] = []
		for n in range(8):
			var mask := (Commands.B | Commands.C) if delay == 0 else (Commands.B if n < delay else Commands.B | Commands.C)
			var sample := c.sample({"buttons":mask}, 1)
			if not sample.action.is_empty(): actions.append(sample.action.type)
		check(actions == ["awaken"], "BC chord tolerance and held suppression %d" % delay)
	var c := Commands.new()
	var action: Dictionary = {}
	for n in range(3): action = c.sample({"buttons":7}, 1).action
	check(action.get("type") == "roll", "AB priority remains with three buttons")

func awaken(model: Combat, slot: int = 0) -> void:
	model.fighters[slot].meter = 300
	var commands := [Combat.neutral(), Combat.neutral()]
	commands[slot].buttons = Commands.B | Commands.C
	model.step(commands)
	for n in range(2): model.step([Combat.neutral(), Combat.neutral()])
	check(model.fighters[slot].awakening_ticks > 0, "activation uses real input")
	for n in range(30): model.step([Combat.neutral(), Combat.neutral()])

func _timing_and_constraints() -> void:
	var c := s.duel()
	var f = c.fighters[0]
	f.meter = 300
	s.input(c, "BC")
	check(f.awakening_ticks == 600 and f.meter == 100 and c.super_freeze == 12, "normal activation pays 200 once")
	s.advance(c, 12)
	check(f.awakening_ticks == 600 and f.awakening_startup == 18, "12 frozen ticks do not spend duration")
	s.advance(c, 17)
	check(f.awakening_ticks == 583 and f.awakening_startup == 1, "startup counts toward duration")
	s.advance(c, 1)
	check(f.awakening_ticks == 582 and f.awakening_startup == 0, "exactly 18 locked ticks")
	c._change_meter(f, 50)
	check(f.meter == 100, "all positive meter gain suppressed")
	c.hitstop = 7
	s.advance(c, 7)
	check(f.awakening_ticks == 582, "hitstop freezes awakening")
	s.input(c, "BC")
	check(f.meter == 100 and f.awakening_ticks < 582, "repeat cannot refresh or spend")
	s.advance(c, f.awakening_ticks)
	check(f.awakening_ticks == 0 and f.awakening_duration == 0, "exact duration exits")
	c._change_meter(f, 7)
	check(f.meter == 107, "gain resumes after expiry")
	for kind in ["meter", "air", "stun", "guard", "roll", "whiff", "throw", "block_confirm", "sweep"]:
		c = s.duel()
		f = c.fighters[0]
		f.meter = 199 if kind == "meter" else 300
		match kind:
			"air": f.grounded = false; f.y -= 50; f.state = "air"
			"stun": f.stun = 1; f.state = "hit"
			"guard": f.stun = 12; f.state = "block"
			"roll": f.roll_frame = 4; f.state = "roll"
			"throw": f.throw_role = "victim"
			"whiff", "block_confirm": c._begin_move(f, c.definition(f).normals["5C"]); f.connected = kind == "block_confirm"
			"sweep":
				c._begin_move(f, c.definition(f).normals["2D"]); f.confirmed = true; c.fighters[1].stun = 30; c.fighters[1].state = "hit"
		# Long enough stun at recognition; hitstun expiring before a chord is recognized is actionable.
		if kind == "stun": f.stun = 6
		var before: int = f.meter
		s.input(c, "BC")
		s.advance(c, 50)
		check(f.awakening_ticks == 0 and f.meter == before, "invalid BC consumed without deferred activation: "+kind)
	# Startup is vulnerable and interruption retains mode.
	c = s.duel("nezuko")
	f = c.fighters[0]; f.meter = 300
	s.input(c, "BC"); s.advance(c, 12)
	var contact := c._contact(c.fighters[1], f, c.definition(c.fighters[1]).normals["5A"], 90, 0, false)
	c._resolve_contact(contact)
	check(f.state == "hit" and f.awakening_startup == 0 and f.awakening_ticks == 600 and f.meter == 100, "startup interrupted without refund or dispel")

func _attributes() -> void:
	for cid in ["tanjiro", "zenitsu", "nezuko", "akaza"]:
		var c := s.duel(cid)
		awaken(c)
		var f = c.fighters[0]
		var config = c.definition(f).awakening
		var before: float = f.x
		s.tick(c, {"x":-1})
		check(is_equal_approx(before-f.x, c.definition(f).walk_speed*config.walk_percent/100.0), "walk multiplier "+cid)
		var move = c.definition(f).normals["5C"]
		c._begin_move(f, move)
		check(f.attack_damage_percent == config.damage_percent, "attack instance captures output "+cid)
		c._end_awakening(f)
		var d = c.fighters[1]
		c._resolve_contact(c._contact(f, d, move, f.attack_instance, 0, false))
		check(1000-d.hp == int(move.damage*config.damage_percent/100), "attack keeps launch multiplier after expiry "+cid)
		c = s.duel("tanjiro")
		c.fighters[1].character = cid
		awaken(c, 1)
		f = c.fighters[0]; d = c.fighters[1]
		move = c.definition(f).motions.max
		c._begin_move(f, move)
		for segment in range(move.hit_count()):
			c._resolve_contact(c._contact(f, d, move, f.attack_instance, segment, false))
		check(1000-d.hp == int(move.damage*config.received_percent/100), "defense reduces entire multi-hit MAX before splitting "+cid)
		check(d.meter == 100, "awakened defender earns no meter "+cid)
	var c := s.duel("tanjiro")
	c.fighters[1].character = "akaza"
	awaken(c, 1)
	var f = c.fighters[0]; var d = c.fighters[1]
	var hit := c._contact(f, d, c.definition(f).motions["236C"], 20, 0, false)
	hit.blocked = true
	c._resolve_contact(hit)
	var full_chip := maxi(1, int(c.definition(f).motions["236C"].damage*0.08))
	check(1000-d.hp == int(full_chip/2), "Akaza chip halves separately")
	c = s.duel("tanjiro")
	c.fighters[1].character = "akaza"
	awaken(c, 1)
	f = c.fighters[0]; d = c.fighters[1]
	c._start_throw(c._contact(f, d, c.definition(f).throw_move, 30, 0, false))
	var time: int = d.awakening_ticks
	s.advance(c, 20)
	check(d.awakening_ticks == time-20, "linked throw advances awakening timer")
	check(1000-d.hp == int(c.definition(f).throw_move.damage*85/100), "throw receives defense reduction")

func _healing_and_projectiles() -> void:
	var c := s.duel("nezuko")
	awaken(c)
	var f = c.fighters[0]; var d = c.fighters[1]
	f.hp = 700; d.hp = 10000
	var move = c.definition(f).normals["5C"]
	for n in range(40):
		c._begin_move(f, move)
		c._resolve_contact(c._contact(f, d, move, f.attack_instance, 0, false))
		c._flush_awakening_healing()
	check(f.hp == 740 and f.awakening_heal_left == 0, "regeneration caps at 40 actual HP")
	c = s.duel("nezuko"); awaken(c)
	f = c.fighters[0]; d = c.fighters[1]
	f.hp = 1; d.hp = 1
	c._begin_move(f, c.definition(f).normals["5C"])
	c._begin_move(d, c.definition(d).normals["5C"])
	var first := c._contact(f,d,f.move,f.attack_instance,0,false)
	var second := c._contact(d,f,d.move,d.attack_instance,0,false)
	c._resolve_contact(first); c._resolve_contact(second); c._flush_awakening_healing()
	check(f.hp == 0 and d.hp == 0, "simultaneous lethal trade cannot revive Nezuko")
	c = s.duel("tanjiro"); awaken(c)
	f = c.fighters[0]; d = c.fighters[1]
	move = c.definition(f).motions["236A"]
	c._begin_move(f,move); c._spawn_projectile(f)
	var projectile: Dictionary = c.projectiles[0]
	c._end_awakening(f)
	c._begin_move(f,c.definition(f).normals["5A"])
	c._resolve_contact(c._contact(f,d,move,projectile.instance,0,true,projectile.facing,projectile.damage_percent))
	check(1000-d.hp == int(move.damage*115/100), "projectile preserves launch multiplier across expiry and next move")
	c = s.duel("nezuko"); awaken(c)
	f = c.fighters[0]; d = c.fighters[1]; f.hp = 999
	c._begin_move(f,c.definition(f).normals["5C"])
	c._resolve_contact(c._contact(f,d,f.move,f.attack_instance,0,false)); c._flush_awakening_healing()
	check(f.hp == 1000 and f.awakening_heal_left == 39, "overheal does not consume unused recovery budget")

func _combo_matrix() -> void:
	for cid in ["tanjiro","zenitsu","nezuko","akaza"]:
		for opponent in ["tanjiro","zenitsu","nezuko","akaza"]:
			for facing in [-1,1]:
				for corner in [false,true]:
					for stocks in [2,3]:
						for finisher in ["236236A", "236236AC"]:
							var c := s.duel(cid,facing,corner)
							c.fighters[1].character = opponent
							c.fighters[0].meter = stocks*100
							var guard := {"x":facing}
							var label: String = "%s/%s/%d/%s/%d" % [cid,opponent,facing,str(corner),stocks] + " / " + finisher
							s.input(c,"5A")
							check(s.wait_contact(c), "starter "+label)
							s.input(c,"5C",guard)
							check(s.wait_contact(c,100,guard), "heavy confirm "+label)
							var f = c.fighters[0]
							var instances: int = f.combo_instances.size()
							s.input(c,"BC",guard)
							for n in range(10):
								if f.awakening_ticks > 0: break
								s.tick(c,{},guard)
							check(f.awakening_ticks == 360 and f.quick_awakening_used and f.combo_instances.size() == instances,"quick preserves scaling "+label)
							for notation in ["5A","5C","236A"]:
								s.input(c,notation,guard)
								check(s.wait_contact(c,100,guard),"quick continuation "+notation+" "+label)
							s.input(c,finisher,guard)
							if stocks == 3:
								check(s.wait_contact(c,100,guard),"one-stock finisher "+label)
								check(f.move.kind == ("max" if finisher == "236236AC" else "super"),"distinct quick finisher "+label)
								check((f.awakening_ticks == 0) == (finisher == "236236AC"),"only MAX consumes awakening "+label)
							else:
								check(f.awakening_ticks > 0 and not s.events.any(func(e): return e.type == "super" and e.attacker == 0),"two-stock route cannot afford a super "+label)
							s.advance(c,100,{},guard)
							var blocked := s.events.any(func(e): return e.type == "block" and e.attacker == 0)
							var spent := 0
							for e in s.events:
								if e.type == "meter" and e.attacker == 0 and e.amount < 0: spent -= e.amount
							check(not blocked and f.combo_instances.size() == 0 and f.combo >= 5,"true combo and eventual recovery "+label)
							check(spent == stocks*100 and c.fighters[1].hp > 0,"correct total cost and bounded route "+label)
							routes.append({"character":cid,"opponent":opponent,"facing":facing,"corner":corner,"stocks":stocks,"finisher":finisher,"damage":1000-c.fighters[1].hp,"combo":f.combo})

func _practice_and_rounds() -> void:
	var c := s.duel()
	var p := Practice.new()
	p.meter_mode = 4
	p.apply_meter(c)
	check(c.fighters[0].meter == 200,"training two stocks")
	c.practice = true; c.awakening_infinite = true
	awaken(c)
	var time: int = c.fighters[0].awakening_ticks
	s.advance(c,700)
	check(c.fighters[0].awakening_ticks == time,"training infinite time")
	p.reset(c,false)
	check(c.fighters[0].awakening_ticks == 0,"training reset clears form")
	c = s.duel(); awaken(c)
	c._finish_round()
	check(c.fighters[0].awakening_ticks == 0,"round end clears mode")
	c.start_round()
	check(c.fighters[0].awakening_ticks == 0 and not c.fighters[0].quick_awakening_used,"fresh round has no awakening state")

func _boundaries() -> void:
	var c := s.duel()
	var f = c.fighters[0]; f.meter = 300
	s.input(c,"BC"); s.advance(c,12); s.advance(c,18,{"x":-1})
	check(not c._can_block(f,c.definition(c.fighters[1]).normals["5A"]),"last startup tick remains vulnerable")
	s.tick(c,{"x":-1})
	check(c._can_block(f,c.definition(c.fighters[1]).normals["5A"]),"guard returns on first actionable tick")
	for slot in [0,1]:
		c = s.duel()
		for actor in c.fighters: actor.meter = 300
		c.step([{"buttons":6},{"buttons":6}])
		c.step([Combat.neutral(),Combat.neutral()]); c.step([Combat.neutral(),Combat.neutral()])
		check(c.fighters[slot].awakening_ticks == 600 and c.fighters[slot].awakening_startup == 18,"simultaneous activation has no slot priority")
	for cid in ["tanjiro","zenitsu","nezuko","akaza"]:
		c = s.duel(cid); awaken(c)
		f = c.fighters[0]
		for key in ["super","max"]:
			f.meter = 300
			c._begin_move(f,c.definition(f).motions[key])
			check(f.attack_damage_percent == (110 if key == "super" else 100),"only ordinary super gets uniform bonus "+cid+"/"+key)
		c = s.duel(cid); awaken(c)
		f = c.fighters[0]
		var expected: float = c.definition(f).walk_speed
		s.tick(c,{"y":-1,"x":1})
		check(is_equal_approx(f.vx,expected) and is_equal_approx(f.vy,-7.38),"jump velocity unaffected "+cid)
		c = s.duel(cid); awaken(c)
		f = c.fighters[0]
		s.tick(c,{"x":-1}); s.tick(c); var before: float = f.x
		s.tick(c,{"x":-1})
		check(is_equal_approx(before-f.x,4.0*c.definition(f).awakening.dash_percent/100.0),"backdash multiplier "+cid)
	c = s.duel("nezuko"); awaken(c)
	f = c.fighters[0]; f.hp = 600
	var blocked := c._contact(f,c.fighters[1],c.definition(f).motions["236A"],501,0,false)
	blocked.blocked = true
	c._resolve_contact(blocked); c._flush_awakening_healing()
	check(f.hp == 600 and f.awakening_heal_left == 40,"blocked attacks never heal")
	c = s.duel()
	f = c.fighters[0]; f.meter = 300
	s.input(c,"5C"); check(s.wait_contact(c),"quota test confirms heavy")
	s.input(c,"BC")
	for n in range(20):
		if f.awakening_ticks > 0: break
		s.tick(c)
	var victim = c.fighters[1]
	c._end_awakening(f)
	f.move = c.definition(f).normals["5C"]; f.confirmed = true; f.move_frame = 10
	f.meter = 300; victim.state = "hit"; victim.stun = 30
	check(not c.can_awaken(f),"second quick awakening cannot reset same combo after expiry")
	victim.stun = 0; c._update_sequences()
	check(not f.quick_awakening_used,"quick quota resets only after opponent recovers")

func _resource_comparison() -> void:
	# Fixed opponent, spacing and starter; measure resource tradeoffs, not an optimal combo claim.
	for cid in ["tanjiro","zenitsu","nezuko","akaza"]:
		for route in ["base","super","max","normal","normal_super","normal_max","quick","quick_super","quick_max"]:
			var c := s.duel(cid)
			c.fighters[1].character = "tanjiro"
			var f = c.fighters[0]
			f.meter = 300
			var guard := {"x":1}
			var label: String = cid+"/"+route
			if route.begins_with("normal"):
				s.input(c,"BC"); s.advance(c,31)
			for notation in ["5A","5C"]:
				s.input(c,notation,{} if notation == "5A" else guard)
				check(s.wait_contact(c,100,{} if notation == "5A" else guard),"comparison starter "+label+"/"+notation)
			if route.begins_with("quick"):
				s.input(c,"BC",guard)
				for notation in ["5A","5C"]:
					s.input(c,notation,guard)
					check(s.wait_contact(c,100,guard),"comparison extension "+label+"/"+notation)
			s.input(c,"236A",guard)
			check(s.wait_contact(c,100,guard),"comparison special "+label)
			if route.ends_with("super") or route.ends_with("max"):
				s.input(c,"236236AC" if route.ends_with("max") else "236236A",guard)
				check(s.wait_contact(c,100,guard),"comparison finisher "+label)
			s.advance(c,100,{},guard)
			var spent := 0
			for event in s.events:
				if event.type == "meter" and event.attacker == 0 and event.amount < 0: spent -= event.amount
			check(not s.events.any(func(e): return e.type == "block" and e.attacker == 0),"comparison remains a true combo "+label)
			comparisons.append({"character":cid,"route":route,"cost":spent,"damage":1000-c.fighters[1].hp,"hits":f.combo,"awakening_ticks_left":f.awakening_ticks,"meter_left":f.meter})

func _ai_activation() -> void:
	for cid in ["tanjiro","zenitsu","nezuko","akaza"]:
		var c := s.duel(cid)
		var f = c.fighters[0]; var d = c.fighters[1]
		f.meter = 300; d.state = "knockdown"; d.stun = 90
		var ai := AI.new(8)
		for n in range(12):
			check(ai.command(f.observable(),d.observable()).buttons == 0,"AI observes before reacting "+cid)
		for n in range(10):
			s.tick(c,ai.command(f.observable(),d.observable()))
			if f.awakening_ticks > 0: break
		check(f.awakening_ticks == 600 and f.meter == 100,"AI normal awakening uses real delayed input "+cid)
		c = s.duel(cid); f = c.fighters[0]; d = c.fighters[1]; f.meter = 300
		s.input(c,"5C"); check(s.wait_contact(c),"AI heavy starter "+cid)
		ai = AI.new(8)
		for n in range(12): ai.command(f.observable(),d.observable())
		for n in range(20):
			s.tick(c,ai.command(f.observable(),d.observable()))
			if f.awakening_ticks > 0: break
		check(f.awakening_ticks == 360 and f.quick_awakening_used and f.meter >= 100 and f.meter < 200,"AI confirmed heavy quick awakening "+cid)

func _max_finishers() -> void:
	for cid in ["tanjiro", "zenitsu", "nezuko", "akaza"]:
		for facing in [-1, 1]:
			for quick in [false, true]:
				for stocks in [2, 3]:
					for notation in ["236236A", "236236C", "236236AC"]:
						for outcome in ["hit", "block", "whiff"]:
							var c := s.duel(cid, facing)
							var f = c.fighters[0]
							var d = c.fighters[1]
							f.meter = stocks * 100
							if quick:
								s.input(c, "5C"); check(s.wait_contact(c), "quick finisher starter")
							s.input(c, "BC"); s.advance(c, 31)
							var before: int = f.meter
							var time: int = f.awakening_ticks
							var hp: int = d.hp
							var kind := "max" if notation == "236236AC" else "super"
							var guard := {"x":facing} if outcome == "block" else {}
							d.x = f.x + facing * (350 if outcome == "whiff" else 34)
							var label: String = "%s/%d/%s/%d/%s/%s" % [cid, facing, str(quick), stocks, notation, outcome]
							s.input(c, notation, guard)
							if stocks == 2:
								check(f.meter == before and f.awakening_ticks > 0, "unaffordable super retains both resources " + label)
								check(not s.events.any(func(e): return e.type == "super" and e.attacker == 0), "no free or fallback super " + label)
								check(s.events.any(func(e): return e.type == "meter_empty" and e.cost == 100), "one-stock cost feedback " + label)
								continue
							check(f.move == c.definition(f).motions[kind], "input selects requested move " + label)
							check(f.meter == before - 100, "both supers spend exactly one stock " + label)
							check(f.attack_damage_percent == (100 if kind == "max" else 110), "separate launch multipliers " + label)
							if kind == "max":
								check(f.awakening_ticks == 0 and f.awakening_duration == 0 and f.awakening_heal_left == 0, "MAX consumes all awakening " + label)
							else:
								check(f.awakening_ticks > 0 and f.awakening_ticks <= time and f.awakening_duration == (360 if quick else 600), "super retains mode without refreshing " + label)
							check(f.presents_awakened_finisher() and c.super_freeze > 0, "super retains launch appearance and freeze " + label)
							s.advance(c, 160, {}, guard)
							check(s.events.filter(func(e): return e.type == "awakening_end" and e.attacker == 0).size() == (1 if kind == "max" else 0), "only MAX ends mode once " + label)
							check(not f.presents_awakened_finisher(), "attack snapshot stops displaying after recovery " + label)
							if outcome == "hit":
								check(hp - d.hp == (289 if kind == "max" else 200), "complete finisher damage " + label)
							elif outcome == "block":
								var move = c.definition(f).motions[kind]
								var chip := 0
								for segment in range(move.hit_count()): chip += maxi(1, int(move.segment_damage(segment) * 0.08))
								check(hp - d.hp == chip, "enhanced super does not increase chip " + label)
							else:
								check(d.hp == hp, "whiff consumes resources without damage " + label)
							var left: int = f.meter
							s.input(c, notation, guard)
							check(f.meter == left and s.events.filter(func(e): return e.type == "super" and e.attacker == 0).size() == 1, "repeat without meter cannot launch " + label)
							c._change_meter(f, 7)
							check(f.meter == left + (7 if kind == "max" else 0), "only ended mode resumes meter gain " + label)
	_super_choice_boundaries()
	_super_choice_damage()
	_super_choice_practice_and_ai()

func _super_choice_boundaries() -> void:
	for cid in ["tanjiro", "zenitsu", "nezuko", "akaza"]:
		for notation in ["236236A", "236236AC"]:
			var kind := "max" if notation == "236236AC" else "super"
			# The mode may expire while the motion is still being entered.
			for meter in [0, 99, 100, 300]:
				var c := s.duel(cid); awaken(c)
				var f = c.fighters[0]
				f.meter = meter; f.awakening_ticks = 1
				s.input(c, notation)
				var cost := 300 if kind == "max" else 100
				check(f.awakening_ticks == 0 and f.meter == (meter - cost if meter >= cost else meter), "expiry rechecks normal cost " + cid + notation + str(meter))
				check((f.move == c.definition(f).motions[kind] if meter >= cost else f.move == null), "expiry keeps input identity without fallback " + cid + notation)
				if f.move != null: check(f.attack_damage_percent == 100, "no expired bonus " + cid + notation)
			for state in ["hit", "air", "whiff", "blocked"]:
				var c := s.duel(cid); awaken(c)
				var f = c.fighters[0]
				f.meter = 100
				if state == "hit":
					f.stun = 60; f.state = "hit"
				elif state == "air":
					f.grounded = false; f.y -= 100; f.vy = -3; f.state = "air"
				else:
					c._begin_move(f, c.definition(f).normals["5C"])
					f.connected = state == "blocked"; f.confirmed = false
					c.fighters[1].x = f.x + 280
				s.input(c, notation)
				check(f.meter == 100 and f.awakening_ticks > 0 and not s.events.any(func(e): return e.type == "super"), "invalid action retains resources " + cid + notation + state)
			var c := s.duel(cid); awaken(c)
			var f = c.fighters[0]
			f.meter = 100
			s.input(c, notation)
			c._resolve_contact(c._contact(c.fighters[1], f, c.definition(c.fighters[1]).normals["5A"], 999, 0, false))
			check(f.move == null and not f.presents_awakened_finisher(), "interrupted super clears launch appearance " + cid + notation)
			check((f.awakening_ticks == 0) == (kind == "max"), "interruption keeps mode decision " + cid + notation)
			check(s.events.filter(func(e): return e.type == "meter" and e.attacker == 0 and e.amount == -100).size() == 1, "interruption does not refund launch cost " + cid + notation)
			# Actual input launches the cinematic after resource payment.
			c = s.duel(cid); awaken(c); f = c.fighters[0]; f.meter = 100
			c.cinematic_moves[c.definition(f).motions[kind].id] = true
			s.input(c, notation)
			for n in range(100):
				if not c.cinematic.is_empty(): break
				s.tick(c)
			check(c.cinematic.get("awakened", false) and c.cinematic.get("move", "") == c.definition(f).motions[kind].id, "cinematic records real move and launch form " + cid + notation)
			var time: int = f.awakening_ticks
			s.advance(c, 20)
			check(f.awakening_ticks == time, "cinematic freezes remaining time " + cid + notation)
			c.finish_cinematic()
			check(c.fighters[1].hp == 1000 - (289 if kind == "max" else 200) and f.meter == 0, "cinematic applies all segments and spends once " + cid + notation)
			check(f.awakening_ticks == time and f.move == null, "cinematic completion preserves chosen mode result " + cid + notation)
		# A launched enhanced super keeps its damage when the mode expires mid-move.
		var c := s.duel(cid); awaken(c)
		var f = c.fighters[0]; f.meter = 100
		s.input(c, "236236A"); f.awakening_ticks = 1
		s.advance(c, 180)
		check(c.fighters[1].hp == 800 and f.awakening_ticks == 0 and f.attack_damage_percent == 110, "enhanced damage persists through expiry " + cid)
		# Launching MAX on the last actionable mode tick still pays its awakened cost.
		c = s.duel(cid); awaken(c); f = c.fighters[0]; f.meter = 100; f.awakening_ticks = 1
		f.buffer_action = {"type":"max"}; f.buffer_left = 10
		s.tick(c)
		check(f.move == c.definition(f).motions.max and f.meter == 0 and f.awakening_ticks == 0, "last active tick can cash out " + cid)

func _super_choice_damage() -> void:
	for cid in ["tanjiro", "zenitsu", "nezuko", "akaza"]:
		for target in ["tanjiro", "zenitsu", "nezuko", "akaza"]:
			for kind in ["super", "max"]:
				var c := s.duel(cid); awaken(c)
				var f = c.fighters[0]; var d = c.fighters[1]
				d.character = target; d.awakening_ticks = 500; d.awakening_duration = 600
				f.hp = 600; f.meter = 100
				var move = c.definition(f).motions[kind]
				c._begin_move(f, move)
				for segment in range(move.hit_count()):
					c._resolve_contact(c._contact(f, d, move, f.attack_instance, segment, false))
				c._flush_awakening_healing()
				var attack_percent := 110 if kind == "super" else 100
				var expected := int(move.damage * attack_percent * c.definition(d).awakening.received_percent / 10000)
				check(1000-d.hp == expected, "single-rounding damage and defense " + cid + target + kind)
				check(f.hp == 600 and f.meter == 0 and d.meter == 0, "supers cannot heal or gain meter " + cid + target + kind)

func _super_choice_practice_and_ai() -> void:
	for notation in ["236236A", "236236AC"]:
		var c := s.duel()
		var p := Practice.new()
		p.meter_mode = 3; p.awakening_infinite = true
		c.practice = true; c.awakening_infinite = true
		awaken(c)
		var f = c.fighters[0]
		f.meter = 0; p.after_step(c)
		check(f.meter == 0, "infinite meter never refills during awakening")
		s.input(c, notation)
		check(f.move == null and f.awakening_ticks > 0, "infinite awakening does not bypass cost " + notation)
		f.meter = 100; s.advance(c, 12); s.input(c, notation)
		check(f.meter == 0 and (f.awakening_ticks == 0) == (notation == "236236AC"), "infinite duration obeys chosen super " + notation)
		p.after_step(c)
		check(f.meter == (300 if notation == "236236AC" else 0), "refill only after mode actually ends " + notation)
	for time in [300, 121, 120, 60]:
		for meter in [0, 99, 100]:
			var finishes := 0
			for seed_value in range(4):
				var c := s.duel("zenitsu"); awaken(c)
				var f = c.fighters[0]; f.meter = meter
				s.input(c, "236A"); check(s.wait_contact(c), "AI choice setup confirms skill")
				f.awakening_ticks = time
				var ai := AI.new(seed_value)
				for n in range(12): ai.command(f.observable(), c.fighters[1].observable())
				for n in range(24):
					s.tick(c, ai.command(f.observable(), c.fighters[1].observable()))
					if f.move != null and f.move.is_super():
						finishes += 1
						check(f.move.kind == ("max" if time <= 120 else "super"), "AI chooses finisher by remaining mode time")
						check(f.meter == 0 and (f.awakening_ticks == 0) == (time <= 120), "AI choice pays stock and consumes mode only for MAX")
						break
				if meter < 100:
					check(not s.events.any(func(e): return e.type in ["super", "meter_empty"]), "AI never attempts unaffordable super")
			check(finishes > 0 if meter == 100 else finishes == 0, "AI real input follows cost requirement")