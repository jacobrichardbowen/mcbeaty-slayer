class_name MainMenu
extends CanvasLayer
## Pre-game menu: match options, controls, and online play. Host a game and
## share the code it shows, or type a friend's code to join them; the lobby
## then lists everyone, lets each player pick a side, and the host deploys.

signal start_requested

const CONTROLS := """Mouse / keyboard: WASD move, mouse look, Left click fire, Right click zoom (rifle),
Space jump, Ctrl or C crouch, F / V / middle click melee, R reload, hold E man the Maxim,
Tab scoreboard, Esc pause, F11 fullscreen. While dead: Q, wheel, 1 or 2 picks your weapon.
Gamepad (Halo 2 layout): sticks move/look, RT fire, R3 zoom, A jump, B melee,
X reload / hold X to man the Maxim, L3 crouch, Y switch weapon (while dead), Back scoreboard."""

var net: Net
var message := ""  # e.g. why the last online game ended

var _grid: GridContainer
var _name: LineEdit
var _offline_row: Control
var _online_row: Control
var _lobby: Control
var _code: Label
var _copy: Button
var _status: Label
var _players: Label
var _deploy_all: Button
var _join_code: LineEdit


func _ready() -> void:
	layer = 10
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 0)
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

	_lobby = _build_lobby()
	box.add_child(_lobby)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_grid)
	_name = LineEdit.new()
	_name.text = GameConfig.player_name
	_name.max_length = 16
	_name.text_changed.connect(func(t: String) -> void: GameConfig.player_name = t.strip_edges() if t.strip_edges() != "" else "Player")
	_row(_grid, "Your name (online)", _name)
	var side := OptionButton.new()
	side.add_item("Nobody: both sides fight for it")
	side.add_item("Whites: defend it")
	side.add_item("Reds: storm it")
	side.selected = GameConfig.bunker_start + 1
	side.item_selected.connect(func(i: int) -> void: GameConfig.bunker_start = i - 1)
	_row(_grid, "Bunker starts with", side)
	var gun := OptionButton.new()
	gun.add_item("Shotgun")
	gun.add_item("Mosin-Nagant (semi-auto rifle)")
	gun.selected = 1 if GameConfig.player_loadout == "rifle" else 0
	gun.item_selected.connect(func(i: int) -> void: GameConfig.player_loadout = "rifle" if i == 1 else "shotgun")
	_row(_grid, "Your weapon", gun)
	var most := GameConfig.MAX_PER_TEAM
	_row(_grid, "Red bots", _spin(0, most, GameConfig.red_bots, func(v: float) -> void: GameConfig.red_bots = int(v)))
	_row(_grid, "White bots", _spin(0, most - 1, GameConfig.white_bots, func(v: float) -> void: GameConfig.white_bots = int(v)))
	_row(_grid, "Score limit", _spin(5, 250, GameConfig.score_limit, func(v: float) -> void: GameConfig.score_limit = int(v), 5))
	_row(_grid, "Mouse sensitivity", sensitivity_slider())
	_row(_grid, "Field of view", value_slider(GameConfig.FOV_MIN, GameConfig.FOV_MAX, 1.0, GameConfig.fov, "%d°",
		func(v: float) -> void: GameConfig.fov = v))
	var inv := CheckBox.new()
	inv.button_pressed = GameConfig.invert_y
	inv.toggled.connect(func(on: bool) -> void: GameConfig.invert_y = on)
	_row(_grid, "Invert look", inv)

	box.add_child(HSeparator.new())
	var help := Label.new()
	help.text = CONTROLS
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	box.add_child(help)

	var start := _button("DEPLOY", 24)
	start.pressed.connect(func() -> void: start_requested.emit())
	_offline_row = start
	box.add_child(start)
	var online := HBoxContainer.new()
	online.add_theme_constant_override("separation", 8)
	var host := _button("HOST ONLINE GAME", 18)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(func() -> void: net.host(GameConfig.player_name))
	online.add_child(host)
	_join_code = LineEdit.new()
	_join_code.placeholder_text = "Friend's code"
	_join_code.custom_minimum_size = Vector2(170, 0)
	_join_code.text_submitted.connect(func(_t: String) -> void: _join())
	online.add_child(_join_code)
	var join := _button("JOIN", 18)
	join.pressed.connect(_join)
	online.add_child(join)
	_online_row = online
	box.add_child(online)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)
	start.grab_focus.call_deferred()

	net.status_changed.connect(func(t: String) -> void:
		_status.text = t
		refresh())
	net.lobby_changed.connect(refresh)
	net.match_left.connect(func(reason: String) -> void:
		message = reason
		refresh())
	refresh()


