extends RefCounted
const Router = preload("res://scripts/input_router.gd")
const Kit = preload("res://scripts/ui/kit.gd")
const ACTION_NAMES := ["左", "右", "下", "上", "A", "B", "C", "D"]
const ACTION_HINTS := ["左移", "右移", "蹲 / 防", "跳跃", "A 轻攻击", "B 轻体术", "C 重攻击", "D 重体术"]
var app: Node
var menu: Control
var waiting_player: int = -1
var waiting_action: int = -1
var key_buttons: Dictionary = {}
var control_options: Array[OptionButton] = []
var notice: Label
var volume_label: Label

func build(owner: Control) -> void:
	menu = owner
	app = menu.app
	menu._backdrop(Color("223a55"), Color("3a1f33"), 0.45)
	menu._header("游戏设置", "OPTIONS", "即时生效 · 自动保存")
	menu.paint(Rect2(40, 108, 1200, 122), func(canvas: Control): _section(canvas, "壹", "声音与演出", Kit.P1))
	var mute := CheckButton.new()
	mute.name = "audio_mute"
	mute.text = "静音"
	mute.position = Vector2(60, 160)
	mute.size = Vector2(170, 44)
	mute.button_pressed = app.settings.muted
	mute.toggled.connect(func(value: bool): app.settings.muted=value; _audio_changed())
	menu.add_child(mute)
	menu.actions.audio_mute = mute
	menu.label("主音量",Rect2(268,164,80,36),17,menu.PAPER,true)
	var slider := HSlider.new()
	slider.name = "audio_volume"
	slider.position = Vector2(350,164)
	slider.size = Vector2(300,36)
	slider.min_value=0;slider.max_value=100;slider.step=1
	slider.value=roundi(app.settings.volume*100)
	menu.add_child(slider)
	menu.actions.audio_volume=slider
	volume_label=menu.label("%d%%" % slider.value,Rect2(664,164,90,36),22,Kit.GOLD_HI)
	slider.value_changed.connect(func(value: float): app.settings.volume=value/100.0; volume_label.text="%d%%" % value; _audio_changed())
	var cinematic := CheckButton.new()
	cinematic.name = "cinematic_enabled"
	cinematic.text = "必杀动画演出"
	cinematic.position = Vector2(800,146)
	cinematic.size = Vector2(400,44)
	cinematic.button_pressed = app.settings.cinematic_enabled
	cinematic.tooltip_text = "奥义 / MAX 命中后播放；关闭后沿用简化演出。"
	cinematic.toggled.connect(func(value: bool): app.settings.cinematic_enabled = value; _save())
	menu.add_child(cinematic)
	menu.actions.cinematic_enabled = cinematic
	menu.label("命中后播放 · 奥义 / MAX，关闭则使用简化演出",Rect2(816,190,400,24),13,menu.MUTED)
	for player in range(2):
		var x := 40 + player*610
		menu.paint(Rect2(x,246,590,360), func(canvas: Control): _section(canvas, "贰" if player == 0 else "叁", "P%d 键位" % [player+1], Kit.player_color(player)))
		var option: OptionButton = menu.device_option("control_p%d" % [player+1],Rect2(x+316,256,254,40))
		option.tooltip_text="控制方式"
		control_options.append(option)
		option.item_selected.connect(func(index: int): _change_controller(player,index))
		for row in range(4):
			for column in range(2):
				var action: int = [3,2,0,1][row] if column==0 else row+4
				var left: int = x+24+column*284
				menu.label(ACTION_HINTS[action],Rect2(left,322+row*52,104,40),16,Kit.PAPER_DIM if column == 0 else Kit.GOLD_HI,true)
				var id := "key_%d_%d" % [player,action]
				var key: Button = menu.button(id,Router.key_name(app.settings.keymaps[player][action]),Rect2(left+108,322+row*52,152,40),func(): _listen(player,action),false,false,18)
				key.keycap = true
				key_buttons[id]=key
		menu.button("defaults_p%d" % [player+1],"恢复 P%d 默认" % [player+1],Rect2(x+24,546,236,44),func(): _restore(player),false,false,17)
	menu.button("defaults_all","恢复双方默认按键",Rect2(940,662,300,46),_restore_all,false,false,17)
	menu.button("settings_back","返回",Rect2(40,662,220,46),app.close_settings,true,true,20).subtitle = "BACK"
	notice=menu.label("点击按键后按新键；Esc 取消改键。P2 默认使用小键盘。",Rect2(280,668,640,34),15,menu.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)
	refresh_controllers()
	menu.reveal()
	mute.grab_focus()
	# Include the slider and dropdowns in a logical tab order.
	var focus_order: Array[Control]=[mute,slider,cinematic]
	for player in range(2):
		focus_order.append(control_options[player])
		for row in range(4):
			for action: int in [[3,2,0,1][row],row+4]: focus_order.append(key_buttons["key_%d_%d" % [player,action]])
		focus_order.append(menu.actions["defaults_p%d" % [player+1]])
	focus_order.append(menu.actions.defaults_all)
	focus_order.append(menu.actions.settings_back)
	for i in range(focus_order.size()):
		var previous: Control=focus_order[posmod(i-1,focus_order.size())]
		var next: Control=focus_order[(i+1)%focus_order.size()]
		focus_order[i].focus_previous=focus_order[i].get_path_to(previous)
		focus_order[i].focus_next=focus_order[i].get_path_to(next)
		focus_order[i].focus_neighbor_top=focus_order[i].get_path_to(previous)
		focus_order[i].focus_neighbor_bottom=focus_order[i].get_path_to(next)

