extends Node2D

var gymnast: StickGymnast
var status: Label

func _ready() -> void:
	queue_redraw()
	gymnast = StickGymnast.new()
	add_child(gymnast)
	_build_play_overlay()

func _build_play_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_left = 180
	status.offset_right = -180
	status.offset_top = -42
	status.offset_bottom = -14
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.text = "NORMAL GIANT     ·     SPACE  PAUSE     ·     R  RESTART     ·     − / +  SPEED"
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color("#b5c4d8"))
	layer.add_child(status)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_catch"):
		gymnast.playing = not gymnast.playing
		status.text = "PAUSED — SPACE TO PLAY" if not gymnast.playing else "SPACE  PAUSE     R  RESTART     − / +  SPEED"
	elif event.is_action_pressed("restart"):
		gymnast.reset()
		status.text = "SPACE  PAUSE     R  RESTART     − / +  SPEED"
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD]:
			gymnast.speed = minf(2.0, gymnast.speed + 0.1)
			status.text = "SPEED  %0.1f×" % gymnast.speed
		elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			gymnast.speed = maxf(0.25, gymnast.speed - 0.1)
			status.text = "SPEED  %0.1f×" % gymnast.speed

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1000, 610), Color("#0e1a2b"))
