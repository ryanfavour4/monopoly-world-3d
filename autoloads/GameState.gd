## GameState.gd
## Autoloaded global singleton that acts as the single source of truth for all
## game-critical state. Every scene and system reads from (and writes to) this
## node rather than storing local copies so that multiplayer sync, save/load,
## and UI updates all have one authoritative location to query.
##
## Loaded automatically by Godot via project.godot [autoload] section as
## "GameState", so any script can reference it as simply `GameState.players`.

extends Node

# ---------------------------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------------------------

## Emitted whenever a player's data changes (money, position, properties, etc.).
## Listeners (UI panels, 3D pawn controllers) subscribe to refresh themselves.
## @param player_id: the peer ID of the player whose state changed.
signal player_state_changed(player_id: int)

## Emitted the moment only one non-bankrupt player remains in the game.
## The game scene listens for this to display a winner screen and halt turns.
## @param winner_id: the peer ID of the last solvent player.
signal game_over(winner_id: int)

# ---------------------------------------------------------------------------
# CONSTANTS — board configuration shared by all systems
# ---------------------------------------------------------------------------

## Standard Monopoly board has 40 spaces (0 = GO, 39 = Boardwalk / last).
## Centralising this here means dice movement, jail logic, etc. all agree.
const BOARD_SIZE: int = 40

## Classic starting money per the official Monopoly rules.
## Override before calling add_player() if house rules differ.
const STARTING_MONEY: int = 1500

## Distinct player pawn colors for up to 6 players
const PLAYER_COLORS: Array[Color] = [
	Color(0.2, 0.65, 1.0),   # Neon Blue
	Color(1.0, 0.35, 0.35),  # Crimson Red
	Color(0.25, 0.95, 0.45), # Emerald Green
	Color(1.0, 0.85, 0.2),   # Gold Yellow
	Color(0.85, 0.35, 1.0),  # Magenta
	Color(0.15, 0.9, 0.9)    # Cyan
]

# ---------------------------------------------------------------------------
# MUTABLE STATE — do NOT write these from outside; use the provided functions
# so signals always fire and invariants stay intact.
# ---------------------------------------------------------------------------

## Zero-based index into `players` indicating whose turn it currently is.
## Use advance_turn() to move it forward; never increment directly.
var current_player_index: int = 0

## Ordered list of all players in the game. Each entry is a Dictionary with
## the shape defined in add_player(). Ordered by join sequence / turn order.
## Type annotation is kept as plain Array for GDScript 4 compatibility with
## heterogeneous dict contents.
var players: Array = []

## Mirrors BOARD_SIZE as a mutable field so future variants (shorter boards,
## custom maps) can be set at runtime before the game starts.
var board_size: int = BOARD_SIZE

## Mirrors STARTING_MONEY; adjust before calling add_player() for custom rules.
var starting_money: int = STARTING_MONEY

# ---------------------------------------------------------------------------
# INTERNAL HELPERS
# ---------------------------------------------------------------------------

## Returns the index of a player entry inside `players` by peer_id, or -1.
## Private convention: prefixed with underscore; callers use get_player().
func _find_player_index(peer_id: int) -> int:
	for i in range(players.size()):
		if players[i]["id"] == peer_id:
			return i
	return -1


# ---------------------------------------------------------------------------
# PUBLIC API
# ---------------------------------------------------------------------------

