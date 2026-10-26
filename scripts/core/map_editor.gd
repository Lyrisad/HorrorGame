class_name MapEditor
extends Node
## Éditeur de carte intégré au jeu (F8 dans la maison ou les égouts, ou menu principal).
## Caméra libre, catalogue de tous les modèles 3D du jeu ; on choisit un objet, on le fait
## glisser : il se pose tout seul sur la surface visée (sol, table, étagère, mur).
## Rotation, taille, hauteur, duplication, suppression, annulation, sauvegarde (MapLayout).
## Les objets liés au scénario (téléphones, gâteau, télé, bureau, frigo...) restent fixes.

const EDIT_LAYER := 1 << 19
const HIDDEN := ["sf:rake", "sf:conifer_pack"]
## Packs de modèles qui contiennent plusieurs objets : on propose chaque objet séparément.
const PACK_PARTS := {
	"sf:kitchen_decor": ["Airfryer", "AlmondBottles", "Blender", "Book3", "Bowl", "CeramicSiloCanister", "ChefKnife", "Coffee Machine",
		"Cooking BookPile", "CookingBook", "CuttingWood", "Detergent", "FauxPlant", "Fruit Bowl", "MeasuringCups", "OliveBottle", "Paper Towel",
		"Plant", "Plate", "SpiceGrinder", "SpiceJars", "Spoonge", "TallSpiceBottles", "Toaster", "Utensils", "VacuumCoffeJar", "WineBox"],
	"sf:office_assets": ["Cactus_Pot_2", "Keyboard_3", "Computer_Mouse_4", "Computer_5", "Monitor_6", "FileBox_Black_7", "FileBox_Green_8",
		"Notepad_11", "PhotoFrame_10x15_12", "PinBoard_24", "CigarettePack_Blue_26", "Ashtray_27", "Table_Rough_32", "TapeRecorder_33",
		"Microphone_34", "Poster_Crumpled_45", "PhotoFrame1_47", "Clipboard_49", "Notebook_50", "Chair_51", "Lamp01_57"],
	"sf:glass_bottles": ["Cylinder_007_1", "Cylinder_008_2", "Cube_003_3", "Cube_004_4", "Cylinder_009_5", "Cylinder_011_7", "Cube_005_8"],
	"sf:old_shelves": ["book shelf", "closet"],
	"brass_candleholders": ["brass_candleholder_01", "brass_candleholder_02", "brass_candleholder_03"],
	"wooden_ladder": ["wooden_ladder_steps"],
	"old_military_crate": ["old_military_crate_a"],
}
const PACK_SCALE := {"sf:kitchen_decor": 0.2, "sf:glass_bottles": 0.055}
## Taille réelle des modèles dont l'échelle d'origine est fantaisiste.
const DEFAULT_FIT := {
	"sf:toilet": {"height": 0.78}, "sf:sink_vanity": {"height": 0.94}, "sf:pizza_box": {"width": 0.36}, "sf:pizza_open": {"width": 0.4},
	"sf:beer_bottle": {"height": 0.24}, "sf:beer_can": {"height": 0.12}, "sf:sneakers": {"width": 0.34}, "sf:sneakers_brown": {"width": 0.36},
	"sf:towel_rail": {"depth": 0.7}, "sf:coat_shelf": {"depth": 1.0}, "sf:toilet_paper": {"height": 0.11}, "sf:flat_tv": {"height": 0.72},
	"sf:floor_lamp": {"height": 1.75}, "sf:monstera": {"height": 1.3}, "sf:persian_rug": {"width": 3.2}, "sf:old_fridge": {"height": 1.75},
	"sf:kitchen_cabinets": {"scale": 0.0254}, "sf:gasmask_gp5": {"height": 0.35}, "sf:pine_tree": {"height": 14.0},
	"rubber_duck_toy": {"height": 0.08}, "gamepad": {"width": 0.16}, "potted_plant_01": {"height": 0.9}, "rubber_boots": {"scale": 0.6},
	"boombox": {"scale": 0.75}, "korean_fire_extinguisher_01": {"height": 0.6}, "street_rat": {"scale": 1.7}, "caged_hanging_light": {"scale": 0.7},
	"vintage_microwave": {"scale": 0.65}, "wine_bottles_01": {"scale": 0.8}, "dining_table": {"scale": 0.75}, "throw_pillows_01": {"width": 1.3},
	"water_manhole_cover": {"width": 0.9},
}

var active := false
var map_id := ""
var root: Node3D
var cam: Camera3D
var lamp: OmniLight3D
var prev_cam: Camera3D
var selected: Node3D = null
var grabbing := false
var fly_speed := 3.0
var _grab_from := Transform3D()
var _riders: Array = []  ## [objet, transform relatif] : ce qui est posé sur l'objet déplacé le suit
var _grab_riders_from: Array = []
var _grab_dir := Vector3.ZERO  ## direction de repos d'une caméra au moment de la prise
var _grab_is_new := false
var _drag_mode := false
var _press_pos := Vector2.ZERO
var _press_moved := false
var _ignore_release := false
var _test_mouse := Vector2(-1, -1)  ## position de souris simulée (tests automatiques)
var _grab_offset := Vector3.ZERO  ## écart objet / surface visée au moment de la prise (s'estompe en bougeant)
var _lift := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _looking := false
var _undo: Array = []
var _last_xf_push := {"node": null, "t": 0.0}
var _dirty := false
var _fixed_body: StaticBody3D
var _edit_bodies: Array[Node] = []
var _catalog: Array = []  ## [libellé, modèle, pièce]
var _pick_seq := 0  ## numéro du dernier modèle demandé dans la liste (les demandes plus anciennes sont abandonnées)
var _shown: Array[int] = []
var _reset_armed := 0.0
var _sel_mat: StandardMaterial3D
var _grab_mat: StandardMaterial3D

