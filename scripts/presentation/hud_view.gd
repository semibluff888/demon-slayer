extends Control
## Screen-space HUD; presentation never changes combat resources.
const InputRouter = preload("res://scripts/input_router.gd")
const Style = preload("res://scripts/presentation/battle_style.gd")
const PAPER := Style.PAPER
const GOLD := Style.GOLD
const MUTED := Style.MUTED
var combat: RefCounted
var catalog: RefCounted
var cpu: bool = true
var training: RefCounted
var input_device: String = "keyboard:0"
var frozen: bool = false
var practice_details: bool = false
var input_hints: Array[String] = ["WASD / FG · VB", "↑↓←→ / JK · NM"]
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
var header: GradientTexture2D
var health: GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	header = _gradient(Color(0.012, 0.022, 0.04, 0.9), Color(0.012, 0.022, 0.04, 0), true)
	health = _gradient(Color("e3ed78"), Color("88d345"))

func _gradient(first: Color, last: Color, vertical: bool = false) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([first, last])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 32 if vertical else 512
	texture.height = 128 if vertical else 16
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.DOWN if vertical else Vector2.RIGHT
	return texture

func reset_effects() -> void:
	trailing.assign([1000.0, 1000.0])
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

func consume(events: Array) -> void:
	for event: Dictionary in events:
		if event.type == "swing" and combat.moves[event.move].kind == "skill":
			callouts[event.attacker] = combat.moves[event.move].display_name
			callout_time[event.attacker] = 1.2
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
	if combat == null or catalog == null or combat.fighters.is_empty():
		return
	if not frozen:
		time += delta
		for i in range(2):
			meter_flash[i] = maxf(0, meter_flash[i] - delta)
			meter_error[i] = maxf(0, meter_error[i] - delta)
			spent_time[i] = maxf(0, spent_time[i] - delta)
			combo_pop[i] = maxf(0, combo_pop[i] - delta)
			trailing[i] = move_toward(trailing[i], combat.fighters[i].hp, delta * 270)
			callout_time[i] = maxf(0, callout_time[i] - delta)
			var stock := int(combat.fighters[i].meter / 100)
			if stock > last_stock[i]:
				meter_flash[i] = 0.55
			last_stock[i] = stock
			last_combo[i] = combat.fighters[i].combo
	queue_redraw()

func _text(value: String, at: Vector2, font_size: int, color: Color = PAPER, title: bool = false) -> void:
	Style.text(self, catalog.title_font if title else catalog.body_font, value, at, font_size, color, 3 if font_size >= 20 else 2)

func _right_text(value: String, right: float, y: float, font_size: int, color: Color = PAPER, title: bool = false) -> void:
	var font: Font = catalog.title_font if title else catalog.body_font
	_text(value, Vector2(right - font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, y), font_size, color, title)

func _fitted_text(value: String, at: Vector2, font_size: int, width: float, color: Color) -> void:
	var measured: float = catalog.body_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, at, mini(font_size, int(font_size * width / maxf(1, measured))), color)

func _diamond(at: Vector2, radius: float, color: Color, filled: bool = true) -> void:
	Style.diamond(self, at, radius, color, filled)

func practice_hints() -> Array[String]:
	return InputRouter.motion_hints(input_device, combat.fighters[0].facing)

func practice_feedback() -> String:
	var down := "S" if input_device == "keyboard:0" else "↓"
	match combat.fighters[0].input.feedback:
		"release_down": return "搓招提示：仍在斜下，松开%s再按横方向＋攻击。" % down
		"motion_timeout": return "搓招提示：方向超时，请在0.5秒内连贯输入。"
		"attack_late": return "搓招提示：攻击偏晚，请在横方向后0.2秒内按攻击。"
		"wrong_button": return "搓招提示：236配轻重斩，214配轻重体术；按右侧键位。"
	return "方向和攻击不必同时按；斜方向可省略。"

func _portrait(slot: int, visual: Resource) -> void:
	var x := 17.0 if slot == 0 else 1137.0
	var points := PackedVector2Array([Vector2(x + 5, 24),Vector2(x + 108, 17),Vector2(x + 124, 87),Vector2(x + 102, 113),Vector2(x, 101)])
	draw_colored_polygon(points, Color("121c2a"))
	points.append(points[0])
	draw_polyline(points, GOLD.darkened(0.35), 4, true)
	var texture: Texture2D = visual.battle_portrait if visual.battle_portrait != null else visual.avatar
	if texture != null:
		draw_set_transform(Vector2(x-2 if slot==0 else x+129,-2),0,Vector2(1 if slot==0 else -1,1))
		draw_texture_rect(texture,Rect2(0,0,131,126),false)
		draw_set_transform(Vector2.ZERO)
	draw_line(Vector2(x, 104), Vector2(x + 104, 116), GOLD, 2, true)
	Style.cloud(self, Vector2(x + 10 if slot == 0 else x + 111, 103), 1 if slot == 0 else -1, 0.75)
	_diamond(Vector2(x + 116 if slot == 0 else x + 4, 35), 4, visual.accent)

