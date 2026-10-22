class_name InventoryUI
extends CanvasLayer
## Inventaire ([I]) : ce que Théo porte sur lui (cases avec une icône dessinée, quantité,
## description) et les documents déjà lus, qu'on peut relire. Le jeu est en pause pendant ce temps.
## Le contenu vient du niveau : Level.inventory() et Level.documents.

const SLOT := Vector2(176, 196)
const INK := Color(0.86, 0.86, 0.82)
const DIM := Color(1, 1, 1, 0.35)

var root: Control
var grid: GridContainer
var empty_label: Label
var detail_name: Label
var detail_desc: Label
var docs_box: VBoxContainer
var docs_title: Label
var objective_label: Label
var is_open := false
var _items: Array = []
var _selected := 0


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.012, 0.014, 0.88)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.custom_minimum_size = Vector2(1180, 0)
	center.add_child(col)
	# en-tête
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(_label("INVENTAIRE", 34, INK, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_label("[I] / [Échap]  fermer", 18, DIM))
	objective_label = _label("", 18, Color(1.0, 0.82, 0.48, 0.9))
	col.add_child(objective_label)
	col.add_child(_separator())
	# objets + détail de l'objet choisi
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	col.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(4 * SLOT.x + 3 * 12, 2 * SLOT.y + 12)
	row.add_child(left)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	left.add_child(grid)
	empty_label = _label("Les poches vides.", 22, DIM)
	left.add_child(empty_label)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	detail_name = _label("", 26, INK, true)
	right.add_child(detail_name)
	detail_desc = _label("", 19, Color(0.78, 0.78, 0.75))
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_desc.custom_minimum_size = Vector2(420, 0)
	right.add_child(detail_desc)
	# documents à relire
	col.add_child(_separator())
	docs_title = _label("DOCUMENTS", 22, INK, true)
	col.add_child(docs_title)
	docs_box = VBoxContainer.new()
	docs_box.add_theme_constant_override("separation", 6)
	col.add_child(docs_box)


func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = Game.ui.mono if bold else Game.ui.sans
	ls.font_size = size
	ls.font_color = color
	l.label_settings = ls
	return l


func _separator() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.12)
	r.custom_minimum_size = Vector2(0, 1)
	return r


func can_open() -> bool:
	return Game.playing and Game.level != null and Game.level.has_method("inventory") \
		and not get_tree().paused and not Game.ui.document_open and not Game.ui.death_menu.visible


func toggle() -> void:
	if is_open:
		close()
	elif can_open():
		open()


func open() -> void:
	is_open = true
	get_tree().paused = true
	Game.capture_mouse(false)
	Sound.play("paper", -14.0, 1.4, "UI")
	_refresh()
	root.visible = true


func close() -> void:
	is_open = false
	root.visible = false
	get_tree().paused = false
	Game.capture_mouse(true)


