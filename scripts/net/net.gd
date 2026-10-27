class_name Net
extends Node
## Online play for up to four people, free and with nothing to install.
##
## The host's game asks a public STUN server for its address on the internet
## and shows it as a short join code. A joining player's game does the same,
## then leaves its own address for the host on a free public message board
## (ntfy.sh). The host's game sends a few packets toward that address, so the
## host's router knows the player is expected and lets their connection in
## (hole punching). Nothing on either router is changed. On the same network,
## friends can join with the host's local address instead.
##
## The host runs the match: bots, health, deaths, respawns, scores, the
## bunker and who is on the Maxim. Each player moves their own soldier and
## judges their own shots, which keeps aiming and movement instant; hits are
## reported to the host, which applies them. Everyone else's soldiers are
## shown a tenth of a second behind, smoothed between updates.

signal lobby_changed
signal status_changed(text: String)
signal match_started
signal match_left(reason: String)

enum Mode { OFFLINE, HOST, CLIENT }
enum Ev { FIRED, MG_FIRED, HIT, DAMAGED, DIED, RESPAWN, MELEE, MOUNT, MOUNTED, PICKUP, DROP, FEED, ANNOUNCE, END, LEFT, KILL }

const PORT := 24565
const MAX_PLAYERS := 4
const SNAPSHOT_EVERY := 3  # physics ticks between host snapshots (20 Hz)
const STATE_EVERY := 2  # physics ticks between a player's own updates (30 Hz)
const INTERP_DELAY := 0.1  # how far behind other soldiers are drawn
const CODE_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"  # Crockford base 32
const MEET_POLL := 4.0  # seconds between the host's looks at the message board (ntfy.sh allows ~1 per 5 s after a burst of 60)
const MEET_WAIT := 3.5  # a joining player's wait for the host to read their note
const KNOCKS := 20  # packets the host sends toward each player on their way in...
const KNOCK_GAP := 0.5  # ...this many seconds apart
const KEEP_OPEN := 20.0  # seconds between packets that stop the host's router forgetting its port

## Public STUN servers, [host, port], asked in turn.
static var stun_servers: Array = [["stun.l.google.com", 19302], ["stun.cloudflare.com", 3478], ["stun1.l.google.com", 19302]]
## The message board ("" to go without). Tests point both at stand-ins.
static var meeting_url := "https://ntfy.sh/"
static var instance: Net

var mode := Mode.OFFLINE
var my_name := "Player"
## peer id -> {"name": String, "team": int}, in the lobby.
var players := {}
var code := ""
var lan_address := ""
var public_address := ""
## Set when a match starts: one entry per soldier, in order:
## {"team", "name", "peer" (0 for a bot), "xf" (first spawn)}.
var roster: Array = []
var settings := {}
var game: Game

var _tick := 0
var _thread: Thread
var _abort := false
var _attempt := 0  # bumped on leaving, so late answers for an old attempt are ignored
var _target := []  # client: the host's [address, port]
var _local_port := 0  # client: the port its address check used, kept for connecting
var _keep_open_to := []  # host: the STUN server [ip, port] its keep-open packets go to
var _keep_open_in := 0.0
var _poll: HTTPRequest
var _poll_in := 0.0
var _meet_since := ""
var _knocks := {}  # host: "ip:port" -> [knocks left, seconds to the next]
var _offset := {}  # sender peer -> local time minus its clock, smallest seen
var _offset_age := {}
var _refusal := ""  # why the host turned us away, if it did


static func online() -> bool:
	return instance != null and instance.mode != Mode.OFFLINE


static func is_host() -> bool:
	return instance != null and instance.mode == Mode.HOST


static func is_client() -> bool:
	return instance != null and instance.mode == Mode.CLIENT


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	leave()
	if instance == self:
		instance = null


func my_peer() -> int:
	return multiplayer.get_unique_id() if online() else 1


static func clock() -> float:
	return Time.get_ticks_usec() / 1000000.0


# --- Hosting and joining ---------------------------------------------------------------

