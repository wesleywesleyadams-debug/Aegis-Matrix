extends SceneTree
func _init() -> void:
	for id in Defs.TECHS:
		var t: Dictionary = Defs.TECHS[id]
		var extra := ""
		for k in t:
			if not k in ["name", "group", "tier", "requires", "cost", "time", "effects", "desc"]:
				extra += " %s=%s" % [k, str(t[k])]
		print("%s | %s | %s | %s |%s" % [t["group"], t["name"], str(t["effects"]), t["desc"], extra])
	quit()
