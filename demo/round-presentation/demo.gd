extends Node2D
const Flow = preload("res://scripts/round_flow.gd")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
const Visual = preload("res://scripts/presentation/character_visual.gd")
const Stage = preload("res://scripts/presentation/stage_view.gd")
const Camera = preload("res://scripts/presentation/duel_camera.gd")
const Banner = preload("res://scripts/presentation/round_banner.gd")
const Actor = preload("res://demo/round-presentation/demo_actor.gd")
const Sound = preload("res://scripts/audio.gd")
const FULL_DURATION := 762.0
const NAMES := {"tanjiro":["礼仪","水息","火意","守护"],"zenitsu":["惊怯","入静","雷鸣","梦醒"]}
const NOTES := {
	"tanjiro":["整理衣领，深呼吸后横刀立势。胜利收刀致意；失衡后单膝缓冲、侧倒。",
		"低位蓄息，水纹随举刀舒展。胜利振刀散水；滑退后背部着地。",
		"抬眼提刀，短促火弧映出决心。胜利沉刀站定；半跪后力竭伏地。",
		"按胸定神，向前踏步守护。胜利温柔致意；撑地失力后侧卧。"],
	"zenitsu":["紧张张望后鼓起勇气。胜利拍胸松气；踉跄两步后侧倒。",
		"闭眼凝神，缓缓进入居合架势。胜利从容纳刀；跪落后前伏。",
		"压身蓄势，短闪拔刀。胜利利落归鞘；击退离地后横身落地。",
		"困倦点头后突然警觉。胜利微睁眼、松肩收刀；摇晃失力后前倒。"]}
var catalog := Catalog.new()
var visuals: Dictionary = {}
var character: String = "tanjiro"
var variant: int = 0
var mode: String = "full"
var elapsed: float = 0
var playback_speed: float = 1.0
var playing: bool = true
var mirrored: bool = false
var capture_mode: bool = false
var stage: Node2D
var banner: Control
var actors: Array[Node2D] = []
var controls: Control
var heading: Label
var note: Label
var status: Label
var scrub: HSlider
var variant_picker: OptionButton
var sound: Node
var last_cue: String = ""
var ui_font: Font

func _ready() -> void:
	for cid in ["tanjiro","zenitsu"]:
		var visual := Visual.new()
		visual.character_id = cid
		visual.asset_directory = "res://demo/round-presentation/assets/characters/%s/" % cid
		visual.load_local_assets()
		visuals[cid] = visual
	stage = Stage.new()
	stage.visual = catalog.stage
	stage.camera = Camera.new()
	add_child(stage)
	for n in range(2):
		var actor := Actor.new()
		actor.scale = Vector2.ONE*3
		actor.position = Vector2(400 if n==0 else 880,594)
		actor.z_index = 5
		add_child(actor)
		actors.append(actor)
	banner = Banner.new()
	banner.title_font = catalog.title_font
	banner.body_font = catalog.body_font
	banner.z_index = 10
	add_child(banner)
	sound = Sound.new()
	add_child(sound)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
	ui_font = font
	_build_ui()
	refresh()

