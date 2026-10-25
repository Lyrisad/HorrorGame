extends Level
## Acte III — Sous la ville.
## Théo se réveille dans les égouts. Une créature aveugle y rôde et chasse au son.
## Trois époques de construction se succèdent : vieux collecteur voûté en briques (ouest),
## réservoir d'orage en béton (centre), galeries techniques (est).
## But : sortir de la cage, trouver le coupe-boulons (local technique) et les trois fusibles de
## l'armoire de l'écluse 3 jetés dans le réseau, remettre le courant, couper la chaîne,
## et remonter par l'échelle.

const T := 2.8  ## taille d'une case (m)
const SPRING := 1.75  ## naissance de la voûte (haut des murs droits)
const CEIL := SPRING + T * 0.5  ## sommet de la voûte = plafond des salles (m)
const CH_W := 0.36  ## demi-largeur de la cunette (rigole creusée au centre des collecteurs)
const CH_D := 0.1  ## profondeur de la cunette (une petite marche, pas besoin de sauter)
const CH_R_IN := 0.2  ## arrondi d'un coin d'allée qui avance dans la cunette (intérieur de virage, croisement)
const CH_R_OUT := 0.1  ## arrondi d'un coin de la cunette elle-même (extérieur de virage, fond)
const WATER_Y := -0.045  ## niveau de l'eau (cunettes et citerne)
const CIS_Y := -0.2  ## fond de la citerne
const HALL_H := 4.1  ## hauteur de la salle de la citerne
const BOX_H := [0.0, 2.55, 2.75]  ## hauteur des galeries « caisson » (zones B et C ; la zone A est voûtée)
const ZONE_LOW := [0.9, 0.9, 1.25]  ## hauteur du soubassement par zone
const SHAFTS := [Vector2i(9, 8), Vector2i(2, 5)]  ## puits vers la forêt (grille + clair de lune)
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## Angles adoucis (pas de « boîtes ») : congé dans les angles rentrants (assez petit pour que les
## canalisations longent la courbe), arêtes saillantes arrondies et gorge au pied des murs.
const R_IN := [0.42, 0.42, 0.32]
const R_OUT := 0.2
const COVE := 0.16
## Portes de service (case, côté du mur) : la gorge s'interrompt sous elles.
const SERVICE_DOORS := [[Vector2i(16, 6), Vector2i(0, 1)], [Vector2i(14, 8), Vector2i(-1, 0)], [Vector2i(17, 10), Vector2i(0, 1)]]
const DOOR_ALONG := 0.3  ## décalage de la porte le long du mur (depuis le milieu)
const DOOR_HALF := 0.56  ## demi-largeur de la porte avec son cadre
const MAP := [
	"#####################",
	"#SS..#.......#..TTT.#",
	"#SS#.#.#####.#..TTT.#",
	"##...#.#...#.#.####.#",
	"##.###.#.#.#.#......#",
	"#..#.....#.#.###.##.#",
	"#.##.###.#.#...#..#.#",
	"#....#.wwwww.#.##.#.#",
	"####.#.wwwww.#....#.#",
	"#....#.wwwww.####.#.#",
	"#.####.......#....#.#",
	"#......##.####.####.#",
	"#.####.#......#...#G#",
	"#......#.####...#.#E#",
	"#####################",
]
const GATE := Vector2i(19, 12)
const MIC_HINT := "Micro ouvert : si tu parles ou cries, la créature t'entend (vumètre MIC en bas à droite).  Paramètres → Micro"
const EXIT := Vector2i(19, 13)

var W := 0
var H := 0
var astar := AStarGrid2D.new()
var creature: Creature
var has_cutters := false
var chain_cut := false
var gate_opened := false
var revealed := false
var dying := false
var escaping := false
var checkpoint := "start"
var gate_doors: Array[Node3D] = []
var gate_body: StaticBody3D
var gate_chain: Node3D
var flicker_lights: Array[Light3D] = []
var _rng := RandomNumberGenerator.new()
var _drip_cd := 2.0
var _wail_cd := 40.0
var _presence_cd := 0.0
var _time := 0.0
var _breath_noise_cd := 0.0
var _unseen := 0.0
var _note_read := false
var _layout: Variant = null  ## disposition personnalisée du décor (éditeur de carte), ou null
var drone: AudioStreamPlayer
var dust: GPUParticles3D
var dust_near: GPUParticles3D
var pillars: Array = []  ## [centre, rayon] des piliers de la citerne (la créature les contourne)
var _lost_said := 0.0
var _shaft_tops: Array = []  ## [centre, hauteur du haut du conduit, lumière de lune] des puits vers la forêt
var _gust_cd := 25.0
var _ledge_side := 1.0  ## -1 / +1 : une des banquettes ; 0 : dans l'eau, au milieu de la cunette
var _lane_cd := 10.0
var _close_seen := false
var _cam_hist: Array[Transform3D] = []  ## dernières secondes filmées (pour le rembobinage)
var _hist_t := 0.0
var _lamp_lights: Array[Light3D] = []  ## luminaires : les plus proches de Théo ont des ombres
var _corridor_lamp: Light3D = null  ## baladeuse du couloir avant la première apparition : elle claque
var _rubble_mats := {}
var _shadow_cd := 0.0
## Fuites de vapeur des galeries techniques : [case, mur, décalage de la bride le long du mur]
const STEAM_LEAKS := [[Vector2i(19, 8), Vector2i(1, 0), 0.35], [Vector2i(16, 4), Vector2i(0, -1), -0.4], [Vector2i(16, 12), Vector2i(0, 1), 0.3]]
var _steam_spots: Array[Vector3] = []
var _chase_heat := 0.0
var room_cam: SecurityCamera
var gate_cam: SecurityCamera


func _ready() -> void:
	_rng.seed = 4242
	W = MAP[0].length()
	H = MAP.size()
	checkpoint = params.get("checkpoint", "start")
	fuses_found = (params.get("fuses", []) as Array).duplicate()
	fuses_in = int(params.get("fuses_in", 0))
	power_on = bool(params.get("power", false))
	make_environment({
		"bg": Color(0, 0, 0),
		"ambient": Color(0.02, 0.024, 0.022),
		"ambient_energy": 0.07,
		"exposure": 1.0,
		"vfog": true,
		"vfog_density": 0.045,
		"vfog_albedo": Color(0.42, 0.47, 0.42),
		"vfog_length": 40.0,
		"vfog_aniso": 0.6,
		"ssr": true,
		"ssao": true,
		"ae_scale": 0.3,
		"ae_max": 1000.0,
		"glow": 1.0,
	})
	Game.set_fx("grain", 0.06)
	Game.set_fx("gain", 0.4)
	Game.set_fx("saturation", 0.55)
	Game.set_fx("tint", Color(0.93, 1.0, 0.95))
	Sound.set_reverb(0.85, 0.32, 0.35)
	Game.set_clock(3, 12, 44, 15)

	_layout = MapLayout.load_entries("egouts")
	_build_geometry()
	_build_pipes()
	_build_steam()
	_build_navigation()
	_build_debris()
	_build_props()
	_build_lights()
	_build_signage()
	_build_gate()
	_build_exit()
	_build_items()
	_build_fuses()
	_build_panel()
	_build_npc()
	_build_hideout()
	_build_glass()
	if _layout != null:
		MapLayout.spawn(_layout, self)
	MapLayout.apply_cams("egouts", self)
	MapLayout.apply_objs("egouts", self)

	creature = Creature.new()
	creature.nav = self
	add_child(creature)
	creature.caught_player.connect(_on_caught)
	# chaque fusible ramassé l'agite un peu plus
	creature.aggression = fuses_found.size() + fuses_in
	creature.lost_track.connect(func(dist: float) -> void:
		# il a perdu la trace : Théo le comprend au silence qui revient
		if dist > 7.0 and _time - _lost_said > 40.0 and not dying:
			_lost_said = _time
			await wait(1.2)
			Game.hud.say(["...Il m'a perdu.", "Il cherche... Il sait plus où je suis.", "Bouge plus. Respire doucement."][randi() % 3], 2.8))

	drone = Sound.loop("drone_sewer", -9.0)
	var flow := Node3D.new()
	add_child(flow)
	flow.position = tile_center(Vector2i(9, 8))
	Sound.loop_at("water_flow_loop", flow, -4.0, 4.0, 25.0)

	if checkpoint == "cutters":
		_start_from_cutters()
	elif checkpoint == "cell":
		_start_from_cell()
	elif checkpoint == "bench":
		_start_from_bench()
	else:
		_intro()
	player.collision_mask |= BARS_LAYER
	# test : --creature=x,z place la créature debout face au joueur
	if Game.args.has("creature"):
		var cp := str(Game.args["creature"]).split(",")
		revealed = true
		creature.player = player
		creature.global_position = Vector3(float(cp[0]), 0, float(cp[1]))
		creature.stand_and_watch(player.head)
		player.set_flashlight(true, true)
		if Game.args.has("chase"):
			creature.activate(Creature.State.CHASE)
	if Game.args.get("autotest", "") == "sewer":
		_autotest()
	if Game.args.has("fusetest"):
		_fusetest()
	if Game.args.has("bottletest"):
		_bottletest()
	if Game.args.has("tour"):
		_tour()
	if Game.args.has("spots"):
		_spots()
	if Game.args.has("lookcam"):
		_lookcam()
	if Game.args.has("gust"):
		_gust_cd = 1.0
	# test : --splashtest → des ronds dans l'eau devant Théo ; --roachtest → des cafards puis la lampe dessus
	if Game.args.has("splashtest"):
		_splash_test()
	if Game.args.has("roachtest"):
		_roach_test()
	if Game.args.has("eventtest"):
		_event_test(str(Game.args["eventtest"]))
	if Game.args.has("misttest") and _mist != null:
		(_mist.material as FogMaterial).density = float(Game.args["misttest"])
	# test : --hinttest[=keys|prompt] → affiche l'indice du micro (le plus long du jeu), les touches, ou une invite
	if Game.args.has("hinttest"):
		if str(Game.args["hinttest"]) == "bottle":
			Game.hud.hint("[G] ou [clic droit]  lancer une bouteille pour faire diversion", 8.0)
			Game.hud.say("Une bouteille... ça peut servir.", 8.0)
		elif str(Game.args["hinttest"]) == "prompt":
			Game.hud.hint("[Maj] courir   ·   [Échap] pause", 8.0)
			# un objet factice droit devant ; les captures désactivent les interactions, on les rétablit
			var ahead := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
			Interactable.create(self, player.eye_position() + ahead * 0.9 - Vector3(0, 0.2, 0), Vector3(0.6, 0.6, 0.6), "Ramasser le coupe-boulons", func() -> void: pass)
			Game.args.erase("shots")
		elif str(Game.args["hinttest"]) == "keys":
			Game.hud.hint("[F] lampe torche   ·   [C] maintenir pour s'accroupir   ·   [Tab] objectif   ·   [I] inventaire", 8.0)
		else:
			Game.hud.hint(MIC_HINT, 8.0)
	# test : --lenstest → gouttes sur l'objectif dès le départ
	if Game.args.has("lenstest"):
		Game.lens_splash(1.0)
	# test : --freecam=x,y,z --freelook=x,y,z → caméra libre (pour inspecter un détail en hauteur)
	if Game.args.has("freecam"):
		var fc := Camera3D.new()
		fc.fov = float(Game.args.get("freefov", 50.0))
		add_child(fc)
		var a3 := str(Game.args["freecam"]).split(",")
		var b3 := str(Game.args.get("freelook", "0,0,0")).split(",")
		fc.look_at_from_position(Vector3(float(a3[0]), float(a3[1]), float(a3[2])), Vector3(float(b3[0]), float(b3[1]), float(b3[2])))
		fc.current = true
	if Game.args.has("pantest"):
		_pantest()
	if Game.args.has("invtest"):
		_invtest()
	if Game.args.has("cuttertest"):
		_cuttertest()
	if Game.args.has("mictest"):
		_mictest()
	if Game.args.has("hide"):
		for nm in str(Game.args["hide"]).split(","):
			var hn := find_child(nm, false, false) as Node3D
			if hn != null:
				hn.visible = false
	# test : --bright → tout éclairé, sans brouillard (pour inspecter la géométrie)
	if Game.args.has("bright"):
		env.volumetric_fog_enabled = false
		env.ambient_light_color = Color(0.8, 0.8, 0.78)
		env.ambient_light_energy = 1.6
		Game.set_fx("grain", 0.0)
	# test : --topdown → vue de dessus sans plafond autour du joueur
	if Game.args.has("topdown"):
		for ch in get_children():
			if ch is MeshInstance3D and (String(ch.name).begins_with("Ceil") or ch.name == "Frames"):
				(ch as MeshInstance3D).visible = false
		var td := Camera3D.new()
		td.projection = Camera3D.PROJECTION_ORTHOGONAL
		td.size = 16.0
		add_child(td)
		td.global_transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), player.global_position + Vector3(0, 12, 0))
		td.current = true
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-70, 20, 0)
		sun.light_energy = 1.5
		add_child(sun)


## Test automatique : grille → chaîne coupée → échelle → épilogue.
func _autotest() -> void:
	await wait(1.0)
	has_cutters = true
	power_on = true
	player.has_flashlight = true
	player.set_flashlight(true, true)
	player.global_position = tile_center(Vector2i(19, 11))
	player.set_look(PI, -0.1)
	_on_gate()
	await wait(1.5)
	_cut_chain()
	await wait(5.0)
	player.global_position = tile_center(EXIT) + Vector3(0, 0, -0.6)
	_climb()


# ================================================================== grille
func cell(t: Vector2i) -> String:
	if t.x < 0 or t.y < 0 or t.x >= W or t.y >= H:
		return "#"
	return MAP[t.y][t.x]


func walkable(t: Vector2i) -> bool:
	return cell(t) != "#"


func tile_center(t: Vector2i) -> Vector3:
	return Vector3((t.x + 0.5) * T, 0.0, (t.y + 0.5) * T)


func tile_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x / T)), 0, W - 1), clampi(int(floor(p.z / T)), 0, H - 1))


## Trois époques de construction : 0 = vieux collecteur voûté en briques (ouest),
## 1 = réservoir d'orage en béton (centre), 2 = galeries techniques carrelées (est).
func zone_of(t: Vector2i) -> int:
	if t.x <= 5:
		return 0
	if t.x <= 12:
		return 1
	return 2


## Axe d'un couloir droit (murs des deux côtés), ou ZERO pour une salle / un croisement.
func corridor_kind(t: Vector2i) -> Vector3:
	if not walkable(t) or t == EXIT:
		return Vector3.ZERO
	var wx := not walkable(t + Vector2i(1, 0)) and not walkable(t + Vector2i(-1, 0))
	var wz := not walkable(t + Vector2i(0, 1)) and not walkable(t + Vector2i(0, -1))
	if wx and not wz:
		return Vector3(0, 0, 1)
	if wz and not wx:
		return Vector3(1, 0, 0)
	return Vector3.ZERO


func is_vault(t: Vector2i) -> bool:
	return zone_of(t) == 0 and corridor_kind(t) != Vector3.ZERO


func is_hall(t: Vector2i) -> bool:
	return walkable(t) and t.x >= 6 and t.x <= 12 and t.y >= 7 and t.y <= 10 and corridor_kind(t) == Vector3.ZERO


## Hauteur sous plafond d'une case (sommet de voûte pour un collecteur).
func h_top(t: Vector2i) -> float:
	if not walkable(t):
		return 0.0
	if is_hall(t):
		return HALL_H
	if corridor_kind(t) != Vector3.ZERO and zone_of(t) > 0:
		return BOX_H[zone_of(t)]
	return CEIL


func _chan_capable(t: Vector2i) -> bool:
	return walkable(t) and zone_of(t) != 2 and not (cell(t) in ["S", "T", "G", "E", "w"])


## Cunette au centre de la case (réseau continu d'un collecteur à l'autre).
func has_channel(t: Vector2i) -> bool:
	if not _chan_capable(t) or is_hall(t):
		return false
	for d: Vector2i in DIRS:
		if _chan_capable(t + d) or cell(t + d) == "w":
			return true
	return false


func _link(t: Vector2i, d: Vector2i) -> bool:
	return has_channel(t) and (has_channel(t + d) or cell(t + d) == "w")


## La cellule (i, j) du découpage 3×3 d'une case est-elle dans la cunette ?
func _cell_chan(t: Vector2i, i: int, j: int) -> bool:
	if not has_channel(t):
		return false
	if i == 1 and j == 1:
		return true
	if i == 1 and j == 0:
		return _link(t, Vector2i(0, -1))
	if i == 1 and j == 2:
		return _link(t, Vector2i(0, 1))
	if i == 0 and j == 1:
		return _link(t, Vector2i(-1, 0))
	if i == 2 and j == 1:
		return _link(t, Vector2i(1, 0))
	return false


func in_channel(p: Vector3) -> bool:
	var t := tile_of(p)
	if not has_channel(t):
		return false
	var c := tile_center(t)
	var i := 0 if p.x < c.x - CH_W else (2 if p.x > c.x + CH_W else 1)
	var j := 0 if p.z < c.z - CH_W else (2 if p.z > c.z + CH_W else 1)
	return _cell_chan(t, i, j)


## Hauteur réelle du sol (la créature y pose les pieds).
func floor_y(p: Vector3) -> float:
	if cell(tile_of(p)) == "w":
		return CIS_Y
	if in_channel(p):
		return -CH_D
	return 0.0


func get_surface(pos: Vector3) -> String:
	if _on_glass(pos):
		return "glass"
	if cell(tile_of(pos)) == "w" or in_channel(pos):
		return "water"
	return "concrete"


# ================================================================== géométrie
var _surf := {}
var _culverts: Array = []  ## [position, normale] des arrivées d'eau sous grille


func _st(surf_name: String) -> SurfaceTool:
	if not _surf.has(surf_name):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surf[surf_name] = st
	return _surf[surf_name]


## Mur vertical de a à b (au sol), de `bottom` à `top`, soubassement jusqu'à ZONE_LOW.
## `na` / `nb` : normales aux deux bords (murs courbes, ombrage lisse) ; sinon normale plate.
func _wall(z: int, a: Vector3, b: Vector3, bottom: float, top: float, inward: Vector3, na := Vector3.ZERO, nb := Vector3.ZERO) -> void:
	var cut := clampf(ZONE_LOW[z], bottom, top)
	var normals := [] if na == Vector3.ZERO else [na, nb, nb, na]
	if cut > bottom:
		_quad_facing(_st("low%d" % z), Vector3(a.x, cut, a.z), Vector3(b.x, cut, b.z), Vector3(b.x, bottom, b.z), Vector3(a.x, bottom, a.z), inward, normals)
	if top > cut:
		_quad_facing(_st("wall%d" % z), Vector3(a.x, top, a.z), Vector3(b.x, top, b.z), Vector3(b.x, cut, b.z), Vector3(a.x, cut, a.z), inward, normals)


## Hauteur des murs droits d'une case (naissance de la voûte pour un collecteur voûté).
func _wall_top(t: Vector2i) -> float:
	return SPRING if is_vault(t) else h_top(t)


func _base(t: Vector2i) -> float:
	return CIS_Y if cell(t) == "w" else 0.0


## Bout de mur (case t, mur du côté d, extrémité vers e) : [retrait, hauteur jusqu'où il s'applique].
## Angle rentrant de la case → congé ; arête saillante du bloc voisin → arrondi.
func _wall_end(t: Vector2i, d: Vector2i, e: Vector2i) -> Vector2:
	if t == EXIT or t + e == EXIT or t + d + e == EXIT:
		return Vector2.ZERO
	if not walkable(t + e):
		return Vector2(R_IN[zone_of(t)], INF)
	if walkable(t + d + e):
		return Vector2(R_OUT, minf(_wall_top(t), _wall_top(t + d + e)))
	return Vector2.ZERO


var _bullnoses := {}


## Mur droit raccourci aux angles + gorge au pied ;
## les arêtes saillantes reçoivent leur arrondi (une seule fois par arête).
func _wall_rounded(t: Vector2i, d: Vector2i, a: Vector3, b: Vector3, bottom: float, top: float, inward: Vector3) -> void:
	var zn := zone_of(t)
	var dir := (b - a).normalized()
	var ea := Vector2i(int(round(-dir.x)), int(round(-dir.z)))
	var ends := [_wall_end(t, d, ea), _wall_end(t, d, -ea)]
	var cuts := [bottom, top]
	for en: Vector2 in ends:
		if en.y > bottom + 0.01 and en.y < top - 0.01:
			cuts.append(en.y)
	cuts.sort()
	for i in cuts.size() - 1:
		var h1: float = cuts[i + 1]
		var sa: float = ends[0].x if ends[0].y >= h1 - 0.001 else 0.0
		var sb: float = ends[1].x if ends[1].y >= h1 - 0.001 else 0.0
		_wall(zn, a + dir * sa, b - dir * sb, cuts[i], h1, inward)
	# gorge au pied du mur : fermée par un embout là où elle ne se prolonge pas (bout droit),
	# interrompue sous une porte de service
	var fa := a + dir * float(ends[0].x)
	var fb := b - dir * float(ends[1].x)
	var spans := [[fa, fb, ends[0].x == 0.0, ends[1].x == 0.0]]
	if [t, d] in SERVICE_DOORS:
		var d0 := a + dir * (T * 0.5 + DOOR_ALONG - DOOR_HALF)
		var d1 := a + dir * (T * 0.5 + DOOR_ALONG + DOOR_HALF)
		spans = [[fa, d0, ends[0].x == 0.0, true], [d1, fb, true, ends[1].x == 0.0]]
	for sp in spans:
		_cove(_st("low%d" % zn), sp[0], sp[1], inward, bottom, sp[2], sp[3])
	# arrondi des arêtes saillantes aux deux bouts
	for k in 2:
		var e: Vector2i = ea if k == 0 else -ea
		var en: Vector2 = ends[k]
		if absf(en.x - R_OUT) > 0.001:
			continue
		var p := (a if k == 0 else b)
		var key := Vector2i(int(round(p.x / T)), int(round(p.z / T)))
		if _bullnoses.has(key):
			continue
		_bullnoses[key] = true
		var u := t + d + e
		var dv := Vector3(d.x, 0, d.y)
		var ev := Vector3(e.x, 0, e.y)
		var q := p + dv * R_OUT - ev * R_OUT
		_arc_wall(zn, q, R_OUT, -dv, ev, minf(bottom, _base(u)), en.y, false)


## Congés verticaux dans les angles rentrants d'une case.
func _fillets(t: Vector2i) -> void:
	if t == EXIT:
		return
	var zn := zone_of(t)
	var r: float = R_IN[zn]
	var c := tile_center(t)
	for pair in [[Vector2i(1, 0), Vector2i(0, 1)], [Vector2i(0, 1), Vector2i(-1, 0)], [Vector2i(-1, 0), Vector2i(0, -1)], [Vector2i(0, -1), Vector2i(1, 0)]]:
		var d: Vector2i = pair[0]
		var e: Vector2i = pair[1]
		if walkable(t + d) or walkable(t + e) or t + d == EXIT or t + e == EXIT:
			continue
		var dv := Vector3(d.x, 0, d.y)
		var ev := Vector3(e.x, 0, e.y)
		var p := c + (dv + ev) * (T * 0.5)
		_arc_wall(zn, p - (dv + ev) * r, r, dv, ev, _base(t), _wall_top(t), true)


## Mur courbe (quart de cercle de centre q, ombrage lisse) + sa gorge qui suit la courbe.
func _arc_wall(zn: int, q: Vector3, r: float, u0: Vector3, u1: Vector3, bottom: float, top: float, concave: bool) -> void:
	const N := 6
	var pts: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	for i in N + 1:
		var th := PI * 0.5 * float(i) / N
		var u := u0 * cos(th) + u1 * sin(th)
		pts.append(q + u * r)
		nrm.append(-u if concave else u)
	for i in N:
		var n := (nrm[i] + nrm[i + 1]).normalized()
		_wall(zn, pts[i], pts[i + 1], bottom, top, n, nrm[i], nrm[i + 1])
		_slope(_st("low%d" % zn), pts[i], pts[i + 1], nrm[i], nrm[i + 1], bottom, COVE)


## Gorge droite (a → b) le long d'un mur, avec embouts triangulaires aux bouts demandés
## (sans eux on verrait « l'intérieur » de la gorge par le côté).
func _cove(st: SurfaceTool, a: Vector3, b: Vector3, n: Vector3, y: float, cap_a: bool, cap_b: bool) -> void:
	if a.distance_to(b) < 0.005:
		return
	_slope(st, a, b, n, n, y, COVE)
	var dir := (b - a).normalized()
	for k in 2:
		if not (cap_a if k == 0 else cap_b):
			continue
		var p: Vector3 = a if k == 0 else b
		var out := -dir if k == 0 else dir
		_tri_facing(st, Vector3(p.x, y + COVE, p.z), Vector3(p.x, y, p.z), Vector3(p.x, y, p.z) + n * COVE, out)


## Bande inclinée à 45° au pied d'un mur (a → b, normales na / nb vers l'espace libre).
func _slope(st: SurfaceTool, a: Vector3, b: Vector3, na: Vector3, nb: Vector3, y: float, size: float) -> void:
	if a.distance_to(b) < 0.005:
		return
	var want := (na + nb).normalized() + Vector3.UP
	var sn_a := (na + Vector3.UP).normalized()
	var sn_b := (nb + Vector3.UP).normalized()
	_quad_facing(st, Vector3(a.x, y + size, a.z), Vector3(b.x, y + size, b.z), Vector3(b.x, y, b.z) + nb * size, Vector3(a.x, y, a.z) + na * size, want, [sn_a, sn_b, sn_b, sn_a])


## Quad dont la face visible regarde vers `want` (l'ordre des sommets est corrigé si besoin).
## `normals` (a, b, c, d) : normales par sommet pour un ombrage lisse ; sinon normale plate.
## Les normales sont toujours données explicitement : le lissage automatique de SurfaceTool
## moyennait des faces perpendiculaires qui se touchent et « étirait » les textures triplanaires.
func _quad_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, normals := []) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		n = (d - a).cross(c - a)
	var flip := n.dot(want) < 0.0
	if normals.is_empty():
		var fn := (n * (-1.0 if flip else 1.0)).normalized()
		normals = [fn, fn, fn, fn]
	if flip:
		_quad(st, d, c, b, a, [normals[3], normals[2], normals[1], normals[0]])
	else:
		_quad(st, a, b, c, d, normals)


func _tri_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(want) < 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	st.set_normal(n.normalized())
	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(b)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(c)


func _hquad(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y: float, up := true) -> void:
	_quad_facing(st, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP if up else Vector3.DOWN)


