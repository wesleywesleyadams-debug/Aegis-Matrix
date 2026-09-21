extends SceneTree
## Composites every sprite in assets/pixel onto one upscaled sheet for review.
func _init() -> void:
	var names := (OS.get_environment("NAMES").split(",") as Array) if OS.get_environment("NAMES") != "" else ["ship_corvette","ship_destroyer","ship_cruiser","ship_miner","starbase","planet_terran","planet_desert","planet_ice","planet_lava","planet_gas","planet_moon","star","asteroid_0","asteroid_1","asteroid_big_0","debris_0","explosion","bolt_laser","bolt_torpedo","engine_flame","icon_minerals","icon_energy","icon_fleet"]
	var sheet := Image.create(1400, 900, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("0b0a1a"))
	var x := 8
	var y := 8
	var row_h := 0
	var scale := int(OS.get_environment("SCALE")) if OS.get_environment("SCALE") != "" else 3
	for n in names:
		var img := Image.load_from_file("res://assets/pixel/%s.png" % n)
		if FileAccess.file_exists("res://assets/pixel/%s_team.png" % n):
			var team := Image.load_from_file("res://assets/pixel/%s_team.png" % n)
			for ty in team.get_height():
				for tx in team.get_width():
					var c := team.get_pixel(tx, ty)
					if c.a > 0:
						img.set_pixel(tx, ty, Color(0.3, 0.7, 1.0) * c.r)
		img.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
		if x + img.get_width() > 1390:
			x = 8
			y += row_h + 8
			row_h = 0
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(x, y))
		x += img.get_width() + 8
		row_h = max(row_h, img.get_height())
	sheet.save_png("user://contact.png")
	print(ProjectSettings.globalize_path("user://contact.png"))
	quit()
