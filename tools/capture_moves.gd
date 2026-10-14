extends SceneTree
## Records a scripted input sequence for one fighter in a real match, for art review.
## Run with a window and a fixed clock:
##   godot --path . --fixed-fps 60 --script res://tools/capture_moves.gd -- --character=tanjiro --script=idle:60,walk:50,idle:20,5A,idle:30,236A
## Steps: idle:N / walk:N / back:N hold for N ticks; dK:N holds numpad direction K
## (d1:40 is the crouching guard); p2=NOTATION/K makes the opponent press NOTATION while
## this fighter holds K (p2=2B/1 is a blocked low, p2=2D a sweep knockdown) and waits
## until both have recovered; gap:N puts the opponent N px in front; any other token is a move notation (5A, 2C, 236A, 6B,
## j236A…) pressed like a player and followed by its full recovery. A leading "intro"
## step first records the real round intro of both fighters from the round start.
## Frames go to artifacts/art-v3/<character>/moves/frame-NNNN.png.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
var game: Node2D
var saved := 0
var folder := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var character := "tanjiro"
	var steps := "idle:60,walk:50,idle:20,5A,idle:30,236A,idle:40".split(",")
	var form := "normal"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--character="):
			character = argument.trim_prefix("--character=")
		elif argument.begins_with("--script="):
			steps = argument.trim_prefix("--script=").split(",")
		elif argument.begins_with("--form="):
			form = argument.trim_prefix("--form=")
	root.size = Vector2i(1280, 720)
	folder = "res://artifacts/art-v3/%s/moves/" % character
	DirAccess.make_dir_recursive_absolute(folder)
	for stale in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder + stale)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	game.characters.assign([character, "zenitsu" if character != "zenitsu" else "tanjiro"])
	game.start_match()
	var model = game.combat
	if steps.size() > 0 and steps[0] == "intro":
		steps.remove_at(0)
		while model.phase == "intro":
			await _tick(Combat.neutral())
	model.phase = "fight"
	model.practice = true
	model.fighters[0].x = 440
	model.fighters[1].x = 510
	model.fighters[0].meter = 300
	if form == "awakened":
		model.awakening_infinite = true
		model.fighters[0].awakening_ticks = 600
		model.fighters[0].awakening_duration = 600
	game.view.camera.reset(model.fighters)
	game.view.stage.sync_camera()
	for step: String in steps:
		var parts := step.split(":")
		var count := int(parts[1]) if parts.size() > 1 else 0
		if step.begins_with("p2="):
			var versus := step.trim_prefix("p2=").split("/")
			await _versus(versus[0], int(versus[1]) if versus.size() > 1 else 5)
			continue
		if parts[0] == "gap":
			# Puts the opponent `count` px in front (its attacks must reach).
			model.fighters[1].x = model.fighters[0].x + count * model.fighters[0].facing
			continue
		if parts[0].length() == 2 and parts[0][0] == "d":
			await _hold(_direction(int(parts[0][1]), model.fighters[0].facing), count)
			continue
		match parts[0]:
			"idle": await _hold(Combat.neutral(), count)
			"walk": await _hold({"x": 1, "y": 0, "buttons": 0}, count)
			"back": await _hold({"x": -1, "y": 0, "buttons": 0}, count)
			_:
				var chain := parts[0].split(">")
				for index in range(chain.size()):
					await _move(chain[index], index < chain.size() - 1)
	game.queue_free()
	await process_frame
	print("MOVE CAPTURE: %d frames" % saved)
	quit()

func _tick(command: Dictionary, other: Dictionary = Combat.neutral()) -> void:
	var model = game.combat
	model.step([command, other])
	game.view.consume(model.events)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + "frame-%04d.png" % saved)
	saved += 1

func _hold(command: Dictionary, count: int) -> void:
	for n in range(count):
		await _tick(command)

## Numpad direction relative to `facing` as a raw command.
static func _direction(direction: int, facing: int, buttons: int = 0) -> Dictionary:
	return {"x": ((direction - 1) % 3 - 1) * facing, "y": 1 - int((direction - 1) / 3), "buttons": buttons}

## The opponent presses `notation` while this fighter holds numpad `hold`; returns once
## both fighters are back on their feet and free.
func _versus(notation: String, hold: int) -> void:
	var digits := ""
	var mask := 0
	for token in notation:
		if token in "123456789": digits += token
		elif token in "ABCD": mask |= 1 << "ABCD".find(token)
	if digits.is_empty(): digits = "5"
	var model = game.combat
	for n in range(digits.length()):
		await _tick(_direction(hold, model.fighters[0].facing), _direction(int(digits[n]), model.fighters[1].facing, mask if n == digits.length() - 1 else 0))
	for n in range(240):
		var mine = model.fighters[0]
		var other = model.fighters[1]
		if n > 6 and other.move == null and mine.move == null and mine.stun == 0 and mine.grounded and mine.state != "knockdown":
			break
		await _tick(_direction(hold, mine.facing))

## Presses one notation; with `link` it returns as soon as the move connects, so the
## next press of a target-combo string lands inside the window.
func _move(notation: String, link: bool = false) -> void:
	var facing: int = game.combat.fighters[0].facing
	var airborne := notation.begins_with("j")
	if airborne:
		notation = notation.substr(1)
		await _tick({"x": 0, "y": -1, "buttons": 0})
		await _hold(Combat.neutral(), 10)
	var digits := ""
	var mask := 0
	for token in notation:
		if token in "123456789": digits += token
		elif token in "ABCD": mask |= 1 << "ABCD".find(token)
	if digits.is_empty(): digits = "5"
	for n in range(digits.length()):
		var direction := int(digits[n])
		await _tick({"x": ((direction - 1) % 3 - 1) * facing, "y": 1 - int((direction - 1) / 3), "buttons": mask if n == digits.length() - 1 else 0})
	for n in range(160):
		var f = game.combat.fighters[0]
		if link and f.connected:
			break
		if n > 6 and f.move == null and f.stun == 0 and f.grounded:
			break
		await _tick(Combat.neutral())
