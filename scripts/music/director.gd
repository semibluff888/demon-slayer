extends Node
## Background music. Every frame it reads the screen, pause, cinematic and round state and
## steers a small pool of players: crossfades between scene tracks, loops each track between
## its authored cue points, jumps to the climax at a final round and ducks for pauses, KOs
## and cinematics. It never writes game state. Tracks, cues, levels and fade times come
## from resources/music/library.json; docs/music.md describes the rules.
const Library = preload("res://scripts/music/library.gd")
const Buses = preload("res://scripts/audio_buses.gd")
const DECKS := 3

class Deck:
	extends RefCounted
	var player: AudioStreamPlayer
	var track: String = ""
	## Which cue set (title, select, battle) loops this deck.
	var scene: String = ""
	var position: float = 0.0
	## Crossfade progress: 0 silent, 1 full; heard through an equal-power curve.
	var gain: float = 0.0
	var target: float = 0.0
	var rate: float = 1.0
	## Set once the loop crossfade to a successor deck has started.
	var looping: bool = false
	## Set once the player reports this deck's position; from then on it is the clock.
	var synced: bool = false

var app: Node
var library := Library.new()
## Off under scripted test and capture trees; music_tests switch it on.
var enabled: bool = true
## Tests drive positions only through advance(); the game also follows the player clock.
var virtual_clock: bool = false
var rng := RandomNumberGenerator.new()
var decks: Array[Deck] = []
var lead: Deck
## Mix context: title, select, battle or result (the battle track, held low).
var scene: String = ""
## Active duck: "", pause, cinematic or round_end.
var duck: String = ""
var level_db: float = 0.0
var level_target: float = 0.0
var level_rate: float = 0.0
var lowpass: float = 0.0
var lowpass_target: float = 0.0
var lowpass_rate: float = 1.0
var title_track: String = ""
var title_choice: String = ""
var battle_track: String = ""
var next_battle: String = ""
var last_battle: String = ""
var climax_done: bool = false
## A new match restarts the battle track even when the same piece is already playing.
var restart: bool = false
## Title tracks continue where they were left.
var resume: Dictionary = {}
var preview_track: String = ""
var preview_scene: String = ""
## The track a settings preview interrupted, resumed when settings close.
var held: Dictionary = {}
var _closing_preview: bool = false
var streams: Dictionary = {}
var requested: Dictionary = {}

func _ready() -> void:
	name = "Music"
	Buses.ensure()
	rng.randomize()
	if get_tree().get_script() != null:
		enabled = false
	for i in range(DECKS):
		var deck := Deck.new()
		deck.player = AudioStreamPlayer.new()
		deck.player.bus = Buses.MUSIC
		add_child(deck.player)
		decks.append(deck)

func _process(delta: float) -> void:
	advance(delta)

func _exit_tree() -> void:
	# Stop playback and collect unfinished background loads so nothing outlives the tree.
	for deck in decks:
		deck.player.stop()
		deck.player.stream = null
	for path: String in requested:
		ResourceLoader.load_threaded_get(path)
	requested.clear()
	streams.clear()

func advance(delta: float) -> void:
	if not enabled or app == null:
		return
	_steer()
	for deck in decks:
		if deck.track.is_empty():
			continue
		deck.position += delta
		if not virtual_clock and deck.player.playing:
			# Right after play() the player may still report its previous position.
			var heard := deck.player.get_playback_position()
			if deck.synced or absf(heard - deck.position) < 0.5:
				deck.position = heard
				deck.synced = true
		deck.gain = move_toward(deck.gain, deck.target, deck.rate * delta)
		if deck.gain <= 0.0 and deck.target <= 0.0:
			_stop(deck)
	if lead != null and not lead.track.is_empty():
		_loop(lead)
	level_db = move_toward(level_db, level_target, level_rate * delta)
	lowpass = move_toward(lowpass, lowpass_target, lowpass_rate * delta)
	Buses.set_lowpass(lowpass, float(library.mix.get("pause_lowpass_hz", 900.0)))
	_mix()

## Called by start_match: picks this match's track (random avoids the last one) and
## restarts it, except when the select track simply carries on into the fight.
func begin_match() -> void:
	var choice: String = library.valid_choice("battle", app.settings.music.get("battle", ""))
	var track := next_battle if not next_battle.is_empty() and choice in [Library.RANDOM, next_battle] else library.resolve("battle", choice, rng, last_battle)
	next_battle = ""
	battle_track = track
	last_battle = track
	climax_done = false
	resume.erase(track)
	restart = not (scene == "select" and lead != null and lead.track == track)

## Settings preview: plays the chosen track while the settings screen is open.
## Random and follow-title choices keep whatever is playing.
func preview(target_scene: String, choice: String) -> void:
	if library.tracks.has(choice):
		preview_track = choice
		preview_scene = target_scene

