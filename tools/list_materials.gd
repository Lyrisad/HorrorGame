extends SceneTree
## Outil : liste les matériaux d'un modèle (émission, transparence, nœud).
## godot --headless --path . --script res://tools/list_materials.gd -- res://chemin.glb


func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for s in m.mesh.get_surface_count():
				var mat := m.get_active_material(s)
				if mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					var aabb: AABB = B._relative_xform(inst, m) * m.get_aabb()
					print("%-45s %-24s emission=%s(%.2f) transp=%d center=%s" % [m.name, sm.resource_name, sm.emission_enabled, sm.emission_energy_multiplier, sm.transparency, aabb.get_center()])
		inst.free()
	quit()
