extends SceneTree
## Outil : rend des vignettes d'animations d'un personnage .glb (vue de face et de profil).
## godot --path . --script res://tools/render_anim.gd -- --glb=res://... --out=<dossier> [--anims=a,b] [--times=0,0.25,0.5]

var glb := ""
var out_dir := "user://anim_renders"
var anims: PackedStringArray = []
var times: PackedFloat32Array = [0.0, 0.25, 0.5, 0.75]
var img_size := Vector2i(384, 512)
var dist := 2.2
var views: PackedStringArray = ["front", "side"]


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="):
			glb = a.substr(6)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--anims="):
			anims = a.substr(8).split(",")
		elif a.begins_with("--size="):
			var p := a.substr(7).split(",")
			img_size = Vector2i(int(p[0]), int(p[1]))
		elif a.begins_with("--dist="):
			dist = float(a.substr(7))
		elif a.begins_with("--views="):
			views = a.substr(8).split(",")
		elif a.begins_with("--times="):
			times = PackedFloat32Array()
			for t in a.substr(8).split(","):
				times.append(float(t))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var vp := SubViewport.new()
	vp.size = img_size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.4, 0.42, 0.45)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	vp.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor_mi.mesh = pm
	vp.add_child(floor_mi)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	var inst: Node3D = (load(glb) as PackedScene).instantiate()
	vp.add_child(inst)
	var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var list: PackedStringArray = anims if anims.size() > 0 else ap.get_animation_list()
	print("animations : ", ap.get_animation_list())
	var aabb := B.local_aabb(inst)
	var c := aabb.get_center()
	var r := dist
	for an in list:
		var anim := ap.get_animation(an)
		for view in views:
			for t in times:
				ap.play(an)
				ap.speed_scale = 0.0
				ap.seek(t * anim.length, true)
				await process_frame
				var ty := 1.0 if r < 2.0 else r * 0.45
				if view == "front":
					cam.look_at_from_position(Vector3(0, ty + 0.2, r * 1.5), Vector3(0, ty, 0))
				elif view == "back":
					cam.look_at_from_position(Vector3(0, ty + 0.2, -r * 1.5), Vector3(0, ty, 0))
				elif view == "rside":
					cam.look_at_from_position(Vector3(-r * 1.5, ty + 0.2, 0), Vector3(0, ty, 0))
				elif view == "top":
					cam.look_at_from_position(Vector3(0.01, r * 1.6, 0), Vector3(0, 0, 0))
				else:
					cam.look_at_from_position(Vector3(r * 1.5, ty + 0.2, 0), Vector3(0, ty, 0))
				await process_frame
				await process_frame
				await process_frame
				vp.get_texture().get_image().save_png("%s/%s_%s_%03d.png" % [out_dir, an, view, int(t * 100)])
	print("rendus terminés")
	quit()