func _section(canvas: Control, numeral: String, heading: String, accent: Color) -> void:
	var rect := Rect2(Vector2.ZERO, canvas.size)
	var shape := Kit.chamfer(rect, 16, 5)
	Kit.gradient_fill(canvas, shape, Color(Kit.INK_700, 0.9), Color(Kit.INK_900, 0.93))
	Kit.frame(canvas, shape, Kit.GOLD, 0.85, 2.0, 1.0)
	Kit.seal(canvas, Rect2(18, 12, 28, 28), menu.catalog.display_font, numeral)
	Kit.text(canvas, menu.catalog.title_font, heading, Vector2(56, 34), 19, accent.lightened(0.25), 3)
	Kit.rule_out(canvas, Vector2(18, 48), Vector2(rect.size.x - 18, 48), Color(Kit.GOLD, 0.45))

func _save() -> void:
	var result: Error=app.settings.save_config()
	notice.text="已保存" if result==OK else app.settings.last_error
	notice.modulate=Color.WHITE if result==OK else Color("ff8197")

func _audio_changed() -> void:
	app.sound.set_levels(app.settings.muted,app.settings.volume)
	app.view.cinematic.sync_audio()
	_save()

func _listen(player: int, action: int) -> void:
	_cancel_listen()
	waiting_player=player;waiting_action=action
	var key: Button=key_buttons["key_%d_%d" % [player,action]]
	key.text="按下新按键…";key.selected=true;key.queue_redraw()
	notice.text="P%d · %s：按下新键，Esc 取消。" % [player+1,ACTION_NAMES[action]]

func _cancel_listen() -> void:
	if waiting_player>=0:
		var key: Button=key_buttons["key_%d_%d" % [waiting_player,waiting_action]]
		key.text=Router.key_name(app.settings.keymaps[waiting_player][waiting_action]);key.selected=false;key.queue_redraw()
	waiting_player=-1;waiting_action=-1

func handle(event: InputEvent) -> bool:
	if waiting_player<0:return false
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int=event.physical_keycode if event.physical_keycode else event.keycode
		if code==KEY_ESCAPE:
			_cancel_listen();notice.text="已取消改键"
		elif app.settings.bind(waiting_player,waiting_action,code):
			_cancel_listen();_apply_keys()
		else:
			notice.text=app.settings.last_error
	elif event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_B:
		_cancel_listen();notice.text="已取消改键"
	return event is InputEventKey or event is InputEventJoypadButton

func _apply_keys() -> void:
	app.router.apply_keymaps(app.settings.keymaps)
	app._reset_inputs()
	for player in range(2):
		for action in range(8): key_buttons["key_%d_%d" % [player,action]].text=Router.key_name(app.settings.keymaps[player][action])
	app.refresh_input_hints()
	_save()

func _restore(player: int) -> void:
	_cancel_listen()
	if app.settings.restore_keyboard(player):_apply_keys()
	else:notice.text=app.settings.last_error

func _restore_all() -> void:
	_cancel_listen()
	app.settings.keymaps=Router.KEYS.duplicate(true)
	_apply_keys()

func refresh_controllers() -> void:
	var available: Array=app.router.available_devices()
	for player in range(2):
		var option: OptionButton=control_options[player]
		option.clear()
		for entry in available:
			if entry.id.begins_with("keyboard:") and entry.id!="keyboard:%d" % player:continue
			option.add_item("键盘" if entry.id.begins_with("keyboard:") else entry.label)
			option.set_item_metadata(option.item_count-1,entry.id)
			if entry.id==app.devices[player]:option.select(option.item_count-1)
		if not app.router.connected(app.devices[player]):
			option.add_item("手柄已断开")
			option.set_item_metadata(option.item_count-1,app.devices[player])
			option.select(option.item_count-1)

func _change_controller(player: int,index: int) -> void:
	var device: String=control_options[player].get_item_metadata(index)
	if device==app.devices[1-player]:
		notice.text="该控制器已由另一位玩家使用。";refresh_controllers();return
	app.devices[player]=device
	app._reset_inputs()
	app.refresh_input_hints()
	notice.text="控制方式已切换"