func _health_bar(slot: int, f: RefCounted, visual: Resource) -> void:
	var x := 147.0 if slot == 0 else 706.0
	var width := 427.0
	if slot == 0:
		_text(visual.display_name, Vector2(x, 37), 24, PAPER, true)
		_right_text("P1", x + width, 35, 13, visual.accent)
	else:
		_right_text(visual.display_name, x + width, 37, 24, PAPER, true)
		_text("木桩" if combat.practice else ("CPU" if cpu else "P2"), Vector2(x, 35), 13, visual.accent)
	var rail := PackedVector2Array([Vector2(x-9,47),Vector2(x+width+7,47),Vector2(x+width+1,76),Vector2(x-1,76)])
	draw_colored_polygon(rail, Color("090d16"))
	rail.append(rail[0])
	draw_polyline(rail, GOLD, 2, true)
	var hp := clampf(f.hp / 1000.0, 0, 1)
	var trail := clampf(trailing[slot] / 1000.0, hp, 1)
	var origin := x if slot == 0 else x + width * (1 - trail)
	draw_rect(Rect2(origin,52,width*trail,18),Color("b74442"))
	origin = x if slot == 0 else x + width * (1 - hp)
	var tint := Color.WHITE if hp >= 0.25 else Color(1,0.69 + sin(time*6)*0.1,0.5)
	if hp > 0:
		draw_texture_rect(health,Rect2(origin,52,width*hp,18),false,tint)
		draw_line(Vector2(origin,53),Vector2(origin+width*hp,53),Color("f7ffd0"),1,true)
	for n in range(1, 10):
		var tick_x := x + width * n / 10.0
		draw_line(Vector2(tick_x,68),Vector2(tick_x,71),Color(0,0,0,0.35),1,true)
	draw_line(Vector2(x,80),Vector2(x+width,80),Color(visual.accent,0.65),2,true)
	for n in range(2):
		var dx := x + 11 + n * 24 if slot == 0 else x + width - 11 - n * 24
		_diamond(Vector2(dx,96),7,GOLD if combat.wins[slot]>n else Color("19202d"))
		_diamond(Vector2(dx,96),8,GOLD,true if combat.wins[slot]>n else false)
	if slot == 0:
		_right_text(visual.element_name,x+width,99,14,visual.accent)
	else:
		_text(visual.element_name,Vector2(x,99),14,visual.accent)

func _meter(slot: int, f: RefCounted, visual: Resource) -> void:
	var left := slot == 0
	var center := Vector2(69 if left else 1211,655)
	var accent: Color = visual.accent
	var stock := int(f.meter / 100)
	var flash := meter_flash[slot]
	var tint := Color("ff697c") if meter_error[slot]>0 else accent
	Style.ink(self,Rect2(29 if left else 891,618,360,79),Color(0.025,0.045,0.075,0.87))
	draw_circle(center,34,Color("091727"),true,-1,true)
	for n in range(3):
		var start := time * (0.5 if stock==3 else 0.12) + n * TAU / 3.0
		draw_arc(center,34 + n%2*4,start,start+1.62,30,Color(tint,0.4+flash*0.5),3 if stock==3 else 2,true)
		draw_arc(center,29,start+0.12,start+1.28,24,Color(tint.lightened(0.4),0.85),1.4,true)
	_diamond(center,40,Color(tint,0.7),false)
	var number := str(stock)
	var number_width: float = catalog.title_font.get_string_size(number,HORIZONTAL_ALIGNMENT_LEFT,-1,45).x
	_text(number,center+Vector2(-number_width/2,16),45,PAPER,true)
	var bx := 118.0 if left else 914.0
	if left:
		_text(visual.element_name,Vector2(bx,637),18,PAPER,true)
	else:
		_right_text(visual.element_name,bx+248,637,18,PAPER,true)
	for n in range(3):
		var cell := Rect2(bx+n*84,648,80,17)
		draw_rect(cell.grow(2),Color("07101c"))
		var fill := clampf((f.meter - (n if left else 2-n)*100)/100.0,0,1)
		var fill_rect := Rect2(cell.position + Vector2(0 if left else cell.size.x*(1-fill),0),Vector2(cell.size.x*fill,cell.size.y))
		draw_rect(fill_rect,tint.lightened(flash*0.6))
		draw_rect(Rect2(fill_rect.position,Vector2(fill_rect.size.x,3)),Color(tint.lightened(0.65),0.9))
		draw_rect(cell,GOLD if stock==3 else tint.lightened(0.22),false,1.1)
	var caption := "MAX  全呼吸" if stock==3 else "呼吸"
	if meter_error[slot]>0:
		caption = "气量不足"
	elif spent_time[slot]>0:
		caption = "−%d 格" % int(meter_spent[slot]/100)
	if left:
		_text(caption,Vector2(bx,688),14,tint if meter_error[slot]>0 else GOLD)
	else:
		_right_text(caption,bx+248,688,14,tint if meter_error[slot]>0 else GOLD)
	Style.cloud(self,center+Vector2(-12 if left else 12,38),1 if left else -1,0.60,0.8)