## Hosts a game. Tests on one machine pass `find_address` false to skip the
## internet address check and the message board.
func host(player_name: String, find_address := true) -> void:
	leave()
	my_name = player_name
	mode = Mode.HOST
	players = {1: {"name": my_name, "team": GameConfig.TEAM_WHITE}}
	lan_address = _lan_address()
	code = ""
	if find_address:
		# The check borrows the game's port, so it learns the port friends will reach.
		_status("Finding your internet address...")
		_start_check(PORT)
	elif _open_server() != OK:
		return
	lobby_changed.emit()


## Host: whether players can connect yet.
func serving() -> bool:
	return mode == Mode.HOST and multiplayer.multiplayer_peer is ENetMultiplayerPeer


func join(player_name: String, text: String) -> void:
	leave()
	my_name = player_name
	_target = decode(text)
	if _target.is_empty():
		_status("That code doesn't look right. It's 10 letters and numbers, or an address like 192.168.1.20.")
		return
	mode = Mode.CLIENT
	players = {}
	_local_port = 0
	_status("Connecting to the host...")
	if meeting_url != "" and not (text.count(".") == 3 and _private(_target[0])):
		# Over the internet: find our address and leave it for the host first.
		_start_check(0)
	else:
		_connect_client()
	lobby_changed.emit()


## Closes the connection and stops anything still on its way.
func leave() -> void:
	_attempt += 1
	_abort = true
	_end_thread()
	_abort = false
	if _poll:
		_poll.cancel_request()
		_poll.queue_free()
		_poll = null
	_knocks = {}
	_keep_open_to = []
	_meet_since = ""
	if mode == Mode.OFFLINE:
		return
	mode = Mode.OFFLINE
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for sig: Array in [[multiplayer.peer_connected, _on_peer_connected], [multiplayer.peer_disconnected, _on_peer_disconnected],
			[multiplayer.connected_to_server, _on_connected], [multiplayer.connection_failed, _on_connection_failed],
			[multiplayer.server_disconnected, _on_server_disconnected]]:
		if (sig[0] as Signal).is_connected(sig[1]):
			(sig[0] as Signal).disconnect(sig[1])
	players = {}
	roster = []
	_offset = {}
	_refusal = ""


func _open_server() -> Error:
	var peer := ENetMultiplayerPeer.new()
	# One spare connection, so a fifth player can be told the game is full.
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		_fail("Couldn't use port %d on this computer. Is another copy of the game hosting?" % PORT)
		return err
	multiplayer.multiplayer_peer = peer
	_connect_signals()
	return OK