var layer: CanvasLayer
var panel: PanelContainer
var search: LineEdit
var list: ItemList
var status: Label
var help: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sel_mat = _overlay_mat(Color(1.0, 0.6, 0.1, 0.22))
	_grab_mat = _overlay_mat(Color(0.2, 1.0, 0.4, 0.28))


func _overlay_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.no_depth_test = false
	return m


func can_open() -> bool:
	return Game.playing and not get_tree().paused and Game.level != null and Game.level.has_method("editor_map") and not Game.ui.document_open


# ================================================================== ouverture / fermeture
func open() -> void:
	if active or Game.level == null or not Game.level.has_method("editor_map"):
		return
	var info: Dictionary = Game.level.editor_map()
	map_id = info["id"]
	root = info["root"]
	active = true
	Game.level.process_mode = Node.PROCESS_MODE_DISABLED
	Game.hud.show_hud(false)
	Game.post.visible = false
	for bus in ["World", "Music", "Ambience"]:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_mute(i, true)
	prev_cam = get_viewport().get_camera_3d()
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.03
	cam.far = 400.0
	Game.level.add_child(cam)
	if prev_cam != null:
		cam.global_position = prev_cam.global_position
		var e := prev_cam.global_basis.get_euler()
		_pitch = clampf(e.x, -1.4, 1.4)
		_yaw = e.y
	cam.global_basis = Basis.from_euler(Vector3(_pitch, _yaw, 0))
	# un pas en arrière et un peu plus haut que la caméra-piéton ; le corps de Théo est masqué
	var back := cam.global_basis.z
	back.y = 0.0
	cam.global_position += back.normalized() * 1.2 + Vector3(0, 0.45, 0)
	cam.cull_mask = 0xFFFFF & ~2
	cam.current = true
	lamp = OmniLight3D.new()
	lamp.light_energy = 1.1
	lamp.omni_range = 16.0
	lamp.light_volumetric_fog_energy = 0.0
	cam.add_child(lamp)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_undo.clear()
	_dirty = false
	_build_ui(str(info.get("nom", map_id)))
	_set_status("Préparation de l'éditeur...")
	await get_tree().process_frame
	await get_tree().process_frame
	_build_catalog()
	_build_bodies()
	_set_status("Prêt. Choisissez un objet dans la liste, ou cliquez sur un objet de la carte.")
	if Game.args.has("edtest"):
		_autotest()
	elif Game.args.has("edclick"):
		_clicktest()
	elif Game.args.has("edcam"):
		_camtest()
	elif Game.args.has("edlap"):
		_laptest()
	elif Game.args.has("edpick"):
		_picktest()


func close() -> void:
	if not active:
		return
	if grabbing:
		_cancel_grab()
	_select(null)
	if _dirty:
		_save()
	for b in _edit_bodies:
		if is_instance_valid(b):
			b.queue_free()
	_edit_bodies.clear()
	if is_instance_valid(_fixed_body):
		_fixed_body.queue_free()
	if is_instance_valid(layer):
		layer.queue_free()
	if prev_cam != null and is_instance_valid(prev_cam):
		prev_cam.current = true
	if is_instance_valid(cam):
		cam.queue_free()
	active = false
	_looking = false
	if Game.level != null and is_instance_valid(Game.level):
		Game.level.process_mode = Node.PROCESS_MODE_INHERIT
	Game.hud.show_hud(true)
	Game.post.visible = true
	for bus in ["World", "Music", "Ambience"]:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_mute(i, false)
	Game.capture_mouse(true)


## Collisions temporaires exactes (forme réelle des meshes) : pour viser, choisir et poser.
func _build_bodies() -> void:
	_fixed_body = StaticBody3D.new()
	_fixed_body.name = "_EditFixed"
	_fixed_body.collision_layer = EDIT_LAYER
	_fixed_body.collision_mask = 0
	# le niveau est figé pendant l'édition : sans ça Godot retirerait ces collisions de la physique
	_fixed_body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	root.add_child(_fixed_body)
	for d in MapLayout.collect(root):
		_attach_body(d)
	for c in MapLayout.cameras(root):
		_attach_body(c)
	for o in MapLayout.movables(root):
		_attach_body(o)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.skin != null or not mi.is_visible_in_tree() or _decor_of(mi) != null:
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = shape
		_fixed_body.add_child(cs)
		cs.global_transform = mi.global_transform


