extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Flow = preload("res://scripts/round_flow.gd")
const Actor = preload("res://scripts/presentation/fighter_view.gd")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
const Sound = preload("res://scripts/audio.gd")
const Main = preload("res://scenes/main.tscn")
const Effects = preload("res://scripts/presentation/effects_view.gd")
var passed := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)

func advance(c: RefCounted, count: int, a: Dictionary = {}) -> void:
	var command := Combat.neutral()
	command.merge(a, true)
	for n in range(count):
		c.step([command, Combat.neutral()])

func duel() -> RefCounted:
	var c := Combat.new()
	c.phase = "fight"
	return c

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_intro()
	_outro()
	_timeouts()
	_visuals()
	await _pause_and_effects()
	for failure in failures: printerr("FAIL: ", failure)
	print("ROUND FLOW TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _intro() -> void:
	var c := Combat.new()
	var start_x: float = c.fighters[0].x
	check(c.round_cue().is_empty(), "actor opening precedes announcements")
	advance(c, Flow.ACTOR_INTRO, {"x":1,"buttons":1})
	check(c.round_cue().text == "ROUND 1", "numbered announcement follows actor opening")
	advance(c, Flow.ROUND - 1, {"x":1,"buttons":1})
	check(c.round_cue().text == "ROUND 1" and c.remaining == 3600, "ROUND lasts 54 ticks without clock drain")
	advance(c, 1)
	check(c.round_cue().text == "READY", "READY begins exactly at round boundary")
	advance(c, Flow.READY - 1)
	check(c.phase == "intro" and c.fighters[0].x == start_x, "intro ignores movement")
	advance(c, 1, {"x":1,"buttons":1})
	check(c.phase == "fight" and c.remaining == 3599 and c.fighters[0].x > start_x, "GO tick accepts movement and starts timer")
	check(c.round_cue().text == "GO!" and c.go_frames == Flow.GO, "GO starts at age zero")
	advance(c, 3, {"buttons":1})
	check(c.fighters[0].move != null, "new GO attack edge enters normal command recognition")
	advance(c, Flow.GO - 3)
	check(c.round_cue().is_empty(), "GO clears after 24 ticks")
	c = Combat.new()
	advance(c, Flow.OPENING + 5, {"buttons":1})
	check(c.fighters[0].move == null, "held pre-GO attack does not fire")
	c.practice = true
	c.new_match("tanjiro", "zenitsu")
	check(c.phase == "fight" and c.round_cue().is_empty(), "practice skips announcements")
	advance(c, 60)
	check(c.remaining == 3600, "practice never drains timer")

func _outro() -> void:
	var c = duel()
	c.fighters[1].hp = 0
	c.fighters[1].vx = 8
	c.fighters[0].meter = 120
	c.fighters[1].meter = 80
	c._finish_round()
	var initial_x: float = c.fighters[1].x
	check(c.phase_frames == Flow.OUTRO and c.wins == [1,0], "KO scores once and allocates 210 ticks")
	c._finish_round()
	check(c.wins == [1,0], "repeated settlement cannot score twice")
	advance(c, Flow.FREEZE)
	check(c.fighters[1].x == initial_x and c.presentation_speed() == 0.25, "configured KO freeze keeps lethal pose")
	check(c.round_cue().text == "K.O." and c.events[0].type == "ko_announce", "KO cue begins after freeze")
	advance(c, Flow.SLOW)
	check(is_equal_approx(c.outro_pose_ticks(1),7.5) and c.presentation_speed() == 1, "30 slow ticks advance pose only 7.5 ticks")
	advance(c, Flow.SETTLE)
	check(c.round_cue().text == "P1 WINS" and c.round_number == 1, "winner appears after 90 ticks without changing round number")
	var hp: int = c.fighters[1].hp
	advance(c, Flow.RESULT - 1, {"buttons":15,"x":1})
	check(c.phase == "round_end" and c.fighters[1].hp == hp and c.wins == [1,0], "outro input cannot hit or score")
	advance(c, 1)
	check(c.phase == "intro" and c.round_number == 2, "next round starts after 210 ticks")
	check(c.fighters[0].meter == 120 and c.fighters[1].meter == 80, "meter carries through longer outro")
	c.phase = "fight"
	c.fighters[1].hp = 0
	c._finish_round()
	advance(c, Flow.OUTRO)
	check(c.phase == "match_end" and c.match_winner == 0, "second victory reaches match result only after winner display")
	c.new_match("tanjiro","zenitsu")
	check(c.go_frames == 0 and c.outro_ticks == 0 and c.wins == [0,0], "restart clears presentation counters")
	c = duel()
	for f in c.fighters: f.hp = 0
	c._finish_round()
	advance(c, Flow.FREEZE)
	check(c.round_cue().text == "DOUBLE K.O." and c.wins == [0,0], "double KO has distinct cue and no score")
	advance(c, Flow.RESULT_AT - Flow.FREEZE)
	check(c.round_cue().text == "DRAW", "double KO resolves to draw")
	advance(c, Flow.RESULT)
	check(c.round_number == 1, "draw repeats same round")
	c = duel()
	c.fighters[1].hp = 0
	c.fighters[1].grounded = false
	c.fighters[1].y -= 75
	c.fighters[1].vy = -3
	c._finish_round()
	advance(c, Flow.RESULT_AT)
	check(c.fighters[1].grounded and c.outro_landed_at[1] > 0, "air KO lands during settlement")
	check(c.snapshot().has("outro_landed_at"), "presentation state belongs to deterministic snapshot")
	c = duel()
	c.fighters[1].hp = 0
	c.fighters[0].grounded = false
	c.fighters[0].y -= 100
	c.fighters[0].vy = -3
	c._finish_round()
	advance(c, Flow.FREEZE + Flow.SLOW)
	check(c.fighters[0].air_ticks == 7, "airborne winner animation uses quarter-speed ticks during KO slow motion")


func _timeouts() -> void:
	var c = duel()
	c.fighters[1].hp = 500
	c.remaining = 1
	advance(c, 1)
	check(c.reason == "TIME UP" and c.presentation_speed() == 1 and c.round_cue().text == "TIME UP", "timeout bypasses freeze and slow motion")
	advance(c, Flow.RESULT_AT)
	check(c.round_cue().text == "P1 WINS", "timeout winner uses same result stage")
	c = duel()
	c.round_open_meter.assign([40,60])
	c.remaining = 1
	advance(c, 1)
	check(c.reason == "DRAW" and c.round_cue().text == "TIME UP", "equal timeout first announces time up")
	advance(c, Flow.RESULT_AT)
	check(c.round_cue().text == "DRAW", "equal timeout then announces draw")
	advance(c, Flow.RESULT)
	check(c.fighters[0].meter == 40 and c.fighters[1].meter == 60, "draw restores opening meters")

func _visuals() -> void:
	var c = duel()
	var catalog := Catalog.new()
	var actor := Actor.new()
	actor.combat = c
	actor.fighter = c.fighters[1]
	actor.visual = catalog.characters.zenitsu
	c.fighters[1].hp = 0
	c._finish_round()
	actor.sync(0, true)
	check(actor.clip != "round_defeat", "freeze retains the finishing contact pose")
	advance(c, Flow.RESULT_AT)
	actor.sync(0, false)
	check(actor.frame_index == actor.visual.frames.get_frame_count("round_defeat") - 1, "KO holds final grounded drawing")
	actor.fighter = c.fighters[0]
	actor.visual = catalog.characters.tanjiro
	actor.sync(0, false)
	check(actor.clip == "round_victory" and actor.frame_index == 0, "winner animation begins during round end")
	advance(c, 30)
	actor.sync(0, false)
	check(actor.frame_index > 0, "winner animation progresses before result menu")
	actor.free()
	var sound := Sound.new()
	root.add_child(sound)
	var cues: Array = sound.cues([{"type":"hit","attacker":0},{"type":"round_end","knockout":true}],c)
	check(cues.size() == 1 and cues[0].kind == "hit", "final impact cue survives KO without early result sound")
	check(sound.cues([{"type":"ko_announce"}],c)[0].kind == "round_end", "KO sound follows announced stage")
	sound.free()


func _pause_and_effects() -> void:
	var game := Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	game.mode = "local"
	game.start_match()
	game.combat.phase = "fight"
	game.combat.fighters[1].hp = 0
	game.combat._finish_round()
	game.view.consume([{"type":"hit","attacker":0,"position":Vector2(480,250)},{"type":"round_end","knockout":true}])
	game.view._process(0)
	var spark_count: int = game.view.effects.sparks.size()
	var spark_life: float = game.view.effects.sparks[0].life
	game.view.effects._process(0.2)
	check(spark_count > 0 and game.view.effects.sparks[0].life == spark_life, "lethal sparks survive and freeze with KO")
	for stage in [0,20,100]:
		while game.combat.outro_ticks < stage: game._physics_process(1.0/60)
		game.view._process(0)
		game.set_paused(true)
		var before: Dictionary = game.combat.snapshot()
		var pose: float = game.view.fighters[0].clock_ticks
		for n in range(12):
			game._physics_process(1.0/60)
			game.view._process(1.0/60)
			game.view.effects._process(1.0/60)
		check(game.combat.snapshot() == before and game.view.fighters[0].clock_ticks == pose, "pause freezes KO, slow motion and result stages")
		game.set_paused(false)
	game.start_match()
	check(game.combat.outro_ticks == 0 and game.view.effects.sparks.is_empty(), "new match clears preserved lethal effects")
	game.queue_free()
	await process_frame