## add_player
## Creates a fresh player dictionary and appends it to the `players` array.
## Should be called once per joining peer before the game starts (typically
## from NetworkUtility.register_player on the host).
##
## @param peer_id   The ENet unique peer ID assigned by Godot's multiplayer.
## @param username  Display name chosen by the player in the lobby UI.
## @return void
func add_player(peer_id: int, username: String) -> void:
	# Guard: prevent duplicate registration if a late-join message arrives twice.
	if _find_player_index(peer_id) != -1:
		push_warning("GameState.add_player: peer %d already registered." % peer_id)
		return

	var color_idx: int = players.size() % PLAYER_COLORS.size()
	var assigned_color: Color = PLAYER_COLORS[color_idx]

	# Build the canonical player dictionary. Every field that other systems
	# depend on must be initialised here so get_player() callers never have
	# to check for key existence with .has().
	var player_dict: Dictionary = {
		"id":         peer_id,        # int  — stable ENet peer ID used as primary key
		"username":   username,       # String — display name shown in HUD / chat
		"money":      starting_money, # int — current cash balance
		"position":   0,              # int — current board space index (0 = GO)
		"properties": [],             # Array[int] — list of board space indices this player owns
		"bankrupt":   false,          # bool — set true by check_bankruptcy(); skipped in turn order
		"in_jail":    false,          # bool — jail status
		"jail_turns": 0,              # int — turns spent in jail
		"color":      assigned_color, # Color — distinct visual pawn color
		"colour":     assigned_color  # Color — alias for British English compatibility
	}

	players.append(player_dict)

	# Notify UI and other systems that the roster changed.
	emit_signal("player_state_changed", peer_id)


## set_players
## Replaces the entire players list (used by clients when receiving roster sync from host).
func set_players(new_players: Array) -> void:
	players = new_players.duplicate(true)
	for p in players:
		if p is Dictionary and p.has("id"):
			emit_signal("player_state_changed", p["id"])


## get_player_ids
## Returns an array of peer IDs for all registered players.
func get_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for p in players:
		if p is Dictionary and p.has("id"):
			ids.append(int(p["id"]))
	return ids


## get_player_position
func get_player_position(peer_id: int) -> int:
	var idx: int = _find_player_index(peer_id)
	if idx != -1:
		return players[idx].get("position", 0)
	return 0


## set_player_position
func set_player_position(peer_id: int, pos: int) -> void:
	var idx: int = _find_player_index(peer_id)
	if idx != -1:
		players[idx]["position"] = pos % board_size
		emit_signal("player_state_changed", peer_id)


## add_money
## Convenience alias for update_player_money
func add_money(peer_id: int, amount: int) -> void:
	update_player_money(peer_id, amount)


## set_in_jail
func set_in_jail(peer_id: int, in_jail: bool) -> void:
	var idx: int = _find_player_index(peer_id)
	if idx != -1:
		players[idx]["in_jail"] = in_jail
		emit_signal("player_state_changed", peer_id)


## is_in_jail
func is_in_jail(peer_id: int) -> bool:
	var idx: int = _find_player_index(peer_id)
	if idx != -1:
		return players[idx].get("in_jail", false)
	return false


## get_player
## Looks up a player dictionary by peer_id. Returns an empty dict {} when the
## peer is not found — callers should check `.is_empty()` before accessing keys.
##
## @param peer_id  The ENet peer ID to look up.
## @return Dictionary — the player dict, or {} if not found.
func get_player(peer_id: int) -> Dictionary:
	var idx: int = _find_player_index(peer_id)
	if idx == -1:
		return {}   # Callers: always guard with .is_empty() / .has("id")
	return players[idx]


## update_player_money
## Adds `delta` to the player's money balance (delta may be negative for rent
## payments, taxes, etc.). After updating, emits player_state_changed so HUD
## labels refresh, then calls check_bankruptcy to evaluate insolvency.
##
## @param peer_id  Target player's peer ID.
## @param delta    Amount to add (positive = gain, negative = loss).
## @return void
func update_player_money(peer_id: int, delta: int) -> void:
	var idx: int = _find_player_index(peer_id)
	if idx == -1:
		push_error("GameState.update_player_money: unknown peer %d" % peer_id)
		return

	# Apply the delta directly on the array element's dictionary.
	# GDScript Dictionaries are reference types, so this mutates in-place.
	players[idx]["money"] += delta

	# Always signal before the bankruptcy check so the HUD shows the updated
	# (possibly negative) balance before we potentially mark the player out.
	emit_signal("player_state_changed", peer_id)

	# Evaluate whether this update pushed the player into insolvency.
	check_bankruptcy(peer_id)


