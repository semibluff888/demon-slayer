extends SceneTree
## BGM: library data, saved choices, and the director's scene, round, pause, loop and
## preview rules, driven on a virtual clock (the headless audio driver keeps no real time).
const Main = preload("res://scenes/main.tscn")
const Settings = preload("res://scripts/game_settings.gd")
const Library = preload("res://scripts/music/library.gd")
const OUT = "res://artifacts/music-tests"
var game: Node
var music: Node
var library := Library.new()
var passed := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(label)

func step(seconds: float, dt: float = 0.05) -> void:
	var elapsed := 0.0
	while elapsed < seconds - 0.000001:
		var tick := minf(dt, seconds - elapsed)
		music.advance(tick)
		elapsed += tick

func active() -> int:
	return music.decks.filter(func(deck) -> bool: return not deck.track.is_empty()).size()

func near(a: float, b: float, tolerance: float = 0.15) -> bool:
	return absf(a - b) <= tolerance

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_library_checks()
	_settings_checks()
	var config := Settings.new()
	config.path = OUT + "/settings.cfg"
	config.save_config()
	game = Main.instantiate()
	game.settings.path = config.path
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	music = game.music
	check(not music.enabled and music.playing().is_empty(), "music stays off under scripted trees")
	music.enabled = true
	music.virtual_clock = true
	music.set_process(false)
	music.rng.seed = 7
	await process_frame
	_title_and_select()
	_battle_flow()
	_settings_preview()
	_follow_and_random()
	_exit_options()
	_buses()
	game.queue_free()
	await process_frame
	# Let the audio thread retire the stopped playbacks before the engine checks for leaks.
	await create_timer(0.25).timeout
	for failure in failures:
		printerr("FAIL: ", failure)
	print("MUSIC TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _library_checks() -> void:
	check(library.tracks.size() == 8, "eight tracks")
	for id: String in library.tracks:
		var track: Dictionary = library.tracks[id]
		var stream := load(library.file(id)) as AudioStreamOggVorbis
		check(stream != null and not stream.loop, "%s loads as a non-looping Vorbis stream" % id)
		if stream == null:
			continue
		check(near(stream.get_length(), float(track.duration), 0.5), "%s duration matches the library" % id)
		check(not str(track.title).is_empty(), "%s has a display name" % id)
		for scene: String in track.cues:
			var cue: Dictionary = track.cues[scene]
			var fade := library.crossfade(id, scene)
			check(float(cue.start) >= 0 and float(cue.start) < float(cue.loop_end), "%s/%s starts inside the loop" % [id, scene])
			check(float(cue.loop_end) <= stream.get_length() and float(cue.loop_end) - float(cue.loop_start) > 2 * fade, "%s/%s loop fits the file and its crossfade" % [id, scene])
			if cue.has("climax"):
				check(float(cue.climax) >= float(cue.loop_start) and float(cue.climax) < float(cue.loop_end) - fade, "%s climax lies in the loop" % id)
	for scene: String in Library.SCENES:
		var choices := library.choices(scene)
		check(library.default_choice(scene) in choices, "%s default is offered" % scene)
		for choice: String in choices:
			check(library.tracks.has(choice) or library.labels.has(choice), "%s choice %s is known" % [scene, choice])
			if library.tracks.has(choice):
				check(library.tracks[choice].cues.has(scene), "%s has cue points for %s" % [choice, scene])
	check(library.default_choice("title") == "homura_movie" and library.default_choice("battle") == Library.RANDOM, "title defaults to 炎, battle to random")
	check(near(float(library.cue("hashira_infinity_castle", "select").start), 172.0, 0.01), "select music enters at 2:52")
	check(library.candidates("battle").size() == 4 and library.candidates("title").size() == 4, "four title and four battle tracks")
	for name: String in ["boot", "menu", "battle_in", "battle_out", "loop", "climax", "pause_in", "pause_out", "round_end_in", "round_restore", "cinematic_in", "cinematic_out", "result", "preview"]:
		check(library.mix.fades.has(name), "fade %s defined" % name)
	check(library.level_db("title") > library.level_db("select") and library.level_db("select") > library.level_db("battle") and library.level_db("battle") > library.level_db("result"), "menus sit louder than the fight, results lowest")

func _settings_checks() -> void:
	var settings := Settings.new()
	settings.path = OUT + "/missing.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.path))
	settings.load_config()
	check(settings.music == {"title": "homura_movie", "select": "hashira_infinity_castle", "battle": "random"}, "fresh settings use the library defaults")
	check(near(settings.music_volume, 0.7, 0.001) and near(settings.sfx_volume, 1.0, 0.001), "music 70 %, effects 100 % by default")
	var legacy := ConfigFile.new()
	legacy.set_value("audio", "muted", false)
	legacy.set_value("audio", "volume", 0.6)
	legacy.save(OUT + "/legacy.cfg")
	settings.path = OUT + "/legacy.cfg"
	settings.load_config()
	check(near(settings.volume, 0.6, 0.001) and near(settings.music_volume, 0.7, 0.001) and settings.music.battle == "random", "older config keeps its volume and gains music defaults")
	var broken := ConfigFile.new()
	broken.set_value("audio", "music_volume", "loud")
	broken.set_value("audio", "sfx_volume", 4.0)
	broken.set_value("music", "title", "not_a_track")
	broken.set_value("music", "select", "rengoku_kyojuro")
	broken.set_value("music", "battle", "shinobu_vs_doma")
	broken.save(OUT + "/broken.cfg")
	settings.path = OUT + "/broken.cfg"
	settings.load_config()
	check(near(settings.music_volume, 0.7, 0.001) and near(settings.sfx_volume, 1.0, 0.001), "invalid levels fall back or clamp")
	check(settings.music.title == "homura_movie" and settings.music.select == "hashira_infinity_castle" and settings.music.battle == "shinobu_vs_doma", "unknown or misplaced tracks fall back per scene")
	settings.music.title = "random"
	settings.music_volume = 0.25
	settings.save_config()
	var loaded := Settings.new()
	loaded.path = settings.path
	loaded.load_config()
	check(loaded.music.title == "random" and near(loaded.music_volume, 0.25, 0.001), "music choices and level round-trip")

func _title_and_select() -> void:
	step(0.05)
	var title: RefCounted = music.lead
	check(music.playing() == "homura_movie" and music.scene == "title", "the title plays 炎 by default")
	check(title.gain < 0.2 and near(music.level_db, library.level_db("title"), 0.01), "boot fades the deck in at the title level")
	step(1.1)
	check(near(title.gain, 1.0, 0.001) and near(title.player.volume_db, library.level_db("title"), 0.05), "boot fade completes")
	game.show_title()
	step(0.1)
	check(music.lead == title and active() == 1, "rebuilding the title screen does not restart its music")
	step(30.0)
	game.choose_mode("cpu")
	step(0.6)
	var select: RefCounted = music.lead
	check(music.playing() == "hashira_infinity_castle" and select.scene == "select" and near(select.position, 172.6), "select crossfades in at 2:52")
	var power: float = pow(sin(select.gain * PI / 2), 2) + pow(sin(title.gain * PI / 2), 2)
	check(active() == 2 and near(power, 1.0, 0.05), "title to select is an equal-power crossfade")
	check(not music.next_battle.is_empty() and (music.streams.has(music.next_battle) or music.requested.has(library.file(music.next_battle))), "select prefetches the next battle track")
	step(0.7)
	check(active() == 1 and near(float(music.resume.homura_movie), 31.2 + library.fade("menu"), 0.2), "title track stops and remembers where it was")
	game.show_stages()
	step(0.2)
	check(music.lead == select, "stage select keeps the select music")
	game.show_title()
	step(0.1)
	check(music.playing() == "homura_movie" and music.lead.position > 32.0, "returning to the title resumes its track")
	game.show_setup()
	step(0.3)
	game.show_title()
	step(0.05)
	check(music.playing() == "homura_movie" and active() <= 3, "a quick back-out reverses the fade")
	step(1.5)
	check(active() == 1, "reversed fade settles on one deck")

func _battle_flow() -> void:
	# The same piece in select and battle carries straight on.
	game.settings.music.battle = "hashira_infinity_castle"
	game.show_setup()
	game.show_stages()
	step(2.0)
	var carried: RefCounted = music.lead
	var before: float = carried.position
	game.start_match()
	step(0.1)
	check(music.lead == carried and carried.scene == "battle" and carried.position > before, "select music carries on into the same battle track")
	step(1.1)
	check(near(music.level_db, library.level_db("battle"), 0.05), "battle settles at the battle level")
	# Random never repeats back to back.
	game.settings.music.battle = "random"
	var picks: Array[String] = []
	for match_index in range(20):
		game.start_match()
		step(0.05)
		picks.append(music.battle_track)
	var repeats := 0
	for i in range(1, picks.size()):
		if picks[i] == picks[i - 1]:
			repeats += 1
	var distinct := {}
	for pick in picks:
		distinct[pick] = true
	check(repeats == 0 and distinct.size() >= 3, "random battle music never repeats back to back")
	check(music.playing() == picks[-1], "each match plays its pick")
	# A fixed track restarts on a rematch from the pause menu.
	game.settings.music.battle = "rengoku_kyojuro"
	game.start_match()
	step(2.5)
	check(music.playing() == "rengoku_kyojuro" and near(music.lead.position, 2.5, 0.1), "fixed battle track starts at its entry")
	step(3.0)
	var restarted: RefCounted = music.lead
	game.start_match()
	step(0.05)
	check(music.lead != restarted and music.lead.position < 0.2, "restarting the match restarts the track")
	step(1.1)
	# Loop: crossfade from loop_end back to loop_start.
	var cue := library.cue("rengoku_kyojuro", "battle")
	var fade := library.crossfade("rengoku_kyojuro", "battle")
	var old: RefCounted = music.lead
	old.position = float(cue.loop_end) - fade - 0.1
	step(0.2)
	check(music.lead != old and old.looping and near(music.lead.position, float(cue.loop_start) + 0.1, 0.1), "the loop crossfades back to loop_start")
	step(fade + 0.1)
	check(active() == 1 and music.lead.track == "rengoku_kyojuro", "loop handoff settles")
	var snapshot: Dictionary = game.combat.snapshot()
	step(5.0)
	check(game.combat.snapshot() == snapshot, "music never touches combat state")
	# Pause: duck plus low-pass, released on resume.
	var music_bus := AudioServer.get_bus_index(&"Music")
	game.set_paused(true)
	step(0.4)
	var filter := AudioServer.get_bus_effect(music_bus, 0) as AudioEffectLowPassFilter
	check(near(music.level_db, library.level_db("battle") + library.duck_db("pause"), 0.05) and AudioServer.is_bus_effect_enabled(music_bus, 0) and near(filter.cutoff_hz, float(library.mix.pause_lowpass_hz), 1.0), "pause ducks and muffles the music")
	check(music.lead.player.playing, "paused music keeps playing")
	game.show_help()
	step(0.1)
	check(music.duck == "pause", "help from the pause keeps the pause mix")
	game.close_help()
	# Every menu over the paused match shares one mix; a settings preview plays open.
	var paused_level: float = music.level_db
	game.show_settings()
	step(0.5)
	check(music.duck == "pause" and near(music.level_db, paused_level, 0.05) and AudioServer.is_bus_effect_enabled(music_bus, 0), "settings from the pause keep the pause mix")
	check(library.duck_db("pause") >= -4.0 and float(library.mix.pause_lowpass_hz) >= 2000.0, "the pause mix stays clearly audible")
	music.preview("battle", "shinobu_vs_doma")
	step(0.7)
	check(music.duck == "" and not AudioServer.is_bus_effect_enabled(music_bus, 0) and near(music.level_db, library.level_db("battle"), 0.05), "a preview from the pause plays open")
	game.close_settings()
	step(0.7)
	check(music.duck == "pause" and music.playing() == "rengoku_kyojuro" and AudioServer.is_bus_effect_enabled(music_bus, 0), "back in the pause the match track and pause mix return")
	game.set_paused(false)
	step(0.5)
	check(music.duck == "" and near(music.level_db, library.level_db("battle"), 0.05) and not AudioServer.is_bus_effect_enabled(music_bus, 0), "resume restores level and opens the filter")
	# Cinematic duck.
	game.view.cinematic.active = true
	game.view.cinematic.phase = "video"
	step(0.3)
	check(music.duck == "cinematic" and near(music.level_db, library.level_db("battle") + library.duck_db("cinematic"), 0.05), "super cinematics duck the music")
	game.view.cinematic.active = false
	game.view.cinematic.phase = ""
	step(1.1)
	check(near(music.level_db, library.level_db("battle"), 0.05), "music returns after the cinematic")
	# Round end, final-round climax, deciding knockout.
	var combat: RefCounted = game.combat
	combat.wins.assign([1, 0])
	combat.phase = "round_end"
	step(0.3)
	check(music.duck == "round_end" and music.scene == "battle", "a knockout ducks the music")
	combat.phase = "intro"
	step(1.1)
	check(music.duck == "" and near(music.level_db, library.level_db("battle"), 0.05) and not music.climax_done, "the next round restores the music")
	var round_two: RefCounted = music.lead
	combat.wins.assign([1, 1])
	combat.phase = "round_end"
	step(0.3)
	combat.phase = "intro"
	step(0.05)
	check(music.climax_done and music.lead != round_two and near(music.lead.position, float(cue.climax), 0.1), "the final round jumps to the climax")
	step(2.0)
	var climax: RefCounted = music.lead
	combat.phase = "round_end"
	step(0.2)
	combat.phase = "intro"
	step(0.1)
	check(music.lead == climax, "a drawn final round does not jump twice")
	combat.wins.assign([2, 1])
	combat.phase = "round_end"
	step(1.6)
	check(music.scene == "result" and near(music.level_db, library.level_db("result"), 0.05), "the deciding knockout lowers to the result level")
	game.show_result()
	step(0.2)
	check(music.lead == climax and music.scene == "result", "results keep the battle track low")
	game.show_setup()
	step(0.1)
	check(music.playing() == "hashira_infinity_castle" and near(music.lead.position, 172.1, 0.1), "back to select restarts the select music at 2:52")
	step(1.5)
	game.mode = "practice"
	game.start_match()
	step(1.2)
	check(music.playing() == "rengoku_kyojuro" and music.scene == "battle", "practice plays the battle music")
	game.reset_practice()
	step(0.1)
	check(music.playing() == "rengoku_kyojuro" and music.lead.position > 1.0, "resetting practice keeps the music")
	game.show_practice_options()
	step(0.4)
	check(music.duck == "pause" and AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index(&"Music"), 0), "training options use the pause mix")
	game.set_paused(false)
	step(0.5)
	game.mode = "cpu"

