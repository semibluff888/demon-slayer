extends Control
## Screen-space battle HUD in the 「大正墨金」style. Presentation never changes
## combat resources. Animations advance by delta * playback_speed, so KO freezes
## stop them; pause (frozen) stops everything, and hitstop or super freeze (held)
## holds the frame while meter and awakening feedback play through it.
const RoundBanner = preload("res://scripts/presentation/round_banner.gd")
const InputRouter = preload("res://scripts/input_router.gd")
const Style = preload("res://scripts/presentation/battle_style.gd")
const Kit = preload("res://scripts/ui/kit.gd")
const GradientText = preload("res://scripts/ui/gradient_text.gd")
const Brush = preload("res://scripts/ui/brush_stroke.gd")
const GAUGE_SHADER = preload("res://scripts/ui/shaders/gauge_fill.gdshader")
const METER_SHADER = preload("res://scripts/ui/shaders/meter_flow.gdshader")
const PAPER := Style.PAPER
const GOLD := Style.GOLD
const MUTED := Style.MUTED
const INK := Style.INK
## P1 layout; every P2 element mirrors around x = 640.
const BAR := Rect2(124, 40, 466, 22)
const PORTRAIT := Rect2(14, 8, 96, 96)
const METER_X := 98.0
const METER_Y := 654.0
const CELL := Vector2(104, 14)
const CELL_STEP := 110.0
const CREST := Vector2(52, 660)
const HP_GOLD := Color("f6c95c")
const HP_AMBER := Color("f39234")
const HP_RED := Color("e8453a")
const CHIP := Color("8e1d27")
const BUTTON_TINTS := [Color("5fc0ff"), Color("6fd69a"), Color("ffb44c"), Color("ff6f6f")]
const COMBO_RAMPS := [[Color("fff3c8"), Color("e8b75a"), Color("8f6326")],
	[Color("fff0c8"), Color("ff9a3c"), Color("a33a12")], [Color("ffe0e0"), Color("ff4a5e"), Color("7c1222")]]
const COMBO_FADE := 0.45
const GUARD_NAMES := ["站立不防", "站立防御", "蹲下防御", "首击后防"]
var round_banner: Control
var combat: RefCounted
var catalog: RefCounted
var super_view: Node2D
var cpu: bool = true
var training: RefCounted
var input_device: String = "keyboard:0"
var awakening_hints: Array[String] = ["I+J", "Num6+Num2"]
var frozen: bool = false
## Hitstop or super freeze: impact feedback holds with the stage and effects.
var held: bool = false
var cinematic_mode: bool = false
var playback_speed: float = 1.0
var practice_details: bool = false
var input_hints: Array[String] = ["WASD / UI · JK", "↑↓←→ / Num56 · Num23"]
var meter_flash: Array[float] = [0.0, 0.0]
var meter_error: Array[float] = [0.0, 0.0]
var meter_spent: Array[int] = [0, 0]
var spent_time: Array[float] = [0.0, 0.0]
var trailing: Array[float] = [1000.0, 1000.0]
var callouts: Array[String] = ["", ""]
var callout_time: Array[float] = [0.0, 0.0]
var combo_pop: Array[float] = [0.0, 0.0]
var last_combo: Array[int] = [0, 0]
var last_stock: Array[int] = [0, 0]
var time: float = 0.0
var awakening_reveal: Array[float] = [0.0, 0.0]
# Presentation-only state for flashes, fades and pops.
var hp_seen: Array[float] = [1000.0, 1000.0]
var damage_flash: Array[float] = [0.0, 0.0]
var combo_fade: Array[float] = [0.0, 0.0]
var combo_shown: Array[int] = [0, 0]
var combo_damage_shown: Array[int] = [0, 0]
var win_pop: Array[float] = [0.0, 0.0]
var wins_seen: Array[int] = [0, 0]
var gauges: Node2D
var meters: Node2D
var overlay: Node2D
var labels: Node2D
var combo_bands: Array = []
var combo_digits: Array = []
var callout_bands: Array = []
var reveal_bands: Array = []
var white: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	white = catalog.ui_assets().white()
	gauges = _layer("HealthFill", GAUGE_SHADER, _draw_health_fills)
	meters = _layer("MeterFill", METER_SHADER, _draw_meter_fills)
	overlay = _layer("Overlay", null, _draw_overlay)
	for slot in range(2):
		var band := Brush.new(1.7 + slot * 4.1)
		band.name = "ComboBand%d" % slot
		band.set_param("taper", 0.6)
		add_child(band)
		combo_bands.append(band)
		var callout := Brush.new(5.3 + slot * 2.9)
		callout.name = "CalloutBand%d" % slot
		add_child(callout)
		callout_bands.append(callout)
		var reveal := Brush.new(8.9 + slot * 1.3)
		reveal.name = "AwakeningBand%d" % slot
		add_child(reveal)
		reveal_bands.append(reveal)
	for slot in range(2):
		var digits := GradientText.new()
		digits.name = "ComboDigits%d" % slot
		digits.setup(catalog.numeric_font, "", 76, 0)
		digits.skew = -0.2
		digits.outline = 9
		digits.visible = false
		add_child(digits)
		combo_digits.append(digits)
	labels = _layer("Labels", null, _draw_labels)
	round_banner = RoundBanner.new()
	round_banner.title_font = catalog.title_font
	round_banner.body_font = catalog.body_font
	round_banner.display_font = catalog.display_font
	round_banner.numeric_font = catalog.numeric_font
	add_child(round_banner)

func _layer(id: String, shader: Shader, painter: Callable) -> Node2D:
	var node := Node2D.new()
	node.name = id
	if shader != null:
		var paint := ShaderMaterial.new()
		paint.shader = shader
		node.material = paint
	node.draw.connect(painter)
	add_child(node)
	return node