func _attach_body(n: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "_EditBody"
	body.collision_layer = EDIT_LAYER
	body.collision_mask = 0
	body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	n.add_child(body)
	for node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		# un objet déplaçable posé DANS un autre (la radio dans la cabane) a sa propre zone de clic
		if mi.mesh == null or _decor_of(mi) != n:
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		cs.global_transform = mi.global_transform
	_edit_bodies.append(body)


# ================================================================== interface
func _build_ui(map_name: String) -> void:
	layer = CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	var th := (Game.ui.ui_theme as Theme).duplicate() as Theme
	th.default_font_size = 17
	panel = PanelContainer.new()
	panel.theme = th
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.04, 0.9)
	sb.border_color = Color(1, 1, 1, 0.15)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_bottom = 1.0
	panel.offset_left = 12
	panel.offset_top = 12
	panel.offset_right = 392
	panel.offset_bottom = -12
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var title := Label.new()
	title.text = "ÉDITEUR DE CARTE — " + map_name.to_upper()
	title.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
	col.add_child(title)
	search = LineEdit.new()
	search.placeholder_text = "Rechercher (chair, bottle, plant, lamp...)"
	search.clear_button_enabled = true
	search.text_changed.connect(_filter)
	col.add_child(search)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# la liste ne prend jamais le clavier : sinon ZQSD (caméra) y « cherche » une lettre — D sautait sur
	# « dead tree trunk » et en créait un à chaque répétition de la touche, abandonné au point (0, 0, 0)
	list.focus_mode = Control.FOCUS_NONE
	list.allow_search = false
	list.item_selected.connect(_on_pick_model)
	col.add_child(list)
	for spec in [["Sauvegarder  (Ctrl+S)", _save], ["Remettre le décor d'origine", _reset], ["Quitter l'éditeur  (F8)", close]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		col.add_child(b)
	help = Label.new()
	help.theme = th
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	help.add_theme_constant_override("shadow_offset_x", 1)
	help.add_theme_constant_override("shadow_offset_y", 1)
	help.text = ("CAMÉRA  clic droit maintenu : regarder · ZQSD/WASD : avancer · Espace / C : monter / descendre · Maj : vite\n" +
		"OBJETS  clic gauche sur un objet : il suit la souris et se pose sur la surface visée · nouveau clic : le poser\n" +
		"        molette : tourner (Alt = précis) · Ctrl + molette : agrandir / réduire · Maj + molette : monter / descendre · flèches : ajuster\n" +
		"        X : coucher · R : remettre droit · Ctrl+D : dupliquer · Suppr : supprimer · Ctrl+Z : annuler\n" +
		"CARTE   Ctrl+S : sauvegarder · L : lampe de travail · F8 ou Échap : quitter (sauvegarde automatique)")
	help.anchor_left = 0.0
	help.anchor_right = 1.0
	help.offset_left = 410
	help.offset_top = 14
	help.offset_right = -14
	layer.add_child(help)
	status = Label.new()
	status.theme = th
	status.add_theme_font_size_override("font_size", 19)
	status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	status.anchor_top = 1.0
	status.anchor_bottom = 1.0
	status.anchor_right = 1.0
	status.offset_left = 410
	status.offset_top = -50
	status.offset_right = -14
	status.offset_bottom = -14
	layer.add_child(status)


func _set_status(t: String) -> void:
	if is_instance_valid(status):
		status.text = t


func _over_ui(pos: Vector2) -> bool:
	return is_instance_valid(panel) and panel.get_global_rect().has_point(pos)


## Catalogue : tous les modèles Poly Haven + Sketchfab du jeu (et les objets des packs).
func _build_catalog() -> void:
	_catalog.clear()
	for d in DirAccess.get_directories_at("res://assets/models"):
		if ResourceLoader.exists(B.model_path(d)):
			if PACK_PARTS.has(d):
				for part: String in PACK_PARTS[d]:
					_catalog.append([d.replace("_", " ") + " › " + part.replace("_", " "), d, part])
			else:
				_catalog.append([d.replace("_", " "), d, ""])
	for d in DirAccess.get_directories_at("res://assets/sketchfab"):
		var slug := "sf:" + d
		if slug in HIDDEN or not ResourceLoader.exists(B.model_path(slug)):
			continue
		if PACK_PARTS.has(slug):
			for part: String in PACK_PARTS[slug]:
				_catalog.append([d.replace("_", " ") + " › " + part.replace("_", " "), slug, part])
		else:
			_catalog.append([d.replace("_", " "), slug, ""])
	_catalog.append(["gobelet rouge", "proc:red_cup", ""])
	_catalog.append(["gobelet rouge renversé", "proc:red_cup_tipped", ""])
	_catalog.append(["toile d'araignée (qui pend du plafond)", "proc:cobweb_strands", ""])
	_catalog.append(["bouteille à ramasser (à lancer pour faire diversion)", "proc:bottle", ""])
	for k in 3:
		_catalog.append(["avis de recherche %d (sur un arbre)" % (k + 1), "proc:poster_%d" % k, ""])
	_catalog.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]).to_lower() < str(b[0]).to_lower())
	_filter(search.text)


func _filter(text: String) -> void:
	list.clear()
	_shown.clear()
	var q := text.strip_edges().to_lower()
	for i in _catalog.size():
		var e: Array = _catalog[i]
		if q == "" or str(e[0]).to_lower().contains(q) or str(e[1]).to_lower().contains(q):
			list.add_item(e[0])
			_shown.append(i)


# ================================================================== entrées
func _input(event: InputEvent) -> void:
	if not active:
		if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F8 and can_open():
			get_viewport().set_input_as_handled()
			open()
		return
	if event is InputEventKey:
		_on_key(event as InputEventKey)
	elif event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _looking:
			_yaw -= mm.relative.x * 0.0035
			_pitch = clampf(_pitch - mm.relative.y * 0.0035, -1.5, 1.5)
			get_viewport().set_input_as_handled()
		elif grabbing and mm.position.distance_to(_press_pos) > 6.0:
			_press_moved = true


