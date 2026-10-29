extends Node
## Lobbies and online play over the same Wi-Fi.
##
## The host's phone runs the real game and is the referee. Every other phone
## sends "I want to do X" requests; the host checks them against the rules,
## applies them, and sends each phone a snapshot of what that player may see
## (their own hand, everyone else's card counts) plus the public events.
##
## Lobbies are found with a UDP broadcast "beacon" on the local network. If a
## router blocks that, players can join by typing the host's IP address.

signal roster_changed
signal lobbies_changed
signal match_started
## Something happened. `result` is only filled in for this phone's own request.
signal updated(events: Array, result: Dictionary)
signal ended(reason: String)

const Game = preload("res://scripts/core/game.gd")

const PORT := 47601
const DISCOVERY_PORT := 47600
const PROTOCOL := 3
const MAX_PLAYERS := 6
const LOBBY_TIMEOUT_MS := 4000

var mode := "offline" # offline | host | client
var my_name := "PLAYER"
var my_seat := -1
var names: Array = [] # lobby players in seat order (host is seat 0)
var lobbies := {} # ip -> { "name", "players", "max", "seen" }
var game: Game = null
var in_match := false
var version := 0 # counts the host's updates, so phones can tell they're in sync

var _peers: Array = [] # host only: peer id for each seat
var _enet: ENetMultiplayerPeer
var _beacon: PacketPeerUDP
var _scanner: PacketPeerUDP
var _beacon_wait := 0.0
var _events: Array = []


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return mode != "offline"


func is_host() -> bool:
	return mode == "host"


# ================================================================ lobby

func host(player_name: String) -> String:
	leave()
	my_name = player_name
	_enet = ENetMultiplayerPeer.new()
	var err := _enet.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		_enet = null
		return "Couldn't open a lobby (error %d). Is another game already hosting on this phone?" % err
	multiplayer.multiplayer_peer = _enet
	mode = "host"
	my_seat = 0
	names = [player_name]
	_peers = [1]
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	roster_changed.emit()
	return ""


func join(ip: String, player_name: String) -> String:
	stop_scan()
	leave()
	my_name = player_name
	_enet = ENetMultiplayerPeer.new()
	var err := _enet.create_client(ip.strip_edges(), PORT)
	if err != OK:
		_enet = null
		return "Couldn't connect to %s (error %d)." % [ip, err]
	multiplayer.multiplayer_peer = _enet
	mode = "client"
	return ""


func leave() -> void:
	if _enet != null:
		_enet.close()
	multiplayer.multiplayer_peer = null
	_enet = null
	if _beacon != null:
		_beacon.close()
	_beacon = null
	mode = "offline"
	my_seat = -1
	version = 0
	names = []
	_peers = []
	in_match = false
	game = null
	_events = []


## Addresses other phones on this Wi-Fi can use to join this one.
static func local_addresses() -> Array:
	var home := []
	var other := []
	for a in IP.get_local_addresses():
		var ip := str(a)
		if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue # IPv6, this phone only, or no network
		if ip.begins_with("192.168.") or ip.begins_with("10.") or (ip.begins_with("172.") and int(ip.split(".")[1]) >= 16 and int(ip.split(".")[1]) <= 31):
			home.append(ip)
		else:
			other.append(ip)
	return home if not home.is_empty() else other


func start_scan() -> void:
	stop_scan()
	lobbies = {}
	_scanner = PacketPeerUDP.new()
	if _scanner.bind(DISCOVERY_PORT) != OK:
		_scanner = null
	lobbies_changed.emit()


func stop_scan() -> void:
	if _scanner != null:
		_scanner.close()
	_scanner = null


func _process(delta: float) -> void:
	if mode == "host" and not in_match and _beacon != null:
		_beacon_wait -= delta
		if _beacon_wait <= 0.0:
			_beacon_wait = 1.0
			var info := {"game": "shotgun-rummy", "v": PROTOCOL, "name": "%s'S TABLE" % my_name, "players": names.size(), "max": MAX_PLAYERS}
			_beacon.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _scanner != null:
		var changed := false
		while _scanner.get_available_packet_count() > 0:
			var data := _scanner.get_packet().get_string_from_utf8()
			var ip := _scanner.get_packet_ip()
			var info = JSON.parse_string(data)
			if info is Dictionary and info.get("game", "") == "shotgun-rummy" and int(info.get("v", 0)) == PROTOCOL:
				changed = changed or not lobbies.has(ip) or int(lobbies[ip]["players"]) != int(info.get("players", 0))
				lobbies[ip] = {"name": str(info.get("name", "TABLE")), "players": int(info.get("players", 0)), "max": int(info.get("max", MAX_PLAYERS)), "seen": Time.get_ticks_msec()}
		for ip in lobbies.keys():
			if Time.get_ticks_msec() - int(lobbies[ip]["seen"]) > LOBBY_TIMEOUT_MS:
				lobbies.erase(ip)
				changed = true
		if changed:
			lobbies_changed.emit()


func _on_connected() -> void:
	_hello.rpc_id(1, my_name, PROTOCOL)


func _on_connection_failed() -> void:
	leave()
	ended.emit("Couldn't reach that lobby. Check you're on the same Wi-Fi.")


