extends Level
## Chapitre final — Surface. Il est 5 h 47, en novembre : il fait nuit noire dans la forêt.
## Théo sort par une bouche d'égout. Des hommes au masque patrouillent avec leurs lampes (ils voient mais
## entendent mal), un drone le filme pour le direct. Sur le sentier : des avis de recherche agrafés aux arbres,
## des affaires abandonnées, des pièges à loup sous les feuilles, et la caméra d'une victime de la session 13 dont
## la dernière vidéo montre une cabane avec une radio... morte, il faut une batterie. Elle est au camp des
## ravisseurs (régie, flux du drone, page du direct, tableau des sujets, téléphones confisqués). La prendre fait
## sortir le deuxième homme du van. À la radio, c'est le direct qui répond : « Ouvrez la trappe. » La créature
## sort de la plaque « S·13 » : course jusqu'à la route, où une caméra sur un poteau se tourne vers lui.
##
## Tout ce qui compte est déplaçable dans l'éditeur (F8, carte « surface ») : la cabane, les pièces du camp, les
## pièges, les cailloux, la caméra, la batterie... Le terrain et les sentiers suivent la cabane et le camp.

const ROAD_Z := -52.0
const POLE := Vector3(3.5, 0, -47.5)
const POLE_STEP := 36.0  ## écart entre deux poteaux de la ligne électrique (le long de la route)
const POLE_R := 0.095  ## rayon d'un poteau en bois (modèle Poly Haven à l'échelle 1,35)
const AREA := Rect2(-60, -62, 120, 82)  ## terrain en relief (x de -60 à 60, z de -62 à 20)
const TRAIL := [Vector3(0, 0, 2), Vector3(-1.5, 0, -8), Vector3(1.0, 0, -17), Vector3(-0.5, 0, -27), Vector3(1.0, 0, -38), Vector3(0, 0, -49)]

var pole_cam: SecurityCamera
var revealed := false
var wind: AudioStreamPlayer
var stage := "start"  ## start → battery (radio morte) → carry (il rapporte la batterie) → chase → done
var has_battery := false
var battery_in := false
var stones := 0
var dying := false
var editing := false
var trunks: Array = []
var creature: Creature
var hunters: Array = []  ## [Hunter] : celui qui patrouille dès le début, celui du van
var drone: Drone
var drones_left := 2
var feed: SecurityFeed
var _feed_mat: ShaderMaterial
# éléments déplaçables (meta « editobj »)
var hut: Node3D
var desk: Node3D
var van: Node3D
var crate: Node3D
var battery: Node3D
var board: Node3D
var fire: Node3D
var work_light: Node3D
var generator: Node3D
var antenna: Node3D
var s13: Node3D
var cam13: Node3D
var exit_hole: Node3D
var traps: Array = []  ## [nœud, déclenché]
var piles: Array = []
# terrain
var _noise := FastNoiseLite.new()
var _hgrid := PackedFloat32Array()
var _gw := 0
var _gd := 0
var _paths: Array = []  ## [[points], largeur]
var _clearings: Array = []  ## [centre, rayon]
var _trunk_grid := {}
var _layout: Variant = null  ## disposition sauvegardée par le joueur (éditeur), ou null
var _force_deco := false  ## pose le décor par défaut même s'il y a une disposition (sous-bois ajouté après coup)
# état
var _trapped := -1
var _trap_prog := 0.0
var _road_said := false
var _radio_glow: OmniLight3D
var _radio_static: AudioStreamPlayer3D
var _drone_cd := 30.0
var _report_cd := 8.0
var _phone_done := false
var _snap_cd := 20.0
var _owl_cd := 12.0
var _s13_heard := false
var cutscene := false  ## une scène où Théo ne contrôle rien (vidéo, téléphone) : les hommes au masque ne le repèrent pas
var _hunter_warned := false
var _stones_told := false
var _dust: GPUParticles3D
var _dust_near: GPUParticles3D


func editor_map() -> Dictionary:
	return {"id": "surface", "root": self, "nom": "Forêt (surface)"}


func _ready() -> void:
	editing = params.get("editor", false)
	_build_environment()
	_layout = MapLayout.load_entries("surface")
	_build_objects()
	MapLayout.apply_objs("surface", self)
	_compute_paths()
	_build_terrain()
	_snap_objects()
	_build_forest()
	_build_decor()
	if _layout != null:
		MapLayout.spawn(_layout, self)
		# carte faite avant les hitbox automatiques et le sous-bois éditable : on les ajoute sans rien déplacer
		for n in MapLayout.collect(self):
			MapLayout.auto_collide(n)
		if not MapLayout.has_flag("surface", "sousbois"):
			_force_deco = true
			_build_undergrowth()
			_force_deco = false
		# pareil pour le mobilier de la route (balises, panneaux, borne, barrière), ajouté après coup
		if not MapLayout.has_flag("surface", "route"):
			_force_deco = true
			_build_roadside()
			_force_deco = false
	_decor_obstacles()
	_build_road_and_pole()
	_build_bounds()

	creature = Creature.new()
	creature.nav = self
	add_child(creature)
	creature.deactivate()
	creature.caught_player.connect(func() -> void: _die("creature"))
	for k in 2:
		var h := Hunter.new()
		h.level = self
		add_child(h)
		hunters.append(h)
	_place_hunters()

	var cp := str(params.get("checkpoint", Game.args.get("checkpoint", "")))
	drones_left = int(params.get("drones", 2))
	if editing:
		player = spawn_player(exit_hole.global_position + Vector3(0, 0, 0.9), 0.0)
		_setup_player()
		Game.ui.fade_rect.color.a = 0.0
	else:
		match cp:
			"carry":
				var resp := _path_point(desk.global_position, 0.45)
				player = spawn_player(resp, rad_to_deg(atan2(-(hut.global_position - resp).x, -(hut.global_position - resp).z)))
				_setup_player()
				has_battery = true
				stones = 4
				stage = "carry"
				battery.visible = false
				_clear_interactables(battery)
				Game.ui.fade_rect.color.a = 0.0
				Game.hud.objective("Rapporter la batterie à la cabane, sans te faire voir")
				hunters[0].wake(false)
				hunters[1].wake(false)
				hunters[1].wp = 4
				_drone_cd = 6.0
			"chase":
				var door := hut.global_transform * Vector3(1.4, 0, 0.6)
				player = spawn_player(door, rad_to_deg(hut.rotation.y) + 180.0)
				_setup_player()
				battery_in = true
				stage = "chase"
				battery.visible = false
				_clear_interactables(battery)
				_install_battery_visual()
				Game.ui.fade_rect.color.a = 0.0
				_release_creature(true)
			_:
				player = spawn_player(exit_hole.global_position + Vector3(0, 0, 0.9), 0.0)
				_setup_player()
				hunters[0].wake(false)
				_play()
	pole_cam.target = player
	if not editing:
		# poussière et pollen en suspension autour de Théo : visibles dans le faisceau de la lampe
		_dust = Nature.dust(self, Vector3(6.0, 2.0, 6.0), 1600)
		_dust_near = Nature.dust_bokeh(self)
	add_trigger(Vector3(0.0, 0, ROAD_Z + 3.0), 9.0, _at_road, false)
	add_trigger(_path_point(hut.global_position, 0.8), 4.0, func() -> void:
		if stage == "start":
			Game.hud.say("Une cabane... Il y a peut-être quelqu'un. Ou un téléphone.", 3.2))
	add_trigger(_path_point(desk.global_position, 0.7), 8.0, func() -> void:
		if stage in ["start", "battery"]:
			Game.hud.say("Un groupe électrogène... Des écrans. C'est leur camp.", 3.2))
	add_trigger(s13.global_position, 5.0, _s13_scratch)
	if Game.args.has("freecam"):
		var fc := Camera3D.new()
		fc.fov = float(Game.args.get("freefov", 50.0))
		add_child(fc)
		var a3 := str(Game.args["freecam"]).split(",")
		var b3 := str(Game.args.get("freelook", "0,0,0")).split(",")
		fc.look_at_from_position(Vector3(float(a3[0]), float(a3[1]), float(a3[2])), Vector3(float(b3[0]), float(b3[1]), float(b3[2])))
		fc.current = true
		if Game.args.has("freelight"):
			B.omni(fc, Vector3.ZERO, Color(1, 1, 1), float(Game.args["freelight"]), 40.0)
	if Game.args.has("torch"):
		player.set_flashlight(true, true)
	if Game.args.has("surfacetest"):
		_surface_test(str(Game.args["surfacetest"]))


func _setup_player() -> void:
	player.has_flashlight = true
	# dehors, rien ne renvoie la lumière : le faisceau porte plus loin que dans les tunnels (sinon on ne voit pas
	# une cabane à six mètres)
	player.flashlight.spot_range = 34.0
	player.flashlight.spot_attenuation = 0.6
	Game.hud.show_hud(true)
	Game.hud.set_battery(1)


func inventory() -> Array:
	var items: Array = [
		{"id": "flashlight", "name": "Lampe torche", "desc": "Ta lampe de service. [F] pour l'allumer : indispensable dans le noir, mais elle se voit de loin."},
		{"id": "phone", "name": "Ton téléphone", "desc": "Aucun réseau. Rien depuis la maison."}]
	if stones > 0:
		items.append({"id": "stone", "name": "Cailloux", "count": stones, "desc": "À lancer ([G] ou clic droit) : sur le drone, ou loin de toi pour détourner les hommes au masque."})
	if has_battery:
		items.append({"id": "battery", "name": "Batterie 12 V", "desc": "Lourde. Pour la radio de la cabane."})
	return items


func get_surface(pos: Vector3) -> String:
	var dz := absf(pos.z - ROAD_Z)
	if dz < 3.4:
		return "concrete"
	if dz < 4.6:
		return "gravel"
	if hut != null:
		var lp := hut.global_transform.affine_inverse() * pos
		if lp.x > -2.1 and lp.x < 2.25 and absf(lp.z) < 1.25 and lp.y > 0.08:
			return "wood"
	return "grass"


func _play() -> void:
	Game.ui.fade_rect.color = Color(0, 0, 0, 1)
	var tw := create_tween()
	tw.tween_property(Game.ui.fade_rect, "color:a", 0.0, 2.5)
	await tw.finished
	Game.hud.say("J'suis sorti... J'suis sorti !", 3.0)
	await wait(3.5)
	Game.hud.say("Il fait nuit noire... Une route, quelque part. Il faut que je trouve quelqu'un.", 3.6)
	Game.hud.objective("Trouver de l'aide")
	await wait(4.5)
	Game.hud.hint("[F] lampe torche (elle se voit de loin)   ·   [C] s'accroupir", 6.0)


# ================================================================== ambiance : la nuit
func _build_environment() -> void:
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.005, 0.008, 0.016)
	sky.sky_horizon_color = Color(0.028, 0.032, 0.045)
	sky.ground_horizon_color = Color(0.015, 0.016, 0.02)
	sky.ground_bottom_color = Color(0.0, 0.0, 0.0)
	sky.sky_energy_multiplier = 1.0
	make_environment({
		"sky": sky,
		"ambient": Color(0.06, 0.075, 0.11),
		"ambient_energy": 0.26,
		"fog": true,
		"fog_color": Color(0.028, 0.033, 0.045),
		"fog_density": 0.016,
		"vfog": true,
		"vfog_density": 0.01,
		"vfog_albedo": Color(0.5, 0.53, 0.6),
		"vfog_length": 60.0,
		"auto_exposure": false,
		"exposure": 1.55,
	})
	# la lune, voilée : juste assez pour deviner les troncs et les silhouettes
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.08
	moon.light_volumetric_fog_energy = 0.6
	moon.rotation_degrees = Vector3(-38, -150, 0)
	add_child(moon)
	Game.set_fx("grain", 0.07)
	Game.set_fx("gain", 0.45)
	Game.set_fx("saturation", 0.5)
	Game.set_fx("tint", Color(0.88, 0.95, 1.08))
	Sound.set_reverb(0.25, 0.08, 0.7)
	Game.set_clock(5, 47, 12, 15)
	if not editing:
		wind = Sound.loop("forest_wind_loop", -14.0)
		Sound.loop("wind_loop", -20.0)