func _on_key(k: InputEventKey) -> void:
	if not k.pressed:
		return
	if is_instance_valid(search) and search.has_focus():
		if k.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
			search.release_focus()
			get_viewport().set_input_as_handled()
		return
	var fine := k.shift_pressed
	var handled := true
	match k.keycode:
		KEY_F8:
			close()
		KEY_ESCAPE:
			if grabbing:
				_cancel_grab()
			elif selected != null:
				_select(null)
			else:
				close()
		KEY_S:
			handled = k.ctrl_pressed
			if handled:
				_save()
		KEY_Z:
			handled = k.ctrl_pressed
			if handled:
				_undo_last()
		KEY_D:
			handled = k.ctrl_pressed
			if handled:
				_duplicate()
		KEY_DELETE, KEY_BACKSPACE:
			_delete()
		KEY_G:
			if selected != null and not grabbing:
				_start_grab(false)
				_drag_mode = false
		KEY_R:
			_upright()
		KEY_X:
			_tilt()
		KEY_L:
			lamp.visible = not lamp.visible
		KEY_KP_ADD, KEY_EQUAL, KEY_PLUS:
			_scale(1.01 if fine else 1.06)
		KEY_KP_SUBTRACT, KEY_MINUS:
			_scale(1.0 / (1.01 if fine else 1.06))
		KEY_PAGEUP:
			_raise(0.1 if fine else 0.01)
		KEY_PAGEDOWN:
			_raise(-0.1 if fine else -0.01)
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			_nudge(k.keycode, 0.1 if fine else 0.02)
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _on_mouse_button(b: InputEventMouseButton) -> void:
	if b.button_index == MOUSE_BUTTON_RIGHT:
		_looking = b.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if b.pressed else Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return
	if _over_ui(b.position) and not _looking:
		return
	match b.button_index:
		MOUSE_BUTTON_LEFT:
			# clic sur un objet : il suit la souris ; nouveau clic : on le pose.
			# (cliquer-glisser marche aussi : on le pose en relâchant)
			if b.pressed:
				if grabbing:
					_drop()
					_ignore_release = true
				else:
					_pick(b.position)
					if selected != null:
						_press_pos = b.position
						_press_moved = false
						_start_grab(false)
						_drag_mode = true
			else:
				if _ignore_release:
					_ignore_release = false
				elif grabbing and _drag_mode:
					if _press_moved:
						_drop()
					else:
						_drag_mode = false
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not b.pressed:
				return
			var sgn := 1.0 if b.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			if selected != null:
				if b.ctrl_pressed:
					_scale(1.06 if sgn > 0 else 1.0 / 1.06)  # Ctrl + molette : taille
				elif b.shift_pressed:
					_raise(sgn * 0.02)  # Maj + molette : monter / descendre
				else:
					_rotate(sgn * (2.0 if b.alt_pressed else 15.0))  # molette : tourner (Alt = précis)
			else:
				fly_speed = clampf(fly_speed * (1.2 if sgn > 0 else 1.0 / 1.2), 0.5, 20.0)
				_set_status("Vitesse de la caméra : %.1f m/s" % fly_speed)
	get_viewport().set_input_as_handled()


# ================================================================== boucle
func _process(delta: float) -> void:
	if not active or not is_instance_valid(cam):
		return
	if _reset_armed > 0.0:
		_reset_armed -= delta
	if not (is_instance_valid(search) and search.has_focus()):
		var mv := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W):
			mv.z -= 1
		if Input.is_physical_key_pressed(KEY_S):
			mv.z += 1
		if Input.is_physical_key_pressed(KEY_A):
			mv.x -= 1
		if Input.is_physical_key_pressed(KEY_D) and not Input.is_key_pressed(KEY_CTRL):
			mv.x += 1
		var up := 0.0
		if Input.is_physical_key_pressed(KEY_SPACE):
			up += 1.0
		if Input.is_physical_key_pressed(KEY_C):
			up -= 1.0
		var spd := fly_speed * (4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		var bas := Basis.from_euler(Vector3(_pitch, _yaw, 0))
		cam.global_position += (bas * mv.limit_length(1.0) + Vector3.UP * up) * spd * delta
	cam.global_basis = Basis.from_euler(Vector3(_pitch, _yaw, 0))
	if grabbing and is_instance_valid(selected):
		_follow_cursor()


# ================================================================== sélection et déplacement
func _ray(screen_pos: Vector2, exclude: Array[RID] = []) -> Dictionary:
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 150.0
	var q := PhysicsRayQueryParameters3D.create(from, to, EDIT_LAYER, exclude)
	return cam.get_world_3d().direct_space_state.intersect_ray(q)


func _decor_of(node: Node) -> Node3D:
	var n := node
	while n != null and n != root:
		if n.has_meta("decor") or n.has_meta("editcam") or n.has_meta("editobj"):
			return n as Node3D
		n = n.get_parent()
	return null


func _is_cam(n: Node) -> bool:
	return n is SecurityCamera and n.has_meta("editcam")


## Refus poli pour les opérations qui n'ont pas de sens sur une caméra.
func _cam_refuse() -> bool:
	if is_instance_valid(selected) and _is_cam(selected):
		_set_status("Caméra de surveillance : on peut la déplacer (clic) et l'orienter (molette, Maj+molette), pas la supprimer ni la redimensionner.")
		return true
	return false


## Les objets de l'histoire (ordinateur...) se déplacent mais ne se suppriment ni ne se dupliquent.
func _story_refuse() -> bool:
	if is_instance_valid(selected) and selected.has_meta("editobj"):
		_set_status("Élément du niveau : on peut le déplacer, le tourner et changer sa taille, pas le supprimer ni le dupliquer.")
		return true
	return false


func _pick(pos: Vector2) -> void:
	var hit := _ray(pos)
	if hit.is_empty():
		_select(null)
		return
	var d := _decor_of(hit["collider"])
	if d == null:
		_select(null)
		_set_status("Objet fixe (structure ou objet lié à l'histoire) : il ne se déplace pas.")
		return
	_select(d)


func _select(n: Node3D) -> void:
	if is_instance_valid(selected):
		_set_overlay(selected, null)
	selected = n
	if n != null:
		_set_overlay(n, _sel_mat)
	_describe()


func _describe() -> void:
	if not is_instance_valid(selected):
		_set_status("Aucun objet choisi.")
		return
	if _is_cam(selected):
		_set_status("Caméra de surveillance   ·   %s" % ("elle suit la souris : posez-la sur un mur ou au plafond (clic gauche) · Échap : annuler" if grabbing else "clic gauche pour la déplacer · molette : tourner · Maj+molette : incliner"))
		return
	var spec: Dictionary = selected.get_meta("spec", {})
	var nm := str(spec.get("model", "?")).trim_prefix("sf:")
	if selected.has_meta("editobj"):
		nm += " (élément du niveau)"
	if str(spec.get("part", "")) != "":
		nm += " › " + str(spec["part"])
	_set_status("%s   ·   taille ×%.2f   ·   %s" % [nm, selected.scale.x, "il suit la souris : clic gauche pour le poser · molette : tourner · Ctrl+molette : taille · Maj+molette : hauteur · Échap : annuler" if grabbing else "clic gauche dessus pour le déplacer · molette : tourner · Ctrl+molette : taille · Maj+molette : hauteur · Suppr : supprimer"])


func _set_overlay(n: Node3D, mat: Material) -> void:
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).material_overlay = mat