func reset_effects() -> void:
	for i in range(trailing.size()):
		trailing[i] = combat.fighters[i].hp if combat != null and i < combat.fighters.size() else 1000.0
	hp_seen.assign(trailing)
	callouts.assign(["", ""])
	callout_time.assign([0.0, 0.0])
	meter_flash.assign([0.0, 0.0])
	meter_error.assign([0.0, 0.0])
	meter_spent.assign([0, 0])
	spent_time.assign([0.0, 0.0])
	combo_pop.assign([0.0, 0.0])
	last_combo.assign([0, 0])
	last_stock.assign([0, 0])
	time = 0
	awakening_reveal.assign([0.0, 0.0])
	damage_flash.assign([0.0, 0.0])
	combo_fade.assign([0.0, 0.0])
	combo_shown.assign([0, 0])
	combo_damage_shown.assign([0, 0])
	win_pop.assign([0.0, 0.0])
	wins_seen.assign(combat.wins if combat != null else [0, 0])

func consume(events: Array) -> void:
	for event: Dictionary in events:
		if event.type == "swing" and combat.moves[event.move].kind == "skill":
			callouts[event.attacker] = combat.moves[event.move].display_name
			callout_time[event.attacker] = 1.2
		elif event.type == "awakening_start":
			awakening_reveal[event.attacker] = 0.85
			callout_time[event.attacker] = 0
		elif event.type == "awakening_denied":
			callouts[event.attacker] = "觉醒需地面行动 / 普通技命中"
			callout_time[event.attacker] = 0.7
		elif event.type == "meter_empty":
			meter_error[event.attacker] = 0.6
			callouts[event.attacker] = "呼吸槽不足 · 需要 %d 格" % int(event.cost / 100)
			callout_time[event.attacker] = 1.2
		elif event.type == "meter":
			meter_flash[event.attacker] = 0.35
			if int(event.amount) < 0:
				meter_spent[event.attacker] = -int(event.amount)
				spent_time[event.attacker] = 0.9
				callout_time[event.attacker] = 0
		elif event.type == "hit":
			combo_pop[event.attacker] = 0.20
		elif event.type == "throw_tech":
			callouts.assign(["拆投", "拆投"])
			callout_time.assign([0.8, 0.8])

func _process(delta: float) -> void:
	delta *= playback_speed
	if combat == null or catalog == null or combat.fighters.is_empty():
		return
	if not frozen:
		# The meter spend and awakening reveal are choreographed into the super
		# freeze, like the cut-in, so only impact feedback waits out a freeze.
		var world_delta := 0.0 if held else delta
		time += world_delta
		for i in range(2):
			var f = combat.fighters[i]
			awakening_reveal[i] = maxf(0, awakening_reveal[i] - delta)
			meter_flash[i] = maxf(0, meter_flash[i] - delta)
			meter_error[i] = maxf(0, meter_error[i] - delta)
			spent_time[i] = maxf(0, spent_time[i] - delta)
			combo_pop[i] = maxf(0, combo_pop[i] - world_delta)
			trailing[i] = move_toward(trailing[i], f.hp, world_delta * 270)
			callout_time[i] = maxf(0, callout_time[i] - world_delta)
			damage_flash[i] = maxf(0, damage_flash[i] - world_delta)
			win_pop[i] = maxf(0, win_pop[i] - world_delta)
			if f.hp < hp_seen[i] - 0.5:
				damage_flash[i] = 0.14
			hp_seen[i] = f.hp
			if combat.wins[i] > wins_seen[i]:
				win_pop[i] = 0.5
			wins_seen[i] = combat.wins[i]
			if f.combo_display > 0 and f.combo >= 2:
				combo_shown[i] = f.combo
				combo_damage_shown[i] = f.combo_damage
				combo_fade[i] = COMBO_FADE
			else:
				combo_fade[i] = maxf(0, combo_fade[i] - world_delta)
			var stock := int(f.meter / 100)
			if stock > last_stock[i]:
				meter_flash[i] = 0.55
			last_stock[i] = stock
			last_combo[i] = f.combo
	_sync_nodes()
	queue_redraw()
	for layer in [gauges, meters, overlay, labels]:
		if layer != null:
			layer.queue_redraw()

func _drawable() -> bool:
	return combat != null and catalog != null and combat.fighters.size() >= 2

func _visual(slot: int) -> Resource:
	return catalog.characters[combat.fighters[slot].character]

static func _mx(slot: int, x: float) -> float:
	return x if slot == 0 else 1280.0 - x

static func _mrect(slot: int, rect: Rect2) -> Rect2:
	return rect if slot == 0 else Rect2(1280.0 - rect.end.x, rect.position.y, rect.size.x, rect.size.y)

static func _mpoints(slot: int, points: PackedVector2Array) -> PackedVector2Array:
	return points if slot == 0 else Kit.mirror_x(points)

func practice_hints() -> Array[String]:
	return InputRouter.motion_hints(input_device, combat.fighters[0].facing)

func practice_feedback() -> String:
	var down := InputRouter.key_name(InputRouter.current_keys(int(input_device.get_slice(":",1)))[2]) if input_device.begins_with("keyboard:") else "↓"
	match combat.fighters[0].input.feedback:
		"release_down": return "搓招提示：仍在斜下，松开%s再按横方向＋攻击。" % down
		"motion_timeout": return "搓招提示：方向超时，请在0.5秒内连贯输入。"
		"attack_late": return "搓招提示：攻击偏晚，请在横方向后0.2秒内按攻击。"
		"wrong_button": return "搓招提示：236配轻重斩，214配轻重体术；按右侧键位。"
	return "方向和攻击不必同时按；斜方向可省略。"

func meter_cell(slot: int, index: int) -> Rect2:
	# Cells are indexed left to right on both sides; P2's outer cell is index 2.
	var x := METER_X if slot == 0 else 1280.0 - METER_X - 2 * CELL_STEP - CELL.x
	return Rect2(x + index * CELL_STEP, METER_Y, CELL.x, CELL.y)

func meter_fill_rect(slot: int, value: int, index: int) -> Rect2:
	var cell := meter_cell(slot, index)
	var fill := clampf((value - (index if slot == 0 else 2 - index) * 100) / 100.0, 0, 1)
	return Rect2(cell.position + Vector2(0 if slot == 0 else cell.size.x * (1 - fill), 0), Vector2(cell.size.x * fill, cell.size.y))