# ================================================================== éléments déplaçables
func _obj(id: String, pos: Vector3, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.name = id
	n.position = pos
	n.rotation_degrees.y = yaw
	n.set_meta("editobj", "surface_" + id)
	return n


## Un objet déplaçable DANS un autre (la radio dans la cabane, un écran sur la table) : il suit son parent quand on
## déplace celui-ci, et se déplace aussi tout seul dans l'éditeur.
func _sub(parent: Node3D, id: String, pos: Vector3, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.name = id
	n.position = pos
	n.rotation_degrees.y = yaw
	n.set_meta("editobj", "surface_" + id)
	return n


func _build_objects() -> void:
	exit_hole = _obj("exit", Vector3(0, 0, 0.6))
	B.model(exit_hole, "water_manhole_cover", Vector3(0.9, 0.0, 0.1), 30.0, {"width": 0.8})
	var hole := B.cylinder(exit_hole, 0.36, 0.36, 0.02, Vector3(0, 0.01, 0), B.color_mat(Color(0, 0, 0), 1.0), false, 20)
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_hut(_obj("hut", Vector3(-24, 0, -19), 90.0))
	_build_camp()
	s13 = _obj("s13", Vector3(-6.5, 0, -10))
	var lid := B.model(s13, "water_manhole_cover", Vector3.ZERO, 0.0, {"width": 0.8})
	lid.name = "Lid"
	B.decal(s13, "res://assets/gen/decal_spray13.png", Vector3(0, 0.1, 0), Vector3.UP, 1.3, 1.3, 0.4)
	_build_cam13(_obj("cam13", Vector3(-2.3, 0, -13.4)))
	var trap_spots := [Vector3(-1.1, 0, -12.2), Vector3(0.7, 0, -21.5), Vector3(-12.8, 0, -19.4), Vector3(14.6, 0, -30.1), Vector3(0.3, 0, -33.8)]
	for i in trap_spots.size():
		var t := _obj("trap_%d" % i, trap_spots[i], randf_range(0, 360))
		B.model(t, "sf:bear_trap", Vector3(0, 0.005, 0), 0.0, {"width": 0.42})
		# un tapis de feuilles projeté sur le sol ET sur les mâchoires : on le devine à peine
		B.decal(t, "res://assets/gen/leaf_litter.png", Vector3(0, 0.2, 0), Vector3.UP, 0.95, 0.95, 0.5)
		traps.append([t, false])
	var stone_spots := [Vector3(1.7, 0, -3.5), Vector3(-2.2, 0, -16.0), Vector3(-15.5, 0, -17.6), Vector3(7.5, 0, -28.2), Vector3(-1.8, 0, -31.0), Vector3(21.0, 0, -26.5)]
	for i in stone_spots.size():
		_build_stones(_obj("stones_%d" % i, stone_spots[i]))




## Les éléments déplaçables sont posés sur le relief (après qu'on connaît leurs positions et le terrain).
func _snap_objects() -> void:
	for n in MapLayout.movables(self):
		# ceux qui sont posés dans un autre (la cabane) suivent leur parent
		if n.get_parent() != self:
			continue
		var nd := n as Node3D
		nd.global_position.y = floor_y(nd.global_position)


func _clear_interactables(n: Node) -> void:
	for c in n.find_children("*", "", true, false):
		if c is Interactable:
			c.queue_free()


# ================================================================== terrain
## Sentiers : le sentier principal (sortie → route) et deux embranchements vers la cabane et le camp.
func _compute_paths() -> void:
	_paths = [[TRAIL, 1.3], [_branch(hut.global_transform * Vector3(1.45, 0, 3.4)), 1.0], [_branch(desk.global_position), 1.1]]
	_clearings = [[hut.global_position, 5.5], [desk.global_position, 11.0], [exit_hole.global_position, 3.5], [s13.global_position, 2.0], [POLE, 3.0]]


## Point du sentier principal le plus proche de `to`, puis un coude, puis `to`.
func _branch(to: Vector3) -> Array:
	var best: Vector3 = TRAIL[0]
	var bd := 1e9
	for i in TRAIL.size() - 1:
		for k in 9:
			var q: Vector3 = (TRAIL[i] as Vector3).lerp(TRAIL[i + 1], k / 8.0)
			var d := Vector2(q.x - to.x, q.z - to.z).length()
			if d < bd:
				bd = d
				best = q
	var mid := best.lerp(to, 0.5) + Vector3(0, 0, 1.5 * sign(to.x))
	return [best, mid, to]


## Le point à la fraction `f` (0 → 1) de la longueur d'un chemin (liste de points), au sol.
func _along(pts: Array, f: float) -> Vector3:
	var total := 0.0
	for i in pts.size() - 1:
		total += Vector2((pts[i + 1] as Vector3).x - (pts[i] as Vector3).x, (pts[i + 1] as Vector3).z - (pts[i] as Vector3).z).length()
	var s := clampf(f, 0.0, 1.0) * total
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var l := Vector2(b.x - a.x, b.z - a.z).length()
		if s <= l or i == pts.size() - 2:
			var p := a.lerp(b, clampf(s / maxf(l, 0.001), 0.0, 1.0))
			p.y = floor_y(p)
			return p
		s -= l
	return pts[pts.size() - 1]


## Un point sur l'embranchement vers `target` (0 = au sentier, 1 = arrivé).
func _path_point(target: Vector3, t: float) -> Vector3:
	var br := _branch(target)
	var a: Vector3 = br[0]
	var p := a.lerp(target, t)
	p.y = floor_y(p)
	return p


func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()


func _path_dist(p: Vector3) -> float:
	var d := 1e9
	for path in _paths:
		var pts: Array = path[0]
		for i in pts.size() - 1:
			d = minf(d, _seg_dist(p, pts[i], pts[i + 1]) - float(path[1]))
	return d


## Distance au plus proche endroit dégagé (sentier, clairière, route) ; 0 dedans.
func _clear_dist(p: Vector3) -> float:
	var d := _path_dist(p)
	for c in _clearings:
		var cp: Vector3 = c[0]
		d = minf(d, Vector2(p.x - cp.x, p.z - cp.z).length() - float(c[1]))
	d = minf(d, absf(p.z - ROAD_Z) - 4.5)
	return maxf(d, 0.0)


func _height_raw(x: float, z: float) -> float:
	var flat := smoothstep(0.4, 7.0, _clear_dist(Vector3(x, 0, z)))
	var h := _noise.get_noise_2d(x, z) * 1.25 + _noise.get_noise_2d(x * 2.7 + 31.0, z * 2.7 - 17.0) * 0.18
	var edge := minf(minf(x - AREA.position.x, AREA.end.x - x), minf(z - AREA.position.y, AREA.end.y - z))
	return h * flat * smoothstep(0.0, 8.0, edge)


func floor_y(p: Vector3) -> float:
	var fx := p.x - AREA.position.x
	var fz := p.z - AREA.position.y
	if _hgrid.is_empty() or fx < 0.0 or fz < 0.0 or fx >= _gw - 1 or fz >= _gd - 1:
		return 0.0
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := _hgrid[j * _gw + i]
	var h10 := _hgrid[j * _gw + i + 1]
	var h01 := _hgrid[(j + 1) * _gw + i]
	var h11 := _hgrid[(j + 1) * _gw + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _floor_p(p: Vector3) -> float:
	return floor_y(p)


## Relief doux (bosses, creux, racines), aplani et tassé sur les sentiers ; collision par carte de hauteurs.
func _build_terrain() -> void:
	_noise.seed = 5
	_noise.frequency = 0.035
	_noise.fractal_octaves = 3
	_gw = int(AREA.size.x) + 1
	_gd = int(AREA.size.y) + 1
	_hgrid.resize(_gw * _gd)
	for j in _gd:
		for i in _gw:
			_hgrid[j * _gw + i] = _height_raw(AREA.position.x + i, AREA.position.y + j)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in _gd:
		for i in _gw:
			var x := AREA.position.x + i
			var z := AREA.position.y + j
			var h := _hgrid[j * _gw + i]
			var p := Vector3(x, h, z)
			var core := 1e9
			for path in _paths:
				var pts: Array = path[0]
				for k in pts.size() - 1:
					core = minf(core, _seg_dist(p, pts[k], pts[k + 1]))
			var path_f := 1.0 - smoothstep(0.5, 1.7, core)
			var dc := Vector2(x - desk.global_position.x, z - desk.global_position.z).length()
			path_f = maxf(path_f, 0.6 * (1.0 - smoothstep(4.0, 10.0, dc)))
			var dh := Vector2(x - hut.global_position.x, z - hut.global_position.z).length()
			path_f = maxf(path_f, 0.45 * (1.0 - smoothstep(3.0, 6.0, dh)))
			# accotement de la route : gravier et terre tassée sur un bon mètre, puis la forêt
			var shoulder := 1.0 - smoothstep(3.4, 5.0, absf(z - ROAD_Z))
			st.set_color(Color(path_f, clampf(-h * 1.6 + 0.35, 0.0, 1.0), shoulder))
			st.add_vertex(p)
	for j in _gd - 1:
		for i in _gw - 1:
			var a := j * _gw + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + _gw)
			st.add_index(a + 1)
			st.add_index(a + _gw + 1)
			st.add_index(a + _gw)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.name = "Terrain"
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/forest_ground.gdshader")
	var tx := func(slug: String, kind: String) -> Texture2D: return load("res://assets/textures/%s/%s_%s.jpg" % [slug, slug, kind])
	m.set_shader_parameter("litter_diff", tx.call("forest_leaves_04", "diff"))
	m.set_shader_parameter("litter_nor", tx.call("forest_leaves_04", "nor"))
	m.set_shader_parameter("needles_diff", tx.call("forest_floor", "diff"))
	m.set_shader_parameter("needles_nor", tx.call("forest_floor", "nor"))
	m.set_shader_parameter("path_diff", tx.call("muddy_tracks", "diff"))
	m.set_shader_parameter("path_nor", tx.call("muddy_tracks", "nor"))
	m.set_shader_parameter("moss_diff", tx.call("moss_wood", "diff"))
	m.set_shader_parameter("gravel_diff", tx.call("gravel_road", "diff"))
	m.set_shader_parameter("gravel_nor", tx.call("gravel_road", "nor"))
	var nt := NoiseTexture2D.new()
	var nn := FastNoiseLite.new()
	nn.frequency = 0.02
	nt.noise = nn
	nt.seamless = true
	m.set_shader_parameter("mask_noise", nt)
	mi.material_override = m
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = _gw
	hm.map_depth = _gd
	hm.map_data = _hgrid
	cs.shape = hm
	body.add_child(cs)
	add_child(body)
	body.position = Vector3(AREA.position.x + (_gw - 1) * 0.5, 0, AREA.position.y + (_gd - 1) * 0.5)
	# au-delà : la lisière, à plat (le brouillard cache tout)
	var litter := B.mat("forest_leaves_04", 2.6, {"color": Color(0.55, 0.52, 0.5)})
	for spec in [[Vector3(0, -0.02, AREA.position.y - 100), Vector3(400, 0.02, 200)], [Vector3(0, -0.02, AREA.end.y + 100), Vector3(400, 0.02, 200)],
			[Vector3(AREA.position.x - 100, -0.02, AREA.get_center().y), Vector3(200, 0.02, AREA.size.y)], [Vector3(AREA.end.x + 100, -0.02, AREA.get_center().y), Vector3(200, 0.02, AREA.size.y)]]:
		B.box(self, spec[1], spec[0], litter, true)


# ================================================================== forêt et sous-bois
func _tree_avoid(p: Vector3) -> bool:
	return _clear_dist(p) < 1.2


## Sous-bois lointain (instancié) : seulement loin des sentiers. Près des sentiers, ce sont des objets de décor.
func _far_brush_avoid(p: Vector3) -> bool:
	return _clear_dist(p) < 9.5


## Une plante près des sentiers : jamais SUR le sentier, la route ou dans une clairière.
func _plant_ok(p: Vector3) -> bool:
	if _path_dist(p) < 0.55 or absf(p.z - ROAD_Z) < 4.8:
		return false
	for c in _clearings:
		var cp: Vector3 = c[0]
		if Vector2(p.x - cp.x, p.z - cp.z).length() < float(c[1]) * 0.85:
			return false
	return AREA.grow(-4.0).has_point(Vector2(p.x, p.z))


func _build_forest() -> void:
	trunks = Nature.scatter_forest(self, Rect2(-120, -150, 240, 260), 1100, _tree_avoid, 33, [], _floor_p)
	trunks.append_array(Nature.scatter_forest(self, Rect2(-60, -62, 120, 82), 560, _tree_avoid, 61, [], _floor_p))
	# sous-bois : fougères, buissons, souches, rochers moussus, branches mortes (près du sentier, là où on passe)
	var brush := [
		["fern_02", "", 6.0, 0.45, 0.9],
		["sf:conifer_pack", "ConiferousShrub", 1.6, 0.8, 1.8],
		["shrub_03", "", 1.0, 0.6, 1.1],
		["weed_plant_02", "", 1.4, 0.3, 0.6],
		["dry_branches_medium_01", "", 2.0, 0.25, 0.4],
		["rock_moss_set_01", "", 0.5, 0.35, 0.8],
		["rock_moss_set_02", "", 0.5, 0.35, 0.8],
		["tree_stump_01", "", 0.5, 0.4, 0.7],
		["tree_stump_02", "", 0.4, 0.4, 0.7],
		["rock_09", "", 0.5, 0.3, 0.7],
	]
	# petites parcelles qui apparaissent en fondu, loin : on ne les voit plus « pousser » d'un bloc en marchant
	Nature.scatter_forest(self, Rect2(-55, -60, 110, 76), 800, _far_brush_avoid, 77, brush, _floor_p, 60.0, 14.0, true)
	_build_trunk_colliders()


func _build_trunk_colliders() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	for t in trunks:
		var p: Vector3 = t[0]
		var r: float = t[1]
		if not AREA.grow(10.0).has_point(Vector2(p.x, p.z)):
			continue
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = 6.0
		cs.shape = cyl
		cs.position = p + Vector3(0, 3.0, 0)
		body.add_child(cs)
		_add_obstacle(p, r)


func _add_obstacle(p: Vector3, r: float) -> void:
	var key := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
	if not _trunk_grid.has(key):
		_trunk_grid[key] = []
	_trunk_grid[key].append([p, r])


func trunks_near(p: Vector3) -> Array:
	var out: Array = []
	var c := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			out.append_array(_trunk_grid.get(c + Vector2i(dx, dz), []))
	return out


## Les troncs couchés et les arbres ajoutés dans l'éditeur deviennent des obstacles (créature, hommes au masque).
func _decor_obstacles() -> void:
	for n in MapLayout.collect(self):
		var model := str((n.get_meta("spec", {}) as Dictionary).get("model", ""))
		if model.contains("dead_tree_trunk"):
			var dir := n.global_basis.x.normalized()
			var half := float((n.get_meta("size", Vector3.ONE) as Vector3).x) * 0.45
			for k in range(-2, 3):
				_add_obstacle(n.global_position + dir * half * k * 0.5, 0.45)
		elif model.contains("pine") or model.contains("conifer"):
			_add_obstacle(n.global_position, 0.3)


## Décor déplaçable (ignoré si le joueur a sauvegardé sa propre disposition : elle est recréée depuis le fichier).
func deco(slug: String, pos: Vector3, yaw := 0.0, fit := {}) -> Node3D:
	if _layout != null and not _force_deco:
		return null
	var n: Node3D
	if slug.begins_with("proc:"):
		n = MapLayout.spawn_entry({"model": slug}, self)
		n.position = Vector3(pos.x, floor_y(pos), pos.z)
		n.rotation_degrees.y = yaw
	else:
		n = B.model(self, slug, Vector3(pos.x, floor_y(pos), pos.z), yaw, fit)
	n.set_meta("decor", true)
	MapLayout.auto_collide(n)
	return n


## Le sous-bois le long des sentiers, par touffes (une espèce domine chaque touffe, comme en vrai) : chaque plante
## est un objet de décor, qu'on déplace, supprime ou ajoute dans l'éditeur (F8).
func _build_undergrowth() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	# modèle, pièce, poids, hauteur min/max, plantes par touffe min/max, étalement (m)
	var kinds := [
		["fern_02", "", 5.0, 0.4, 0.85, 3, 7, 1.3],
		["nettle_plant", "", 1.4, 0.35, 0.7, 3, 6, 0.9],
		["weed_plant_02", "", 1.8, 0.3, 0.55, 2, 5, 1.0],
		["shrub_03", "", 1.4, 0.6, 1.1, 1, 3, 1.2],
		["shrub_02", "", 0.9, 0.5, 1.0, 1, 2, 1.0],
		["shrub_04", "", 0.9, 0.5, 1.0, 1, 2, 1.0],
		["sf:conifer_pack", "ConiferousShrub", 1.2, 0.8, 1.7, 1, 2, 1.5],
		["dry_branches_medium_01", "", 1.5, 0.22, 0.38, 1, 2, 1.4],
		["rock_moss_set_01", "", 0.6, 0.3, 0.7, 1, 1, 0.0],
		["rock_moss_set_02", "", 0.6, 0.3, 0.7, 1, 1, 0.0],
		["tree_stump_02", "", 0.5, 0.35, 0.6, 1, 1, 0.0],
	]
	var total := 0.0
	for k in kinds:
		total += float(k[2])
	# pas de plante dans un objet déjà posé (décor de la carte du joueur, pièges, pierres...)
	var taken: Array = []
	for n in MapLayout.collect(self) + MapLayout.movables(self):
		if n.get_parent() != self or MapLayout.is_soft(n.get_meta("spec", {})):
			continue
		var sz: Vector3 = n.get_meta("size", Vector3.ONE * 0.8)
		taken.append([n.global_position, clampf(maxf(sz.x, sz.z) * n.scale.x * 0.5, 0.3, 3.0) + 0.35])
	var room := func(q: Vector3) -> bool:
		for t in taken:
			var tp: Vector3 = t[0]
			if Vector2(q.x - tp.x, q.z - tp.z).length() < float(t[1]):
				return false
		return _plant_ok(q)
	var clumps := 0
	var tries := 0
	while clumps < 95 and tries < 3000:
		tries += 1
		var p := Vector3(rng.randf_range(AREA.position.x, AREA.end.x), 0, rng.randf_range(AREA.position.y, AREA.end.y))
		var d := _clear_dist(p)
		if d < 0.6 or d > 9.0 or not room.call(p):
			continue
		var r := rng.randf() * total
		var kind: Array = kinds[0]
		for k in kinds:
			r -= float(k[2])
			if r <= 0.0:
				kind = k
				break
		clumps += 1
		for i in rng.randi_range(int(kind[5]), int(kind[6])):
			var a := rng.randf() * TAU
			var q := p + Vector3(cos(a), 0, sin(a)) * float(kind[7]) * sqrt(rng.randf()) * (0.0 if i == 0 else 1.0)
			if not room.call(q):
				continue
			var fit := {"height": rng.randf_range(float(kind[3]), float(kind[4]))}
			if str(kind[1]) != "":
				fit["part"] = kind[1]
			deco(kind[0], q, rng.randf() * 360.0, fit)


func _build_decor() -> void:
	if _layout != null:
		return
	_build_undergrowth()
	# décor du camp, autour de la régie (déplaçable / supprimable dans l'éditeur)
	var c := desk.global_position
	deco("sf:canvas_tent", c + Vector3(5.0, 0, 5.5), 200.0, {"width": 4.0})
	deco("sf:sat_dish", c + Vector3(-6.0, 0, 3.5), 140.0, {"width": 1.4})
	deco("sf:military_furniture", c + Vector3(3.5, 0, 3.0), 90.0, {"part": "SM_MTable_001_1", "scale": 1.0})
	deco("sf:military_furniture", c + Vector3(-2.6, 0, 7.4), 30.0, {"part": "SM_MChair_002", "scale": 1.0})
	deco("sf:military_furniture", c + Vector3(-0.4, 0, 7.6), -40.0, {"part": "SM_MChair_002", "scale": 1.0})
	deco("metal_jerrycan", c + Vector3(-7.2, 0, -1.6), 10.0, {"height": 0.45})
	deco("plastic_jerrycan", c + Vector3(-5.8, 0, -3.6), 60.0, {"height": 0.4})
	deco("propane_tank", c + Vector3(2.4, 0, 2.6), 0.0, {"height": 0.6})
	deco("old_military_crate", c + Vector3(-3.6, 0, -1.8), 20.0, {"width": 1.0})
	deco("wooden_crate_01", c + Vector3(1.2, 0, -3.2), 40.0, {"height": 0.55})
	deco("sf:sleeping_bag", c + Vector3(4.2, 0.02, 7.6), 100.0, {"width": 1.8})
	deco("wooden_axe", c + Vector3(-2.4, 0, 5.2), 70.0, {"height": 0.7})
	# troncs couchés en travers du sentier
	deco("dead_tree_trunk", Vector3(0.6, 0, -24.0), 75.0, {"width": 5.0, "collide": true})
	deco("dead_tree_trunk_02", Vector3(-0.8, 0, -36.5), 105.0, {"width": 5.5, "collide": true})
	deco("dead_tree_trunk", Vector3(-10.0, 0, -22.6), 15.0, {"width": 4.5, "collide": true})
	# affaires des victimes d'avant, au bord du sentier
	deco("sf:sneakers_brown", Vector3(1.9, 0, -9.6), 130.0, {"width": 0.34})
	deco("vintage_suitcase", Vector3(-3.1, 0, -25.5), 200.0, {"width": 0.6})
	deco("sf:worn_cap", Vector3(-2.6, 0.0, -39.8), 70.0, {"depth": 0.27})
	deco("sf:sleeping_bag", Vector3(13.0, 0, -32.6), 40.0, {"width": 1.8})
	deco("sf:flashlight_dead", Vector3(2.2, 0, -30.4), 210.0, {"depth": 0.24})
	# avis de recherche agrafés aux troncs qui bordent le sentier (face au sentier, à hauteur d'yeux)
	var posted := 0
	for t in trunks:
		if posted >= 6:
			break
		var p: Vector3 = t[0]
		var r: float = t[1]
		if r < 0.18 or r > 0.36 or _path_dist(p) > 2.2 or _path_dist(p) < 0.0:
			continue
		var to := _nearest_on_trail(p) - p
		to.y = 0.0
		if to.length() < 0.5:
			continue
		var out := to.normalized()
		var pst := MapLayout.spawn_entry({"model": "proc:poster_%d" % (posted % 3)}, self)
		pst.global_position = Vector3(p.x, floor_y(p) + 1.35, p.z) + out * (r + 0.01)
		pst.rotation.y = atan2(out.x, out.z)
		posted += 1
	_build_roadside()


## Le bord de la D 47 : balises J6 (des deux côtés, à ~33 m), un 80 et un « chasse en cours » (à droite de chaque
## sens de circulation), la borne kilométrique, la barrière du chemin (ouverte, chaîne coupée), le panneau de l'ONF,
## quelques déchets, un avis de recherche sur le poteau de la caméra. Décor déplaçable dans l'éditeur.
func _build_roadside() -> void:
	if _layout != null and not _force_deco:
		return
	for x in [-82.0, -49.0, -16.0, 18.0, 51.0, 84.0]:
		deco("proc:road_delineator", Vector3(x, 0, ROAD_Z + 4.0), 90.0)
	for x in [-66.0, -33.0, 1.0, 34.0, 67.0]:
		deco("proc:road_delineator", Vector3(x, 0, ROAD_Z - 4.0), 90.0)
	deco("proc:road_sign_80", Vector3(-24.0, 0, ROAD_Z + 4.25), -90.0)
	deco("proc:road_sign_chasse", Vector3(22.0, 0, ROAD_Z - 4.3), 90.0)
	deco("proc:road_borne", Vector3(34.0, 0, ROAD_Z + 4.1), 90.0)
	# la barrière du chemin forestier, face à la route : lisse repoussée côté bois, à l'écart du chemin
	var mouth := _nearest_on_trail(Vector3(0, 0, ROAD_Z + 4.4))
	deco("proc:road_barrier", Vector3(mouth.x, 0, ROAD_Z + 4.4), 180.0)
	deco("proc:road_sign_b0", Vector3(mouth.x - 2.55, 0, ROAD_Z + 4.45), 180.0)
	deco("proc:road_foret", Vector3(mouth.x - 6.2, 0, ROAD_Z + 4.9), 195.0)
	# ce que les gens jettent par la fenêtre
	deco("old_tyre", Vector3(-20.5, 0, ROAD_Z - 5.3), 30.0, {"width": 0.62})
	deco("trashbag", Vector3(13.5, 0, ROAD_Z - 5.0), 70.0, {"height": 0.5})
	deco("can_rusted", Vector3(-3.4, 0, ROAD_Z + 3.9), 20.0, {"height": 0.12})
	deco("sf:beer_can", Vector3(mouth.x + 2.6, 0, ROAD_Z + 4.1), 110.0, {"height": 0.12})
	var pst := MapLayout.spawn_entry({"model": "proc:poster_2"}, self)
	pst.global_position = Vector3(POLE.x, floor_y(POLE) + 1.4, POLE.z + POLE_R + 0.01)


func _nearest_on_trail(p: Vector3) -> Vector3:
	var best := p
	var bd := 1e9
	for path in _paths:
		var pts: Array = path[0]
		for i in pts.size() - 1:
			for k in 11:
				var q: Vector3 = (pts[i] as Vector3).lerp(pts[i + 1], k / 10.0)
				var d := Vector2(q.x - p.x, q.z - p.z).length()
				if d < bd:
					bd = d
					best = q
	return best


func _build_bounds() -> void:
	for spec in [[Vector3(0, 2, AREA.end.y - 3.0), Vector3(130, 6, 1)], [Vector3(0, 2, AREA.position.y + 1.0), Vector3(130, 6, 1)],
			[Vector3(AREA.position.x + 3.0, 2, AREA.get_center().y), Vector3(1, 6, 90)], [Vector3(AREA.end.x - 3.0, 2, AREA.get_center().y), Vector3(1, 6, 90)]]:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec[1]
		cs.shape = bs
		b.add_child(cs)
		add_child(b)
		b.position = spec[0]


# ----------------------------------------------------------- interface pour la créature (Creature.nav)
func nav_path(_from: Vector3, to: Vector3) -> PackedVector3Array:
	return PackedVector3Array([to])


func random_point(near: Vector3, max_tiles: int) -> Vector3:
	var r := float(max_tiles) * 2.8
	var p := near + Vector3(randf_range(-r, r), 0, randf_range(-r, r))
	p.y = floor_y(p)
	return p


func has_los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	if player != null:
		q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func obstacles() -> Array:
	return trunks_near(creature.global_position)


func on_noise(pos: Vector3, radius: float) -> void:
	for h in hunters:
		(h as Hunter).hear(pos, radius)
	if creature != null and creature.visible:
		creature.hear(pos, radius)


# ================================================================== route et poteau
## La D 47 : enrobé bombé aux bords grignotés, marquage usé, accotements de gravier (terrain), herbe sèche, la ligne
## électrique sur poteaux en bois ; la caméra des ravisseurs est sanglée sur le poteau du chemin (POLE).
func _build_road_and_pole() -> void:
	_build_asphalt()
	_build_power_line()
	_build_verge_grass()
	var pole_pos := POLE
	B.box(self, Vector3(0.08, 0.08, 1.6), pole_pos + Vector3(0, 6.6, 0.6), B.color_mat(Color(0.25, 0.25, 0.25), 0.5, 0.8), false)
	B.box(self, Vector3(0.3, 0.1, 0.5), pole_pos + Vector3(0, 6.55, 1.35), B.color_mat(Color(0.2, 0.2, 0.2), 0.5, 0.8), false)
	var sodium := B.spot(self, pole_pos + Vector3(0, 6.45, 1.35), pole_pos + Vector3(0, 0, 4.0), Color(1.0, 0.62, 0.3), 3.0, 18.0, 55.0, true)
	sodium.light_volumetric_fog_energy = 2.5
	Game.add_flare(sodium, 1.4, 1.3)
	var mount_y := 4.6
	var r := POLE_R
	# son alimentation : un câble noir qui descend de la ligne, agrafé au poteau
	var cable := B.cylinder(self, 0.007, 0.007, 2.55, pole_pos + Vector3(0.03, mount_y + 1.42, r + 0.008), B.color_mat(Color(0.03, 0.03, 0.03), 0.5), false, 6)
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var steel := B.color_mat(Color(0.22, 0.22, 0.23), 0.45, 0.85)
	for dy in [-0.075, -0.01]:
		B.cylinder(self, r + 0.008, r + 0.008, 0.022, pole_pos + Vector3(0, mount_y + dy, 0), steel, false, 16)
	var face := Vector3(0, 0, 1)
	var watch_path := (Vector3(0, 1.0, -30.0) - (pole_pos + Vector3(0, mount_y, r))).normalized()
	pole_cam = SecurityCamera.create(self, pole_pos + Vector3(0, mount_y, r) + face * SecurityCamera.ARM, watch_path)
	pole_cam.attach_wall(pole_pos + Vector3(0, mount_y, r), face)
	pole_cam.pivot.global_basis = Basis.looking_at(Vector3(-1.0, -0.15, -0.35).normalized(), Vector3.UP)


## Profil en travers de l'enrobé (bombé pour que l'eau s'écoule) : hauteur à |dz| / demi-largeur.
const ROAD_PROFILE := [[0.0, 0.045], [0.6, 0.038], [0.93, 0.025], [1.0, 0.008]]
const ROAD_HALF := 3.45


func _road_y(f: float) -> float:
	f = absf(f)
	for i in ROAD_PROFILE.size() - 1:
		var a: Array = ROAD_PROFILE[i]
		var b: Array = ROAD_PROFILE[i + 1]
		if f <= float(b[0]):
			return lerpf(a[1], b[1], (f - float(a[0])) / (float(b[0]) - float(a[0])))
	return 0.008


func _build_asphalt() -> void:
	var en := FastNoiseLite.new()
	en.seed = 12
	en.frequency = 0.3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fs := [-1.0, -0.93, -0.6, 0.0, 0.6, 0.93, 1.0]
	var x0 := -160
	var n := 320
	for i in n + 1:
		var x := float(x0 + i)
		# bords grignotés : l'enrobé s'effrite dans le gravier, différemment de chaque côté
		var e_n := en.get_noise_2d(x, 0.0) * 0.16 + en.get_noise_2d(x * 3.1, 9.0) * 0.07
		var e_s := en.get_noise_2d(x, 40.0) * 0.16 + en.get_noise_2d(x * 3.1, 49.0) * 0.07
		var patch := 0.92 + en.get_noise_2d(x * 0.15, 80.0) * 0.12  # rapiéçages plus sombres, usure plus claire
		for f: float in fs:
			var e := e_n if f < 0.0 else e_s
			var dz := f * ROAD_HALF + (e * signf(f) if absf(f) == 1.0 else e * signf(f) * 0.35 if absf(f) > 0.9 else 0.0)
			var dirt := 0.6 if absf(f) == 1.0 else 0.8 if absf(f) > 0.9 else 1.0
			st.set_color(Color(dirt * patch, dirt * patch * 0.97, dirt * patch * 0.9))
			st.set_uv(Vector2(x, ROAD_Z + dz))
			st.add_vertex(Vector3(x, _road_y(f), ROAD_Z + dz))
	var w := fs.size()
	for i in n:
		for j in w - 1:
			var a := i * w + j
			st.add_index(a)
			st.add_index(a + w)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(a + w)
			st.add_index(a + w + 1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Route"
	mi.mesh = st.commit()
	var mat := (B.mat("asphalt_02", 1.0, {"color": Color(0.4, 0.4, 0.4), "roughness": 0.45, "triplanar": false, "world": false}) as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.uv1_scale = Vector3(0.25, 0.25, 1.0)
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	add_child(mi)
	# marquage : axe discontinu (3 m / 10 m), lignes de rive (3 m / 3,5 m) ; peinture usée, rétroréfléchissante
	var ms := SurfaceTool.new()
	ms.begin(Mesh.PRIMITIVE_TRIANGLES)
	for line: Array in [[0.0, 0.12, 13.0], [-3.0, 0.15, 6.5], [3.0, 0.15, 6.5]]:
		var zc: float = line[0]
		var half_w: float = line[1] * 0.5
		var step: float = line[2]
		var y := _road_y(zc / ROAD_HALF) + 0.005
		var x := -160.0 + (step * 0.37 if zc > 0.0 else 0.0)
		while x < 157.0:
			var q := [Vector3(x, y, ROAD_Z + zc - half_w), Vector3(x + 3.0, y, ROAD_Z + zc - half_w),
				Vector3(x + 3.0, y, ROAD_Z + zc + half_w), Vector3(x, y, ROAD_Z + zc + half_w)]
			var uv := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
			for k in [0, 1, 2, 0, 2, 3]:
				ms.set_normal(Vector3.UP)
				ms.set_uv(uv[k])
				ms.add_vertex(q[k])
			x += step
	var marks := MeshInstance3D.new()
	marks.name = "Marquage"
	marks.mesh = ms.commit()
	marks.material_override = Roadside.retro("res://assets/gen/road_paint.png", 2.5, false, false, Color(0.82, 0.82, 0.78))
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marks)


## La ligne électrique le long de la route, côté forêt : poteaux en bois avec traverse et isolateurs, trois fils qui
## pendent entre deux poteaux. Le poteau du chemin (POLE) est celui de la caméra.
func _build_power_line() -> void:
	var others := ["bolt", "cap", "connection", "fastener", "fuse", "insulator", "nail", "nut", "pole", "ring", "support",
		"transformer", "preset_01", "preset_03"]
	var arms := []
	for k in range(-4, 5):
		var p := Vector3(POLE.x + k * POLE_STEP, 0, POLE.z)
		var pole := B.model(self, "modular_electricity_poles", Vector3(p.x, floor_y(p) - 0.05, p.z), 90.0 + sin(k * 1.7) * 4.0,
			{"scale": 1.35, "remove": others})
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = POLE_R + 0.02
		cyl.height = 6.0
		cs.shape = cyl
		var sb := StaticBody3D.new()
		sb.add_child(cs)
		pole.add_child(sb)
		sb.position = Vector3(0, 3.0, 0)
		var arm := AABB()
		for mi: MeshInstance3D in pole.find_children("*", "MeshInstance3D", true, false):
			if String(mi.name).begins_with("preset_02_connection_large") or String(mi.get_parent().name).begins_with("preset_02_connection_large"):
				arm = mi.global_transform * mi.get_aabb()
		arms.append(arm)
	var spans := []
	for k in arms.size() - 1:
		var a: AABB = arms[k]
		var b: AABB = arms[k + 1]
		for o in [-1.0, 0.0, 1.0]:
			var pa := Vector3(a.get_center().x, a.end.y - 0.04, a.get_center().z + o * (a.size.z * 0.5 - 0.12))
			var pb := Vector3(b.get_center().x, b.end.y - 0.04, b.get_center().z + o * (b.size.z * 0.5 - 0.12))
			spans.append([pa, pb, 0.55 + absf(o) * 0.06])
	var wires := MeshInstance3D.new()
	wires.name = "Fils"
	wires.mesh = _wire_mesh(spans, 0.016)
	var wm := StandardMaterial3D.new()
	# câbles alu nus : ils accrochent la lampe à sodium et le faisceau
	wm.albedo_color = Color(0.55, 0.55, 0.53)
	wm.roughness = 0.5
	wm.metallic = 0.3
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	wires.material_override = wm
	wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wires)


## Des fils (tubes à 6 faces) qui pendent en chaînette entre deux points : [[a, b, flèche], ...].
func _wire_mesh(spans: Array, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 24
	var base := 0
	for sp: Array in spans:
		var a: Vector3 = sp[0]
		var b: Vector3 = sp[1]
		var sag: float = sp[2]
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		var up := side.cross(dir).normalized()
		var ring := []
		for j in 6:
			ring.append(side * cos(j * TAU / 6.0) + up * sin(j * TAU / 6.0))
		for i in seg + 1:
			var t := float(i) / seg
			var c := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
			for v: Vector3 in ring:
				st.set_normal(v)
				st.add_vertex(c + v * radius)
		for i in seg:
			for j in 6:
				var i0 := base + i * 6 + j
				var i1 := base + i * 6 + (j + 1) % 6
				st.add_index(i0)
				st.add_index(i0 + 6)
				st.add_index(i1)
				st.add_index(i1)
				st.add_index(i0 + 6)
				st.add_index(i1 + 6)
		base += (seg + 1) * 6
	return st.commit()


## L'herbe sèche des bas-côtés (novembre) : touffes instanciées, denses contre l'enrobé, qui s'éclaircissent sous les
## arbres ; jamais sur le chemin. Par tronçons de 30 m (les tronçons hors de vue ne sont pas dessinés).
func _build_verge_grass() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var dx := Vector3(cos(a), 0, sin(a)) * 0.36
		var q := [-dx, dx, dx + Vector3(0, 0.6, 0), -dx + Vector3(0, 0.6, 0)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[idx])
			st.add_vertex(q[idx])
	var tuft := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/road_grass.gdshader")
	mat.set_shader_parameter("tex", load("res://assets/gen/road_grass.png"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	var chunks := {}
	for side in [-1.0, 1.0]:
		for i in 3400:
			var x := rng.randf_range(-105.0, 105.0)
			var d := 3.3 + pow(rng.randf(), 1.5) * 4.4
			var p := Vector3(x, 0, ROAD_Z + side * d)
			var s := rng.randf_range(0.55, 1.2) * (0.65 if d < 3.8 else 1.0)
			var hue := rng.randf()
			var yaw := rng.randf() * TAU
			var tall := rng.randf_range(0.8, 1.35)
			if _path_dist(p) < 0.25 or (d > 6.0 and rng.randf() < 0.5):
				continue
			p.y = floor_y(p) - 0.03
			var key := int(floor(x / 30.0)) * 2 + (1 if side > 0.0 else 0)
			if not chunks.has(key):
				chunks[key] = []
			var col := Color(1.0, 1.0, 1.0).lerp(Color(0.62, 0.7, 0.5), hue * hue) * rng.randf_range(0.75, 1.0)
			(chunks[key] as Array).append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * tall, s)), p), col])
	for key in chunks:
		var items: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = tuft
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i][0])
			mm.set_instance_color(i, items[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 80.0
		add_child(mmi)


# ================================================================== la caméra de la victime (session 13)
func _build_cam13(holder: Node3D) -> void:
	cam13 = holder
	var body := Node3D.new()
	holder.add_child(body)
	body.rotation_degrees = Vector3(0, 35, 82)
	var black := B.color_mat(Color(0.03, 0.03, 0.035), 0.35, 0.4)
	B.box(body, Vector3(0.065, 0.1, 0.032), Vector3(0, 0.05, 0), black, false)
	B.cylinder(body, 0.016, 0.016, 0.012, Vector3(0, 0.075, 0.021), B.color_mat(Color(0.02, 0.02, 0.025), 0.1, 0.6), false, 16, Vector3(90, 0, 0))
	B.box(body, Vector3(0.05, 0.012, 0.02), Vector3(0, 0.02, -0.022), B.color_mat(Color(0.2, 0.2, 0.22), 0.4, 0.8), false)
	B.decal(holder, "res://assets/gen/leaf_litter.png", Vector3(0, 0.2, 0), Vector3.UP, 0.7, 0.7, 0.5)
	# sa diode de batterie faible clignote encore, faiblement, dans les feuilles
	var led := B.omni(holder, Vector3(0, 0.06, 0), Color(1.0, 0.1, 0.05), 0.12, 0.7)
	var dot := B.cylinder(body, 0.004, 0.004, 0.003, Vector3(0.02, 0.09, 0.017), B.emissive(Color(1.0, 0.08, 0.05), 5.0, true), false, 8, Vector3(90, 0, 0))
	var blink := create_tween().set_loops()
	blink.tween_callback(func() -> void:
		led.visible = true
		dot.visible = true)
	blink.tween_interval(0.12)
	blink.tween_callback(func() -> void:
		led.visible = false
		dot.visible = false)
	blink.tween_interval(1.9)
	var it := Interactable.create(holder, Vector3(0, 0.08, 0), Vector3(0.5, 0.3, 0.5), "Ramasser la caméra", Callable())
	it.on_use = func() -> void:
		it.queue_free()
		holder.visible = false
		_play_cam13()


## Théo ramasse la caméra et relit son dernier fichier sur le petit écran : la victime de la session 13 traverse
## cette même forêt, trouve la cabane, voit les lumières du camp... puis des phares, un moteur, la fin.
## (La vidéo est rendue en direct depuis le décor : quatre plans, la caméra suit les vrais sentiers.)
func _play_cam13() -> void:
	player.control_enabled = false
	cutscene = true
	Sound.play("pickup", -8.0, 0.9)
	Game.hud.say("Une caméra... comme la mienne. BWC-7, série 0402. Il reste un fichier.", 3.4)
	await wait(1.0)
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.audio_listener_enable_3d = false
	add_child(vp)
	var vcam := Camera3D.new()
	vcam.fov = 78.0
	vcam.far = 80.0
	vcam.cull_mask = 1 | 2
	# sa caméra filmait en mode nuit (infrarouge) : image noir et blanc, bien plus claire que la nôtre
	var e := (env as Environment).duplicate() as Environment
	e.volumetric_fog_enabled = false
	e.fog_density = 0.035
	e.ambient_light_energy *= 5.0
	e.tonemap_exposure *= 2.6
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.0
	e.adjustment_contrast = 1.25
	vcam.environment = e
	vp.add_child(vcam)
	var vlamp := SpotLight3D.new()
	vlamp.spot_range = 22.0
	vlamp.spot_angle = 38.0
	vlamp.light_energy = 3.0
	vcam.add_child(vlamp)
	var osd := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = 18
	ls.font_color = Color(1, 1, 1, 0.9)
	ls.outline_size = 2
	ls.outline_color = Color.BLACK
	osd.label_settings = ls
	osd.position = Vector2(10, 8)
	vp.add_child(osd)
	# la caméra en main, écran retourné vers Théo
	var dev := Node3D.new()
	player.cam.add_child(dev)
	dev.position = Vector3(0.0, 0.004, -0.17)
	dev.rotation_degrees = Vector3(4, 0, 0)
	var shell := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.19, 0.115, 0.03)
	shell.mesh = bm
	shell.material_override = B.color_mat(Color(0.03, 0.03, 0.035), 0.35, 0.4)
	dev.add_child(shell)
	var scr := StandardMaterial3D.new()
	scr.albedo_color = Color.BLACK
	scr.emission_enabled = true
	scr.emission_texture = vp.get_texture()
	scr.emission_energy_multiplier = 1.1
	var lcd := B.quad(dev, Vector2(0.168, 0.0945), Vector3(0, 0, 0.0155), scr)
	lcd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# son trajet, en quatre plans (la caméra coupe entre deux fichiers) : sur le chemin de la cabane, dedans devant la
	# radio, sur le chemin du camp, puis il court vers les lumières. Il marche SUR les sentiers (ceux du terrain).
	var h := hut.global_position
	var c := desk.global_position
	var to_hut := _branch(hut.global_transform * Vector3(1.45, 0, 3.4))
	var to_camp := _branch(c)
	var radio := hut.find_child("CBRadio", true, false) as Node3D
	var rp := radio.global_position + Vector3(0, 0.08, 0) if radio != null else h + Vector3(0, 0.9, 0)
	var in_hut := rp + hut.global_basis * Vector3(0.12, 0.5, 0.72)
	# [début (s), chemin (vide = plan fixe), avancée de, à (fraction du chemin), ce qu'il regarde, heure (s après 5 h), allure]
	var plans := [[0.0, to_hut, 0.18, 0.86, h + Vector3(0, 1.4, 0), 31 * 60 + 12, 1.0], [6.5, [], 0.0, 0.0, rp, 33 * 60 + 41, 0.0],
		[10.5, to_camp, 0.03, 0.4, c + Vector3(0, 1.0, 0), 37 * 60 + 5, 1.0], [15.0, to_camp, 0.4, 0.78, c + Vector3(0, 1.0, 0), 37 * 60 + 9, 2.2]]
	var end_t := 19.5
	# la vidéo date d'il y a deux semaines : ni les hommes au masque ni le drone de cette nuit ne doivent y passer
	var now_only := []
	for who: Node in hunters + ([drone] if drone != null and is_instance_valid(drone) else []):
		for gi: GeometryInstance3D in who.find_children("*", "GeometryInstance3D", true, false):
			now_only.append([gi, gi.layers])
			gi.layers = 1 << 9
	var pant := Sound.loop("breath_heavy_loop", -16.0, "UI")
	var lines := [[0.4, "(essoufflé) ...je suis sorti. Je suis dehors. Il fait nuit noire..."], [3.8, "Une cabane, là... Il y a peut-être quelqu'un."],
		[7.0, "Une radio. Elle est morte... Faut une batterie."], [11.0, "De la lumière, là-bas... un groupe électrogène. C'est leur camp. Ils doivent en avoir une."],
		[15.6, "(il court) Un moteur... des phares... non — NON —"]]
	var li := 0
	var t := 0.0
	var shown := -1
	var said := -1
	while t < end_t:
		await ticked
		t += get_process_delta_time()
		var k := plans.size() - 1
		while k > 0 and t < float(plans[k][0]):
			k -= 1
		var pl: Array = plans[k]
		var t0: float = pl[0]
		var t1: float = plans[k + 1][0] if k + 1 < plans.size() else end_t
		var w := clampf((t - t0) / (t1 - t0), 0.0, 1.0)
		if k != shown:
			# changement de fichier : image qui saute, grésillement (le dernier plan suit le précédent sans coupure)
			if shown >= 0 and k != 3:
				Sound.play("glitch_0", -14.0, 1.2, "UI")
				scr.emission_energy_multiplier = 0.15
				create_tween().tween_property(scr, "emission_energy_multiplier", 1.1, 0.3)
			shown = k
		var path: Array = pl[1]
		var run: float = pl[6]
		var pos: Vector3
		var look: Vector3 = pl[4]
		if path.is_empty():
			pos = in_hut + Vector3(sin(t * 1.3) * 0.02, sin(t * 1.9) * 0.015, 0)
		else:
			var f := lerpf(pl[2], pl[3], w)
			pos = _along(path, f)
			var ahead := _along(path, f + 0.2) + Vector3(0, 1.4, 0)
			look = ahead.lerp(look, 0.3 + 0.4 * w)
			if k == 3 and w > 0.65:
				look = look.lerp(c + Vector3(-4, 1.0, -4), (w - 0.65) / 0.35)
			pos.y += 1.5 + absf(sin(t * 7.0 * run)) * 0.04 * run
			pos += vcam.global_basis.x * sin(t * 7.0 * run) * 0.03 if vcam.is_inside_tree() else Vector3.ZERO
		if (look - pos).length() > 0.2:
			vcam.global_transform = Transform3D(Basis.looking_at((look - pos).normalized(), Vector3.UP), pos)
		var clock := float(pl[5]) + t - t0
		osd.text = "BWC-7   SN 0402   ▶ LECTURE   IR\n03/11/2026   05:%02d:%02d" % [int(clock / 60.0), int(clock) % 60]
		if li < lines.size() and t >= float(lines[li][0]):
			Game.hud.say(lines[li][1], 3.4, "Caméra 0402")
			li += 1
		# sa lampe infrarouge, plus faible dans la cabane (sinon tout est blanc) ; les phares du van, puis plus rien
		vlamp.light_energy = 0.6 if path.is_empty() else 3.0
		if t > end_t - 1.5:
			vlamp.light_energy = 3.0 + (t - end_t + 1.5) * 30.0
		# test (--surfacetest=cam) : où est sa caméra par rapport aux sentiers, et ce qu'elle filme
		if Game.args.has("surfacetest") and int(t) != said:
			said = int(t)
			print("CAM13 t=%d plan=%d pos=%s hors sentier=%.2f m" % [said, k, pos.snapped(Vector3.ONE * 0.1), maxf(_path_dist(pos), 0.0)])
			if Game.args.has("shot") and said % 2 == 1:
				vp.get_texture().get_image().save_png("%s_video_%02d.png" % [str(Game.args["shot"]), said])
	if is_instance_valid(pant):
		pant.queue_free()
	for gl: Array in now_only:
		if is_instance_valid(gl[0]):
			(gl[0] as GeometryInstance3D).layers = gl[1]
	Sound.play("glitch_0", -6.0)
	scr.emission_texture = null
	scr.emission = Color(0.6, 0.6, 0.6)
	await wait(0.8)
	dev.queue_free()
	vp.queue_free()
	player.control_enabled = true
	cutscene = false
	Game.hud.say("...Une cabane avec une radio. Il lui faut une batterie. Et leur camp en a une.", 4.0)
	if stage == "start":
		Game.hud.objective("La cabane du garde forestier (à gauche du sentier)")


## Près de la plaque « S·13 », on entend gratter dessous. (La créature, déjà.)
func _s13_scratch() -> void:
	if _s13_heard or stage != "start":
		return
	_s13_heard = true
	Sound.play_at(Sound.variant("claw", 4), s13.global_position + Vector3(0, -0.3, 0), 0.0, 0.8, 3.0, 18.0, null, "Creature")
	await wait(0.9)
	Sound.play_at(Sound.variant("claw", 4), s13.global_position + Vector3(0, -0.3, 0), -3.0, 0.75, 3.0, 18.0, null, "Creature")
	await wait(1.6)
	Game.hud.say("...Ça gratte. Là-dessous.", 2.4)


# ================================================================== pièges à loup
func _check_traps() -> void:
	if _trapped >= 0:
		_struggle()
		return
	if not player.control_enabled:
		return
	for i in traps.size():
		var tr: Array = traps[i]
		if tr[1]:
			continue
		var p := (tr[0] as Node3D).global_position
		if Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length() < 0.33:
			_spring_trap(i)
			return


## Le piège se referme sur la jambe : claquement, cri, sang. Il faut marteler E pour écarter les mâchoires
## (la barre retombe si on lâche). Le bruit attire les hommes au masque.
func _spring_trap(i: int) -> void:
	traps[i][1] = true
	var p := (traps[i][0] as Node3D).global_position
	Sound.play_at("trap_snap", p + Vector3(0, 0.2, 0), 6.0, 1.0, 5.0, 60.0)
	Game.shake(1.6)
	Game.flash(0.5)
	Game.glitch(0.5, false)
	player.control_enabled = false
	player.limp = minf(0.7, player.limp + 0.4)
	player.set_look(player.yaw, deg_to_rad(-55.0))
	B.decal(self, "res://assets/gen/decal_blood_pool.png", p + Vector3(0, 0.1, 0), Vector3.UP, 0.6, 0.6, 0.3, Color(1, 1, 1, 0.85))
	on_noise(p, 30.0)
	Game.hud.say("AAAH ! Putain... ma jambe !", 2.4)
	_trapped = i
	_trap_prog = 0.0
	await wait(0.8)
	Game.hud.hint("Martèle [E] pour écarter les mâchoires du piège", 5.0)


func _struggle() -> void:
	var dt := get_process_delta_time()
	_trap_prog = maxf(0.0, _trap_prog - dt * 0.22)
	if Input.is_action_just_pressed("interact"):
		_trap_prog += 0.09
		Game.shake(0.25)
		Sound.play("flashlight_tap_0", -16.0, randf_range(0.5, 0.7))
	Game.hud.hold(maxf(_trap_prog, 0.001))
	if _trap_prog >= 1.0:
		var p := (traps[_trapped][0] as Node3D).global_position
		_trapped = -1
		Game.hud.hold(0.0)
		Sound.play_at("trap_snap", p + Vector3(0, 0.2, 0), -6.0, 0.7, 3.0, 20.0)
		player.control_enabled = true
		Game.hud.say("...Ça saigne. Je peux encore marcher. Un peu.", 3.0)


# ================================================================== cailloux
## Un tas de galets de calcaire clair (sur les feuilles sombres, on les voit dans le faisceau de la lampe).
func _build_stones(holder: Node3D) -> void:
	var mats := [B.mat("hacked_concrete", 0.25, {"color": Color(0.52, 0.5, 0.46), "roughness": 1.0}),
		B.mat("hacked_concrete", 0.25, {"color": Color(0.4, 0.39, 0.36), "roughness": 1.0}),
		B.mat("hacked_concrete", 0.25, {"color": Color(0.58, 0.54, 0.47), "roughness": 1.0})]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(holder.name))
	for k in 7:
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.035, 0.07)
		sm.height = sm.radius * 2.0
		sm.radial_segments = 7
		sm.rings = 4
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = mats[k % mats.size()]
		holder.add_child(mi)
		var flat := rng.randf_range(0.45, 0.7)
		mi.scale = Vector3(rng.randf_range(0.9, 1.5), flat, rng.randf_range(0.7, 1.2))
		mi.rotation = Vector3(rng.randf_range(-0.25, 0.25), rng.randf() * TAU, rng.randf_range(-0.25, 0.25))
		# un peu enfoncés dans la terre, éparpillés
		mi.position = Vector3(rng.randf_range(-0.24, 0.24), sm.radius * flat * 0.45, rng.randf_range(-0.24, 0.24))
	var it := Interactable.create(holder, Vector3(0, 0.1, 0), Vector3(0.5, 0.3, 0.5), "Ramasser des cailloux", Callable())
	it.on_use = func() -> void:
		it.queue_free()
		holder.visible = false
		stones += 3
		Sound.play("pickup", -10.0, 0.8)
		Game.hud.pickup("Cailloux (%d)" % stones)
		if stones <= 3:
			Game.hud.hint("[G] ou [clic droit]  lancer un caillou : sur le drone, ou loin de toi pour faire diversion", 6.0)
	piles.append(holder)


