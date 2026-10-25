class_name PauseMenu
extends CanvasLayer
## Esc / Start: pauses the match, frees the mouse, offers look settings.

signal quit_requested
signal restart_requested


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sens_label := Label.new()
	sens_label.text = "Mouse sensitivity"
	box.add_child(sens_label)
	var sens := HSlider.new()
	sens.min_value = 0.02
	sens.max_value = 0.4
	sens.step = 0.01
	sens.value = GameConfig.mouse_sensitivity
	sens.value_changed.connect(func(v: float) -> void: GameConfig.mouse_sensitivity = v)
	box.add_child(sens)
	var inv := CheckBox.new()
	inv.text = "Invert look"
	inv.button_pressed = GameConfig.invert_y
	inv.toggled.connect(func(on: bool) -> void: GameConfig.invert_y = on)
	box.add_child(inv)
	for entry in [["Resume", _close], ["Restart match", func() -> void: _leave(restart_requested)],
			["Quit to menu", func() -> void: _leave(quit_requested)], ["Quit game", func() -> void: get_tree().quit()]]:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(entry[1])
		box.add_child(b)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if visible:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()


func _open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _leave(sig: Signal) -> void:
	visible = false
	get_tree().paused = false
	sig.emit()
