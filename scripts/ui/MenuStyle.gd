class_name MenuStyle
## Shared look for menu buttons (title, New Game page, Load Game, pause and
## end-of-match menus, Account and Options pop-ups) so every menu matches.

const BUTTON_SIZE := Vector2(320, 64)
const FONT_SIZE := 26

static func button(b: Button) -> void:
	b.custom_minimum_size = Vector2(maxf(b.custom_minimum_size.x, BUTTON_SIZE.x), BUTTON_SIZE.y)
	b.add_theme_font_size_override("font_size", FONT_SIZE)
