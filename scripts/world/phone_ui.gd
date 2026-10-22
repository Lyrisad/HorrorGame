class_name PhoneUI
extends SubViewport
## Écran du téléphone de Théo (rendu dans une texture) :
## écran verrouillé avec les notifications (la plus récente en haut),
## conversation façon messagerie (bulles, « en train d'écrire… », barre de saisie toujours visible :
## un appui dessus fait monter le clavier, qui tape la réponse),
## écran d'appel. Toutes les méthodes « longues » peuvent être attendues avec `await`.

const W := 540
const H := 1080
const BUBBLE_IN := Color(0.17, 0.17, 0.19)
const BUBBLE_OUT := Color(0.04, 0.52, 1.0)
const HEADER_H := 216.0
const BAR_H := 92.0
const KB_H := 360.0
const HOME_H := 34.0  ## marge de la barre d'accueil quand le clavier est fermé
const FIELD_FONT := 34

var sans: SystemFont
var sans_bold: SystemFont
var sans_light: SystemFont
var lock_root: Control
var chat_root: Control
var call_root: Control
var notif_box: VBoxContainer
var lock_clock: Label
var status_time: Array[Label] = []
var chat_name: Label
var chat_avatar: PanelContainer
var chat_box: VBoxContainer
var chat_clip: Control
var kb_root: Control
var input_label: Label
var bar: Control
var field: PanelContainer
var caret: ColorRect
var mic: Control
var send_btn: PanelContainer
var touch: Panel
var keys := {}
var _kb_t := 0.0  ## 0 = clavier fermé, 1 = ouvert (animé)
var _kb_target := 0.0
var _focused := false
var _blink := 0.0
var call_name: Label
var call_status: Label
var call_avatar: PanelContainer
var threads := {}  ## contact → [[texte, sortant], ...]
var current_chat := ""
var _call_t := 0.0
var _calling := false

const COLORS := {"Max": Color(0.85, 0.45, 0.2), "Inès": Color(0.7, 0.3, 0.75), "Karim": Color(0.2, 0.6, 0.5)}


func _ready() -> void:
	size = Vector2i(W, H)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	transparent_bg = false
	var emoji := SystemFont.new()
	emoji.font_names = PackedStringArray(["Segoe UI Emoji", "Noto Color Emoji", "Apple Color Emoji"])
	sans = _font(400, emoji)
	sans_bold = _font(700, emoji)
	sans_light = _font(300, emoji)
	_build_lock()
	_build_chat()
	_build_call()
	show_screen("lock")


func _font(weight: int, fallback: Font) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Arial"])
	f.font_weight = weight
	f.fallbacks = [fallback]
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


