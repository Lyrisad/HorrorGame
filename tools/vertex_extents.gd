extends SceneTree
## Outil : étendue réelle des sommets (percentiles) d'un modèle, pour repérer les sommets parasites.
## godot --headless --path . --script res://tools/vertex_extents.gd -- res://a.glb


func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		var xs := PackedFloat32Array()
		var ys := PackedFloat32Array()
		var zs := PackedFloat32Array()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var xf := B._relative_xform(inst, m)
			for s in m.mesh.get_surface_count():
				var arr := m.mesh.surface_get_arrays(s)
				for v in arr[Mesh.ARRAY_VERTEX]:
					var w: Vector3 = xf * v
					xs.append(w.x)
					ys.append(w.y)
					zs.append(w.z)
		var axes := [xs, ys, zs]
		for k in 3:
			var a: PackedFloat32Array = axes[k]
			a.sort()
			var n := a.size()
			print("%s %s: min=%.3f p1=%.3f p99=%.3f max=%.3f (n=%d)" % [path.get_file(), "xyz"[k], a[0], a[int(n * 0.01)], a[int(n * 0.99)], a[n - 1], n])
		inst.free()
	quit()
