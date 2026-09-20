extends Node2D
const StageView = preload("res://scripts/presentation/stage_view.gd")
const FighterView = preload("res://scripts/presentation/fighter_view.gd")
const EffectsView = preload("res://scripts/presentation/effects_view.gd")
const HUDView = preload("res://scripts/presentation/hud_view.gd")
const Camera = preload("res://scripts/presentation/duel_camera.gd")
var combat: RefCounted
var catalog: RefCounted
var screen: String = "title"
var characters: Array[String] = ["tanjiro", "zenitsu"]
var debug_boxes: bool = false
var cpu: bool = true
var paused: bool = false
var input_hints: Array[String] = ["WASD / FG · VB", "↑↓←→ / JK · NM"]
var camera := Camera.new()
var stage: Node2D
var effects: Node2D
var hud: Control
var fighters: Array[Node2D] = []
var shadow_layer: Node2D
var debug_layer: Node2D
var foreground_layer: Node2D
var time: float = 0

func _ready() -> void:
	stage = StageView.new()
	stage.visual = catalog.stage
	stage.camera = camera
	add_child(stage)
	shadow_layer = Node2D.new()
	shadow_layer.z_index = 1
	shadow_layer.draw.connect(_draw_shadows)
	add_child(shadow_layer)
	for i in range(2):
		var actor := FighterView.new()
		actor.combat = combat
		actor.player_accent = Color("75cbd6") if i == 0 else Color("f2c379")
		actor.z_index = 2
		add_child(actor)
		fighters.append(actor)
	effects = EffectsView.new()
	effects.combat = combat
	effects.camera = camera
	effects.z_index = 10
	add_child(effects)
	foreground_layer = Node2D.new()
	foreground_layer.draw.connect(func(): stage.draw_foreground(foreground_layer))
	add_child(foreground_layer)
	hud = HUDView.new()
	hud.combat = combat
	hud.catalog = catalog
	hud.size = Vector2(1280, 720)
	hud.z_index = 30
	add_child(hud)
	debug_layer = Node2D.new()
	debug_layer.z_index = 40
	debug_layer.draw.connect(_draw_debug)
	add_child(debug_layer)

func _process(delta: float) -> void:
	if not paused:
		time += delta
	var battle: bool = screen == "battle" and combat.fighters.size() == 2
	stage.menu_mode = not battle
	stage.freeze = paused
	hud.visible = screen == "battle"
	effects.visible = battle
	effects.freeze = paused or combat.super_freeze > 0
	shadow_layer.visible = battle
	debug_layer.visible = battle and debug_boxes
	for i in range(2):
		fighters[i].visible = battle
	if not battle:
		return
	for i in range(2):
		var f = combat.fighters[i]
		fighters[i].fighter = f
		fighters[i].visual = catalog.characters[f.character]
		fighters[i].sync(delta, paused or combat.hitstop > 0 or combat.super_freeze > 0)
	if not paused:
		camera.update(combat.fighters, delta)
		camera.shake = Vector2(sin(time * 79), cos(time * 93)) * effects.trauma * 11
	stage.sync_camera()
	for i in range(2):
		var f = combat.fighters[i]
		fighters[i].z_index = 3 if f.throw_role == "victim" and f.throw_frame >= 8 else 2
		fighters[i].position = camera.point(Vector2(f.x, f.y))
		fighters[i].scale = Vector2.ONE * camera.zoom
	hud.cpu = cpu
	hud.frozen = paused
	hud.input_hints = input_hints
	shadow_layer.queue_redraw()
	debug_layer.queue_redraw()

func reset_effects() -> void:
	for actor in fighters:
		actor.reset_pose()
	if effects != null:
		effects.reset_effects()
		hud.reset_effects()
	if combat.fighters.size() == 2:
		camera.reset(combat.fighters)

func consume(events: Array) -> void:
	for i in range(fighters.size()):
		fighters[i].consume(events, i)
	effects.consume(events)
	hud.consume(events)

func _draw_shadows() -> void:
	for f in combat.fighters:
		var at := camera.point(Vector2(f.x, 286))
		var width := 18.0 * camera.zoom * clampf(1 - (286 - f.y) / 230.0, 0.45, 1)
		shadow_layer.draw_set_transform(at, 0, Vector2(width, 5))
		shadow_layer.draw_circle(Vector2.ZERO, 1, Color(0.01, 0.02, 0.04, 0.46), true, -1, true)
	shadow_layer.draw_set_transform(Vector2.ZERO)

func _draw_debug() -> void:
	for projectile in combat.projectiles:
		debug_layer.draw_rect(camera.rect(combat.projectile_box(projectile)), Color(1, 0.7, 0.2), false, 1.5)
	for f in combat.fighters:
		for pair in [[f.hurtbox(), Color(0.3, 0.8, 1, 0.7)], [f.hitbox(), Color(1, 0.3, 0.2, 0.8)], [f.pushbox(), Color(0.3, 1, 0.5, 0.6)]]:
			if pair[0].has_area():
				debug_layer.draw_rect(camera.rect(pair[0]), pair[1], false, 1.5)
		var info := "P%d %s %s %d" % [f.slot + 1, f.state, f.move.id if f.move != null else "-", f.move_frame]
		debug_layer.draw_string(catalog.body_font, camera.point(Vector2(f.x - 24, f.y - 82)), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
