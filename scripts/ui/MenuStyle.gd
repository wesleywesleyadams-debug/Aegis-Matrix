class_name MenuStyle
## Shared look for menu buttons (title, New Game page, Load Game, pause and
## end-of-match menus, Account and Options pop-ups) so every menu matches.

const BUTTON_SIZE := Vector2(320, 64)
const FONT_SIZE := 26

static func button(b: Button) -> void:
	b.custom_minimum_size = Vector2(maxf(b.custom_minimum_size.x, BUTTON_SIZE.x), BUTTON_SIZE.y)
	b.add_theme_font_size_override("font_size", FONT_SIZE)

## The red of a button that leaves: the title screen's Quit, and Quit to
## Title in the pause and end-of-match menus. One definition, so every exit in
## the game looks like the same kind of thing.
static func leave(b: Button) -> void:
	tint(b, [Color("5a1a1a"), Color("7a2424"), Color("3a1010")], Color("ff6a6a"), Color("ffd6d6"))

## Recolours a menu button: bg for normal / hover / pressed, then its border
## and label colours.
static func tint(b: Button, bg: Array, border: Color, font: Color) -> void:
	for i in 3:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg[i]
		sb.border_color = border
		sb.set_border_width_all(2)
		sb.set_content_margin_all(12)
		b.add_theme_stylebox_override(["normal", "hover", "pressed"][i], sb)
	b.add_theme_color_override("font_color", font)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