func _rids(n: Node3D) -> Array[RID]:
	var out: Array[RID] = []
	for c in n.find_children("*", "CollisionObject3D", true, false):
		out.append((c as CollisionObject3D).get_rid())
	return out


func _size(n: Node3D) -> Vector3:
	return (n.get_meta("size", Vector3(0.3, 0.3, 0.3)) as Vector3) * n.scale.x


## Objets de décor posés sur `s` (coussins sur le canapé, bouteilles sur l'étagère...).
func _find_riders(s: Node3D) -> Array:
	var out := []
	var size: Vector3 = s.get_meta("size", Vector3.ZERO)
	if not bool((s.get_meta("spec", {}) as Dictionary).get("center", true)) or size.y < 0.05:
		return out
	var inv := s.global_transform.affine_inverse()
	for d in MapLayout.collect(root):
		if d == s:
			continue
		var lp := inv * d.global_position
		if absf(lp.x) < size.x * 0.5 + 0.02 and absf(lp.z) < size.z * 0.5 + 0.02 and lp.y > 0.04 and lp.y < size.y + 0.1:
			out.append([d, inv * d.global_transform])
	return out


func _carry() -> void:
	if not is_instance_valid(selected):
		return
	for r in _riders:
		if is_instance_valid(r[0]):
			(r[0] as Node3D).global_transform = selected.global_transform * (r[1] as Transform3D)


func _rider_xfs() -> Array:
	var out := []
	for r in _riders:
		if is_instance_valid(r[0]):
			out.append([r[0], (r[0] as Node3D).transform])
	return out


func _start_grab(is_new: bool) -> void:
	if not is_instance_valid(selected):
		return
	grabbing = true
	_grab_is_new = is_new
	_grab_from = selected.transform
	_grab_dir = (selected as SecurityCamera).rest_dir if _is_cam(selected) else Vector3.ZERO
	_riders = [] if is_new else _find_riders(selected)
	_grab_riders_from = _rider_xfs()
	_grab_offset = Vector3.ZERO
	_press_pos = _mouse_pos()
	if not is_new and not _is_cam(selected):
		var hit := _ray(_press_pos, _grab_excludes())
		if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.55:
			_grab_offset = selected.global_position - (hit["position"] as Vector3)
	_lift = 0.0
	_set_overlay(selected, _grab_mat)
	_describe()


func _mouse_pos() -> Vector2:
	return _test_mouse if _test_mouse.x >= 0.0 else get_viewport().get_mouse_position()


func _grab_excludes() -> Array[RID]:
	var excl := _rids(selected)
	for r in _riders:
		if is_instance_valid(r[0]):
			excl.append_array(_rids(r[0]))
	return excl


func _follow_cursor() -> void:
	var mouse := _mouse_pos()
	var hit := _ray(mouse, _grab_excludes())
	var keep := clampf(1.0 - mouse.distance_to(_press_pos) / 90.0, 0.0, 1.0)
	var size := _size(selected)
	var centered := bool((selected.get_meta("spec", {}) as Dictionary).get("center", true))
	if hit.is_empty():
		selected.global_position = cam.global_position - cam.global_basis.z * 2.5
		return
	var n: Vector3 = hit["normal"]
	var p: Vector3 = hit["position"]
	if _is_cam(selected):
		var sc_cam := selected as SecurityCamera
		if absf(n.y) < 0.45:
			var out := Vector3(n.x, 0, n.z).normalized()
			sc_cam.global_position = p
			sc_cam.set_rest((out + Vector3(0, -0.45, 0)).normalized())
			sc_cam.attach_wall(p, n)
		elif n.y < -0.55:
			var flat_dir := Vector3(sc_cam.rest_dir.x, 0, sc_cam.rest_dir.z)
			if flat_dir.length() < 0.1:
				flat_dir = -cam.global_basis.z
			sc_cam.set_rest((flat_dir.normalized() + Vector3(0, -0.7, 0)).normalized())
			sc_cam.attach_ceiling(p)
		return
	if n.y > 0.55:
		# sol, table, étagère : posé dessus (sans sauter au moment de la prise)
		selected.global_position = p + _grab_offset * keep + Vector3(0, _lift, 0)
		_carry()
	elif n.y < -0.55:
		# plafond : suspendu dessous
		selected.global_position = p - Vector3(0, size.y - _lift, 0)
		_carry()
	else:
		# mur : face à la pièce, collé au mur, centré sur le curseur
		var flat := Vector3(n.x, 0, n.z).normalized()
		var sc := selected.scale
		selected.global_basis = Basis.from_euler(Vector3(0, atan2(flat.x, flat.z), 0))
		selected.scale = sc
		var off := flat * (size.z * 0.5 + 0.005 if centered else 0.01)
		selected.global_position = p + off - Vector3(0, size.y * 0.5 if centered else 0.0, 0) + Vector3(0, _lift, 0)
	_carry()


func _drop() -> void:
	grabbing = false
	_drag_mode = false
	if is_instance_valid(selected):
		if not _grab_is_new:
			_undo.append({"op": "xf", "node": selected, "xf": _grab_from, "riders": _grab_riders_from, "dir": _grab_dir})
		_set_overlay(selected, _sel_mat)
	_dirty = true
	_describe()