func _settings_preview() -> void:
	game.show_title()
	step(1.5)
	var title: RefCounted = music.lead
	game.show_settings()
	step(0.1)
	check(music.lead == title, "opening settings keeps the title music")
	game.gui.actions.music_title.item_selected.emit(library.choices("title").find("kisatsutai"))
	step(0.1)
	check(game.settings.music.title == "kisatsutai" and music.playing() == "kisatsutai", "changing the title track previews it")
	game.gui.actions.music_battle.item_selected.emit(library.choices("battle").find("shinobu_vs_doma"))
	step(0.1)
	check(music.playing() == "shinobu_vs_doma" and music.preview_scene == "battle", "battle choices preview too")
	game.gui.actions.music_battle.item_selected.emit(library.choices("battle").find("random"))
	step(0.1)
	check(music.playing() == "shinobu_vs_doma", "random keeps the current preview")
	game.close_settings()
	step(0.1)
	check(music.playing() == "kisatsutai" and music.preview_track.is_empty(), "closing settings returns to the chosen title track")
	step(1.0)
	# Preview from a paused match resumes the match track where it was.
	game.settings.music.battle = "hekireki_issen"
	game.show_setup()
	game.show_stages()
	game.start_match()
	step(4.0)
	game.set_paused(true)
	game.show_settings()
	step(0.1)
	var position: float = music.lead.position
	music.preview("battle", "rengoku_kyojuro")
	step(0.5)
	check(music.playing() == "rengoku_kyojuro", "preview interrupts the match track")
	game.close_settings()
	step(0.05)
	check(music.playing() == "hekireki_issen" and music.lead.position >= position, "closing settings resumes the match track")
	game.set_paused(false)

