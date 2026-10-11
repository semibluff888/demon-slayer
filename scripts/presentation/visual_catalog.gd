extends RefCounted
const Character = preload("res://scripts/presentation/character_visual.gd")
const Stage = preload("res://scripts/presentation/stage_visual.gd")
const CombatData = preload("res://scripts/combat_catalog.gd")
var data := CombatData.new()
var characters: Dictionary = {}
var stage := Stage.new()
var stages: Dictionary = {}
var body_font: Font
var title_font: Font
## Brush calligraphy for screen titles, names and battle callouts.
var display_font: Font
## Condensed numerals and English captions (timer, combo, kickers).
var numeric_font: Font
var _ui_assets: RefCounted

func _init(load_combat_art: bool = true) -> void:
	body_font = _font("res://art/fonts/NotoSansSC-ui.ttf", ["Microsoft YaHei UI", "Microsoft YaHei"], 500)
	title_font = _font("res://art/fonts/NotoSerifSC-title.ttf", ["SimSun", "Microsoft YaHei"], 900)
	display_font = _font("res://art/fonts/MaShanZheng-display.ttf", ["KaiTi", "STKaiti"], 400)
	numeric_font = _font("res://art/fonts/Oswald-numeric.ttf", ["Bahnschrift", "Arial Narrow"], 700)
	# Missing glyphs fall through the families, then to the operating system.
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])
	_fallback(body_font, system)
	_fallback(title_font, body_font)
	_fallback(display_font, title_font)
	_fallback(numeric_font, body_font)
	for id in data.characters:
		var definition = data.characters[id]
		var visual := Character.new()
		visual.character_id = id
		visual.display_name = definition.display_name
		visual.portrait_faces_right = definition.portrait_faces_right
		visual.menu_focus_x = definition.menu_focus_x
		visual.epithet = definition.epithet
		visual.element_name = definition.element_name
		visual.accent = definition.accent
		visual.asset_directory = definition.visual_directory
		visual.model_scale = definition.model_scale
		visual.awakening = definition.awakening
		visual.hit_reaction_frames = definition.hit_reaction_frames.duplicate()
		visual.state_animations = definition.state_animations.duplicate()
		for clip: String in visual.state_animations.values():
			if not clip in visual.required_move_clips:
				visual.required_move_clips.append(clip)
		for move in definition.all_moves():
			if not move.clip_id() in visual.required_move_clips:
				visual.required_move_clips.append(move.clip_id())
		visual.load_local_assets(load_combat_art)
		characters[id] = visual
	var definitions: Array = []
	for file in ResourceLoader.list_directory("res://resources/stages"):
		if file.ends_with(".tres"):
			definitions.append(load("res://resources/stages/" + file).duplicate())
	definitions.sort_custom(func(a,b): return a.roster_order < b.roster_order)
	for definition in definitions:
		definition.load_thumbnail()
		stages[definition.id] = definition
	stage = stages.get("wisteria", stage)
	if load_combat_art:
		stage.load_local_assets()

func _font(path: String, fallbacks: Array, weight: int) -> Font:
	# Bundled fonts are static instances subset by tools/subset_fonts.py.
	if ResourceLoader.exists(path):
		var font := FontVariation.new()
		font.base_font = load(path)
		return font
	var system := SystemFont.new()
	system.font_names = PackedStringArray(fallbacks + ["Microsoft YaHei", "sans-serif"])
	system.font_weight = weight
	return system

func _fallback(font: Font, next: Font) -> void:
	var chain: Array[Font] = [next]
	font.fallbacks = chain

## Rasterized UI icons, generated textures and the menu Theme, built on first use.
func ui_assets() -> RefCounted:
	if _ui_assets == null:
		_ui_assets = preload("res://scripts/ui/ui_assets.gd").new()
	return _ui_assets

func readiness() -> Dictionary:
	var report := {"stage": stage.art_ready, "characters": {}}
	for id: String in characters:
		report.characters[id] = {"ready": characters[id].art_ready,
			"missing_clips": characters[id].missing_clips(), "portrait": characters[id].portrait != null}
	return report

func prepare_match(ids: Array, stage_id: String) -> void:
	for id: String in characters:
		if id in ids:
			if not characters[id].art_ready:
				characters[id].load_local_assets()
		else:
			characters[id].release_combat_assets()
	for id: String in stages:
		if id == stage_id:
			if not stages[id].art_ready:
				stages[id].load_local_assets()
		else:
			stages[id].release_assets()