## Lancer : si le drone est près du centre de l'image, le caillou part droit sur lui (on vise à l'œil, pas au pixel).
func _throw_stone() -> void:
	stones -= 1
	var rb := RigidBody3D.new()
	rb.mass = 0.25
	rb.collision_layer = 0
	rb.collision_mask = 1 | Drone.LAYER
	rb.contact_monitor = true
	rb.max_contacts_reported = 2
	rb.continuous_cd = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.045
	cs.shape = sh
	rb.add_child(cs)
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.07
	sm.radial_segments = 6
	sm.rings = 3
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = B.mat("hacked_concrete", 0.3, {"color": Color(0.4, 0.39, 0.36), "roughness": 1.0})
	rb.add_child(mi)
	add_child(rb)
	var cam := player.cam
	var fwd := -cam.global_basis.z
	var start := cam.global_position + fwd * 0.4 + cam.global_basis.x * 0.12 - Vector3(0, 0.1, 0)
	rb.global_position = start
	var vel := fwd * 16.0 + Vector3(0, 2.2, 0) + Vector3(player.velocity.x, 0, player.velocity.z)
	if drone != null and is_instance_valid(drone) and not drone.down:
		var to := drone.global_position - cam.global_position
		if to.length() < 28.0 and fwd.dot(to.normalized()) > cos(deg_to_rad(16.0)):
			# trajectoire balistique qui l'atteint (en tenant compte de sa vitesse)
			var tt := to.length() / 17.0
			var aim := drone.global_position + drone.vel * tt
			vel = (aim - start) / tt + Vector3(0, 0.5 * 9.8 * tt, 0)
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-4, 4), randf_range(-10, 10))
	Sound.play("flashlight_tap_0", -14.0, 0.6)
	var done := [false]
	rb.body_entered.connect(func(b: Node) -> void:
		if done[0]:
			return
		done[0] = true
		if drone != null and is_instance_valid(drone) and b == drone.body:
			drone.hit()
		else:
			Sound.play_at(Sound.variant("rock_hit", 3), rb.global_position, 0.0, randf_range(0.9, 1.1), 4.0, 35.0)
			# le caillou qui retombe attire les hommes au masque (ils ne l'ont pas vu partir)
			on_noise(rb.global_position, 24.0))
	await wait(6.0)
	if is_instance_valid(rb):
		rb.queue_free()