func _build_geometry() -> void:
	var frame_st := SurfaceTool.new()  # pilastres, arcs, portiques (boîtes indexées : jamais mêlées aux autres)
	frame_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pil_st := SurfaceTool.new()
	pil_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pilaster := BoxMesh.new()
	pilaster.size = Vector3(0.26, SPRING, 0.08)
	var beam := BoxMesh.new()
	beam.size = Vector3(1, 1, 1)

	for z in H:
		for x in W:
			var t := Vector2i(x, z)
			if not walkable(t):
				continue
			var zn := zone_of(t)
			var c := tile_center(t)
			var kind := corridor_kind(t)
			var vault := is_vault(t)
			var htop := h_top(t)
			var is_exit := t == EXIT
			_floor_tile(t)
			# --- murs (et linteaux au-dessus des passages plus bas) ---
			for d: Vector2i in DIRS:
				var inward := Vector3(-d.x, 0, -d.y)
				var side_c := c + Vector3(d.x, 0, d.y) * (T * 0.5)
				var along := Vector3(-d.y, 0, d.x) * (T * 0.5)
				var a := side_c - along
				var b := side_c + along
				var base := CIS_Y if cell(t) == "w" else 0.0
				if is_exit:
					var bottom := base if not walkable(t + d) else h_top(t + d)
					_wall(zn, a, b, bottom, CEIL + 4.5, inward)
					continue
				if walkable(t + d):
					var hn := h_top(t + d)
					if hn < htop - 0.01 and not vault and t + d != EXIT:
						_quad_facing(_st("wall%d" % zn), Vector3(a.x, htop, a.z), Vector3(b.x, htop, b.z), Vector3(b.x, hn, b.z), Vector3(a.x, hn, a.z), inward)
					# portique en béton au passage d'une époque à l'autre
					if zone_of(t + d) != zn and (d.x > 0 or d.y > 0):
						_portal(frame_st, beam, side_c, Vector3(-d.y, 0, d.x), minf(htop, hn))
					continue
				_wall_rounded(t, d, a, b, base, _wall_top(t), inward)
			if is_exit:
				continue
			_fillets(t)
			# --- plafond ---
			if not vault:
				var ceil_st := _st("ceil%d" % zn)
				var x0 := x * T
				var z0 := z * T
				if t in SHAFTS:
					_shaft(t, htop)
				else:
					_hquad(ceil_st, x0, z0, x0 + T, z0 + T, htop, false)
				# galeries « caisson » : cadres en béton entre deux tronçons
				if kind != Vector3.ZERO:
					var prev_box := t - Vector2i(int(round(kind.x)), int(round(kind.z)))
					if walkable(prev_box) and corridor_kind(prev_box) == kind and zone_of(prev_box) == zn:
						var ac2 := Vector3(1, 0, 0) if absf(kind.z) > 0.5 else Vector3(0, 0, 1)
						var p := c - kind * (T * 0.5)
						for sg in [-1.0, 1.0]:
							var post_c: Vector3 = p + ac2 * sg * (T * 0.5 - 0.1) + Vector3(0, htop * 0.5, 0)
							frame_st.append_from(beam, 0, Transform3D(Basis.from_scale(_axis_size(ac2, kind, Vector3(0.2, htop, 0.3))), post_c))
						frame_st.append_from(beam, 0, Transform3D(Basis.from_scale(_axis_size(ac2, kind, Vector3(T, 0.22, 0.3))), p + Vector3(0, htop - 0.11, 0)))
				continue
			_vault(t, pil_st, pilaster)

	# --- matériaux ---
	var mats := {
		"floor0": B.mat("damaged_concrete_floor", 2.2, {"roughness": 0.45, "color": Color(0.5, 0.5, 0.46)}),
		"floor1": B.mat("cracked_concrete", 2.4, {"roughness": 0.5, "color": Color(0.55, 0.55, 0.52)}),
		"floor2": B.mat("dirty_concrete", 2.0, {"roughness": 0.55, "color": Color(0.6, 0.6, 0.58)}),
		"chan": B.mat("concrete_moss", 1.0, {"roughness": 0.35, "color": Color(0.35, 0.38, 0.3)}),
		"chanwall": B.mat("concrete_moss", 1.0, {"roughness": 0.35, "color": Color(0.4, 0.42, 0.34)}),
		"cis": B.mat("concrete_moss", 2.0, {"roughness": 0.4, "color": Color(0.3, 0.32, 0.26)}),
		"step": B.mat("concrete_moss", 1.2, {"roughness": 0.4, "color": Color(0.45, 0.47, 0.4)}),
		"low0": B.mat("concrete_moss", 1.6, {"roughness": 0.5, "color": Color(0.5, 0.52, 0.45)}),
		"wall0": B.mat("mossy_brick", 1.6, {"roughness": 0.7, "color": Color(0.62, 0.6, 0.55)}),
		"ceil0": B.mat("mossy_brick", 1.6, {"roughness": 0.7, "color": Color(0.52, 0.5, 0.46)}),
		"low1": B.mat("concrete_moss", 2.0, {"roughness": 0.45, "color": Color(0.42, 0.45, 0.38)}),
		"wall1": B.mat("concrete_wall_006", 2.5, {"roughness": 0.8, "color": Color(0.62, 0.62, 0.6)}),
		"ceil1": B.mat("hacked_concrete", 2.5, {"roughness": 0.85, "color": Color(0.5, 0.5, 0.48)}),
		"low2": B.mat("dirty_tiles", 1.2, {"roughness": 0.3, "color": Color(0.8, 0.82, 0.78)}),
		"wall2": B.mat("concrete_block_wall_02", 2.0, {"roughness": 0.8, "color": Color(0.6, 0.66, 0.62)}),
		"ceil2": B.mat("concrete_wall_006", 2.5, {"roughness": 0.85, "color": Color(0.5, 0.52, 0.5)}),
		"shaft": B.mat("castle_brick_07", 1.4, {"roughness": 0.8, "color": Color(0.55, 0.55, 0.52)}),
	}
	for m in mats.values():
		(m as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	# sols, murs et plafonds : mousse, sel, coulures, vase, flaques (shaders/sewer_surface.gdshader)
	for spec in [["floor0", "damaged_concrete_floor", 2.2, Color(0.5, 0.5, 0.46), 0.45, 0],
			["floor1", "cracked_concrete", 2.4, Color(0.55, 0.55, 0.52), 0.5, 1],
			["floor2", "dirty_concrete", 2.0, Color(0.6, 0.6, 0.58), 0.55, 2],
			["low0", "concrete_moss", 1.6, Color(0.5, 0.52, 0.45), 0.5, 0],
			["wall0", "mossy_brick", 1.6, Color(0.62, 0.6, 0.55), 0.7, 0],
			["ceil0", "mossy_brick", 1.6, Color(0.52, 0.5, 0.46), 0.7, 0],
			["low1", "concrete_moss", 2.0, Color(0.42, 0.45, 0.38), 0.45, 1],
			["wall1", "concrete_wall_006", 2.5, Color(0.62, 0.62, 0.6), 0.8, 1],
			["ceil1", "hacked_concrete", 2.5, Color(0.5, 0.5, 0.48), 0.85, 1],
			["low2", "dirty_tiles", 1.2, Color(0.8, 0.82, 0.78), 0.3, 2],
			["wall2", "concrete_block_wall_02", 2.0, Color(0.6, 0.66, 0.62), 0.8, 2],
			["ceil2", "concrete_wall_006", 2.5, Color(0.5, 0.52, 0.5), 0.85, 2]]:
		mats[spec[0]] = _sewer_surface(spec[1], spec[2], spec[3], spec[4], spec[5])
	var water_mat := ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	var rip := NoiseTexture2D.new()
	var rn := FastNoiseLite.new()
	rn.frequency = 0.035
	rip.noise = rn
	rip.seamless = true
	rip.as_normal_map = true
	rip.bump_strength = 5.0
	water_mat.set_shader_parameter("ripple", rip)
	water_mat.set_shader_parameter("speed", 0.05)
	water_mat.set_shader_parameter("color", Color(0.045, 0.05, 0.038))
	mats["water"] = water_mat
	_water_mat = water_mat
	var floor_faces := PackedVector3Array()
	for surf_name: String in _surf:
		var st: SurfaceTool = _surf[surf_name]
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.name = surf_name.capitalize().replace(" ", "")
		mi.mesh = st.commit()
		mi.material_override = mats.get(surf_name)
		add_child(mi)
		if surf_name.begins_with("floor") or surf_name in ["chan", "chanwall", "cis", "step"]:
			floor_faces.append_array(mi.mesh.get_faces())
	var frame_mi := MeshInstance3D.new()
	frame_mi.name = "Frames"
	frame_mi.mesh = frame_st.commit()
	frame_mi.material_override = _wet_concrete(0.0, 0.35, 0.0)
	add_child(frame_mi)
	var pil_mi := MeshInstance3D.new()
	pil_mi.name = "Pilasters"
	pil_mi.mesh = pil_st.commit()
	pil_mi.material_override = mats["wall0"]
	add_child(pil_mi)

	# collisions : sol exact (cunettes, citerne) + un pavé par case pleine bordant un couloir
	var body := StaticBody3D.new()
	add_child(body)
	var floor_shape := ConcavePolygonShape3D.new()
	floor_shape.set_faces(floor_faces)
	var fcs := CollisionShape3D.new()
	fcs.shape = floor_shape
	body.add_child(fcs)
	for z in H:
		for x in W:
			var t := Vector2i(x, z)
			if walkable(t):
				continue
			var near := false
			for d: Vector2i in DIRS:
				if walkable(t + d):
					near = true
			if not near:
				continue
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(T, HALL_H + 6.0, T)
			cs.shape = bs
			cs.position = tile_center(t) + Vector3(0, (HALL_H + 6.0) * 0.5 - 1.0, 0)
			body.add_child(cs)
	# eau de la citerne : un seul plan continu
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5 * T, 3 * T)
	water.mesh = pm
	water.material_override = water_mat
	water.name = "CisternWater"
	add_child(water)
	water.position = Vector3(9.5 * T, WATER_Y, 8.5 * T)
	# arrivées d'eau sous grille au bout des cunettes
	var grate_mat := B.color_mat(Color(0.12, 0.1, 0.08), 0.6, 0.8)
	for cv in _culverts:
		var pos: Vector3 = cv[0]
		var n: Vector3 = cv[1]
		var side := Vector3(-n.z, 0, n.x)
		var hole := B.quad(self, Vector2(0.5, 0.17), pos + n * 0.003 + Vector3(0, -0.11, 0), B.color_mat(Color(0.01, 0.01, 0.01), 1.0), Vector3(0, rad_to_deg(atan2(n.x, n.z)), 0))
		hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for k in 6:
			B.box(self, Vector3(0.018, 0.17, 0.018), pos + n * 0.012 + side * (-0.2 + k * 0.08) + Vector3(0, -0.11, 0), grate_mat, false)


## Taille d'une boîte orientée : x le long de `across`, z le long de `axis`.
func _axis_size(across: Vector3, axis: Vector3, s: Vector3) -> Vector3:
	if absf(across.x) > 0.5:
		return Vector3(s.x, s.y, s.z)
	return Vector3(s.z, s.y, s.x)


## Portique en béton (deux piliers + linteau) dans le plan de passage entre deux époques.
func _portal(st: SurfaceTool, box: BoxMesh, center: Vector3, across: Vector3, h: float) -> void:
	for sg in [-1.0, 1.0]:
		var p: Vector3 = center + across * sg * (T * 0.5 - 0.17) + Vector3(0, h * 0.5, 0)
		var size := Vector3(0.34, h, 0.55) if absf(across.x) > 0.5 else Vector3(0.55, h, 0.34)
		st.append_from(box, 0, Transform3D(Basis.from_scale(size), p))
	var lsize := Vector3(T, 0.4, 0.55) if absf(across.x) > 0.5 else Vector3(0.55, 0.4, T)
	st.append_from(box, 0, Transform3D(Basis.from_scale(lsize), center + Vector3(0, minf(h, CEIL) - 0.2, 0)))


## Sol d'une case : allées latérales + cunette creusée (fond, parois, eau), ou fond de citerne.
func _floor_tile(t: Vector2i) -> void:
	var zn := zone_of(t)
	var x0 := t.x * T
	var z0 := t.y * T
	var c := tile_center(t)
	if cell(t) == "w":
		_hquad(_st("cis"), x0, z0, x0 + T, z0 + T, CIS_Y)
		# marches : bord de la citerne (plus bas au droit d'une cunette qui s'y déverse)
		for d: Vector2i in DIRS:
			var n := t + d
			if not walkable(n) or cell(n) == "w":
				continue
			var side_c := c + Vector3(d.x, 0, d.y) * (T * 0.5)
			var tan := Vector3(-d.y, 0, d.x)
			var inward := Vector3(-d.x, 0, -d.y)
			var spans := [[-T * 0.5, -CH_W, 0.0], [-CH_W, CH_W, -CH_D if _link(n, -d) else 0.0], [CH_W, T * 0.5, 0.0]]
			for sp in spans:
				var pa: Vector3 = side_c + tan * float(sp[0])
				var pb: Vector3 = side_c + tan * float(sp[1])
				var top: float = sp[2]
				_quad_facing(_st("step"), Vector3(pa.x, top, pa.z), Vector3(pb.x, top, pb.z), Vector3(pb.x, CIS_Y, pb.z), Vector3(pa.x, CIS_Y, pa.z), inward)
		return
	var fl := _st("floor%d" % zn)
	if not has_channel(t):
		_hquad(fl, x0, z0, x0 + T, z0 + T, 0.0)
		return
	var xs := [x0, c.x - CH_W, c.x + CH_W, x0 + T]
	var zs := [z0, c.z - CH_W, c.z + CH_W, z0 + T]
	# coins arrondis : ils sont tous aux 4 coins de la cellule centrale
	var corners := {}  # Vector2i(i, j) → [[coin, intérieur de la cellule, rayon, l'éclat est-il de la cunette], ...]
	var trims := {}  # coin → rayon (les parois droites s'arrêtent avant la courbe)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var pc := Vector2(c.x + sx * CH_W, c.z + sz * CH_W)
			var arm_x := _cell_chan(t, 1 + sx, 1)
			var arm_z := _cell_chan(t, 1, 1 + sz)
			if arm_x and arm_z:
				# le coin de l'allée en diagonale avance dans l'eau : arrondi, l'éclat devient cunette
				var k := Vector2i(1 + sx, 1 + sz)
				corners[k] = corners.get(k, []) + [[pc, Vector2(sx, sz), CH_R_IN, true]]
				trims[_corner_key(pc)] = CH_R_IN
			elif not arm_x and not arm_z:
				# coin de la cunette elle-même (fond, extérieur de virage)
				corners[Vector2i(1, 1)] = corners.get(Vector2i(1, 1), []) + [[pc, Vector2(-sx, -sz), CH_R_OUT, false]]
				trims[_corner_key(pc)] = CH_R_OUT
	for i in 3:
		for j in 3:
			var ax: float = xs[i]
			var bx: float = xs[i + 1]
			var az: float = zs[j]
			var bz: float = zs[j + 1]
			var chan := _cell_chan(t, i, j)
			var cc: Array = corners.get(Vector2i(i, j), [])
			if cc.is_empty():
				if chan:
					_hquad(_st("chan"), ax, az, bx, bz, -CH_D)
					_hquad(_st("water"), ax, az, bx, bz, WATER_Y)
				else:
					_hquad(fl, ax, az, bx, bz, 0.0)
			else:
				var poly := _rounded_rect(ax, az, bx, bz, cc)
				if chan:
					_hpoly(_st("chan"), poly, -CH_D)
					_hpoly(_st("water"), poly, WATER_Y)
				else:
					_hpoly(fl, poly, 0.0)
				for co in cc:
					_channel_fillet(fl, co[0], co[1], co[2], co[3])
			if not chan:
				continue
			# parois : côtés qui donnent sur une allée de la même case
			for e in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var ni: int = i + int(e[0])
				var nj: int = j + int(e[1])
				if ni < 0 or ni > 2 or nj < 0 or nj > 2:
					continue  # bord de case : la cunette continue chez le voisin
				if _cell_chan(t, ni, nj):
					continue
				var wa: Vector2
				var wb: Vector2
				if e[0] != 0:
					var wx := ax if e[0] == -1 else bx
					wa = Vector2(wx, az)
					wb = Vector2(wx, bz)
				else:
					var wz := az if e[1] == -1 else bz
					wa = Vector2(ax, wz)
					wb = Vector2(bx, wz)
				var along := (wb - wa).normalized()
				wa += along * float(trims.get(_corner_key(wa), 0.0))
				wb -= along * float(trims.get(_corner_key(wb), 0.0))
				var into := Vector3(-float(e[0]), 0, -float(e[1]))
				_quad_facing(_st("chanwall"), Vector3(wa.x, 0, wa.y), Vector3(wb.x, 0, wb.y), Vector3(wb.x, -CH_D, wb.y), Vector3(wa.x, -CH_D, wa.y), into)
	# fin de cunette côté salle / galerie technique : l'eau arrive par une grille
	for d: Vector2i in DIRS:
		if walkable(t + d) and not _link(t, d) and cell(t + d) != "#":
			_culverts.append([c + Vector3(d.x, 0, d.y) * CH_W, Vector3(-d.x, 0, -d.y)])


func _corner_key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 1000.0), roundi(p.y * 1000.0))


## Points d'un quart de cercle remplaçant le coin `pc` d'une cellule dont l'intérieur est vers `dir`.
func _corner_arc(pc: Vector2, dir: Vector2, r: float) -> PackedVector2Array:
	var cen := pc + dir * r
	var pts := PackedVector2Array()
	for k in 7:
		var th := PI * 0.5 * float(k) / 6.0
		pts.append(cen + Vector2(-dir.x * cos(th), -dir.y * sin(th)) * r)
	return pts


## Rectangle [ax, bx] × [az, bz] dont certains coins sont arrondis (polygone convexe, ordonné).
func _rounded_rect(ax: float, az: float, bx: float, bz: float, cc: Array) -> PackedVector2Array:
	var pts: Array[Vector2] = []
	var rounded := {}
	for co in cc:
		rounded[_corner_key(co[0])] = true
		for q in _corner_arc(co[0], co[1], co[2]):
			pts.append(q)
	for q in [Vector2(ax, az), Vector2(bx, az), Vector2(bx, bz), Vector2(ax, bz)]:
		if not rounded.has(_corner_key(q)):
			pts.append(q)
	var mid := Vector2((ax + bx) * 0.5, (az + bz) * 0.5)
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return (a - mid).angle() < (b - mid).angle())
	return PackedVector2Array(pts)


## Polygone convexe horizontal (éventail depuis son centre), face vers le haut.
func _hpoly(st: SurfaceTool, poly: PackedVector2Array, y: float) -> void:
	var mid := Vector2.ZERO
	for q in poly:
		mid += q
	mid /= poly.size()
	var m3 := Vector3(mid.x, y, mid.y)
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		_tri_facing(st, m3, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3.UP)


## Éclat retiré par un coin arrondi (entre le coin et la courbe) + paroi courbe de la cunette.
## `sliver_chan` : l'éclat est de l'eau (coin d'allée arrondi) ; sinon c'est de l'allée.
func _channel_fillet(fl: SurfaceTool, pc: Vector2, dir: Vector2, r: float, sliver_chan: bool) -> void:
	var arc := _corner_arc(pc, dir, r)
	var cen := pc + dir * r
	for k in arc.size() - 1:
		var a := arc[k]
		var b := arc[k + 1]
		if sliver_chan:
			_tri_facing(_st("chan"), Vector3(pc.x, -CH_D, pc.y), Vector3(a.x, -CH_D, a.y), Vector3(b.x, -CH_D, b.y), Vector3.UP)
			_tri_facing(_st("water"), Vector3(pc.x, WATER_Y, pc.y), Vector3(a.x, WATER_Y, a.y), Vector3(b.x, WATER_Y, b.y), Vector3.UP)
		else:
			_tri_facing(fl, Vector3(pc.x, 0.0, pc.y), Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y), Vector3.UP)
		# la paroi regarde toujours vers l'eau
		var na := Vector3(a.x - cen.x, 0, a.y - cen.y).normalized() * (1.0 if sliver_chan else -1.0)
		var nb := Vector3(b.x - cen.x, 0, b.y - cen.y).normalized() * (1.0 if sliver_chan else -1.0)
		_quad_facing(_st("chanwall"), Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, -CH_D, b.y), Vector3(a.x, -CH_D, a.y), na + nb, [na, nb, nb, na])


## Voûte en berceau d'un collecteur de la zone A, tympans, arcs de renfort et pilastres.
func _vault(t: Vector2i, pil_st: SurfaceTool, pilaster: BoxMesh) -> void:
	var c := tile_center(t)
	var ax: Vector3 = corridor_kind(t)
	var ac := Vector3(1, 0, 0) if absf(ax.z) > 0.5 else Vector3(0, 0, -1)
	var r := T * 0.5
	var segs := 14
	var arc: Array[Vector3] = []
	for i in segs + 1:
		var th := PI * float(i) / segs
		arc.append(Vector3(c.x, SPRING, c.z) + ac * cos(th) * r + Vector3.UP * sin(th) * r)
	var s0 := -ax * (T * 0.5)
	var s1 := ax * (T * 0.5)
	var ceil_st := _st("ceil0")
	var wall_st := _st("wall0")
	for i in segs:
		var axis_c := Vector3(c.x, SPRING, c.z)
		var na := (axis_c - arc[i]).normalized()
		var nb := (axis_c - arc[i + 1]).normalized()
		_quad_facing(ceil_st, arc[i] + s0, arc[i + 1] + s0, arc[i + 1] + s1, arc[i] + s1, (axis_c - (arc[i] + arc[i + 1]) * 0.5).normalized(), [na, nb, nb, na])
	# extrémités : tympan au-dessus de l'arc (vers une salle) ou lunette (cul-de-sac)
	for sgn in [-1.0, 1.0]:
		var face_dir: Vector3 = ax * sgn
		var nt := t + Vector2i(int(round(face_dir.x)), int(round(face_dir.z)))
		var off := face_dir * (T * 0.5)
		if walkable(nt) and corridor_kind(nt) == ax and zone_of(nt) == 0:
			continue
		if not walkable(nt):
			var center := Vector3(c.x, SPRING, c.z) + off
			for i in segs:
				_tri_facing(wall_st, center, arc[i] + off, arc[i + 1] + off, -face_dir)
		else:
			for i in segs:
				var p0 := arc[i] + off
				var p1 := arc[i + 1] + off
				_quad_facing(wall_st, p0, p1, Vector3(p1.x, CEIL, p1.z), Vector3(p0.x, CEIL, p0.z), face_dir)
	# arc de renfort en brique entre deux tronçons + pilastres
	var prev := t - Vector2i(int(round(ax.x)), int(round(ax.z)))
	if walkable(prev) and corridor_kind(prev) == ax and zone_of(prev) == 0:
		var rr := r - 0.08
		var band := 0.13
		var inner: Array[Vector3] = []
		for i in segs + 1:
			var th2 := PI * float(i) / segs
			inner.append(Vector3(c.x, SPRING, c.z) + ac * cos(th2) * rr + Vector3.UP * sin(th2) * rr)
		for i in segs:
			var ca := Vector3(c.x, SPRING, c.z)
			_quad_facing(wall_st, inner[i] + s0 - ax * band, inner[i + 1] + s0 - ax * band, inner[i + 1] + s0 + ax * band, inner[i] + s0 + ax * band, (ca - inner[i]).normalized())
			for sg in [-1.0, 1.0]:
				var o: Vector3 = s0 + ax * band * sg
				_quad_facing(wall_st, arc[i] + o, arc[i + 1] + o, inner[i + 1] + o, inner[i] + o, ax * sg)
		for sg2 in [-1.0, 1.0]:
			var wall_pt: Vector3 = Vector3(c.x, SPRING * 0.5, c.z) + ac * sg2 * (r - 0.04) + s0
			pil_st.append_from(pilaster, 0, Transform3D(Basis.looking_at(ac * sg2, Vector3.UP), wall_pt))


## Puits vers la rue : trémie dans le plafond, conduit en briques, grille, clair de lune.
func _shaft(t: Vector2i, h: float) -> void:
	var zn := zone_of(t)
	var c := tile_center(t)
	var x0 := t.x * T
	var z0 := t.y * T
	var hs := 0.55
	var ceil_st := _st("ceil%d" % zn)
	_hquad(ceil_st, x0, z0, x0 + T, c.z - hs, h, false)
	_hquad(ceil_st, x0, c.z + hs, x0 + T, z0 + T, h, false)
	_hquad(ceil_st, x0, c.z - hs, c.x - hs, c.z + hs, h, false)
	_hquad(ceil_st, c.x + hs, c.z - hs, x0 + T, c.z + hs, h, false)
	var top := h + 2.2
	var sh := _st("shaft")
	for d: Vector2i in DIRS:
		var side_c := c + Vector3(d.x, 0, d.y) * hs
		var along := Vector3(-d.y, 0, d.x) * hs
		var a := side_c - along
		var b := side_c + along
		_quad_facing(sh, Vector3(a.x, top, a.z), Vector3(b.x, top, b.z), Vector3(b.x, h, b.z), Vector3(a.x, h, a.z), Vector3(-d.x, 0, -d.y))
	var iron := B.color_mat(Color(0.08, 0.075, 0.07), 0.6, 0.7)
	for k in 9:
		B.box(self, Vector3(0.03, 0.05, hs * 2.0), c + Vector3(-hs + 0.06 + k * 0.122, top - 0.05, 0), iron, false)
	var moon := B.spot(self, c + Vector3(0.25, top + 1.5, 0.1), c + Vector3(-0.3, 0, -0.2), Color(0.55, 0.66, 0.95), 9.0, top + 4.0, 24.0, true)
	moon.light_volumetric_fog_energy = 4.0
	moon.shadow_blur = 1.5
	_shaft_tops.append([c, top, moon])


# ================================================================== canalisations
const PIPE_INSET := 0.22


## Canalisations continues le long des murs : elles suivent le mur d'une case à l'autre,
## se rejoignent dans les angles (coude) et plongent dans la maçonnerie là où le mur s'arrête.
func _build_pipes() -> void:
	var rust := SurfaceTool.new()
	rust.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grey := SurfaceTool.new()
	grey.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 12
	sph.rings = 6
	var box := BoxMesh.new()
	for z in H:
		for x in W:
			var t := Vector2i(x, z)
			if not walkable(t) or cell(t) in ["E", "G", "w"]:
				continue
			var zn := zone_of(t)
			# [hauteur, rayon, retrait supplémentaire] ; rayon < 0 = chemin de câbles
			var lines: Array = [[1.38, 0.085, 0.0]]
			if zn == 1:
				lines = [[1.62, 0.11, 0.0], [1.26, 0.045, -0.06]]
			elif zn == 2:
				lines = [[2.22, 0.024, -0.1], [2.3, 0.024, -0.1], [2.46, -1.0, 0.0]]
			var st := grey if zn == 2 else rust
			for d: Vector2i in DIRS:
				if walkable(t + d):
					continue
				var dn := Vector3(d.x, 0, d.y)
				var tan := Vector2i(-d.y, d.x)
				var tan3 := Vector3(tan.x, 0, tan.y)
				for ln in lines:
					var y: float = ln[0]
					var r: float = ln[1]
					var inset: float = PIPE_INSET + float(ln[2])
					var lc := tile_center(t) + dn * (T * 0.5 - inset) + Vector3(0, y, 0)
					var ends: Array[Vector3] = []
					for e in [-1, 1]:
						var n: Vector2i = t + tan * int(e)
						var endp: Vector3 = lc + tan3 * (T * 0.5) * e
						if not walkable(n):
							# coin rentrant : on s'arrête au coin, coude commun avec le mur voisin
							endp = lc + tan3 * (T * 0.5 - inset) * e
							if r > 0.0:
								st.append_from(sph, 0, Transform3D(Basis.from_scale(Vector3.ONE * r), endp))
						elif walkable(n + d) or cell(n) in ["E", "G", "w"] or zone_of(n) != zn:
							# le mur s'arrête : le tuyau plonge dans la maçonnerie (bride au mur)
							if r > 0.0:
								endp -= tan3 * e * (r + 0.05)
								st.append_from(sph, 0, Transform3D(Basis.from_scale(Vector3.ONE * r), endp))
								_pipe_seg(st, cyl, endp, endp + dn * (inset + 0.1), r)
								_pipe_seg(st, cyl, endp + dn * (inset - 0.03), endp + dn * (inset + 0.005), r * 1.5)
							else:
								endp -= tan3 * e * 0.05
						ends.append(endp)
					if r > 0.0:
						_pipe_seg(st, cyl, ends[0], ends[1], r)
						# colliers de fixation
						if r > 0.04:
							for k in [-0.7, 0.7]:
								var cp: Vector3 = lc + tan3 * k
								_pipe_seg(st, cyl, cp - tan3 * 0.025, cp + tan3 * 0.025, r * 1.18)
								var arm := Vector3(inset, 0.04, 0.05) if absf(dn.x) > 0.5 else Vector3(0.05, 0.04, inset)
								st.append_from(box, 0, Transform3D(Basis.from_scale(arm), cp + dn * (inset * 0.5)))
					else:
						# chemin de câbles : tôle en U + quelques câbles
						var mid := (ends[0] + ends[1]) * 0.5
						var length := ends[0].distance_to(ends[1])
						var tray := Vector3(length, 0.05, 0.3) if absf(tan3.x) > 0.5 else Vector3(0.3, 0.05, length)
						st.append_from(box, 0, Transform3D(Basis.from_scale(tray), mid + dn * 0.04))
						for k in 3:
							var cofs: Vector3 = dn * (0.0 + k * 0.06 - 0.02) + Vector3(0, 0.04, 0)
							_pipe_seg(st, cyl, ends[0] + cofs, ends[1] + cofs, 0.014)
	for pair in [[rust, B.mat("rusty_metal_02", 1.0, {"metallic": 0.6, "roughness": 0.75})], [grey, B.color_mat(Color(0.32, 0.33, 0.33), 0.5, 0.7)]]:
		var mi := MeshInstance3D.new()
		mi.name = "Pipes"
		mi.mesh = (pair[0] as SurfaceTool).commit()
		mi.material_override = pair[1]
		add_child(mi)


func _pipe_seg(st: SurfaceTool, cyl: CylinderMesh, a: Vector3, b: Vector3, r: float) -> void:
	var length := a.distance_to(b)
	if length < 0.001:
		return
	var bs := _axis_basis(b - a)
	st.append_from(cyl, 0, Transform3D(Basis(bs.x * r, bs.y * length, bs.z * r), (a + b) * 0.5))


func _axis_basis(along: Vector3) -> Basis:
	# cylindre : axe Y du maillage aligné sur `along`
	var y := along.normalized()
	var x := Vector3.UP.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normals: Array) -> void:
	# a-b-c-d dans le sens horaire vu depuis la face visible
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normals[k])
		st.set_uv([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)][k])
		st.add_vertex([a, b, c, d][k])


# ================================================================== navigation
func _build_navigation() -> void:
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	for z in H:
		for x in W:
			astar.set_point_solid(Vector2i(x, z), not walkable(Vector2i(x, z)))
	astar.set_point_solid(GATE, true)
	astar.set_point_solid(EXIT, true)


func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := tile_of(from)
	var b := tile_of(to)
	var out := PackedVector3Array()
	if astar.is_point_solid(b):
		return out
	var ids := astar.get_id_path(a, b, true)
	# voie du moment : une banquette, l'autre, ou en plein dans la cunette (voir _process)
	for i in ids.size():
		var c := tile_center(ids[i])
		var kind := corridor_kind(ids[i])
		if has_channel(ids[i]) and kind != Vector3.ZERO and i < ids.size() - 1 and _ledge_side != 0.0:
			c += Vector3(kind.z, 0, kind.x) * 0.72 * _ledge_side
		if i == 0 and from.distance_to(c) < 1.2:
			continue
		out.append(c)
	var end := Vector3(clampf(to.x, b.x * T + 0.5, (b.x + 1) * T - 0.5), 0.0, clampf(to.z, b.y * T + 0.5, (b.y + 1) * T - 0.5))
	out.append(end)
	return out