func awakening_meter_caption(f: RefCounted) -> String:
	if f.meter < 100:
		return "气量不足 · 超杀 / MAX需1格"
	return "超杀1格保留觉醒 / MAX1格耗尽"

func has_super_title() -> bool:
	return is_instance_valid(super_view) and not super_view.active.is_empty()

func practice_details_visible() -> bool:
	return practice_details and not has_super_title() and not frozen

# --- Geometry -------------------------------------------------------------------

func _bar_points(slot: int, rect: Rect2 = BAR) -> PackedVector2Array:
	return _mpoints(slot, Kit.blade(rect))

## Part of the health bar between two fractions measured from the outer end.
func _bar_span(slot: int, from: float, to: float) -> Array:
	# Skip sub-pixel slivers; they can fail triangulation and are invisible anyway.
	if (to - from) * BAR.size.x < 1.0:
		return []
	var cut := Rect2(BAR.position.x + BAR.size.x * from, BAR.position.y - 2, BAR.size.x * (to - from), BAR.size.y + 4)
	if from <= 0.0:
		cut = cut.grow_side(SIDE_LEFT, 2)
	var clip := _mpoints(slot, PackedVector2Array([cut.position, Vector2(cut.end.x, cut.position.y), cut.end, Vector2(cut.position.x, cut.end.y)]))
	return Geometry2D.intersect_polygons(_bar_points(slot), clip)

func _bar_uvs(slot: int, points: PackedVector2Array) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	for point in points:
		var x := point.x if slot == 0 else 1280.0 - point.x
		uvs.append(Vector2((x - BAR.position.x) / BAR.size.x, (point.y - BAR.position.y) / BAR.size.y))
	return uvs

func _cell_points(slot: int, rect: Rect2) -> PackedVector2Array:
	var lean := 5.0
	if slot == 0:
		return Kit.slant(rect, lean)
	return PackedVector2Array([rect.position, Vector2(rect.end.x - lean, rect.position.y), rect.end, Vector2(rect.position.x + lean, rect.end.y)])

func _hp_color(ratio: float) -> Color:
	var color := HP_GOLD.lerp(HP_AMBER, clampf((0.55 - ratio) / 0.2, 0, 1))
	color = color.lerp(HP_RED, clampf((0.32 - ratio) / 0.08, 0, 1))
	if ratio < 0.25:
		color = color.lerp(Color("ff9a78"), 0.18 + 0.18 * sin(time * 7.5))
	return color

# --- Base layer: plates, tracks and damage trails --------------------------------

func _draw() -> void:
	if not _drawable():
		return
	for slot in range(2):
		var visual := _visual(slot)
		# Ink wash behind the name and bar keeps them legible on any stage.
		var wash := _mpoints(slot, PackedVector2Array([Vector2(0, 0), Vector2(612, 0), Vector2(588, 92), Vector2(0, 112)]))
		var shade := PackedColorArray()
		for point in wash:
			var outer := absf(point.x - 640.0) / 640.0
			shade.append(Color(Kit.INK_900, 0.62 * outer * (1.0 - point.y / 130.0)))
		draw_polygon(wash, shade)
		draw_colored_polygon(_bar_points(slot, BAR.grow(5)), Color(Kit.INK_900, 0.92))
		Kit.gradient_fill(self, _bar_points(slot), Kit.INK_700, Kit.INK_900)
		Kit.pattern(self, _mrect(slot, BAR), Kit.pattern_for(combat.fighters[slot].character), Color(visual.accent, 0.07), 8, _bar_points(slot))
		var hp := clampf(combat.fighters[slot].hp / 1000.0, 0, 1)
		var trail := clampf(trailing[slot] / 1000.0, hp, 1)
		var chip := CHIP.lerp(Color("fff1dc"), clampf(damage_flash[slot] / 0.14, 0, 1))
		for polygon: PackedVector2Array in _bar_span(slot, hp, trail):
			draw_colored_polygon(polygon, chip)
		if not cinematic_mode:
			for n in range(3):
				var cell := meter_cell(slot, n)
				draw_colored_polygon(_cell_points(slot, cell.grow(2)), Color(Kit.INK_900, 0.9))
				Kit.gradient_fill(self, _cell_points(slot, cell), Color(Kit.INK_700, 0.95), Color(Kit.INK_900, 0.95))

# --- Shader fills -----------------------------------------------------------------

func _draw_health_fills() -> void:
	if not _drawable():
		return
	(gauges.material as ShaderMaterial).set_shader_parameter("phase", time)
	for slot in range(2):
		var hp := clampf(combat.fighters[slot].hp / 1000.0, 0, 1)
		var tint := _hp_color(hp)
		for polygon: PackedVector2Array in _bar_span(slot, 0.0, hp):
			gauges.draw_polygon(polygon, PackedColorArray([tint]), _bar_uvs(slot, polygon), white)

func _draw_meter_fills() -> void:
	if not _drawable() or cinematic_mode:
		return
	(meters.material as ShaderMaterial).set_shader_parameter("phase", time)
	for slot in range(2):
		var f = combat.fighters[slot]
		var stock := clampi(int(f.meter / 100), 0, 3)
		var tint: Color = _visual(slot).accent
		if stock == 3:
			tint = Kit.GOLD.lerp(Color("fff2c4"), 0.25 + 0.25 * sin(time * 6.0))
		if meter_error[slot] > 0:
			tint = Color("f48a8f")
		tint = tint.lightened(meter_flash[slot] * 0.6)
		var span := CELL_STEP * 2 + CELL.x
		for n in range(3):
			var fill := meter_fill_rect(slot, f.meter, n)
			if fill.size.x < 1.0:
				continue
			var cell := meter_cell(slot, n)
			var full: bool = fill.size.x >= cell.size.x - 0.01
			var color := tint if full else Color(tint.darkened(0.25), 0.85)
			var clip := PackedVector2Array([fill.position, Vector2(fill.end.x, fill.position.y), fill.end, Vector2(fill.position.x, fill.end.y)])
			for polygon: PackedVector2Array in Geometry2D.intersect_polygons(_cell_points(slot, cell), clip):
				var uvs := PackedVector2Array()
				for point in polygon:
					var x := point.x if slot == 0 else 1280.0 - point.x
					uvs.append(Vector2((x - METER_X) / span, (point.y - METER_Y) / CELL.y))
				meters.draw_polygon(polygon, PackedColorArray([color]), uvs, white)