# ================================================================== la cabane du garde forestier
## La cabane de chasse : une entrée (la porte arrachée), une cloison percée d'un passage, et la pièce où David
## Roche (session 13) s'est caché : la radio sur la table, sa carte annotée au mur, le lit de camp.
## Repère de la cabane : plancher à y = 0,16 ; pièce x de -2,1 à 0,55 ; entrée x de 0,75 à 2,25 ; z de -1,25 à 1,18 ;
## porte côté +z (x de 1,05 à 1,85) ; passage dans la cloison (x = 0,64) pour z de -0,9 à -0,1.
## Chaque meuble, chaque objet est un élément déplaçable à part (_sub) : il suit la cabane, ou se déplace seul.
func _build_hut(holder: Node3D) -> void:
	hut = holder
	B.model(holder, "sf:log_cabin", Vector3.ZERO, 0.0, {"height": 3.7, "remove": ["Door"], "collide": "mesh"})
	var inside := Node3D.new()
	holder.add_child(inside)
	inside.name = "Inside"
	var fl := 0.16
	var top := 0.75  ## hauteur de la table
	# --- la pièce : la table contre le mur du fond, la radio, la chaise tirée
	B.model(_sub(inside, "hut_table", Vector3(-1.3, fl, -0.92)), "small_wooden_table_01", Vector3.ZERO, 0.0, {"height": 0.75, "collide": true})
	var rad := _sub(inside, "hut_radio", Vector3(-1.25, fl + top, -1.02))
	var radio := B.model(rad, "sf:cb_radio", Vector3.ZERO, 0.0, {"width": 0.24})
	radio.name = "CBRadio"
	var label := StandardMaterial3D.new()
	label.albedo_texture = load("res://assets/gen/cb_label.png")
	B.quad(rad, Vector2(0.14, 0.05), Vector3(0.25, 0.002, 0.18), label, Vector3(-90, 0, 0))
	# les câbles qui pendent au bord de la table, et la place de la batterie dessous
	for k in 2:
		var wire := B.cylinder(rad, 0.004, 0.004, 0.55, Vector3(0.55 + k * 0.03, -0.27, 0.36), B.color_mat(Color(0.7, 0.05, 0.05) if k == 0 else Color(0.05, 0.05, 0.05), 0.5), false, 5)
		wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var slot := Node3D.new()
	rad.add_child(slot)
	slot.name = "BatterySlot"
	slot.position = Vector3(0.75, -top, 0.07)
	var it := Interactable.create(rad, Vector3(0, 0.12, 0.02), Vector3(0.6, 0.4, 0.6), "La radio", _use_radio)
	it.name = "RadioUse"
	B.model(_sub(inside, "hut_chair", Vector3(-1.4, fl, -0.25), 165.0), "dining_chair_02", Vector3.ZERO, 0.0, {"height": 0.9, "collide": true})
	B.model(_sub(inside, "hut_cans", Vector3(-1.78, fl + top, -0.82)), "russian_food_cans_01", Vector3.ZERO, 0.0, {"height": 0.11})
	B.model(_sub(inside, "hut_lamp", Vector3(-0.95, fl + top, -0.78), 70.0), "sf:flashlight_dead", Vector3.ZERO, 0.0, {"depth": 0.22})
	# sa carte, punaisée au-dessus de la table
	var map_mat := StandardMaterial3D.new()
	map_mat.albedo_texture = load("res://assets/gen/hut_map.png")
	map_mat.roughness = 0.95
	var map := _sub(inside, "hut_map", Vector3(-1.3, fl + 1.42, -1.235))
	B.quad(map, Vector2(0.64, 0.48), Vector3.ZERO, map_mat)
	Interactable.create(map, Vector3(0, 0, 0.085), Vector3(0.7, 0.55, 0.2), "La carte", _read_map)
	B.model(_sub(inside, "hut_clock", Vector3(-0.3, fl + 1.55, -1.24)), "wall_clock", Vector3.ZERO, 0.0, {"height": 0.26})
	# le lit de camp le long du mur, un sac de couchage dessus
	var bed := _sub(inside, "hut_bed", Vector3(-1.05, fl, 0.72), 90.0)
	B.model(bed, "old_bed_frame", Vector3.ZERO, 0.0, {"depth": 1.9, "collide": true})
	B.model(_sub(bed, "hut_bed_bag", Vector3(0.02, 0.42, -0.15), -10.0), "sf:sleeping_bag", Vector3.ZERO, 0.0, {"width": 1.6})
	B.model(_sub(inside, "hut_jerrycan", Vector3(-1.95, fl, -0.3), 80.0), "metal_jerrycan", Vector3.ZERO, 0.0, {"height": 0.45})
	# l'étagère contre la cloison : un bocal, des bouteilles
	var shelf := _sub(inside, "hut_shelf", Vector3(0.36, fl, 0.72), -90.0)
	B.model(shelf, "wooden_bookshelf_worn", Vector3.ZERO, 0.0, {"height": 1.55, "collide": true})
	B.model(_sub(shelf, "hut_jug", Vector3(-0.17, 1.55, 0)), "jug_01", Vector3.ZERO, 0.0, {"height": 0.22})
	# les bouteilles une par une (chacune se prend dans l'éditeur)
	var bottles := [["wine_bottles_01_bordeaux", 0.3, Vector3(0.07, 1.55, 0.03)], ["wine_bottles_01_alsace", 0.34, Vector3(0.16, 1.55, -0.04)],
		["wine_bottles_01_burgundy", 0.29, Vector3(0.26, 1.55, 0.02)]]
	for i in bottles.size():
		var b: Array = bottles[i]
		B.model(_sub(shelf, "hut_bottle_%d" % i, b[2], i * 40.0), "wine_bottles_01", Vector3.ZERO, 0.0, {"part": b[0], "height": b[1]})
	B.model(_sub(inside, "hut_light", Vector3(-0.8, 2.44 - 0.3, 0.1)), "caged_hanging_light", Vector3.ZERO, 0.0, {"height": 0.3})
	var webs := [Vector3(-2.0, 2.44, -1.15), Vector3(0.45, 2.44, 1.1), Vector3(-2.0, 2.44, 1.1), Vector3(2.15, 2.44, -1.15)]
	for i in webs.size():
		Props.cobweb(_sub(inside, "hut_web_%d" % i, webs[i] - Vector3(0, 0.48, 0)))
	# --- l'entrée : bois de chauffage contre le mur, bottes, pelle, bidon
	_woodpile(_sub(inside, "hut_wood", Vector3(2.08, fl, -0.45), 90.0), Vector3.ZERO, 0.36, 1.5, 0.95, 0.0)
	B.model(_sub(inside, "hut_boots", Vector3(2.0, fl, 0.9), 200.0), "rubber_boots", Vector3.ZERO, 0.0, {"height": 0.4})
	B.model(_sub(inside, "hut_spade", Vector3(0.85, fl, 1.05), 10.0), "rusted_spade_01", Vector3.ZERO, 0.0, {"height": 1.0})
	B.model(_sub(inside, "hut_jerrycan_2", Vector3(0.95, fl, -1.05), 20.0), "metal_jerrycan", Vector3.ZERO, 0.0, {"height": 0.45})
	# --- dehors : le gros tas de bûches contre le pignon, le billot et sa hache, un tonneau d'eau de pluie
	_woodpile(_sub(holder, "hut_wood_out", Vector3(-2.95, 0.0, -0.4), 90.0), Vector3.ZERO, 0.45, 2.2, 1.15, 0.0)
	var block := _sub(holder, "hut_block", Vector3(3.4, 0.0, 2.6))
	B.model(block, "tree_stump_01", Vector3.ZERO, 0.0, {"height": 0.45, "collide": true})
	B.model(_sub(block, "hut_axe", Vector3(-0.02, 0.36, 0), 30.0), "wooden_axe", Vector3.ZERO, 0.0, {"height": 0.7, "rot": Vector3(160, 0, 0)})
	B.model(_sub(holder, "hut_barrel", Vector3(-2.95, 0.0, 1.55)), "Barrel_01", Vector3.ZERO, 0.0, {"height": 0.9, "collide": true})
	B.model(_sub(holder, "hut_tyre", Vector3(3.1, 0.0, -1.0)), "old_tyre", Vector3.ZERO, 0.0, {"width": 0.65})
	B.model(_sub(holder, "hut_branches", Vector3(2.6, 0.0, -2.4), 40.0), "dry_branches_medium_01", Vector3.ZERO, 0.0, {"width": 1.2})


