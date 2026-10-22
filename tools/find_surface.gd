extends SceneTree
## Outil : repère une surface horizontale dans un modèle (ex. plateau d'un bureau) :
## sommets dont la hauteur est dans [ymin, ymax] (et x > xmin), centre et étendue.
## godot --headless --path . --script res://tools/find_surface.gd -- res://modele.glb ymin ymax xmin


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var inst: Node3D = (load(a[0]) as PackedScene).instantiate()
	var ymin := float(a[1])
	var ymax := float(a[2])
	var xmin := float(a[3]) if a.size() > 3 else -INF
	var aabb := B.local_aabb(inst)
	print("aabb ", aabb)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var acc := Vector3.ZERO
	var n := 0
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := B._relative_xform(inst, m)
		for s in m.mesh.get_surface_count():
			for v in m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = xf * v
				if p.y >= ymin and p.y <= ymax and p.x > xmin:
					lo = lo.min(p)
					hi = hi.max(p)
					acc += p
					n += 1
	print("sommets=%d centre=%s min=%s max=%s" % [n, acc / maxi(n, 1), lo, hi])
	inst.free()
	quit()