# --- Overlay: frames, portraits, timer, captions -----------------------------------

func _draw_overlay() -> void:
	if not _drawable():
		return
	for slot in range(2):
		var f = combat.fighters[slot]
		var visual := _visual(slot)
		_draw_bar_frame(slot, visual)
		_draw_portrait(slot, f, visual)
		_draw_nameplate(slot, f, visual)
		_draw_wins(slot)
		if not cinematic_mode:
			_draw_meter(slot, f, visual)
			_awakening_status(slot, f)
	_draw_timer()
	if cinematic_mode:
		return
	if combat.practice and training != null:
		_practice()
	else:
		_draw_input_hint(0, input_hints[0])
		if cpu:
			Kit.text_aligned(overlay, catalog.numeric_font, "CPU", Vector2(1256, 713), 12, Color(MUTED, 0.75), 2, 2)
		else:
			_draw_input_hint(1, input_hints[1])

## Compact footer legend: player chip, movement keys and the four attack keys
## as keycaps ("W A S D / U I · J K"); pad hints stay as text.
func _draw_input_hint(slot: int, hint: String) -> void:
	var font: Font = catalog.body_font
	var parts := hint.split(" / ")
	var keys: Array[String] = []
	if parts.size() == 2 and not hint.begins_with("手柄"):
		keys.append(parts[0].replace(" ", ""))
		for group in parts[1].split(" · "):
			for key in group.split(" ", false):
				keys.append(key)
	var height := 15.0
	var width := Kit.width(catalog.numeric_font, "P%d" % [slot + 1], 11) + 12
	if keys.is_empty():
		width += Kit.width(font, hint, 11)
	else:
		for key in keys:
			width += Kit.keycap_width(font, key, height) + 4
	var x := 24.0 if slot == 0 else 1256.0 - width
	var chip := Rect2(x, 704, Kit.width(catalog.numeric_font, "P%d" % [slot + 1], 11) + 8, 15)
	overlay.draw_colored_polygon(Kit.slant(chip, 3), Color(Kit.player_color(slot), 0.75))
	Kit.text_aligned(overlay, catalog.numeric_font, "P%d" % [slot + 1], Vector2(chip.get_center().x, chip.end.y - 3), 11, Kit.INK_900, 1)
	x = chip.end.x + 4
	if keys.is_empty():
		Kit.text(overlay, font, hint, Vector2(x, 716), 11, Color(MUTED, 0.75), 2)
		return
	for i in range(keys.size()):
		x += Kit.keycap(overlay, font, keys[i], Vector2(x, 711.5), height, false, 0.7) + (8 if i == 0 else 4)

func _draw_bar_frame(slot: int, visual: Resource) -> void:
	Kit.frame(overlay, _bar_points(slot, BAR.grow(2)), Kit.GOLD, 1.0, 2.5, 1.2)
	for n in range(1, 4):
		var x := _mx(slot, BAR.position.x + BAR.size.x * n / 4.0)
		overlay.draw_line(Vector2(x, BAR.position.y + 13), Vector2(x, BAR.end.y - 2), Color(Kit.INK_900, 0.45), 1.5, true)
	# Gilt end cap where the blade meets the timer.
	var tip := Vector2(_mx(slot, BAR.end.x + 4), BAR.get_center().y)
	Kit.diamond(overlay, tip, 7, Kit.INK_900)
	Kit.diamond(overlay, tip, 5, Kit.GOLD)
	var outer := Vector2(_mx(slot, BAR.position.x - 2), BAR.end.y + 4)
	overlay.draw_line(outer, outer + Vector2(160 if slot == 0 else -160, 0), Color(visual.accent, 0.55), 1.5, true)

func _draw_portrait(slot: int, f: RefCounted, visual: Resource) -> void:
	var rect := _mrect(slot, PORTRAIT)
	var shape := Kit.chamfer(rect, 20, 5 if slot == 0 else 10)
	_portrait_shadow(shape)
	Kit.gradient_fill(overlay, shape, Kit.INK_600, Kit.INK_900)
	Kit.pattern(overlay, rect, Kit.pattern_for(f.character), Color(visual.accent, 0.12), 10, shape)
	var texture: Texture2D = visual.battle_portrait if visual.battle_portrait != null else visual.avatar
	var awakened: bool = f.awakening_ticks > 0 or f.presents_awakened_finisher()
	if not combat.cinematic.is_empty() and combat.cinematic.attacker == slot and not combat.cinematic.get("released", false):
		awakened = awakened or combat.cinematic.get("awakened", false)
	if combat.cinematic_victory_form_slot == slot and combat.phase in ["round_end", "match_end"]:
		awakened = true
	if awakened and visual.awakened_portrait != null:
		texture = visual.awakened_portrait
	Kit.clipped_texture(overlay, texture, shape, rect, Rect2(0, 0, 1, 1), slot == 1)
	# Ground the bust with a soft ink fade along the lower edge.
	var foot := Kit.chamfer(Rect2(rect.position.x, rect.end.y - 26, rect.size.x, 26), 20, 4 if slot == 0 else 8)
	Kit.gradient_fill(overlay, foot, Color(Kit.INK_900, 0), Color(Kit.INK_900, 0.7))
	var accent: Color = visual.accent
	if f.awakening_ticks > 0 and combat.definition(f).awakening != null:
		accent = combat.definition(f).awakening.color
	Kit.frame(overlay, shape, Kit.GOLD, 1.0, 4.0, 1.6)
	overlay.draw_polyline(Kit.closed(Kit.chamfer(rect.grow(-5), 16, 5 if slot == 0 else 10)), Color(accent, 0.35), 1.0, true)
	# Player tag and element crest sit on the frame.
	var tag := "P1" if slot == 0 else ("木桩" if combat.practice else ("CPU" if cpu else "P2"))
	var font: Font = catalog.numeric_font
	var tag_width := Kit.width(font, tag, 13) + 14
	var chip := Rect2(rect.position.x + (4 if slot == 0 else rect.size.x - tag_width - 4), rect.end.y - 9, tag_width, 18)
	overlay.draw_colored_polygon(Kit.slant(chip, 4), Kit.player_color(slot))
	Kit.text_aligned(overlay, font, tag, Vector2(chip.get_center().x, chip.end.y - 4), 13, Kit.INK_900, 1)
	Kit.crest(overlay, catalog.display_font, Kit.crest_glyph(visual.element_name), Vector2(_mx(slot, PORTRAIT.end.x - 10), PORTRAIT.position.y + 12), 13, visual.accent)