## transfer_money
## Moves `amount` from one player to another atomically. Used for rent
## collection, buying houses, paying fines to other players, etc.
## Both sides emit player_state_changed so both HUDs update.
##
## @param from_id  Peer ID of the payer.
## @param to_id    Peer ID of the recipient.
## @param amount   Positive integer amount to transfer.
## @return void
func transfer_money(from_id: int, to_id: int, amount: int) -> void:
	if amount <= 0:
		push_warning("GameState.transfer_money: amount must be positive (got %d)" % amount)
		return

	# Deduct from payer — this also fires the signal and triggers bankruptcy check.
	update_player_money(from_id, -amount)

	# Credit the recipient (no bankruptcy risk when gaining money).
	# We call update_player_money to keep signal emission consistent.
	update_player_money(to_id, amount)


## advance_turn
## Moves current_player_index forward by one, wrapping around when it reaches
## the end of the players array. Bankrupt players are automatically skipped
## so their turn never fires.
## Emits player_state_changed for the newly active player so the HUD and
## pawn highlight can update.
##
## @return void
func advance_turn() -> void:
	if players.is_empty():
		push_warning("GameState.advance_turn: no players registered.")
		return

	# We may need to loop more than once if consecutive players are bankrupt.
	# The loop is bounded by players.size() to prevent an infinite loop in
	# the degenerate case where all players are bankrupt (game_over should
	# have fired before this state is reached).
	var steps: int = 0
	var total: int = players.size()

	while steps < total:
		current_player_index = (current_player_index + 1) % total
		steps += 1

		# Stop at the first non-bankrupt player we find.
		if not players[current_player_index]["bankrupt"]:
			break

	# Signal the newly active player so the board scene can highlight their
	# pawn and enable their action buttons.
	var active_id: int = players[current_player_index]["id"]
	emit_signal("player_state_changed", active_id)


## get_current_player
## Convenience accessor that resolves the current_player_index to the actual
## player dict so callers don't need to index into players[] themselves.
##
## @return Dictionary — the active player's dict, or {} if players is empty.
func get_current_player() -> Dictionary:
	if players.is_empty():
		return {}
	return players[current_player_index]


## check_bankruptcy
## Evaluates whether a player's money has dropped below zero. If so, marks
## them as bankrupt. After marking, counts non-bankrupt players and emits
## game_over if only one remains.
##
## @param peer_id  The peer ID of the player to evaluate.
## @return bool — true if the player is (newly or previously) bankrupt, else false.
func check_bankruptcy(peer_id: int) -> bool:
	var idx: int = _find_player_index(peer_id)
	if idx == -1:
		push_error("GameState.check_bankruptcy: unknown peer %d" % peer_id)
		return false

	# Already flagged; nothing more to do.
	if players[idx]["bankrupt"]:
		return true

	# Bankruptcy threshold: money strictly below zero. A balance of exactly $0
	# is technically insolvent in some rule sets; adjust the comparison if needed.
	if players[idx]["money"] < 0:
		players[idx]["bankrupt"] = true
		emit_signal("player_state_changed", peer_id)

		# Count how many players are still solvent after this bankruptcy.
		var alive: Array = players.filter(func(p): return not p["bankrupt"])

		if alive.size() == 1:
			# Only one player remains — they win.
			var winner_id: int = alive[0]["id"]
			emit_signal("game_over", winner_id)

		return true

	return false


## reset_game
## Clears all mutable state so a new game can be started without restarting
## Godot. Called by the lobby scene when returning to the main menu or when
## the host restarts the game.
##
## @return void
func reset_game() -> void:
	players.clear()
	current_player_index = 0
	# Restore configurable fields to their defaults in case they were changed.
	board_size = BOARD_SIZE
	starting_money = STARTING_MONEY
	# No signals are emitted here; the calling scene is responsible for
	# tearing down any listeners before invoking reset_game().
