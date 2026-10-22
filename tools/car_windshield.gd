extends SceneTree
## Outil : analyse le pare-brise du modèle (triangles des vitres orientés vers l'avant).


func _init() -> void:
	var inst: Node3D = (load("res://assets/sketchfab/corolla/corolla.glb") as PackedScene).instantiate()
	var root := Node3D.new()
	root.add_child(inst)
	inst.rotation_degrees.y = 180.0
	var m := inst.find_children("corolla_e180_windows*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var xf := B._relative_xform(root, m)
	var arr := m.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var up := 0
	var dn := 0
	var d := Vector3(0, 0.356, 0.864).normalized()
	var nrm_plane := Vector3(0, 0.864, -0.356).normalized()
	var p0 := Vector3(0, 0.918, -1.243)
	var offs := []
	for i in range(0, idx.size(), 3):
		var a := xf * v[idx[i]]
		var b := xf * v[idx[i + 1]]
		var c := xf * v[idx[i + 2]]
		var nrm := (b - a).cross(c - a).normalized()
		var cen := (a + b + c) / 3.0
		if abs(nrm.x) < 0.5 and cen.z < -0.3:
			if nrm.y > 0:
				up += 1
			else:
				dn += 1
			if abs(cen.x) < 0.2:
				offs.append("%.3f/%.3f n=%.2f,%.2f" % [(cen - p0).dot(d), (cen - p0).dot(nrm_plane), nrm.y, nrm.z])
	print("up=", up, " dn=", dn)
	for o in offs:
		print("  ", o)
	var mat := m.get_active_material(0)
	print(mat, " ", mat.resource_name)
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		print("transp=", sm.transparency, " albedo=", sm.albedo_color, " cull=", sm.cull_mode, " rough=", sm.roughness, " tex=", sm.albedo_texture)
	quit()