func _portrait_shadow(shape: PackedVector2Array) -> void:
	var offset := PackedVector2Array()
	for point in shape:
		offset.append(point + Vector2(3, 4))
	overlay.draw_colored_polygon(offset, Color(0, 0, 0, 0.35))

func _draw_nameplate(slot: int, f: RefCounted, visual: Resource) -> void:
	var font: Font = catalog.title_font
	var name_width := Kit.text_aligned(overlay, font, visual.display_name, Vector2(_mx(slot, BAR.position.x + 2), 33), 21, PAPER, 0 if slot == 0 else 2, 4)
	var element_at := Vector2(_mx(slot, BAR.position.x + name_width + 14), 32)
	Kit.diamond(overlay, element_at + Vector2(0, -5), 3, visual.accent)
	Kit.text_aligned(overlay, catalog.body_font, visual.element_name, element_at + Vector2(9 if slot == 0 else -9, 0), 12,
		Color(visual.accent.lightened(0.25), 0.95), 0 if slot == 0 else 2, 3)
	if f.awakening_ticks > 0:
		var data: Resource = combat.definition(f).awakening
		Kit.text_aligned(overlay, catalog.numeric_font, "AWAKENED", Vector2(_mx(slot, BAR.end.x - 4), 32), 12, data.color.lightened(0.2), 2 if slot == 0 else 0, 3)

func _draw_wins(slot: int) -> void:
	for n in range(2):
		var center := Vector2(_mx(slot, BAR.end.x - 18 - n * 24), 77)
		var won: bool = combat.wins[slot] > n
		if won:
			var pop := 1.0 + (0.6 * Kit.ease_out(win_pop[slot] / 0.5) if n == combat.wins[slot] - 1 else 0.0)
			Kit.glow(overlay, center, 14 * pop, Color(Kit.GOLD, 0.55))
			Kit.diamond(overlay, center, 8 * pop, Kit.INK_900)
			Kit.diamond(overlay, center, 6.5 * pop, Kit.GOLD)
			Kit.diamond(overlay, center, 2.5, Kit.GOLD_HI)
		else:
			Kit.diamond(overlay, center, 7, Color(Kit.INK_900, 0.85))
			Kit.diamond(overlay, center, 6, Color(Kit.GOLD, 0.6), false, 1.2)

func _draw_timer() -> void:
	var center := Vector2(640, 50)
	var practice: bool = combat.practice
	var seconds := ceili(combat.remaining / 60.0)
	var urgent: bool = not practice and seconds <= 10 and combat.phase == "fight"
	var rim: Color = Kit.CRIMSON.lerp(Kit.GOLD_HI, 0.3 + 0.3 * sin(time * 9.0)) if urgent else Kit.GOLD
	Kit.glow(overlay, center, 58, Color(Kit.INK_900, 0.55))
	Kit.tsuba(overlay, center, 40, rim)
	var value := "∞" if practice else str(seconds)
	var font: Font = catalog.body_font if practice else catalog.numeric_font
	var color: Color = Color("ff8a7a") if urgent else PAPER
	Kit.text_aligned(overlay, font, value, center + Vector2(0, 16), 40 if not practice else 36, color, 1, 6)
	var label := "修炼模式" if practice else "第%s回合" % Kit.numeral(combat.round_number)
	var label_font: Font = catalog.title_font
	var w := Kit.width(label_font, label, 12) + 26
	var plate := Rect2(640 - w * 0.5, 94, w, 19)
	overlay.draw_colored_polygon(Kit.chamfer(plate, 6), Color(Kit.INK_900, 0.9))
	overlay.draw_polyline(Kit.closed(Kit.chamfer(plate, 6)), Color(Kit.GOLD, 0.7), 1.0, true)
	Kit.text_aligned(overlay, label_font, label, Vector2(640, plate.end.y - 5), 12, Kit.GOLD_HI, 1)

