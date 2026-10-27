class_name Net
extends Node
## Online play for up to four people, free and with nothing to install.
##
## The host's game asks their router to open a port (UPnP) and shows a short
## join code: their internet address and port, spelled in ten characters.
## Friends type the code (or, on the same network, the host's local address)
## and connect straight to the host over ENet.
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
var _upnp: UPNP
var _router_thread: Thread
var _mapped := false
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

func host(player_name: String, open_router := true) -> Error:
	leave()
	my_name = player_name
	var peer := ENetMultiplayerPeer.new()
	# One spare connection, so a fifth player can be told the game is full.
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		_status("Couldn't open port %d on this computer (is another copy hosting?)" % PORT)
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	players = {1: {"name": my_name, "team": GameConfig.TEAM_WHITE}}
	_connect_signals()
	lan_address = _lan_address()
	code = ""
	_status("Opening a port on your router...")
	if open_router:
		_router_thread = Thread.new()
		_router_thread.start(_open_router)
	lobby_changed.emit()
	return OK


func join(player_name: String, text: String) -> Error:
	leave()
	my_name = player_name
	var addr := decode(text)
	if addr.is_empty():
		_status("That code doesn't look right. It's 10 letters and numbers, or an address like 192.168.1.20.")
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(addr[0], addr[1])
	if err != OK:
		_status("Couldn't start connecting (%s)." % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	players = {}
	_connect_signals()
	_status("Connecting to %s..." % addr[0])
	return OK


## Closes the connection (and the router port, if we opened one).
func leave() -> void:
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
	if _router_thread and _router_thread.is_started():
		_router_thread.wait_to_finish()
	_router_thread = null
	if _mapped and _upnp:
		_upnp.delete_port_mapping(PORT, "UDP")
	_mapped = false
	players = {}
	roster = []
	_offset = {}
	_refusal = ""


func _connect_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _status(text: String) -> void:
	status_changed.emit(text)


## Runs on a thread: router discovery can take a couple of seconds.
func _open_router() -> void:
	_upnp = UPNP.new()
	var ok := false
	var external := ""
	if _upnp.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS \
			and _upnp.get_gateway() and _upnp.get_gateway().is_valid_gateway():
		ok = _upnp.add_port_mapping(PORT, PORT, "Tower of Power", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS
		external = _upnp.query_external_address()
	_router_done.call_deferred(ok, external)


func _router_done(ok: bool, external: String) -> void:
	if mode != Mode.HOST:
		return
	_mapped = ok
	if _router_thread and _router_thread.is_started():
		_router_thread.wait_to_finish()
	_router_thread = null
	if external != "":
		_set_public(external, ok)
	else:
		# No router answer: ask a public echo service for our address, so a
		# player who forwards the port by hand still gets a code.
		var http := HTTPRequest.new()
		add_child(http)
		http.timeout = 5.0
		http.request_completed.connect(func(_r: int, status: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			_set_public(body.get_string_from_utf8().strip_edges() if status == 200 else "", false))
		if http.request("https://api.ipify.org") != OK:
			http.queue_free()
			_set_public("", false)


func _set_public(address: String, router_opened: bool) -> void:
	public_address = address
	var parts := address.split(".")
	if parts.size() != 4:
		code = ""
		_status("Couldn't find your internet address. Friends on your network can join with %s." % lan_address)
	elif _private(address):
		code = ""
		_status("Friends outside your network can't reach this PC: it's behind a second router, or your internet provider shares one address between customers. Someone else should host. Friends on your network can join with %s." % lan_address)
	else:
		code = encode(address, PORT)
		if router_opened:
			_status("Ready. Friends join with the code above (or %s on your network)." % lan_address)
		else:
			_status("Your router didn't open the port by itself. Turn on UPnP in its settings, or forward UDP port %d to %s, and the code above will work. Friends on your network can join with %s." % [PORT, lan_address, lan_address])
	lobby_changed.emit()


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
	leave()
	_status("Couldn't reach the host. Check the code; the host may need to open their router's port.")
	match_left.emit("Couldn't reach the host.")


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
	if mode != Mode.HOST:
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