func _cancel_grab() -> void:
	grabbing = false
	_drag_mode = false
	if not is_instance_valid(selected):
		return
	if _grab_is_new:
		var n := selected
		_select(null)
		n.queue_free()
		if not _undo.is_empty() and _undo.back().get("node") == n:
			_undo.pop_back()
	else:
		selected.transform = _grab_from
		if _is_cam(selected):
			(selected as SecurityCamera).set_rest(_grab_dir)
		for r in _grab_riders_from:
			if is_instance_valid(r[0]):
				(r[0] as Node3D).transform = r[1]
		_set_overlay(selected, _sel_mat)
		_describe()


## Mémorise la position avant une petite retouche (regroupe les retouches rapprochées).
func _push_xf(n: Node3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _last_xf_push["node"] == n and now - float(_last_xf_push["t"]) < 0.8:
		_last_xf_push["t"] = now
		return
	_last_xf_push = {"node": n, "t": now}
	_riders = _find_riders(n)
	_undo.append({"op": "xf", "node": n, "xf": n.transform, "riders": _rider_xfs(), "dir": (n as SecurityCamera).rest_dir if _is_cam(n) else Vector3.ZERO})
	if _undo.size() > 300:
		_undo.pop_front()


func _rotate(deg: float) -> void:
	if not is_instance_valid(selected):
		return
	if not grabbing:
		_push_xf(selected)
	if _is_cam(selected):
		var sc_cam := selected as SecurityCamera
		sc_cam.set_rest(sc_cam.rest_dir.rotated(Vector3.UP, deg_to_rad(deg)))
		_dirty = true
		return
	selected.global_rotate(Vector3.UP, deg_to_rad(deg))
	if not grabbing:
		_carry()
	_dirty = true
	_describe()


func _scale(f: float) -> void:
	if not is_instance_valid(selected):
		return
	if _cam_refuse():
		return
	if not grabbing:
		_push_xf(selected)
	selected.scale = (selected.scale * f).clamp(Vector3.ONE * 0.05, Vector3.ONE * 20.0)
	_dirty = true
	_describe()


func _raise(d: float) -> void:
	if not is_instance_valid(selected):
		return
	if _is_cam(selected):
		# Maj + molette sur une caméra : on l'incline (plus ou moins plongeante)
		_push_xf(selected)
		var sc_cam := selected as SecurityCamera
		var side := sc_cam.rest_dir.cross(Vector3.UP)
		if side.length() > 0.01:
			var nd := sc_cam.rest_dir.rotated(side.normalized(), d * 4.0)
			if nd.y < 0.2 and nd.y > -0.97:
				sc_cam.set_rest(nd)
		_dirty = true
		return
	if grabbing:
		_lift += d
		return
	_push_xf(selected)
	selected.global_position.y += d
	_carry()
	_dirty = true


func _nudge(key: Key, d: float) -> void:
	if not is_instance_valid(selected) or grabbing:
		return
	var fwd := -cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := cam.global_basis.x
	right.y = 0
	right = right.normalized()
	var v := Vector3.ZERO
	match key:
		KEY_UP:
			v = fwd
		KEY_DOWN:
			v = -fwd
		KEY_LEFT:
			v = -right
		KEY_RIGHT:
			v = right
	_push_xf(selected)
	selected.global_position += v * d
	_carry()
	_dirty = true


func _upright() -> void:
	if not is_instance_valid(selected):
		return
	if _cam_refuse():
		return
	_push_xf(selected)
	var fwd := selected.global_basis.z
	var sc := selected.scale
	selected.global_basis = Basis.from_euler(Vector3(0, atan2(fwd.x, fwd.z), 0))
	selected.scale = sc
	_dirty = true


func _tilt() -> void:
	if not is_instance_valid(selected):
		return
	if _cam_refuse():
		return
	_push_xf(selected)
	selected.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_dirty = true


# ================================================================== ajout / copie / suppression
func _on_pick_model(idx: int) -> void:
	list.deselect_all()
	if idx < 0 or idx >= _shown.size():
		return
	if grabbing:
		_cancel_grab()
	var e: Array = _catalog[_shown[idx]]
	var slug: String = e[1]
	var part: String = e[2]
	_set_status("Chargement de « %s »..." % e[0])
	_pick_seq += 1
	var seq := _pick_seq
	await get_tree().process_frame
	if seq != _pick_seq or not active:
		return  # un autre modèle a été demandé entre-temps : seul le dernier est créé
	var n: Node3D
	if slug.begins_with("proc:"):
		n = MapLayout.spawn_entry({"model": slug}, root)
	else:
		var fit: Dictionary = {}
		if part != "":
			fit["part"] = part
			if PACK_SCALE.has(slug):
				fit["scale"] = PACK_SCALE[slug]
		else:
			fit = (DEFAULT_FIT.get(slug, {}) as Dictionary).duplicate()
		n = B.model(root, slug, Vector3.ZERO, 0.0, fit)
		# échelle d'origine absurde (modèle en centimètres...) : on ramène à ~60 cm
		var sz: Vector3 = n.get_meta("size", Vector3.ONE)
		var mx := maxf(sz.x, maxf(sz.y, sz.z))
		if not DEFAULT_FIT.has(slug) and part == "" and (mx > 8.0 or mx < 0.02):
			var s0 := float((n.get_meta("spec") as Dictionary).get("scale", 1.0))
			n.free()
			fit["scale"] = s0 * 0.6 / maxf(mx, 0.0001)
			n = B.model(root, slug, Vector3.ZERO, 0.0, fit)
		n.set_meta("decor", true)
		_auto_collide(n)
	_attach_body(n)
	_undo.append({"op": "add", "node": n})
	_dirty = true
	_select(n)
	_start_grab(true)
	_drag_mode = false


## Les gros objets posés au sol bloquent le joueur, comme les meubles d'origine.
func _auto_collide(n: Node3D) -> void:
	MapLayout.auto_collide(n)


func _duplicate() -> void:
	if not is_instance_valid(selected):
		return
	if _cam_refuse() or _story_refuse():
		return
	if grabbing:
		_drop()
	var n := MapLayout.spawn_entry(MapLayout.entry_of(selected, root), root)
	_attach_body(n)
	_undo.append({"op": "add", "node": n})
	_dirty = true
	_select(n)
	_start_grab(true)
	_drag_mode = false


func _delete() -> void:
	if not is_instance_valid(selected):
		return
	if _cam_refuse() or _story_refuse():
		return
	if grabbing:
		_cancel_grab()
		if not is_instance_valid(selected):
			return
	_undo.append({"op": "del", "entry": MapLayout.entry_of(selected, root)})
	var n := selected
	_select(null)
	n.queue_free()
	_dirty = true
	_set_status("Objet supprimé (Ctrl+Z pour annuler).")


func _undo_last() -> void:
	if grabbing:
		_cancel_grab()
		return
	if _undo.is_empty():
		_set_status("Rien à annuler.")
		return
	var op: Dictionary = _undo.pop_back()
	match op["op"]:
		"xf":
			if is_instance_valid(op["node"]):
				(op["node"] as Node3D).transform = op["xf"]
				if _is_cam(op["node"]) and (op.get("dir", Vector3.ZERO) as Vector3) != Vector3.ZERO:
					(op["node"] as SecurityCamera).set_rest(op["dir"])
				_select(op["node"])
			for r in op.get("riders", []):
				if is_instance_valid(r[0]):
					(r[0] as Node3D).transform = r[1]
		"add":
			if is_instance_valid(op["node"]):
				if selected == op["node"]:
					_select(null)
				(op["node"] as Node3D).queue_free()
		"del":
			var n := MapLayout.spawn_entry(op["entry"], root)
			_attach_body(n)
			_select(n)
	_last_xf_push = {"node": null, "t": 0.0}
	_dirty = true


# ================================================================== fichier
func _save() -> void:
	if grabbing:
		_drop()
	var path := MapLayout.save(map_id, root)
	_dirty = false
	_set_status("Carte sauvegardée (%d objets) → %s" % [MapLayout.collect(root).size(), path])


func _reset() -> void:
	if _reset_armed <= 0.0:
		_reset_armed = 3.0
		_set_status("Remettre le décor d'origine ? Toutes vos modifications seront perdues. Cliquez encore pour confirmer.")
		return
	MapLayout.reset(map_id)
	_dirty = false
	var lvl := Game.level_name
	var params := Game.level_params.duplicate()
	params["editor"] = true
	close()
	Game.start_level(lvl, params)


# ================================================================== test automatique (--edtest)
## Choisit un objet, le déplace et le tourne, ajoute un modèle du catalogue, en supprime un,
## sauvegarde puis quitte : la partie suivante doit recréer exactement cette disposition.
func _autotest() -> void:
	var decor := MapLayout.collect(root)
	print("EDTEST décor=%d catalogue=%d" % [decor.size(), _catalog.size()])
	await get_tree().create_timer(1.5).timeout
	var target: Node3D = null
	var victim: Node3D = null
	for d in decor:
		var m := str((d.get_meta("spec", {}) as Dictionary).get("model", ""))
		if target == null and (m == "sofa_02" or m == "deco" or m.begins_with("trashbag")):
			target = d
		elif victim == null and (m == "rubber_boots" or m == "WetFloorSign_01"):
			victim = d
	if target == null:
		target = decor[0]
	_select(target)
	_rotate(30.0)
	_push_xf(target)
	target.global_position += Vector3(0.8, 0, 0.3)
	print("EDTEST déplacé %s → %s" % [target.get_meta("spec")["model"], MapLayout.entry_of(target, root)["xf"].slice(9)])
	await get_tree().create_timer(1.0).timeout
	search.text = "toilet"
	_filter("toilet")
	_on_pick_model(0)
	await get_tree().create_timer(0.5).timeout
	selected.global_position = cam.global_position - cam.global_basis.z * 2.0
	selected.global_position.y = root.global_position.y + (0.36 if map_id == "maison" else 0.0)
	_drop()
	print("EDTEST ajouté %s" % selected.get_meta("spec")["model"])
	await get_tree().create_timer(1.5).timeout
	if victim != null:
		_select(victim)
		_delete()
		print("EDTEST supprimé")
	_save()
	print("EDTEST sauvegardé %d objets" % MapLayout.collect(root).size())
	await get_tree().create_timer(1.0).timeout
	close()


## --edclick : clic gauche sur un objet → il suit la souris ; nouveau clic → posé.
func _clicktest() -> void:
	await get_tree().create_timer(1.0).timeout
	# premier objet de décor réellement visible (le rayon sous son centre le touche)
	var target: Node3D = null
	var sp := Vector2.ZERO
	var vr := get_viewport().get_visible_rect()
	for d in MapLayout.collect(root):
		var size0: Vector3 = d.get_meta("size", Vector3.ONE)
		var c := d.global_position + Vector3(0, size0.y * 0.5, 0)
		if cam.is_position_behind(c):
			continue
		var p := cam.unproject_position(c)
		if not vr.grow(-60).has_point(p) or _over_ui(p):
			continue
		var h := _ray(p)
		if not h.is_empty() and _decor_of(h["collider"]) == d:
			target = d
			sp = p
			break
	if target == null:
		print("EDCLICK aucun objet visible")
		close()
		return
	var before := target.global_position
	var dbg := _ray(sp)
	print("EDCLICK cible=%s écran=%s derrière=%s cam=%s rayon=%s" % [target.get_meta("spec")["model"], sp, cam.is_position_behind(target.global_position), cam.global_position, "rien" if dbg.is_empty() else "%s (%s) décor=%s" % [dbg["collider"], (dbg["collider"] as Node).get_path(), _decor_of(dbg["collider"])]])
	print("EDCLICK corps de la cible : %s" % [target.find_children("*", "CollisionObject3D", true, false)])
	_test_mouse = sp
	_click(sp, true)
	_click(sp, false)
	await get_tree().create_timer(0.3).timeout
	print("EDCLICK après clic : sélection=%s suit_la_souris=%s a_sauté=%.3f m" % [selected == target, grabbing and not _drag_mode, target.global_position.distance_to(before)])
	var dest := sp + Vector2(160, 40)
	for i in 20:
		_test_mouse = sp.lerp(dest, (i + 1) / 20.0)
		await get_tree().process_frame
	print("EDCLICK déplacé de %.2f m en suivant la souris" % target.global_position.distance_to(before))
	_click(dest, true)
	_click(dest, false)
	await get_tree().create_timer(0.3).timeout
	var placed := target.global_position
	_test_mouse = sp
	await get_tree().create_timer(0.3).timeout
	print("EDCLICK posé : suit_encore=%s resté_en_place=%s" % [grabbing, target.global_position.distance_to(placed) < 0.001])
	_dirty = false
	_test_mouse = Vector2(-1, -1)
	close()


func _click(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	_on_mouse_button(ev)


## --edcam : déplace une caméra de surveillance sur le mur visé, la tourne, l'incline, sauvegarde.
func _camtest() -> void:
	await get_tree().create_timer(1.0).timeout
	var cams := MapLayout.cameras(root)
	print("EDCAM caméras réglables : %d" % cams.size())
	var c := cams[0]
	var before := c.global_position
	_select(c)
	_start_grab(false)
	_test_mouse = get_viewport().get_visible_rect().size * Vector2(0.6, 0.45)
	for i in 6:
		await get_tree().process_frame
	_drop()
	_rotate(20.0)
	_raise(0.05)
	print("EDCAM déplacée de %.2f m, direction %s" % [c.global_position.distance_to(before), c.rest_dir])
	_save()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MapLayout.file_for(map_id)))
	print("EDCAM fichier : %d caméras enregistrées" % (data.get("cams", []) as Array).size())
	_test_mouse = Vector2(-1, -1)
	close()


