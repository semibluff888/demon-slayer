extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
var passed := 0
var failures: Array[String] = []
class SimulatedRouter extends "res://scripts/input_router.gd":
	var commands: Array = [{}, {}]
	func sample(device: String) -> Dictionary:
		var result := {"x":0,"y":0,"buttons":0}
		result.merge(commands[1 if device == "keyboard:1" else 0],true)
		return result
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label); printerr("FAIL: ", label)
func _run() -> void:
	var game = Main.instantiate()
	game.settings.path = "res://artifacts/cinematic-handoff-settings.cfg"
	root.add_child(game)
	game.set_physics_process(false)
	game.view.set_process(false)
	game.view.cinematic.set_process(false)
	game.sound.muted = true
	game.sound.reset_audio()
	game.router = SimulatedRouter.new()
	game.mode = "local"
	for cid in ["tanjiro", "nezuko", "zenitsu", "akaza"]:
		for kind in ["super", "max"]:
			var slot := 1 if kind == "max" else 0
			game.characters.assign([cid,"akaza"] if slot == 0 else ["tanjiro",cid])
			game.start_match()
			var model = game.combat
			model.phase = "fight"
			var a = model.fighters[slot]
			var d = model.fighters[1-slot]
			a.x = 480; d.x = 515; a.facing = 1; d.facing = -1; a.meter = 300
			model.cinematic_moves = {cid + "_" + kind:true}
			model._begin_move(a,model.definition(a).motions[kind])
			for n in range(130):
				model.step([Combat.neutral(),Combat.neutral()])
				if not model.cinematic.is_empty(): break
			var cinema = game.view.cinematic
			# Enter the post-video path directly; no media playback or capture needed.
			cinema.streams.clear()
			cinema.begin()
			game.view._process(0.0)
			var label: String = cid + " " + kind
			check(cinema.phase == "tail" and not game.view.hud.cinematic_mode and game.gui.visible, label + " HUD restored at video end")
			check(not game.view.stage.freeze, label + " stage animation resumes at video end")
			if cid == "zenitsu": check(is_equal_approx(cinema.residual_effect.rotation, PI/2), label + " lightning reversed")
			cinema._process(0.64)
			check(cinema.blocks_combat(), label + " controls wait for recovery")
			game.set_paused(true)
			cinema._process(0.5)
			check(is_equal_approx(cinema.tail_time,0.64), label + " pause freezes tail")
			game.set_paused(false)
			cinema._process(0.02)
			game.view._process(0.0)
			check(not cinema.blocks_combat() and cinema.active, label + " controls released before victim completion")
			check(game.view.fighters[slot].cinematic_pose.is_empty() and game.view.fighters[slot].texture != null, label + " actor has continuous texture")
			var old_x: float = a.x
			var victim_x: float = d.x
			var stun: int = d.stun
			game.router.commands[slot] = {"x":-1}
			for n in range(5): game._physics_process(1.0/60)
			check(a.x < old_x and d.x == victim_x and d.stun == stun, label + " main loop moves only attacker")
			game.router.commands[slot] = {"x":-1,"y":-1}
			game._physics_process(1.0/60)
			game.view._process(1.0/60)
			var y: float = a.y
			var vy: float = a.vy
			var texture = game.view.fighters[slot].texture
			check(not a.grounded and y < model.FLOOR_Y, label + " jump accepted during tail")
			cinema._process(0.5)
			check(not cinema.active and model.cinematic.is_empty(), label + " tail completes")
			check(a.y == y and a.vy == vy and not a.grounded, label + " completion does not snap attacker to floor")
			check(game.view.fighters[slot].texture == texture and game.view.fighters[1-slot].texture != null, label + " no blank frame on completion")
			check(game.view.fighters[1-slot].frame_index == 11, label + " victim holds final fallen pose")
			game.router.commands = [{},{}]
	game.sound.reset_audio()
	game.queue_free()
	await process_frame
	print("CINEMATIC HANDOFF: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)
