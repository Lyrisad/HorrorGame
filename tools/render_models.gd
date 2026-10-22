extends SceneTree
## Outil : rend une vignette de chaque modèle vu depuis +Z (face "avant" = +Z) et depuis +X.
## godot --path . --script res://tools/render_models.gd -- --out=<dossier> [--only=a,b]

var out_dir := "user://renders"
var only: PackedStringArray = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.37, 0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	# repère : flèche rouge = +Z (vers la caméra de face), verte = +X
	var dir := DirAccess.open("res://assets/models")
	for slug in dir.get_directories():
		if only.size() > 0 and not only.has(slug):
			continue
		var holder := Node3D.new()
		vp.add_child(holder)
		var inst: Node3D = (load("res://assets/models/%s/%s_1k.gltf" % [slug, slug]) as PackedScene).instantiate()
		holder.add_child(inst)
		var aabb := B.local_aabb(inst)
		var c := aabb.get_center()
		var r := aabb.size.length() * 0.75 + 0.05
		var marker := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.02, 1.0) * r
		marker.mesh = bm
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(1, 0, 0)
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = mm
		marker.position = Vector3(c.x, aabb.position.y, c.z + r * 0.5)
		holder.add_child(marker)
		for view in ["front", "side"]:
			if view == "front":
				cam.look_at_from_position(c + Vector3(0.0, r * 0.35, r * 1.6), c)
			else:
				cam.look_at_from_position(c + Vector3(r * 1.6, r * 0.35, 0.0), c)
			await process_frame
			await process_frame
			await process_frame
			var img := vp.get_texture().get_image()
			img.save_png("%s/%s_%s.png" % [out_dir, slug, view])
		holder.queue_free()
		await process_frame
	print("rendus terminés")
	quit()
