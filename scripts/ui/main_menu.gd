class_name MainMenu
extends CanvasLayer
## Pre-game lobby: match options and controls.

signal start_requested

const CONTROLS := """Mouse / keyboard: WASD move, mouse look, Left click fire, Right click zoom (rifle),
Space jump, Ctrl or C crouch, F / V / middle click melee, R reload, hold E man the Maxim,
Tab scoreboard, Esc pause, F11 fullscreen. While dead: Q, wheel, 1 or 2 picks your weapon.
Gamepad (Halo 2 layout): sticks move/look, RT fire, R3 zoom, A jump, B melee,
X reload / hold X to man the Maxim, L3 crouch, Y switch weapon (while dead), Back scoreboard."""


func _ready() -> void:
	layer = 10
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(620, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "TOWER OF POWER"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Ascension  ·  Team Slayer  ·  Shotguns  ·  No Shields  ·  Whites vs Reds"
	sub.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)

	var side := OptionButton.new()
	side.add_item("Nobody: both sides fight for it")
	side.add_item("Whites (you): defend it")
	side.add_item("Reds: you storm it")
	side.selected = GameConfig.bunker_start + 1
	side.item_selected.connect(func(i: int) -> void: GameConfig.bunker_start = i - 1)
	_row(grid, "Bunker starts with", side)
	var gun := OptionButton.new()
	gun.add_item("Shotgun")
	gun.add_item("Mosin-Nagant (semi-auto rifle)")
	gun.selected = 1 if GameConfig.player_loadout == "rifle" else 0
	gun.item_selected.connect(func(i: int) -> void: GameConfig.player_loadout = "rifle" if i == 1 else "shotgun")
	_row(grid, "Your weapon", gun)
	var most := GameConfig.MAX_PER_TEAM
	_row(grid, "Red bots", _spin(1, most, GameConfig.red_bots, func(v: float) -> void: GameConfig.red_bots = int(v)))
	_row(grid, "White bots (your side)", _spin(0, most - 1, GameConfig.white_bots, func(v: float) -> void: GameConfig.white_bots = int(v)))
	_row(grid, "Score limit", _spin(5, 250, GameConfig.score_limit, func(v: float) -> void: GameConfig.score_limit = int(v), 5))
	_row(grid, "Mouse sensitivity", _slider(0.02, 0.4, GameConfig.mouse_sensitivity, func(v: float) -> void: GameConfig.mouse_sensitivity = v))
	_row(grid, "Field of view (Halo 2 = 70)", _slider(60, 100, GameConfig.fov, func(v: float) -> void: GameConfig.fov = v, 1.0))
	var inv := CheckBox.new()
	inv.button_pressed = GameConfig.invert_y
	inv.toggled.connect(func(on: bool) -> void: GameConfig.invert_y = on)
	_row(grid, "Invert look", inv)

	box.add_child(HSeparator.new())
	var help := Label.new()
	help.text = CONTROLS
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	box.add_child(help)

	var start := Button.new()
	start.text = "DEPLOY"
	start.custom_minimum_size = Vector2(0, 52)
	start.add_theme_font_size_override("font_size", 24)
	start.pressed.connect(func() -> void: start_requested.emit())
	box.add_child(start)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)
	start.grab_focus.call_deferred()


func _row(grid: GridContainer, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _spin(lo: float, hi: float, value: float, on_change: Callable, step := 1.0) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = value
	sb.value_changed.connect(on_change)
	return sb


func _slider(lo: float, hi: float, value: float, on_change: Callable, step := 0.01) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 24)
	s.value_changed.connect(on_change)
	return s