func _connect_client() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_target[0], _target[1], 0, 0, 0, _local_port)
	if err != OK:
		_fail("Couldn't start connecting (%s)." % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	_connect_signals()


func _connect_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _status(text: String) -> void:
	status_changed.emit(text)


## Gives up on the connection, saying why.
func _fail(reason: String) -> void:
	leave()
	_status(reason)
	match_left.emit(reason)


# --- Finding our address and meeting up ------------------------------------------------

## Asks the STUN servers for our internet address from `local_port`, on a
## thread since it can take a second or two.
func _start_check(local_port: int) -> void:
	var attempt := _attempt
	_thread = Thread.new()
	_thread.start(func() -> void:
		var found := Stun.discover(local_port, stun_servers, func() -> bool: return _abort)
		_checked.call_deferred(found, attempt))


func _end_thread() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null


func _checked(found: Dictionary, attempt: int) -> void:
	if attempt != _attempt:
		return  # leave() already waited for that thread
	_end_thread()
	if mode == Mode.HOST:
		if found.has("error"):
			_fail("Couldn't use port %d on this computer. Is another copy of the game hosting?" % PORT)
		elif _open_server() == OK:
			if found.has("address"):
				_keep_open_to = found["server"]
				_set_public(found["address"], found["port"], true)
			else:
				_look_up_address()
	elif mode == Mode.CLIENT:
		_local_port = found.get("local_port", 0)
		if found.has("address"):
			_leave_note("join %s:%d" % [found["address"], found["port"]])
		else:
			_connect_client()


## Host: no STUN server answered (UDP blocked?), so ask a web service for our
## address instead and hope the router keeps the game's port number.
func _look_up_address() -> void:
	var attempt := _attempt
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(func(_r: int, status: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		if attempt == _attempt:
			_set_public(body.get_string_from_utf8().strip_edges() if status == 200 else "", PORT, false))
	if http.request("https://api.ipify.org") != OK:
		http.queue_free()
		_set_public("", PORT, false)


func _set_public(address: String, port: int, checked: bool) -> void:
	public_address = address
	if address.count(".") != 3 or not address.is_valid_ip_address():
		code = ""
		_status("Couldn't reach the internet to make a code. Is this PC online? Friends on your own network can join with %s." % lan_address)
	else:
		code = encode(address, port)
		if checked:
			_status("Ready. Friends join with the code above (or %s on your own network)." % lan_address)
		else:
			_status("Ready, but the address check got no answer, so friends outside your network may not get in. If they can't, forward UDP port %d to %s in your router's settings, or let someone else host. On your own network they can join with %s." % [PORT, lan_address, lan_address])
	_poll_in = 0.0
	lobby_changed.emit()


## The message board topic for a host's address: named after its code.
static func _topic(address: Array) -> String:
	return "tower-of-power-" + encode(address[0], address[1]).replace("-", "")


## Client: leaves our address on the message board for the host, gives the
## host a moment to read it and knock, then connects.
func _leave_note(note: String) -> void:
	var attempt := _attempt
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	var then := func(left: bool) -> void:
		if attempt != _attempt:
			return
		if not left:
			_connect_client()
			return
		get_tree().create_timer(MEET_WAIT).timeout.connect(func() -> void:
			if attempt == _attempt:
				_connect_client())
	http.request_completed.connect(func(result: int, status: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		http.queue_free()
		then.call(result == HTTPRequest.RESULT_SUCCESS and status == 200))
	if http.request(meeting_url + _topic(_target), [], HTTPClient.METHOD_POST, note) != OK:
		http.queue_free()
		then.call(false)


## Host: keeps our router's port in use, knocks toward players on their way
## in, and looks for new notes on the message board.
func _process(delta: float) -> void:
	if not serving() or code == "":
		return
	var enet := (multiplayer.multiplayer_peer as ENetMultiplayerPeer).host
	if not _keep_open_to.is_empty():
		_keep_open_in -= delta
		if _keep_open_in <= 0.0:
			_keep_open_in = KEEP_OPEN
			enet.socket_send(_keep_open_to[0], _keep_open_to[1], Stun.request(Crypto.new().generate_random_bytes(12)))
	for to: String in _knocks.keys():
		var knock: Array = _knocks[to]
		knock[1] -= delta
		if knock[1] <= 0.0:
			# Sending toward them is what tells our router to let their packets in.
			var at := to.split(":")
			enet.socket_send(at[0], int(at[1]), PackedByteArray([0]))
			knock[0] -= 1
			knock[1] = KNOCK_GAP
			if knock[0] <= 0:
				_knocks.erase(to)
	if meeting_url != "" and game == null and _poll == null and players.size() < MAX_PLAYERS:
		_poll_in -= delta
		if _poll_in <= 0.0:
			_read_notes()


func _read_notes() -> void:
	_poll = HTTPRequest.new()
	_poll.timeout = 10.0
	add_child(_poll)
	_poll.request_completed.connect(_on_notes.bind(_attempt))
	var since := _meet_since if _meet_since != "" else "1m"
	if _poll.request("%s%s/json?poll=1&since=%s" % [meeting_url, _topic(decode(code)), since]) != OK:
		_on_notes(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), _attempt)


func _on_notes(result: int, status: int, _h: PackedStringArray, body: PackedByteArray, attempt: int) -> void:
	if attempt != _attempt or _poll == null:
		return
	_poll.queue_free()
	_poll = null
	_poll_in = 20.0 if status == 429 else MEET_POLL  # 429: the board asks us to slow down
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		return
	for line in body.get_string_from_utf8().split("\n", false):
		var note: Variant = JSON.parse_string(line)
		if not note is Dictionary or note.get("event") != "message":
			continue
		_meet_since = str(note.get("id", _meet_since))
		var words := str(note.get("message", "")).split(" ")
		var at := decode(words[1]) if words.size() == 2 and words[0] == "join" and words[1].count(".") == 3 else []
		if at.size() == 2 and at[1] > 0 and at[1] < 65536 and _knocks.size() < 16:
			_knocks["%s:%d" % at] = [KNOCKS, 0.0]


static func _private(address: String) -> bool:
	var p := address.split(".")
	var a := int(p[0])
	var b := int(p[1])
	return a == 10 or a == 127 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b < 32) or (a == 100 and b >= 64 and b < 128)


static func _lan_address() -> String:
	for a in IP.get_local_addresses():
		var p := a.split(".")
		if p.size() == 4 and _private(a) and not a.begins_with("127.") and not a.begins_with("100."):
			return a
	return "127.0.0.1"


## An IPv4 address and port as ten characters, e.g. "4F2KQ-8M0TX".
static func encode(address: String, port: int) -> String:
	var p := address.split(".")
	var n := (int(p[0]) << 40) | (int(p[1]) << 32) | (int(p[2]) << 24) | (int(p[3]) << 16) | port
	var s := ""
	for i in 10:
		s = CODE_ALPHABET[n & 31] + s
		n >>= 5
	return s.substr(0, 5) + "-" + s.substr(5)


## [address, port] from a join code, an address, or address:port; [] if none.
static func decode(text: String) -> Array:
	var t := text.strip_edges().to_upper().replace(" ", "")
	if t.count(".") == 3:
		var parts := t.split(":")
		var port := int(parts[1]) if parts.size() > 1 else PORT
		return [parts[0], port] if parts[0].is_valid_ip_address() else []
	t = t.replace("-", "").replace("O", "0").replace("I", "1").replace("L", "1")
	if t.length() != 10:
		return []
	var n := 0
	for ch in t:
		var v := CODE_ALPHABET.find(ch)
		if v < 0:
			return []
		n = (n << 5) | v
	var address := "%d.%d.%d.%d" % [(n >> 40) & 255, (n >> 32) & 255, (n >> 24) & 255, (n >> 16) & 255]
	return [address, n & 65535]


# --- Lobby ---------------------------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	pass  # they introduce themselves with _hello


## Host: turns a player away, telling them why first.
func _refuse(id: int, reason: String) -> void:
	_refused.rpc_id(id, reason)
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if mode == Mode.HOST and multiplayer.multiplayer_peer:
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id))