func playing() -> String:
	return lead.track if lead != null else ""

# --- Steering -------------------------------------------------------------------------

func _steer() -> void:
	if app.screen != "settings" and not preview_track.is_empty():
		preview_track = ""
		_closing_preview = true
	var wanted := _wanted_scene()
	var track := _wanted_track(wanted)
	var reason := _duck(wanted)
	var target := library.level_db(preview_scene if not preview_track.is_empty() else wanted) + library.duck_db(reason)
	var first := lead == null
	var switching := not track.is_empty() and (first or lead.track != track or (restart and wanted == "battle"))
	var fades := _fades(wanted)
	if switching:
		restart = false
		_enter(track, wanted, fades)
	elif lead != null and not track.is_empty():
		lead.scene = _cue_scene(track, wanted)
	_closing_preview = false
	var wins: Array = app.combat.wins
	if wanted == "battle" and not climax_done and app.combat.phase == "intro" and wins[0] == 1 and wins[1] == 1 and lead != null and lead.track == battle_track:
		climax_done = true
		_climax()
	if first:
		level_db = target
	elif not is_equal_approx(target, level_target) or reason != duck:
		var time := _level_fade(wanted, reason, fades.x if switching else -1.0)
		level_rate = absf(target - level_db) / maxf(time, 0.01)
		lowpass_rate = 1.0 / maxf(time, 0.01)
	level_target = target
	lowpass_target = 1.0 if reason == "pause" else 0.0
	if wanted != scene:
		_prefetch_next(wanted)
	scene = wanted
	duck = reason

func _wanted_scene() -> String:
	var screen: String = app.screen
	if screen == "settings":
		screen = app.settings_return
	elif screen == "help":
		screen = app.help_return
	match screen:
		"setup", "stage":
			return "select"
		"result":
			return "result"
		"battle":
			var combat: RefCounted = app.combat
			# The deciding knockout already settles the music to its result level.
			if not combat.practice and (combat.phase == "match_end" or (combat.phase == "round_end" and combat.wins.max() >= 2)):
				return "result"
			return "battle"
	return "title"

func _wanted_track(wanted: String) -> String:
	if not preview_track.is_empty():
		return preview_track
	match wanted:
		"title":
			return _title_track()
		"select":
			var track := library.resolve("select", app.settings.music.get("select", ""), rng)
			return track if not track.is_empty() else _title_track()
	if battle_track.is_empty():
		battle_track = library.resolve("battle", app.settings.music.get("battle", ""), rng, last_battle)
		last_battle = battle_track
	return battle_track

## The title piece is drawn once per session (or when its setting changes).
func _title_track() -> String:
	var choice: String = library.valid_choice("title", app.settings.music.get("title", ""))
	if title_track.is_empty() or choice != title_choice:
		title_choice = choice
		title_track = library.resolve("title", choice, rng, title_track)
	return title_track

## Every menu over a paused match (pause, help, training options, settings) shares the
## pause mix; only a settings preview plays open so the choice can be judged.
func _duck(wanted: String) -> String:
	if wanted not in ["battle", "result"]:
		return ""
	if app.paused:
		return "" if not preview_track.is_empty() else "pause"
	if app.view.cinematic.is_video_visible():
		return "cinematic"
	if wanted == "battle" and app.combat.phase == "round_end":
		return "round_end"
	return ""

func _cue_scene(track: String, wanted: String) -> String:
	if not preview_track.is_empty():
		wanted = preview_scene
	var name := "battle" if wanted == "result" else wanted
	var cues: Dictionary = library.tracks.get(track, {}).get("cues", {})
	return name if cues.has(name) or cues.is_empty() else str(cues.keys()[0])

## (fade in, fade out) for a track change into `wanted`.
func _fades(wanted: String) -> Vector2:
	if lead == null:
		return Vector2(library.fade("boot"), 0.0)
	if not preview_track.is_empty() or _closing_preview:
		return Vector2.ONE * library.fade("preview")
	if wanted in ["battle", "result"]:
		return Vector2(library.fade("battle_in"), library.fade("battle_out"))
	return Vector2.ONE * library.fade("menu")

func _level_fade(wanted: String, reason: String, crossfade: float) -> float:
	if reason != duck:
		match reason:
			"pause": return library.fade("pause_in")
			"cinematic": return library.fade("cinematic_in")
			"round_end": return library.fade("round_end_in")
		match duck:
			"pause": return library.fade("pause_out")
			"cinematic": return library.fade("cinematic_out")
			"round_end": return library.fade("round_restore")
	if wanted == "result" and scene == "battle":
		return library.fade("result")
	return crossfade if crossfade >= 0.0 else library.fade("menu")

# --- Decks ----------------------------------------------------------------------------

