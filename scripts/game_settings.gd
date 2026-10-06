class_name GameSettings
extends RefCounted
const Router = preload("res://scripts/input_router.gd")
const RESERVED := [KEY_ESCAPE, KEY_F1, KEY_F2, KEY_F3, KEY_BACKSPACE, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK, KEY_PRINT]
var path: String = "user://settings.cfg"
var muted: bool = false
var volume: float = 1.0
var keymaps: Array = Router.KEYS.duplicate(true)
var last_error: String = ""

func load_config() -> void:
	muted = false
	volume = 1.0
	keymaps = Router.KEYS.duplicate(true)
	var file := ConfigFile.new()
	if file.load(path) != OK: return
	muted = bool(file.get_value("audio", "muted", false))
	var saved_volume = file.get_value("audio", "volume", 1.0)
	if saved_volume is float or saved_volume is int:
		volume = clampf(float(saved_volume), 0, 1) if is_finite(float(saved_volume)) else 1.0
	var candidate: Array = []
	for player in range(2):
		var keys = file.get_value("keyboard", "p%d" % [player+1], Router.KEYS[player])
		if keys is not Array and keys is not PackedInt32Array and keys is not PackedInt64Array: return
		candidate.append(Array(keys))
	if _valid_maps(candidate): keymaps = candidate

func _valid_maps(maps: Array) -> bool:
	if maps.size() != 2: return false
	var used: Array = []
	for keys in maps:
		if keys.size() != 8: return false
		for key in keys:
			if key is not int or key <= 0 or key in RESERVED or key in used: return false
			used.append(key)
	return true

func bind(player: int, action: int, key: int) -> bool:
	last_error = ""
	if key <= 0 or key in RESERVED:
		last_error = "此键保留给系统操作，请换一个按键。"
		return false
	for p in range(2):
		for a in range(8):
			if keymaps[p][a] == key and (p != player or a != action):
				last_error = "%s 已用于 P%d · %s" % [Router.key_name(key), p+1, ["左", "右", "下", "上", "A", "B", "C", "D"][a]]
				return false
	keymaps[player][action] = key
	return true

func restore_keyboard(player: int) -> bool:
	var candidate := keymaps.duplicate(true)
	candidate[player] = Router.KEYS[player].duplicate()
	if not _valid_maps(candidate):
		last_error = "默认按键被另一方占用，请先恢复双方默认。"
		return false
	keymaps = candidate
	last_error = ""
	return true

func save_config() -> Error:
	var file := ConfigFile.new()
	file.set_value("audio", "muted", muted)
	file.set_value("audio", "volume", volume)
	for player in range(2): file.set_value("keyboard", "p%d" % [player+1], keymaps[player])
	var result := file.save(path)
	last_error = "" if result == OK else "设置暂未保存，请检查本地存储权限。"
	return result