@rpc("authority", "reliable")
func _refused(reason: String) -> void:
	_refusal = reason


func _on_peer_disconnected(id: int) -> void:
	if mode != Mode.HOST:
		return
	var who: String = players.get(id, {}).get("name", "A player")
	players.erase(id)
	_lobby.rpc(players)
	lobby_changed.emit()
	if game:
		game.remove_peer(id, who)


func _on_connected() -> void:
	_status("Connected. Waiting for the host to deploy...")
	_hello.rpc_id(1, my_name)


func _on_connection_failed() -> void:
	_fail("Couldn't reach the host. Check the code with them. If it's right, a router is turning the connection away: the host can forward UDP port %d to their PC in their router's settings, or someone else can host." % PORT)


func _on_server_disconnected() -> void:
	var reason := _refusal if _refusal != "" else "The host left the game."
	leave()
	_status(reason)
	match_left.emit(reason)


@rpc("any_peer", "reliable")
func _hello(player_name: String) -> void:
	if mode != Mode.HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	if game != null:
		_refuse(id, "A match is already under way. Try again when it ends.")
		return
	if players.size() >= MAX_PLAYERS:
		_refuse(id, "That game is full (%d players)." % MAX_PLAYERS)
		return
	# Join the side with fewer people on it.
	var count := [0, 0]
	for p: Dictionary in players.values():
		count[p["team"]] += 1
	players[id] = {"name": player_name.left(16), "team": 0 if count[0] <= count[1] else 1}
	_lobby.rpc(players)
	lobby_changed.emit()