func random_point(near: Vector3, max_tiles: int) -> Vector3:
	var c := tile_of(near)
	for _i in 40:
		var t := c + Vector2i(randi_range(-max_tiles, max_tiles), randi_range(-max_tiles, max_tiles))
		if t.x < 0 or t.y < 0 or t.x >= W or t.y >= H:
			continue
		if astar.is_point_solid(t) or t == c:
			continue
		return tile_center(t)
	return tile_center(c)


func has_los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Fuites de vapeur dans les galeries techniques : sur les canalisations qui courent en haut des murs,
## un raccord fuit et crache un jet qui siffle vers le bas (il couvre les petits bruits... et ceux de la créature).
func _build_steam() -> void:
	_steam_spots.clear()
	var dark := B.color_mat(Color(0.16, 0.16, 0.15), 0.45, 0.8)
	for spec in STEAM_LEAKS:
		var t: Vector2i = spec[0]
		var d: Vector2i = spec[1]
		var c := tile_center(t)
		var dn := Vector3(d.x, 0, d.y)
		var tan := Vector3(-d.y, 0, d.x)
		# la canalisation basse des deux qui longent le mur (2,22 m, à 12 cm du mur : voir _build_pipes)
		var leak := c + dn * (T * 0.5 - (PIPE_INSET - 0.1)) + tan * float(spec[2]) + Vector3(0, 2.22, 0)
		# le raccord qui fuit : un manchon un peu plus gros autour du tuyau existant
		var sleeve := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.042
		cm.bottom_radius = 0.042
		cm.height = 0.07
		cm.radial_segments = 12
		sleeve.mesh = cm
		sleeve.material_override = dark
		add_child(sleeve)
		sleeve.global_transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5) if absf(tan.x) > 0.5 else Basis(Vector3(1, 0, 0), PI * 0.5), leak)
		# jet vers l'avant et vers le bas : il descend dans la galerie avant de remonter en nuage
		var out := (-dn * 0.75 + Vector3(0, -0.55, 0) + tan * 0.2).normalized()
		var jet := Nature.steam(self, leak - dn * 0.03, out)
		jet.name = "SteamLeak"
		Sound.loop_at("steam_hiss_loop", jet, -5.0, 2.0, 16.0)
		# le mur ruisselle sous la fuite, une flaque au sol
		B.decal(self, "res://assets/gen/decal_grime.png", leak + dn * 0.12 + Vector3(0, -0.8, 0), -dn, 0.6, 1.6, 0.2, Color(1, 1, 1, 0.75))
		B.decal(self, "res://assets/gen/decal_puddle.png", Vector3(leak.x, 0.0, leak.z) - dn * 0.6, Vector3.UP, 1.2, 1.0, 0.2, Color(1, 1, 1, 0.85))
		_steam_spots.append(Vector3(leak.x, 1.4, leak.z))


## Coup de vent dans la forêt au-dessus d'un puits : le vent siffle dans la grille, quelques feuilles
## mortes tombent en tourbillonnant, la lune tremble à travers les branches ; parfois une chouette.
func _forest_gust(c: Vector3, top: float, moon: SpotLight3D) -> void:
	Sound.play_at("wind_gust", c + Vector3(0, top + 0.8, 0), 2.0, randf_range(0.9, 1.1), 6.0, 40.0)
	# les feuilles se posent sur la passerelle ou flottent sur l'eau
	Nature.leaves(self, c + Vector3(0, top - 0.15, 0), func(p: Vector3) -> float: return maxf(floor_y(p), WATER_Y), randi_range(5, 9))
	var base := moon.global_position
	var energy := moon.light_energy
	var t := 0.0
	var dripped := false
	while t < 4.2:
		await ticked
		t += get_process_delta_time()
		var k := sin(clampf(t / 4.2, 0.0, 1.0) * PI)
		# les branches balancées par le vent passent devant la lune
		moon.light_energy = energy * (1.0 - k * (0.35 + 0.3 * sin(t * 7.3) * sin(t * 2.9)))
		moon.global_position = base + Vector3(sin(t * 2.7) * 0.3, 0, cos(t * 2.1) * 0.22) * k
		if t > 1.6 and not dripped:
			dripped = true
			Sound.play_at(Sound.variant("drip", 3), c + Vector3(0, top - 0.2, 0), -8.0, 1.0, 3.0, 20.0)
	moon.light_energy = energy
	moon.global_position = base
	if randf() < 0.35:
		await wait(randf_range(1.5, 4.0))
		Sound.play_at("owl_hoot", c + Vector3(0, top + 6.0, 0), -2.0, randf_range(0.95, 1.05), 8.0, 45.0)


func _steam_dist(pos: Vector3) -> float:
	var best := INF
	for sp in _steam_spots:
		best = minf(best, Vector2(pos.x - sp.x, pos.z - sp.z).length())
	return best


func obstacles() -> Array:
	return pillars


func on_noise(pos: Vector3, radius: float) -> void:
	# près de la fuite de vapeur, le sifflement couvre les petits bruits
	if _steam_dist(pos) < 4.5:
		radius *= 0.55
	if creature != null:
		creature.hear(pos, radius)


## Bruit d'un objet (bouteille qui éclate) : la créature fonce voir, sans pister Théo.
func lure_noise(pos: Vector3, radius: float) -> void:
	if creature != null:
		creature.hear(pos, radius, true)


# ================================================================== décor
func _wall_tiles(t: Vector2i) -> Array:
	var out := []
	for d: Vector2i in DIRS:
		if not walkable(t + d):
			out.append(d)
	return out


## Position contre un mur (côté `d` de la case t), à `inset` m du mur.
func wall_pos(t: Vector2i, d: Vector2i, inset := 0.3, along := 0.0) -> Vector3:
	var c := tile_center(t)
	var side := Vector3(d.x, 0, d.y)
	var tangent := Vector3(-d.y, 0, d.x)
	return c + side * (T * 0.5 - inset) + tangent * along


func yaw_facing(dir: Vector3) -> float:
	return rad_to_deg(atan2(dir.x, dir.z))


## Objet de décor, déplaçable avec l'éditeur de carte (F8) ; ignoré si le joueur a sauvegardé
## sa propre disposition (elle est recréée depuis le fichier).
func deco(slug: String, pos: Vector3, yaw := 0.0, fit := {}) -> Node3D:
	if _layout != null:
		return null
	var n := B.model(self, slug, pos, yaw, fit)
	n.set_meta("decor", true)
	return n


## Pour l'éditeur de carte intégré.
func editor_map() -> Dictionary:
	return {"id": "egouts", "root": self, "nom": "Égouts"}


## Cases « libres » d'une époque (pas les salles scénarisées), avec au moins un mur.
func _decor_tiles(zn: int) -> Array:
	var out := []
	for z in H:
		for x in W:
			var t := Vector2i(x, z)
			if walkable(t) and zone_of(t) == zn and not (cell(t) in ["S", "T", "G", "E", "w"]) and not _wall_tiles(t).is_empty():
				out.append(t)
	return out


func _build_props() -> void:
	# --- A : vieux collecteur (détritus, mousse, déversoirs)
	var junk := ["trashbag", "can_rusted", "old_tyre", "wooden_crate_01", "cardboard_box_01", "trashbag"]
	for t: Vector2i in _decor_tiles(0):
		var walls := _wall_tiles(t)
		var d: Vector2i = walls[_rng.randi() % walls.size()]
		if _rng.randf() < 0.4:
			var slug: String = junk[_rng.randi() % junk.size()]
			var m := deco(slug, wall_pos(t, d, 0.42, _rng.randf_range(-0.9, 0.9)), _rng.randf_range(0, 360))
			if slug == "old_tyre" and m != null:
				m.rotation_degrees.x = 80.0
				m.position.y = 0.06
		for wd: Vector2i in walls:
			if _rng.randf() < 0.55:
				B.decal(self, "res://assets/gen/decal_moss.png", wall_pos(t, wd, 0.0, _rng.randf_range(-0.7, 0.7)) + Vector3(0, 0.45, 0), Vector3(-wd.x, 0, -wd.y), _rng.randf_range(1.4, 2.6), 0.9, 0.4)
	# déversoirs : une vieille conduite crache un filet d'eau au pied du mur
	for spec in [[Vector2i(4, 2), Vector2i(1, 0)], [Vector2i(2, 9), Vector2i(0, -1)], [Vector2i(3, 13), Vector2i(0, 1)], [Vector2i(1, 6), Vector2i(-1, 0)]]:
		_outfall(spec[0], spec[1])
	# --- B : réservoir d'orage (béton, échelles, bidons, piliers dans la citerne)
	var gear_b := ["plastic_jerrycan", "propane_tank", "rusted_wheel_rim_01", "Barrel_01", "wooden_crate_01", "plastic_jerrycan"]
	for t: Vector2i in _decor_tiles(1):
		if _rng.randf() > 0.38:
			continue
		var walls := _wall_tiles(t)
		var d: Vector2i = walls[_rng.randi() % walls.size()]
		var slug: String = gear_b[_rng.randi() % gear_b.size()]
		deco(slug, wall_pos(t, d, 0.4, _rng.randf_range(-0.8, 0.8)), _rng.randf_range(0, 360), {"collide": slug in ["Barrel_01", "wooden_crate_01"]})
	for spec in [[Vector2i(6, 2), Vector2i(-1, 0)], [Vector2i(10, 12), Vector2i(0, 1)]]:
		var lad := deco("wooden_ladder", wall_pos(spec[0], spec[1], 0.32), yaw_facing(Vector3(-spec[1].x, 0, -spec[1].y)), {"part": "wooden_ladder_steps", "height": 2.3})
		if lad != null:
			lad.rotation_degrees.x = -14.0
	deco("WetFloorSign_01", tile_center(Vector2i(6, 6 - 1)) + Vector3(0.9, 0, -0.9), 30.0)
	var col_mat := _wet_concrete(WATER_Y, 0.55, 1.0)
	for cx in [8.5, 10.5]:
		for cz in [7.85, 9.15]:
			var cp := Vector3(cx * T, (HALL_H + CIS_Y) * 0.5, cz * T)
			B.box(self, Vector3(0.6, HALL_H - CIS_Y, 0.6), cp, col_mat, true)
			# socle en béton au pied de chaque poteau (l'un d'eux porte un fusible)
			B.box(self, Vector3(0.95, 0.26, 0.95), Vector3(cp.x, CIS_Y + 0.13, cp.z), col_mat, true)
			pillars.append([Vector3(cp.x, 0, cp.z), 0.52])
	for cx2 in [8.5, 10.5]:
		B.decal(self, "res://assets/gen/decal_gauge.png", Vector3(cx2 * T, 0.75, 9.15 * T + 0.3), Vector3(0, 0, 1), 0.28, 1.5, 0.08)
	B.decal(self, "res://assets/gen/decal_gauge.png", Vector3(6 * T + 0.01, 0.9, 8.5 * T), Vector3(1, 0, 0), 0.3, 1.6, 0.1)
	# --- C : galeries techniques (armoires électriques, extincteurs, caisses, portes de service)
	var gear_c := ["utility_box_02", "korean_fire_extinguisher_01", "plastic_crate_03", "old_military_crate", "hand_truck", "plastic_crate_03"]
	for t: Vector2i in _decor_tiles(2):
		var walls := _wall_tiles(t)
		for wd: Vector2i in walls:
			B.decal(self, "res://assets/gen/decal_hazard.png", wall_pos(t, wd, 0.0) + Vector3(0, 0.3, 0), Vector3(-wd.x, 0, -wd.y), T, 0.2, 0.06)
		if _rng.randf() < 0.3:
			B.decal(self, "res://assets/gen/decal_puddle.png", tile_center(t) + Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.6, 0.6)), Vector3.UP, _rng.randf_range(0.9, 1.8), _rng.randf_range(0.8, 1.5), 0.2)
		if _rng.randf() > 0.42:
			continue
		var d: Vector2i = walls[_rng.randi() % walls.size()]
		var slug: String = gear_c[_rng.randi() % gear_c.size()]
		var fit := {}
		var inset := 0.4
		if slug == "utility_box_02":
			inset = 0.24
		elif slug == "korean_fire_extinguisher_01":
			fit = {"height": 0.6}
		elif slug == "old_military_crate":
			fit = {"part": "old_military_crate_a", "width": 0.8}
		var m := deco(slug, wall_pos(t, d, inset, _rng.randf_range(-0.7, 0.7)), yaw_facing(Vector3(-d.x, 0, -d.y)), fit)
		if slug == "utility_box_02":
			B.decal(self, "res://assets/gen/decal_danger.png", wall_pos(t, d, 0.0) + Vector3(0, 1.75, 0), Vector3(-d.x, 0, -d.y), 0.9, 0.34, 0.1)
			if m != null:
				m.name = "UtilityBox"
	for spec in SERVICE_DOORS:
		_service_door(spec[0], spec[1])
	# rats
	for t4 in [Vector2i(4, 3), Vector2i(10, 5), Vector2i(16, 8), Vector2i(3, 13), Vector2i(17, 4)]:
		var rat := Rat.new()
		rat.level = self
		add_child(rat)
		rat.position = tile_center(t4) + Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.6, 0.6))


## Vieille conduite qui sort du mur et laisse couler un filet d'eau jusqu'au sol.
func _outfall(t: Vector2i, d: Vector2i) -> void:
	var n := Vector3(-d.x, 0, -d.y)
	var wall := wall_pos(t, d, 0.0, 0.6) + Vector3(0, 0.62, 0)
	var rust := B.mat("rusty_metal_02", 0.6, {"metallic": 0.6, "roughness": 0.7, "color": Color(0.8, 0.7, 0.6)})
	var pipe := B.cylinder(self, 0.12, 0.12, 0.42, wall + n * 0.19, rust, false, 16)
	pipe.basis = _axis_basis(n)
	var lip := B.cylinder(self, 0.145, 0.145, 0.05, wall + n * 0.38, rust, false, 16)
	lip.basis = _axis_basis(n)
	var inner := B.cylinder(self, 0.1, 0.1, 0.02, wall + n * 0.395, B.color_mat(Color(0.01, 0.01, 0.01), 1.0), false, 16)
	inner.basis = _axis_basis(n)
	var flange := B.cylinder(self, 0.2, 0.2, 0.03, wall + n * 0.015, rust, false, 16)
	flange.basis = _axis_basis(n)
	var mouth := wall + n * 0.42 + Vector3(0, -0.08, 0)
	var stream_mat := ShaderMaterial.new()
	stream_mat.shader = load("res://shaders/stream.gdshader")
	var s := B.quad(self, Vector2(0.12, mouth.y), Vector3(mouth.x, mouth.y * 0.5, mouth.z), stream_mat, Vector3(0, yaw_facing(n) + 90.0, 0))
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var s2 := B.quad(self, Vector2(0.12, mouth.y), Vector3(mouth.x, mouth.y * 0.5, mouth.z), stream_mat, Vector3(0, yaw_facing(n), 0))
	s2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.decal(self, "res://assets/gen/decal_puddle.png", mouth + n * 0.3 - Vector3(0, mouth.y, 0), Vector3.UP, 1.0, 1.3, 0.2)
	var snd := Node3D.new()
	add_child(snd)
	snd.position = mouth
	Sound.loop_at("water_flow_loop", snd, -14.0, 1.0, 9.0)


## Porte de service métallique (fermée) dans un mur des galeries techniques.
func _service_door(t: Vector2i, d: Vector2i) -> void:
	if walkable(t + d) or not walkable(t):
		return  # pas de mur de ce côté (ou case pleine) : la porte n'aurait aucun sens
	var n := Vector3(-d.x, 0, -d.y)
	var pos := wall_pos(t, d, 0.0, DOOR_ALONG)
	var yaw := yaw_facing(n)
	var frame := B.color_mat(Color(0.18, 0.2, 0.2), 0.5, 0.7)
	var door := B.mat("rusty_metal_sheet", 1.0, {"metallic": 0.5, "roughness": 0.7, "color": Color(0.55, 0.6, 0.58)})
	var holder := Node3D.new()
	add_child(holder)
	holder.position = pos
	holder.rotation_degrees.y = yaw
	B.box(holder, Vector3(0.95, 2.05, 0.05), Vector3(0, 1.025, 0.03), door, false)
	for sx in [-0.5, 0.5]:
		B.box(holder, Vector3(0.06, 2.12, 0.08), Vector3(sx, 1.06, 0.04), frame, false)
	B.box(holder, Vector3(1.06, 0.06, 0.08), Vector3(0, 2.1, 0.04), frame, false)
	B.box(holder, Vector3(0.12, 0.03, 0.04), Vector3(0.33, 1.0, 0.075), B.color_mat(Color(0.5, 0.5, 0.48), 0.3, 0.9), false)
	B.decal(self, "res://assets/gen/decal_danger.png", pos + n * 0.06 + Vector3(0, 1.6, 0), n, 0.7, 0.26, 0.12)


func _build_lights() -> void:
	var warm := Color(1.0, 0.62, 0.32)
	# A : baladeuses grillagées suspendues à la voûte
	for s in [[Vector2i(1, 1), true], [Vector2i(4, 3), false], [Vector2i(3, 7), false], [Vector2i(1, 11), true], [Vector2i(4, 13), false]]:
		var t: Vector2i = s[0]
		var c := tile_center(t)
		var hang := h_top(t)
		var fixture := B.model(self, "caged_hanging_light", c + Vector3(0, hang, 0), 90.0 if _rng.randf() < 0.5 else 0.0, {"center": false, "scale": 0.7})
		fixture.name = "Lamp"
		B.set_shadows(fixture, false)
		# la lumière naît DANS le tube de la baladeuse (pas de boule lumineuse en dessous)
		var l := B.omni(self, c + Vector3(0, hang - 0.46, 0), warm, 0.42, 8.0, s[1])
		l.light_volumetric_fog_energy = 0.8
		Game.add_flare(l, 1.1, 1.0)
		_lamp_lights.append(l)
		l.set_meta("fixture", fixture)
		var glow := _own_emissive(fixture)
		if glow != null:
			l.set_meta("glow", glow)
		l.set_meta("buzz", Sound.loop_at("buzz_loop", fixture, -22.0, 1.5, 8.0))
		if s[1]:
			flicker_lights.append(l)
		if t == Vector2i(4, 3):
			_corridor_lamp = l
	# B : appliques murales au sodium (déplaçables dans l'éditeur : leur lumière les suit)
	var lamp_i := 0
	for s in [[Vector2i(8, 5), Vector2i(0, -1), true], [Vector2i(9, 3), Vector2i(0, -1), false], [Vector2i(6, 8), Vector2i(-1, 0), false], [Vector2i(12, 9), Vector2i(1, 0), false], [Vector2i(10, 12), Vector2i(0, -1), false]]:
		var t2: Vector2i = s[0]
		var d2: Vector2i = s[1]
		var n2 := Vector3(-d2.x, 0, -d2.y)
		# hublot vissé au mur, au-dessus des canalisations
		var p := wall_pos(t2, d2, 0.0) + Vector3(0, 2.15, 0)
		var lamp := B.model(self, "industrial_wall_lamp", p, yaw_facing(n2), {"center": false})
		B.set_shadows(lamp, false)
		lamp.set_meta("editobj", "lamp_b%d" % lamp_i)
		lamp_i += 1
		var l2 := B.omni(lamp, Vector3(0, 0, 0.08), Color(1.0, 0.55, 0.22), 0.7 if is_hall(t2) else 0.48, 10.0 if is_hall(t2) else 7.5, s[2] or t2 == Vector2i(9, 3))
		l2.light_volumetric_fog_energy = 0.7
		Game.add_flare(l2, 1.3, 1.0)
		_lamp_lights.append(l2)
		if s[2]:
			flicker_lights.append(l2)
			var glow2 := _own_emissive(lamp)
			if glow2 != null:
				l2.set_meta("glow", glow2)
	# C : néons de service (froids), un rouge de secours devant l'écluse
	for s in [[Vector2i(14, 8), false], [Vector2i(16, 4), false], [Vector2i(19, 6), false], [Vector2i(19, 9), true], [Vector2i(15, 12), false], [Vector2i(14, 1), true]]:
		var t3: Vector2i = s[0]
		var c3 := tile_center(t3)
		var top := h_top(t3)
		var fluo := B.model(self, "mounted_fluorescent_lights", c3 + Vector3(0, top - 0.02, 0), 90.0 if corridor_kind(t3).x > 0.5 else 0.0, {"center": false})
		fluo.name = "Fluo"
		var l3 := B.omni(self, c3 + Vector3(0, top - 0.35, 0), Color(0.82, 0.95, 1.0), 0.6, 7.0, false)
		Game.add_flare(l3, 0.9, 1.4)
		_lamp_lights.append(l3)
		l3.set_meta("fixture", fluo)
		l3.set_meta("buzz", Sound.loop_at("buzz_loop", fluo, -18.0, 2.0, 9.0))
		if s[1]:
			flicker_lights.append(l3)
	# feu de secours rouge devant l'écluse : un vrai hublot au mur, ampoule teintée
	var rp := Vector3(20 * T, 1.75, 10.6 * T)
	var red_lamp := B.model(self, "industrial_wall_lamp", rp, yaw_facing(Vector3(-1, 0, 0)), {"center": false})
	B.set_shadows(red_lamp, false)
	red_lamp.set_meta("editobj", "lamp_red")
	var red_glow := _own_emissive(red_lamp)
	if red_glow != null:
		red_glow.emission = Color(1.0, 0.08, 0.04)
		red_glow.albedo_color = Color(1.0, 0.2, 0.15)
	var red := B.omni(red_lamp, Vector3(0, 0, 0.08), Color(1.0, 0.08, 0.05), 0.55, 6.0)
	red.light_volumetric_fog_energy = 0.9
	Game.add_flare(red, 1.2, 0.9)
	_lamp_lights.append(red)


