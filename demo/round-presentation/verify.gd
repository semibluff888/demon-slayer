extends SceneTree
const Demo = preload("res://demo/round-presentation/demo.gd")
var passed := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if ok: passed+=1
	else: failures.append(label)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var demo := Demo.new()
	root.add_child(demo)
	demo.set_process(false)
	demo.sound.muted=true
	for cid in ["tanjiro","zenitsu"]:
		demo.character=cid
		for v in range(4):
			demo.variant=v
			for clip in ["intro","victory","defeat"]:
				demo.mode=clip
				var key: String="%s_%s" % [char(97+v),clip]
				var visual: Resource=demo.visuals[cid]
				var count := 12 if clip=="defeat" else 18
				check(visual.frames.has_animation(key) and visual.frames.get_frame_count(key)==count, "complete authored clip "+cid+" "+key)
				for n in range(count):
					var tex: Texture2D=visual.frames.get_frame_texture(key,n)
					check(tex!=null and tex.get_size()==Vector2(1024,640),"frame retains shared anchor canvas")
				for mirror in [false,true]:
					demo.mirrored=mirror
					demo.elapsed=210 if clip=="defeat" else 120
					demo.refresh()
					check(demo.actors[0].clip==key and demo.actors[0].frame_index==count-1,"clip reaches and holds last frame")
					check(demo.actors[0].facing==(-1 if mirror else 1),"mirror follows chosen facing")
	demo.mode="full"
	demo.elapsed=60
	demo.playing=false
	demo._process(0.5)
	check(demo.elapsed==60,"pause holds timeline")
	demo.playing=true
	demo.playback_speed=0.25
	demo._process(1)
	check(demo.elapsed==75,"quarter-speed advances correct amount")
	var character_picker: OptionButton=demo.controls.get_child(0)
	character_picker.item_selected.emit(1)
	check(demo.character=="zenitsu" and demo.elapsed==0,"character selector resets playback")
	demo.variant_picker.item_selected.emit(2)
	check(demo.variant==2 and demo.heading.text.contains("雷鸣"),"variant selector updates selected motion")
	demo.scrub.value=35
	check(demo.elapsed==35 and not demo.playing,"scrubbing selects and holds exact pose")
	demo.queue_free()
	await process_frame
	for failure in failures: printerr("FAIL: ",failure)
	print("ROUND DEMO TESTS: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)
