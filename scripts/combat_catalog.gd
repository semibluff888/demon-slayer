class_name CombatCatalog
extends RefCounted
const Definition = preload("res://scripts/character_definition.gd")
var characters: Dictionary = {}
var moves: Dictionary = {}

func _init() -> void:
	var files := ResourceLoader.list_directory("res://resources/characters")
	files.sort()
	for file in files:
		if not file.ends_with(".tres"):
			continue
		register(load("res://resources/characters/" + file))

func register(definition: Definition) -> void:
	assert(definition != null and not definition.id.is_empty())
	assert(not characters.has(definition.id), "Duplicate character ID")
	characters[definition.id] = definition
	for move in definition.all_moves():
		assert(not moves.has(move.id) or moves[move.id] == move, "Duplicate move ID")
		moves[move.id] = move
