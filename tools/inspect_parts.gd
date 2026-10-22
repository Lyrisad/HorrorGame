extends SceneTree
## Outil : détaille les sous-parties d'un modèle (transform + AABB).
## godot --headless --path . --script res://tools/inspect_parts.gd -- slug


func _init() -> void:
	for slug in OS.get_cmdline_user_args():
		var inst: Node3D = (load("res://assets/models/%s/%s_1k.gltf" % [slug, slug]) as PackedScene).instantiate()
		print("== ", slug)
		for n in inst.find_children("*", "Node3D", true, false):
			var mi := n as MeshInstance3D
			var xf := B._relative_xform(inst, n)
			var s := "  %-40s origin=(%.2f, %.2f, %.2f)" % [n.name, xf.origin.x, xf.origin.y, xf.origin.z]
			if mi != null:
				var b: AABB = xf * mi.get_aabb()
				s += "  aabb_min=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % [b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z]
			print(s)
		inst.free()
	quit()