func _enter(track: String, wanted: String, fades: Vector2) -> void:
	var cue_scene := _cue_scene(track, wanted)
	var cue := library.cue(track, cue_scene)
	var from := float(cue.get("start", 0.0))
	if _closing_preview and held.get("track", "") == track:
		from = float(held.position)
	elif cue_scene == "title" and resume.has(track):
		from = float(resume[track])
	if from >= float(cue.get("loop_end", INF)) - library.crossfade(track, cue_scene) - 1.0:
		from = float(cue.get("loop_start", 0.0))
	if not preview_track.is_empty() and held.is_empty() and lead != null:
		held = {"track": lead.track, "position": lead.position + fades.y}
	elif preview_track.is_empty():
		held.clear()
	_switch(track, cue_scene, from, fades.x, fades.y)

func _switch(track: String, cue_scene: String, from: float, fade_in: float, fade_out: float) -> void:
	var revived: Deck
	for deck in decks:
		if deck.track.is_empty():
			continue
		if deck == lead and deck.scene == "title":
			resume[deck.track] = deck.position + fade_out
		# Reverse a fade still in progress instead of stacking a second copy.
		if revived == null and deck != lead and deck.track == track and deck.scene == cue_scene and not deck.looping and deck.gain > 0.05:
			revived = deck
			continue
		_fade(deck, 0.0, fade_out)
	if revived != null:
		lead = revived
		_fade(revived, 1.0, fade_in)
		return
	_start(track, cue_scene, from, fade_in)

func _start(track: String, cue_scene: String, from: float, fade_in: float) -> Deck:
	var stream := _stream(track)
	if stream == null:
		return lead
	var deck := _free_deck()
	deck.track = track
	deck.scene = cue_scene
	deck.position = from
	deck.gain = 0.0
	deck.looping = false
	deck.synced = false
	_fade(deck, 1.0, fade_in)
	deck.player.stream = stream
	deck.player.volume_db = -80.0
	deck.player.play(from)
	lead = deck
	return deck

func _fade(deck: Deck, target: float, seconds: float) -> void:
	deck.target = target
	deck.rate = absf(target - deck.gain) / maxf(seconds, 0.01) if seconds > 0.0 else INF

func _free_deck() -> Deck:
	var quietest: Deck
	for deck in decks:
		if deck.track.is_empty():
			return deck
		if deck != lead and (quietest == null or deck.gain < quietest.gain):
			quietest = deck
	_stop(quietest)
	return quietest

func _stop(deck: Deck) -> void:
	deck.player.stop()
	deck.track = ""
	deck.gain = 0.0
	deck.target = 0.0
	deck.looping = false
	if deck == lead:
		lead = null

## Crossfades the lead deck from loop_end back to loop_start, keeping any frame overshoot.
func _loop(deck: Deck) -> void:
	var cue := library.cue(deck.track, deck.scene)
	var fade := library.crossfade(deck.track, deck.scene)
	var end := float(cue.get("loop_end", INF))
	if deck.looping or deck.position < end - fade:
		return
	deck.looping = true
	var overshoot := deck.position - (end - fade)
	_fade(deck, 0.0, fade - overshoot)
	_start(deck.track, deck.scene, float(cue.get("loop_start", 0.0)) + overshoot, fade - overshoot)

## Final round: lift into the track's climax for the deciding fight.
func _climax() -> void:
	var cue := library.cue(battle_track, "battle")
	if not cue.has("climax"):
		return
	var fade := library.fade("climax")
	for deck in decks:
		if not deck.track.is_empty():
			_fade(deck, 0.0, fade)
	_start(battle_track, "battle", float(cue.climax), fade)

func _mix() -> void:
	for deck in decks:
		if not deck.track.is_empty():
			deck.player.volume_db = library.gain_db(deck.track) + level_db + Buses.level_db(sin(deck.gain * PI * 0.5))

# --- Streams --------------------------------------------------------------------------

func _stream(track: String) -> AudioStream:
	if streams.has(track):
		return streams[track]
	var path := library.file(track)
	var stream: AudioStream
	if requested.has(path):
		requested.erase(path)
		stream = ResourceLoader.load_threaded_get(path) as AudioStream
	elif ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		push_warning("Music track cannot be loaded: " + path)
	streams[track] = stream
	return stream

## Loads the next likely track in the background: select music on the title screen, this
## match's battle track on the select screens.
func _prefetch_next(wanted: String) -> void:
	var track := ""
	if wanted == "title":
		track = library.resolve("select", app.settings.music.get("select", ""), rng)
	elif wanted == "select":
		next_battle = library.resolve("battle", app.settings.music.get("battle", ""), rng, last_battle)
		track = next_battle
	var path := library.file(track)
	if track.is_empty() or streams.has(track) or requested.has(path) or not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_request(path, "AudioStream") == OK:
		requested[path] = true
