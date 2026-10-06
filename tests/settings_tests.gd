extends SceneTree
const Main=preload("res://scenes/main.tscn")
const Settings=preload("res://scripts/game_settings.gd")
const Router=preload("res://scripts/input_router.gd")
const OUT="res://artifacts/menu-settings"
class VirtualRouter extends Router:
	var present:=true
	func connected(device: String) -> bool:
		return present if device.begins_with("pad:") else super.connected(device)
	func sample(device: String) -> Dictionary:
		return {"x":0,"y":0,"buttons":0} if device.begins_with("pad:") else super.sample(device)
	func available_devices() -> Array[Dictionary]:
		var devices: Array[Dictionary]=super.available_devices().filter(func(entry: Dictionary): return entry.id.begins_with("keyboard:"))
		if present:
			devices.append({"id":"pad:98","label":"Test P1"})
			devices.append({"id":"pad:99","label":"Test P2"})
		return devices
var game: Node
var passed:=0
var failures: Array[String]=[]
func _initialize() -> void:_run.call_deferred()
func check(ok: bool,label: String) -> void:
	if ok:passed+=1
	else:failures.append(label)
func _key(code: int) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=true
	Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
	event=event.duplicate();event.pressed=false
	Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func _pad(button: int) -> void:
	var event:=InputEventJoypadButton.new()
	event.device=98;event.button_index=button;event.pressed=true
	Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
	event=event.duplicate();event.pressed=false
	Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func click(id: String) -> void:game.gui.actions[id].pressed.emit()
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var config=Settings.new()
	config.path=OUT+"/settings-test.cfg"
	config.keymaps=Router.KEYS.duplicate(true);config.muted=false;config.volume=1
	config.save_config()
	game=Main.instantiate();game.settings.path=config.path
	root.add_child(game);game.set_physics_process(false)
	await process_frame
	check(game.gui.actions.has("settings") and not game.gui.actions.has("sound"),"title exposes settings instead of direct sound toggle")
	check(game.gui.actions.help.text=="帮助","help is a first-level menu")
	check(Router.current_keys(0).slice(4)==[KEY_U,KEY_I,KEY_J,KEY_K],"P1 UIJK")
	check(Router.current_keys(1).slice(4)==[KEY_KP_5,KEY_KP_6,KEY_KP_2,KEY_KP_3],"P2 physical numpad 5623")
	await _key(KEY_S)
	check(game.gui.actions.mode_local.has_focus(),"mapped down moves native menu focus")
	await _key(KEY_W)
	await _key(KEY_U)
	check(game.screen=="setup" and game.mode=="cpu","mapped U confirms title mode")
	check(not game.gui.actions.has("devices"),"character selection removes device action")
	await _key(KEY_I)
	check(game.screen=="title","mapped I returns from selection")
	click("settings")
	check(game.screen=="settings","settings opens from title")
	game.gui.actions.audio_volume.value=37
	game.gui.actions.audio_mute.button_pressed=true
	check(is_equal_approx(game.sound.volume,0.37) and game.sound.muted,"audio controls apply immediately")
	var loaded=Settings.new();loaded.path=config.path;loaded.load_config()
	check(loaded.muted and is_equal_approx(loaded.volume,0.37),"audio settings persisted")
	await _key(KEY_F2)
	loaded.load_config()
	check(not game.sound.muted and not game.gui.actions.audio_mute.button_pressed and not loaded.muted,"F2 updates audio checkbox and persistent mute")
	game.sound.play("select",0.5)
	var voice: AudioStreamPlayer=game.sound.voices[(game.sound.cursor-1)%game.sound.voices.size()]
	check(is_equal_approx(voice.volume_db,-17.0+linear_to_db(0.5*0.37)),"cue gain and master volume combine")
	game.gui.actions.audio_volume.value=20
	check(is_equal_approx(voice.volume_db,-17.0+linear_to_db(0.5*0.2)),"master slider updates existing voices")
	game.gui.actions.audio_volume.value=0
	check(voice.volume_db<=-100,"zero volume silences existing voice")
	game.gui.actions.audio_volume.value=37
	await _key(KEY_F2)
	game.gui.actions.audio_volume.grab_focus()
	await _key(KEY_D)
	check(game.settings.volume>0.37,"mapped keyboard right adjusts native volume slider")
	game.gui.actions.audio_volume.value=37
	game.gui.actions.audio_mute.grab_focus()
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(game.gui.actions.audio_volume.has_focus(),"gamepad navigates to volume slider")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	check(game.settings.volume>0.37,"gamepad adjusts volume")
	game.gui.actions.key_0_4.grab_focus()
	await _pad(JOY_BUTTON_A)
	check(game.gui.settings_panel.waiting_player==0,"gamepad opens remapping capture")
	await _pad(JOY_BUTTON_B)
	check(game.gui.settings_panel.waiting_player<0 and game.screen=="settings","gamepad cancels capture without exiting settings")
	click("key_0_4")
	await _key(KEY_R)
	check(Router.current_keys(0)[4]==KEY_R and game.settings.keymaps[0][4]==KEY_R,"physical key rebind updates live map")
	check(game.gui.settings_panel.waiting_player<0,"capture ends after valid bind")
	click("key_1_4")
	await _key(KEY_R)
	check(game.settings.keymaps[1][4]==KEY_KP_5 and game.gui.settings_panel.waiting_player==1,"cross-player duplicate refused")
	await _key(KEY_ESCAPE)
	check(game.screen=="settings" and game.gui.settings_panel.waiting_player<0,"Escape cancels key capture without closing settings")
	click("key_0_5")
	await _key(KEY_F2)
	check(game.settings.keymaps[0][5]==KEY_I and game.sound.muted,"reserved hotkey does not trigger during capture")
	await _key(KEY_ESCAPE)
	loaded.load_config()
	check(loaded.keymaps[0][4]==KEY_R,"key binding persists in config")
	check(Router.motion_hints("keyboard:0",1)[0].contains("R / J"),"training hints follow rebinding")
	click("settings_back")
	await _key(KEY_R)
	check(game.screen=="setup","rebound confirmation works outside settings")
	await _key(KEY_R);await _key(KEY_R)
	check(game.screen=="stage" and not game.gui.actions.has("devices"),"both picks lock and stage has no device action")
	await _key(KEY_R)
	check(game.screen=="battle","rebound keyboard completes entire menu flow")
	game.set_paused(true)
	check(game.gui.actions.has("settings"),"pause exposes settings")
	var before: Dictionary=game.combat.snapshot()
	click("settings")
	for n in range(30):game._physics_process(1.0/60)
	check(game.combat.snapshot()==before and game.paused,"settings preserves frozen combat")
	click("defaults_p1")
	check(Router.current_keys(0)==Router.KEYS[0],"restore P1 defaults")
	click("key_1_7");await _key(KEY_KP_1)
	check(Router.current_keys(1)[7]==KEY_KP_1,"P2 can rebind its own keys")
	click("defaults_all")
	check(Router.current_keys(0)==Router.KEYS[0] and Router.current_keys(1)==Router.KEYS[1],"restore both defaults")
	click("settings_back")
	check(game.screen=="battle" and game.paused and game.gui.actions.has("resume"),"settings returns to pause, never resumes automatically")
	click("resume")
	check(not game.paused,"manual resume works")
	await _controller_recovery()
	for player in range(2):
		for action in range(4):
			var event:=InputEventKey.new();event.physical_keycode=Router.KEYS[player][action+4];event.pressed=true
			Input.parse_input_event(event);Input.flush_buffered_events()
			check(game.router.sample("keyboard:%d" % player).buttons==1<<action,"physical default isolated P%d %d" % [player+1,action])
			check(game.router.sample("keyboard:%d" % [1-player]).buttons==0,"other keyboard remains neutral")
			event=event.duplicate();event.pressed=false
			Input.parse_input_event(event);Input.flush_buffered_events()
	var top_row:=InputEventKey.new();top_row.physical_keycode=KEY_5;top_row.pressed=true
	Input.parse_input_event(top_row);Input.flush_buffered_events()
	check(game.router.sample("keyboard:1").buttons==0,"number-row 5 cannot impersonate keypad 5")
	top_row=top_row.duplicate();top_row.pressed=false;Input.parse_input_event(top_row);Input.flush_buffered_events()
	# Upgrade only untouched legacy defaults and keep player-authored layouts.
	var legacy:=ConfigFile.new()
	for player in range(2): legacy.set_value("keyboard", "p%d" % [player+1], Settings.LEGACY_KEYS[player])
	legacy.set_value("audio", "muted", true)
	legacy.set_value("audio", "volume", 0.42)
	legacy.save(OUT+"/legacy.cfg")
	loaded.path=OUT+"/legacy.cfg";loaded.load_config()
	check(loaded.keymaps==Router.KEYS and loaded.muted and is_equal_approx(loaded.volume,0.42), "legacy default upgrade preserves audio")
	loaded.save_config();loaded.load_config()
	check(loaded.keymaps==Router.KEYS, "upgraded defaults survive save and reload")
	var custom: Array=Settings.LEGACY_KEYS.duplicate(true)
	custom[0][4]=KEY_R
	legacy.set_value("keyboard", "p1", custom[0]);legacy.save(loaded.path);loaded.load_config()
	check(loaded.keymaps==custom, "custom legacy layout remains untouched")
	loaded.keymaps=Settings.LEGACY_KEYS.duplicate(true)
	loaded.save_config();loaded.load_config()
	check(loaded.keymaps==Settings.LEGACY_KEYS, "explicitly saved old keys remain selectable after upgrade")
	# Malformed persisted settings cannot create duplicate or reserved bindings.
	var file:=ConfigFile.new()
	file.set_value("keyboard","p1",[KEY_ESCAPE,KEY_D,KEY_S,KEY_W,KEY_U,KEY_I,KEY_J,KEY_K])
	file.save(OUT+"/invalid.cfg")
	loaded.path=OUT+"/invalid.cfg";loaded.load_config()
	check(loaded.keymaps==Router.KEYS,"invalid saved bindings fall back to complete defaults")
	for screen_name: String in ["title","settings","setup","pause"]:
		if screen_name=="title":game.show_title()
		elif screen_name=="settings":game.show_settings()
		elif screen_name=="setup":game.choose_mode("local")
		else:game.start_match();game.set_paused(true)
		await process_frame
		for node in game.gui.get_children():
			if node is Control:
				var rect: Rect2=node.get_rect()
				check(rect.end.x<=1281 and rect.end.y<=721,"control fits screen: "+screen_name+"/"+str(node.name))
	game.queue_free();await process_frame
	# Restore test-local defaults for repeatability; never write the player's file.
	config.keymaps=Router.KEYS.duplicate(true);config.muted=false;config.volume=1;config.save_config()
	for failure in failures:printerr("FAIL: ",failure)
	print("SETTINGS TESTS: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _controller_recovery() -> void:
	var previous=game.router
	var virtual:=VirtualRouter.new()
	game.router=virtual;game.mode="local"
	game.devices.assign(["pad:98","pad:99"])
	game.set_paused(true);game.show_settings()
	var before: Dictionary=game.combat.snapshot()
	var panel=game.gui.settings_panel
	var p2: OptionButton=panel.control_options[1]
	var duplicate_index: int=-1
	for i in range(p2.item_count):
		if p2.get_item_metadata(i)=="pad:98":duplicate_index=i
	p2.item_selected.emit(duplicate_index)
	check(game.devices==["pad:98","pad:99"],"controller cannot be assigned to both players")
	virtual.present=false;game._on_joy_connection(98,false)
	for player in range(2):
		var option: OptionButton=panel.control_options[player]
		check(option.get_item_metadata(option.selected)==game.devices[player] and option.item_count==2,"settings retains disconnected device and offers keyboard")
	game.close_settings()
	game.set_paused(false)
	check(game.paused,"cannot resume while required controllers are disconnected")
	game.show_settings();panel=game.gui.settings_panel
	for player in range(2):panel.control_options[player].item_selected.emit(0)
	check(game.devices==["keyboard:0","keyboard:1"],"both disconnected controllers can switch to keyboard from settings")
	game.close_settings()
	check(game.paused and game.combat.snapshot()==before,"disconnect recovery keeps combat state frozen")
	click("resume")
	check(not game.paused,"keyboard fallback allows manual resume")
	game.router=previous
	await process_frame