func _draw_meter(slot: int, f: RefCounted, visual: Resource) -> void:
	var left := slot == 0
	var stock := clampi(int(f.meter / 100), 0, 3)
	var max_ready := stock == 3
	var error := meter_error[slot] > 0
	var tint: Color = Color("f48a8f") if error else visual.accent
	for n in range(3):
		var cell := meter_cell(slot, n)
		var full: bool = meter_fill_rect(slot, f.meter, n).size.x >= cell.size.x - 0.01
		var line: Color = Kit.GOLD_HI if max_ready else (tint.lightened(0.3) if full else Color(Kit.GOLD, 0.65))
		overlay.draw_polyline(Kit.closed(_cell_points(slot, cell)), Color(Kit.INK_900, 0.9), 2.5, true)
		overlay.draw_polyline(Kit.closed(_cell_points(slot, cell)), line, 1.0, true)
	if max_ready:
		var span := Rect2(meter_cell(slot, 0).position, Vector2(CELL_STEP * 2 + CELL.x, CELL.y))
		Kit.glow(overlay, span.get_center(), 120, Color(Kit.GOLD, 0.12 + 0.06 * sin(time * 6.0)))
	var crest_at := Vector2(_mx(slot, CREST.x), CREST.y)
	if max_ready or meter_flash[slot] > 0:
		Kit.glow(overlay, crest_at, 46, Color(Kit.GOLD if max_ready else tint, 0.35 + meter_flash[slot]))
	Kit.crest(overlay, catalog.display_font, Kit.crest_glyph(visual.element_name), crest_at, 30, tint)
	# Stock count reads "2/3" at the inner end of the gauge on both sides.
	var count_width := Kit.width(catalog.numeric_font, str(stock), 34)
	var group := count_width + 4 + Kit.width(catalog.numeric_font, "/3", 13)
	var inner := METER_X + CELL_STEP * 2 + CELL.x + 12
	var count_x := inner if left else 1280.0 - inner - group
	var count_color: Color = Kit.GOLD_HI if max_ready else PAPER
	Kit.text(overlay, catalog.numeric_font, str(stock), Vector2(count_x, METER_Y + 19), 34, count_color, 5)
	Kit.text(overlay, catalog.numeric_font, "/3", Vector2(count_x + count_width + 4, METER_Y + 19), 13, Color(Kit.PAPER_DIM, 0.8), 3)
	var heading_x := _mx(slot, METER_X + 2)
	Kit.text_aligned(overlay, catalog.title_font, visual.element_name, Vector2(heading_x, METER_Y - 7), 14, PAPER, 0 if left else 2, 3)
	if max_ready:
		var pulse := 0.75 + 0.25 * sin(time * 8.0)
		Kit.text_aligned(overlay, catalog.numeric_font, "MAX", Vector2(_mx(slot, METER_X + CELL_STEP * 2 + CELL.x), METER_Y - 6), 18, Color(Kit.GOLD_HI, pulse), 2 if left else 0, 4)
	var caption := "觉醒 " + awakening_hints[slot] if stock >= 2 else ""
	var caption_color: Color = Kit.GOLD
	if f.awakening_ticks > 0:
		var data: Resource = combat.definition(f).awakening
		caption_color = data.color.lightened(0.15)
		caption = awakening_meter_caption(f)
	if error:
		caption = "气量不足"
		caption_color = Color("ff9aa0")
	elif spent_time[slot] > 0 and f.awakening_ticks <= 0:
		caption = "−%d 格" % int(meter_spent[slot] / 100)
		caption_color = Kit.GOLD_HI
	Kit.text_aligned(overlay, catalog.body_font, caption, Vector2(heading_x, METER_Y + 33), 13, caption_color, 0 if left else 2, 3)

func _awakening_emblem(at: Vector2, cid: String, color: Color) -> void:
	if cid == "zenitsu":
		overlay.draw_colored_polygon(PackedVector2Array([at + Vector2(1,-9),at + Vector2(-6,1),at + Vector2(-1,1),at + Vector2(-3,9),at + Vector2(7,-3),at + Vector2(2,-3)]), color)
	elif cid == "nezuko":
		var points := PackedVector2Array([at+Vector2(0,-9),at+Vector2(2,-2),at+Vector2(6,-5),at+Vector2(7,3),at+Vector2(2,8),at+Vector2(-3,8),at+Vector2(-7,3),at+Vector2(-5,-3),at+Vector2(-3,1)])
		overlay.draw_colored_polygon(points, color)
		Kit.diamond(overlay, at + Vector2(0,3), 3, INK)
	else:
		var count := 6 if cid == "akaza" else 8
		for n in range(count):
			var direction := Vector2.from_angle(n * TAU / count)
			overlay.draw_line(at + direction * 4, at + direction * 9, color, 1.2, true)
		Kit.diamond(overlay, at, 3, color, false)

func _awakening_status(slot: int, f: RefCounted) -> void:
	if f.awakening_ticks <= 0:
		return
	var data: Resource = combat.definition(f).awakening
	var left := slot == 0
	var rect := _mrect(slot, Rect2(BAR.position.x, 70, 300, 36))
	var infinite: bool = combat.practice and combat.awakening_infinite
	var warning: bool = not infinite and f.awakening_ticks <= 120
	var accent: Color = data.color.lerp(Color("ffe4cf"), 0.16)
	if warning:
		accent = accent.lerp(Color("fff0df"), 0.30 + 0.22 * sin(f.awakening_ticks * 0.23))
	var shape := Kit.chamfer(rect, 9, 6 if left else 9)
	Kit.gradient_fill(overlay, shape, Color(Kit.INK_700, 0.93), Color(Kit.INK_900, 0.93))
	Kit.gradient_fill(overlay, Kit.chamfer(rect, 9, 6 if left else 9), Color(accent, 0.16), Color(accent, 0.0))
	overlay.draw_polyline(Kit.closed(shape), Color(accent, 0.6), 1.0, true)
	overlay.draw_rect(Rect2(rect.position.x if left else rect.end.x - 3, rect.position.y, 3, rect.size.y), accent)
	var edge := rect.position.x if left else rect.end.x
	var direction := 1.0 if left else -1.0
	_awakening_emblem(Vector2(edge + direction * 20, rect.get_center().y), f.character, accent)
	var align := 0 if left else 2
	Kit.text_aligned(overlay, catalog.body_font, "快速觉醒" if f.awakening_quick else "觉醒", Vector2(edge + direction * 38, rect.position.y + 13), 10, Color(accent, 0.95), align, 2)
	Kit.text_aligned(overlay, catalog.display_font, data.display_name, Vector2(edge + direction * 38, rect.position.y + 30), 17, PAPER, align, 3)
	var seconds := "∞" if infinite else "%.1f" % (f.awakening_ticks / 60.0)
	var far := rect.end.x if left else rect.position.x
	Kit.text_aligned(overlay, catalog.numeric_font if not infinite else catalog.body_font, seconds, Vector2(far - direction * 22, rect.position.y + 26), 22, accent, 2 if left else 0, 3)
	if not infinite:
		Kit.text_aligned(overlay, catalog.numeric_font, "s", Vector2(far - direction * 16, rect.position.y + 26), 11, Color(PAPER, 0.7), 0 if left else 2)
	var fraction := 1.0 if infinite else clampf(float(f.awakening_ticks) / maxi(1, f.awakening_duration), 0, 1)
	var rail := Rect2(rect.position.x + 38, rect.end.y - 5, rect.size.x - 50, 2)
	if not left:
		rail.position.x = rect.position.x + 12
	overlay.draw_rect(rail, Color(accent, 0.16))
	var fill := Rect2(rail.position + Vector2(0 if left else rail.size.x * (1 - fraction), 0), Vector2(rail.size.x * fraction, 2))
	overlay.draw_rect(fill, accent)
	if fraction > 0:
		overlay.draw_rect(Rect2(fill.end.x - 2 if left else fill.position.x, rail.position.y - 1, 2, 4), Color("fff4dc"))

