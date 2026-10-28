## NetworkUtility.gd
## Autoloaded singleton that owns all ENet multiplayer networking for the game.
## Responsibilities:
##   • Starting a server (host_game) or connecting to one (join_game).
##   • Registering players across the network via RPC so GameState stays in sync.
##   • Coordinating the "start game" transition so every peer loads Board.tscn
##     at the same moment.
##   • Syncing completed turn results (dice + movement) back to all peers.
##
## Architecture note: This singleton only handles *transport* (who connected,
## what data was sent). Game logic lives in GameState; scene changes are
## triggered via Godot's built-in get_tree().change_scene_to_file().
##
## Loaded by Godot via project.godot [autoload] as "NetworkUtility".
## Usage:
##   NetworkUtility.host_game("Alice")
##   NetworkUtility.join_game("192.168.1.5", "Bob")

extends Node

# ---------------------------------------------------------------------------
# CONSTANTS
# ---------------------------------------------------------------------------

## The UDP port the ENet server listens on and clients connect to.
## Must match on both ends; players behind NAT may need port-forwarding.
const DEFAULT_PORT: int = 7777

## Maximum simultaneous peers (1 host + 5 clients = 6-player Monopoly).
## ENet will refuse connections beyond this limit automatically.
const MAX_PEERS: int = 6

# ---------------------------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------------------------

## Emitted on the host whenever a peer connects or disconnects so the lobby
## scene can refresh the player list shown to all users.
signal lobby_updated()

## Emitted on every peer (via RPC from host) when the host presses "Start Game".
## The lobby scene listens for this to trigger the scene transition.
signal game_start_requested()

## Emitted on the client when ENetMultiplayerPeer reports a connection failure
## (wrong IP, server full, server offline, etc.).
signal connection_failed()

## Emitted on the client when it successfully completes the ENet handshake
## with the host. At this point the client calls register_player() RPC.
signal connection_succeeded()

# ---------------------------------------------------------------------------
# INTERNAL STATE
# ---------------------------------------------------------------------------

## Stores the local player's chosen username between join_game() / host_game()
## and the register_player() RPC call that happens once the connection is live.
var _local_username: String = ""
var _connection_timer: Timer

# ---------------------------------------------------------------------------
# LIFECYCLE
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Connect Godot's built-in multiplayer signals to our private handlers.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	_connection_timer = Timer.new()
	_connection_timer.name = "ConnectionWatchdog"
	_connection_timer.wait_time = 7.0
	_connection_timer.one_shot = true
	_connection_timer.timeout.connect(_on_connection_timeout)
	add_child(_connection_timer)

# ---------------------------------------------------------------------------
# HOST / JOIN
# ---------------------------------------------------------------------------

## host_game
## Creates an ENet server peer and assigns it as the active multiplayer peer
## for the entire scene tree. Returns true on success, false on failure (e.g. port already in use).
func host_game(username: String) -> bool:
	disconnect_from_game()
	GameState.reset_game()
	_local_username = username

	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(DEFAULT_PORT, MAX_PEERS)

	if err != OK:
		push_error("NetworkUtility.host_game: failed to create server on port %d (error %d)" % [DEFAULT_PORT, err])
		emit_signal("connection_failed")
		return false

	multiplayer.multiplayer_peer = peer
	GameState.add_player(multiplayer.get_unique_id(), username)
	emit_signal("lobby_updated")

	print("NetworkUtility: Server started on port %d. Host peer ID = %d" % [DEFAULT_PORT, multiplayer.get_unique_id()])
	return true


## join_game
## Resolves host IP if needed, cleanly resets any existing peer, and creates client connection.
func join_game(ip: String, username: String) -> bool:
	disconnect_from_game()
	GameState.reset_game()
	_local_username = username

	var target_ip: String = ip.strip_edges()
	if target_ip.is_empty() or target_ip.to_lower() == "localhost":
		target_ip = "127.0.0.1"
	elif not target_ip.is_valid_ip_address():
		var resolved: String = IP.resolve_hostname(target_ip, IP.TYPE_IPV4)
		if not resolved.is_empty() and resolved != "0.0.0.0":
			target_ip = resolved

	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(target_ip, DEFAULT_PORT)

	if err != OK:
		push_error("NetworkUtility.join_game: failed to initiate connection to %s:%d (error %d)" % [target_ip, DEFAULT_PORT, err])
		emit_signal("connection_failed")
		return false

	multiplayer.multiplayer_peer = peer
	print("NetworkUtility: Connecting to %s:%d …" % [target_ip, DEFAULT_PORT])
	if _connection_timer:
		_connection_timer.stop()
		_connection_timer.start()
	return true


## disconnect_from_game
## Cleanly tears down the ENet connection and removes the multiplayer peer.
func disconnect_from_game() -> void:
	if _connection_timer:
		_connection_timer.stop()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	print("NetworkUtility: Disconnected.")

# ---------------------------------------------------------------------------
# RPC FUNCTIONS
# ---------------------------------------------------------------------------