## Matériau des murs / sols / plafonds avec ce que l'humidité y dépose ; plus de mousse et de sel dans le vieux
## collecteur en briques, presque pas dans les galeries carrelées.
func _sewer_surface(slug: String, tile: float, tint: Color, rough: float, zn: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sewer_surface.gdshader")
	var base := "res://assets/textures/%s/%s_" % [slug, slug]
	m.set_shader_parameter("albedo_tex", load(base + "diff.jpg"))
	m.set_shader_parameter("normal_tex", load(base + "nor.jpg"))
	m.set_shader_parameter("rough_tex", load(base + "rough.jpg"))
	m.set_shader_parameter("moss_tex", load("res://assets/textures/concrete_moss/concrete_moss_diff.jpg"))
	m.set_shader_parameter("mud_tex", load("res://assets/textures/brown_mud_leaves_01/brown_mud_leaves_01_diff.jpg"))
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("rough_mul", rough)
	var amounts: Array = [[0.75, 0.5, 0.7, 0.6, 0.6], [0.5, 0.4, 0.6, 0.5, 0.5], [0.15, 0.15, 0.5, 0.3, 0.45]][zn]
	for i in 5:
		m.set_shader_parameter(["moss", "salt", "damp", "mud", "puddles"][i], amounts[i])
	return m


## Béton de coffrage vieilli (coulures, crasse, algues à la ligne d'eau) — shaders/wet_concrete.gdshader.
var _concrete_mats := {}


func _wet_concrete(water_y: float, algae_h: float, submerged: float) -> ShaderMaterial:
	var key := "%s|%s|%s" % [water_y, algae_h, submerged]
	if _concrete_mats.has(key):
		return _concrete_mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/wet_concrete.gdshader")
	var base := "res://assets/textures/concrete_wall_006/concrete_wall_006_"
	m.set_shader_parameter("albedo_tex", load(base + "diff.jpg"))
	m.set_shader_parameter("normal_tex", load(base + "nor.jpg"))
	m.set_shader_parameter("rough_tex", load(base + "rough.jpg"))
	m.set_shader_parameter("water_y", water_y)
	m.set_shader_parameter("algae_h", algae_h)
	m.set_shader_parameter("submerged", submerged)
	_concrete_mats[key] = m
	return m


## Matériau émissif propre à un luminaire (copie : on peut le faire grésiller sans toucher aux autres).
func _own_emissive(model: Node3D) -> StandardMaterial3D:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var m := mi.get_active_material(si) as StandardMaterial3D
			if m != null and m.emission_enabled:
				var own := m.duplicate() as StandardMaterial3D
				mi.set_surface_override_material(si, own)
				return own
	return null


func _build_signage() -> void:
	# graffitis des victimes précédentes
	# (sous les canalisations : entre la gorge du pied de mur et le tuyau, comme bombé à hauteur d'homme accroupi)
	B.decal(self, "res://assets/gen/decal_hear.png", Vector3(5 * T, 0.76, 1.5 * T), Vector3(-1, 0, 0), 1.8, 0.9, 0.3)
	B.decal(self, "res://assets/gen/decal_run.png", Vector3(2.5 * T, 0.76, 6 * T), Vector3(0, 0, -1), 1.8, 0.9, 0.3)
	B.decal(self, "res://assets/gen/decal_scratches.png", Vector3(1 * T, 0.72, 1.2 * T), Vector3(1, 0, 0), 0.75, 0.75, 0.3)
	B.decal(self, "res://assets/gen/decal_help.png", Vector3(9.5 * T, 2.3, 7 * T + 0.02), Vector3(0, 0, 1), 3.0, 0.75, 0.3)
	B.decal(self, "res://assets/gen/decal_watch.png", Vector3(13 * T, 2.12, 10.5 * T), Vector3(-1, 0, 0), 1.5, 0.75, 0.3)
	# marquages de service : chaque époque a les siens
	B.decal(self, "res://assets/gen/decal_collecteur.png", Vector3(3.5 * T, 0.82, 3 * T), Vector3(0, 0, 1), 1.4, 0.52, 0.3)
	B.decal(self, "res://assets/gen/decal_mark_c704.png", Vector3(4 * T, 1.02, 8.6 * T), Vector3(1, 0, 0), 0.9, 0.3, 0.3)
	B.decal(self, "res://assets/gen/decal_mark_c711.png", Vector3(1 * T, 1.02, 12.5 * T), Vector3(1, 0, 0), 0.9, 0.3, 0.3)
	B.decal(self, "res://assets/gen/decal_reservoir.png", Vector3(6 * T + 0.01, 2.6, 4.5 * T), Vector3(1, 0, 0), 2.0, 0.75, 0.3)
	B.decal(self, "res://assets/gen/decal_sector.png", Vector3(6 * T, 2.0, 4.5 * T - 1.2), Vector3(1, 0, 0), 1.6, 0.6, 0.3)
	B.decal(self, "res://assets/gen/decal_galerie.png", Vector3(13.5 * T, 1.82, 6 * T), Vector3(0, 0, 1), 1.5, 0.55, 0.3)
	B.decal(self, "res://assets/gen/decal_exit_up.png", Vector3(20 * T, 1.9, 11.5 * T), Vector3(-1, 0, 0), 1.8, 0.45, 0.3)
	# pochoirs de direction : local technique (nord-est) et écluse 3 (sud-est)
	B.decal(self, "res://assets/gen/decal_tech_right.png", Vector3(12 * T, 2.1, 5.5 * T), Vector3(1, 0, 0), 2.2, 0.55, 0.4)
	B.decal(self, "res://assets/gen/decal_tech_right.png", Vector3(9 * T, 2.1, 1 * T), Vector3(0, 0, 1), 2.2, 0.55, 0.4)
	B.decal(self, "res://assets/gen/decal_lock_right.png", Vector3(20 * T, 1.82, 4.5 * T), Vector3(-1, 0, 0), 1.8, 0.45, 0.3)
	B.decal(self, "res://assets/gen/decal_lock_right.png", Vector3(20 * T, 1.82, 9.5 * T), Vector3(-1, 0, 0), 1.8, 0.45, 0.3)
	# crasse, coulures, fissures
	for _i in 40:
		var t3 := Vector2i(_rng.randi_range(1, W - 2), _rng.randi_range(1, H - 2))
		if not walkable(t3):
			continue
		var walls3 := _wall_tiles(t3)
		if walls3.is_empty():
			continue
		var d3: Vector2i = walls3[_rng.randi() % walls3.size()]
		var n := Vector3(-d3.x, 0, -d3.y)
		if _rng.randf() < 0.7:
			B.decal(self, "res://assets/gen/decal_grime.png", wall_pos(t3, d3, 0.0, _rng.randf_range(-0.6, 0.6)) + Vector3(0, 1.6, 0), n, _rng.randf_range(1.0, 2.0), 2.8, 0.5)
		else:
			B.decal(self, "res://assets/gen/decal_cracks.png", wall_pos(t3, d3, 0.0, _rng.randf_range(-0.8, 0.8)) + Vector3(0, _rng.randf_range(0.8, 2.0), 0), n, 1.2, 1.2, 0.3)
	# sang
	B.decal(self, "res://assets/gen/decal_blood_smear.png", tile_center(Vector2i(14, 10)), Vector3.UP, 1.6, 2.6, 0.4)
	B.decal(self, "res://assets/gen/decal_blood_pool.png", tile_center(Vector2i(14, 11)), Vector3.UP, 1.8, 1.8, 0.4)
	B.decal(self, "res://assets/gen/decal_handprint.png", Vector3(15 * T, 1.2, 11.4 * T), Vector3(-1, 0, 0), 0.5, 0.6, 0.3)
	# caméras de surveillance (même ici...)
	room_cam = SecurityCamera.create(self, Vector3(0.25 + T, CEIL - 0.25, 0.25 + T), Vector3(1, -0.5, 1))
	gate_cam = SecurityCamera.create(self, Vector3(20 * T - 0.25, BOX_H[2] - 0.25, 11 * T + 0.3), Vector3(-1, -0.5, 1))
	room_cam.set_meta("editcam", "cam0")
	gate_cam.set_meta("editcam", "cam1")


func _build_items() -> void:
	_build_cell()
	_build_bottles()
	# lampe torche tombée juste derrière les barreaux de la cage, faisceau vers l'intérieur
	var fl_pos := Vector3((CELL.x + 1) * T + 0.42, 0.04, CELL_DOOR_Z[1] + 0.45)
	var torch := B.cylinder(self, 0.022, 0.022, 0.2, fl_pos, B.color_mat(Color(0.08, 0.08, 0.09), 0.4, 0.6), false, 10, Vector3(0, 30, 90))
	torch.name = "TorchProp"
	var torch_light := B.spot(self, fl_pos + Vector3(-0.1, 0, 0), tile_center(CELL) + Vector3(-0.6, 0.35, 0.3), Color(1, 0.95, 0.85), 3.0, 8.0, 26.0)
	torch_light.name = "TorchLight"
	torch_light.light_volumetric_fog_energy = 1.4
	var it := Interactable.create(self, fl_pos + Vector3(0, 0.1, 0), Vector3(0.5, 0.35, 0.45), "Attraper la lampe (à travers les barreaux)", func() -> void: _pick_torch(torch, torch_light))
	it.name = "TorchPickup"
	if checkpoint != "start":
		torch.queue_free()
		torch_light.queue_free()
		it.queue_free()
		_cell_solved()

	# la note d'un égoutier, par terre dans le premier collecteur, sous le graffiti
	var note_pos := wall_pos(Vector2i(4, 1), Vector2i(0, -1), 0.55, -0.2)
	var note := B.quad(self, Vector2(0.21, 0.28), note_pos + Vector3(0, 0.012, 0), B.textured("res://assets/gen/note_worker.png"), Vector3(-90, 197, 0))
	note.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.decal(self, "res://assets/gen/decal_blood_smear.png", note_pos + Vector3(0.3, 0, 0.1), Vector3.UP, 0.8, 1.2, 0.2, Color(1, 1, 1, 0.6))
	deco("metal_toolbox", note_pos + Vector3(-0.5, 0, -0.1), 70.0, {"height": 0.3})
	Interactable.create(self, note_pos + Vector3(0, 0.08, 0), Vector3(0.45, 0.2, 0.45), "Lire la note", func() -> void:
		await read_document("Note d'un égoutier",
			"[b]IL NE VOIT RIEN.[/b]\n\nIl entend TOUT.\nTa lumière, il s'en fout. Tes pas, non.\n\n" +
			"Marche pas dans l'eau.\nCours jamais.\n\nQuand il clique : à genoux, bouge plus.\nIl passera à côté.\n\nS'il te colle : fais du bruit AILLEURS.\nUne bouteille, n'importe quoi. Il ira voir.\n\n[i]— B.[/i]", "paper")
		if not _note_read:
			_note_read = true
			Game.hud.say("« B. »... Bertrand ? Le gars du registre ?", 3.0))

	# téléphone de Max
	var phone_pos := tile_center(Vector2i(1, 10)) + Vector3(0.75, 0.02, 0.3)
	B.box(self, Vector3(0.075, 0.009, 0.155), phone_pos, B.color_mat(Color(0.03, 0.03, 0.035), 0.3, 0.4), false, Vector3(0, 35, 0))
	var glow := B.quad(self, Vector2(0.065, 0.14), phone_pos + Vector3(0, 0.006, 0), B.emissive(Color(0.55, 0.65, 0.9), 1.6, true), Vector3(-90, 35, 0))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.omni(self, phone_pos + Vector3(0, 0.15, 0), Color(0.5, 0.6, 1.0), 0.08, 1.2)
	B.decal(self, "res://assets/gen/decal_blood_smear.png", phone_pos, Vector3.UP, 1.2, 1.6, 0.3, Color(1, 1, 1, 0.8))
	Interactable.create(self, phone_pos + Vector3(0, 0.08, 0), Vector3(0.4, 0.25, 0.4), "Ramasser le téléphone", func() -> void: _read_max_phone())

	# casquette de Karim + traces
	var cap_pos := tile_center(Vector2i(14, 11)) + Vector3(0.55, 0.0, -0.6)
	var cap := B.model(self, "sf:worn_cap", cap_pos, 140.0, {"depth": 0.27})
	cap.rotation_degrees.x = -8.0

	# les corps : Karim au fond de l'impasse, Inès au bord de la citerne (Max reste introuvable)
	_body("karim", tile_center(Vector2i(14, 11)) + Vector3(-0.2, 0.0, 0.25), 2.4,
		["Karim...", "Non... non, non, non. KARIM !", "...Il a essayé d'atteindre l'écluse. Comme moi."])
	_body("ines", wall_pos(Vector2i(6, 8), Vector2i(-1, 0), 0.75), PI * 0.5,
		["Inès ?!", "...Elle est froide.", "C'est son nid. Il les ramène ici."])

	# local technique : établi, étagères, coupe-boulons, journal d'entretien
	var tc := tile_center(Vector2i(17, 1))
	var bench_mat := B.mat("rusty_metal_02", 1.0, {"metallic": 0.5, "roughness": 0.8, "color": Color(0.5, 0.5, 0.5)})
	B.box(self, Vector3(2.2, 0.06, 0.7), tc + Vector3(0, 0.92, -T * 0.5 + 0.4), bench_mat, true)
	for sx in [-1.0, 1.0]:
		B.box(self, Vector3(0.06, 0.92, 0.6), tc + Vector3(sx * 1.0, 0.46, -T * 0.5 + 0.4), bench_mat, false)
	deco("metal_tool_chest", tc + Vector3(-0.7, 0.95, -T * 0.5 + 0.35), 0.0)
	deco("steel_frame_shelves_01", tile_center(Vector2i(16, 2)) + Vector3(0, 0, T * 0.5 - 0.35), 180.0, {"height": 2.0, "collide": true})
	deco("power_box_01", Vector3(18.5 * T, 1.6, T + 0.06), 0.0, {"center": false, "scale": 1.0})
	deco("cardboard_box_01", tile_center(Vector2i(18, 2)) + Vector3(0.5, 0, 0.6), 20.0)
	deco("Barrel_01", tile_center(Vector2i(18, 2)) + Vector3(-0.4, 0, 0.8), 0.0, {"collide": true})
	var fluo := B.model(self, "mounted_fluorescent_lights", tile_center(Vector2i(17, 2)) + Vector3(0, CEIL - 0.02, -0.6), 0.0, {"center": false})
	fluo.name = "Fluo"
	var fl := B.omni(self, tile_center(Vector2i(17, 2)) + Vector3(0, CEIL - 0.4, -0.6), Color(0.85, 0.95, 1.0), 1.6, 9.0, true)
	flicker_lights.append(fl)
	Sound.loop_at("buzz_loop", fluo, -16.0, 2.0, 10.0)

	if checkpoint in ["start", "cell", "bench"]:
		var cutters := B.model(self, "bolt_cutters_01", tc + Vector3(0.35, 0.97, -T * 0.5 + 0.45), 0.0, {"rot": Vector3(90, 0, 70)})
		cutters.name = "Cutters"
		var bucket := B.model(self, "can_rusted", tc + Vector3(0.75, 0.95, -T * 0.5 + 0.55), 0.0, {"scale": 1.6})
		bucket.name = "Bucket"
		Interactable.create(self, tc + Vector3(0.35, 1.05, -T * 0.5 + 0.45), Vector3(0.7, 0.3, 0.5), "Prendre le coupe-boulons", func() -> void: _take_cutters(cutters, bucket)).name = "CuttersUse"
	var log_pos := tc + Vector3(-0.15, 0.955, -T * 0.5 + 0.55)
	B.quad(self, Vector2(0.21, 0.29), log_pos, B.textured("res://assets/gen/paper.png"), Vector3(-90, 8, 0))
	Interactable.create(self, log_pos + Vector3(0, 0.05, 0), Vector3(0.35, 0.15, 0.4), "Lire", func() -> void:
		await read_document("Registre d'intervention",
			"[b]REGISTRE D'INTERVENTION — SECTEUR C-7[/b]\n\n" +
			"03/11 — Grille écluse 3 condamnée (chaîne + cadenas) sur ordre de la direction. Personne ne descend sans autorisation.\n\n" +
			"06/11 — Encore des bruits dans le collecteur principal. On dirait des clics. Bertrand dit que c'est la dilatation des canalisations.\n\n" +
			"09/11 — Bertrand n'est pas remonté.\n\n" +
			"10/11 — Les « messieurs de la direction » ont installé des caméras partout. Ils disent que c'est pour notre sécurité.\n\n" +
			"11/11 — Ils ont retiré les trois fusibles de l'armoire de l'écluse 3 et les ont balancés dans le réseau. « Comme ça, personne ne sort. » Sortir d'où ?", "typed"))


# ================================================================== la cellule (début)
## Théo se réveille enfermé dans une cage rouillée, dans un coin de la salle de départ.
## Pour sortir : attraper la lampe à travers les barreaux, arracher un barreau descellé,
## s'en servir pour faire tomber les clés posées sur une caisse, ouvrir le cadenas.
const CELL := Vector2i(1, 2)
## Les barreaux arrêtent le corps de Théo mais pas son regard : on vise ce qui est derrière.
const BARS_LAYER := 1 << 5
const CELL_DOOR_Z := [6.55, 7.45]  ## porte dans la grille côté est (entre ces z)
var cell_door: Node3D
var cell_door_body: StaticBody3D
var cell_open := false
var has_bar := false
var has_keys := false
var _cell_keys: Node3D
var _keys_down := false
var _loose_bar: Node3D


func _build_cell() -> void:
	var x_w := CELL.x * T
	var x_e := (CELL.x + 1) * T
	var z_n := CELL.y * T
	var z_s := (CELL.y + 1) * T
	var top := h_top(CELL)
	var iron := B.mat("rusty_metal_02", 0.5, {"metallic": 0.65, "roughness": 0.65, "color": Color(0.55, 0.5, 0.45)})
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	var box := BoxMesh.new()
	var loose_x := x_w + 1.65
	# grille nord (vers le reste de la salle) : barreaux tous les 13 cm, traverses plates
	var nx := int((x_e - x_w) / 0.13)
	for i in range(1, nx):
		var x := x_w + i * (x_e - x_w) / nx
		if absf(x - loose_x) < 0.06:
			continue
		_pipe_seg(st, cyl, Vector3(x, 0, z_n), Vector3(x, top, z_n), 0.016)
	for y in [0.08, 1.15, 2.2, top - 0.06]:
		st.append_from(box, 0, Transform3D(Basis.from_scale(Vector3(x_e - x_w, 0.05, 0.025)), Vector3((x_w + x_e) * 0.5, y, z_n)))
	# grille est : la porte au milieu
	var nz := int((z_s - z_n) / 0.13)
	for i in range(1, nz):
		var z := z_n + i * (z_s - z_n) / nz
		if z > CELL_DOOR_Z[0] - 0.04 and z < CELL_DOOR_Z[1] + 0.04:
			continue
		_pipe_seg(st, cyl, Vector3(x_e, 0, z), Vector3(x_e, top, z), 0.016)
	for y in [0.08, 1.15, 2.2]:
		for span in [[z_n, CELL_DOOR_Z[0] - 0.03], [CELL_DOOR_Z[1] + 0.03, z_s]]:
			var za: float = span[0]
			var zb: float = span[1]
			st.append_from(box, 0, Transform3D(Basis.from_scale(Vector3(0.025, 0.05, zb - za)), Vector3(x_e, y, (za + zb) * 0.5)))
	st.append_from(box, 0, Transform3D(Basis.from_scale(Vector3(0.025, 0.05, z_s - z_n)), Vector3(x_e, top - 0.06, (z_n + z_s) * 0.5)))
	# montants de la porte
	for z in CELL_DOOR_Z:
		st.append_from(box, 0, Transform3D(Basis.from_scale(Vector3(0.05, top, 0.05)), Vector3(x_e, top * 0.5, z)))
	st.generate_normals()
	var bars := MeshInstance3D.new()
	bars.name = "CellBars"
	bars.mesh = st.commit()
	bars.material_override = iron
	add_child(bars)
	# collisions de la grille (la porte a la sienne)
	var body := StaticBody3D.new()
	body.collision_layer = BARS_LAYER
	add_child(body)
	for spec in [[Vector3((x_w + x_e) * 0.5, top * 0.5, z_n), Vector3(x_e - x_w, top, 0.08)],
			[Vector3(x_e, top * 0.5, (z_n + CELL_DOOR_Z[0]) * 0.5), Vector3(0.08, top, CELL_DOOR_Z[0] - z_n)],
			[Vector3(x_e, top * 0.5, (CELL_DOOR_Z[1] + z_s) * 0.5), Vector3(0.08, top, z_s - CELL_DOOR_Z[1])]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec[1]
		cs.shape = bs
		cs.position = spec[0]
		body.add_child(cs)
	# le barreau descellé (rouillé à la base, un peu de travers)
	_loose_bar = Node3D.new()
	add_child(_loose_bar)
	_loose_bar.position = Vector3(loose_x, 0, z_n)
	_loose_bar.rotation_degrees.z = 2.5
	var lb := B.cylinder(_loose_bar, 0.016, 0.016, top, Vector3(0, top * 0.5, 0), iron, false, 8)
	lb.name = "LooseBar"
	B.decal(self, "res://assets/gen/decal_grime.png", Vector3(loose_x, 0.05, z_n), Vector3.UP, 0.4, 0.4, 0.2, Color(0.5, 0.3, 0.2, 0.8))
	Interactable.create(self, Vector3(loose_x, 0.9, z_n + 0.12), Vector3(0.35, 1.6, 0.3), "Secouer le barreau rouillé (maintenir)", _pull_bar, 2.4).name = "LooseBarUse"
	# porte : pivote sur son gond nord, s'ouvre vers l'extérieur
	cell_door = Node3D.new()
	cell_door.name = "CellDoor"
	add_child(cell_door)
	cell_door.position = Vector3(x_e, 0, CELL_DOOR_Z[0])
	var dw: float = CELL_DOOR_Z[1] - CELL_DOOR_Z[0]
	var dst := SurfaceTool.new()
	dst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 6:
		var z := 0.08 + k * (dw - 0.16) / 5.0
		_pipe_seg(dst, cyl, Vector3(0, 0.05, z), Vector3(0, 2.15, z), 0.016)
	for y in [0.06, 1.15, 2.17]:
		dst.append_from(box, 0, Transform3D(Basis.from_scale(Vector3(0.03, 0.05, dw - 0.04)), Vector3(0, y, dw * 0.5)))
	dst.generate_normals()
	var door_mi := MeshInstance3D.new()
	door_mi.mesh = dst.commit()
	door_mi.material_override = iron
	cell_door.add_child(door_mi)
	# cadenas sur la chaîne, côté extérieur
	B.box(cell_door, Vector3(0.05, 0.07, 0.035), Vector3(0.05, 1.05, dw - 0.06), B.color_mat(Color(0.5, 0.42, 0.18), 0.35, 0.85), false)
	cell_door_body = StaticBody3D.new()
	cell_door_body.collision_layer = BARS_LAYER
	cell_door.add_child(cell_door_body)
	var dcs := CollisionShape3D.new()
	var dbs := BoxShape3D.new()
	dbs.size = Vector3(0.08, 2.3, dw)
	dcs.shape = dbs
	dcs.position = Vector3(0, 1.15, dw * 0.5)
	cell_door_body.add_child(dcs)
	# zone limitée au cadenas : elle ne doit pas masquer ce qu'on vise à travers la grille
	Interactable.create(self, Vector3(x_e - 0.08, 1.05, CELL_DOOR_Z[1] - 0.12), Vector3(0.3, 0.6, 0.4), "Examiner le cadenas", _try_cell_door).name = "CellDoorUse"
	# intérieur : vieux sommier, matelas taché, seau, traces des « sujets » précédents
	var bed := B.model(self, "old_bed_frame", Vector3(x_w + 0.52, 0, (z_n + z_s) * 0.5 + 0.1), 0.0, {"collide": true})
	if bed != null:
		bed.name = "CellBed"
	var mattress := B.box(self, Vector3(0.84, 0.12, 1.9), Vector3(x_w + 0.52, 0.61, (z_n + z_s) * 0.5 + 0.1), B.mat("fabric_pattern_07", 1.0, {"color": Color(0.26, 0.23, 0.17), "roughness": 1.0}), false)
	mattress.rotation_degrees.y = 3.0
	B.decal(self, "res://assets/gen/decal_blood_smear.png", Vector3(x_w + 0.52, 0.68, (z_n + z_s) * 0.5 + 0.4), Vector3.UP, 0.6, 0.7, 0.2, Color(0.6, 0.5, 0.45, 0.6))
	B.model(self, "can_rusted", Vector3(x_e - 0.45, 0, z_s - 0.4), 30.0, {"scale": 1.7})
	B.decal(self, "res://assets/gen/decal_scratches.png", Vector3(x_w + 0.01, 0.95, z_n + 1.6), Vector3(1, 0, 0), 0.6, 0.6, 0.12)
	B.decal(self, "res://assets/gen/decal_watch.png", Vector3(x_e - 0.75, 0.72, z_s - 0.01), Vector3(0, 0, -1), 1.1, 0.55, 0.12, Color(1, 1, 1, 0.8))
	# dehors : une caisse avec le trousseau, hors de portée du bras
	var crate_pos := Vector3(x_e + 1.2, 0, CELL_DOOR_Z[0] - 0.45)
	var crate := B.model(self, "wooden_crate_01", crate_pos, 12.0, {"collide": true})
	var crate_top := B.local_aabb(crate).size.y if crate != null else 0.5
	_cell_keys = _key_ring()
	_cell_keys.position = crate_pos + Vector3(-0.12, crate_top + 0.005, 0.05)
	Interactable.create(self, _cell_keys.position + Vector3(0, 0.08, 0), Vector3(0.4, 0.3, 0.4), "Les clés...", _reach_keys).name = "KeysUse"


## Trousseau : anneau + deux clés.
func _key_ring() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var steel := B.color_mat(Color(0.55, 0.52, 0.45), 0.35, 0.9)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.022
	tm.outer_radius = 0.027
	ring.mesh = tm
	ring.material_override = steel
	n.add_child(ring)
	for k in 2:
		var key := Node3D.new()
		n.add_child(key)
		key.position = Vector3(0.03 + k * 0.008, 0.002, -0.01 + k * 0.025)
		key.rotation_degrees.y = -20.0 + k * 35.0
		B.box(key, Vector3(0.055, 0.004, 0.012), Vector3(0.03, 0, 0), steel, false)
		B.cylinder(key, 0.011, 0.011, 0.004, Vector3(0, 0, 0), steel, false, 10)
	return n


func _pull_bar() -> void:
	if has_bar:
		return
	has_bar = true
	var use := find_child("LooseBarUse", false, false)
	if use != null:
		use.queue_free()
	Sound.play_at("metal_clang", _loose_bar.global_position + Vector3(0, 1.0, 0), -6.0, 1.4, 4.0, 30.0)
	Game.shake(0.4)
	var tw := create_tween()
	tw.tween_property(_loose_bar, "rotation_degrees:z", 25.0, 0.25)
	tw.tween_property(_loose_bar, "position:y", 0.3, 0.2)
	await tw.finished
	_loose_bar.visible = false
	Sound.play("pickup", -6.0)
	Game.hud.pickup("Barre de fer")
	await wait(0.4)
	Game.hud.say("Il a cédé... Un mètre et demi de ferraille. Ça peut servir.", 3.2)


func _reach_keys() -> void:
	if _keys_down:
		# les clés sont tombées juste devant les barreaux : on les ramasse en passant le bras
		has_keys = true
		_cell_keys.queue_free()
		var use := find_child("KeysUse", false, false)
		if use != null:
			use.queue_free()
		Sound.play("pickup", -6.0)
		Game.hud.pickup("Trousseau de clés")
		Game.hud.say("Je les ai.", 1.8)
		return
	if not has_bar:
		Game.hud.say("Les clés... sur la caisse. Trop loin, même en tendant le bras.", 3.2)
		return
	# le barreau passe entre les barreaux, accroche l'anneau et fait glisser le trousseau
	var use2 := find_child("KeysUse", false, false) as Interactable
	use2.disable()
	var rod := B.cylinder(self, 0.016, 0.016, 1.5, Vector3.ZERO, B.mat("rusty_metal_02", 0.5, {"metallic": 0.65, "roughness": 0.65}), false, 8)
	var from := player.head.global_position + Vector3(0, -0.35, 0)
	var tip := _cell_keys.global_position + Vector3(0, 0.03, 0)
	var dir := (tip - from).normalized()
	rod.global_transform = Transform3D(_axis_basis(dir), from + dir * 0.4)
	var tw := create_tween()
	tw.tween_property(rod, "global_position", tip - dir * 0.75, 0.7).set_trans(Tween.TRANS_SINE)
	await tw.finished
	Sound.play_at("metal_clang", tip, -18.0, 2.2, 2.0, 10.0)
	var drop := Vector3((CELL.x + 1) * T + 0.22, 0.012, tip.z + 0.25)
	var tw2 := create_tween()
	tw2.tween_property(rod, "global_position", rod.global_position - dir * 0.5, 0.5)
	tw2.parallel().tween_property(_cell_keys, "global_position", Vector3((tip.x + drop.x) * 0.5, tip.y, (tip.z + drop.z) * 0.5), 0.45)
	tw2.tween_property(_cell_keys, "global_position", drop, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw2.finished
	Sound.play_at("pickup", drop, -4.0, 1.6, 2.0, 12.0)
	rod.queue_free()
	_keys_down = true
	use2.position = drop + Vector3(0, 0.1, 0)
	(use2.get_child(0) as CollisionShape3D).shape.size = Vector3(0.45, 0.3, 0.45)
	use2.prompt = "Ramasser les clés (à travers les barreaux)"
	use2.enabled = true
	use2.collision_layer = 4
	Game.hud.say("Allez... allez... Voilà !", 2.2)


func _try_cell_door() -> void:
	if cell_open:
		return
	if not has_keys:
		Sound.play_at("door_locked", cell_door.global_position + Vector3(0, 1.0, 0.4), -4.0, 1.3)
		Game.hud.say("Cadenassée. Une vraie cage... Qui fait ça ?!", 3.0)
		return
	cell_open = true
	var use := find_child("CellDoorUse", false, false)
	if use != null:
		use.queue_free()
	Sound.play_at("pickup", cell_door.global_position + Vector3(0, 1.0, 0.8), -2.0, 0.7)
	await wait(0.6)
	_open_cell_door(false)
	params = {"checkpoint": "cell"}
	Game.level_params = params
	await wait(1.0)
	Game.hud.say("Dehors. Bon. Et maintenant... par où ?", 3.0)
	Game.hud.objective("Trouver une sortie")


func _open_cell_door(instant: bool) -> void:
	cell_open = true
	cell_door_body.collision_layer = 0
	if instant:
		cell_door.rotation_degrees.y = 105.0
		return
	Sound.play_at("door_creak", cell_door.global_position + Vector3(0, 1.0, 0.4), 0.0, 0.8)
	var tw := create_tween()
	tw.tween_property(cell_door, "rotation_degrees:y", 105.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Test --tour[=début,fin] : visite automatique de points de vue répartis sur toute la carte
## (un toutes les 1,5 s, à partir de 1 s) ; les captures se règlent avec --shots.
## Chaque point : depuis le centre d'une case, vers un passage ouvert ou un angle.
func _tour() -> void:
	var views := []
	for z in H:
		for x in W:
			var t := Vector2i(x, z)
			if not walkable(t) or t == EXIT:
				continue
			var kind := corridor_kind(t)
			# salles et croisements : vers chaque passage ; couloirs : un sur trois, dans l'axe
			if kind == Vector3.ZERO:
				for d: Vector2i in DIRS:
					if walkable(t + d):
						views.append([t, Vector3(d.x, 0, d.y)])
			elif (x + z) % 3 == 0:
				views.append([t, kind])
	var r := str(Game.args.get("tour", "")).split(",")
	var first := int(r[0]) if r.size() > 1 else 0
	var last := int(r[1]) if r.size() > 1 else views.size() - 1
	print("TOUR %d points de vue" % views.size())
	await wait(1.0)
	for i in range(first, mini(last + 1, views.size())):
		var v: Array = views[i]
		var dir: Vector3 = v[1]
		var pos := tile_center(v[0]) - dir * 1.1
		player.global_position = Vector3(pos.x, floor_y(pos) + 0.02, pos.z)
		player.set_look(atan2(-dir.x, -dir.z), deg_to_rad(8.0))
		print("TOUR #%d case=%s dir=%s" % [i, v[0], dir])
		await wait(1.5)


## Test --spots : points de vue choisis (portes, luminaires, inscriptions, jonctions voûte / salle).
const SPOTS := [
	# portes de service
	[Vector3(46.2, 0, 17.6), 180.0, -8.0], [Vector3(41.5, 0, 26.6), 90.0, -8.0], [Vector3(48.4, 0, 28.6), 200.0, -8.0],
	# appliques murales (zone B) et feu rouge de l'écluse
	[Vector3(23.8, 0, 16.6), 0.0, 18.0], [Vector3(26.6, 0, 11.0), 0.0, 18.0], [Vector3(20.0, 0, 23.8), 90.0, 18.0],
	[Vector3(33.0, 0, 26.6), -90.0, 18.0], [Vector3(29.4, 0, 35.6), 0.0, 18.0], [Vector3(53.8, 0, 29.6), -90.0, 12.0],
	# baladeuses (zone A)
	[Vector3(4.2, 0, 6.0), 0.0, 25.0], [Vector3(12.6, 0, 11.4), 0.0, 25.0], [Vector3(9.8, 0, 22.0), 0.0, 25.0],
	[Vector3(4.2, 0, 32.4), 0.0, 25.0], [Vector3(12.6, 0, 38.0), 0.0, 25.0],
	# inscriptions
	[Vector3(12.0, 0, 4.2), -90.0, -12.0], [Vector3(7.0, 0, 14.2), 180.0, -12.0], [Vector3(9.8, 0, 10.8), 0.0, -12.0],
	[Vector3(34.4, 0, 29.4), -90.0, 5.0], [Vector3(54.4, 0, 12.6), -90.0, 0.0], [Vector3(4.6, 0, 3.4), 90.0, -10.0],
	# jonctions voûtes / salles de briques
	[Vector3(9.8, 0, 3.0), 90.0, 15.0], [Vector3(12.6, 0, 12.2), 180.0, 15.0], [Vector3(7.0, 0, 9.6), 90.0, 15.0],
	[Vector3(9.8, 0, 22.4), -90.0, 15.0],
]


func _spots() -> void:
	await wait(1.0)
	for i in SPOTS.size():
		var sp: Array = SPOTS[i]
		var pos: Vector3 = sp[0]
		player.global_position = Vector3(pos.x, floor_y(pos) + 0.02, pos.z)
		player.set_look(deg_to_rad(float(sp[1])), deg_to_rad(float(sp[2])))
		if Game.args.has("nolamp"):
			player.set_flashlight(false, true)
		print("SPOT #%d %s" % [i, pos])
		await wait(1.5)


## Test --mictest (avec --torch) : niveaux de micro simulés (silence, voix, cri), créature à 12 m.
func _mictest() -> void:
	await wait(1.0)
	creature.player = player
	creature.global_position = player.global_position + Vector3(0, 0, -12.0)
	creature.activate(Creature.State.PATROL)
	creature.path.clear()
	creature.target_speed = 0.0
	for step in [["silence", -70.0, 3.0], ["voix", -34.0, 2.0], ["silence", -70.0, 3.0], ["cri", -12.0, 1.5]]:
		Sound.debug_mic_db = step[1]
		await wait(step[2])
		print("MICTEST %s : voix=%.2f fond=%.0f dB · créature=%s distance=%.1f" % [step[0], Sound.mic_voice, Sound.mic_floor, Creature.State.keys()[creature.state], creature.global_position.distance_to(player.global_position)])


## Test --cuttertest (avec --checkpoint=bench) : prend le coupe-boulons, réessaie (ne doit pas planter),
## puis suit la poursuite.
func _cuttertest() -> void:
	await wait(1.5)
	var use := find_child("CuttersUse", false, false) as Interactable
	print("CUTTERTEST zone présente : ", use != null, " checkpoint=", checkpoint)
	use.trigger()
	await wait(0.2)
	var again := find_child("CuttersUse", false, false) as Interactable
	print("CUTTERTEST zone après prise : ", again != null and not again.is_queued_for_deletion(), " · reprise enregistrée : ", Game.level_params.get("checkpoint", "?"))
	_take_cutters(null, null)  # double appel : doit être ignoré sans planter
	for i in 10:
		await wait(0.8)
		print("CUTTERTEST t=%.1f créature=%s vitesse=%.1f distance=%.1f cœur=%.2f" % [0.8 * (i + 1), Creature.State.keys()[creature.state], creature.speed, creature.global_position.distance_to(player.global_position), player.danger])


## Test --invtest (avec --torch) : quelques objets en poche, l'inventaire s'ouvre (capture --shots=3).
func _invtest() -> void:
	await wait(1.5)
	bottles = 3
	fuses_found = ["bertrand", "karim"]
	fuses_in = 1
	has_cutters = true
	documents.append({"title": "Note d'un égoutier", "text": "...", "style": "paper"})
	documents.append({"title": "Le téléphone de Max", "text": "...", "style": "phone"})
	Game.hud.pickup("Coupe-boulons")
	await wait(0.5)
	Game.inventory.open()


## Test --lookcam[=0|1] : Théo regarde une caméra de surveillance de près (support, rotule).
func _lookcam() -> void:
	await wait(0.6)
	var c: SecurityCamera = gate_cam if str(Game.args.get("lookcam", "1")) != "0" else room_cam
	var out := c.mount_out if c.mount_out.length() > 0.1 else -c.rest_dir
	var side := Vector3(-out.z, 0, out.x)
	var pos := c.global_position + Vector3(out.x, 0, out.z) * 1.3 + side * float(Game.args.get("lookside", 0.7))
	player.global_position = Vector3(pos.x, floor_y(pos), pos.z)
	await wait(0.2)  # la tête suit le corps à l'image suivante
	var to := c.global_position - player.head.global_position
	player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	print("LOOKCAM caméra=%s support=%s" % [c.global_position, c.mount_out])


## Test --pantest (avec --torch) : la créature rôde à 8 m, Théo est à bout de souffle.
func _pantest() -> void:
	await wait(1.0)
	creature.player = player
	creature.global_position = player.global_position + Vector3(0, 0, -8.0)
	creature.activate(Creature.State.PATROL)
	await wait(0.5)
	player.exhausted = true
	player.stamina = 0.0
	for i in 8:
		await wait(0.5)
		player.exhausted = true
		print("PANTEST t=%.1f état=%s vitesse=%.2f distance=%.1f" % [0.5 * (i + 1), Creature.State.keys()[creature.state], creature.speed, creature.global_position.distance_to(player.global_position)])


## Test --bottletest (avec --creature --chase) : en pleine poursuite, Théo lance une bouteille
## dans un couloir latéral ; la créature doit lâcher la poursuite et filer vers le bruit.
func _bottletest() -> void:
	await wait(2.0)
	bottles = 1
	player.set_look(deg_to_rad(float(Game.args.get("throwyaw", 90.0))), 0.15)
	await wait(0.2)
	_throw_bottle()
	for i in 10:
		await wait(0.5)
		print("BOTTLETEST t=%.1f état=%s créature=%s joueur=%.1f m" % [0.5 * (i + 1), Creature.State.keys()[creature.state], creature.global_position, creature.global_position.distance_to(player.global_position)])


## Test --fusetest (avec --torch) : ramasse les trois fusibles, les pose, remet le courant,
## coupe la chaîne. Captures : --shots=2.5,6,9.5,13,16,19.5
func _fusetest() -> void:
	await wait(0.5)
	var look := func(target: Vector3) -> void:
		var to := target - player.head.global_position
		player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	for id in ["bertrand", "citerne", "karim"]:
		var spec: Array = FUSES[id]
		var target: Vector3 = tile_center(spec[0]) + spec[1]
		if id == "citerne":
			target = Vector3(10.5 * T - 0.36, 0.1, 9.15 * T + 0.05)
		player.global_position = Vector3(target.x - 1.1, floor_y(target), target.z + 0.6)
		await wait(0.3)
		look.call(target)
		await wait(2.2)
		var best: Interactable = null
		for n in get_children():
			if n is Interactable and (n as Interactable).prompt == "Ramasser le fusible" and (n as Node3D).global_position.distance_to(target) < 0.6:
				best = n
		print("FUSETEST ", id, " -> ", best != null)
		if best != null:
			best.trigger()
		await wait(1.0)
	player.global_position = PANEL_POS + Vector3(-1.2, 0, 0.2)
	await wait(0.3)
	look.call(PANEL_POS + Vector3(0, 1.3, 0))
	await wait(1.5)
	_use_panel()
	await wait(2.0)
	if Game.args.has("panelview"):
		# vue rapprochée du boîtier, les trois fusibles vissés
		player.global_position = PANEL_POS + Vector3(-0.85, 0, 0.0)
		look.call(PANEL_POS + Vector3(0, 1.35, -0.05))
		await wait(3.0)
	print("FUSETEST posés=%d prompt=%s" % [fuses_in, _panel_use.prompt])
	_panel_use.trigger()
	await wait(2.5)
	print("FUSETEST courant=%s" % power_on)
	has_cutters = true
	player.global_position = tile_center(Vector2i(19, 11))
	look.call(tile_center(GATE) + Vector3(0, 1.1, 0))
	_on_gate()
	await wait(1.0)
	_cut_chain()
	await wait(3.0)
	print("FUSETEST grille ouverte=%s" % gate_opened)


## Test --celltest : résout la cellule étape par étape (captures avec --shots=2,3.5,4.8,6.6,8.9,10.4,14.5).
func _celltest() -> void:
	Game.ui.fade_rect.color.a = 0.0
	_setup_triggers()
	var look := func(target: Vector3) -> void:
		var to := target - player.head.global_position
		player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	var use := func(nm: String) -> void:
		var it := find_child(nm, false, false) as Interactable
		# comme le joueur : il faut que le rayon de visée tombe sur la zone (pas sur les barreaux)
		await get_tree().physics_frame
		player.ray.force_raycast_update()
		var aimed := player.ray.get_collider() == it
		print("CELLTEST ", nm, " -> ", it.prompt if it != null else "(absent)", "  visée=", aimed, "  (touché : ", player.ray.get_collider(), ")")
		if it != null and aimed:
			it.trigger()
	look.call((find_child("TorchProp", false, false) as Node3D).global_position)
	await wait(2.5)
	await use.call("TorchPickup")
	await wait(1.5)
	look.call(Vector3((CELL.x + 1) * T, 1.05, CELL_DOOR_Z[1] - 0.12))
	await use.call("CellDoorUse")
	await wait(1.5)
	look.call(_loose_bar.global_position + Vector3(0, 0.9, 0))
	await use.call("LooseBarUse")
	await wait(2.0)
	# Théo s'approche de la grille pour viser les clés
	player.global_position = Vector3((CELL.x + 1) * T - 0.4, 0, CELL_DOOR_Z[0] + 0.1)
	await wait(0.3)
	look.call(_cell_keys.global_position)
	await use.call("KeysUse")
	await wait(2.6)
	look.call(_cell_keys.global_position)
	await wait(0.8)
	await use.call("KeysUse")
	await wait(1.0)
	look.call(Vector3((CELL.x + 1) * T, 1.05, CELL_DOOR_Z[1] - 0.12))
	await use.call("CellDoorUse")
	await wait(3.0)
	print("CELLTEST ouverte=%s barreau=%s clés=%s lampe=%s" % [cell_open, has_bar, has_keys, player.has_flashlight])


## Cellule déjà ouverte (tests --torch, reprise au point de contrôle).
func _cell_solved() -> void:
	_open_cell_door(true)
	has_keys = true
	for nm in ["CellDoorUse", "KeysUse", "LooseBarUse"]:
		var n := find_child(nm, false, false)
		if n != null:
			n.queue_free()
	if is_instance_valid(_cell_keys):
		_cell_keys.queue_free()


# ================================================================== bouteilles (diversion)
## Bouteilles vides ramassées dans les égouts : on les lance (G ou clic droit), elles éclatent
## plus loin et la créature fonce vers le bruit. De quoi la détourner... ou la semer.
const BOTTLE_SPOTS := [
	[Vector2i(4, 1), Vector2(0.7, 0.9)], [Vector2i(1, 9), Vector2(-0.8, 0.5)], [Vector2i(4, 12), Vector2(0.6, -0.8)],
	[Vector2i(6, 3), Vector2(-0.7, 0.4)], [Vector2i(12, 7), Vector2(0.75, 0.6)], [Vector2i(10, 12), Vector2(-0.6, 0.8)],
	[Vector2i(15, 5), Vector2(0.8, -0.6)], [Vector2i(18, 8), Vector2(-0.75, 0.7)],
]
var bottles := 0
var _bottle_told := false


func _build_bottles() -> void:
	for spec in BOTTLE_SPOTS:
		var off: Vector2 = spec[1]
		var pos: Vector3 = tile_center(spec[0]) + Vector3(off.x, 0.0, off.y)
		var b := B.model(self, "sf:beer_bottle", pos + Vector3(0, 0.035, 0), randf_range(0, 360), {"width": 0.24, "rot": Vector3(0, 0, 90)})
		var it := Interactable.create(self, pos + Vector3(0, 0.1, 0), Vector3(0.45, 0.3, 0.45), "Ramasser la bouteille", Callable())
		it.on_use = func() -> void:
			b.queue_free()
			it.queue_free()
			bottles += 1
			Sound.play("pickup", -10.0, 1.3)
			Game.hud.pickup("Bouteille vide")
			if bottles == 1:
				Game.hud.hint("[G] ou [clic droit]  lancer une bouteille pour faire diversion", 5.0)
			if not _bottle_told:
				_bottle_told = true
				await wait(0.6)
				Game.hud.say("Une bouteille vide... Si je la lance assez loin, il ira voir là-bas.", 3.4)


func _throw_bottle() -> void:
	bottles -= 1
	var rb := RigidBody3D.new()
	rb.mass = 0.4
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.contact_monitor = true
	rb.max_contacts_reported = 2
	rb.continuous_cd = true
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.035
	cap.height = 0.24
	cs.shape = cap
	rb.add_child(cs)
	var m := B.model(rb, "sf:beer_bottle", Vector3(0, -0.12, 0), 0.0, {"height": 0.24})
	m.rotation_degrees.y = randf_range(0, 360)
	add_child(rb)
	var cam := player.cam
	var fwd := -cam.global_basis.z
	rb.global_position = cam.global_position + fwd * 0.4 + cam.global_basis.x * 0.12 - Vector3(0, 0.12, 0)
	rb.linear_velocity = fwd * 11.0 + Vector3(0, 2.4, 0) + Vector3(player.velocity.x, 0, player.velocity.z)
	rb.angular_velocity = Vector3(randf_range(-14, 14), randf_range(-4, 4), randf_range(-14, 14))
	player.emit_noise(1.2)
	rb.body_entered.connect(func(_b: Node) -> void: _shatter(rb))
	await wait(4.0)
	if is_instance_valid(rb):
		_shatter(rb)


func _shatter(target: Variant) -> void:
	if not is_instance_valid(target):
		return
	var rb := target as RigidBody3D
	if rb.has_meta("broken"):
		return
	rb.set_meta("broken", true)
	var pos := rb.global_position
	var wet := get_surface(pos) == "water"
	if wet:
		Sound.play_at(Sound.variant("step_water", 4), pos, 2.0, 0.7, 5.0, 40.0)
		splash(pos, 2.0)
		lure_noise(pos, 12.0)
	else:
		Sound.play_at("glass_break", pos, 4.0, randf_range(0.92, 1.08), 6.0, 70.0)
		lure_noise(pos, 22.0)
		# éclats de verre au sol (ils craqueront sous les pieds)
		_glass_patch(Vector3(pos.x, 0, pos.z), 0.35, 50)
	rb.queue_free()


# ================================================================== fusibles de l'écluse
## La grille de l'écluse 3 est motorisée : « la direction » a retiré les trois fusibles de son
## armoire et les a jetés dans le réseau. Un par époque de construction — et chacun raconte
## quelque chose (Bertrand, la citerne, Karim).
const FUSES := {
	"bertrand": [Vector2i(5, 13), Vector3(0.55, 0.0, -0.45), "Le casque de Bertrand... et un fusible. Il essayait de remettre le courant, lui aussi."],
	"citerne": [Vector2i(10, 9), Vector3.ZERO, "Un fusible... posé sur le socle du pilier, au milieu de l'eau. Ils les ont vraiment jetés n'importe où."],
	"karim": [Vector2i(14, 11), Vector3(0.35, 0.0, 0.55), "Karim l'avait dans la main... Il savait. Il allait à l'écluse."],
}
const PANEL_POS := Vector3(20 * T - 0.16, 0.0, 11.35 * T)
const PANEL_H := 0.75  ## hauteur du boîtier à fusibles (le modèle est en centimètres)
const FUSE_SCALE := PANEL_H / 105.0
const CHASE_FROM := Vector2i(19, 7)  ## d'où surgit la créature quand le seau tombe (galerie est)  ## armoire de commande, mur est, avant la grille
var fuses_found: Array = []  ## identifiants ramassés
var fuses_in := 0  ## posés dans l'armoire
var power_on := false
var _panel_sockets: Array[Node] = []
var _panel_led: MeshInstance3D
var _panel_use: Interactable


## Fusible à vis en céramique (le même que ceux du boîtier), couché au sol.
func _fuse_mesh(parent: Node3D) -> Node3D:
	return B.model(parent, "sf:fuse_screw", Vector3.ZERO, 0.0, {"scale": FUSE_SCALE})


func _build_fuses() -> void:
	for id in FUSES:
		if id in fuses_found:
			continue
		var spec: Array = FUSES[id]
		var pos: Vector3 = tile_center(spec[0]) + spec[1]
		pos.y = floor_y(pos) + 0.002
		if id == "citerne":
			# sur le socle en béton d'un pilier, au milieu de la citerne : il faut patauger (bruit)
			var cp := Vector3(10.5 * T, 0, 9.15 * T)
			pos = cp + Vector3(-0.36, CIS_Y + 0.26 + 0.018, 0.05)
		var f := _fuse_mesh(self)
		f.position = pos
		f.rotation_degrees.y = randf_range(0, 360)
		if id == "bertrand":
			# le casque de chantier de Bertrand, renversé à côté
			# sur l'allée, à côté du fusible (jamais au-dessus de la cunette)
			for off in [Vector3(-0.38, 0, 0.12), Vector3(0.0, 0, 0.42), Vector3(0.4, 0, 0.1), Vector3(0.0, 0, -0.42)]:
				var hp: Vector3 = pos + off
				if not in_channel(hp) and not in_channel(hp + Vector3(0.18, 0, 0)) and not in_channel(hp - Vector3(0.18, 0, 0)):
					_hard_hat(Vector3(hp.x, floor_y(hp), hp.z))
					break
			B.decal(self, "res://assets/gen/decal_blood_smear.png", pos + Vector3(-0.2, 0, 0.3), Vector3.UP, 1.1, 1.4, 0.2, Color(1, 1, 1, 0.7))
		var glint := B.omni(f, Vector3(0, 0.06, 0), Color(1.0, 0.9, 0.7), 0.04, 0.6)
		glint.light_specular = 1.0
		var it := Interactable.create(self, pos + Vector3(0, 0.1, 0), Vector3(0.45, 0.3, 0.45), "Ramasser le fusible", Callable())
		var fid: String = id
		it.on_use = func() -> void:
			f.queue_free()
			it.queue_free()
			fuses_found.append(fid)
			Sound.play("pickup", -6.0, 1.2)
			_agitate_creature()
			Game.hud.pickup("Fusible (%d / 3)" % (fuses_found.size() + fuses_in))
			await wait(0.5)
			Game.hud.say(spec[2], 3.6)
			_save_progress()
			_lock_objective()


## Chaque fusible ramassé : elle s'agite (un peu plus rapide, l'oreille un peu plus fine),
## et on l'entend gronder quelque part dans le réseau.
func _agitate_creature() -> void:
	if creature == null:
		return
	creature.aggression = fuses_found.size() + fuses_in
	if creature.state == Creature.State.DORMANT:
		return
	await wait(randf_range(1.8, 3.0))
	Sound.play_at(Sound.variant("creature_growl", 3), creature.head_position(), 2.0, randf_range(0.75, 0.85), 10.0, 90.0, null, "Creature")


## Casque de chantier (scan d'un vrai casque cassé, plein de boue), tombé de travers.
func _hard_hat(at: Vector3) -> void:
	var m := B.model(self, "sf:hard_hat", at, 35.0, {"width": 0.3})
	m.rotation_degrees.z = 14.0
	m.position.y += 0.025


## Armoire de commande de l'écluse : trois logements vides, un voyant rouge.
func _build_panel() -> void:
	# boîtier vissé au mur est, porte ouverte ; dans le modèle, l'avant regarde vers +Z et le fond
	# est à z = -0.214 : tourné de -90° il regarde l'ouest, le fond contre le mur
	var wall_x := 20 * T
	var center := Vector3(wall_x - 0.214 - 0.01, 1.35, PANEL_POS.z)
	var box := B.model(self, "sf:fusebox_vintage", center, -90.0, {"height": PANEL_H, "center": false})
	box.name = "LockPanel"
	_panel_sockets.clear()
	for s in box.find_children("Socket_*", "", true, false):
		_panel_sockets.append(s)
	_panel_sockets.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.23, PANEL_H, 0.56)
	cs.shape = bs
	body.add_child(cs)
	body.position = Vector3(wall_x - 0.115, 1.35, PANEL_POS.z)
	# voyant au-dessus du boîtier (rouge : pas de courant)
	_panel_led = B.sphere(self, 0.016, Vector3(wall_x - 0.03, 1.78, PANEL_POS.z + 0.18), B.emissive(Color(1.0, 0.1, 0.05), 3.0), 8)
	B.box(self, Vector3(0.04, 0.05, 0.05), Vector3(wall_x - 0.02, 1.78, PANEL_POS.z + 0.18), B.color_mat(Color(0.1, 0.1, 0.1), 0.6, 0.3), false)
	B.decal(self, "res://assets/gen/decal_danger.png", Vector3(wall_x, 1.88, PANEL_POS.z - 0.05), Vector3(-1, 0, 0), 0.5, 0.18, 0.06)
	_panel_use = Interactable.create(self, Vector3(wall_x - 0.36, 1.35, PANEL_POS.z), Vector3(0.3, 0.7, 0.6), "Armoire de l'écluse", _use_panel)
	_panel_use.name = "PanelUse"
	_refresh_panel()


func _refresh_panel() -> void:
	# les fusibles posés apparaissent vissés dans les logements vides
	for k in _panel_sockets.size():
		var sock := _panel_sockets[k] as Node3D
		var has := sock.get_child_count() > 0
		if k < fuses_in and not has:
			B.model(sock, "sf:fuse_screw", Vector3.ZERO, 0.0, {"center": false})
		elif k >= fuses_in and has:
			for c in sock.get_children():
				c.queue_free()
	(_panel_led.material_override as StandardMaterial3D).emission = Color(0.1, 1.0, 0.2) if power_on else Color(1.0, 0.1, 0.05)
	if power_on:
		_panel_use.prompt = "Armoire de l'écluse (sous tension)"
	elif fuses_in >= 3:
		_panel_use.prompt = "Remettre le courant (maintenir)"
		_panel_use.hold_time = 1.6
	else:
		_panel_use.prompt = "Armoire de l'écluse (fusibles %d / 3)" % (fuses_in + fuses_found.size())


func _use_panel() -> void:
	if power_on:
		return
	if fuses_found.size() > 0:
		# on enfiche ce qu'on a
		fuses_in += fuses_found.size()
		fuses_found.clear()
		Sound.play_at("pickup", PANEL_POS + Vector3(0, 1.3, 0), -4.0, 0.8)
		on_noise(player.global_position, 4.0)
		_refresh_panel()
		_save_progress()
		if fuses_in < 3:
			Game.hud.say("Il en manque encore %d." % (3 - fuses_in), 2.5)
			_lock_objective()
		else:
			Game.hud.say("Les trois. Bon... Ça va faire du bruit.", 3.0)
		return
	if fuses_in >= 3:
		_restore_power()
		return
	if fuses_in == 0:
		Game.hud.say("Trois logements vides. Plus un seul fusible... Le moteur de la grille ne risque pas de tourner.", 4.0)
	else:
		Game.hud.say("Il en manque encore %d." % (3 - fuses_in), 2.5)
	_lock_objective()


func _restore_power() -> void:
	power_on = true
	_refresh_panel()
	Sound.play_at("boom_hit", PANEL_POS + Vector3(0, 1.3, 0), 2.0, 0.8, 8.0, 80.0)
	Sound.play_at("servo", tile_center(GATE) + Vector3(0, 1.5, 0), 0.0, 0.7, 6.0, 40.0)
	Game.shake(0.7)
	Game.glitch(0.4)
	var hum := Node3D.new()
	add_child(hum)
	hum.position = PANEL_POS + Vector3(-0.3, 1.3, 0)
	Sound.loop_at("buzz_loop", hum, -8.0, 2.0, 14.0)
	# les néons des galeries techniques se rallument en clignotant
	for l in flicker_lights:
		l.light_energy = 2.2
	on_noise(PANEL_POS, 70.0)
	_save_progress()
	await wait(1.0)
	if chain_cut:
		_open_gate()
	else:
		Game.hud.say("Le moteur tourne... Reste la chaîne.", 2.8)
		_lock_objective()


## Objectif courant autour de l'écluse, selon ce qui reste à faire.
func _lock_objective() -> void:
	if gate_opened:
		return
	var todo: Array[String] = []
	if not chain_cut:
		todo.append("couper la chaîne" if has_cutters else "trouver de quoi couper la chaîne")
	if not power_on:
		var n := fuses_in + fuses_found.size()
		todo.append("rétablir le courant (fusibles %d / 3)" % n if n < 3 else "remettre le courant (armoire)")
	Game.hud.objective("Écluse 3 : " + " · ".join(PackedStringArray(todo)))


## Point de reprise : ce qui a été trouvé ou fait reste acquis après une mort.
func _save_progress() -> void:
	if params.get("checkpoint", "start") == "start":
		return
	params["fuses"] = fuses_found.duplicate()
	params["fuses_in"] = fuses_in
	params["power"] = power_on
	Game.level_params = params


# ================================================================== grille de l'écluse
func _build_gate() -> void:
	var c := tile_center(GATE)
	var gate := B.model(self, "large_iron_gate", c + Vector3(0, 0, 0.6), 0.0, {"width": T - 0.05, "center": true})
	gate.name = "Gate"
	var inst := gate.get_child(0) as Node3D
	# chaque battant pivote autour de son gond
	var s := inst.scale.x
	for part_name in ["large_iron_gate_left_door", "large_iron_gate_right_door"]:
		var part := inst.find_child(part_name, true, false) as Node3D
		if part == null:
			continue
		var hinge_x := (-1.45 if part_name.contains("left") else 1.45)
		var pivot := Node3D.new()
		pivot.name = part_name + "_pivot"
		inst.add_child(pivot)
		pivot.position = Vector3(hinge_x, 0, 0)
		part.reparent(pivot, true)
		gate_doors.append(pivot)
		# chaque battant est solide (une fois ouvert, on ne le traverse pas)
		var bb := B.local_aabb(pivot)
		var leaf_body := StaticBody3D.new()
		var leaf_cs := CollisionShape3D.new()
		var leaf_box := BoxShape3D.new()
		leaf_box.size = Vector3(bb.size.x, bb.size.y, maxf(bb.size.z, 0.12 / s))
		leaf_cs.shape = leaf_box
		leaf_cs.position = bb.get_center()
		leaf_body.add_child(leaf_cs)
		pivot.add_child(leaf_body)
	# le verrou est fixé sur le battant droit : il part avec lui
	var bolt := inst.find_child("large_iron_gate_bolt", true, false) as Node3D
	if bolt != null and gate_doors.size() == 2:
		bolt.reparent(gate_doors[1], true)
	gate_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(T, CEIL, 0.3)
	cs.shape = bs
	cs.position = c + Vector3(0, CEIL * 0.5, 0.6)
	gate_body.add_child(cs)
	add_child(gate_body)
	# chaîne + cadenas
	gate_chain = Node3D.new()
	add_child(gate_chain)
	gate_chain.position = c + Vector3(0, 1.05, 0.5)
	var steel := B.color_mat(Color(0.35, 0.33, 0.3), 0.45, 0.9)
	for i in 7:
		var link := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.018
		tm.outer_radius = 0.035
		link.mesh = tm
		link.material_override = steel
		gate_chain.add_child(link)
		link.position = Vector3((i - 3) * 0.05, sin(i * 0.9) * 0.02, 0)
		link.rotation_degrees = Vector3(90 if i % 2 == 0 else 0, 0, 90)
	B.box(gate_chain, Vector3(0.07, 0.08, 0.03), Vector3(0.02, -0.08, 0.0), B.color_mat(Color(0.6, 0.5, 0.2), 0.35, 0.9), false)
	var gate_use := Interactable.create(self, c + Vector3(0, 1.1, 0.15), Vector3(1.6, 1.0, 0.6), "Examiner la grille", _on_gate)
	gate_use.name = "GateUse"
	var gate_lamp := B.model(self, "industrial_wall_lamp", Vector3(20 * T - 0.02, 2.3, 12.2 * T), -90.0, {"center": false})
	gate_lamp.set_meta("editobj", "lamp_gate")
	var gl := B.omni(gate_lamp, Vector3(0, -0.1, 0.28), Color(1.0, 0.75, 0.45), 0.8, 6.0)
	gl.light_volumetric_fog_energy = 2.0
	_lamp_lights.append(gl)


func _build_exit() -> void:
	var c := tile_center(EXIT)
	var steel := B.mat("rusty_metal_02", 0.6, {"metallic": 0.7, "roughness": 0.6})
	var wall_z := (EXIT.y + 1) * T - 0.12
	for i in 22:
		B.box(self, Vector3(0.5, 0.035, 0.035), Vector3(c.x, 0.35 + i * 0.32, wall_z - 0.1), steel, false)
	for sx in [-0.26, 0.26]:
		B.box(self, Vector3(0.04, 7.3, 0.05), Vector3(c.x + sx, 3.65, wall_z - 0.1), steel, false)
	# bouche d'égout entrouverte et clair de lune
	var cover := B.model(self, "water_manhole_cover", c + Vector3(0.2, CEIL + 4.5, 0.4), 0.0, {"width": 0.9})
	cover.rotation_degrees.z = 12
	var moon := B.spot(self, c + Vector3(0.1, CEIL + 5.2, 0.2), c + Vector3(0, 0, -0.3), Color(0.55, 0.65, 0.9), 4.0, 12.0, 24.0, true)
	moon.light_volumetric_fog_energy = 5.0
	var ladder := Interactable.create(self, Vector3(c.x, 1.3, wall_z - 0.25), Vector3(0.8, 1.6, 0.4), "Grimper", _climb)
	ladder.name = "Ladder"


# ================================================================== déroulé
func _intro() -> void:
	player = spawn_player(tile_center(CELL) + Vector3(0.2, 0, 0.35), -80.0)
	Game.hud.show_hud(true)
	Game.hud.set_battery(2)
	for sc in [room_cam, gate_cam]:
		sc.target = player
		sc.tracking = true
	# test : --torch → pas de réveil, cage ouverte, lampe allumée tout de suite
	if Game.args.has("torch"):
		if not Game.args.has("warp"):
			player.global_position = tile_center(Vector2i(2, 1))
		_cell_solved()
		for nm in ["TorchProp", "TorchLight", "TorchPickup"]:
			var n := find_child(nm, false, false)
			if n != null:
				n.queue_free()
		player.has_flashlight = true
		player.set_flashlight(true, true)
		Game.ui.fade_rect.color.a = 0.0
		if not Game.args.has("tour"):
			_setup_triggers()
		return
	if Game.args.has("celltest"):
		_celltest()
		return
	player.has_flashlight = false
	player.control_enabled = false
	player.look_enabled = false
	Game.set_blackout(true, true)
	Game.ui.fade_rect.color.a = 0.0
	# caméra au sol, qui regarde le plafond
	var lying := Transform3D(Basis.from_euler(Vector3(1.35, 0.4, 0.5)), player.global_position + Vector3(0.1, 0.18, 0.2))
	player.set_cinematic(lying, 1.0)
	Sound.play("tinnitus", -6.0)
	await wait(2.0)
	Game.set_blackout(false)
	Game.glitch(1.0)
	await wait(0.5)
	Game.glitch(0.6, false)
	Sound.play("wake_gasp", -2.0)
	await wait(2.5)
	Game.hud.say("Ah... ma tête...", 2.6)
	await wait(2.0)
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: player.set_cinematic(lying, w), 1.0, 0.0, 3.0).set_trans(Tween.TRANS_SINE)
	await wait(1.0)
	Sound.play("body_fall", -18.0, 1.3)
	await wait(2.2)
	player.control_enabled = true
	player.look_enabled = true
	Game.hud.say("Où... où je suis ?", 2.5)
	await wait(3.0)
	Game.hud.say("...Des barreaux ? Je suis dans une CAGE ?!", 3.0)
	await wait(3.4)
	Game.hud.say("Ma lampe... là, juste derrière la grille.", 3.0)
	Game.hud.objective("Sortir de la cellule")
	_setup_triggers()
	if Sound.mic_active():
		await wait(6.0)
		Game.hud.hint(MIC_HINT, 8.0)


## Reprise juste avant de prendre le coupe-boulons (l'établi, le seau, tout est en place).
func _start_from_bench() -> void:
	var tc := tile_center(Vector2i(17, 1))
	player = spawn_player(tc + Vector3(0.35, 0, 0.55), 0.0)
	player.set_flashlight(true, true)
	Game.hud.show_hud(true)
	Game.hud.set_battery(1)
	Game.ui.fade_rect.color.a = 0.0
	Game.glitch(0.8)
	revealed = true
	creature.player = player
	for sc in [room_cam, gate_cam]:
		sc.target = player
		sc.tracking = true
	Game.hud.objective("Prendre le coupe-boulons... et courir")
	_setup_triggers()


func _start_from_cell() -> void:
	player = spawn_player(tile_center(Vector2i(2, 1)), -90.0)
	player.has_flashlight = true
	player.set_flashlight(true, true)
	Game.hud.show_hud(true)
	Game.hud.set_battery(2)
	Game.ui.fade_rect.color.a = 0.0
	Game.glitch(0.8)
	for sc in [room_cam, gate_cam]:
		sc.target = player
		sc.tracking = true
	if params.get("npc", false):
		_lock_objective()
	else:
		Game.hud.objective("Trouver une sortie")
	_setup_triggers()


func _start_from_cutters() -> void:
	player = spawn_player(tile_center(Vector2i(16, 2)) + Vector3(0.6, 0, 0), 180.0)
	has_cutters = true
	player.set_flashlight(true, true)
	Game.hud.show_hud(true)
	Game.hud.set_battery(1)
	Game.ui.fade_rect.color.a = 0.0
	Game.glitch(0.8)
	revealed = true
	creature.player = player
	creature.global_position = tile_center(Vector2i(4, 11))
	creature.activate(Creature.State.PATROL)
	for sc in [room_cam, gate_cam]:
		sc.target = player
		sc.tracking = true
	_lock_objective()
	_setup_triggers()


func _pick_torch(torch: Node3D, torch_light: Node3D) -> void:
	if not is_instance_valid(torch):
		return
	var pickup := find_child("TorchPickup", false, false)
	if pickup != null:
		pickup.queue_free()
	torch.queue_free()
	if is_instance_valid(torch_light):
		torch_light.queue_free()
	Sound.play("pickup", -6.0)
	player.has_flashlight = true
	player.set_flashlight(true)
	Game.hud.pickup("Lampe torche")
	await wait(1.0)
	if cell_open:
		Game.hud.objective("Trouver une sortie")
	await wait(2.5)
	Game.hud.hint("[F] lampe torche   ·   [C] maintenir pour s'accroupir   ·   [Tab] objectif   ·   [I] inventaire", 6.0)


func _setup_triggers() -> void:
	add_trigger(Vector3(4.5 * T, 0, 1.5 * T), 2.6, func() -> void:
		Game.hud.say("« Il entend tout »... Qui ça, « il » ?", 3.0))
	# la baladeuse du couloir lâche juste avant que Théo passe dessous (déjà morte si on reprend plus loin)
	if _corridor_lamp != null and is_instance_valid(_corridor_lamp) and _corridor_lamp.visible:
		if revealed:
			_lamp_off(_corridor_lamp)
		else:
			add_trigger(_corridor_lamp.global_position, 4.5, _corridor_lamp_fails)
	# première apparition, mise en scène : elle traverse le croisement au bout du collecteur
	for t in [Vector2i(4, 5), Vector2i(5, 5), Vector2i(4, 6)]:
		add_trigger(tile_center(t), 1.5, _reveal_cross)
	# si le joueur passe par ailleurs : depuis le bord de la citerne, ou plus loin
	for t in [Vector2i(6, 10), Vector2i(12, 6), Vector2i(12, 10), Vector2i(6, 7), Vector2i(6, 12)]:
		add_trigger(tile_center(t), 1.6, _reveal_cistern)
	add_trigger(tile_center(Vector2i(16, 4)), 2.0, _reveal_far)
	add_trigger(tile_center(Vector2i(15, 1)), 2.0, _reveal_far)
	add_trigger(tile_center(Vector2i(19, 6)), 2.0, _reveal_far)
	add_trigger(tile_center(Vector2i(19, 11)), 2.0, func() -> void:
		Game.hud.say("Une grille... C'est l'écluse 3 ?", 2.8))


## Première rencontre : la créature traverse le croisement, dans la lumière, sans « voir » la lampe
## braquée sur elle ; un rat couine plus loin et elle file vers le bruit. On comprend sans le dire.
func _reveal_cross() -> void:
	if revealed:
		return
	revealed = true
	creature.player = player
	var a := tile_center(Vector2i(8, 4))
	var mid := tile_center(Vector2i(8, 5))
	creature.global_position = a
	creature.heading = 0.0
	creature.stand_and_watch(null, "listen", 0.8)
	creature.visible = false
	# on attend que Théo regarde vers le bout du collecteur (ou un peu)
	var t := 0.0
	while t < 5.0:
		await ticked
		t += get_process_delta_time()
		var to := (mid + Vector3(0, 1.2, 0) - player.head.global_position).normalized()
		if (-player.head.global_basis.z).dot(to) > 0.75:
			break
	creature.visible = true
	creature.script_walk(PackedVector3Array([mid]), 1.1)
	Sound.play_at(Sound.variant("creature_click", 3), mid + Vector3(0, 1.8, 0), 2.0, 1.0, 8.0, 50.0)
	Game.glitch(0.25, false)
	await creature.script_done
	# elle s'arrête au milieu, tête qui tressaute... la lumière de la lampe ne lui fait rien
	creature.stand_and_watch(null, "listen", 0.7)
	creature.twitch.spasm(0.8)
	await wait(1.4)
	Game.hud.say("...", 1.2)
	await wait(1.6)
	Sound.play_at(Sound.variant("creature_click", 3), mid + Vector3(0, 1.8, 0), 0.0, 0.95, 8.0, 50.0)
	await wait(1.2)
	# un rat couine dans le noir, vers la citerne : elle bondit dans cette direction
	var rat_pos := tile_center(Vector2i(8, 7)) + Vector3(0.6, 0, -0.4)
	Sound.play_at(Sound.variant("rat_squeak", 3), rat_pos, 2.0, 0.9, 6.0, 40.0)
	await wait(0.25)
	creature.twitch.spasm(1.2)
	# elle se dresse d'un coup et hurle vers le bruit... puis part au galop
	creature.stand_and_watch(null, "screech", 1.3)
	creature.actor.anim.seek(0.5, true)
	Sound.play_at("creature_shriek", mid + Vector3(0, 1.8, 0), 3.0, 1.0, 10.0, 70.0)
	Game.glitch(0.3, false)
	await wait(1.1)
	creature.script_walk(PackedVector3Array([tile_center(Vector2i(8, 6)), rat_pos]), 3.4)
	Game.glitch(0.3, false)
	await creature.script_done
	creature.deactivate()
	await wait(1.0)
	Game.hud.say("C'est quoi... ce truc...", 3.0)
	await wait(3.4)
	Game.hud.say("Il a foncé sur le bruit. Ma lampe, il l'a même pas remarquée.", 3.6)
	# quelques instants plus tard, elle rôde pour de bon
	await wait(14.0)
	if creature.state == Creature.State.DORMANT and not escaping:
		creature.global_position = tile_center(Vector2i(9, 9))
		creature.activate(Creature.State.PATROL)


func _reveal_cistern() -> void:
	if revealed:
		return
	revealed = true
	var pt := tile_of(player.global_position)
	# la créature traverse la citerne du côté opposé au joueur
	var far_x := 11 if pt.x <= 8 else 7
	var a := tile_center(Vector2i(far_x, 7 if pt.y > 8 else 9))
	var b := tile_center(Vector2i(far_x, 9 if pt.y > 8 else 7))
	creature.player = player
	creature.global_position = a
	creature.heading = atan2(-(b - a).x, -(b - a).z)
	creature.script_walk(PackedVector3Array([b]), 1.1)
	Sound.play("stinger_soft", -2.0)
	await wait(1.5)
	Game.glitch(0.4)
	Game.hud.say("...", 1.5)
	await wait(2.5)
	Game.hud.say("C'est quoi... ce truc...", 3.0)
	await creature.script_done
	creature.activate(Creature.State.PATROL)


func _reveal_far() -> void:
	if revealed:
		return
	revealed = true
	creature.player = player
	var spawn := tile_center(Vector2i(9, 8))
	creature.global_position = spawn
	creature.activate(Creature.State.PATROL)
	Sound.play_at("creature_shriek", spawn + Vector3(0, 2, 0), 6.0, 0.9, 12.0, 90.0)
	Game.glitch(0.5)
	await wait(2.5)
	Game.hud.say("C'était quoi, ça ?!", 2.5)


## Corps d'un des amis (personnage Rocketbox figé dans une pose au sol) + sang + réaction de Théo.
func _body(who: String, pos: Vector3, yaw: float, lines: Array) -> void:
	var a := Actor.create(self, who, pos, yaw)
	a.play("dead", 0.0)
	a.tint("", Color(0.62, 0.58, 0.56), 0.55)
	# la pose est appliquée tout de suite, puis le corps est posé au sol : le gros du corps (et pas
	# seulement le point le plus bas, souvent une main) touche le sol
	var low := a.lowest_point(0.06)
	if low < INF:
		a.global_position.y += floor_y(pos) + 0.005 - low
	B.decal(self, "res://assets/gen/decal_blood_pool.png", pos + Vector3(0, 0.1, 0), Vector3.UP, 2.2, 2.2, 0.5)
	# des mouches tournent au-dessus du corps
	var flies := Nature.flies(self, pos + Vector3(0, floor_y(pos) + 0.4, 0))
	Sound.loop_at("flies_loop", flies, -12.0, 1.0, 7.0)
	var seen := [false]
	var it := Interactable.create(self, pos + Vector3(0, 0.3, 0), Vector3(1.4, 0.6, 1.4), "Examiner", func() -> void:
		if seen[0]:
			Game.hud.say(lines[lines.size() - 1], 3.0)
			return
		seen[0] = true
		Sound.play("stinger_soft", -6.0)
		Game.glitch(0.3)
		player.danger = maxf(player.danger, 0.4)
		for l in lines:
			Game.hud.say(l, 3.2)
			await wait(3.4))
	it.name = "Body_" + who


func _read_max_phone() -> void:
	await read_document("Le téléphone de Max",
		"[b]Max[/b]  ·  batterie 3 %\n\n" +
		"[color=#9aa]Brouillon non envoyé — 01:47[/color]\n" +
		"ils nous ont descendus en bas. inès a crié et après plus rien. karim est parti chercher une sortie vers l'écluse il est pas revenu\n\n" +
		"[color=#9aa]Brouillon non envoyé — 02:20[/color]\n" +
		"il clique. quand il clique faut plus bouger\n\n" +
		"[color=#9aa]Brouillon non envoyé — 02:31[/color]\n" +
		"théo si tu trouves ça pardon pour ton anniv de l'an dernier. barre toi", "phone")
	Game.hud.say("Max...", 2.0)


func _take_cutters(cutters: Node3D, bucket: Node3D) -> void:
	if has_cutters:
		return
	has_cutters = true
	var use := find_child("CuttersUse", false, false)
	if use != null:
		use.queue_free()
	cutters.queue_free()
	Sound.play("pickup", -4.0)
	Game.hud.pickup("Coupe-boulons")
	# point de reprise : si la poursuite tourne mal, on recommence devant l'établi
	params = {"checkpoint": "bench"}
	_save_progress()
	# le seau rouillé tombe de l'établi : vacarme
	var tw := create_tween()
	tw.tween_property(bucket, "position", bucket.position + Vector3(0.3, -0.9, 0.4), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await wait(0.3)
	Sound.play_at("metal_clang", bucket.global_position, 6.0, 1.0, 8.0, 80.0)
	Game.glitch(0.3, false)
	await wait(0.6)
	Game.hud.say("Merde... merde, merde.", 1.8)
	await wait(1.2)
	# un hurlement au bout de la galerie : il arrive, et il sait où est Théo
	revealed = true
	creature.player = player
	if not creature.visible or creature.global_position.distance_to(player.global_position) > 22.0:
		creature.global_position = tile_center(CHASE_FROM)
	creature.charge(6.0)
	Game.shake(0.6)
	await wait(1.4)
	Game.hud.say("Il arrive. COURS !", 2.0)
	Game.hud.objective("Le semer")
	_watch_escape()


## La poursuite après le coupe-boulons. Le point de reprise reste devant l'établi : quoi qu'il arrive
## ensuite, mourir oblige à reprendre le coupe-boulons et à refaire la poursuite.
func _watch_escape() -> void:
	var calm := 0.0
	while not dying and not escaping:
		await ticked
		calm = 0.0 if creature.is_hunting() else calm + get_process_delta_time()
		if calm > 6.0:
			break
	if dying or escaping:
		return
	Game.hud.say("...Je crois que je l'ai semé.", 2.8)
	await wait(3.0)
	_lock_objective()


func _on_gate() -> void:
	var use := find_child("GateUse", false, false) as Interactable
	if chain_cut:
		return
	if not has_cutters:
		Sound.play_at("door_locked", tile_center(GATE) + Vector3(0, 1, 0), -4.0, 0.7)
		on_noise(player.global_position, 6.0)
		if power_on:
			Game.hud.say("Une chaîne et un cadenas... Il me faut de quoi couper ça.", 3.5)
		else:
			Game.hud.say("Une chaîne, un cadenas... et une grille à moteur. L'armoire à côté est éteinte.", 4.0)
		_lock_objective()
		return
	# couper : action longue et bruyante
	use.disable()
	var cut := Interactable.create(self, tile_center(GATE) + Vector3(0, 1.1, 0.15), Vector3(1.6, 1.0, 0.6), "Couper la chaîne (maintenir)", _cut_chain, 2.6)
	cut.name = "CutUse"
	Game.hud.say("Ça va faire un boucan d'enfer... Faut qu'il soit loin.", 3.2)


func _cut_chain() -> void:
	chain_cut = true
	var cut := find_child("CutUse", false, false)
	if cut != null:
		cut.queue_free()
	Sound.play_at("cutter_strain", gate_chain.global_position, 0.0)
	await wait(0.7)
	Sound.play_at("chain_snap", gate_chain.global_position, 6.0, 1.0, 10.0, 90.0)
	on_noise(gate_chain.global_position, 90.0)
	gate_chain.queue_free()
	await wait(0.6)
	if not power_on:
		Game.hud.say("La chaîne a sauté... mais la grille ne bouge pas. Le moteur est mort.", 3.6)
		_lock_objective()
		if creature.state != Creature.State.CHASE:
			creature.hear(tile_center(GATE), 90.0)
		return
	Game.hud.say("Ça y est !", 1.5)
	_open_gate()


func _open_gate() -> void:
	gate_opened = true
	gate_body.queue_free()
	Sound.play_at("gate_open", tile_center(GATE) + Vector3(0, 1.5, 0), 4.0, 1.0, 10.0, 90.0)
	for i in gate_doors.size():
		var tw := create_tween()
		tw.tween_property(gate_doors[i], "rotation_degrees:y", -95.0 if i == 0 else 95.0, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	astar.set_point_solid(GATE, false)
	# la créature a tout entendu
	if creature.state != Creature.State.CHASE:
		creature.hear(tile_center(GATE), 90.0)
	Sound.play("stinger_violin", -6.0)
	await wait(1.2)
	Game.hud.objective("Monter à l'échelle !")
	Game.hud.say("Vite !", 1.2)


func inventory() -> Array:
	var items := []
	if player != null and player.has_flashlight:
		items.append({"id": "flashlight", "name": "Lampe torche", "desc": "Ta lampe de service. Il n'y voit rien : la lumière ne te trahit pas. [F] pour l'allumer."})
	if has_bar and not cell_open:
		items.append({"id": "bar", "name": "Barre de fer", "desc": "Un barreau arraché à la cage. Assez long pour attraper quelque chose à travers la grille."})
	if has_keys and not cell_open:
		items.append({"id": "keys", "name": "Trousseau de clés", "desc": "Deux clés sur un anneau. L'une d'elles doit ouvrir le cadenas de la cage."})
	if bottles > 0:
		items.append({"id": "bottle", "name": "Bouteille vide", "count": bottles, "desc": "Lance-la loin de toi ([G] ou clic droit) : le verre qui éclate l'attire là-bas."})
	if not fuses_found.is_empty():
		items.append({"id": "fuse", "name": "Fusible", "count": fuses_found.size(), "desc": "Fusible de l'armoire de commande de l'écluse 3. Il en faut trois (%d posé%s)." % [fuses_in, "s" if fuses_in > 1 else ""]})
	if has_cutters:
		items.append({"id": "cutters", "name": "Coupe-boulons", "desc": "Pris sur l'établi du local technique. De quoi couper la chaîne de la grille."})
	return items


## Pose de la caméra sur l'échelle après `p` échelons (p continu).
func _climb_pose(p: float, c: Vector3, wall_z: float) -> Transform3D:
	var i := floorf(p)
	var f := p - i
	# chaque échelon : traction (smoothstep sur 70 % du temps) puis petit temps d'arrêt
	var pull := smoothstep(0.0, 0.7, f)
	var y := 1.35 + (i + pull) * 0.42
	var side := 1.0 if int(i) % 2 == 0 else -1.0  # main gauche, main droite
	var sway := sin(pull * PI) * side
	var basis := Basis.from_euler(Vector3(0.32 + 0.04 * sin(p * PI), PI + 0.05 * sway, 0.045 * sway))
	return Transform3D(basis, Vector3(c.x + 0.03 * sway, y, wall_z - 0.45 - 0.03 * sin(pull * PI)))


func _climb() -> void:
	if escaping:
		return
	escaping = true
	player.control_enabled = false
	player.look_enabled = false
	player.set_flashlight(true, true)
	var c := tile_center(EXIT)
	var wall_z := (EXIT.y + 1) * T - 0.12
	var start := player.head.global_transform
	var face := _climb_pose(0.0, c, wall_z)
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: player.set_cinematic(start.interpolate_with(face, w), 1.0), 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await wait(0.7)
	# montée continue, calculée à chaque image : un échelon toutes les RUNG_TIME secondes,
	# l'élan de chaque traction (montée rapide puis pause), le corps qui balance d'un bras sur l'autre
	const RUNGS := 14
	const RUNG_TIME := 0.42
	var t := 0.0
	var last_rung := -1
	while t < RUNGS * RUNG_TIME:
		await ticked
		t += get_process_delta_time()
		var p := minf(t / RUNG_TIME, float(RUNGS))
		player.set_cinematic(_climb_pose(p, c, wall_z), 1.0)
		var rung := int(p)
		if rung != last_rung and rung < RUNGS:
			last_rung = rung
			Sound.play_at("ladder_step", Vector3(c.x, 1.35 + rung * 0.42 - 0.8, wall_z), -6.0, randf_range(0.9, 1.1))
			if rung == 6:
				Sound.play_at("creature_shriek", c + Vector3(0, 1, -3), 6.0, 1.0, 10.0, 60.0)
				Game.glitch(0.6)
				Game.shake(0.8)
	Sound.play("door_creak", -4.0, 0.6)
	Game.flash(0.6)
	await Game.ui.fade_to(1.0, 1.2)
	Game.start_level("ending")


# ================================================================== mort
func _on_caught() -> void:
	if dying or escaping:
		return
	dying = true
	player.control_enabled = false
	player.look_enabled = false
	var start := player.head.global_transform
	var to_head := creature.head_position() - start.origin
	var face := Transform3D(Basis.looking_at(to_head.normalized(), Vector3.UP), start.origin)
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: player.set_cinematic(start.interpolate_with(face, w), 1.0), 0.0, 1.0, 0.18)
	Sound.play("creature_attack", 4.0)
	Game.glitch(1.0, false)
	Game.shake(3.0)
	await wait(0.35)
	# Théo hurle, la caméra est arrachée et tombe au sol : elle ne filme plus que le plafond
	Sound.play(Sound.variant("theo_scream", 2), 2.0, randf_range(0.95, 1.05))
	Sound.play("hit_impact", -2.0)
	Game.flash(0.4)
	var ground := player.global_position + Vector3(randf_range(-0.25, 0.25), 0, randf_range(-0.25, 0.25))
	ground.y = maxf(floor_y(ground), WATER_Y) + 0.06
	var ahead := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
	var up_basis := Basis.looking_at(Vector3.UP, ahead) * Basis(Vector3(1, 0, 0), randf_range(-0.2, 0.2)) * Basis(Vector3(0, 0, 1), randf_range(-0.6, 0.6))
	var floor_t := Transform3D(up_basis, ground)
	var tw2 := create_tween()
	tw2.tween_method(func(w: float) -> void: player.set_cinematic(face.interpolate_with(floor_t, w), 1.0), 0.0, 1.0, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await wait(0.45)
	Sound.play("body_fall", -2.0)
	Game.shake(1.0)
	Game.glitch(0.6, false)
	# hors du champ : on l'entend traîner Théo au loin
	var back := Vector3(creature.global_position.x - player.global_position.x, 0, creature.global_position.z - player.global_position.z)
	back = back.normalized() if back.length() > 0.01 else -ahead
	var drag_node := Node3D.new()
	add_child(drag_node)
	drag_node.global_position = player.global_position + Vector3(0, 0.2, 0)
	var drag := Sound.loop_at("body_drag_loop", drag_node, -3.0, 2.0, 16.0)
	Sound.play_at(Sound.variant("creature_growl", 3), creature.head_position(), 2.0, 0.85, 6.0, 40.0, null, "Creature")
	var tw3 := create_tween()
	tw3.tween_property(drag_node, "global_position", drag_node.global_position + back * 6.0, 3.0)
	await wait(0.3)
	creature.deactivate()
	Sound.muffle_master(3000.0, 1.2)
	await wait(2.7)
	if is_instance_valid(drag):
		Sound.fade(drag, -60.0, 0.6, true)
	await wait(0.8)
	Sound.play("signal_lost", -4.0, 1.0, "UI")
	Game.hud.osd("SIGNAL PERDU")
	Game.glitch(1.0, false)
	await wait(0.8)
	Game.set_blackout(true)
	await wait(1.2)
	Game.hud.osd("")
	Sound.reset_effects()
	await _rewind()
	Game.level_params = params
	Game.retry_from_checkpoint()


## Rembobinage façon cassette : la caméra repart à l'envers sur ses dernières secondes, en accéléré,
## l'horloge recule, puis la lecture reprend au dernier point de reprise.
func _rewind() -> void:
	if _cam_hist.size() < 10:
		return
	Game.set_blackout(false)
	Game.clock_running = false
	Game.set_rewind(1.0)
	Game.hud.set_rec(false)  # une cassette qu'on rembobine n'enregistre pas
	Game.hud.osd("◀◀  REMBOBINAGE", true)
	var whirr := Sound.play("tape_rewind_0", -6.0, 1.0, "UI")
	if creature != null:
		creature.deactivate()
	var n := _cam_hist.size()
	var dur := clampf(n / 30.0 / 5.0, 1.2, 2.6)
	var t := 0.0
	while t < dur:
		await ticked
		var dt := get_process_delta_time()
		t += dt
		var idx := clampi(int((1.0 - t / dur) * (n - 1)), 0, n - 1)
		player.set_cinematic(_cam_hist[idx], 1.0)
		Game.clock = maxf(0.0, Game.clock - dt * (n / 30.0) / dur)
		Game.hud.set_clock(Game.clock_text())
		if randf() < dt * 3.0:
			Game.glitch(0.3, false)
	if is_instance_valid(whirr):
		whirr.queue_free()
	Game.flash(0.4)
	Game.set_rewind(0.0)
	Game.hud.osd("", true)
	Game.set_blackout(true, true)



# ================================================================== ambiance
func _ambient_loop() -> void:
	pass


func _process(delta: float) -> void:
	super._process(delta)
	_time += delta
	if player == null:
		return
	if Input.is_action_just_pressed("throw") and bottles > 0 and player.can_act() and not dying and not escaping and not Game.args.has("shots"):
		_throw_bottle()
	_zone_audio(delta)
	_creature_tracks(delta)
	_lamp_shadows(delta)
	_update_rings()
	_update_debris(delta)
	_update_roaches(delta)
	_update_events(delta)
	# la caméra garde en mémoire ses 12 dernières secondes de trajet (rembobinage à la mort)
	_hist_t += delta
	if _hist_t >= 1.0 / 30.0 and not dying:
		_hist_t = 0.0
		_cam_hist.append(player.head.global_transform)
		if _cam_hist.size() > 360:
			_cam_hist.pop_front()
	# la créature surgit tout près, en face : la mise au point de la caméra patine
	if creature != null and creature.visible and creature.state != Creature.State.DORMANT:
		var cd := creature.global_position.distance_to(player.global_position)
		var face := (-player.cam.global_basis.z).dot((creature.head_position() - player.cam.global_position).normalized())
		if cd < 2.8 and face > 0.6 and not _close_seen:
			_close_seen = true
			Game.focus_hunt(1.0)
		elif cd > 5.0:
			_close_seen = false
	# de temps en temps elle change de voie : l'autre banquette, ou elle redescend patauger dans l'eau
	_lane_cd -= delta
	if _lane_cd <= 0.0:
		_lane_cd = randf_range(8.0, 18.0)
		_ledge_side = 0.0 if randf() < 0.35 else (1.0 if randf() < 0.5 else -1.0)
	# l'égoutier : on le voit depuis la cage ; il parle quand Théo sort et s'approche
	if _npc_state == 0 and _npc != null:
		var dn := Vector2(player.global_position.x - NPC_POS.x, player.global_position.z - NPC_POS.z).length()
		if cell_open and dn < 2.4:
			_npc_talk()
		elif not cell_open and not _npc_seen and player.flashlight_on and dn < 5.5:
			var to := (NPC_POS + Vector3(0, 0.6, 0) - player.eye_position()).normalized()
			if to.dot(-player.cam.global_basis.z) > 0.94:
				_npc_seen = true
				Game.hud.say("Y'a quelqu'un, là... Hé ! Monsieur ! ...Il bouge pas.", 3.4)
	# de temps en temps, un coup de vent dans la forêt au-dessus du puits le plus proche
	_gust_cd -= delta
	if _gust_cd <= 0.0 and not _shaft_tops.is_empty():
		_gust_cd = randf_range(35.0, 80.0)
		var best: Array = _shaft_tops[0]
		for st in _shaft_tops:
			if (st[0] as Vector3).distance_to(player.global_position) < (best[0] as Vector3).distance_to(player.global_position):
				best = st
		_forest_gust(best[0], best[1], best[2])
	# poussière en suspension autour de Théo (visible dans le faisceau de la lampe)
	if dust == null:
		dust = Nature.dust(self, Vector3(5.0, 1.6, 5.0), 2600)
		dust_near = Nature.dust_bokeh(self)
	dust.global_position = player.global_position + Vector3(0, 1.4, 0)
	# grains tout près de l'objectif : flous, comme de petites bulles dans le faisceau
	dust_near.global_position = player.cam.global_position - player.cam.global_basis.z * 1.0
	# gouttes qui tombent autour du joueur
	_drip_cd -= delta
	if _drip_cd <= 0.0:
		_drip_cd = randf_range(0.5, 2.0)
		var p := player.global_position + Vector3(randf_range(-5, 5), 2.6, randf_range(-5, 5))
		if walkable(tile_of(p)) and _is_water(p) and randf() < 0.8:
			_falling_drop(p)
		else:
			Sound.play_at(Sound.variant("drip", 3), p, randf_range(-14.0, -4.0), randf_range(0.8, 1.3), 2.5, 20.0)
	# cri lointain (quelqu'un d'autre est encore en vie ?)
	_wail_cd -= delta
	if _wail_cd <= 0.0:
		_wail_cd = randf_range(70.0, 130.0)
		var far := random_point(player.global_position, 8)
		Sound.play_at("distant_wail", far + Vector3(0, 1.5, 0), -2.0, randf_range(0.9, 1.05), 12.0, 120.0)
	# néons défaillants
	for l in flicker_lights:
		if randf() < delta * 3.0:
			var on := randf() > 0.35
			l.visible = on
			if l.has_meta("glow"):
				var g := l.get_meta("glow") as StandardMaterial3D
				if not g.has_meta("base"):
					g.set_meta("base", g.emission_energy_multiplier)
				g.emission_energy_multiplier = float(g.get_meta("base")) if on else 0.02
	# présence de la créature : rythme cardiaque, parasites
	# (pendant une poursuite le cœur s'emballe, puis il ralentit lentement quand elle a lâché)
	if creature != null and creature.is_hunting():
		_chase_heat = 1.0
	else:
		_chase_heat = maxf(0.0, _chase_heat - delta / 12.0)
	if creature != null and creature.visible:
		var d := creature.global_position.distance_to(player.global_position)
		var danger := clampf(1.0 - d / 16.0, 0.0, 1.0)
		danger = maxf(danger, _chase_heat * 0.75)
		player.danger = danger
		_presence_cd -= delta
		if d < 7.0 and _presence_cd <= 0.0:
			_presence_cd = randf_range(0.8, 2.5)
			Game.glitch(0.12 + (7.0 - d) * 0.04, false)
		Game.set_fx("gain", 0.4 + danger * 0.45)
	else:
		player.danger = _chase_heat * 0.75
	# trop longtemps sans la croiser : elle vient rôder dans le secteur du joueur (sans savoir où il est)
	if revealed and creature != null and not escaping and creature.state in [Creature.State.PATROL, Creature.State.SEARCH]:
		var dist := creature.global_position.distance_to(player.global_position)
		_unseen = 0.0 if dist < 13.0 else _unseen + delta
		if _unseen > 40.0:
			_unseen = 0.0
			creature.wander_to(random_point(player.global_position, 2))
	# à bout de souffle : la respiration fait du bruit
	_breath_noise_cd -= delta
	if player.exhausted and _breath_noise_cd <= 0.0:
		_breath_noise_cd = 1.0
		on_noise(player.global_position, 3.8)


# ================================================================== l'égoutier mourant
## Adossé au mur juste devant la cage : inconscient tant que Théo est enfermé, il se réveille
## quand Théo sort et s'approche, et lui explique l'écluse 3 et les trois fusibles avant de mourir.
const NPC_POS := Vector3(3 * T - 0.44, 0.0, 7.6)
var _npc: Actor
var _npc_breath: AudioStreamPlayer3D
var _npc_twitch: TwitchModifier
var _npc_body: BreathModifier
var _npc_state := 0  ## 0 = inconscient, 1 = il parle, 2 = mort
var _npc_seen := false


func _build_npc() -> void:
	_npc = Actor.create(self, "egoutier", NPC_POS, PI * 0.5)
	_npc.play("sit", 0.0)
	_npc.tint("", Color(0.72, 0.68, 0.64), 0.75)
	# assis : ce sont les fesses qui portent (le point le plus bas de la pose d'origine était une main,
	# il restait 12 cm de vide sous lui) — on pose le bassin à hauteur d'assise
	if _npc.anim != null:
		_npc.anim.advance(0.0)  # la pose assise doit être appliquée avant de mesurer
	var pelvis_y := _npc.bone_position("Pelvis").y
	_npc.global_position.y += floor_y(NPC_POS) + 0.12 - pelvis_y
	_npc_twitch = TwitchModifier.new()
	_npc_twitch.forward_ref = _npc
	_npc_twitch.twitch_amount = 0.08
	_npc.skeleton.add_child(_npc_twitch)
	_npc_twitch.bones = {"head": _npc.bone("Head"), "neck": _npc.bone("Neck")}
	_npc_body = BreathModifier.new()
	_npc_body.forward_ref = _npc
	_npc_body.chest = _npc.bone("Spine2")
	_npc_body.head = _npc.bone("Head")
	_npc_body.droop = 0.85
	# les mains à plat au sol, de chaque côté (plus de bras tendus en avant)
	_npc_body.pelvis = _npc.bone("Pelvis")
	_npc_body.ground_y = floor_y(NPC_POS)
	_npc_body.arms = [[_npc.bone("L UpperArm"), _npc.bone("L Forearm"), _npc.bone("L Hand"), -1.0],
		[_npc.bone("R UpperArm"), _npc.bone("R Forearm"), _npc.bone("R Hand"), 1.0]]
	_npc.skeleton.add_child(_npc_body)
	# il a saigné là, en glissant le long du mur
	B.decal(self, "res://assets/gen/decal_blood_pool.png", NPC_POS + Vector3(-0.35, 0.1, 0), Vector3.UP, 1.4, 1.6, 0.4, Color(1, 1, 1, 0.85))
	B.decal(self, "res://assets/gen/decal_blood_smear.png", Vector3(3 * T - 0.01, 0.95, NPC_POS.z + 0.1), Vector3(-1, 0, 0), 0.5, 1.0, 0.15, Color(1, 1, 1, 0.75))
	var it := Interactable.create(self, NPC_POS + Vector3(-0.3, 0.55, 0), Vector3(1.1, 1.0, 0.9), "L'homme...", func() -> void:
		if _npc_state == 0 and cell_open:
			_npc_talk()
		elif _npc_state == 2:
			Game.hud.say("Son badge : « L. Mercier — Service assainissement ». ...Désolé, Lucien.", 3.6))
	it.name = "NpcUse"
	if params.get("npc", false):
		_npc_dead_pose()
		return
	_npc_breath = Sound.loop_at("dying_breath_loop", _npc, -8.0, 1.6, 9.0)
	_npc_breath.position.y = 0.7
	# un peu plus grave et plus lent : un homme âgé qui s'épuise
	_npc_breath.pitch_scale = 0.9


func _npc_dead_pose() -> void:
	_npc_state = 2
	_npc_body.depth = 0.0
	_npc_body.droop = 1.0
	_npc_twitch.twitch_amount = 0.0
	_npc_twitch.look_weight = 0.0


func _npc_say(text: String, duration: float) -> void:
	# pas de fausse voix : le sous-titre suffit ; sa respiration s'efface pendant qu'il parle
	if is_instance_valid(_npc_breath):
		Sound.fade(_npc_breath, -22.0, 0.3)
	Game.hud.say(text, duration, "L'égoutier")
	await wait(duration + 0.25)
	if is_instance_valid(_npc_breath) and _npc_state == 1:
		Sound.fade(_npc_breath, -8.0, 0.6)


func _npc_talk() -> void:
	if _npc_state != 0:
		return
	_npc_state = 1
	var head := _npc.global_position + Vector3(0, 0.8, 0)
	Sound.play_at(Sound.variant("dying_cough", 2), head, -2.0, 1.0, 2.0, 14.0)
	# Théo s'accroupit devant lui : on ne rate rien de ce qu'il dit
	player.control_enabled = false
	player.look_enabled = false
	var start := player.head.global_transform
	var eye := NPC_POS + Vector3(-1.0, 0.92, 0.12)
	var close := Transform3D(Basis.looking_at(head + Vector3(0.05, -0.08, 0) - eye, Vector3.UP), eye)
	var cam_tw := create_tween()
	cam_tw.tween_method(func(w: float) -> void: player.set_cinematic(start.interpolate_with(close, w), 1.0), 0.0, 1.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# il relève la tête vers Théo
	_npc_twitch.target = player.head
	var tw := create_tween().set_parallel()
	tw.tween_property(_npc_body, "droop", 0.15, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_npc_twitch, "look_weight", 0.85, 1.6).set_trans(Tween.TRANS_SINE)
	await wait(1.6)
	await _npc_say("Toi... t'es réveillé...", 2.2)
	Game.hud.say("Monsieur ? Vous êtes blessé... attendez, je—", 2.4)
	await wait(2.5)
	await _npc_say("Laisse... Écoute-moi. La seule sortie, c'est l'écluse 3. La grille, tout au fond, vers l'est.", 4.0)
	await _npc_say("Ils l'ont fermée avec une chaîne. Y a des pinces dans le local technique... au nord.", 3.6)
	Sound.play_at(Sound.variant("dying_cough", 2), head, -6.0, 1.05, 2.0, 14.0)
	await wait(0.9)
	await _npc_say("Et ils ont coupé le courant. Les trois fusibles de l'armoire... ils les ont balancés dans le réseau.", 4.0)
	await _npc_say("Un dans chaque partie des égouts. Bertrand est parti les chercher... il est jamais revenu.", 3.8)
	await _npc_say("La chose, là-dedans... elle voit rien. Elle entend. Quand elle clique... tu bouges plus.", 4.0)
	Game.hud.say("Tenez bon, je vais chercher de l'aide—", 2.0)
	await wait(2.1)
	await _npc_say("...Les fusibles...", 1.8)
	# dernier souffle
	if is_instance_valid(_npc_breath):
		Sound.fade(_npc_breath, -60.0, 1.0, true)
	Sound.play_at("death_rattle", head, -3.0, 0.96, 2.0, 12.0)
	var tw2 := create_tween().set_parallel()
	tw2.tween_property(_npc_body, "droop", 1.0, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw2.tween_property(_npc_body, "depth", 0.0, 2.6)
	tw2.tween_property(_npc_twitch, "look_weight", 0.0, 1.8)
	_npc_twitch.twitch_amount = 0.0
	await wait(2.8)
	_npc_dead_pose()
	params["npc"] = true
	Game.level_params = params
	Game.hud.say("Hé... Hé ! ...Non. Non, non, non.", 2.6)
	await wait(2.8)
	Game.hud.say("...Trois fusibles. Une chaîne. L'écluse 3.", 2.8)
	# Théo se relève
	var back := player.head.global_transform
	var tw3 := create_tween()
	tw3.tween_method(func(w: float) -> void: player.set_cinematic(close.interpolate_with(back, w), 1.0 - w), 0.0, 1.0, 1.1).set_trans(Tween.TRANS_SINE)
	await wait(1.1)
	player.set_cinematic(Transform3D(), 0.0)
	player.control_enabled = true
	player.look_enabled = true
	_lock_objective()


# ================================================================== planque d'une ancienne victime
## Cul-de-sac où quelqu'un a tenu des jours : sac de couchage, conserves vides, traits au mur,
## sa lampe morte. On comprend sans qu'on le dise.
const HIDEOUT := Vector2i(8, 13)


func _build_hideout() -> void:
	var c := tile_center(HIDEOUT)
	var base := Vector3(c.x + 1.0, floor_y(Vector3(c.x + 1.0, 0, c.z)), c.z)
	# tout le campement est un seul « élément du niveau » : on le déplace d'un bloc dans l'éditeur (F8)
	var camp := Node3D.new()
	camp.name = "Hideout"
	add_child(camp)
	camp.global_position = base
	camp.set_meta("editobj", "hideout")
	camp.set_meta("spec", {"model": "campement de la victime", "center": false})
	B.model(camp, "sf:sleeping_bag", Vector3(0, 0.005, 0.15), 182.0, {"depth": 1.85})
	B.decal(camp, "res://assets/gen/decal_grime.png", Vector3(0, 0.05, -0.6), Vector3.UP, 1.0, 1.0, 0.3, Color(0.6, 0.5, 0.4, 0.7))
	# conserves vides, une canette
	for spec in [[Vector3(-0.3, 0, -1.05), 0.0, false], [Vector3(0.12, 0, -1.2), 40.0, true], [Vector3(-0.22, 0, 1.15), 75.0, true], [Vector3(0.15, 0, 1.2), 10.0, false]]:
		var can := B.model(camp, "can_rusted", spec[0], spec[1], {"scale": 1.6})
		if spec[2]:
			can.rotation_degrees.z = 90.0
			can.position.y += 0.06
	var beer := B.model(camp, "sf:beer_can", Vector3(-0.32, 0.035, -0.95), 130.0, {"height": 0.12})
	beer.rotation_degrees.x = 90.0
	# sa lampe torche, éteinte depuis longtemps
	var lamp := B.model(camp, "sf:flashlight_dead", Vector3(-0.3, 0.022, -0.62), 65.0, {"depth": 0.24})
	for mi in lamp.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si) as StandardMaterial3D
			if mat != null and mat.emission_enabled:
				var dead := mat.duplicate() as StandardMaterial3D
				dead.emission_enabled = false
				m.set_surface_override_material(si, dead)
	var seen := [false]
	var it := Interactable.create(camp, Vector3(0, 0.3, 0), Vector3(1.0, 0.7, 2.2), "Examiner", func() -> void:
		if seen[0]:
			Game.hud.say("Onze jours, ici. Tout seul, dans le noir.", 2.8)
			return
		seen[0] = true
		Game.glitch(0.15)
		Game.hud.say("Quelqu'un a tenu ici... Un duvet, des conserves vides.", 3.2)
		await wait(3.4)
		Game.hud.say("Onze traits sur le mur. Onze jours.", 2.8)
		await wait(3.0)
		Game.hud.say("Sa lampe est morte. Plus de piles... Et lui, il est où ?", 3.4))
	it.name = "HideoutUse"
	it.position = Vector3(0, 0.3, 0)
	# les traits gravés au mur : un élément à part, qui se colle à n'importe quel mur dans l'éditeur
	var marks := Node3D.new()
	marks.name = "HideoutMarks"
	add_child(marks)
	marks.global_transform = Transform3D(Basis.from_euler(Vector3(0, atan2(-1.0, 0.0), 0)), Vector3((HIDEOUT.x + 1) * T - 0.005, 1.05, c.z + 0.75))
	marks.set_meta("editobj", "hideout_marks")
	marks.set_meta("spec", {"model": "traits gravés au mur", "center": true})
	var dcl := B.decal(marks, "res://assets/gen/decal_tally.png", Vector3.ZERO, Vector3(0, 0, 1), 0.62, 0.31, 0.12, Color(1, 1, 1, 0.85))
	dcl.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3.ZERO)
	# surface invisible pour pouvoir viser les traits dans l'éditeur
	var pick := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.62, 0.31)
	pick.mesh = q
	var inv := StandardMaterial3D.new()
	inv.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inv.albedo_color = Color(1, 1, 1, 0)
	inv.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pick.material_override = inv
	pick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marks.add_child(pick)
	pick.position = Vector3(0, 0, 0.004)


# ================================================================== éclats de verre
## Plaques d'éclats de verre au sol : on ne peut pas marcher dessus sans bruit, même accroupi.
## (Les bouteilles lancées en laissent aussi.) Souvent, l'autre choix, c'est de patauger.
const GLASS_SPOTS := [Vector2i(4, 3), Vector2i(6, 5), Vector2i(12, 4), Vector2i(1, 9), Vector2i(15, 4), Vector2i(19, 5)]
var glass_patches: Array = []  ## [centre, rayon]


func _build_glass() -> void:
	# sur l'allée, le long du mur (les coins d'une case ne sont jamais dans la cunette)
	for t: Vector2i in GLASS_SPOTS:
		var c := tile_center(t)
		for off in [Vector3(0.86, 0, 0.86), Vector3(-0.86, 0, 0.86), Vector3(0.86, 0, -0.86), Vector3(-0.86, 0, -0.86), Vector3.ZERO]:
			var p: Vector3 = c + off
			var ok := not in_channel(p)
			for k in 8:
				var a := k * TAU / 8.0
				var q := p + Vector3(cos(a), 0, sin(a)) * 0.4
				if in_channel(q) or not walkable(tile_of(q)):
					ok = false
					break
			if ok:
				_glass_patch(p, 0.4, 70)
				break


func _glass_patch(center: Vector3, radius: float, count: int, bottle := true) -> void:
	glass_patches.append([center, radius])
	var gy := maxf(floor_y(center), WATER_Y)
	# la bouteille elle-même, cassée en deux (goulot + cul), couchée au milieu des éclats
	if bottle:
		var b := B.model(self, "sf:broken_bottle", Vector3(center.x, gy + 0.002, center.z), randf_range(0, 360), {"width": randf_range(0.28, 0.34), "center": false})
		B.set_shadows(b, false)
		# vrai verre de bouteille : vert sombre, translucide, très brillant
		var bottle_glass := StandardMaterial3D.new()
		bottle_glass.albedo_color = Color(0.07, 0.2, 0.06, 0.78)
		bottle_glass.roughness = 0.04
		bottle_glass.metallic_specular = 1.0
		bottle_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		bottle_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
		bottle_glass.rim_enabled = true
		bottle_glass.rim = 0.25
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = bottle_glass
	# menus éclats du même verre vert (et un peu de verre clair), pas plus gros qu'un ongle
	var specs := [[Color(0.12, 0.3, 0.1, 0.65)], [Color(0.85, 0.9, 0.88, 0.3)]]
	var tools: Array[SurfaceTool] = []
	var mats: Array[StandardMaterial3D] = []
	for sp in specs:
		var m := StandardMaterial3D.new()
		m.albedo_color = sp[0]
		m.roughness = 0.04
		m.metallic_specular = 1.0
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mats.append(m)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
	for k in count:
		var r := radius * pow(randf(), 1.3)
		var a := randf() * TAU
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = maxf(floor_y(p), WATER_Y) + 0.0015
		var size := randf_range(0.003, 0.009) if randf() < 0.85 else randf_range(0.01, 0.018)
		var st2: SurfaceTool = tools[1] if k % 5 == 0 else tools[0]
		var a0 := randf() * TAU
		var tilt := Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3)).normalized()
		st2.set_normal(tilt)
		for v in 3:
			var av := a0 + v * TAU / 3.0 + randf_range(-0.6, 0.6)
			var rv := size * randf_range(0.4, 1.0)
			var off := Vector3(cos(av) * rv, 0, sin(av) * rv)
			off.y = -(tilt.x * off.x + tilt.z * off.z) / tilt.y
			st2.add_vertex(p + off)
	for i2 in tools.size():
		var mi := MeshInstance3D.new()
		mi.mesh = tools[i2].commit()
		mi.material_override = mats[i2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _on_glass(p: Vector3) -> bool:
	for g in glass_patches:
		var c: Vector3 = g[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(g[1]) + 0.15:
			return true
	return false


# ================================================================== traces mouillées de la créature
## Elle sort de l'eau : ses mains et ses pieds laissent des empreintes humides sur les allées,
## qui sèchent en une minute ou deux. On lit son chemin... et on sait qu'elle est passée il y a peu.
var _prints: Array = []  ## [décal, âge]
var _print_from := Vector3.INF
var _print_side := 1.0


func _creature_tracks(delta: float) -> void:
	for i in range(_prints.size() - 1, -1, -1):
		var e: Array = _prints[i]
		e[1] = float(e[1]) + delta
		var dcl := e[0] as Decal
		if float(e[1]) > 110.0 or not is_instance_valid(dcl):
			if is_instance_valid(dcl):
				dcl.queue_free()
			_prints.remove_at(i)
			continue
		dcl.modulate.a = (1.0 - smoothstep(45.0, 110.0, float(e[1]))) * 0.95
	if creature == null or not creature.visible or creature.state in [Creature.State.DORMANT, Creature.State.STAND]:
		_print_from = Vector3.INF
		return
	var p := creature.global_position
	if _print_from == Vector3.INF:
		_print_from = p
		return
	if Vector2(p.x - _print_from.x, p.z - _print_from.z).length() < 0.8:
		return
	_print_from = p
	_print_side = -_print_side
	var fwd := Vector3(-sin(creature.heading), 0, -cos(creature.heading))
	var side := Vector3(-fwd.z, 0, fwd.x)
	var at := p + side * 0.22 * _print_side
	if get_surface(at) == "water" or in_channel(at):
		return
	var d := Decal.new()
	d.texture_albedo = B.tex("res://assets/gen/decal_wet_print.png")
	d.texture_orm = B.tex("res://assets/gen/decal_wet_print_orm.png")
	var ln := randf_range(0.34, 0.44)
	d.size = Vector3(ln * randf_range(0.45, 0.6), 0.4, ln)
	d.modulate = Color(1, 1, 1, 0.95)
	d.normal_fade = 0.3
	d.cull_mask = 1
	add_child(d)
	d.global_transform = Transform3D(Basis(Vector3.UP, creature.heading + randf_range(-0.3, 0.3)), Vector3(at.x, floor_y(at) + 0.1, at.z))
	_prints.append([d, 0.0])
	if _prints.size() > 70:
		var old: Array = _prints.pop_front()
		if is_instance_valid(old[0]):
			(old[0] as Decal).queue_free()


# ================================================================== acoustique
## Chaque partie du réseau sonne différemment, et la créature s'entend étouffée derrière un mur
## (nette quand elle est en vue) : on peut la situer à l'oreille. La vapeur qui siffle la couvre.
var _rev := [0.85, 0.32, 0.35, 30.0, 0.0]
var _occl_cut := 20000.0
var _occl_db := 0.0
var _in_hall := false
var _fog_cd := 0.0
var _splash_cd := 0.0


func _zone_audio(delta: float) -> void:
	var t := tile_of(player.global_position)
	var target: Array
	if cell(t) == "w" or is_hall(t):
		target = [0.98, 0.5, 0.22, 120.0, 0.0]  # citerne : immense, comme une cathédrale
	elif zone_of(t) == 0:
		target = [0.84, 0.38, 0.45, 60.0, 0.0]  # voûtes de briques : long écho
	elif zone_of(t) == 1:
		target = [0.72, 0.3, 0.4, 35.0, 0.0]
	else:
		target = [0.3, 0.22, 0.06, 10.0, 0.35]  # galeries techniques carrelées : sec, métallique
	var k := 1.0 - exp(-1.5 * delta)
	for i in 5:
		_rev[i] = lerpf(_rev[i], float(target[i]), k)
	Sound.set_reverb(_rev[0], _rev[1], _rev[2], _rev[3], _rev[4])
	# la créature : étouffée derrière les murs, couverte par la vapeur
	if creature != null and creature.visible:
		var ears := player.eye_position()
		var mouth := creature.head_position()
		var cut := 20000.0
		var db := 0.0
		if not has_los(ears, mouth):
			cut = clampf(2400.0 - ears.distance_to(mouth) * 80.0, 650.0, 2400.0)
			db = -5.0
		var ds := _steam_dist(player.global_position)
		if ds < 6.5:
			var m := 1.0 - ds / 6.5
			db -= 10.0 * m
			cut = minf(cut, lerpf(20000.0, 1500.0, m))
		_occl_cut = lerpf(_occl_cut, cut, 1.0 - exp(-6.0 * delta))
		_occl_db = lerpf(_occl_db, db, 1.0 - exp(-6.0 * delta))
		Sound.set_creature_filter(_occl_cut, _occl_db)
	# buée sur l'objectif en entrant dans la citerne (air chaud et humide)
	_fog_cd -= delta
	var in_hall := cell(t) == "w" or is_hall(t)
	if in_hall and not _in_hall and _fog_cd <= 0.0:
		_fog_cd = 80.0
		Game.lens_fog(0.8)
	_in_hall = in_hall
	_splash_cd -= delta


## Sans ombre, la lumière d'une lampe traverse les murs et se reflète sur le sol mouillé de l'allée
## d'à côté. Les 9 luminaires les plus proches de Théo projettent donc des ombres (assez pour que rien
## ne « fuie » autour de lui, sans payer les ombres de toutes les lampes du réseau).
func _lamp_shadows(delta: float) -> void:
	_shadow_cd -= delta
	if _shadow_cd > 0.0 or _lamp_lights.is_empty():
		return
	_shadow_cd = 0.4
	var here := player.global_position
	var lights := _lamp_lights.duplicate()
	lights.sort_custom(func(a: Light3D, b: Light3D) -> bool: return a.global_position.distance_squared_to(here) < b.global_position.distance_squared_to(here))
	for i in lights.size():
		var l := lights[i] as Light3D
		if is_instance_valid(l):
			l.shadow_enabled = i < 9


## Un pas de Théo : en courant dans l'eau, ça éclabousse parfois jusqu'à l'objectif.
func on_footstep(surface: String) -> void:
	if surface == "water":
		splash(player.global_position, 1.5 if player.running else (0.6 if player.crouching else 1.0))
	if surface == "water" and player.running and _splash_cd <= 0.0 and randf() < 0.3:
		_splash_cd = 6.0
		Game.lens_splash(randf_range(0.6, 1.0))


# ================================================================== eau vivante
## L'eau réagit : un rond s'élargit à chaque pas (Théo, la créature), sous chaque goutte qui tombe de la
## voûte, là où une bouteille tombe ; des débris (feuilles, mousse, plastique) dérivent vers la citerne ;
## une brume basse traîne au ras de la citerne.
var _water_mat: ShaderMaterial
var _rings: Array = []  ## [x, z, instant, force]
var _ring_i := 0
var _flow := {}  ## case → case suivante vers la citerne (Vector2i(-1, -1) : grille d'évacuation)
var _sink_dir := {}  ## case qui se jette dans la salle de la citerne → direction de la grille
var _debris: Array = []  ## [nœud, vitesse, décalage latéral, rotation, phase, âge]
var _debris_mats: Array[StandardMaterial3D] = []
var _mist: FogVolume
const DEBRIS_N := 34


func _is_water(pos: Vector3) -> bool:
	return cell(tile_of(pos)) == "w" or in_channel(pos)


## Quelque chose touche l'eau en `pos` : un rond s'élargit à la surface.
func splash(pos: Vector3, strength := 1.0) -> void:
	if _water_mat == null or not _is_water(pos):
		return
	var r := [pos.x, pos.z, _time, strength]
	if _rings.size() < 24:
		_rings.append(r)
	else:
		_rings[_ring_i] = r
		_ring_i = (_ring_i + 1) % 24


func _update_rings() -> void:
	if _water_mat == null:
		return
	var arr: Array[Vector4] = []
	for i in 24:
		if i < _rings.size() and _time - float(_rings[i][2]) < 2.3:
			var r: Array = _rings[i]
			arr.append(Vector4(r[0], r[1], r[2], r[3]))
		else:
			arr.append(Vector4.ZERO)
	_water_mat.set_shader_parameter("rings", arr)
	_water_mat.set_shader_parameter("ring_now", _time)


## Une goutte se détache de la voûte et tombe dans l'eau (on la voit passer dans le faisceau).
func _falling_drop(p: Vector3) -> void:
	var top := h_top(tile_of(p)) - 0.05
	var drop := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.005, 0.03)
	drop.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.9, 0.9, 0.7)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.roughness = 0.1
	drop.material_override = m
	drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drop)
	drop.global_position = Vector3(p.x, top, p.z)
	var fall := sqrt(2.0 * maxf(top - WATER_Y, 0.2) / 9.8)
	var tw := create_tween()
	tw.tween_property(drop, "global_position:y", WATER_Y, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		splash(Vector3(p.x, 0, p.z), 0.55)
		Sound.play_at(Sound.variant("drip", 3), Vector3(p.x, WATER_Y, p.z), randf_range(-12.0, -4.0), randf_range(0.85, 1.25), 2.5, 20.0)
		drop.queue_free())


