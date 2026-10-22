extends Node
## Outil : rendu d'un modèle tel que le jeu le charge (B.model), éclairage neutre, 3 angles.
## godot --path . res://tools/render_model.tscn -- --model=sf:hard_hat --out=<dossier>

func _ready() -> void:
	var slug := "sf:hard_hat"
	var out := "user://model_renders"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			slug = a.substr(8)
		elif a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = Vector2i(600, 600)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.32, 0.35)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	we.environment = e
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(sun)
	var m := B.model(vp, slug, Vector3.ZERO, 0.0, {})
	var bb := B.local_aabb(m)
	var c := bb.get_center()
	var r := bb.size.length() * 1.2
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	var k := 0
	for dir in [Vector3(1, 0.6, 1), Vector3(-1, 0.4, 0.3), Vector3(0.1, 1.5, -0.6)]:
		cam.look_at_from_position(c + (dir as Vector3).normalized() * r, c)
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s/%s_%d.png" % [out, slug.replace(":", "_"), k])
		k += 1
	get_tree().quit()