func _label(text: String, font: Font, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _rounded(color: Color, radius: int, margin := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


func _full(c: Control) -> Control:
	c.position = Vector2.ZERO
	c.size = Vector2(W, H)
	return c


func _status_bar(parent: Control, dark := false) -> void:
	var col := Color(0.05, 0.05, 0.06) if dark else Color.WHITE
	var t := _label("23:41", sans_bold, 30, col)
	t.position = Vector2(42, 16)
	parent.add_child(t)
	status_time.append(t)
	var right := _label("4G", sans_bold, 24, col)
	right.position = Vector2(W - 172, 20)
	parent.add_child(right)
	for i in 4:
		var bar := ColorRect.new()
		bar.color = col
		var hh := 8.0 + i * 5.0
		bar.position = Vector2(W - 132 + i * 10, 44 - hh)
		bar.size = Vector2(7, hh)
		parent.add_child(bar)
	var batt := Panel.new()
	var bs := StyleBoxFlat.new()
	bs.draw_center = false
	bs.border_color = col
	bs.set_border_width_all(3)
	bs.set_corner_radius_all(6)
	batt.add_theme_stylebox_override("panel", bs)
	batt.position = Vector2(W - 84, 22)
	batt.size = Vector2(46, 24)
	parent.add_child(batt)
	var lvl := ColorRect.new()
	lvl.color = col
	lvl.position = Vector2(W - 79, 27)
	lvl.size = Vector2(22, 14)
	parent.add_child(lvl)


# ================================================================== écran verrouillé
func _build_lock() -> void:
	lock_root = _full(Control.new())
	add_child(lock_root)
	var wall := TextureRect.new()
	wall.texture = load("res://assets/gen/phone_wallpaper.png")
	wall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_full(wall)
	lock_root.add_child(wall)
	_status_bar(lock_root)
	var lock_icon := _label("🔒", sans, 30)
	lock_icon.position = Vector2(W * 0.5 - 16, 70)
	lock_root.add_child(lock_icon)
	lock_clock = _label("23:41", sans_light, 168)
	lock_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_clock.position = Vector2(0, 100)
	lock_clock.size = Vector2(W, 200)
	lock_root.add_child(lock_clock)
	var date := _label("samedi 14 novembre", sans, 38, Color(1, 1, 1, 0.9))
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date.position = Vector2(0, 312)
	date.size = Vector2(W, 50)
	lock_root.add_child(date)
	notif_box = VBoxContainer.new()
	notif_box.position = Vector2(22, 400)
	notif_box.size = Vector2(W - 44, 640)
	notif_box.add_theme_constant_override("separation", 14)
	lock_root.add_child(notif_box)


## Nouvelle notification, ajoutée EN HAUT de la pile.
func notify(sender: String, text: String) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _rounded(Color(0.12, 0.12, 0.14, 0.86), 30, 22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/gen/icon_messages.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.custom_minimum_size = Vector2(64, 64)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var who := _label(sender, sans_bold, 40)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	head.add_child(_label("maintenant", sans, 30, Color(1, 1, 1, 0.55)))
	var body := _label(text, sans, 38, Color(1, 1, 1, 0.92))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 360
	col.add_child(body)
	notif_box.add_child(card)
	notif_box.move_child(card, 0)
	# les anciennes notifications passent en « il y a x min »
	for i in range(1, notif_box.get_child_count()):
		var old := notif_box.get_child(i)
		var lbl := (old.get_child(0).get_child(1).get_child(0) as HBoxContainer).get_child(1) as Label
		if lbl.text == "maintenant":
			lbl.text = "il y a 1 min"
	while notif_box.get_child_count() > 4:
		notif_box.get_child(notif_box.get_child_count() - 1).queue_free()
	card.modulate.a = 0.0
	card.pivot_offset = Vector2((W - 44) * 0.5, 60)
	card.scale = Vector2(0.9, 0.9)
	var tw := create_tween().set_parallel()
	tw.tween_property(card, "modulate:a", 1.0, 0.35)
	tw.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_add_to_thread(sender, text, false)


func clear_notifications() -> void:
	for c in notif_box.get_children():
		c.queue_free()


# ================================================================== conversation
func _build_chat() -> void:
	chat_root = _full(Control.new())
	add_child(chat_root)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0)
	_full(bg)
	chat_root.add_child(bg)
	_status_bar(chat_root)
	# en-tête : retour, avatar, nom
	var header := ColorRect.new()
	header.color = Color(0.08, 0.08, 0.09)
	header.position = Vector2(0, 64)
	header.size = Vector2(W, 150)
	chat_root.add_child(header)
	var back := _label("‹", sans_light, 80, BUBBLE_OUT)
	back.position = Vector2(18, 64)
	chat_root.add_child(back)
	chat_avatar = _avatar("M", 76)
	chat_avatar.position = Vector2(W * 0.5 - 38, 74)
	chat_root.add_child(chat_avatar)
	chat_name = _label("Max", sans, 34)
	chat_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chat_name.position = Vector2(0, 160)
	chat_name.size = Vector2(W, 40)
	chat_root.add_child(chat_name)
	# fil des messages, ancré en bas (au-dessus du clavier quand il est affiché)
	chat_clip = Control.new()
	chat_clip.clip_contents = true
	chat_clip.position = Vector2(0, HEADER_H)
	chat_clip.size = Vector2(W, H - HEADER_H - HOME_H - BAR_H)
	chat_root.add_child(chat_clip)
	chat_box = VBoxContainer.new()
	chat_box.add_theme_constant_override("separation", 12)
	chat_box.size = Vector2(W, 0)
	chat_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat_box.anchor_top = 1.0
	chat_box.anchor_bottom = 1.0
	chat_box.anchor_right = 1.0
	chat_box.offset_left = 20
	chat_box.offset_right = -20
	chat_box.offset_top = -12
	chat_box.offset_bottom = -12
	chat_clip.add_child(chat_box)
	# clavier AZERTY : caché sous l'écran, il monte quand on touche le champ de saisie
	kb_root = Control.new()
	kb_root.size = Vector2(W, KB_H)
	chat_root.add_child(kb_root)
	var kb := ColorRect.new()
	kb.color = Color(0.13, 0.13, 0.14)
	kb.size = Vector2(W, KB_H)
	kb_root.add_child(kb)
	var rows := ["AZERTYUIOP", "QSDFGHJKLM", "WXCVBN'"]
	var kw := 48.0
	var gap := 5.0
	for r in rows.size():
		var row: String = rows[r]
		var total := row.length() * kw + (row.length() - 1) * gap
		var x0 := (W - total) * 0.5
		for i in row.length():
			var k := _key(row[i], Vector2(x0 + i * (kw + gap), 14 + r * 72), Vector2(kw, 62))
			kb_root.add_child(k)
			keys[row[i]] = k
	var dark := Color(0.24, 0.24, 0.26)
	kb_root.add_child(_key("⇧", Vector2(8, 158), Vector2(62, 62), dark))
	kb_root.add_child(_key("⌫", Vector2(W - 70, 158), Vector2(62, 62), dark))
	kb_root.add_child(_key("123", Vector2(8, 230), Vector2(92, 62), dark))
	var space := _key("espace", Vector2(108, 230), Vector2(W - 216 - 8, 62))
	kb_root.add_child(space)
	keys[" "] = space
	kb_root.add_child(_key("retour", Vector2(W - 100, 230), Vector2(92, 62), dark))
	# barre de saisie, toujours là sous les messages (comme une vraie messagerie)
	bar = Control.new()
	bar.size = Vector2(W, BAR_H)
	chat_root.add_child(bar)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.04, 0.04, 0.045)
	bar_bg.size = Vector2(W, BAR_H)
	bar.add_child(bar_bg)
	var plus := _avatar("+", 56, Color(0.18, 0.18, 0.2))
	(plus.get_child(0) as Label).add_theme_font_override("font", sans_light)
	(plus.get_child(0) as Label).add_theme_font_size_override("font_size", 46)
	plus.position = Vector2(16, 18)
	bar.add_child(plus)
	field = PanelContainer.new()
	var fs := _rounded(Color(0.07, 0.07, 0.08), 30)
	fs.border_color = Color(0.26, 0.26, 0.28)
	fs.set_border_width_all(2)
	field.add_theme_stylebox_override("panel", fs)
	field.position = Vector2(86, 16)
	field.size = Vector2(W - 86 - 16, 60)
	bar.add_child(field)
	var inner := Control.new()
	inner.clip_contents = true
	field.add_child(inner)
	input_label = _label("Message", sans, FIELD_FONT, Color(1, 1, 1, 0.35))
	input_label.position = Vector2(24, 8)
	input_label.size = Vector2(W - 86 - 16 - 24 - 70, 44)
	inner.add_child(input_label)
	caret = ColorRect.new()
	caret.color = BUBBLE_OUT
	caret.size = Vector2(3, 38)
	caret.visible = false
	inner.add_child(caret)
	# micro (champ vide) / bouton d'envoi bleu (dès qu'il y a du texte)
	mic = Control.new()
	mic.position = Vector2(W - 86 - 16 - 50, 12)
	inner.add_child(mic)
	var grey := Color(0.55, 0.55, 0.58)
	var capsule := Panel.new()
	capsule.add_theme_stylebox_override("panel", _rounded(grey, 8))
	capsule.position = Vector2(8, 0)
	capsule.size = Vector2(16, 24)
	mic.add_child(capsule)
	var cup := Panel.new()
	var cs := StyleBoxFlat.new()
	cs.draw_center = false
	cs.border_color = grey
	cs.border_width_left = 3
	cs.border_width_right = 3
	cs.border_width_bottom = 3
	cs.set_corner_radius_all(12)
	cup.add_theme_stylebox_override("panel", cs)
	cup.position = Vector2(2, 10)
	cup.size = Vector2(28, 22)
	mic.add_child(cup)
	var stem := ColorRect.new()
	stem.color = grey
	stem.position = Vector2(14.5, 31)
	stem.size = Vector2(3, 6)
	mic.add_child(stem)
	send_btn = _avatar("↑", 48, BUBBLE_OUT)
	(send_btn.get_child(0) as Label).add_theme_font_size_override("font_size", 30)
	send_btn.position = Vector2(W - 86 - 16 - 56, 6)
	send_btn.visible = false
	inner.add_child(send_btn)
	keys["⏎"] = send_btn
	# doigt qui touche l'écran (cercle gris qui s'estompe)
	touch = Panel.new()
	touch.add_theme_stylebox_override("panel", _rounded(Color(1, 1, 1, 0.22), 40))
	touch.size = Vector2(80, 80)
	touch.visible = false
	chat_root.add_child(touch)
	# barre d'accueil (geste) en bas de l'écran
	var home := Panel.new()
	home.add_theme_stylebox_override("panel", _rounded(Color(1, 1, 1, 0.85), 4))
	home.position = Vector2(W * 0.5 - 70, H - 16)
	home.size = Vector2(140, 7)
	chat_root.add_child(home)
	_layout_kb()


## Place clavier, barre de saisie et fil des messages selon l'ouverture du clavier.
func _layout_kb() -> void:
	var k := ease(_kb_t, -2.2)  # montée rapide puis amortie, comme le vrai clavier
	kb_root.position.y = H - KB_H * k
	bar.position.y = lerpf(H - HOME_H - BAR_H, H - KB_H - BAR_H, k)
	chat_clip.size.y = bar.position.y - HEADER_H


func _key(text: String, pos: Vector2, sz: Vector2, color := Color(0.36, 0.36, 0.38)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _rounded(color, 10))
	p.position = pos
	p.size = sz
	var l := _label(text, sans, 30 if text.length() == 1 else 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _avatar(initial: String, d: float, color := Color(0.4, 0.4, 0.45)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _rounded(color, int(d * 0.5)))
	p.custom_minimum_size = Vector2(d, d)
	p.size = Vector2(d, d)
	var l := _label(initial, sans_bold, int(d * 0.45))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _add_to_thread(contact: String, text: String, outgoing: bool) -> void:
	if not threads.has(contact):
		threads[contact] = []
	threads[contact].append([text, outgoing])
	if current_chat == contact and chat_root.visible:
		_bubble(text, outgoing, true)


func _bubble(text: String, outgoing: bool, animate: bool) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END if outgoing else BoxContainer.ALIGNMENT_BEGIN
	var b := PanelContainer.new()
	var sb := _rounded(BUBBLE_OUT if outgoing else BUBBLE_IN, 34)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	b.add_theme_stylebox_override("panel", sb)
	var l := _label(text, sans, 44)
	var tw_size := sans.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
	if tw_size > 380.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 380
	b.add_child(l)
	row.add_child(b)
	chat_box.add_child(row)
	while chat_box.get_child_count() > 7:
		chat_box.get_child(0).free()
	if animate:
		row.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(row, "modulate:a", 1.0, 0.25)
	return row


## Ouvre la conversation avec `contact` (déverrouillage).
func open_chat(contact: String) -> void:
	current_chat = contact
	for c in chat_box.get_children():
		c.free()
	chat_name.text = contact
	(chat_avatar.get_child(0) as Label).text = contact.substr(0, 1)
	chat_avatar.add_theme_stylebox_override("panel", _rounded(COLORS.get(contact, Color(0.4, 0.4, 0.45)), 38))
	for m in threads.get(contact, []):
		_bubble(m[0], m[1], false)
	_set_field("")
	_focused = false
	_kb_target = 0.0
	_kb_t = 0.0
	_layout_kb()
	show_screen("chat")


## Message entrant dans la conversation ouverte : « … » puis la bulle.
func receive(contact: String, text: String, typing_time := 1.2) -> void:
	if current_chat == contact and chat_root.visible:
		var dots := _bubble("•  •  •", false, true)
		var lbl := (dots.get_child(0) as PanelContainer).get_child(0) as Label
		var t := 0.0
		while t < typing_time:
			await get_tree().process_frame
			t += get_process_delta_time()
			lbl.modulate.a = 0.45 + 0.45 * sin(t * 9.0)
		dots.free()
	_add_to_thread(contact, text, false)


## Théo touche le champ de saisie, le clavier monte, il tape la réponse lettre par lettre puis l'envoie.
func type_reply(text: String, cps := 9.0) -> void:
	await _tap(bar.position + field.position + Vector2(150, 30))
	_focused = true
	_blink = 0.0
	_kb_target = 1.0
	await get_tree().create_timer(0.45, false).timeout
	var typed := ""
	for ch in text:
		typed += ch
		_set_field(typed)
		_press(ch.to_upper())
		Sound.play("phone_tap", -20.0, randf_range(0.9, 1.15), "UI")
		await get_tree().create_timer(1.0 / cps * randf_range(0.6, 1.5), false).timeout
	await get_tree().create_timer(0.35, false).timeout
	_press("⏎")
	Sound.play("message_sent", -16.0, 1.0, "UI")
	_set_field("")
	_add_to_thread(current_chat, text, true)
	await get_tree().create_timer(0.8, false).timeout
	# il range le clavier (le champ reste là, vide)
	_focused = false
	_kb_target = 0.0


## Texte du champ : indication grise quand il est vide, sinon la fin du texte (le champ défile).
func _set_field(t: String) -> void:
	if t == "":
		input_label.text = "Message"
		input_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	else:
		var shown := t
		while shown.length() > 1 and sans.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, FIELD_FONT).x > input_label.size.x - 8.0:
			shown = shown.substr(1)
		input_label.text = shown
		input_label.add_theme_color_override("font_color", Color.WHITE)
	mic.visible = t == ""
	send_btn.visible = t != ""
	var w := 0.0 if t == "" else sans.get_string_size(input_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FIELD_FONT).x
	caret.position = Vector2(input_label.position.x + w + 2.0, 11)


## Appui du doigt à l'écran (petit cercle qui s'estompe).
func _tap(pos: Vector2) -> void:
	touch.position = pos - touch.size * 0.5
	touch.pivot_offset = touch.size * 0.5
	touch.scale = Vector2(0.7, 0.7)
	touch.modulate.a = 1.0
	touch.visible = true
	Sound.play("phone_tap", -18.0, 0.8, "UI")
	var tw := create_tween()
	tw.tween_property(touch, "scale", Vector2(1.1, 1.1), 0.25)
	tw.parallel().tween_property(touch, "modulate:a", 0.0, 0.35)
	await tw.finished
	touch.visible = false


func _press(k: String) -> void:
	var key := keys.get(k) as PanelContainer
	if key == null:
		return
	var sb := key.get_theme_stylebox("panel") as StyleBoxFlat
	var base := sb.bg_color
	var radius := sb.corner_radius_top_left
	key.add_theme_stylebox_override("panel", _rounded(base.lightened(0.35), radius))
	await get_tree().create_timer(0.09, false).timeout
	if is_instance_valid(key):
		key.add_theme_stylebox_override("panel", _rounded(base, radius))


# ================================================================== appel
func _build_call() -> void:
	call_root = _full(Control.new())
	add_child(call_root)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/gen/phone_wallpaper.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.modulate = Color(0.35, 0.35, 0.4)
	_full(bg)
	call_root.add_child(bg)
	_status_bar(call_root)
	call_avatar = _avatar("K", 190)
	call_avatar.position = Vector2(W * 0.5 - 95, 190)
	call_root.add_child(call_avatar)
	call_name = _label("Karim", sans, 62)
	call_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	call_name.position = Vector2(0, 410)
	call_name.size = Vector2(W, 80)
	call_root.add_child(call_name)
	call_status = _label("Appel…", sans, 34, Color(1, 1, 1, 0.7))
	call_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	call_status.position = Vector2(0, 492)
	call_status.size = Vector2(W, 50)
	call_root.add_child(call_status)
	# boutons d'appel : pictogrammes (assets/gen/icon_*.png, Material Icons)
	var buttons := [["silence", "icon_mute"], ["clavier", "icon_keypad"], ["haut-parleur", "icon_speaker"]]
	for i in 3:
		var b := _avatar("", 110, Color(1, 1, 1, 0.18))
		b.position = Vector2(60 + i * 150, 640)
		call_root.add_child(b)
		call_root.add_child(_icon(buttons[i][1], Vector2(60 + i * 150 + 55, 695), 56))
		var l := _label(buttons[i][0], sans, 24, Color(1, 1, 1, 0.8))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(40 + i * 150, 758)
		l.size = Vector2(150, 30)
		call_root.add_child(l)
	var hang := _avatar("", 130, Color(0.92, 0.25, 0.2))
	hang.position = Vector2(W * 0.5 - 65, 860)
	call_root.add_child(hang)
	call_root.add_child(_icon("icon_hangup", Vector2(W * 0.5, 925), 74))


## Pictogramme blanc centré sur `center`.
func _icon(icon_name: String, center: Vector2, px: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://assets/gen/%s.png" % icon_name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size = Vector2(px, px)
	t.position = center - t.size * 0.5
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func call_contact(contact: String) -> void:
	call_name.text = contact
	(call_avatar.get_child(0) as Label).text = contact.substr(0, 1)
	call_avatar.add_theme_stylebox_override("panel", _rounded(COLORS.get(contact, Color(0.4, 0.4, 0.45)), 95))
	call_status.text = "Appel…"
	_calling = true
	show_screen("call")


func set_call_status(text: String) -> void:
	call_status.text = text
	_calling = false


# ================================================================== commun
func show_screen(which: String) -> void:
	lock_root.visible = which == "lock"
	chat_root.visible = which == "chat"
	call_root.visible = which == "call"


func set_time(text: String) -> void:
	lock_clock.text = text
	for l in status_time:
		l.text = text


func _process(delta: float) -> void:
	if not is_equal_approx(_kb_t, _kb_target):
		_kb_t = move_toward(_kb_t, _kb_target, delta / 0.28)
		_layout_kb()
	# curseur qui clignote dans le champ quand il a le « focus »
	_blink += delta
	caret.visible = _focused and fmod(_blink, 1.0) < 0.55
	if _calling:
		_call_t += delta
		call_status.text = "Appel" + ".".repeat(1 + int(_call_t * 2.0) % 3)
