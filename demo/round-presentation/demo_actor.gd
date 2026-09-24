extends Node2D
var visual: Resource
var clip: String = ""
var frame_index: int = 0
var facing: int = 1
var element: String = ""
var element_progress: float = -1.0

func set_pose(source: Resource, motion: String, ticks: float, direction: int) -> void:
	visual = source
	clip = motion
	facing = direction
	if visual.frames != null and visual.frames.has_animation(clip):
		frame_index = mini(visual.frames.get_frame_count(clip) - 1, int(maxf(0,ticks) * visual.frames.get_animation_speed(clip) / 60.0))
	else:
		frame_index = 0
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, Vector2(18, 3))
	draw_circle(Vector2.ZERO, 1, Color(0.02,0.025,0.045,0.45))
	draw_set_transform(Vector2.ZERO)
	if visual == null or visual.frames == null or not visual.frames.has_animation(clip):
		return
	var texture: Texture2D = visual.frames.get_frame_texture(clip,frame_index)
	var factor: float = visual.canonical_height / visual.source_height
	draw_set_transform(Vector2.ZERO,0,Vector2(facing,1))
	draw_texture_rect(texture,Rect2(-visual.feet_anchor*factor,texture.get_size()*factor),false)
	if element_progress >= 0 and element_progress <= 1:
		var fade := sin(element_progress * PI)
		if element == "water":
			for layer in range(3):
				var points := PackedVector2Array()
				for i in range(33):
					var a := float(i)/32*TAU + element_progress*TAU
					points.append(Vector2(cos(a)*(28+layer*3), sin(a)*5-3-layer))
				draw_polyline(points,Color(0.35,0.85,0.96,fade*(0.6-layer*0.15)),1.2,true)
		elif element == "fire":
			var points := PackedVector2Array()
			for i in range(25):
				var a := -1.8+float(i)/24*2.4
				points.append(Vector2(9,-31)+Vector2(cos(a)*36,sin(a)*30))
			draw_polyline(points,Color(1,0.37,0.13,fade*0.65),2,true)
			draw_polyline(points,Color(1,0.87,0.46,fade*0.8),0.65,true)
		elif element == "thunder":
			for side in [-1,1]:
				var points := PackedVector2Array()
				for i in range(7):
					points.append(Vector2(side*(14+sin(i*13.0)*5),-i*9))
				draw_polyline(points,Color(0.5,0.8,1,fade*0.75),2,true)
				draw_polyline(points,Color(1,0.94,0.6,fade),0.65,true)
	draw_set_transform(Vector2.ZERO)
