extends RefCounted
## Track table, per-scene choices and the music mix from resources/music/library.json.
## A choice is a track id or one of the special values below; see docs/music.md.
const PATH := "res://resources/music/library.json"
const SCENES := ["title", "select", "battle"]
const RANDOM := "random"
const FOLLOW_TITLE := "follow_title"
var tracks: Dictionary = {}
var scenes: Dictionary = {}
var labels: Dictionary = {}
var mix: Dictionary = {}

func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if data is not Dictionary:
		push_error("Music library is missing or invalid: " + PATH)
		return
	tracks = data.get("tracks", {})
	scenes = data.get("scenes", {})
	labels = data.get("choice_labels", {})
	mix = data.get("mix", {})

func choices(scene: String) -> Array:
	return scenes.get(scene, {}).get("choices", [])

func default_choice(scene: String) -> String:
	return str(scenes.get(scene, {}).get("default", ""))

## A saved choice survives only while the library still offers it for that scene.
func valid_choice(scene: String, value: String) -> String:
	return value if value in choices(scene) else default_choice(scene)

func defaults() -> Dictionary:
	var result := {}
	for scene: String in SCENES:
		result[scene] = default_choice(scene)
	return result

func label(choice: String) -> String:
	return str(tracks[choice].title) if tracks.has(choice) else str(labels.get(choice, choice))

func candidates(scene: String) -> Array[String]:
	var result: Array[String] = []
	for choice in choices(scene):
		if tracks.has(choice):
			result.append(choice)
	return result

## Resolves a choice to a track id. Random never repeats `avoid` when it has an alternative;
## follow_title resolves to "" so the caller keeps the title track.
func resolve(scene: String, choice: String, rng: RandomNumberGenerator, avoid: String = "") -> String:
	choice = valid_choice(scene, choice)
	if choice == FOLLOW_TITLE:
		return ""
	if choice != RANDOM:
		return choice
	var pool := candidates(scene)
	if pool.size() > 1:
		pool.erase(avoid)
	return pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else ""

## Cue points for a track in a scene; a track used elsewhere falls back to its first cue set.
func cue(track: String, scene: String) -> Dictionary:
	var cues: Dictionary = tracks.get(track, {}).get("cues", {})
	if cues.has(scene):
		return cues[scene]
	return cues.values()[0] if not cues.is_empty() else {}

func file(track: String) -> String:
	return str(tracks.get(track, {}).get("file", ""))

func gain_db(track: String) -> float:
	return float(tracks.get(track, {}).get("gain_db", 0.0))

func level_db(scene: String) -> float:
	return float(mix.get("levels_db", {}).get(scene, 0.0))

func duck_db(reason: String) -> float:
	return float(mix.get("duck_db", {}).get(reason, 0.0))

func fade(name: String) -> float:
	return float(mix.get("fades", {}).get(name, 1.0))

func crossfade(track: String, scene: String) -> float:
	return float(cue(track, scene).get("crossfade", fade("loop")))
