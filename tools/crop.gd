extends SceneTree
## Dev: crops a region of a capture and upscales it, for checking fine UI fit.
## CROP="x,y,w,h" SRC=<path> OUT=<path> SCALE=3
func _init() -> void:
	var src := OS.get_environment("SRC")
	var img := Image.load_from_file(src)
	var p := OS.get_environment("CROP").split(",")
	var r := Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
	var out := img.get_region(r)
	var k := int(OS.get_environment("SCALE")) if OS.get_environment("SCALE") != "" else 3
	out.resize(r.size.x * k, r.size.y * k, Image.INTERPOLATE_NEAREST)
	out.save_png(OS.get_environment("OUT"))
	print("CROP saved ", OS.get_environment("OUT"))
	quit()
