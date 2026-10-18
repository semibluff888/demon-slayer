extends SceneTree
## Regression for the 「大正墨金」front end: bundled glyph coverage, round-cue
## mapping, freeze semantics of the new HUD and effect state, mouse-transparent
## decoration, live hit areas during entry motion, and device-aware prompts.
const Main = preload("res://scenes/main.tscn")
const Banner = preload("res://scripts/presentation/round_banner.gd")
const Effects = preload("res://scripts/presentation/effects_view.gd")
const PromptBar = preload("res://scripts/ui/prompt_bar.gd")
const Glyphs = preload("res://scripts/ui/command_glyphs.gd")
const Support = preload("res://tests/combat_test_support.gd")
const BUNDLED := ["res://art/fonts/NotoSansSC-ui.ttf", "res://art/fonts/NotoSerifSC-title.ttf", "res://art/fonts/MaShanZheng-display.ttf"]
var passed := 0
var failures: Array[String] = []
var game: Node2D
var helper := Support.new()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)

func _run() -> void:
	create_timer(60).timeout.connect(func(): printerr("UI redesign watchdog expired"); quit(1))
	_check_glyphs()
	_check_banner()
	_check_prompts()
	_check_effects()
	game = Main.instantiate()
	game.settings.path = "res://artifacts/ui_redesign_tests-settings.cfg"
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	game.settings.cinematic_enabled = false
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	await process_frame
	await _check_screens()
	_check_hud_freeze()
	_check_hud_hitstop()
	game.queue_free()
	await process_frame
	for failure in failures:
		printerr("FAIL: ", failure)
	print("UI REDESIGN TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

## Every non-ASCII character the game can compose must exist in each bundled
## CJK face, so release builds never fall back to tofu or system fonts.
func _check_glyphs() -> void:
	var text := ""
	for directory in ["res://scripts", "res://resources", "res://moves"]:
		text += _collect(directory)
	var characters := {}
	for character in text:
		var code := character.unicode_at(0)
		if code > 0x7F and code not in [0xFEFF] and not (code >= 0x2500 and code <= 0x257F):
			characters[code] = true
	check(characters.size() > 300, "glyph scan found the UI repertoire")
	for path: String in BUNDLED:
		var font: FontFile = load(path)
		var missing := ""
		for code: int in characters:
			# Han text and CJK punctuation must exist in every face; symbols
			# (arrows, ∞, ·) only need the body face that draws them.
			var han := (code >= 0x3000 and code <= 0x303F) or (code >= 0x4E00 and code <= 0x9FFF) or (code >= 0xFF00 and code <= 0xFFEF)
			if (han or path == BUNDLED[0]) and not font.has_char(code):
				missing += String.chr(code)
		check(missing.is_empty(), "%s covers all UI text; missing: %s" % [path.get_file(), missing.substr(0, 40)])
	var numeric: FontFile = load("res://art/fonts/Oswald-numeric.ttf")
	for character in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.:/!+-":
		check(numeric.has_char(character.unicode_at(0)), "numeric face covers " + character)

func _collect(directory: String) -> String:
	var text := ""
	for entry in ResourceLoader.list_directory(directory):
		var path := directory.path_join(entry)
		if entry.ends_with("/"):
			text += _collect(path.trim_suffix("/"))
		elif entry.ends_with(".gd") or entry.ends_with(".tres"):
			text += FileAccess.get_file_as_string(path)
	return text

func _check_banner() -> void:
	var expected := {"ROUND 1": ["第壹回合", "ROUND 1"], "ROUND 12": ["第12回合", "ROUND 12"], "READY": ["全集中", "READY"],
		"GO!": ["开战", "FIGHT"], "K.O.": ["K.O.", "胜负已分"], "DOUBLE K.O.": ["DOUBLE K.O.", "两败俱伤"],
		"TIME UP": ["时间到", "TIME UP"], "DRAW": ["平局", "DRAW"], "P2 WINS": ["胜", "P2 WINS"], "CUSTOM": ["CUSTOM", ""]}
	for cue: String in expected:
		var layout: Dictionary = Banner.compose(cue)
		check(layout.main == expected[cue][0] and layout.get("kicker", "") == expected[cue][1], "banner maps " + cue)
	check(Banner.compose("P1 WINS", "灶门炭治郎").sub == "灶门炭治郎", "winner banner keeps the fighter name")

func _check_prompts() -> void:
	var kinds := func(value: String) -> Array:
		return PromptBar.pieces(value).map(func(part: Dictionary): return part.kind)
	check(kinds.call("U 确认 · I 返回") == ["key", "text", "gap", "key", "text"], "keyboard hints become keycaps")
	check(kinds.call("十字键 · A 确认 · B 返回") == ["text", "gap", "pad", "text", "gap", "pad", "text"], "pad hints become face buttons")
	check(kinds.call("P1 U 确认    P2 Num5 确认") == ["chip", "key", "text", "space", "chip", "key", "text"], "local hints keep player chips")
	check(kinds.call("请选择不同设备") == ["text"], "warnings stay plain text")
	var tokens := Glyphs.tokens("236236 + A+C").map(func(token: Dictionary): return token.kind)
	check(tokens == ["dir", "dir", "dir", "dir", "dir", "dir", "plus", "button", "plus", "button"], "command notation becomes glyphs")

func _check_effects() -> void:
	var model = helper.duel("tanjiro")
	var effects := Effects.new()
	effects.combat = model
	var move: Resource = model.definition(model.fighters[0]).motions["super"]
	effects.consume([{"type": "hit", "attacker": 0, "move": move.id, "segment": 0, "position": Vector2(520, 250)},
		{"type": "block", "attacker": 0, "move": move.id, "segment": 0, "position": Vector2(520, 250)},
		{"type": "clash", "attacker": 0, "position": Vector2(500, 250)}])
	check(not effects.flashes.is_empty() and not effects.streaks.is_empty() and not effects.shards.is_empty(), "impacts add light, streak and guard layers")
	check(not effects.motes.is_empty() and effects.screen_flash > 0, "super contact adds element motes and a brief screen flash")
	var held := [effects.flashes.duplicate(true), effects.streaks.duplicate(true), effects.motes.duplicate(true), effects.screen_flash]
	effects.freeze = true
	effects._process(0.5)
	check([effects.flashes, effects.streaks, effects.motes, effects.screen_flash] == held, "hitstop and pause hold the new layers")
	effects.freeze = false
	effects.playback_speed = 0.0
	effects._process(0.5)
	check([effects.flashes, effects.streaks, effects.motes, effects.screen_flash] == held, "zero presentation speed holds the new layers")
	effects.playback_speed = 1.0
	effects._process(0.5)
	check(effects.flashes.is_empty() and effects.streaks.is_empty() and effects.shards.is_empty() and effects.motes.is_empty() and effects.screen_flash == 0, "new layers expire within half a second")
	effects.consume([{"type": "hit", "attacker": 0, "move": move.id, "segment": 0, "position": Vector2(520, 250)}])
	effects.consume([{"type": "round_end"}])
	check(effects.flashes.is_empty() and effects.motes.is_empty(), "round finish clears the new layers")
	effects.free()

func _decorations_ignore_mouse(screen: String) -> void:
	for child in game.gui.get_children():
		if child is Control and not (child is BaseButton or child is Range or child is ScrollContainer):
			check(child.mouse_filter == Control.MOUSE_FILTER_IGNORE, "decoration ignores the mouse on %s: %s" % [screen, child.name])

func _check_screens() -> void:
	game.show_title()
	await process_frame
	check(game.gui.actions.mode_cpu.get_global_rect().has_point(Vector2(210, 400)), "title hit area is live during entry motion")
	_decorations_ignore_mouse("title")
	var confirm := "%s 确认" % game.router.key_name(game.router.current_keys(0)[4])
	check(game.gui.footer.text.begins_with(confirm), "title prompts start on the keyboard")
	var pad := InputEventJoypadButton.new()
	pad.device = 0
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	pad.pressed = true
	game._input(pad)
	await process_frame
	check(game.menu_device == "pad:0" and game.gui.footer.text.begins_with("十字键") and game.gui.footer.text.contains("A 确认"), "title prompts follow the gamepad")
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.pressed = true
	game._input(key)
	await process_frame
	check(game.menu_device == "keyboard:0" and game.gui.footer.text.begins_with(confirm), "title prompts return to the keyboard")
	game.choose_mode("local")
	await process_frame
	_decorations_ignore_mouse("setup")
	check(game.gui.fighter_names.size() == 2 and game.gui.fighter_names[1].text == game.catalog.characters[game.characters[1]].display_name, "select names follow the picks")
	game.selection.confirm(0)
	game.selection.confirm(1)
	game.selection.tick(10.0)  # play out the matchup lock-in
	await process_frame
	check(game.screen == "stage" and game.gui.preview != null and game.gui.preview.stage == game.catalog.stages[game.stage_id], "stage preview follows the selection")
	_decorations_ignore_mouse("stage")
	game.start_match()
	game.set_paused(true)
	await process_frame
	_decorations_ignore_mouse("pause")
	game.show_settings()
	await process_frame
	_decorations_ignore_mouse("settings")
	check(game.gui.actions.key_0_4.keycap and not game.gui.actions.settings_back.keycap, "key bindings render as keycaps")
	game.close_settings()
	game.show_help()
	await process_frame
	check(game.gui.actions.guide_basics.tab and game.gui.actions.guide_basics.selected, "help pages use tabs")
	game.close_help()
	game.set_paused(false)
	game.mode = "cpu"
	game.start_match()
	game.combat.phase = "match_end"
	game.combat.match_winner = 1
	game.combat.wins.assign([1, 2])
	game.show_result()
	await process_frame
	_decorations_ignore_mouse("result")
	game.start_match()

func _check_hud_freeze() -> void:
	var hud = game.view.hud
	var model = game.combat
	# The world view refreshes these each battle frame; set them explicitly here.
	hud.frozen = false
	hud.held = false
	hud.playback_speed = 1.0
	model.phase = "fight"
	model.fighters[0].combo = 9
	model.fighters[0].combo_display = 50
	model.fighters[1].hp = 700
	model.wins.assign([1, 0])
	hud._process(1.0 / 60)
	check(hud.combo_fade[0] > 0 and hud.damage_flash[1] > 0 and hud.win_pop[0] > 0, "HUD reacts to combo, damage and round wins")
	var state := [hud.time, hud.combo_fade.duplicate(), hud.damage_flash.duplicate(), hud.win_pop.duplicate()]
	hud.frozen = true
	hud._process(0.5)
	check([hud.time, hud.combo_fade, hud.damage_flash, hud.win_pop] == state, "pause holds HUD presentation state")
	hud.frozen = false
	hud.playback_speed = 0.0
	hud._process(0.5)
	check([hud.time, hud.combo_fade, hud.damage_flash, hud.win_pop] == state, "KO freeze holds HUD presentation state")
	hud.playback_speed = 1.0
	model.fighters[0].combo_display = 0
	hud._process(0.5)
	check(hud.combo_fade[0] == 0 and hud.damage_flash[1] == 0, "combo plate fades out after the combo ends")
	hud.reset_effects()
	check(hud.combo_fade == [0.0, 0.0] and hud.wins_seen == [1, 0], "HUD reset clears fades and adopts current wins")

## Hitstop and super freeze hold impact feedback with the stage and effects,
## while the meter spend and awakening reveal keep playing through the freeze.
func _check_hud_hitstop() -> void:
	var hud = game.view.hud
	var model = game.combat
	var frame := func() -> void:
		game.view._process(1.0 / 60) # The world view sets the HUD flags first.
		hud._process(1.0 / 60)
	model.phase = "fight"
	model.fighters[0].combo = 3
	model.fighters[0].combo_display = 50
	model.hitstop = 6
	model.fighters[1].hp -= 80
	frame.call()
	check(hud.held and is_equal_approx(hud.damage_flash[1], 0.14), "a hit flashes at full strength when hitstop begins")
	hud.combo_pop[0] = 0.2
	hud.awakening_reveal[0] = 0.85
	hud.spent_time[0] = 0.9
	var state := [hud.time, hud.damage_flash.duplicate(), hud.trailing.duplicate(), hud.combo_pop.duplicate(), hud.combo_fade.duplicate()]
	for n in range(5):
		frame.call()
	check([hud.time, hud.damage_flash, hud.trailing, hud.combo_pop, hud.combo_fade] == state, "hitstop holds HUD impact feedback")
	check(hud.awakening_reveal[0] < 0.85 and hud.spent_time[0] < 0.9, "awakening reveal and meter spend play through the freeze")
	model.hitstop = 0
	model.super_freeze = 12
	frame.call()
	check(hud.held and hud.damage_flash == state[1] and hud.trailing == state[2], "super freeze holds HUD impact feedback")
	model.super_freeze = 0
	frame.call()
	check(not hud.held and hud.damage_flash[1] < 0.14 and hud.trailing[1] < state[2][1], "HUD impact feedback resumes after the freeze")
