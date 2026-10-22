extends SceneTree
## Outil : vignettes (face +Z / profil +X / dessus) de fichiers .glb quelconques.
## godot --path . --script res://tools/render_glb.gd -- --out=<dossier> res://a.glb res://b.glb ...

var out_dir := "user://glb_renders"
var files: PackedStringArray = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		else:
			files.append(a)
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
	for path in files:
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		vp.add_child(inst)
		var aabb := B.local_aabb(inst)
		var c := aabb.get_center()
		var r := aabb.size.length() * 0.6 + 0.05
		var base := path.get_file().get_basename()
		for view in ["front", "side", "top"]:
			match view:
				"front":
					cam.look_at_from_position(c + Vector3(0.0, r * 0.35, r * 1.6), c)
				"side":
					cam.look_at_from_position(c + Vector3(r * 1.6, r * 0.35, 0.0), c)
				"top":
					cam.look_at_from_position(c + Vector3(0.01, r * 1.8, 0.3), c)
			await process_frame
			await process_frame
			await process_frame
			vp.get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, base, view])
		inst.queue_free()
		await process_frame
	print("rendus terminés")
	quit()