func _follow_and_random() -> void:
	game.settings.music.select = "follow_title"
	game.show_title()
	step(2.0)
	var title: RefCounted = music.lead
	game.choose_mode("local")
	step(0.2)
	check(music.lead == title and music.scene == "select", "follow_title keeps the title music on select")
	game.settings.music.select = "hashira_infinity_castle"
	game.settings.music.title = "random"
	game.show_title()
	step(0.1)
	check(music.playing() in library.candidates("title"), "random title picks one of the title tracks")
	var pick: String = music.playing()
	game.show_setup()
	step(1.5)
	game.show_title()
	step(0.1)
	check(music.playing() == pick, "a random title pick holds for the session")

func _exit_options() -> void:
	game.settings.music.battle = "rengoku_kyojuro"
	game.start_match()
	step(1.2)
	game.set_paused(true)
	step(0.1)
	game.gui.actions.main_menu.pressed.emit()
	step(0.1)
	check(game.screen == "title" and not game.paused and music.scene == "title" and music.duck == "", "返回主菜单 leaves the paused match for the title music")
	step(1.5)

func _buses() -> void:
	for bus: StringName in [&"Music", &"SFX", &"Voice"]:
		check(AudioServer.get_bus_index(bus) > 0 and AudioServer.get_bus_send(AudioServer.get_bus_index(bus)) == &"Master", "%s bus feeds Master" % bus)
	check(music.decks.all(func(deck) -> bool: return deck.player.bus == &"Music"), "music decks play on the Music bus")
	check(game.view.cinematic.soundtrack.bus == &"SFX" and game.view.cinematic.movie.bus == &"SFX", "cinematic audio plays on the SFX bus")
	check(AudioServer.get_bus_effect_count(0) == 1 and AudioServer.get_bus_effect(0, 0) is AudioEffectHardLimiter, "a limiter guards the Master bus")
	game.settings.muted = false
	game.sound.muted = false
	game.toggle_audio()
	check(AudioServer.is_bus_mute(0) and game.settings.muted, "F2 mutes the Master bus")
	game.toggle_audio()
	check(not AudioServer.is_bus_mute(0), "F2 again unmutes")