@rpc("authority", "reliable")
func _lobby(p: Dictionary) -> void:
	players = p
	lobby_changed.emit()


## Picks a side in the lobby.
func set_team(team: int) -> void:
	if mode == Mode.HOST:
		_team(team, 1)
	elif mode == Mode.CLIENT:
		_request_team.rpc_id(1, team)


@rpc("any_peer", "reliable")
func _request_team(team: int) -> void:
	if mode == Mode.HOST:
		_team(team, multiplayer.get_remote_sender_id())


func _team(team: int, peer: int) -> void:
	if players.has(peer):
		players[peer]["team"] = clampi(team, 0, 1)
		_lobby.rpc(players)
		lobby_changed.emit()


## Host: starts the match for everyone, humans first, bots after.
func start_match(white_bots: int, red_bots: int) -> void:
	if not serving():
		return
	settings = {"bunker_start": GameConfig.bunker_start, "score_limit": GameConfig.score_limit}
	roster = []
	var per_team := [0, 0]
	var ids := players.keys()
	ids.sort()
	for id: int in ids:
		var p: Dictionary = players[id]
		roster.append({"team": p["team"], "name": p["name"], "peer": id})
		per_team[p["team"]] += 1
	var bots := [white_bots, red_bots]
	var names := [GameConfig.WHITE_NAMES, GameConfig.RED_NAMES]
	for team in 2:
		for i in mini(bots[team], GameConfig.MAX_PER_TEAM - per_team[team]):
			roster.append({"team": team, "name": names[team][i % names[team].size()], "peer": 0})
	_begin(settings, roster)


## Called on the host after it has built its game and chosen first spawns.
func send_start() -> void:
	_begin.rpc(settings, roster)


@rpc("authority", "reliable")
func _begin(p_settings: Dictionary, p_roster: Array) -> void:
	settings = p_settings
	roster = p_roster
	GameConfig.bunker_start = settings["bunker_start"]
	GameConfig.score_limit = settings["score_limit"]
	_offset = {}
	match_started.emit()


# --- In the match ----------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not online() or game == null or not game.is_inside_tree():
		return
	_tick += 1
	if mode == Mode.HOST and _tick % SNAPSHOT_EVERY == 0:
		_snapshot.rpc(game.pack_snapshot())
	elif mode == Mode.CLIENT and _tick % STATE_EVERY == 0 and game.player:
		_state.rpc_id(1, game.pack_own_state())


@rpc("any_peer", "unreliable_ordered")
func _state(data: PackedByteArray) -> void:
	if mode == Mode.HOST and game:
		game.apply_player_state(multiplayer.get_remote_sender_id(), data)


@rpc("authority", "unreliable_ordered")
func _snapshot(data: PackedByteArray) -> void:
	if mode == Mode.CLIENT and game:
		game.apply_snapshot(data)


## Local time minus the sender's clock, at its smallest (least delayed) over
## the last few seconds: maps their timestamps onto our clock.
func clock_offset(peer: int, sent_at: float) -> float:
	var now := clock()
	var off := now - sent_at
	if not _offset.has(peer) or off < float(_offset[peer]) or now - float(_offset_age.get(peer, 0.0)) > 5.0:
		_offset[peer] = off
		_offset_age[peer] = now
	return _offset[peer]


## Sends a game event: from a client to the host, or from the host to
## everyone (or to one peer).
func send(kind: int, args: Array, to_peer := 0) -> void:
	if mode == Mode.HOST:
		if to_peer > 0:
			_event.rpc_id(to_peer, kind, args)
		else:
			_event.rpc(kind, args)
	elif mode == Mode.CLIENT:
		_event.rpc_id(1, kind, args)


@rpc("any_peer", "reliable")
func _event(kind: int, args: Array) -> void:
	if game == null:
		return
	game.on_net_event(kind, args, multiplayer.get_remote_sender_id())


## Host: passes a player's event on to everyone else.
func relay(kind: int, args: Array, from_peer: int) -> void:
	if mode != Mode.HOST:
		return
	for id: int in multiplayer.get_peers():
		if id != from_peer:
			_event.rpc_id(id, kind, args)