## --edlap : prend l'ordinateur (objet de l'histoire), le pose ailleurs, refuse de le supprimer, sauvegarde.
## --edpick=id1,id2 : vise chaque élément déplaçable (même posé dans un autre, comme la radio dans la cabane)
## et clique dessus ; affiche ce qui est sélectionné. Ne sauvegarde rien.
func _picktest() -> void:
	await get_tree().create_timer(1.0).timeout
	var by_id := {}
	for o in MapLayout.movables(root):
		by_id[str(o.get_meta("editobj"))] = o
	for id in str(Game.args["edpick"]).split(","):
		var o: Node3D = by_id.get(id)
		if o == null:
			print("EDPICK %s : introuvable" % id)
			continue
		var host := o.get_parent() as Node3D
		# vise ses propres maillages (pas ceux des objets posés dessus) : le centre, puis deux autres points
		var target := o.global_position
		var aims: Array[Vector3] = []
		for mi in o.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh != null and _decor_of(mi) == o:
				var bb := (mi as MeshInstance3D).get_aabb()
				var xf := (mi as MeshInstance3D).global_transform
				aims = [xf * bb.get_center(), xf * (bb.position + bb.size * 0.35), xf * (bb.position + bb.size * 0.65)]
				target = aims[0]
				break
		if aims.is_empty():
			aims = [target]
		# la caméra devant la table, ou à 1,2 m de l'objet côté pièce (côté extérieur s'il est dehors), à hauteur d'yeux
		cam.global_position = host.global_transform * Vector3(0, 1.7, 1.8)
		if not id.begins_with("surface_camp"):
			var top := o
			while top.get_parent() != root:
				top = top.get_parent() as Node3D
			var flat := target - top.global_position
			flat.y = 0.0
			var out := flat.length() > 2.6
			cam.global_position = target + (flat.normalized() * 1.4 if out else -flat.normalized() * 1.2) + Vector3(0, 0.7 if out else 0.25, 0)
		var dir := target - cam.global_position
		_yaw = atan2(-dir.x, -dir.z)
		_pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
		for i in 3:
			await get_tree().process_frame
		for a in aims:
			_pick(cam.unproject_position(a))
			if selected == o:
				break
		var got := "rien"
		if selected != null:
			got = str(selected.get_meta("editobj")) if selected.has_meta("editobj") else str((selected.get_meta("spec", {}) as Dictionary).get("model", "?"))
		print("EDPICK %s → sélectionné : %s" % [id, got])
		_select(null)
	_dirty = false
	close()