## Un tas de bûches rangées (base au sol, `length` le long de l'axe x local tourné de `yaw`), avec sa collision.
func _woodpile(parent: Node3D, pos: Vector3, depth: float, length: float, height: float, yaw: float) -> void:
	var pile := Node3D.new()
	parent.add_child(pile)
	pile.position = pos
	pile.rotation_degrees.y = yaw
	var bark := B.mat("pine_bark", 0.6, {"color": Color(0.55, 0.47, 0.38)})
	var cut := B.mat("pine_bark", 0.15, {"color": Color(1.5, 1.25, 0.95)})
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 100.0 + pos.z * 7.0)
	var r := 0.075
	var y := r
	while y < height - r * 0.5:
		var x := -length * 0.5 + r
		while x < length * 0.5 - r * 0.5:
			var rr := r * rng.randf_range(0.8, 1.15)
			var log_mi := B.cylinder(pile, rr, rr, depth * rng.randf_range(0.9, 1.05), Vector3(x, y, rng.randf_range(-0.03, 0.03)), bark, false, 7, Vector3(90, 0, 0))
			log_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			# bout scié, plus clair, côté visible (à l'opposé du mur)
			var face := B.cylinder(pile, rr * 0.92, rr * 0.92, 0.01, log_mi.position - Vector3(0, 0, log_mi.mesh.get("height") * 0.5 + 0.004), cut, false, 7, Vector3(90, 0, 0))
			face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			x += r * 2.0
		y += r * 1.75
	_solid(pile, Vector3(length, height, depth), Vector3(0, height * 0.5, 0))


func _solid(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)
	sb.position = pos


func _read_map() -> void:
	await read_document("La carte de la cabane", "[center][img=860]res://assets/gen/hut_map.png[/img][/center]", "paper")
	if stage in ["start", "battery"]:
		Game.hud.say("« D.R. »... David Roche. Le gars des avis de recherche. Il était ici avant moi.", 3.8)
		await wait(4.0)
		Game.hud.say("Leur camp, à l'est. « Batterie ? »... Il a eu la même idée que moi.", 3.6)


func _use_radio() -> void:
	if stage in ["chase", "done"]:
		return
	if battery_in:
		_radio_call()
		return
	if has_battery:
		has_battery = false
		battery_in = true
		Sound.play("pickup", -6.0, 0.7)
		_install_battery_visual()
		Game.hud.say("Les pinces... rouge sur le plus. Allez...", 2.6)
		await wait(2.0)
		_radio_power_on()
		Game.hud.objective("Appeler à l'aide (la radio)")
		var it := hut.find_child("RadioUse", true, false) as Interactable
		if it != null:
			it.prompt = "Appeler à l'aide"
		return
	Game.hud.say("Une radio CB... morte. Les câbles pendent : il lui faut une batterie de 12 volts.", 4.0)
	if stage == "start":
		stage = "battery"
		await wait(4.2)
		Game.hud.say("Leur camp... Ils doivent bien en avoir une.", 3.0)
		Game.hud.objective("Trouver une batterie 12 V (le camp des ravisseurs, à l'est)")


func _install_battery_visual() -> void:
	_build_battery_mesh(hut.find_child("BatterySlot", true, false) as Node3D)


func _radio_power_on() -> void:
	var radio := hut.find_child("CBRadio", true, false) as Node3D
	var at := radio.global_position + Vector3(0, 0.08, 0) if radio != null else hut.global_position
	_radio_glow = B.omni(self, at, Color(1.0, 0.55, 0.2), 0.3, 1.4)
	_radio_static = Sound.loop_at("radio_static_loop", radio if radio != null else hut, -10.0, 1.5, 12.0)
	Sound.play_at("ui_beep", at, -8.0, 0.8, 2.0, 10.0)


## Il appelle à l'aide... et c'est le direct qui répond. Le public a voté : on ouvre la trappe.
func _radio_call() -> void:
	stage = "chase"
	var it := hut.find_child("RadioUse", true, false) as Interactable
	if it != null:
		it.queue_free()
	player.control_enabled = false
	if is_instance_valid(_radio_static):
		_radio_static.volume_db = -4.0
	Game.hud.say("Allô ? Allô, quelqu'un m'entend ?", 2.6)
	await wait(3.0)
	Game.hud.say("À l'aide ! Je m'appelle Théo Marchand. Je suis dans une forêt, près d'une route... Il y a un camp, des caméras... et un truc. Un monstre.", 5.0)
	await wait(5.6)
	Sound.play("glitch_0", -6.0, 0.7)
	await wait(2.0)
	Game.hud.say("...On vous reçoit très bien, Théo.", 3.0, "Radio")
	await wait(3.3)
	Game.hud.say("Merci... Merci ! Envoyez quelqu'un, vite !", 2.6)
	await wait(3.0)
	Game.hud.say("Vous êtes en direct, Théo. Quatre mille trois cent douze personnes vous regardent.", 4.2, "Radio")
	await wait(4.6)
	Game.hud.say("Le public a voté.", 2.4, "Radio")
	await wait(2.8)
	Game.hud.say("...Ouvrez la trappe.", 2.4, "Radio")
	await wait(2.0)
	if is_instance_valid(_radio_static):
		Sound.fade(_radio_static, -60.0, 0.4, true)
	if is_instance_valid(_radio_glow):
		_radio_glow.queue_free()
	params = {"checkpoint": "chase", "drones": drones_left}
	Game.level_params = params
	_release_creature(false)


## La créature sort de la plaque « S·13 »... puis elle fonce. Les hommes au masque rentrent au van.
func _release_creature(quick: bool) -> void:
	stage = "chase"
	for h in hunters:
		(h as Hunter).leave()
	var at := s13.global_position
	Sound.play_at("lamp_break_0", at + Vector3(0, 0.3, 0), 2.0, 0.6, 8.0, 80.0)
	var lid := s13.find_child("Lid", true, false) as Node3D
	if lid != null:
		var tw := create_tween()
		tw.tween_property(lid, "position", lid.position + Vector3(1.2, 0.0, 0.6), 0.35)
		tw.parallel().tween_property(lid, "rotation_degrees:z", 70.0, 0.35)
	await wait(0.4 if quick else 0.8)
	Sound.play_at("creature_shriek", at + Vector3(0, 1.0, 0), 4.0, 1.0, 10.0, 90.0, null, "Creature")
	Game.glitch(0.6)
	if not quick:
		await wait(1.2)
		Game.hud.say("Non... non, non, non.", 2.0)
	creature.player = player
	creature.global_position = at
	creature.activate(Creature.State.CHASE)
	player.control_enabled = true
	player.stamina = 1.0
	Game.hud.objective("COURS. LA ROUTE.")
	await wait(1.0)
	Game.hud.say("Elle arrive... COURS !", 2.0)


