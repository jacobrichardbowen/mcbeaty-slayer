class_name InputSetup
extends RefCounted
## Registers the input map at startup so bindings live in code.
## Keyboard/mouse follows Halo PC habits; the pad follows the Halo 2 Xbox
## layout (A jump, B melee, X reload / hold to man the gun, RT fire, L3 crouch).


static func register() -> void:
	_keys("move_forward", [KEY_W, KEY_UP])
	_keys("move_back", [KEY_S, KEY_DOWN])
	_keys("move_left", [KEY_A, KEY_LEFT])
	_keys("move_right", [KEY_D, KEY_RIGHT])
	_keys("jump", [KEY_SPACE])
	_keys("crouch", [KEY_CTRL, KEY_C])
	_keys("reload", [KEY_R])
	_keys("melee", [KEY_F, KEY_V])
	_keys("action", [KEY_E])
	_keys("scoreboard", [KEY_TAB])
	_keys("pause", [KEY_ESCAPE, KEY_P])
	_keys("toggle_fullscreen", [KEY_F11])
	var alt_enter := InputEventKey.new()
	alt_enter.physical_keycode = KEY_ENTER
	alt_enter.alt_pressed = true
	InputMap.action_add_event("toggle_fullscreen", alt_enter)
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_mouse("melee", MOUSE_BUTTON_MIDDLE)

	_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_button("jump", JOY_BUTTON_A)
	_button("melee", JOY_BUTTON_B)
	_button("reload", JOY_BUTTON_X)
	_button("action", JOY_BUTTON_X)
	_button("crouch", JOY_BUTTON_LEFT_STICK)
	_button("pause", JOY_BUTTON_START)
	_button("scoreboard", JOY_BUTTON_BACK)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


static func _keys(action: String, keys: Array) -> void:
	_ensure(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


static func _mouse(action: String, button: MouseButton) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


static func _axis(action: String, axis: JoyAxis, value: float) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


static func _button(action: String, button: JoyButton) -> void:
	_ensure(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