## Sens du courant : les cunettes se jettent dans la salle de la citerne (par les grilles au bout).
func _build_flow() -> void:
	var dist := {}
	var queue: Array[Vector2i] = []
	for z in H:
		for x in W:
			var t := Vector2i(x, z)
			if not has_channel(t):
				continue
			for d: Vector2i in DIRS:
				if is_hall(t + d) or cell(t + d) == "w":
					dist[t] = 0
					_flow[t] = Vector2i(-1, -1)
					_sink_dir[t] = Vector3(d.x, 0, d.y)
					queue.append(t)
					break
	while not queue.is_empty():
		var t: Vector2i = queue.pop_front()
		for d: Vector2i in DIRS:
			var n := t + d
			if dist.has(n) or not has_channel(n) or not _link(t, d):
				continue
			dist[n] = int(dist[t]) + 1
			_flow[n] = t
			queue.append(n)


func _build_debris() -> void:
	_build_flow()
	var tex: Texture2D = load("res://assets/gen/water_debris.png")
	for k in 4:
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.uv1_scale = Vector3(0.25, 1, 1)
		m.uv1_offset = Vector3(0.25 * k, 0, 0)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if k in [1, 3] else BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.35
		_debris_mats.append(m)
	for i in DEBRIS_N:
		var n := MeshInstance3D.new()
		var q := QuadMesh.new()
		n.mesh = q
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
		_debris.append([n, 0.0, 0.0, 0.0, randf() * TAU, 0.0])
		_respawn_debris(_debris[i], true)
	# brume au ras de l'eau de la citerne : plus dense en bas, en volutes, elle dérive lentement
	_mist = FogVolume.new()
	_mist.name = "CisternMist"
	_mist.size = Vector3(5 * T, 0.9, 3 * T)
	var fm := FogMaterial.new()
	fm.density = 0.7
	fm.albedo = Color(0.7, 0.74, 0.7)
	fm.height_falloff = 2.5
	fm.edge_fade = 0.5
	var nt := NoiseTexture3D.new()
	nt.width = 64
	nt.height = 16
	nt.depth = 64
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.06
	nt.noise = fn
	fm.density_texture = nt
	_mist.material = fm
	add_child(_mist)
	_mist.position = Vector3(9.5 * T, WATER_Y + 0.4, 8.5 * T)