# ================================================================== le camp des ravisseurs
func _build_camp() -> void:
	var c := Vector3(28, 0, -31)
	# la régie : bâche camouflage, table militaire, écrans, ordinateur, chaises
	desk = _obj("camp_desk", c, 0.0)
	B.model(_sub(desk, "camp_tarp", Vector3(0, 0, 0.2), 90.0), "sf:tarp", Vector3.ZERO, 0.0, {"width": 4.5})
	B.model(desk, "sf:military_furniture", Vector3(0, 0, 0), 0.0, {"part": "SM_MTable_001", "scale": 1.0, "collide": true})
	var top := 0.94
	feed = SecurityFeed.new()
	feed.cam_label = "DRONE 2"
	add_child(feed)
	_feed_mat = feed.screen_material(1.0)
	# les écrans : la face avant du modèle est son +X ; l'image est collée sur la dalle, tournée vers les chaises
	var mon1 := _sub(desk, "camp_screen_1", Vector3(-0.5, top, -0.25), -90.0)
	B.model(mon1, "sf:flat_tv", Vector3.ZERO, 0.0, {"height": 0.42})
	SecurityFeed.screen(mon1, Vector2(0.6, 0.33), Vector3(0.021, 0.235, 0), Vector3(0, 90, 0), _feed_mat)
	Interactable.create(mon1, Vector3(0.1, 0.24, 0), Vector3(0.25, 0.45, 0.7), "L'écran", func() -> void:
		if drone != null and is_instance_valid(drone) and not drone.down:
			Game.hud.say("C'est moi... vu d'en haut. Le drone. Ils me filment en ce moment même.", 3.6)
		else:
			Game.hud.say("Plus d'image. Le drone est par terre.", 2.6))
	var stream := StandardMaterial3D.new()
	stream.albedo_color = Color.BLACK
	stream.emission_enabled = true
	stream.emission_texture = load("res://assets/gen/screen_stream.png")
	stream.emission_energy_multiplier = 1.1
	var mon2 := _sub(desk, "camp_screen_2", Vector3(0.25, top, -0.3), -102.0)
	B.model(mon2, "sf:flat_tv", Vector3.ZERO, 0.0, {"height": 0.42})
	SecurityFeed.screen(mon2, Vector2(0.6, 0.33), Vector3(0.021, 0.235, 0), Vector3(0, 90, 0), stream)
	var lap_mat := StandardMaterial3D.new()
	lap_mat.albedo_color = Color.BLACK
	lap_mat.emission_enabled = true
	lap_mat.emission_texture = load("res://assets/gen/screen_stream.png")
	lap_mat.emission_energy_multiplier = 0.9
	var lap := _sub(desk, "camp_laptop", Vector3(0.85, top, 0.1), -35.0)
	Props.laptop(lap, Vector3.ZERO, 0.0, lap_mat)
	B.omni(desk, Vector3(0, top + 0.45, 0.35), Color(0.6, 0.7, 1.0), 0.4, 3.0)
	B.model(_sub(desk, "camp_chair_1", Vector3(-0.4, 0, 0.9), 180.0), "sf:military_furniture", Vector3.ZERO, 0.0, {"part": "SM_MChair_001", "scale": 1.0, "collide": true})
	B.model(_sub(desk, "camp_chair_2", Vector3(0.6, 0, 0.95), 160.0), "sf:military_furniture", Vector3.ZERO, 0.0, {"part": "SM_MChair_001", "scale": 1.0, "collide": true})
	var reg := _sub(desk, "camp_registre", Vector3(-0.95, top, 0.15), 15.0)
	B.box(reg, Vector3(0.22, 0.01, 0.3), Vector3(0, 0.005, 0), B.color_mat(Color(0.85, 0.83, 0.78), 0.9), false)
	Interactable.create(reg, Vector3(0, 0.06, 0), Vector3(0.35, 0.2, 0.4), "Le registre", func() -> void:
		await read_document("Registre des sessions",
			"[b]SESSIONS — 2026[/b]\n\n" +
			"01 — 14/02 — 1 sujet — 312 spectateurs — 2 h 10 — non retrouvé\n" +
			"04 — 03/05 — 2 sujets — 870 spectateurs — 3 h 02 — non retrouvés\n" +
			"09 — 22/08 — 1 sujet (R. Lebrun) — 2 140 spectateurs — 4 h 15 — non retrouvé\n" +
			"12 — 06/10 — 1 sujet (C. Meyer) — 2 980 spectateurs — 4 h 41 — non retrouvée\n" +
			"13 — 03/11 — 1 sujet (D. Roche, agent de sécurité) — 3 655 spectateurs — 5 h 02 — sorti à 05:51 — [i]récupéré au van[/i]\n" +
			"[b]14 — 14/11 — 4 sujets — EN COURS — 4 312 spectateurs[/b]\n\n" +
			"Recettes (dons) : 61 400 €\nProchaine étape : vote du public.", "typed")
		Game.hud.say("Les avis de recherche, sur les arbres... C'était eux. Personne ne les a jamais retrouvés.", 4.0))
	Interactable.create(lap, Vector3(0, 0.12, 0), Vector3(0.5, 0.3, 0.45), "L'ordinateur", func() -> void:
		await read_document("Le direct — session 14",
			"[b]● DIRECT — SESSION 14 — 4 312 spectateurs[/b]\n\n" +
			"[color=#7af]vlad_88[/color] [color=#5d7]50 €[/color] — fais-le passer par l'eau\n" +
			"[color=#7af]nightowl[/color] [color=#5d7]20 €[/color] — LÂCHE LA BÊTE\n" +
			"[color=#7af]k0rr[/color] [color=#5d7]100 €[/color] — coupe-lui la lumière lol\n" +
			"[color=#7af]m.b[/color] [color=#5d7]500 €[/color] — vote : LA RADIO\n" +
			"[color=#7af]lu_cie[/color] [color=#5d7]30 €[/color] — les 3 autres c'était trop court\n" +
			"[color=#7af]Dmitri[/color] [color=#5d7]250 €[/color] — plus long que la 13 svp\n\n" +
			"[b]PROCHAINE ÉTAPE — vote en cours :[/b]  « LA RADIO » 61 %  ·  « LA ROUTE » 39 %", "phone")
		Game.hud.say("« La radio »... Ils votent. Ils votent pour ce qui va m'arriver.", 3.6))
	# le van (le deuxième homme dort dedans)
	van = _obj("van", c + Vector3(5.5, 0, -5.0), 110.0)
	B.model(van, "sf:old_van", Vector3.ZERO, 0.0, {"width": 5.2, "collide": true})
	# le tableau des sujets, sur un chevalet
	board = _obj("camp_board", c + Vector3(-3.4, 0, 0.3), 70.0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_texture = load("res://assets/gen/board_subjects.png")
	bmat.roughness = 0.9
	B.box(board, Vector3(1.5, 1.06, 0.03), Vector3(0, 1.3, -0.02), B.color_mat(Color(0.25, 0.18, 0.12), 0.8), false)
	B.quad(board, Vector2(1.4, 0.98), Vector3(0, 1.3, 0.0), bmat)
	_solid(board, Vector3(1.5, 1.9, 0.15), Vector3(0, 0.95, -0.03))
	for k in [-0.55, 0.55]:
		B.cylinder(board, 0.02, 0.02, 1.9, Vector3(k, 0.95, -0.06), B.color_mat(Color(0.3, 0.25, 0.2), 0.8), false, 6)
	Interactable.create(board, Vector3(0, 1.3, 0.1), Vector3(1.4, 1.0, 0.3), "Le tableau", func() -> void:
		await read_document("Le tableau — session 14",
			"[b]SESSION 14 — 4 sujets[/b]   [i]« le public a choisi »[/i]\n\n" +
			"Sujet 1 — Maxime D., 24 ans — [color=#b33]✗[/color]\nSujet 2 — Inès F., 23 ans — [color=#b33]✗[/color]\n" +
			"Sujet 3 — Karim H., 25 ans — [color=#b33]✗[/color]\nSujet 4 — Théo M., 24 ans, agent de sécurité — [b]EN COURS[/b]\n\n" +
			"Pas d'intervention avant la sortie.\nLa bête se rappelle au sifflet.", "paper")
		Game.hud.say("Le public a choisi... Nous quatre. Comme des numéros.", 3.4))
	# le feu de camp : braises, fumée, lueur qui vacille (la seule chaleur ici)
	fire = _obj("camp_fire", c + Vector3(-1.5, 0, 6.0))
	_campfire(fire)
	# lampe de chantier sur trépied, braquée sur la régie
	work_light = _obj("camp_light", c + Vector3(-3.0, 0, 2.6), rad_to_deg(atan2(-3.0, 2.6)))
	B.model(work_light, "sf:work_light", Vector3.ZERO, 0.0, {"height": 1.6, "collide": true})
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.light_energy = 5.0
	lamp.spot_range = 14.0
	lamp.spot_angle = 50.0
	lamp.shadow_enabled = true
	lamp.light_volumetric_fog_energy = 1.8
	work_light.add_child(lamp)
	lamp.position = Vector3(0, 1.55, 0)
	lamp.rotation_degrees = Vector3(-22, 0, 0)
	Game.add_flare(lamp, 1.0, 1.0)
	# groupe électrogène qui ronfle
	generator = _obj("camp_generator", c + Vector3(-6.5, 0, -2.5), 30.0)
	B.model(generator, "sf:generator", Vector3.ZERO, 0.0, {"width": 0.75, "collide": true})
	Sound.loop_at("generator_loop", generator, -4.0, 3.0, 30.0)
	# mât d'antennes (le brouilleur : c'est pour ça que rien ne capte), diode rouge
	antenna = _obj("camp_antenna", c + Vector3(-4.5, 0, -5.5))
	B.cylinder(antenna, 0.03, 0.04, 3.2, Vector3(0, 1.6, 0), B.color_mat(Color(0.35, 0.35, 0.36), 0.5, 0.8), true, 8)
	B.model(antenna, "sf:antennas", Vector3(0, 3.0, 0), 0.0, {"height": 0.9})
	B.box(antenna, Vector3(0.3, 0.4, 0.2), Vector3(0, 0.2, 0), B.color_mat(Color(0.12, 0.12, 0.13), 0.6, 0.4), true)
	var led := B.omni(antenna, Vector3(0, 3.3, 0), Color(1.0, 0.05, 0.05), 0.4, 2.0)
	var blink := create_tween().set_loops()
	blink.tween_callback(func() -> void: led.visible = not led.visible)
	blink.tween_interval(0.7)
	# la caisse des téléphones confisqués (ceux des sessions d'avant)
	crate = _obj("camp_crate", c + Vector3(-0.6, 0, 2.2), 15.0)
	B.model(crate, "plastic_crate_01", Vector3.ZERO, 0.0, {"height": 0.32, "collide": true})
	for k in 8:
		Props.phone(crate, Vector3(randf_range(-0.12, 0.12), 0.2 + k * 0.012, randf_range(-0.08, 0.08)), randf_range(0, 360),
			[Color(0.05, 0.05, 0.06), Color(0.7, 0.68, 0.66), Color(0.12, 0.2, 0.35), Color(0.4, 0.1, 0.1)][k % 4])
	Interactable.create(crate, Vector3(0, 0.36, 0), Vector3(0.45, 0.3, 0.45), "Les téléphones", _use_phone)
	# la batterie de secours, à côté du groupe
	battery = _obj("camp_battery", c + Vector3(-5.6, 0, -1.3))
	_build_battery_mesh(battery)
	var bit := Interactable.create(battery, Vector3(0, 0.15, 0), Vector3(0.5, 0.35, 0.45), "Débrancher la batterie", Callable(), 1.4)
	bit.on_use = _take_battery


## Feu de camp : cercle de pierres, bûches en tipi à moitié consumées, lit de braises, flammes, étincelles, fumée.
func _campfire(holder: Node3D) -> void:
	B.model(holder, "stone_fire_pit", Vector3.ZERO, 0.0, {"width": 1.2, "collide": true})
	var coals := B.cylinder(holder, 0.34, 0.36, 0.05, Vector3(0, 0.04, 0), B.emissive(Color(1.0, 0.22, 0.04), 1.6), false, 14)
	coals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var char_mat := B.color_mat(Color(0.05, 0.04, 0.035), 0.95)
	var bark := B.mat("pine_bark", 0.5, {"color": Color(0.35, 0.3, 0.25)})
	for k in 5:
		var a := k * TAU / 5.0 + 0.3
		var log_mi := B.cylinder(holder, 0.045, 0.06, 0.62, Vector3(cos(a) * 0.16, 0.24, sin(a) * 0.16), bark if k % 2 == 0 else char_mat, false, 7)
		log_mi.rotation = Vector3(0, -a, 0)
		log_mi.rotate_object_local(Vector3(0, 0, 1), 0.55)
	# une bûche tombée sur le côté, rougeoyante
	var fallen := B.cylinder(holder, 0.05, 0.05, 0.55, Vector3(0.12, 0.08, -0.1), char_mat, false, 7, Vector3(0, 30, 90))
	fallen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flame := B.omni(holder, Vector3(0, 0.5, 0), Color(1.0, 0.45, 0.15), 1.4, 8.0, true)
	flame.name = "Flame"
	flame.light_volumetric_fog_energy = 1.2
	holder.add_child(_fire_particles(64, 0.6, 0.15, Vector2(0.2, 0.34), [Color(1.5, 0.95, 0.4, 0.9), Color(1.3, 0.45, 0.08, 0.6), Color(0.5, 0.08, 0.02, 0.0)], 0.5, 1.6))
	var sparks := _fire_particles(10, 1.8, 0.12, Vector2(0.025, 0.025), [Color(4.0, 2.2, 0.8, 1.0), Color(3.0, 0.8, 0.1, 0.7), Color(1.0, 0.2, 0.0, 0.0)], 1.4, 0.5)
	sparks.process_material.set("spread", 25.0)
	sparks.process_material.set("turbulence_enabled", true)
	sparks.process_material.set("turbulence_noise_strength", 2.0)
	holder.add_child(sparks)
	var smoke := Nature.steam(holder, Vector3(0, 0.9, 0), Vector3.UP)
	smoke.position = Vector3(0, 0.9, 0)
	Sound.loop_at("fire_loop", holder, -8.0, 1.0, 12.0)


func _fire_particles(amount: int, life: float, radius: float, size: Vector2, ramp: Array, speed: float, rise: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.position = Vector3(0, 0.12, 0)
	p.visibility_aabb = AABB(Vector3(-1, -0.2, -1), Vector3(2, 3.5, 2))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = speed * 0.6
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, rise, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1, 0.15))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.colors = PackedColorArray(ramp)
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	var sg := Gradient.new()
	sg.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	soft.gradient = sg
	m.albedo_texture = soft
	q.material = m
	p.draw_pass_1 = q
	return p


func _build_battery_mesh(parent: Node3D) -> void:
	if parent == null:
		return
	var case := B.box(parent, Vector3(0.27, 0.19, 0.17), Vector3(0, 0.095, 0), B.color_mat(Color(0.06, 0.06, 0.07), 0.6, 0.1), false)
	case.name = "Battery"
	B.box(parent, Vector3(0.27, 0.012, 0.17), Vector3(0, 0.196, 0), B.color_mat(Color(0.12, 0.12, 0.13), 0.6), false)
	B.cylinder(parent, 0.012, 0.012, 0.025, Vector3(-0.09, 0.21, 0.04), B.color_mat(Color(0.75, 0.08, 0.06), 0.5, 0.3), false, 8)
	B.cylinder(parent, 0.012, 0.012, 0.025, Vector3(0.09, 0.21, 0.04), B.color_mat(Color(0.12, 0.12, 0.12), 0.5, 0.3), false, 8)


## Il débranche la batterie... et la porte du van claque : le deuxième homme était dedans.
func _take_battery() -> void:
	if has_battery:
		return
	has_battery = true
	Sound.play("pickup", -6.0, 0.7)
	Game.hud.pickup("Batterie 12 V")
	battery.visible = false
	_clear_interactables(battery)
	stage = "carry"
	params = {"checkpoint": "carry", "drones": drones_left}
	Game.level_params = params
	Game.hud.say("Je l'ai. Lourde... Vite, à la cabane.", 2.6)
	await wait(2.4)
	Sound.play_at("door_slam", van.global_position + Vector3(0, 1.0, 0), 4.0, 0.85, 6.0, 50.0)
	await wait(0.7)
	(hunters[1] as Hunter).wake(true)
	Game.glitch(0.4)
	await wait(1.4)
	Game.hud.say("Le van... Il y en avait un deuxième dedans. Il m'a pas vu. Pas encore.", 3.4)
	Game.hud.objective("Rapporter la batterie à la cabane, sans te faire voir")
	await wait(3.6)
	Game.hud.hint("Ils voient, mais entendent mal : reste hors de leurs lampes, accroupis-toi ([C]), éteins ta lampe ([F]). Un caillou lancé loin les attire.", 8.0)


## Un téléphone pris au hasard dans la caisse : celui d'un autre. Des messages de sa famille, des semaines
## d'appels manqués... Et « aucun service » : ils brouillent tout. C'est pour ça que rien ne capte.
func _use_phone() -> void:
	if _phone_done:
		Game.hud.say("Rien. Aucun réseau, sur aucun.", 2.0)
		return
	_phone_done = true
	player.control_enabled = false
	cutscene = true
	var ui := PhoneUI.new()
	add_child(ui)
	var phone := Node3D.new()
	player.cam.add_child(phone)
	phone.position = Vector3(0.0, -0.035, -0.28)
	phone.rotation_degrees = Vector3(8, 0, 0)
	var shell := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.0765, 0.1605, 0.0085)
	shell.mesh = bm
	shell.material_override = B.color_mat(Color(0.7, 0.68, 0.66), 0.3, 0.6)
	phone.add_child(shell)
	var scr_mat := StandardMaterial3D.new()
	scr_mat.albedo_color = Color(0.015, 0.015, 0.018)
	scr_mat.emission_enabled = true
	scr_mat.emission_texture = ui.get_texture()
	scr_mat.emission_energy_multiplier = 0.9
	var scr := B.quad(phone, Vector2(0.0725, 0.1525), Vector3(0, 0, 0.0044), scr_mat)
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := B.omni(phone, Vector3(0, 0, 0.1), Color(0.6, 0.7, 1.0), 0.15, 0.8)
	Sound.play("pickup", -10.0, 1.2)
	await get_tree().process_frame
	ui.set_time("05:58")
	ui.show_screen("lock")
	ui.notify("Papa", "Romain rappelle-moi. Ta mère ne dort plus.")
	ui.notify("Léa", "t'es où ??? ça fait 3 semaines")
	ui.notify("Gendarmerie", "Avis de recherche partagé 2 140 fois")
	ui.notify("Batterie", "4 %")
	await wait(0.6)
	Game.hud.say("C'est pas le mien... « Romain ». Celui de l'avis de recherche.", 3.4)
	await wait(3.6)
	ui.call_contact("17")
	await wait(2.4)
	ui.set_call_status("Aucun service")
	Sound.play("ui_beep", -10.0, 0.6)
	Game.hud.say("« Aucun service »... Les antennes, là-bas. Ils brouillent tout.", 3.4)
	await wait(3.6)
	Game.hud.say("C'est pour ça que rien ne capte. Depuis la maison.", 2.8)
	await wait(2.6)
	var tw := create_tween()
	tw.tween_property(scr_mat, "emission_energy_multiplier", 0.0, 0.6)
	tw.parallel().tween_property(glow, "light_energy", 0.0, 0.6)
	await tw.finished
	phone.queue_free()
	ui.queue_free()
	player.control_enabled = true
	cutscene = false


# ================================================================== hommes au masque
func _place_hunters() -> void:
	var a := hunters[0] as Hunter
	# il sort du camp par son sentier, puis DESCEND le sentier principal vers la plaque d'égout : Théo voit sa lampe
	# arriver de loin et doit se cacher (première rencontre, ~35 s après la sortie)
	a.global_position = _path_point(desk.global_position, 0.7)
	a.route = _route(0)
	var b := hunters[1] as Hunter
	b.global_position = van.global_position + van.global_basis.x * 1.4
	b.route = _route(1)
	b.camp = battery.global_position


## Rondes : l'un tourne entre le camp, le sentier et la cabane ; l'autre (celui du van) reste plus près du camp.
func _route(k: int) -> Array:
	var c := desk.global_position
	var h := hut.global_position
	var j_camp := _path_point(c, 0.0)
	var j_hut := _path_point(h, 0.0)
	if k == 0:
		return [j_camp, TRAIL[2], TRAIL[1], TRAIL[2], j_hut, _path_point(h, 0.75), j_hut, j_camp, _path_point(c, 0.5),
			c + Vector3(-7, 0, 2), c + Vector3(-3, 0, -7), c + Vector3(4, 0, 7), _path_point(c, 0.5)]
	return [c + Vector3(-5, 0, -3), c + Vector3(-8, 0, 4), _path_point(c, 0.35), c + Vector3(3, 0, 6), c + Vector3(6, 0, -1)]