# --- Practice -----------------------------------------------------------------------

func _practice() -> void:
	var chip := "%s  ·  最近 %d HIT / %d 伤害" % [GUARD_NAMES[training.guard_mode], training.last_combo, training.last_damage]
	var font: Font = catalog.body_font
	var w := Kit.width(font, chip, 13) + 34
	var plate := Rect2(640 - w * 0.5, 122, w, 24)
	Kit.plate(overlay, Kit.chamfer(plate, 7), 0.86)
	Kit.text_aligned(overlay, font, chip, Vector2(640, plate.end.y - 7), 13, Kit.GOLD_HI, 1)
	_input_log(Rect2(12, 132, 150, 372))
	if has_super_title() or frozen:
		return
	if practice_details_visible():
		var card := Rect2(405, 156, 470, 108)
		Kit.plate(overlay, Kit.chamfer(card, 10, 5), 0.82)
		var hints := practice_hints()
		for n in range(hints.size()):
			Kit.text(overlay, font, hints[n], Vector2(card.position.x + 16, card.position.y + 24 + n * 22), 16 if n < 2 else 13, PAPER if n < 2 else MUTED, 3)
		Kit.text(overlay, font, practice_feedback(), Vector2(card.position.x + 16, card.end.y - 12), 14, Kit.GOLD_HI, 3)
	elif not combat.fighters[0].input.feedback.is_empty():
		var message := practice_feedback()
		var size := Kit.fitted(font, message, 15, 560)
		var toast := Rect2(96, 600, Kit.width(font, message, size) + 32, 28)
		Kit.plate(overlay, Kit.chamfer(toast, 8, 5), 0.88, Kit.GOLD_HI)
		Kit.text(overlay, font, message, Vector2(toast.position.x + 16, toast.end.y - 9), size, Kit.GOLD_HI, 3)

func _input_log(rect: Rect2) -> void:
	var shape := Kit.chamfer(rect, 10, 9)
	Kit.gradient_fill(overlay, shape, Color(Kit.INK_700, 0.74), Color(Kit.INK_900, 0.5))
	overlay.draw_polyline(Kit.closed(shape), Color(Kit.GOLD, 0.35), 1.0, true)
	Kit.text(overlay, catalog.title_font, "输入记录", Vector2(rect.position.x + 12, rect.position.y + 21), 13, Kit.GOLD_HI, 3)
	Kit.tracked(overlay, catalog.numeric_font, "INPUT", Vector2(rect.end.x - 12, rect.position.y + 20), 10, Color(Kit.GOLD, 0.7), 1.5, 2)
	Kit.rule(overlay, rect.position + Vector2(8, 28), Vector2(rect.end.x - 8, rect.position.y + 28), Color(Kit.GOLD, 0.5))
	var input = combat.fighters[0].input
	var entries: Array = input.history
	var rows := mini(entries.size(), 12)
	for row in range(rows):
		var index: int = entries.size() - 1 - row
		var entry: Dictionary = entries[index]
		var next_tick: int = input.tick + 1 if index == entries.size() - 1 else int(entries[index + 1].tick)
		var frames := clampi(next_tick - int(entry.tick), 1, 99)
		var y := rect.position.y + 50 + row * 26
		var alpha := 1.0 - row * 0.055
		Kit.text_aligned(overlay, catalog.numeric_font, str(frames), Vector2(rect.position.x + 34, y + 5), 14, Color(Kit.PAPER_DIM, alpha), 2, 2)
		Kit.arrow(overlay, Vector2(rect.position.x + 52, y), 9.5, int(entry.direction), Color(PAPER, alpha))
		var x := rect.position.x + 72
		for n in range(4):
			if int(entry.buttons) & (1 << n):
				var tint: Color = BUTTON_TINTS[n]
				overlay.draw_circle(Vector2(x, y), 9, Color(Kit.INK_900, alpha), true, -1, true)
				overlay.draw_circle(Vector2(x, y), 7.5, Color(tint.darkened(0.2), alpha), true, -1, true)
				Kit.text_aligned(overlay, catalog.numeric_font, "ABCD"[n], Vector2(x, y + 4.5), 12, Color(PAPER, alpha), 1)
				x += 20
	var action: String = input.last_action
	if not action.is_empty():
		var size := Kit.fitted(catalog.body_font, action, 13, rect.size.x - 20)
		Kit.text(overlay, catalog.body_font, action, Vector2(rect.position.x + 10, rect.end.y - 10), size, MUTED, 2)

# --- Animated nodes (combo, callouts, awakening reveal) -----------------------------

## Left column start for P1 callouts; practice shifts it past the input log.
func _column(slot: int) -> float:
	return (166.0 if combat.practice and training != null else 16.0) if slot == 0 else 1264.0

func _combo_origin(slot: int) -> float:
	return _column(slot) + (10.0 if slot == 0 else -10.0)

