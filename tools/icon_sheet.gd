extends Node
## Renders every tech icon onto one sheet: OUT (default user://icons.png).
func _ready() -> void:
	var ids: Array = Defs.TECHS.keys()
	var cols := 12
	var sheet := Image.create(cols * (TechIcons.SIZE + 2), int(ceil(ids.size() / float(cols))) * (TechIcons.SIZE + 2), false, Image.FORMAT_RGBA8)
	for i in ids.size():
		var im: Image = TechIcons.icon(ids[i]).get_image()
		sheet.blit_rect(im, Rect2i(0, 0, TechIcons.SIZE, TechIcons.SIZE), Vector2i((i % cols) * (TechIcons.SIZE + 2), (i / cols) * (TechIcons.SIZE + 2)))
	sheet.save_png(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "user://icons.png")
	get_tree().quit()
