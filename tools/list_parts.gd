extends SceneTree
## Outil : liste les "pièces" d'un pack de modèles (nœuds contenant des maillages) avec leur taille.
## godot --headless --path . --script res://tools/list_parts.gd -- res://chemin/pack.glb ...


func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		print("== ", path)
		var total := B.local_aabb(inst)
		print("   total size=(%.2f, %.2f, %.2f)" % [total.size.x, total.size.y, total.size.z])
		# descend jusqu'au premier nœud ayant plusieurs enfants
		var n: Node = inst
		while n.get_child_count() == 1 and not (n.get_child(0) is MeshInstance3D):
			n = n.get_child(0)
		for c in n.get_children():
			if not (c is Node3D):
				continue
			var meshes := c.find_children("*", "MeshInstance3D", true, false)
			if c is MeshInstance3D:
				meshes.append(c)
			if meshes.is_empty():
				continue
			var holder := Node3D.new()
			var dup: Node3D = c.duplicate()
			holder.add_child(dup)
			dup.transform = B._relative_xform(inst, c)
			var bb := B.local_aabb(holder)
			print("   %-50s size=(%.2f, %.2f, %.2f) center=(%.2f, %.2f, %.2f) meshes=%d" % [c.name, bb.size.x, bb.size.y, bb.size.z, bb.get_center().x, bb.get_center().y, bb.get_center().z, meshes.size()])
			holder.free()
		inst.free()
	quit()
