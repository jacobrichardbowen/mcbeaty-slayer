extends Node
## Entry point: registers input, shows the lobby, and runs matches.
## Pass `-- --autostart` on the command line to skip the lobby.

var _menu: MainMenu
var _game: Game


func _ready() -> void:
	InputSetup.register()
	if "--autostart" in OS.get_cmdline_user_args():
		_start_game()
	else:
		_show_menu()


func _show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu = MainMenu.new()
	_menu.start_requested.connect(_start_game)
	add_child(_menu)


func _start_game() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null
	_game = Game.new()
	_game.name = "Game"
	add_child(_game)
	_game.exit_requested.connect(_on_exit, CONNECT_DEFERRED)
	_game.restart_requested.connect(_on_restart, CONNECT_DEFERRED)
	_game.start()


func _end_game() -> void:
	get_tree().paused = false
	if _game:
		_game.queue_free()
		_game = null


func _on_exit() -> void:
	_end_game()
	_show_menu()


func _on_restart() -> void:
	_end_game()
	_start_game()
