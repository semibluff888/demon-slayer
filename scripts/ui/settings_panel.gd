extends RefCounted
const Router = preload("res://scripts/input_router.gd")
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
	menu.rect(Rect2(0,0,1280,720),Color("09111f"))
	menu.slash(Rect2(718,0,562,720),Color("142337"),100)
	menu.label("游戏设置",Rect2(48,23,650,63),40,menu.PAPER,true)
	menu.label("即时生效 · 自动保存",Rect2(905,47,326,27),16,menu.MUTED,false,HORIZONTAL_ALIGNMENT_RIGHT)
	menu.panel(Rect2(48,113,1184,96))
	menu.label("声音",Rect2(70,135,110,43),23,menu.GOLD,true)
	var mute := CheckButton.new()
	mute.name = "audio_mute"
	mute.text = "静音"
	mute.position = Vector2(204,134)
	mute.size = Vector2(151,43)
	mute.button_pressed = app.settings.muted
	mute.toggled.connect(func(value: bool): app.settings.muted=value; _audio_changed())
	menu.add_child(mute)
	menu.actions.audio_mute = mute
	menu.label("音量",Rect2(400,141,75,34),18,menu.PAPER)
	var slider := HSlider.new()
	slider.name = "audio_volume"
	slider.position = Vector2(483,138)
	slider.size = Vector2(246,40)
	slider.min_value=0;slider.max_value=100;slider.step=1
	slider.value=roundi(app.settings.volume*100)
	menu.add_child(slider)
	menu.actions.audio_volume=slider
	volume_label=menu.label("%d%%" % slider.value,Rect2(748,140,95,32),22,menu.GOLD)
	slider.value_changed.connect(func(value: float): app.settings.volume=value/100.0; volume_label.text="%d%%" % value; _audio_changed())
	var cinematic := CheckButton.new()
	cinematic.name = "cinematic_enabled"
	cinematic.text = "必杀动画演出"
	cinematic.position = Vector2(884,127)
	cinematic.size = Vector2(308,43)
	cinematic.button_pressed = app.settings.cinematic_enabled
	cinematic.tooltip_text = "奥义 / MAX 命中后播放；关闭后沿用简化演出。"
	cinematic.toggled.connect(func(value: bool): app.settings.cinematic_enabled = value; _save())
	menu.add_child(cinematic)
	menu.actions.cinematic_enabled = cinematic
	menu.label("命中后播放 · 奥义 / MAX",Rect2(901,170,285,23),13,menu.MUTED)
	for player in range(2):
		var x := 48 + player*618
		menu.panel(Rect2(x,230,566,372))
		menu.label("P%d 键盘" % [player+1],Rect2(x+20,245,200,40),25,menu.PAPER,true)
		var option: OptionButton = menu.device_option("control_p%d" % [player+1],Rect2(x+239,247,305,36))
		option.tooltip_text="控制方式"
		control_options.append(option)
		option.item_selected.connect(func(index: int): _change_controller(player,index))
		for row in range(4):
			for column in range(2):
				var action: int = [3,2,0,1][row] if column==0 else row+4
				var left: int = x+20+column*276
				menu.label(["左","右","下","上","A","B","C","D"][action],Rect2(left,313+row*52,49,35),20,menu.GOLD)
				var id := "key_%d_%d" % [player,action]
				var key: Button = menu.button(id,Router.key_name(app.settings.keymaps[player][action]),Rect2(left+57,309+row*52,194,40),func(): _listen(player,action),false,false,18)
				key_buttons[id]=key
		menu.button("defaults_p%d" % [player+1],"恢复 P%d 默认" % [player+1],Rect2(x+20,541,226,39),func(): _restore(player),false,false,17)
	menu.button("defaults_all","恢复双方默认按键",Rect2(937,654,294,44),_restore_all,false,false,17)
	menu.button("settings_back","返回",Rect2(48,654,213,44),app.close_settings,true,true,20)
	notice=menu.label("点击按键后按新键；Esc 取消改键。P2 默认使用小键盘。",Rect2(51,613,1179,30),16,menu.MUTED)
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

func _save() -> void:
	var result: Error=app.settings.save_config()
	notice.text="已保存" if result==OK else app.settings.last_error
	notice.modulate=menu.MUTED if result==OK else Color("ff8197")

func _audio_changed() -> void:
	app.sound.set_levels(app.settings.muted,app.settings.volume)
	app.view.cinematic.sync_audio()
	_save()

func _listen(player: int, action: int) -> void:
	_cancel_listen()
	waiting_player=player;waiting_action=action
	var key: Button=key_buttons["key_%d_%d" % [player,action]]
	key.text="按下新按键…";key.selected=true;key.queue_redraw()
	notice.text="P%d · %s：按下新键，Esc 取消。" % [player+1,["左","右","下","上","A","B","C","D"][action]]

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