func _laptest() -> void:
	await get_tree().create_timer(1.0).timeout
	var objs := MapLayout.movables(root)
	print("EDLAP éléments déplaçables : %s" % str(objs.map(func(o: Node) -> String: return str(o.get_meta("editobj")))))
	var lap := objs[0]
	for o in objs:
		if str(o.get_meta("editobj")) == str(Game.args.get("edlap", "")):
			lap = o
	var before := lap.global_position
	_select(lap)
	_start_grab(false)
	_test_mouse = get_viewport().get_visible_rect().size * Vector2(0.45, 0.7)
	for i in 6:
		await get_tree().process_frame
	_drop()
	_rotate(30.0)
	_delete()
	_duplicate()
	var it := lap.find_children("*", "Interactable", true, false)
	print("EDLAP déplacé de %.2f m → %s ; toujours là : %s ; zone d'interaction attachée : %s à %s" % [lap.global_position.distance_to(before), lap.global_position, is_instance_valid(lap) and not lap.is_queued_for_deletion(), it.size(), (it[0] as Node3D).global_position if it.size() > 0 else Vector3.ZERO])
	_save()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MapLayout.file_for(map_id)))
	print("EDLAP fichier : objs=%s" % str(data.get("objs", [])))
	_test_mouse = Vector2(-1, -1)
	close()