func _respawn_debris(e: Array, anywhere := false) -> void:
	var n := e[0] as MeshInstance3D
	var keys := _flow.keys()
	if keys.is_empty():
		n.visible = false
		return
	var here := player.global_position if player != null else Vector3(10, 0, 10)
	var t: Vector2i = keys[randi() % keys.size()]
	for _k in 30:
		var cand: Vector2i = keys[randi() % keys.size()]
		var dd := tile_center(cand).distance_to(here)
		if anywhere or (dd > 4.0 and dd < 13.0):
			t = cand
			break
	var kind := randi() % 100
	var k := 0 if kind < 35 else (1 if kind < 70 else (2 if kind < 85 else 3))
	var sizes := [0.055, 0.13, 0.09, 0.16]
	(n.mesh as QuadMesh).size = Vector2.ONE * float(sizes[k]) * randf_range(0.8, 1.25)
	n.material_override = _debris_mats[k]
	n.visible = true
	e[1] = randf_range(0.06, 0.16)
	e[2] = randf_range(-0.2, 0.2)
	e[3] = randf_range(-0.4, 0.4)
	e[5] = 0.0
	var c := tile_center(t)
	n.global_transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, randf() * TAU, 0)), Vector3(c.x + randf_range(-0.15, 0.15), WATER_Y + 0.004, c.z + randf_range(-0.15, 0.15)))


