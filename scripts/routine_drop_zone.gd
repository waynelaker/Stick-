class_name StickRoutineDropZone
extends Control

signal skill_dropped(payload: Dictionary, insertion_index: int)

var insertion_index: int = 0
var validator: Callable
var hovering := false

func setup(index: int, validation: Callable) -> void:
	insertion_index = index
	validator = validation
	custom_minimum_size = Vector2(24, 104)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	var valid: bool = data is Dictionary and str(data.get("kind", "")) == "stick_skill" and validator.is_valid() and bool(validator.call(data, insertion_index))
	hovering = valid
	queue_redraw()
	return valid

func _drop_data(_position: Vector2, data: Variant) -> void:
	hovering = false
	skill_dropped.emit(data, insertion_index)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hovering:
		hovering = false
		queue_redraw()

func _draw() -> void:
	var color := Color("#72f1b8") if hovering else Color("#385c7c")
	var width := 5.0 if hovering else 2.0
	draw_line(Vector2(size.x / 2.0, 10.0), Vector2(size.x / 2.0, size.y - 10.0), color, width, true)
