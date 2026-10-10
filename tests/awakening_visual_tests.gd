extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Art = preload("res://scripts/presentation/visual_catalog.gd")
const Actor = preload("res://scripts/presentation/fighter_view.gd")
var passed := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failures.append(label); printerr("FAIL: ",label)
func _initialize() -> void:
	var art := Art.new()
	for cid in art.characters:
		var visual = art.characters[cid]
		check(visual.art_ready and visual.missing_clips().is_empty(),cid+" both forms are complete")
		var c := Combat.new()
		c.new_match(cid,cid); c.phase = "fight"
		var actors := [Actor.new(),Actor.new()]
		for i in range(2):
			actors[i].combat = c; actors[i].fighter = c.fighters[i]; actors[i].visual = visual
			actors[i].sync(0,false)
		var f = c.fighters[0]; var actor = actors[0]
		actor.clock_ticks = 39
		var count: int = visual.frames.get_frame_count("idle")
		f.awakening_ticks = 600
		f.awakening_duration = 600
		actor.sync(0,false)
		check(actor.clock_ticks == 39,cid+" changing form does not restart pose")
		check(visual.frames.get_frame_count("idle") == count,cid+" shared base atlas unchanged")
		check(actor._frames() != actors[1]._frames(),cid+" mirrors select atlases independently")
		for clip: String in visual.frames.get_animation_names():
			check(visual.awakening_frames.has_animation(clip),cid+" alternate clip "+clip)
			if not visual.awakening_frames.has_animation(clip):continue
			check(visual.frames.get_frame_count(clip) == visual.awakening_frames.get_frame_count(clip),cid+" matching frame count "+clip)
			for index in range(visual.awakening_frames.get_frame_count(clip)):
				var texture: Texture2D = visual.awakening_frames.get_frame_texture(clip,index)
				check(texture != null and texture is AtlasTexture and texture.atlas != null,cid+" loaded "+clip+"/"+str(index))
		var snapshot: Dictionary = c.snapshot()
		actor.sync(0.5,true)
		check(actor.clock_ticks == 39 and snapshot == c.snapshot(),cid+" pause freezes pose and cannot mutate combat")
		f.state = "hit"; f.stun = 10
		actor.sync(0,false)
		check(actor.form_active(),cid+" hit does not remove appearance")
		actor.clock_ticks = 7
		c._end_awakening(f); actor.sync(0,false)
		check(actor.clock_ticks == 7 and not actor.form_active(),cid+" expiry preserves reaction timing")
		f.stun = 0; f.meter = 100; f.awakening_ticks = 300; f.awakening_duration = 360
		c._begin_move(f, c.definition(f).motions.max); actor.sync(0, false)
		check(f.awakening_ticks == 0 and actor.form_active(), cid+" MAX retains launch form after consuming mode")
		check(actor._frames() == visual.awakening_frames, cid+" MAX uses awakened atlas")
		f.move = null; f.state = "idle"; actor.sync(0, false)
		check(not actor.form_active() and actor._frames() == visual.frames, cid+" MAX recovery returns to base atlas")
		f.meter = 100; f.awakening_ticks = 300; f.awakening_duration = 360
		c._begin_move(f, c.definition(f).motions.super); actor.sync(0, false)
		check(f.meter == 0 and f.awakening_ticks == 300 and actor.form_active(), cid+" enhanced super preserves mode and form")
		f.move = null; f.state = "idle"; actor.sync(0, false)
		check(actor.form_active(), cid+" enhanced super recovery retains active mode")
		f.meter = 100
		c._begin_move(f, c.definition(f).motions.super)
		c._end_awakening(f); actor.sync(0, false)
		check(actor.form_active(), cid+" enhanced super retains launch form if mode expires mid-move")
		f.move = null; f.state = "idle"; actor.sync(0, false)
		check(not actor.form_active(), cid+" expired super recovery restores base form")
		if cid == "nezuko":
			f.stun = 0; f.meter = 300
			c._begin_move(f,c.definition(f).motions.max); actor.sync(0,false)
			check(actor.form_active() and is_equal_approx(actor._pose_scale().x,1.15),"MAX uses same enlarged demon form")
			f.awakening_ticks = 300; f.awakening_duration = 360
			c._begin_move(f,c.definition(f).motions.max); actor.sync(0,false)
			check(is_equal_approx(actor._pose_scale().x,1.15),"MAX never double scales")
			f.move = null; f.state = "idle"; actor.sync(0,false)
			check(not actor.form_active(),"MAX ending restores ordinary form")
			f.hp = 0; actor.sync(0,false)
			check(not actor.form_active(),"KO returns to ordinary form")
		for item in actors:item.free()
	print("AWAKENING VISUAL: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)