func _update_debris(delta: float) -> void:
	if player == null:
		return
	var here := player.global_position
	for e in _debris:
		var n := e[0] as MeshInstance3D
		if not n.visible:
			continue
		e[5] = float(e[5]) + delta
		var p := n.global_position
		var t := tile_of(p)
		if not _flow.has(t) or p.distance_to(here) > 16.0 or float(e[5]) > 90.0:
			_respawn_debris(e)
			continue
		var nxt: Vector2i = _flow[t]
		var target: Vector3
		if nxt == Vector2i(-1, -1):
			# bout de cunette : le débris file vers la grille et disparaît dessous
			target = tile_center(t) + (_sink_dir[t] as Vector3) * (T * 0.5)
			if Vector2(p.x - target.x, p.z - target.z).length() < 0.25:
				_respawn_debris(e)
				continue
		else:
			target = tile_center(nxt)
			var along := (target - tile_center(t)).normalized()
			target += Vector3(-along.z, 0, along.x) * float(e[2])
		var dir := Vector3(target.x - p.x, 0, target.z - p.z)
		if dir.length() > 0.001:
			p += dir.normalized() * float(e[1]) * delta
		n.global_position = Vector3(p.x, WATER_Y + 0.004 + sin(_time * 1.3 + float(e[4])) * 0.002, p.z)
		n.rotate_y(float(e[3]) * delta)
	if _mist != null:
		_mist.position.x = 9.5 * T + sin(_time * 0.05) * 0.8
		_mist.position.z = 8.5 * T + cos(_time * 0.037) * 0.5


