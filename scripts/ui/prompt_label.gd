extends Label
## Label whose hint text renders as keycap prompts (see prompt_bar.gd). The
## app keeps writing plain hint or warning text and tinting via `modulate`.
const PromptBar = preload("res://scripts/ui/prompt_bar.gd")
const Kit = preload("res://scripts/ui/kit.gd")
var alignment: int = 1

func _ready() -> void:
	clip_text = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for state in ["font_color", "font_shadow_color", "font_outline_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)

func _draw() -> void:
	if not text.is_empty():
		PromptBar.paint(self, Rect2(Vector2.ZERO, size), text, get_theme_font("font"), Kit.PAPER_DIM, alignment)