func _combo(slot: int, f: RefCounted) -> void:
	if f.combo_display<=0 or f.combo<2:
		return
	var left := slot==0
	var origin := Vector2(32 if left else 1054,193)
	var pop := 1.0 + sin(clampf(combo_pop[slot]/0.2,0,1)*PI)*0.12
	draw_set_transform(origin,0,Vector2.ONE*pop)
	Style.ink(self,Rect2(-5,3,186,76))
	var transform := Transform2D(Vector2(pop,0),Vector2(-0.15*pop,pop),origin)
	draw_set_transform_matrix(transform)
	_text(str(f.combo),Vector2(7,64),64,GOLD,true)
	draw_set_transform(origin)
	var digit_width: float = catalog.title_font.get_string_size(str(f.combo),HORIZONTAL_ALIGNMENT_LEFT,-1,64).x
	_text("HIT",Vector2(minf(112,14+digit_width),42),23,PAPER,true)
	_text("连击",Vector2(minf(112,14+digit_width),65),16,PAPER)
	_text("%d 伤害" % f.combo_damage,Vector2(9,98),16,GOLD)
	draw_set_transform(Vector2.ZERO)

func _practice() -> void:
	var names := ["站立不防","站立防御","蹲下防御","首击后防"]
	Style.ink(self,Rect2(406,618,468,80),Color(0.02,0.035,0.06,0.88))
	_text("%s  ·  最近 %d HIT / %d 伤害" % [names[training.guard_mode],training.last_combo,training.last_damage],Vector2(419,638),14,GOLD)
	var input_text := ""
	var entries: Array = combat.fighters[0].input.history
	for entry in entries.slice(maxi(0,entries.size()-8)):
		input_text+=str(entry.direction)
		for n in range(4):
			if int(entry.buttons)&(1<<n):
				input_text+="ABCD"[n]
		input_text+="  "
	_fitted_text(input_text,Vector2(419,659),15,440,PAPER)
	_fitted_text(combat.fighters[0].input.last_action,Vector2(419,684),14,440,MUTED)
	if practice_details:
		Style.ink(self,Rect2(270,117,740,119),Color(0.02,0.035,0.06,0.94))
		var hints := practice_hints()
		for n in range(hints.size()):
			_text(hints[n],Vector2(292,145+n*22),16 if n<2 else 14,PAPER if n<2 else MUTED)
		_text(practice_feedback(),Vector2(292,221),14,GOLD)
	elif not combat.fighters[0].input.feedback.is_empty():
		Style.ink(self,Rect2(298,572,684,32))
		_text(practice_feedback(),Vector2(310,594),15,GOLD)

func _draw() -> void:
	if combat==null or catalog==null or combat.fighters.size()<2 or header==null:
		return
	draw_texture_rect(header,Rect2(0,0,1280,132),false)
	for i in range(2):
		var f = combat.fighters[i]
		var visual = catalog.characters[f.character]
		_portrait(i,visual)
		_health_bar(i,f,visual)
		_meter(i,f,visual)
		_combo(i,f)
		if callout_time[i]>0:
			var alpha := minf(1,callout_time[i]*3)
			var x := 32.0 if i==0 else 811.0
			Style.ink(self,Rect2(x,135,436,41),Color(0.025,0.04,0.07,alpha*0.90))
			draw_line(Vector2(x+7,174),Vector2(x+423,174),Color(visual.accent,alpha),1,true)
			_fitted_text(callouts[i],Vector2(x+11,162),21,414,Color(PAPER,alpha))
	Style.ink(self,Rect2(588,7,104,83),Color(0.015,0.02,0.032,0.93))
	var seconds := "∞" if combat.practice else str(ceili(combat.remaining/60.0))
	var timer_width: float = catalog.title_font.get_string_size(seconds,HORIZONTAL_ALIGNMENT_LEFT,-1,59).x
	_text(seconds,Vector2(640-timer_width/2,69),59,PAPER,true)
	var round_label := "修  炼" if combat.practice else "第 %d 回合" % (combat.wins[0]+combat.wins[1]+1)
	_text(round_label,Vector2(612,105),13,GOLD)
	if combat.practice and training!=null:
		_practice()
	else:
		_text("P1  "+input_hints[0],Vector2(27,716),11,MUTED)
		_right_text("CPU" if cpu else "P2  "+input_hints[1],1253,716,11,MUTED)
	if combat.phase in ["intro","round_end"]:
		Style.ink(self,Rect2(339,264,602,108),Color(0.02,0.025,0.04,0.93))
		draw_line(Vector2(389,267),Vector2(895,267),GOLD,1.5,true)
		draw_line(Vector2(374,369),Vector2(880,369),GOLD,1.5,true)
		var message := ("凝神" if combat.phase_frames>45 else "拔刀") if combat.phase=="intro" else ("平局 · 再决" if combat.round_winner<0 else "胜负已分")
		var tw: float = catalog.title_font.get_string_size(message,HORIZONTAL_ALIGNMENT_LEFT,-1,53).x
		_text(message,Vector2(640-tw/2,338),53,PAPER,true)