## Un homme au masque vient de le repérer : sa radio grésille (il prévient l'autre) et une note stridente part ;
## Théo ne le dit qu'une fois dans la partie. Quand il le perd, sa radio grésille encore (il rend compte).
func on_spotted(h: Node3D) -> void:
	Sound.play("spotted_sting", -5.0, randf_range(0.97, 1.03), "UI")
	Sound.play_at("radio_squelch", h.global_position + Vector3(0, 1.5, 0), -2.0, 1.0, 4.0, 40.0)
	if Game.first_time("hunter_spotted"):
		Game.hud.say("Il m'a vu... COURS !", 1.8)


func on_lost(h: Node3D) -> void:
	Sound.play_at("radio_squelch", h.global_position + Vector3(0, 1.5, 0), -4.0, 0.94, 4.0, 40.0)


## La première fois qu'il passe à côté d'un tas de cailloux (une fois dans la partie) : Théo le remarque.
func _look_for_stones() -> void:
	for pile in piles:
		var pn := pile as Node3D
		if not pn.visible:
			continue
		var to := pn.global_position - player.eye_position()
		if to.length() < 4.5 and (-player.cam.global_basis.z).dot(to.normalized()) > 0.6:
			_stones_told = true
			if Game.first_time("stones_seen") and stones == 0:
				Game.hud.say("Des cailloux... Ça peut servir. Les lancer loin, pour les attirer ailleurs.", 3.4)
			return


## La première fois qu'il voit la lampe d'un homme au masque : il comprend, et on lui dit comment se cacher.
func _look_for_hunters() -> void:
	var eye := player.eye_position()
	for h in hunters:
		var hh := h as Hunter
		if hh.state == Hunter.S.HIDDEN:
			continue
		var head := hh.global_position + Vector3(0, 1.5, 0)
		var to := head - eye
		if to.length() < 32.0 and (-player.cam.global_basis.z).dot(to.normalized()) > 0.55 and has_los(eye, head):
			_hunter_warned = true
			if not Game.first_time("hunter_first_seen"):
				return
			Game.hud.say("Une lampe... Quelqu'un vient. Il a... un masque. C'est un des leurs !", 3.4)
			await wait(3.6)
			Game.hud.hint("Il voit bien mais entend mal : sors du sentier, accroupis-toi ([C]), éteins ta lampe ([F])", 7.0)
			return


# ================================================================== le drone
func _update_drone(delta: float) -> void:
	if drone != null and is_instance_valid(drone) and not drone.down:
		feed.cam.global_transform = drone.view_transform()
		# il signale Théo aux hommes au masque : l'abattre a un vrai intérêt
		_report_cd -= delta
		if _report_cd <= 0.0:
			_report_cd = 11.0
			if has_los(drone.global_position, player.eye_position()):
				for h in hunters:
					if (h as Hunter).state in [Hunter.S.PATROL, Hunter.S.SEARCH]:
						(h as Hunter).hear(player.global_position, 999.0)
						break
		return
	if stage in ["chase", "done"] or drones_left <= 0 or editing:
		return
	_drone_cd -= delta
	if _drone_cd <= 0.0:
		_drone_cd = 9999.0
		drones_left -= 1
		drone = Drone.new()
		drone.level = self
		add_child(drone)
		drone.global_position = player.global_position + Vector3(randf_range(-8, 8), 10.0, -16.0)
		_feed_mat.set_shader_parameter("static_mix", 0.0)
		await wait(4.0)
		if drones_left == 1:
			Game.hud.say("C'est quoi ce bourdonnement... Un drone ?! Il me filme...", 3.2)
		else:
			Game.hud.say("Un autre drone... Ils en avaient un deuxième.", 3.0)


func on_drone_down(_d: Node) -> void:
	_feed_mat.set_shader_parameter("static_mix", 1.0)
	Game.hud.say("Touché !" if drones_left > 0 else "Et de deux. Plus d'yeux dans le ciel.", 2.0)
	_drone_cd = 55.0


# ================================================================== la nuit qui vit
func _night_sounds(delta: float) -> void:
	_owl_cd -= delta
	if _owl_cd <= 0.0:
		_owl_cd = randf_range(25.0, 50.0)
		var a := randf() * TAU
		Sound.play_at(Sound.variant("owl", 2), player.global_position + Vector3(cos(a) * 30.0, 8.0, sin(a) * 30.0), -6.0, randf_range(0.9, 1.05), 15.0, 80.0)
	# une branche qui craque dans le noir, derrière lui
	_snap_cd -= delta
	if _snap_cd <= 0.0:
		_snap_cd = randf_range(30.0, 70.0)
		var back := player.cam.global_basis.z
		back.y = 0.0
		var p := player.global_position + back.normalized() * randf_range(8.0, 14.0) + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		Sound.play_at(Sound.variant("twig_snap", 2), p, -2.0, randf_range(0.8, 1.1), 5.0, 30.0)


# ================================================================== la route, la mort, la fin
func _at_road() -> void:
	if stage == "chase":
		stage = "done"
		_creature_recalled()
		_reveal()
	elif not _road_said and stage != "done":
		_road_said = true
		Game.hud.say("La route... Pas une voiture. Personne. Il faut que je trouve un moyen d'appeler.", 4.0)


## Un sifflet strident, quelque part près du poteau : la créature s'arrête net, puis repart dans le brouillard.
func _creature_recalled() -> void:
	Sound.play_at("whistle", POLE + Vector3(0, 4.0, 0), 4.0, 1.0, 20.0, 120.0)
	if creature == null or not creature.visible:
		return
	creature.stand_and_watch(null, "listen", 0.8)
	creature.twitch.spasm(1.0)
	await wait(1.6)
	creature.script_walk(PackedVector3Array([s13.global_position]), 2.6)
	await wait(4.0)
	creature.deactivate()