func _label(text: String, pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_override("font",ui_font)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.add_theme_color_override("font_outline_color",Color(0.02,0.03,0.06,0.9))
	label.add_theme_constant_override("outline_size",4)
	label.z_index = 15
	add_child(label)
	return label

func _picker(items: Array, x: float, width: float) -> OptionButton:
	var picker := OptionButton.new()
	picker.position = Vector2(x,78)
	picker.size = Vector2(width,38)
	picker.add_theme_font_override("font",ui_font)
	picker.add_theme_font_size_override("font_size",17)
	for item: String in items: picker.add_item(item)
	controls.add_child(picker)
	return picker

func _button(text: String, x: float, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.position = Vector2(x,78)
	button.size = Vector2(94,38)
	button.add_theme_font_override("font",ui_font)
	button.add_theme_font_size_override("font_size",17)
	button.pressed.connect(action)
	controls.add_child(button)

func _build_ui() -> void:
	heading = _label("",Vector2(34,20),30,Color("f3ead6"))
	note = _label("",Vector2(36,137),17,Color("ded5c1"))
	status = _label("",Vector2(36,643),20,Color("e8c789"))
	controls = Control.new()
	controls.z_index = 20
	add_child(controls)
	var chars := _picker(["灶门炭治郎","我妻善逸"],34,170)
	chars.item_selected.connect(func(i: int):
		character = "tanjiro" if i==0 else "zenitsu"
		_update_variants()
		replay())
	variant_picker = _picker([],218,178)
	_update_variants()
	variant_picker.item_selected.connect(func(i: int): variant=i; replay())
	var segment := _picker(["完整流程","开场表演","胜利动作","落败动作"],410,164)
	segment.item_selected.connect(func(i: int): mode=["full","intro","victory","defeat"][i]; replay())
	var speed := _picker(["1 倍速","0.5 倍速","0.25 倍速"],588,142)
	speed.item_selected.connect(func(i: int): playback_speed=[1.0,0.5,0.25][i])
	_button("左右镜像",748,func(): mirrored=not mirrored; refresh())
	_button("暂停/播放",856,func(): playing=not playing; stage.freeze=not playing)
	_button("重播",964,replay)
	_button("退出",1072,func(): get_tree().quit())
	scrub = HSlider.new()
	scrub.position=Vector2(34,687)
	scrub.size=Vector2(1212,20)
	scrub.step=1
	scrub.value_changed.connect(func(value: float): elapsed=value; playing=false; refresh())
	controls.add_child(scrub)

func _update_variants() -> void:
	variant_picker.clear()
	for i in range(4): variant_picker.add_item("%s · %s" % [char(65+i),NAMES[character][i]])
	variant_picker.select(variant)

func replay() -> void:
	elapsed=0
	playing=true
	last_cue=""
	sound.reset_audio()
	refresh()

func duration() -> float:
	return FULL_DURATION if mode=="full" else (Flow.OUTRO if mode=="defeat" else Flow.ACTOR_INTRO)

func _process(delta: float) -> void:
	if playing:
		elapsed=minf(duration(),elapsed+delta*60*playback_speed)
		if elapsed>=duration(): playing=false
	stage.freeze=not playing
	refresh()

func pose(slot: int, cid: String, clip: String, ticks: float, demo_asset: bool = true) -> void:
	var side := (1-slot) if mirrored else slot
	var gap := 480.0
	if mode=="full" and elapsed>=240:
		gap = lerpf(480,176,clampf((elapsed-240)/36.0,0,1))
	actors[slot].position = Vector2(640+(-gap/2 if side==0 else gap/2),594) if mode=="full" else Vector2(640,594)
	actors[slot].element=""
	actors[slot].element_progress=-1
	actors[slot].set_pose(visuals[cid] if demo_asset else catalog.characters[cid],
		("%s_%s" % [char(97+variant),clip]) if demo_asset else clip,ticks,1 if side==0 else -1)
	if demo_asset and clip in ["intro","victory"]:
		actors[slot].element="water" if cid=="tanjiro" and variant==1 else ("fire" if cid=="tanjiro" and variant==2 else ("thunder" if cid=="zenitsu" and variant==2 else ""))
		actors[slot].element_progress=clampf((ticks-20)/68,0,1)

func _outcome(tick: float, loser: int) -> void:
	var other := "zenitsu" if character=="tanjiro" else "tanjiro"
	var ids := [character,other]
	var motion := Flow.motion_ticks(int(tick),true)
	for slot in range(2):
		if slot==loser:
			pose(slot,ids[slot],"defeat",motion)
		elif tick>=Flow.RESULT_AT:
			pose(slot,ids[slot],"victory",tick-Flow.RESULT_AT)
		else:
			pose(slot,ids[slot],"intro",120)
	if tick>=Flow.RESULT_AT:
		banner.cue={"text":"P%d WINS" % (2 if loser==0 else 1),"subtitle":catalog.characters[ids[1-loser]].display_name,"age":tick-Flow.RESULT_AT,"duration":Flow.RESULT}
	elif tick>=Flow.FREEZE:
		banner.cue={"text":"K.O.","age":tick-Flow.FREEZE,"duration":Flow.RESULT_AT-Flow.FREEZE}
	else:
		banner.cue={}
	status.text="落败 · KO 定格 / 慢放 / 倒地保持" if loser==0 else "获胜 · 终结慢放 / 收尾 / 胜利表演"

func refresh() -> void:
	if heading==null: return
	var other := "zenitsu" if character=="tanjiro" else "tanjiro"
	heading.text="%s   /   %s · %s" % [catalog.characters[character].display_name,char(65+variant),NAMES[character][variant]]
	note.text=NOTES[character][variant]
	controls.visible=not capture_mode
	banner.cue={}
	for actor in actors: actor.visible=true
	if mode=="full":
		if elapsed<120:
			pose(0,character,"intro",elapsed)
			pose(1,other,"intro",elapsed)
			status.text="开场 · 双方同时表演"
		elif elapsed<240:
			pose(0,character,"intro",120)
			pose(1,other,"intro",120)
			var t := elapsed-120
			if t<Flow.ROUND: banner.cue={"text":"ROUND 1","age":t,"duration":Flow.ROUND}
			elif t<Flow.INTRO: banner.cue={"text":"READY","age":t-Flow.ROUND,"duration":Flow.READY}
			else: banner.cue={"text":"GO!","age":t-Flow.INTRO,"duration":Flow.GO}
			status.text="ROUND → READY → GO!  ·  GO! 首帧开放操作"
		elif elapsed<312:
			pose(0,character,"stand_heavy",fmod(elapsed-240,36),false)
			pose(1,other,"guard",0,false)
			status.text="短交手 · 预览接入对战后的节奏"
		elif elapsed<522:
			_outcome(elapsed-312,1)
		elif elapsed<552:
			pose(0,character,"intro",120)
			pose(1,other,"intro",120)
			status.text="接下来 · 当前角色落败方案"
		else:
			_outcome(minf(elapsed-552,209),0)
	else:
		actors[1].visible=false
		if mode=="defeat":
			pose(0,character,"defeat",Flow.motion_ticks(int(elapsed),true))
			status.text="落败动作 · 含 0.1 秒定格与 0.5 秒慢放"
			if elapsed>=Flow.FREEZE and elapsed<Flow.RESULT_AT:
				banner.cue={"text":"K.O.","age":elapsed-Flow.FREEZE,"duration":Flow.RESULT_AT-Flow.FREEZE}
		else:
			pose(0,character,mode,elapsed)
			status.text="开场表演 · 2 秒" if mode=="intro" else "胜利动作 · 2 秒"
	var current: String=banner.cue.get("text","")
	if current!=last_cue and not current.is_empty() and playing and not capture_mode:
		sound.play("round_end" if current=="K.O." else ("fight" if current=="GO!" else "select"),0.65)
	last_cue=current
	banner.queue_redraw()
	scrub.max_value=duration()
	scrub.set_value_no_signal(elapsed)