# ================================================================== cafards
## Des cafards sur les murs et au sol : quand le faisceau les attrape, ils détalent dans tous les sens
## et disparaissent dans les fissures.
var _roaches: Array = []
var _roach_cd := 2.0
var _skitter_cd := 0.0


func _update_roaches(delta: float) -> void:
	_skitter_cd -= delta
	_roach_cd -= delta
	for i in range(_roaches.size() - 1, -1, -1):
		var r = _roaches[i]
		if not is_instance_valid(r):
			_roaches.remove_at(i)
		elif (r as Node3D).global_position.distance_to(player.global_position) > 15.0:
			(r as Node3D).queue_free()
			_roaches.remove_at(i)
	if _roach_cd > 0.0 or _roaches.size() > 75:
		return
	_roach_cd = randf_range(0.8, 1.8)
	# un groupe à quelques mètres, jamais en plein dans le faisceau
	for _try in 20:
		var c := tile_of(player.global_position) + Vector2i(randi_range(-5, 5), randi_range(-5, 5))
		if not walkable(c) or cell(c) in ["w", "G", "E"]:
			continue
		var walls := _wall_tiles(c)
		if walls.is_empty():
			continue
		var d: Vector2i = walls[randi() % walls.size()]
		var nrm := Vector3(-d.x, 0, -d.y)
		var tan := Vector3(-d.y, 0, d.x)
		var on_wall := randf() < 0.3
		var base := wall_pos(c, d, 0.0, randf_range(-0.9, 0.9))
		if on_wall:
			base += Vector3(0, randf_range(0.3, 1.3), 0) + nrm * 0.012
		else:
			# au sol : n'importe où sur l'allée (pas seulement au pied du mur)
			base += nrm * randf_range(0.3, 1.1)
			base.y = floor_y(base) + 0.004
			if _is_water(base) or not walkable(tile_of(base)):
				continue
		var dist := base.distance_to(player.global_position)
		if dist < 3.5 or dist > 14.0:
			continue
		if player.flashlight_on:
			var to := (base - player.flashlight.global_position).normalized()
			if (-player.flashlight.global_basis.z).dot(to) > 0.85:
				continue
		var v_axis := Vector3.UP if on_wall else nrm
		for k in (1 if randf() < 0.25 else randi_range(2, 8)):
			# l'emplacement est vérifié AVANT de créer le cafard (jamais dans l'eau ni hors de l'allée)
			var off := Vector2(randf_range(-0.35, 0.35), randf_range(-0.25, 0.25))
			var at := base + tan * off.x + v_axis * off.y
			if on_wall:
				at.y = clampf(at.y, 0.22, 1.5)
			elif _is_water(at) or not walkable(tile_of(at)):
				continue
			var r := Roach.new()
			r.level = self
			r.on_wall = on_wall
			r.normal = nrm if on_wall else Vector3.UP
			r.u_axis = tan
			r.v_axis = v_axis
			r.home = base
			add_child(r)
			r.global_position = at
			_roaches.append(r)
		break


func _event_test(kind: String) -> void:
	await wait(1.5)
	match kind:
		"bang":
			_ev_pipe_bang()
		"debris":
			_ev_debris()
		"debrisnear":
			_ev_debris(true)
		"lamp":
			_ev_lamp_pop()
		"grate":
			_ev_grate()
		"rats":
			_ev_rats()


func _splash_test() -> void:
	await wait(1.0)
	for k in 12:
		var f := -player.cam.global_basis.z
		f.y = 0.0
		splash(player.global_position + f.normalized() * randf_range(1.2, 2.6) + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)), 1.2)
		await wait(0.35)


func _roach_test() -> void:
	await wait(0.8)
	var base := player.global_position + Vector3(0, 0.6, 0) - player.cam.global_basis.z * 2.0
	var right := player.cam.global_basis.x
	for k in 6:
		var r := Roach.new()
		r.level = self
		r.on_wall = false
		r.normal = Vector3.UP
		r.u_axis = Vector3.RIGHT
		r.v_axis = Vector3.BACK
		var at := player.global_position - player.cam.global_basis.z * 1.6 + right * (1.3 + randf_range(-0.25, 0.25)) + Vector3(0, 0, randf_range(-0.25, 0.25))
		at.y = floor_y(at) + 0.004
		r.home = at
		add_child(r)
		r.global_position = at
		_roaches.append(r)
	await wait(2.2)
	# Théo tourne la tête vers eux : le faisceau les attrape
	var to := (player.global_position + right * 1.3 - player.cam.global_basis.z * 1.6) - player.global_position
	player.set_look(atan2(-to.x, -to.z), deg_to_rad(-38.0))


func roach_skitter(pos: Vector3) -> void:
	if _skitter_cd > 0.0:
		return
	_skitter_cd = 0.6
	Sound.play_at(Sound.variant("roach_skitter", 3), pos, -14.0, randf_range(0.9, 1.15), 1.0, 7.0)


class Roach extends Node3D:
	var level: Node
	var on_wall := false
	var normal := Vector3.UP
	var u_axis := Vector3.RIGHT  ## axes du plan où il marche (mur : horizontal / vertical ; sol : deux axes au sol)
	var v_axis := Vector3.FORWARD
	var home := Vector3.ZERO
	var anim: AnimationPlayer
	var model: Node3D
	var fleeing := false
	var flee_t := 0.0
	var dir := Vector2.ZERO
	var speed := 0.0
	var pause_t := 0.0
	var walk_name := ""
	var idle_name := ""

	func _ready() -> void:
		var ps: PackedScene = load("res://assets/sketchfab/cockroach/cockroach.glb")
		model = ps.instantiate() as Node3D
		add_child(model)
		# le modèle est un cafard « géant » : 2,2 m de long (antennes comprises) → 3 cm
		model.scale = Vector3.ONE * (randf_range(0.026, 0.036) / 2.2)
		var aps := model.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			anim = aps[0] as AnimationPlayer
			for a in anim.get_animation_list():
				if a.ends_with("walking"):
					walk_name = a
				elif a.ends_with("idle"):
					idle_name = a
			if idle_name != "":
				anim.play(idle_name)
				anim.seek(randf() * 1.2, true)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# brun très foncé et luisant (la texture d'origine tire sur l'orange)
			for si in m3.mesh.get_surface_count():
				var mat := m3.get_active_material(si) as StandardMaterial3D
				if mat != null:
					var dm := mat.duplicate() as StandardMaterial3D
					dm.albedo_color = dm.albedo_color * Color(0.45, 0.36, 0.3)
					dm.roughness = 0.35
					m3.set_surface_override_material(si, dm)
		dir = Vector2.from_angle(randf() * TAU)
		pause_t = randf_range(0.5, 3.0)
		_orient()

	func _process(delta: float) -> void:
		var p = level.player
		if p == null:
			return
		# loin de Théo (on ne les distinguerait pas) : figés, sans animation, ça ne coûte presque rien
		var far: bool = not fleeing and global_position.distance_squared_to(p.global_position) > 64.0
		if anim != null:
			if far and anim.is_playing():
				anim.pause()
			elif not far and not anim.is_playing():
				anim.play()
		if far:
			return
		if not fleeing and p.flashlight_on and p.flashlight.light_energy > 0.6:
			var to: Vector3 = global_position - p.flashlight.global_position
			var dd := to.length()
			if dd < 7.0 and (-p.flashlight.global_basis.z).dot(to / dd) > 0.91:
				_flee(p)
		if fleeing:
			flee_t -= delta
			if flee_t <= 0.0:
				queue_free()
				return
		else:
			# petits déplacements nerveux, puis immobile
			pause_t -= delta
			if pause_t <= 0.0:
				if speed > 0.0:
					speed = 0.0
					pause_t = randf_range(1.0, 4.0)
				else:
					speed = randf_range(0.03, 0.09)
					pause_t = randf_range(0.3, 1.2)
					dir = dir.rotated(randf_range(-1.6, 1.6))
		if speed > 0.0:
			var step := (u_axis * dir.x + v_axis * dir.y) * speed * delta
			var np := global_position + step
			# rester sur sa surface : sur le mur entre 0,2 et 1,5 m, près de son coin ; au sol, hors de l'eau
			var off := np - home
			var bad := absf(off.dot(u_axis)) > 1.2
			if on_wall:
				bad = bad or np.y < 0.2 or np.y > 1.55
			else:
				bad = bad or absf(off.dot(v_axis)) > 0.7 or level._is_water(np)
			if bad:
				dir = -dir.rotated(randf_range(-0.7, 0.7))
			else:
				global_position = np
			if anim != null and walk_name != "":
				anim.play(walk_name, 0.1, clampf(speed / 0.08, 0.8, 4.0))
			_orient()
		elif anim != null and idle_name != "":
			anim.play(idle_name, 0.2)

	func _flee(p) -> void:
		fleeing = true
		flee_t = randf_range(0.9, 2.0)
		speed = randf_range(0.3, 0.55)
		pause_t = 99.0
		# ils fuient le centre du faisceau, chacun un peu de son côté
		var o: Vector3 = p.flashlight.global_position
		var bd: Vector3 = -p.flashlight.global_basis.z
		var center := o + bd * (global_position - o).dot(bd)
		var away := global_position - center
		var d2 := Vector2(away.dot(u_axis), away.dot(v_axis))
		if d2.length() < 0.01:
			d2 = Vector2.from_angle(randf() * TAU)
		dir = d2.normalized().rotated(randf_range(-0.6, 0.6))
		level.roach_skitter(global_position)

	func _orient() -> void:
		var fwd := (u_axis * dir.x + v_axis * dir.y).normalized()
		if fwd.length() < 0.5:
			return
		# la tête du modèle est vers -Z
		var y := normal
		var x := y.cross(-fwd).normalized()
		var z := x.cross(y).normalized()
		global_basis = Basis(x, y, z)


# ================================================================== événements au hasard
## Les égouts vivent : de temps en temps un coup de bélier fait sonner les canalisations, des gravats
## tombent de la voûte, une lampe claque et s'éteint pour de bon, une grille grince toute seule, une
## ruée de rats fuit quelque chose. Les plus bruyants attirent la créature.
var _event_cd := 50.0
var _dead_lamps := 0


func _update_events(delta: float) -> void:
	if dying or escaping or not cell_open:
		return
	_event_cd -= delta
	if _event_cd > 0.0:
		return
	_event_cd = randf_range(25.0, 55.0)
	var roll := randf()
	if roll < 0.27:
		_ev_pipe_bang()
	elif roll < 0.5:
		_ev_debris()
	elif roll < 0.65 and _dead_lamps < 3:
		_ev_lamp_pop()
	elif roll < 0.83:
		_ev_grate()
	else:
		_ev_rats()


## Une case avec un mur, à bonne distance de Théo : [case, direction du mur] (ou [] si rien trouvé).
func _event_spot(min_d: float, max_d: float) -> Array:
	for _try in 40:
		var t := tile_of(player.global_position) + Vector2i(randi_range(-5, 5), randi_range(-5, 5))
		if not walkable(t) or cell(t) in ["w", "G", "E"]:
			continue
		var dd := tile_center(t).distance_to(player.global_position)
		if dd < min_d or dd > max_d:
			continue
		var walls := _wall_tiles(t)
		if walls.is_empty():
			continue
		return [t, walls[randi() % walls.size()]]
	return []


func _pipe_height(t: Vector2i) -> float:
	return [1.38, 1.62, 2.22][zone_of(t)]


## Coup de bélier : un gros BANG métallique, puis l'onde qui court le long de la canalisation.
func _ev_pipe_bang() -> void:
	var sp := _event_spot(5.0, 14.0)
	if sp.is_empty():
		return
	var t: Vector2i = sp[0]
	var d: Vector2i = sp[1]
	var tan := Vector3(-d.y, 0, d.x)
	var pos := wall_pos(t, d, PIPE_INSET) + Vector3(0, _pipe_height(t), 0)
	Sound.play_at(Sound.variant("pipe_bang", 4), pos, 5.0, randf_range(0.8, 1.0), 8.0, 70.0)
	if pos.distance_to(player.global_position) < 9.0:
		Game.shake(0.15)
	_dust_puff(Vector3(pos.x, h_top(t) - 0.1, pos.z))
	lure_noise(pos, 16.0)
	for k in randi_range(1, 3):
		await wait(randf_range(0.25, 0.6))
		var p2 := pos + tan * randf_range(-4.0, 4.0)
		Sound.play_at(Sound.variant("pipe_bang", 4), p2, -4.0 - k * 3.0, randf_range(1.0, 1.25), 6.0, 50.0)


## Des gravats se détachent de la voûte : quelques morceaux de béton tombent (on les voit), un nuage de
## poussière, et ils restent là.
func _ev_debris(near := false) -> void:
	var at := Vector3.INF
	var fwd := -player.cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if near:
		at = player.global_position + fwd * 1.6  # (test : juste devant la caméra)
	for _try in (0 if near else 30):
		var cand := player.global_position + fwd.rotated(Vector3.UP, randf_range(-0.9, 0.9)) * randf_range(3.5, 9.0)
		if walkable(tile_of(cand)) and has_los(player.eye_position(), cand + Vector3(0, 0.3, 0)):
			at = cand
			break
	if at == Vector3.INF:
		return
	var top := h_top(tile_of(at)) - 0.05
	_dust_puff(Vector3(at.x, top, at.z))
	_dust_trickle(Vector3(at.x, top, at.z))
	Sound.play_at(Sound.variant("rubble", 3), at + Vector3(0, 1.0, 0), 2.0, randf_range(0.9, 1.1), 6.0, 45.0)
	# ce qui se détache de la voûte au-dessus : briques et mortier dans le vieux réseau, béton ailleurs
	var kinds: Array = ["brick", "brick", "mortar"] if zone_of(tile_of(at)) == 0 else ["concrete", "concrete", "dirty"]
	for k in randi_range(4, 7):
		var s := randf_range(0.045, 0.12)
		var sz := Vector3(s * randf_range(0.8, 1.3), s * randf_range(0.45, 0.75), s * randf_range(0.8, 1.2))
		_drop_rubble(at, top, sz, _rubble_mat(kinds[randi() % kinds.size()]), randf_range(0.0, 0.35), 5)
	# et une poignée de gravillons
	for k in randi_range(10, 18):
		var s2 := randf_range(0.012, 0.03)
		_drop_rubble(at, top, Vector3(s2, s2 * 0.7, s2), _rubble_mat(kinds[randi() % kinds.size()]), randf_range(0.05, 0.6), 4)
	await wait(0.8)
	_dust_puff(Vector3(at.x, 0.15, at.z))
	lure_noise(at, 12.0)


## Un morceau tombe en tournant, rebondit un peu et se couche sur sa plus grande face, posé pile sur le sol
## (ou au fond de la cunette). Les gravillons disparaissent quand Théo est passé depuis longtemps.
func _drop_rubble(at: Vector3, top: float, sz: Vector3, mat: Material, delay: float, seg: int) -> void:
	var p0 := at + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	var chunk := _rock_chunk(sz, mat, seg)
	chunk.position = Vector3(p0.x, top, p0.z)
	chunk.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	var rest := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, randf_range(-0.15, 0.15))
	var lift := -(Transform3D(rest, Vector3.ZERO) * chunk.mesh.get_aabb()).position.y
	var land_y := floor_y(p0) + lift
	var hop := Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)) * clampf(sz.x, 0.02, 0.1)
	if absf(floor_y(p0 + hop) - floor_y(p0)) > 0.03:
		hop = Vector3.ZERO  # pas de rebond par-dessus le bord de la cunette
	var fall := sqrt(2.0 * maxf(top - land_y, 0.3) / 9.8)
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(chunk, "position:y", land_y, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(chunk, "rotation", chunk.rotation + Vector3(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0), randf_range(-4.0, 4.0)), fall)
	tw.tween_callback(func() -> void: splash(Vector3(p0.x, 0, p0.z), 0.9 if sz.x > 0.04 else 0.35))
	tw.tween_property(chunk, "position", Vector3(p0.x + hop.x * 0.5, land_y + sz.y * 0.5, p0.z + hop.z * 0.5), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(chunk, "quaternion", rest.get_rotation_quaternion(), 0.2)
	tw.tween_property(chunk, "position", Vector3(p0.x + hop.x, land_y, p0.z + hop.z), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if sz.x < 0.04:
		get_tree().create_timer(120.0, false).timeout.connect(func() -> void: if is_instance_valid(chunk): chunk.queue_free())


## Matière des gravats : texture de béton dans le repère du morceau (elle ne glisse pas pendant la chute),
## mate et sèche — aucun reflet (la carte de rugosité du béton les faisait luire).
func _rubble_mat(kind: String) -> StandardMaterial3D:
	if _rubble_mats.has(kind):
		return _rubble_mats[kind]
	var spec: Array = {"brick": ["dirty_concrete", Color(0.34, 0.22, 0.16)], "mortar": ["hacked_concrete", Color(0.36, 0.35, 0.32)],
		"concrete": ["hacked_concrete", Color(0.34, 0.335, 0.31)], "dirty": ["cracked_concrete", Color(0.25, 0.245, 0.22)]}[kind]
	var src := B.mat(spec[0], 1.0)
	var m := StandardMaterial3D.new()
	m.albedo_texture = src.albedo_texture
	m.albedo_color = spec[1]
	if src.normal_texture != null:
		m.normal_enabled = true
		m.normal_texture = src.normal_texture
		m.normal_scale = 0.6
	m.roughness = 1.0
	m.metallic_specular = 0.15
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 3.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_rubble_mats[kind] = m
	return m


## Filet de poussière qui tombe de la voûte d'où les morceaux se sont détachés.
func _dust_trickle(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.1
	p.visibility_aabb = AABB(Vector3(-1, -3.5, -1), Vector3(2, 4, 2))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.1
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, -3.0, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.0
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color(1, 1, 1, 0.6))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.04, 0.04)
	q.material = _soft_dot_mat(Color(0.5, 0.48, 0.44, 0.22))
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.4).timeout.connect(func() -> void: if is_instance_valid(p): p.emitting = false)
	get_tree().create_timer(3.0).timeout.connect(func() -> void: if is_instance_valid(p): p.queue_free())


## Tache ronde et floue (poussière) pour les particules.
func _soft_dot_mat(col: Color) -> StandardMaterial3D:
	var puff := Gradient.new()
	puff.set_color(0, Color(1, 1, 1, 1))
	puff.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = puff
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


## Morceau de béton ou de brique cassé : une sphère grossière déformée au hasard, à facettes nettes
## (cassure franche, pas un galet lisse ni un cube).
func _rock_chunk(size: Vector3, mat: Material, seg := 5) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = seg
	sm.rings = maxi(2, seg - 2)
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	# même écrasement pour les sommets confondus (sinon le bloc se fendrait aux coutures)
	var disp := {}
	for i in verts.size():
		var key := Vector3i((verts[i] * 1000.0).round())
		if not disp.has(key):
			disp[key] = randf_range(0.65, 1.25)
		verts[i] = verts[i] * float(disp[key]) * size
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for t in idx:
		st.add_vertex(verts[t])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Une lampe grésille, claque (verre qui éclate, étincelles) et ne se rallumera plus.
func _ev_lamp_pop() -> void:
	var cands: Array = []
	for l in _lamp_lights:
		if not is_instance_valid(l) or not l.visible or l.light_energy < 0.1:
			continue
		if l.light_color.g < 0.2:
			continue  # le feu rouge de l'écluse reste allumé
		var lp := l.get_parent() as Node
		if lp != null and str(lp.get_meta("editobj", "")) == "lamp_gate":
			continue
		var dd := l.global_position.distance_to(player.global_position)
		if dd > 4.0 and dd < 16.0:
			cands.append(l)
	if cands.is_empty():
		return
	var l := cands[randi() % cands.size()] as Light3D
	_dead_lamps += 1
	flicker_lights.erase(l)
	_lamp_lights.erase(l)
	var e := l.light_energy
	var t := 0.0
	while t < 0.9:
		await ticked
		t += get_process_delta_time()
		_lamp_level(l, e, 0.0 if randf() < 0.5 else randf_range(0.4, 1.6))
	await _lamp_burst(l, e)
	lure_noise(l.global_position, 10.0)
	if randf() < 0.5:
		await wait(0.8)
		Game.hud.say(["...Génial.", "Non, non, non... pas maintenant.", "Encore une de moins."][randi() % 3], 2.2)


## Intensité d'un luminaire (et de son tube / ampoule) : k = 1 normal, 0 éteint.
func _lamp_level(l: Light3D, e: float, k: float) -> void:
	l.light_energy = e * k
	if l.has_meta("glow"):
		var g := l.get_meta("glow") as StandardMaterial3D
		if not g.has_meta("base"):
			g.set_meta("base", g.emission_energy_multiplier)
		g.emission_energy_multiplier = float(g.get_meta("base")) * clampf(k, 0.02, 1.5)


## L'ampoule claque : verre qui éclate, étincelles, un dernier éclair, puis plus rien.
func _lamp_burst(l: Light3D, e: float) -> void:
	Sound.play_at("lamp_break_0", l.global_position, 0.0, randf_range(0.9, 1.1), 4.0, 35.0)
	_sparks(l.global_position)
	l.light_energy = e * 3.0
	await wait(0.06)
	_lamp_off(l)


## Luminaire mort : lumière, tube / ampoule et grésillement coupés, plus d'ombre ni d'événement dessus.
func _lamp_off(l: Light3D) -> void:
	flicker_lights.erase(l)
	_lamp_lights.erase(l)
	l.visible = false
	if l.has_meta("glow"):
		(l.get_meta("glow") as StandardMaterial3D).emission_energy_multiplier = 0.0
	else:
		var fix: Node3D = l.get_meta("fixture") if l.has_meta("fixture") else (l.get_parent() as Node3D if l.get_parent() != self else null)
		if fix != null:
			var g := _own_emissive(fix)
			if g != null:
				g.emission_energy_multiplier = 0.0
	if l.has_meta("buzz") and is_instance_valid(l.get_meta("buzz")):
		Sound.fade(l.get_meta("buzz"), -60.0, 0.1, true)


## La baladeuse du couloir, juste avant la première apparition : elle grésille, a des ratés, se coupe,
## se rallume... puis claque au moment où Théo arrive dessous. Le couloir est noir pour la suite.
func _corridor_lamp_fails() -> void:
	var l := _corridor_lamp
	if l == null or not is_instance_valid(l) or not l.visible:
		return
	_lamp_lights.erase(l)
	flicker_lights.erase(l)
	var e := l.light_energy
	var buzz: Node = l.get_meta("buzz") if l.has_meta("buzz") else null
	if is_instance_valid(buzz):
		Sound.fade(buzz, -9.0, 0.6)
	# premiers ratés
	var t := 0.0
	while t < 1.4:
		await ticked
		t += get_process_delta_time()
		_lamp_level(l, e, 0.12 if randf() < 0.22 else randf_range(0.75, 1.1))
	# elle se coupe presque... et se rallume
	_lamp_level(l, e, 0.04)
	await wait(0.55)
	_lamp_level(l, e, 1.0)
	await wait(0.6)
	# stroboscope qui s'emballe, puis elle claque
	t = 0.0
	while t < 0.7:
		await ticked
		t += get_process_delta_time()
		_lamp_level(l, e, 0.0 if randf() < 0.5 else randf_range(0.5, 1.8))
	await _lamp_burst(l, e)
	Game.shake(0.3)
	await wait(1.1)
	Game.hud.say("...Merde.", 1.6)


## Une grille d'arrivée d'eau grince toute seule, comme si quelque chose la poussait de l'autre côté.
func _ev_grate() -> void:
	var best: Array = []
	for cv in _culverts:
		var dd := (cv[0] as Vector3).distance_to(player.global_position)
		if dd > 3.0 and dd < 14.0:
			best = cv
			if randf() < 0.5:
				break
	if best.is_empty():
		_ev_pipe_bang()
		return
	var pos: Vector3 = best[0]
	Sound.play_at(Sound.variant("grate_creak", 3), pos + Vector3(0, 0.2, 0), 0.0, randf_range(0.85, 1.05), 5.0, 35.0)
	await wait(randf_range(0.6, 1.2))
	splash(pos - (best[1] as Vector3) * 0.2, 1.3)
	Sound.play_at(Sound.variant("drip", 3), pos, -4.0, 0.8, 3.0, 20.0)


## Une ruée de rats : ils déboulent d'un couloir, passent à côté de Théo et filent plus loin.
func _ev_rats() -> void:
	var a := random_point(player.global_position, 4)
	if a.distance_to(player.global_position) < 5.0:
		return
	var b := player.global_position + (player.global_position - a).normalized() * 6.0
	if not walkable(tile_of(b)):
		b = random_point(player.global_position, 3)
	var path := nav_path(a, player.global_position)
	path.append_array(nav_path(player.global_position, b))
	if path.size() < 2:
		return
	Sound.play_at(Sound.variant("rat_squeak", 3), a, 2.0, 1.1, 5.0, 30.0)
	for k in randi_range(5, 9):
		var rat := Rat.new()
		rat.level = self
		rat.run_path = path.duplicate()
		rat.run_speed = randf_range(3.2, 4.2)
		rat.side = randf_range(-0.35, 0.35)
		add_child(rat)
		rat.global_position = a + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
		await wait(randf_range(0.05, 0.25))
	for k in 3:
		await wait(randf_range(0.4, 0.8))
		Sound.play_at(Sound.variant("rat_squeak", 3), player.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), -6.0, randf_range(1.0, 1.3), 3.0, 20.0)
		Sound.play_at(Sound.variant("roach_skitter", 3), player.global_position, -10.0, 1.4, 2.0, 12.0)


## Petit nuage de poussière qui tombe (de la voûte, ou soulevé au sol).
func _dust_puff(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 2.6
	p.explosiveness = 0.85
	p.visibility_aabb = AABB(Vector3(-2, -3, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, -0.35, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.1, Color(1, 1, 1, 0.5))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.25, 0.25)
	q.material = _soft_dot_mat(Color(0.6, 0.57, 0.52, 0.35))
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.3).timeout.connect(func() -> void: if is_instance_valid(p): p.emitting = false)
	get_tree().create_timer(3.5).timeout.connect(func() -> void: if is_instance_valid(p): p.queue_free())


## Gerbe d'étincelles d'une ampoule qui claque.
func _sparks(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 30
	p.lifetime = 0.8
	p.explosiveness = 0.95
	p.visibility_aabb = AABB(Vector3(-2, -3, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.9, 0.6, 1))
	fade.set_color(1, Color(1.0, 0.4, 0.1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	pm.particle_flag_align_y = true
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.006, 0.04)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.albedo_color = Color(1, 1, 1, 1)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.15).timeout.connect(func() -> void: if is_instance_valid(p): p.emitting = false)
	get_tree().create_timer(1.5).timeout.connect(func() -> void: if is_instance_valid(p): p.queue_free())


# ================================================================== rats
class Rat extends Node3D:
	var level: Node
	var run_path := PackedVector3Array()  ## ruée : il suit ce chemin à toute allure puis disparaît
	var run_speed := 3.5
	var side := 0.0
	var fleeing := false
	var _dir := Vector3.ZERO
	var _t := 0.0
	var model: Node3D

	func _ready() -> void:
		model = B.model(self, "street_rat", Vector3.ZERO, randf_range(0, 360), {"scale": 1.7})

	func _process(delta: float) -> void:
		var p: Player = level.player
		if p == null:
			return
		if not run_path.is_empty():
			var target := run_path[0]
			var to := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
			if to.length() < 0.4:
				run_path.remove_at(0)
				if run_path.is_empty():
					queue_free()
				return
			var dir := to.normalized()
			global_position += (dir + Vector3(-dir.z, 0, dir.x) * side * 0.3) * run_speed * delta
			global_position.y = level.floor_y(global_position)
			model.rotation.y = atan2(dir.x, dir.z)
			return
		if not fleeing:
			# petits mouvements nerveux
			_t += delta
			if fmod(_t, 2.0) < delta:
				model.rotation.y += randf_range(-0.6, 0.6)
			if global_position.distance_to(p.global_position) < 3.2:
				fleeing = true
				_dir = (global_position - p.global_position)
				_dir.y = 0
				_dir = _dir.normalized().rotated(Vector3.UP, randf_range(-0.6, 0.6))
				model.rotation.y = atan2(_dir.x, _dir.z)
				Sound.play_at(Sound.variant("rat_squeak", 3), global_position, -8.0, randf_range(0.9, 1.2), 2.0, 15.0)
			return
		global_position += _dir * 3.2 * delta
		_t += delta
		if _t > 6.0 or global_position.distance_to(p.global_position) > 9.0:
			queue_free()