func _sync_nodes() -> void:
	if combo_digits.is_empty():
		return
	if round_banner != null:
		round_banner.visible = not cinematic_mode
		if not cinematic_mode:
			round_banner.cue = combat.round_cue()
	for slot in range(2):
		var digits = combo_digits[slot]
		var band = combo_bands[slot]
		var visible_combo := combo_fade[slot] > 0 and combo_shown[slot] >= 2 and not frozen
		digits.visible = visible_combo
		band.visible = visible_combo
		if visible_combo:
			var alpha := clampf(combo_fade[slot] / 0.2, 0, 1)
			var count: int = combo_shown[slot]
			var tier := 2 if count >= 20 else (1 if count >= 10 else 0)
			digits.set_ramp(COMBO_RAMPS[tier])
			digits.text = str(count)
			digits.refresh()
			var pop := 1.0 + 0.24 * pow(combo_pop[slot] / 0.2, 2)
			var block := _combo_block_width(slot)
			var x := _combo_origin(slot) if slot == 0 else _combo_origin(slot) - block
			var slide := (1.0 - alpha) * (-18.0 if slot == 0 else 18.0)
			digits.position = Vector2(x + slide, 236)
			digits.scale = Vector2.ONE * pop
			digits.modulate.a = alpha
			var ink: Color = Color(Kit.INK_900, 0.78 * alpha) if tier == 0 else Color(COMBO_RAMPS[tier][1].darkened(0.62), 0.82 * alpha)
			band.configure(Rect2(x - 22 + slide, 182, block + 70, 64), ink, 10.0, 1.0, slot == 1)
		var callout_band = callout_bands[slot]
		var show_callout := callout_time[slot] > 0 and not cinematic_mode and not has_super_title() and not frozen
		callout_band.visible = show_callout
		if show_callout:
			var value: String = callouts[slot]
			var size := Kit.fitted(catalog.display_font, value, 24, 420)
			var w := Kit.width(catalog.display_font, value, size) + 60
			var alpha := minf(1, callout_time[slot] * 3)
			var accent: Color = _visual(slot).accent
			var rect := Rect2(_column(0) if slot == 0 else 1264 - w, 118, w, 34)
			callout_band.configure(rect, Color(accent.darkened(0.45), 0.9 * alpha), 6.0, Kit.ease_out((1.2 - callout_time[slot]) / 0.18 + 0.2), slot == 1)
		var reveal = reveal_bands[slot]
		var show_reveal := awakening_reveal[slot] > 0 and not has_super_title() and not frozen and not cinematic_mode
		reveal.visible = show_reveal
		if show_reveal:
			var data: Resource = combat.definition(combat.fighters[slot]).awakening
			var progress := Kit.ease_out((0.85 - awakening_reveal[slot]) / 0.22)
			var alpha := smoothstep(0.0, 0.2, awakening_reveal[slot])
			var rect := Rect2(_column(0) - 4 if slot == 0 else 1268 - 300, 110, 300, 52)
			reveal.configure(rect, Color(data.color.darkened(0.35), 0.92 * alpha), 8.0, progress, slot == 1)

func _combo_block_width(slot: int) -> float:
	var digits = combo_digits[slot]
	return digits.text_width() + 12 + maxf(Kit.width(catalog.numeric_font, "HITS", 24), Kit.width(catalog.body_font, "连击", 13))

func _draw_labels() -> void:
	if not _drawable():
		return
	for slot in range(2):
		if combo_digits.size() > slot and combo_digits[slot].visible:
			var digits = combo_digits[slot]
			var alpha: float = digits.modulate.a
			var origin: Vector2 = digits.position
			var after: float = origin.x + digits.text_width() * digits.scale.x + 10
			var hits_color: Color = COMBO_RAMPS[2 if combo_shown[slot] >= 20 else (1 if combo_shown[slot] >= 10 else 0)][0]
			Kit.text(labels, catalog.numeric_font, "HITS", Vector2(after, origin.y - 30), 24, Color(hits_color, alpha), 5)
			Kit.text(labels, catalog.body_font, "连击", Vector2(after + 1, origin.y - 8), 13, Color(PAPER, alpha), 3)
			var damage := "%d 伤害" % combo_damage_shown[slot]
			var dw := Kit.width(catalog.body_font, damage, 14) + 22
			var plate := Rect2(origin.x + 4, origin.y + 8, dw, 22)
			Kit.plate(labels, Kit.slant(plate, 6), 0.88 * alpha, Color(Kit.GOLD, alpha))
			Kit.text_aligned(labels, catalog.body_font, damage, Vector2(plate.get_center().x, plate.end.y - 6), 14, Color(PAPER, alpha), 1)
		if callout_bands.size() > slot and callout_bands[slot].visible:
			var value: String = callouts[slot]
			var alpha := minf(1, callout_time[slot] * 3)
			var size := Kit.fitted(catalog.display_font, value, 24, 420)
			var accent: Color = _visual(slot).accent
			var x := _column(0) + 24.0 if slot == 0 else 1240.0
			Kit.text_aligned(labels, catalog.display_font, value, Vector2(x, 144), size, Color(accent.lightened(0.55), alpha), 0 if slot == 0 else 2, 4)
		if reveal_bands.size() > slot and reveal_bands[slot].visible:
			var data: Resource = combat.definition(combat.fighters[slot]).awakening
			var alpha := smoothstep(0.0, 0.2, awakening_reveal[slot])
			var slide := 14.0 * pow(clampf((awakening_reveal[slot] - 0.63) / 0.22, 0, 1), 2)
			var x := (_column(0) + 18.0 - slide) if slot == 0 else (1246.0 + slide)
			var f = combat.fighters[slot]
			Kit.text_aligned(labels, catalog.display_font, "觉 醒", Vector2(x, 148), 34, Color(PAPER, alpha), 0 if slot == 0 else 2, 5)
			Kit.tracked(labels, catalog.numeric_font, "QUICK CANCEL" if f.awakening_quick else "AWAKENING",
				Vector2(x + (112 if slot == 0 else -112), 143), 12, Color(data.color.lightened(0.45), alpha), 2.5, 0 if slot == 0 else 2)