func _on_server_disconnected() -> void:
	leave()
	ended.emit("The host left the game.")


func _on_peer_connected(_id: int) -> void:
	pass # players introduce themselves with _hello


func _on_peer_disconnected(id: int) -> void:
	if mode != "host":
		return
	var seat := _peers.find(id)
	if seat < 0:
		return
	var who: String = names[seat]
	if in_match:
		_ended.rpc("%s left the game." % who)
		leave()
		ended.emit("%s left the game." % who)
		return
	_peers.remove_at(seat)
	names.remove_at(seat)
	_send_roster()


@rpc("any_peer", "call_remote", "reliable")
func _hello(player_name: String, protocol: int) -> void:
	if mode != "host":
		return
	var peer := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_reject(peer, "That phone has a different version of the game. Update both.")
	elif in_match:
		_reject(peer, "That game has already started.")
	elif names.size() >= MAX_PLAYERS:
		_reject(peer, "That lobby is full.")
	else:
		var clean := player_name.strip_edges().to_upper().left(10)
		if clean == "":
			clean = "PLAYER %d" % (names.size() + 1)
		while names.has(clean):
			clean += "*"
		names.append(clean)
		_peers.append(peer)
		_send_roster()


func _reject(peer: int, reason: String) -> void:
	_rejected.rpc_id(peer, reason)
	# give the message a moment to arrive before hanging up
	get_tree().create_timer(0.5).timeout.connect(_drop_peer.bind(peer))


func _drop_peer(peer: int) -> void:
	if _enet != null:
		_enet.disconnect_peer(peer)


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	leave()
	ended.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _ended(reason: String) -> void:
	leave()
	ended.emit(reason)


func _send_roster() -> void:
	_roster.rpc(names)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _roster(lobby_names: Array) -> void:
	names = lobby_names
	roster_changed.emit()


# ================================================================ match

func start_match() -> void:
	if mode != "host" or names.size() < 2:
		return
	in_match = true
	game = Game.new()
	game.setup(names)
	game.event.connect(_on_host_event)
	match_started.emit()
	for seat in range(1, _peers.size()):
		_match_start.rpc_id(_peers[seat], seat)
	game.start_round()
	_flush(1, {})


@rpc("authority", "call_remote", "reliable")
func _match_start(seat: int) -> void:
	my_seat = seat
	in_match = true
	game = Game.new()


## Asks to do something on this player's turn. The answer arrives through
## `updated` (with `result` filled in).
func act(action: String, args: Array) -> void:
	if mode == "host":
		var res := perform(game, my_seat, action, args, true)
		_flush(1, res)
	elif mode == "client":
		_request.rpc_id(1, action, args)


@rpc("any_peer", "call_remote", "reliable")
func _request(action: String, args: Array) -> void:
	if mode != "host" or not in_match:
		return
	var peer := multiplayer.get_remote_sender_id()
	var seat := _peers.find(peer)
	if seat < 0:
		return
	var res := perform(game, seat, action, args, false)
	_flush(peer, res)


@rpc("authority", "call_remote", "reliable")
func _update(host_version: int, snap: Dictionary, events: Array, result: Dictionary) -> void:
	if game == null:
		return
	version = host_version
	var first := game.players.is_empty()
	game.load_snapshot(snap)
	if first:
		match_started.emit()
	updated.emit(events, result)


func _on_host_event(kind: String, data: Dictionary) -> void:
	_events.append([kind, data.duplicate(true)])


## Sends everyone their view of the game after an action by `requester`.
func _flush(requester: int, result: Dictionary) -> void:
	var events := _events
	_events = []
	version += 1
	for seat in range(1, _peers.size()):
		var peer: int = _peers[seat]
		_update.rpc_id(peer, version, game.snapshot(seat), events, result if peer == requester else {})
	updated.emit(events, result if requester == 1 else {})


## Applies `action` for `seat`, checking the arguments since they may come
## from another phone. Also used directly for pass-and-play.
static func perform(g: Game, seat: int, action: String, args: Array, by_host: bool) -> Dictionary:
	var bad := {"ok": false, "error": "That didn't work."}
	match action:
		"draw_stock":
			return g.draw_stock(seat)
		"draw_discard":
			return g.draw_discard(seat)
		"meld":
			if args.size() == 1 and args[0] is Array:
				return g.meld(seat, args[0])
		"lay_off":
			if args.size() == 2 and args[0] is Array and args[1] is String:
				return g.lay_off(seat, args[0], args[1])
		"swap":
			if args.size() == 4 and args[0] is String and args[1] is String and args[2] is String and args[3] is Array:
				return g.swap_trump(seat, args[0], args[1], args[2], args[3])
		"discard":
			if args.size() == 1 and args[0] is String:
				return g.discard(seat, args[0])
		"use_item":
			if args.size() == 3 and args[0] is String and args[1] is int and args[2] is String:
				return g.use_item(seat, args[0], args[1], args[2])
		"shoot":
			if args.size() == 1 and args[0] is int:
				return g.shoot(seat, args[0])
		"next_round":
			if by_host:
				return g.start_round()
		"play_again":
			if by_host and g.phase == "match_over":
				g.reset_match()
				return g.start_round()
	return bad
