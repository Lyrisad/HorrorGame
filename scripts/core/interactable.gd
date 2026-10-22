class_name Interactable
extends Area3D
## Zone avec laquelle le joueur peut interagir en la regardant ([E]).
## `hold_time` > 0 : il faut maintenir la touche (couper une chaîne...).

signal used

var prompt := "Interagir"
var hold_time := 0.0
var enabled := true
var on_use: Callable


static func create(parent: Node, pos: Vector3, size: Vector3, text: String, cb: Callable, hold := 0.0) -> Interactable:
	var it := Interactable.new()
	it.prompt = text
	it.on_use = cb
	it.hold_time = hold
	it.collision_layer = 4
	it.collision_mask = 0
	it.monitoring = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	it.add_child(shape)
	parent.add_child(it)
	it.position = pos
	return it


func trigger() -> void:
	if not enabled:
		return
	used.emit()
	if on_use.is_valid():
		on_use.call()


func disable() -> void:
	enabled = false
	collision_layer = 0