## register_player
## Called by a newly connected client on the HOST to announce their username.
@rpc("any_peer", "reliable")
func register_player(username: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	GameState.add_player(sender_id, username)

	# Synchronize authoritative player roster to ALL peers (host + clients)
	sync_player_roster.rpc(GameState.players)
	print("NetworkUtility: Registered player '%s' (peer %d)" % [username, sender_id])

	# Automatically trigger scene transition to 3D board for both host and clients
	call_deferred("_auto_start_joined_game")


func _auto_start_joined_game() -> void:
	print("NetworkUtility: All players joined — transitioning to Board scene.")
	start_game.rpc()


## start_solo_game
## Starts an offline single-player session directly on Board.tscn
func start_solo_game(username: String) -> void:
	disconnect_from_game()
	GameState.reset_game()
	_local_username = username
	GameState.add_player(1, username)
	get_tree().change_scene_to_file("res://scenes/board/Board.tscn")


## sync_player_roster
## Authority broadcasts the full player roster so all peers have identical state.
@rpc("authority", "call_local", "reliable")
func sync_player_roster(roster: Array) -> void:
	GameState.set_players(roster)
	emit_signal("lobby_updated")
	print("NetworkUtility: Synchronized roster (%d players)." % roster.size())


## start_game
## Called by the host to command every peer (including host) to load the board scene.
@rpc("authority", "call_local", "reliable")
func start_game() -> void:
	emit_signal("game_start_requested")
	get_tree().change_scene_to_file("res://scenes/board/Board.tscn")


## request_start_game
## Host-side wrapper that calls start_game() via RPC on all peers, including
## the host itself. The lobby "Start" button should call this function.
##
## @return void
func request_start_game() -> void:
	if not multiplayer.is_server():
		push_warning("NetworkUtility.request_start_game: only the host can start the game.")
		return
	# Calling with rpc() sends to all peers; calling locally covers the host.
	start_game.rpc()


## broadcast_turn_result
## Called at the end of the active player's turn to sync the dice outcome and
## new board position to all peers. This keeps every client's GameState and 3D
## pawn position consistent without requiring a dedicated state-sync loop.
##
## RPC mode: "any_peer" — the current player (not always the host) sends this.
## Reliability: "reliable" — position data must not be lost or applied out of order.
##
## @param player_id    Peer ID of the player who just moved.
## @param dice_total   Sum of the two dice (2–12); used for display / Chance cards.
## @param new_position Board space index after movement (0–39).
## @return void
@rpc("any_peer", "reliable")
func broadcast_turn_result(player_id: int, dice_total: int, new_position: int) -> void:
	# Validate the position to guard against tampered/corrupt RPC data.
	if new_position < 0 or new_position >= GameState.board_size:
		push_error("NetworkUtility.broadcast_turn_result: invalid position %d for player %d" % [new_position, player_id])
		return

	# Update the local GameState — every peer applies this so their board
	# rendering and UI reflect the moved pawn's new location.
	var player: Dictionary = GameState.get_player(player_id)
	if player.is_empty():
		push_error("NetworkUtility.broadcast_turn_result: unknown player %d" % player_id)
		return

	# Directly mutate position; do not go through update_player_money because
	# position changes do not trigger bankruptcy. Emit signal manually.
	player["position"] = new_position
	GameState.emit_signal("player_state_changed", player_id)

	print("NetworkUtility: Player %d rolled %d, moved to space %d." % [player_id, dice_total, new_position])

# ---------------------------------------------------------------------------
# CONVENIENCE ACCESSORS
# ---------------------------------------------------------------------------

## get_local_peer_id
## Returns this machine's unique peer ID assigned by ENet.
## The host always has ID 1; clients receive incrementing IDs (2, 3, …).
## Returns 1 even before a peer is created (single-player / offline testing).
##
## @return int — this peer's multiplayer unique ID.
func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()


## is_host
## Convenience wrapper around multiplayer.is_server() so callers don't need
## to import or reference the multiplayer object directly.
##
## @return bool — true if this peer is the ENet server (host).
func is_host() -> bool:
	return multiplayer.is_server()

# ---------------------------------------------------------------------------
# PRIVATE SIGNAL HANDLERS — connected in _ready()
# ---------------------------------------------------------------------------

## Called on the HOST when a new ENet peer completes its connection handshake.
## We do NOT add them to GameState here; we wait for their register_player RPC
## because we need their username, which only arrives via RPC.
func _on_peer_connected(peer_id: int) -> void:
	print("NetworkUtility: Peer %d connected." % peer_id)
	# lobby_updated will fire after register_player() runs and confirms the username.


## Called on all peers when an ENet peer drops (disconnect, crash, timeout).
## Removes the player from GameState so the game can continue without them.
func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkUtility: Peer %d disconnected." % peer_id)

	var player: Dictionary = GameState.get_player(peer_id)
	if not player.is_empty():
		player["bankrupt"] = true
		GameState.emit_signal("player_state_changed", peer_id)

	# Broadcast the updated roster to remaining players.
	if multiplayer.is_server():
		sync_player_roster.rpc(GameState.players)


## Called on the CLIENT once the ENet handshake with the host succeeds.
## Now that we have a valid connection and a peer ID, we can register ourselves
## in the host's GameState by sending our username via RPC.
func _on_connected_to_server() -> void:
	if _connection_timer:
		_connection_timer.stop()
	print("NetworkUtility: Connected to server. Local peer ID = %d" % multiplayer.get_unique_id())
	emit_signal("connection_succeeded")

	# Call register_player on the HOST (peer 1) — the RPC annotation routes it.
	# We pass _local_username which was stored during join_game().
	register_player.rpc_id(1, _local_username)


## Called when the connection watchdog expires before the handshake completes.
func _on_connection_timeout() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		var status = multiplayer.multiplayer_peer.get_connection_status()
		if status == MultiplayerPeer.CONNECTION_CONNECTING:
			push_warning("NetworkUtility: Connection attempt timed out.")
			_on_connection_failed()


## Called on the CLIENT if the ENet connection attempt times out or is refused.
func _on_connection_failed() -> void:
	if _connection_timer:
		_connection_timer.stop()
	push_warning("NetworkUtility: Connection to server failed.")
	disconnect_from_game()
	emit_signal("connection_failed")


## Called on the CLIENT when the host disconnects or server drops.
func _on_server_disconnected() -> void:
	print("NetworkUtility: Server disconnected.")
	disconnect_from_game()
	GameState.reset_game()
	emit_signal("connection_failed")
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")