func _build_lobby() -> Control:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	var head := Label.new()
	head.text = "ONLINE LOBBY"
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	panel.add_child(head)
	var code_row := HBoxContainer.new()
	_code = Label.new()
	_code.add_theme_font_size_override("font_size", 40)
	_code.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_code)
	_copy = Button.new()
	_copy.text = "Copy code"
	_copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(net.code))
	code_row.add_child(_copy)
	panel.add_child(code_row)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	panel.add_child(_status)
	_players = Label.new()
	_players.add_theme_font_size_override("font_size", 18)
	panel.add_child(_players)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 8)
	for team in 2:
		var b := Button.new()
		b.text = "Play for the %s" % GameConfig.TEAM_NAMES[team]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: net.set_team(team))
		sides.add_child(b)
	panel.add_child(sides)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_deploy_all = _button("DEPLOY EVERYONE", 22)
	_deploy_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deploy_all.pressed.connect(func() -> void: net.start_match(GameConfig.white_bots, GameConfig.red_bots))
	actions.add_child(_deploy_all)
	var leave := _button("Leave", 18)
	leave.pressed.connect(func() -> void:
		net.leave()
		message = ""
		refresh())
	actions.add_child(leave)
	panel.add_child(actions)
	panel.add_child(HSeparator.new())
	return panel


## Shows the main menu or the lobby, whichever fits the connection.
func refresh() -> void:
	if not is_inside_tree():
		return
	var mode := net.mode
	_lobby.visible = mode != Net.Mode.OFFLINE
	_offline_row.visible = mode == Net.Mode.OFFLINE
	_online_row.visible = mode == Net.Mode.OFFLINE
	_grid.visible = mode != Net.Mode.CLIENT
	_name.editable = mode == Net.Mode.OFFLINE  # the others already have it
	_deploy_all.visible = net.serving()
	_code.text = net.code if net.code != "" else ("" if mode == Net.Mode.CLIENT else "...")
	_code.visible = mode == Net.Mode.HOST
	_copy.visible = mode == Net.Mode.HOST and net.code != ""
	var lines := []
	for id: int in net.players:
		var p: Dictionary = net.players[id]
		lines.append("%s%s  —  %s" % [p["name"], " (host)" if id == 1 else "", GameConfig.TEAM_NAMES[p["team"]]])
	_players.text = "\n".join(lines)
	if mode == Net.Mode.OFFLINE and message != "":
		_status.text = message
		_lobby.visible = true
		_code.visible = false
		_copy.visible = false
		_deploy_all.visible = false


func _join() -> void:
	message = ""
	net.join(GameConfig.player_name, _join_code.text)
	refresh()


func _button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", font_size)
	return b


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


## A slider with its value written beside it (`format`, e.g. "%d°").
static func value_slider(lo: float, hi: float, step: float, value: float, format: String, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var shown := Label.new()
	shown.custom_minimum_size = Vector2(52, 0)
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shown.text = format % value
	row.add_child(shown)
	s.value_changed.connect(func(v: float) -> void:
		shown.text = format % v
		on_change.call(v))
	return row


## Degrees the view turns per pixel of mouse movement.
static func sensitivity_slider() -> Control:
	return value_slider(GameConfig.SENSITIVITY_MIN, GameConfig.SENSITIVITY_MAX, 0.002, GameConfig.mouse_sensitivity, "%.3f",
		func(v: float) -> void: GameConfig.mouse_sensitivity = v)
