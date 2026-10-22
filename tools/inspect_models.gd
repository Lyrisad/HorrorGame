extends SceneTree
## Outil : affiche la taille (AABB) et la structure des modèles importés.
## godot --headless --path . --script res://tools/inspect_models.gd


func _init() -> void:
	var dir := DirAccess.open("res://assets/models")
	for slug in dir.get_directories():
		var path := "res://assets/models/%s/%s_1k.gltf" % [slug, slug]
		var ps: PackedScene = load(path)
		if ps == null:
			print(slug, " : ECHEC")
			continue
		var inst: Node3D = ps.instantiate()
		var aabb := B.local_aabb(inst)
		var meshes := inst.find_children("*", "MeshInstance3D", true, false)
		var names := []
		for m in meshes:
			names.append(m.name)
		print("%-28s size=(%.2f, %.2f, %.2f)  min=(%.2f, %.2f, %.2f)  meshes=%d %s" % [slug, aabb.size.x, aabb.size.y, aabb.size.z, aabb.position.x, aabb.position.y, aabb.position.z, meshes.size(), str(names.slice(0, 6))])
		inst.free()
	quit()