func _refresh() -> void:
	for c in grid.get_children():
		c.queue_free()
	_items = Game.level.inventory()
	empty_label.visible = _items.is_empty()
	for i in _items.size():
		grid.add_child(_slot(i))
	_selected = clampi(_selected, 0, maxi(_items.size() - 1, 0))
	_show_detail()
	objective_label.text = ("Objectif : " + Game.hud._objective_text) if Game.hud._objective_text != "" else ""
	for c in docs_box.get_children():
		c.queue_free()
	var docs: Array = Game.level.documents
	docs_title.visible = not docs.is_empty()
	for d in docs:
		var b := Button.new()
		b.theme = Game.ui.ui_theme
		b.text = "▤  " + str(d["title"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 20)
		var doc: Dictionary = d
		b.pressed.connect(func() -> void:
			root.visible = false
			await Game.ui.show_document(doc["text"], doc.get("style", "paper"))
			if is_open:
				root.visible = true)
		docs_box.add_child(b)


func _slot(i: int) -> Control:
	var it: Dictionary = _items[i]
	var b := Button.new()
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	var sel := sb.duplicate() as StyleBoxFlat
	sel.bg_color = Color(1, 1, 1, 0.1)
	sel.border_color = Color(1.0, 0.82, 0.48, 0.9)
	b.add_theme_stylebox_override("normal", sel if i == _selected else sb)
	b.add_theme_stylebox_override("hover", sel)
	b.add_theme_stylebox_override("pressed", sel)
	b.mouse_entered.connect(func() -> void:
		_selected = i
		_show_detail())
	var icon := ItemIcon.new()
	icon.kind = str(it.get("icon", it["id"]))
	icon.position = Vector2(28, 18)
	icon.size = Vector2(SLOT.x - 56, 112)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	var name := _label(str(it["name"]), 17, INK)
	name.position = Vector2(12, 138)
	name.size = Vector2(SLOT.x - 24, 24)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(name)
	if int(it.get("count", 1)) > 1:
		var n := _label("×%d" % int(it["count"]), 20, Color(1.0, 0.82, 0.48), true)
		n.position = Vector2(SLOT.x - 58, 8)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(n)
	return b


func _show_detail() -> void:
	if _items.is_empty():
		detail_name.text = ""
		detail_desc.text = ""
		return
	var it: Dictionary = _items[_selected]
	detail_name.text = str(it["name"]) + ("  ×%d" % int(it["count"]) if int(it.get("count", 1)) > 1 else "")
	detail_desc.text = str(it.get("desc", ""))
	for k in grid.get_child_count():
		var b := grid.get_child(k) as Button
		var st := b.get_theme_stylebox("hover")
		b.add_theme_stylebox_override("normal", st if k == _selected else _plain_style())


func _plain_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	return sb


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if Game.ui.document_open:
		return
	if event.is_action_pressed("inventory") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
		return
	# flèches : changer d'objet
	if event is InputEventKey and event.pressed and not _items.is_empty():
		var k := (event as InputEventKey).physical_keycode
		var step := {KEY_RIGHT: 1, KEY_D: 1, KEY_LEFT: -1, KEY_A: -1, KEY_DOWN: 4, KEY_S: 4, KEY_UP: -4, KEY_W: -4}
		if step.has(k):
			_selected = clampi(_selected + int(step[k]), 0, _items.size() - 1)
			_show_detail()
			get_viewport().set_input_as_handled()


## Icône d'objet dessinée au trait (style carnet de terrain, sans image).
class ItemIcon:
	extends Control
	var kind := ""

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var ink := Color(0.88, 0.87, 0.82)
		var soft := Color(0.88, 0.87, 0.82, 0.35)
		var w := 3.0
		match kind:
			"flashlight":
				var body := PackedVector2Array([c + Vector2(-46, -9), c + Vector2(14, -9), c + Vector2(14, 9), c + Vector2(-46, 9), c + Vector2(-46, -9)])
				draw_polyline(body, ink, w, true)
				draw_polyline(PackedVector2Array([c + Vector2(14, -9), c + Vector2(30, -17), c + Vector2(30, 17), c + Vector2(14, 9)]), ink, w, true)
				draw_line(c + Vector2(-20, -9), c + Vector2(-20, -14), ink, w)
				for a in [-0.35, 0.0, 0.35]:
					draw_line(c + Vector2(38, 0) + Vector2(cos(a), sin(a)) * 4.0, c + Vector2(38, 0) + Vector2(cos(a), sin(a)) * 22.0, soft, 2.0)
			"bottle":
				var pts := PackedVector2Array([c + Vector2(-5, -46), c + Vector2(5, -46), c + Vector2(5, -24), c + Vector2(16, -10), c + Vector2(16, 44),
					c + Vector2(-16, 44), c + Vector2(-16, -10), c + Vector2(-5, -24), c + Vector2(-5, -46)])
				draw_polyline(pts, ink, w, true)
				draw_rect(Rect2(c + Vector2(-11, 2), Vector2(22, 20)), soft, false, 2.0)
				draw_line(c + Vector2(-7, -36), c + Vector2(7, -36), soft, 2.0)
			"keys":
				draw_arc(c + Vector2(-22, -14), 16, 0, TAU, 32, ink, w, true)
				for k in 2:
					var o := c + Vector2(-8 + k * 6, -4 + k * 10)
					var d := Vector2(1, 0.62 + k * 0.25).normalized()
					var tip := o + d * 52
					draw_line(o, tip, ink, w)
					draw_arc(o - d * 6, 7, 0, TAU, 16, ink, 2.5, true)
					var n := Vector2(-d.y, d.x)
					draw_line(tip - d * 6, tip - d * 6 + n * 8, ink, w)
					draw_line(tip - d * 16, tip - d * 16 + n * 6, ink, w)
			"bar":
				draw_line(c + Vector2(-48, 38), c + Vector2(46, -40), ink, 6.0)
				draw_line(c + Vector2(30, -30), c + Vector2(40, -20), soft, 2.0)
				for k in 4:
					var p := c + Vector2(-30 + k * 18, 23 - k * 15.5)
					draw_circle(p + Vector2(4, 4), 2.0, soft)
			"fuse":
				draw_rect(Rect2(c + Vector2(-28, -12), Vector2(56, 24)), ink, false, w)
				for sx in [-1.0, 1.0]:
					draw_rect(Rect2(c + Vector2(sx * 36 - 8, -15), Vector2(16, 30)), ink, false, w)
				draw_line(c + Vector2(-20, 0), c + Vector2(20, 0), soft, 2.0)
			"cutters":
				var pivot := c + Vector2(6, -14)
				draw_line(pivot, c + Vector2(-34, 44), ink, 5.0)
				draw_line(pivot, c + Vector2(-8, 46), ink, 5.0)
				draw_polyline(PackedVector2Array([pivot, c + Vector2(30, -46), c + Vector2(38, -36), pivot]), ink, w, true)
				draw_polyline(PackedVector2Array([pivot, c + Vector2(40, -30), c + Vector2(34, -20), pivot]), ink, w, true)
				draw_circle(pivot, 4.0, ink)
			"phone":
				var r := Rect2(c + Vector2(-20, -44), Vector2(40, 88))
				draw_rect(r, ink, false, w)
				draw_rect(Rect2(r.position + Vector2(5, 9), Vector2(30, 64)), soft, false, 2.0)
				draw_line(c + Vector2(-5, 37), c + Vector2(5, 37), ink, 2.0)
			_:
				draw_rect(Rect2(c - Vector2(24, 24), Vector2(48, 48)), ink, false, w)
