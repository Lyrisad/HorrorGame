extends SceneTree
## Outil : liste les surfaces du modèle de voiture (matériau + boîte englobante, repère CarRig :
## modèle tourné de 180°, avant vers -Z). Sert à caler la pluie sur le vrai pare-brise.
## godot --headless --path . --script res://tools/car_glass.gd -- [filtre]


func _init() -> void:
	var filt := ""
	if OS.get_cmdline_user_args().size() > 0:
		filt = OS.get_cmdline_user_args()[0].to_lower()
	var inst: Node3D = (load("res://assets/sketchfab/corolla/corolla.glb") as PackedScene).instantiate()
	var root := Node3D.new()
	root.add_child(inst)
	inst.rotation_degrees.y = 180.0
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := B._relative_xform(root, m)
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			var mname := mat.resource_name if mat != null else "?"
			if filt != "" and not (mname.to_lower().contains(filt) or String(m.name).to_lower().contains(filt)):
				continue
			var arr := m.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var lo := Vector3.INF
			var hi := -Vector3.INF
			for p in v:
				var w := xf * p
				lo = lo.min(w)
				hi = hi.max(w)
			print("%-40s s%d %-28s n=%5d lo=(%.3f, %.3f, %.3f) hi=(%.3f, %.3f, %.3f)" % [m.name, s, mname, v.size(), lo.x, lo.y, lo.z, hi.x, hi.y, hi.z])
	quit()