func _die(cause: String) -> void:
	if dying or stage == "done":
		return
	dying = true
	_trapped = -1
	Game.hud.hold(0.0)
	player.control_enabled = false
	player.look_enabled = false
	var start := player.head.global_transform
	var killer: Hunter = null
	var nearest := 1e9
	for h in hunters:
		var dd := (h as Hunter).global_position.distance_to(player.global_position)
		if (h as Hunter).visible and dd < nearest:
			nearest = dd
			killer = h
	var who: Vector3 = creature.head_position() if cause == "creature" or killer == null else killer.global_position + Vector3(0, 1.6, 0)
	var face := Transform3D(Basis.looking_at((who - start.origin).normalized(), Vector3.UP), start.origin)
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: player.set_cinematic(start.interpolate_with(face, w), 1.0), 0.0, 1.0, 0.2)
	if cause == "creature":
		Sound.play("creature_attack", 4.0)
	elif killer != null:
		killer.actor.play("strike", 0.1, 1.2)
		Sound.play("hit_impact", 0.0)
	Game.glitch(1.0, false)
	Game.shake(3.0)
	await wait(0.35)
	Sound.play(Sound.variant("theo_scream", 2), 2.0, randf_range(0.95, 1.05))
	Game.flash(0.4)
	var ground := player.global_position + Vector3(0, 0.06, 0)
	var ahead := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
	var floor_t := Transform3D(Basis.looking_at(Vector3.UP, ahead) * Basis(Vector3(0, 0, 1), randf_range(-0.6, 0.6)), ground)
	var tw2 := create_tween()
	tw2.tween_method(func(w: float) -> void: player.set_cinematic(face.interpolate_with(floor_t, w), 1.0), 0.0, 1.0, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await wait(0.45)
	Sound.play("body_fall", -2.0)
	Game.shake(1.0)
	await wait(2.2)
	Sound.play("signal_lost", -4.0, 1.0, "UI")
	Game.hud.osd("SIGNAL PERDU")
	Game.glitch(1.0, false)
	await wait(1.0)
	Game.set_blackout(true)
	await wait(1.2)
	Game.hud.osd("")
	Game.set_blackout(false, true)
	Game.level_params = params
	Game.retry_from_checkpoint()


func _reveal() -> void:
	if revealed:
		return
	revealed = true
	pole_cam.tracking = true
	Sound.play_at("servo", pole_cam.global_position, 4.0, 0.8, 8.0, 80.0)
	await wait(1.5)
	Game.hud.say("Non...", 1.8)
	await wait(1.6)
	Game.hud.say("Non, non, non...", 2.0)
	Game.glitch(0.6)
	await wait(1.2)
	Game.glitch(1.0)
	Game.hud.set_rec(false)
	Game.hud.live_overlay(true, 4312, "")
	Sound.play("stinger_soft", -4.0)
	var viewers := 4312
	for i in 30:
		viewers += randi_range(40, 400)
		Game.hud.live_overlay(true, viewers, "")
		await wait(0.12)
	Game.hud.live_overlay(true, viewers, "SESSION 14 — TERMINÉE\nMerci d'avoir regardé.")
	await wait(3.5)
	player.control_enabled = false
	Sound.play("boom_hit", 0.0)
	Game.glitch(1.0, false)
	Game.set_blackout(true)
	Game.hud.show_hud(false)
	if wind != null:
		Sound.fade(wind, -60.0, 0.3, true)
	await wait(1.0)
	Sound.play("signal_lost", -2.0, 1.0, "UI")
	Game.clock_running = false
	await wait(2.0)
	Game.ui.fade_rect.color = Color(0, 0, 0, 1)
	Game.set_blackout(false, true)
	await Game.ui.show_card([
		{"text": "FIN DE L'ENREGISTREMENT", "style": "red"},
		"",
		"Cet enregistrement a été retrouvé le 2 décembre 2026",
		"sur un serveur hébergé à l'étranger, aux côtés de treize autres « sessions ».",
		"",
		"Théo Marchand, Maxime Dubreuil, Inès Ferrand et Karim Haddad",
		"n'ont jamais été retrouvés.",
	], 1.6, 5.0, 1.5)
	await Game.ui.show_card([
		{"text": "DERNIER ENREGISTREMENT", "style": "title"},
		{"text": "Merci d'avoir joué.", "style": "small"},
		"",
		{"text": "Modèles : Poly Haven (CC0), Sketchfab (CC BY — voir CREDITS.md), Microsoft Rocketbox (MIT)", "style": "small"},
		{"text": "Animations : CMU Motion Capture Database  ·  Sons : Freesound (CC0) et générés par code  ·  Moteur : Godot", "style": "small"},
	], 1.2, 4.0, 1.5)
	Game.quit_to_menu()


func _process(delta: float) -> void:
	super._process(delta)
	if player == null or dying or editing:
		return
	_check_traps()
	_update_drone(delta)
	_night_sounds(delta)
	if _dust != null:
		_dust.global_position = player.global_position + Vector3(0, 1.4, 0)
		_dust_near.global_position = player.cam.global_position - player.cam.global_basis.z * 1.0
	if not _hunter_warned:
		_look_for_hunters()
	if not _stones_told:
		_look_for_stones()
	if Input.is_action_just_pressed("throw") and stones > 0 and player.can_act():
		_throw_stone()
	# le feu vacille
	if fire != null:
		var fl := fire.find_child("Flame", false, false) as OmniLight3D
		if fl != null:
			fl.light_energy = 1.2 + sin(Time.get_ticks_msec() / 90.0) * 0.15 + randf_range(-0.12, 0.12)
	var d := 99.0
	if creature != null and creature.visible:
		d = creature.global_position.distance_to(player.global_position)
	for h in hunters:
		var hh := h as Hunter
		if hh.state != Hunter.S.HIDDEN:
			d = minf(d, hh.global_position.distance_to(player.global_position) * (0.6 if hh.state == Hunter.S.CHASE else 1.4))
	player.danger = clampf(1.0 - d / 16.0, 0.0, 1.0)


func prewarm_extras() -> Array:
	var out: Array = [creature]
	out.append_array(hunters)
	var d := Drone.new()
	d.level = self
	d.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(d)
	d.set_meta("prewarm_temp", true)
	out.append(d)
	return out


## Tests : --surfacetest=look|flee|trap|trapmash|drone|dronelook|dronehit|droneview|hunterview|seen|chase|radio|road|phone|cam|dump
func _surface_test(kind: String) -> void:
	await wait(1.0)
	player.set_flashlight(true, true)
	var fwd := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
	match kind:
		"trap":
			player.global_position = (traps[0][0] as Node3D).global_position + Vector3(0, 0.05, 0.2)
		"trapmash":
			# on marche sur le piège, puis on martèle E (environ 7 appuis par seconde)
			player.global_position = (traps[0][0] as Node3D).global_position + Vector3(0, 0.05, 0.1)
			await wait(1.5)
			var presses := 0
			while _trapped >= 0 and presses < 60:
				var ev := InputEventAction.new()
				ev.action = "interact"
				ev.pressed = true
				Input.parse_input_event(ev)
				await get_tree().process_frame
				await get_tree().process_frame
				var up := InputEventAction.new()
				up.action = "interact"
				Input.parse_input_event(up)
				presses += 1
				await wait(0.14)
			print("PIEGE libéré après %d appuis : %s" % [presses, "oui" if _trapped < 0 else "NON"])
		"dronehit":
			# le drone en vol stationnaire, on vise à côté (8°) et on lance : l'aide à la visée doit le toucher
			stones = 3
			_drone_cd = 0.0
			await wait(6.0)
			for k in 3:
				if drone == null or drone.down:
					break
				var to := drone.global_position - player.eye_position()
				var yaw_to := atan2(-to.x, -to.z) + deg_to_rad(8.0)
				var pitch_to := atan2(to.y, Vector2(to.x, to.z).length())
				player.set_look(yaw_to, pitch_to)
				await get_tree().process_frame
				_throw_stone()
				await wait(2.0)
				print("DRONE essai %d : distance %.1f m, abattu = %s" % [k + 1, to.length(), "oui" if drone == null or drone.down else "non"])
		"drone":
			_drone_cd = 0.0
		"hitbox":
			# Théo marche droit sur un objet de la carte du joueur qui a une hitbox automatique : il doit s'arrêter devant
			for h in hunters:
				(h as Node3D).process_mode = Node.PROCESS_MODE_DISABLED
				(h as Node3D).visible = false
			_drone_cd = 1e9
			var autos := []
			for n in MapLayout.collect(self):
				if n.has_node("AutoCollide"):
					autos.append(n)
			print("HITBOX objets avec hitbox automatique : %d / %d" % [autos.size(), MapLayout.collect(self).size()])
			for want in ["SM_MTable_001_1", "old_military_crate", "canvas_tent"]:
				for n in autos:
					var spec: Dictionary = n.get_meta("spec", {})
					if not (str(spec.get("model", "")) + str(spec.get("part", ""))).contains(want):
						continue
					var c: Vector3 = (n as Node3D).global_position
					var start := c + Vector3(0, 0, 3.0)
					player.global_position = Vector3(start.x, floor_y(start) + 0.05, start.z)
					player.set_look(0.0, 0.0)
					await wait(0.3)
					Input.action_press("move_forward")
					await wait(2.5)
					Input.action_release("move_forward")
					var d := Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length()
					print("HITBOX %s : parti à 3.0 m, arrêté à %.2f m du centre (traversé = %s)" % [want, d, "OUI" if player.global_position.z < c.z else "non"])
					break
		"dronelook":
			# Théo, lampe éteinte, suit le drone des yeux (personne ne patrouille) : on doit le voir arriver
			for h in hunters:
				(h as Node3D).process_mode = Node.PROCESS_MODE_DISABLED
				(h as Node3D).visible = false
			player.set_flashlight(false, true)
			_drone_cd = 0.0
			var t0 := 0.0
			while t0 < 40.0:
				if drone != null and is_instance_valid(drone):
					var to := drone.global_position - player.eye_position()
					player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
					if fmod(t0, 1.0) < get_process_delta_time():
						print("DRONE à %.1f m, %.1f m au-dessus" % [to.length(), to.y])
				await get_tree().process_frame
				t0 += get_process_delta_time()
		"look":
			# captures du décor : personne ne patrouille
			for h in hunters:
				(h as Node3D).process_mode = Node.PROCESS_MODE_DISABLED
				(h as Node3D).visible = false
			_drone_cd = 1e9
		"droneview":
			var dv := Drone.new()
			dv.level = self
			add_child(dv)
			dv.global_position = player.global_position + fwd * 1.6 + Vector3(0, 1.5, 0)
			await wait(0.4)
			dv.process_mode = Node.PROCESS_MODE_DISABLED
		"hunterview":
			var h := hunters[0] as Hunter
			h.global_position = player.global_position + fwd * 4.0
			h.heading = player.yaw + PI
			h.rotation.y = h.heading
			h.actor.play("idle", 0.0)
			await wait(0.3)
			h.process_mode = Node.PROCESS_MODE_DISABLED
		"seen":
			var h2 := hunters[0] as Hunter
			h2.global_position = player.global_position + fwd * 12.0
			h2.heading = player.yaw + PI
			h2.state = Hunter.S.SEARCH
		"chase":
			_release_creature(true)
		"flee":
			# sur la route : il le repère à 10 m, Théo sprinte vers l'ouest (sans lampe si --dark) ; on mesure l'écart
			player.global_position = Vector3(-4.0, 0.05, ROAD_Z + 1.5)
			player.set_look(PI * 0.5, 0.0)
			if Game.args.has("dark"):
				player.set_flashlight(false, true)
			var h4 := hunters[0] as Hunter
			h4.global_position = player.global_position + Vector3(10.0, 0, 0)
			h4.heading = PI * 0.5
			h4.state = Hunter.S.SEARCH
			h4.suspicion = 1.2
			(hunters[1] as Hunter).process_mode = Node.PROCESS_MODE_DISABLED
			_drone_cd = 1e9
			await wait(0.4)
			Input.action_press("move_forward")
			Input.action_press("run")
			for i in 14:
				await wait(1.0)
				print("FUITE t=%d écart=%.1f m état=%s souffle=%.2f endurance=%.2f" % [i + 1, h4.global_position.distance_to(player.global_position),
					Hunter.S.keys()[h4.state], h4.wind, player.stamina])
			Input.action_release("move_forward")
			Input.action_release("run")
		"radio":
			player.global_position = hut.global_transform * Vector3(-0.6, 0.05, -0.2)
			battery_in = true
			_install_battery_visual()
			_radio_power_on()
			_radio_call()
		"road":
			_release_creature(true)
			await wait(2.0)
			player.global_position = Vector3(0.0, 0.05, ROAD_Z + 4.0)
		"phone":
			_use_phone()
		"cam":
			_play_cam13()
		"dump":
			for n in MapLayout.movables(self):
				var nd := n as Node3D
				var bb := B.local_aabb(nd)
				print("OBJ %s pos=%s taille=%s enfants=%d" % [nd.name, nd.global_position.snapped(Vector3.ONE * 0.1), bb.size.snapped(Vector3.ONE * 0.01), nd.get_child_count()])
				for ch in nd.get_children():
					if ch is Node3D:
						print("     - %s %s taille=%s" % [ch.name, (ch as Node3D).position.snapped(Vector3.ONE * 0.01), (ch.get_meta("size", Vector3.ZERO) as Vector3).snapped(Vector3.ONE * 0.01)])
	for i in 12:
		await wait(1.0)
		var hs: String = Hunter.S.keys()[(hunters[0] as Hunter).state]
		var hs2: String = Hunter.S.keys()[(hunters[1] as Hunter).state]
		var cs: String = Creature.State.keys()[creature.state]
		var dr := "oui" if drone != null and is_instance_valid(drone) and not drone.down else "non"
		print("SURFACE t=%d étape=%s masque1=%s masque2=%s soupçon=%.2f créature=%s boite=%.2f drone=%s piège=%.2f" % [i + 1, stage, hs, hs2, (hunters[0] as Hunter).suspicion, cs, player.limp, dr, _trap_prog])


# ================================================================== drone
class Drone extends Node3D:
	const LAYER := 1 << 7
	var level
	var model: Node3D
	var body: StaticBody3D
	var led: OmniLight3D
	var search: SpotLight3D
	var strobe: OmniLight3D
	var buzz: AudioStreamPlayer3D
	var discs: Array[Node3D] = []
	var down := false
	var vel := Vector3.ZERO
	var t := 0.0
	var orbit := 0.0

	func _ready() -> void:
		model = B.model(self, "sf:drone", Vector3.ZERO, 0.0, {"width": 0.55})
		# hélices : on cache les pales figées et on met à leur place un disque flou qui tourne (comme à l'image)
		var blur := StandardMaterial3D.new()
		blur.albedo_color = Color(0.1, 0.1, 0.11, 0.35)
		blur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		blur.cull_mode = BaseMaterial3D.CULL_DISABLED
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			if String(mi.name).to_lower().contains("propeller"):
				var c := global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb().get_center()
				(mi as MeshInstance3D).visible = false
				var disc := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.11
				cm.bottom_radius = 0.11
				cm.height = 0.004
				cm.radial_segments = 20
				disc.mesh = cm
				disc.material_override = blur
				add_child(disc)
				disc.position = c
				discs.append(disc)
		led = OmniLight3D.new()
		led.light_color = Color(1.0, 0.1, 0.08)
		led.light_energy = 0.9
		led.omni_range = 3.0
		add_child(led)
		led.position = Vector3(0, -0.05, 0.12)
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.016
		sm.height = 0.032
		dot.mesh = sm
		dot.material_override = B.emissive(Color(1.0, 0.1, 0.08), 6.0, true)
		led.add_child(dot)
		# le projecteur braqué sur Théo : un cône dans la brume, on le voit arriver de loin
		search = SpotLight3D.new()
		search.light_color = Color(0.85, 0.9, 1.0)
		search.light_energy = 7.0
		search.spot_range = 18.0
		search.spot_angle = 10.0
		search.spot_attenuation = 0.8
		search.light_volumetric_fog_energy = 6.0
		add_child(search)
		search.position = Vector3(0, -0.12, 0)
		# feu à éclats blanc (double flash), comme un vrai drone de nuit
		strobe = OmniLight3D.new()
		strobe.light_color = Color(1, 1, 1)
		strobe.light_energy = 2.0
		strobe.omni_range = 5.0
		add_child(strobe)
		strobe.position = Vector3(0, 0.05, -0.12)
		var sdot := MeshInstance3D.new()
		var ssm := SphereMesh.new()
		ssm.radius = 0.02
		ssm.height = 0.04
		sdot.mesh = ssm
		sdot.material_override = B.emissive(Color(1, 1, 1), 10.0, true)
		strobe.add_child(sdot)
		body = StaticBody3D.new()
		body.collision_layer = LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.6
		cs.shape = sh
		body.add_child(cs)
		add_child(body)
		buzz = Sound.loop_at("drone_loop", self, 0.0, 4.0, 50.0)
		orbit = randf() * TAU

	func _process(delta: float) -> void:
		if down or level == null:
			return
		t += delta
		var p: Player = level.player
		if p == null:
			return
		orbit += delta * 0.16
		var target := p.global_position + Vector3(cos(orbit) * 6.5, 4.6 + sin(t * 0.7) * 0.4, sin(orbit) * 6.5)
		var want := (target - global_position) * 1.1
		if want.length() > 6.5:
			want = want.normalized() * 6.5
		vel = vel.lerp(want, 1.0 - exp(-2.0 * delta))
		global_position += vel * delta
		var to := p.global_position - global_position
		rotation.y = atan2(-to.x, -to.z)
		var local := global_basis.inverse() * vel
		model.rotation = Vector3(clampf(local.z * 0.06, -0.3, 0.3), 0, clampf(-local.x * 0.06, -0.3, 0.3))
		for d in discs:
			d.rotate_object_local(Vector3.UP, delta * 90.0)
		led.visible = fmod(t, 1.0) < 0.18
		var ph := fmod(t, 1.4)
		strobe.visible = ph < 0.05 or (ph > 0.16 and ph < 0.21)
		var aim := p.global_position + Vector3(sin(t * 0.9) * 0.6, 0.9, cos(t * 0.7) * 0.6)
		if (aim - search.global_position).length() > 0.5:
			search.look_at(aim, Vector3.FORWARD if absf((aim - search.global_position).normalized().y) > 0.98 else Vector3.UP)

	func view_transform() -> Transform3D:
		var p: Player = level.player
		var eye := global_position + Vector3(0, -0.12, 0)
		return Transform3D(Basis.looking_at((p.global_position + Vector3(0, 1.0, 0) - eye).normalized(), Vector3.UP), eye)

	func hit() -> void:
		if down:
			return
		down = true
		led.visible = false
		search.visible = false
		strobe.visible = false
		for d in discs:
			d.visible = false
		Sound.play_at("lamp_break_0", global_position, 4.0, 0.8, 6.0, 50.0)
		if is_instance_valid(buzz):
			var tw0 := buzz.create_tween()
			tw0.tween_property(buzz, "pitch_scale", 0.4, 1.0)
			tw0.parallel().tween_property(buzz, "volume_db", -60.0, 1.2)
		var ground := Vector3(global_position.x, level.floor_y(global_position) + 0.12, global_position.z)
		var tw := create_tween()
		tw.tween_property(self, "global_position", ground, sqrt(2.0 * maxf(global_position.y - ground.y, 0.5) / 9.8)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(self, "rotation", rotation + Vector3(2.4, 6.0, 1.1), 1.0)
		tw.tween_callback(func() -> void:
			Sound.play_at(Sound.variant("rock_hit", 3), global_position, 2.0, 0.6, 4.0, 30.0)
			body.collision_layer = 0
			level.on_drone_down(self))


# ================================================================== l'homme au masque
class Hunter extends Node3D:
	enum S { HIDDEN, PATROL, INVESTIGATE, SEARCH, CHASE, LEAVING }
	const WALK := 1.15
	const RUN := 3.6  ## gilet, rangers, masque à gaz : il court lourdement, moins vite que Théo qui sprinte
	const JOG := 2.4  ## essoufflé dans son masque
	var level
	var camp := Vector3.ZERO  ## où il va d'abord (la batterie volée)
	var route: Array = []
	var actor: Actor
	var lamp: SpotLight3D
	var breath: AudioStreamPlayer3D
	var state := S.HIDDEN
	var wp := 0
	var target := Vector3.ZERO
	var home := Vector3.ZERO
	var suspicion := 0.0
	var last_seen := Vector3.ZERO
	var lost_t := 0.0
	var wait_t := 0.0
	var speed := 0.0
	var heading := 0.0
	var _vis_cd := 0.0
	var wind := 1.0  ## son souffle : il ne sprinte pas indéfiniment (6 s), puis trottine le temps de récupérer
	var winded := false
	var _step := 0.0
	var _chased_at := -100.0  ## dernière fois qu'il le poursuivait (s) : le retrouver juste après n'est pas un nouveau « repéré »

	func _ready() -> void:
		actor = Actor.new()
		actor.character = "hunter"  ## le modèle du ravisseur, avec sa course de forêt
		actor.ready.connect(func() -> void:
			actor.tint("", Color(0.16, 0.16, 0.17), 0.85)
			actor.hide_material("helmet")
			var mask := Node3D.new()
			B.model(mask, "sf:gasmask_gp5", Vector3.ZERO, 180.0, {"remove": ["Icosphere"], "height": 0.43})
			actor.attach("Head", mask, Vector3(0, -0.2, -0.1)), CONNECT_ONE_SHOT)
		add_child(actor)
		lamp = SpotLight3D.new()
		lamp.light_color = Color(1.0, 0.95, 0.85)
		lamp.light_energy = 6.0
		lamp.spot_range = 24.0
		lamp.spot_angle = 18.0
		lamp.shadow_enabled = true
		lamp.light_volumetric_fog_energy = 2.2
		add_child(lamp)
		lamp.position = Vector3(0.22, 1.35, -0.25)
		lamp.rotation_degrees = Vector3(-8, 0, 0)
		visible = false

	func wake(from_van: bool) -> void:
		visible = true
		state = S.PATROL
		wp = 0
		home = global_position
		if route.size() > 0:
			var to: Vector3 = route[0] - global_position
			heading = atan2(-to.x, -to.z)
		breath = Sound.loop_at("gasmask_breath_loop", self, -2.0, 2.0, 16.0)
		if breath != null:
			breath.position.y = 1.6
		if from_van:
			state = S.INVESTIGATE
			target = camp

	func leave() -> void:
		if state == S.HIDDEN:
			return
		state = S.LEAVING
		target = home

	func hear(pos: Vector3, radius: float) -> void:
		if state in [S.HIDDEN, S.CHASE, S.LEAVING]:
			return
		# il entend mal (le masque, le groupe électrogène) : seulement les bruits proches ou forts
		if global_position.distance_to(pos) < radius * 0.6:
			state = S.INVESTIGATE
			target = pos
			wait_t = 0.0

	func _process(delta: float) -> void:
		if state == S.HIDDEN or level == null or level.dying:
			return
		var p: Player = level.player
		_vision(delta, p)
		var goal := global_position
		var want_speed := 0.0
		match state:
			S.PATROL:
				if route.is_empty():
					return
				goal = route[wp]
				want_speed = WALK
				if _flat(goal - global_position).length() < 0.7:
					wp = (wp + 1) % route.size()
			S.INVESTIGATE:
				goal = target
				want_speed = WALK * 1.5
				if _flat(goal - global_position).length() < 0.9:
					state = S.SEARCH
					wait_t = 0.0
			S.SEARCH:
				wait_t += delta
				heading += sin(wait_t * 1.6) * delta * 1.5
				if wait_t > 5.0:
					state = S.PATROL
			S.CHASE:
				_chased_at = Time.get_ticks_msec() / 1000.0
				goal = p.global_position if lost_t < 0.5 else last_seen
				want_speed = JOG if winded else RUN
				if global_position.distance_to(p.global_position) < 1.25:
					level._die("hunter")
					return
				if lost_t > 3.0:
					state = S.SEARCH
					wait_t = 0.0
					suspicion = 0.5
					level.on_lost(self)
			S.LEAVING:
				goal = target
				want_speed = WALK * 1.4
				if _flat(goal - global_position).length() < 0.9:
					state = S.HIDDEN
					visible = false
					if breath != null:
						breath.queue_free()
					return
		speed = lerpf(speed, want_speed, 1.0 - exp(-4.0 * delta))
		# le souffle : se vide en sprintant, revient au trot ou en marchant
		if speed > JOG + 0.3:
			wind = maxf(0.0, wind - delta / 6.0)
			winded = winded or wind <= 0.0
		else:
			wind = minf(1.0, wind + delta / 7.0)
			if winded and wind > 0.5:
				winded = false
		if breath != null:
			breath.pitch_scale = lerpf(breath.pitch_scale, 1.3 if state == S.CHASE else 1.0, 1.0 - exp(-2.0 * delta))
			breath.volume_db = lerpf(breath.volume_db, 3.0 if state == S.CHASE else -2.0, 1.0 - exp(-2.0 * delta))
		# ses pas (rangers) : on l'entend arriver derrière soi
		if want_speed > 0.0:
			_step += speed * delta
			var stride := 1.3 if speed > 2.0 else 0.75
			if _step > stride:
				_step = 0.0
				var run := speed > 2.0
				Sound.play_at(Sound.variant("step_" + str(level.get_surface(global_position)), 4), global_position + Vector3(0, 0.05, 0),
					-3.0 if run else -12.0, randf_range(0.78, 0.88), 3.0, 34.0 if run else 18.0)
		var to := _flat(goal - global_position)
		if to.length() > 0.2 and want_speed > 0.0:
			heading = lerp_angle(heading, atan2(-to.x, -to.z), 1.0 - exp(-5.0 * delta))
			var fwd := Vector3(-sin(heading), 0, -cos(heading))
			global_position += fwd * speed * delta
			for o in level.trunks_near(global_position):
				var c: Vector3 = o[0]
				var r: float = float(o[1]) + 0.35
				var off := _flat(global_position - c)
				if off.length() < r and off.length() > 0.001:
					var out := off.normalized() * r
					global_position.x = c.x + out.x
					global_position.z = c.z + out.z
		rotation.y = heading
		global_position.y = level.floor_y(global_position)
		actor.locomote("run" if speed > 1.8 else "walk", speed if want_speed > 0.0 else 0.0, "idle")
		lamp.rotation_degrees.y = sin(Time.get_ticks_msec() / 900.0) * (6.0 if state == S.CHASE else 18.0)

	func _flat(v: Vector3) -> Vector3:
		return Vector3(v.x, 0, v.z)

	## Il VOIT : Théo dans son champ (55°), sans arbre entre eux. Plus visible debout, lampe allumée, en mouvement,
	## et surtout dans le faisceau de sa lampe ; beaucoup moins accroupi dans le noir.
	func _vision(delta: float, p: Player) -> void:
		_vis_cd -= delta
		if _vis_cd > 0.0:
			return
		_vis_cd = 0.12
		if level.cutscene and state != S.CHASE:
			return
		var dt := 0.12
		var eye := global_position + Vector3(0, 1.6, 0)
		var chest := p.global_position + Vector3(0, 0.6 if p.crouching else 1.1, 0)
		var to := chest - eye
		var d := to.length()
		var seen := false
		# en pleine course, dans le noir, à travers son masque : il le perd de vue bien plus vite
		var reach := 24.0 if state != S.CHASE else (20.0 if p.flashlight_on else 13.0)
		if d < reach and state != S.LEAVING:
			var fwd := -global_basis.z
			var ang := fwd.dot(to.normalized())
			if ang > cos(deg_to_rad(55.0)) and level.has_los(eye, chest):
				var v := 1.0 - d / 24.0
				v *= 0.45 if p.crouching else 1.0
				v *= 1.0 if p.flashlight_on else 0.55
				if ang > cos(deg_to_rad(20.0)) and d < 18.0:
					v *= 2.2
				if p.moving:
					v *= 1.3
				suspicion = minf(suspicion + v * dt * 2.4, 1.5)
				seen = true
				if state == S.CHASE:
					last_seen = p.global_position
					lost_t = 0.0
		if not seen:
			suspicion = maxf(0.0, suspicion - dt * 0.3)
			if state == S.CHASE:
				lost_t += dt
		if state in [S.PATROL, S.SEARCH, S.INVESTIGATE]:
			if suspicion >= 1.0:
				state = S.CHASE
				last_seen = p.global_position
				lost_t = 0.0
				if Time.get_ticks_msec() / 1000.0 - _chased_at > 8.0:
					level.on_spotted(self)
			elif suspicion > 0.45 and seen and state != S.INVESTIGATE:
				state = S.INVESTIGATE
				target = p.global_position
