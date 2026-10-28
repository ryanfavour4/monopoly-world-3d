###############################################################################
# TurnManager.gd
# Path: scenes/board/TurnManager.gd
#
# PURPOSE:
#   Controls the full lifecycle of a single Monopoly turn, from deciding whose
#   turn it is, through dice rolling and player movement, all the way to
#   landing resolution and end-of-turn advancement.
#
#   This node lives as a child of the Board scene and acts as the central
#   authority for turn flow. In multiplayer, only the HOST (the Godot
#   "multiplayer authority") runs the real logic; clients receive RPC calls
#   to synchronise their local state.
#
# SIGNALS:
#   turn_started(player_id)   — emitted when a player's turn begins.
#   turn_ended(player_id)     — emitted when a player's turn fully ends.
#   idle_detected(player_id)  — emitted when 5 s of inactivity passes.
#   dice_roll_requested(player_id) — internal; DiceRoller listens to enable
#                                    the roll button for the active player.
#
# DEPENDENCIES:
#   - AudioManager   : autoload; provides AudioManager.play_ding()
#   - GameState      : autoload; stores per-player position, money, jail state
#   - BoardManager   : autoload or sibling node; handles landing rules
#   - UIManager      : autoload; shows modals / action panels
###############################################################################

extends Node

# ---------------------------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------------------------

## Emitted at the very start of a player's turn so that UI and other systems
## can react (e.g., highlight the active player token, enable the dice UI).
signal turn_started(player_id: int)

## Emitted after the player has finished all post-roll actions and explicitly
## (or automatically) ends their turn.
signal turn_ended(player_id: int)

## Emitted when idle_timer fires — the player has not rolled within 5 seconds.
## Connected by the AnimationManager to trigger an idle/waiting animation on
## the player's token.
signal idle_detected(player_id: int)

## Internal signal; DiceRoller connects to this to know when it should become
## interactive (i.e., when it should allow the local player to press "Roll").
signal dice_roll_requested(player_id: int)

# ---------------------------------------------------------------------------
# ONREADY REFERENCES
# ---------------------------------------------------------------------------

var idle_timer: Timer

func _ready() -> void:
	if has_node("IdleTimer"):
		idle_timer = $IdleTimer
	else:
		idle_timer = Timer.new()
		idle_timer.name = "IdleTimer"
		idle_timer.wait_time = 5.0
		idle_timer.one_shot = true
		add_child(idle_timer)
	if not idle_timer.timeout.is_connected(_on_idle_timer_timeout):
		idle_timer.timeout.connect(_on_idle_timer_timeout)

# ---------------------------------------------------------------------------
# STATE VARIABLES
# ---------------------------------------------------------------------------

## The peer ID of whichever player is currently taking their turn.
## Peer ID 1 is typically the host in Godot's ENet/WebRTC multiplayer.
var current_player_id: int = 0

## Tracks whether the active player has already rolled the dice this turn.
## Prevents rolling twice in a single turn (unless doubles are rolled).
var has_rolled_this_turn: bool = false

## Counts how many consecutive doubles the active player has rolled.
## Rolling three doubles in a row sends the player directly to Jail.
var doubles_count: int = 0

## Ordered list of peer IDs representing the turn sequence.
## Populated once at game start by setup_turn_order() and never reshuffled
## mid-game (standard Monopoly rules).
var turn_order: Array[int] = []

## Internal index into turn_order pointing at the player whose turn it is.
## Advances by 1 (with wrap-around) each time end_turn() is called and
## doubles were NOT rolled.
var _turn_order_index: int = 0

# ---------------------------------------------------------------------------
# SETUP
# ---------------------------------------------------------------------------

## Called once at game start (by GameManager or Board scene _ready).
## Receives the full list of connected peer IDs, shuffles them to establish
## a random turn order, and stores the result in turn_order.
##
## @param player_ids  Array of integer peer IDs for every human player.
func setup_turn_order(player_ids: Array[int]) -> void:
	# Work on a copy so we don't mutate the caller's array.
	var ids: Array[int] = player_ids.duplicate()

	# Fisher-Yates shuffle for a fair random order.
	for i in range(ids.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp: int = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp

	turn_order = ids
	_turn_order_index = 0

	print("[TurnManager] Turn order established: ", turn_order)

	# Synchronize to all peers if multiplayer
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc_sync_turn_order.rpc(turn_order)


@rpc("authority", "call_local", "reliable")
func rpc_sync_turn_order(order: Array) -> void:
	var int_order: Array[int] = []
	for id in order:
		int_order.append(int(id))
	turn_order = int_order
	_turn_order_index = 0
	print("[TurnManager] Synced turn order from host: ", turn_order)


func get_turn_order() -> Array[int]:
	return turn_order


func get_current_player_id() -> int:
	if turn_order.is_empty():
		return current_player_id
	return turn_order[_turn_order_index]

# ---------------------------------------------------------------------------
# TURN LIFECYCLE
# ---------------------------------------------------------------------------

## Starts a new turn for the given player.
## Resets per-turn state, kicks off the idle timer, plays a ding sound,
## and notifies all listeners that a new turn has begun.
##
## Called directly on the host, and mirrored on clients via rpc_begin_turn().
##
## @param player_id  The peer ID of the player whose turn is starting.
func begin_turn(player_id: int) -> void:
	# ---- Update state ----
	current_player_id  = player_id
	has_rolled_this_turn = false
	# doubles_count is intentionally NOT reset here — it persists across
	# the "bonus rolls" a player gets for rolling doubles.  It IS reset
	# inside on_dice_rolled() when the player does NOT roll doubles.

	# ---- Start idle watchdog ----
	# If idle_timer is already running (edge case), stop it first to avoid
	# double-firing.
	if idle_timer.time_left > 0.0:
		idle_timer.stop()
	idle_timer.start()

	# ---- Audio feedback ----
	# AudioManager is an autoload; play_ding() should be non-blocking.
	if Engine.has_singleton("AudioManager"):
		AudioManager.play_ding()

	# ---- Notify listeners ----
	turn_started.emit(player_id)

	# Signal the DiceRoller so it knows to activate for the local player
	# (DiceRoller will internally check if player_id matches the local peer).
	dice_roll_requested.emit(player_id)

	print("[TurnManager] Turn started for player: ", player_id)


## Called by DiceRoller or active player to request a roll
func request_roll() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_request_roll.rpc_id(1)
	else:
		_host_generate_and_broadcast_roll()


@rpc("any_peer", "reliable")
func rpc_request_roll() -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != current_player_id:
		push_warning("[TurnManager] Peer %d requested roll but current player is %d" % [sender_id, current_player_id])
		return
	_host_generate_and_broadcast_roll()


func _host_generate_and_broadcast_roll() -> void:
	var d1: int = randi_range(1, 6)
	var d2: int = randi_range(1, 6)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc_roll_dice.rpc(d1, d2)
	else:
		rpc_roll_dice(d1, d2)


@rpc("authority", "call_local", "reliable")
func rpc_roll_dice(die1: int, die2: int) -> void:
	var dice_node: Node = get_tree().root.find_child("DiceRoller", true, false)
	if dice_node and dice_node.has_method("play_roll"):
		dice_node.play_roll(die1, die2)

	var dice_3d: Node = get_tree().root.find_child("Dice3D", true, false)
	if dice_3d and dice_3d.has_method("play_roll"):
		dice_3d.play_roll(die1, die2)

	# The server resolves movement after dice animation settles (approx 1.2s)
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		get_tree().create_timer(1.2).timeout.connect(func():
			on_dice_rolled(die1, die2)
		)


## Called by DiceRoller after a roll animation completes.
## Handles doubles logic, calculates the move total, and triggers movement.
##
## In multiplayer this is ONLY called on the host; clients receive the result
## via RPC and display it through DiceRoller.show_result().
##
## @param die1  Value of the first die  (1–6).
## @param die2  Value of the second die (1–6).
func on_dice_rolled(die1: int, die2: int) -> void:
	# ---- Guard: must be the host's responsibility ----
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		push_warning("[TurnManager] on_dice_rolled called on a client — ignoring.")
		return

	# ---- Stop idle timer (player is active) ----
	idle_timer.stop()

	# ---- Mark that the player has rolled ----
	has_rolled_this_turn = true

	var total: int = die1 + die2
	var rolled_doubles: bool = (die1 == die2)

	print("[TurnManager] Player %d rolled %d + %d = %d (doubles: %s)" \
		% [current_player_id, die1, die2, total, rolled_doubles])

	if rolled_doubles:
		doubles_count += 1
		print("[TurnManager] Doubles count: ", doubles_count)

		# Three consecutive doubles → go to jail immediately (Monopoly rule).
		if doubles_count >= 3:
			print("[TurnManager] Three doubles! Sending player to jail.")
			send_to_jail(current_player_id)
			return
	else:
		# Not doubles; reset the streak.
		doubles_count = 0

	# ---- Execute the move ----
	_move_player(current_player_id, total)


## Private.  Computes the new board position for the player and triggers the
## movement animation.  Handles GO wrap-around (40 tiles on a standard board).
func _move_player(player_id: int, steps: int) -> void:
	var current_pos: int = GameState.get_player_position(player_id)
	const BOARD_SIZE: int = 40
	var new_pos: int = (current_pos + steps) % BOARD_SIZE
	var passed_go: bool = (current_pos + steps) >= BOARD_SIZE

	if passed_go:
		print("[TurnManager] Player %d passed GO! Awarding $200." % player_id)
		GameState.add_money(player_id, 200)

	GameState.set_player_position(player_id, new_pos)
	print("[TurnManager] Moving player %d: %d → %d" % [player_id, current_pos, new_pos])

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc_move_player.rpc(player_id, new_pos, passed_go)
	else:
		rpc_move_player(player_id, new_pos, passed_go)


@rpc("authority", "call_local", "reliable")
func rpc_move_player(player_id: int, target_tile: int, passed_go: bool) -> void:
	GameState.set_player_position(player_id, target_tile)
	if passed_go:
		var ui: Node = get_tree().root.find_child("UIManager", true, false)
		if ui and ui.has_method("show_passed_go_toast"):
			ui.show_passed_go_toast(player_id)

	var board_node: Node = get_tree().root.find_child("Board", true, false)
	if board_node and board_node.has_method("move_pawn"):
		board_node.move_pawn(player_id, target_tile, passed_go)
	else:
		_handle_landing(player_id, target_tile)


## Private.  Resolves the rules effect of landing on a particular tile.
## Delegates the actual rule logic to BoardManager and shows the relevant UI.
##
## @param player_id   Peer ID of the player who just landed.
## @param tile_index  The 0-based index of the tile they landed on.
func _handle_landing(player_id: int, tile_index: int) -> void:
	print("[TurnManager] Handling landing: player %d on tile %d" \
		% [player_id, tile_index])

	BoardManager.handle_landing(player_id, tile_index)

	var ui: Node = get_tree().root.find_child("UIManager", true, false)
	if ui and ui.has_method("show_landing_ui"):
		ui.show_landing_ui(player_id, tile_index)

	# After landing resolution, the turn is considered "awaiting player action"
	# (e.g., the player must press "End Turn" or complete a purchase).
	# The end_turn() call will come from the UI or from an automatic timer.


## Called when the active player (or host on their behalf) ends the turn.
## Emits turn_ended, then advances to the next player and begins their turn.
##
## If the player rolled doubles, they get another turn (unless they were sent
## to jail for three consecutive doubles — handled in on_dice_rolled).
func end_turn() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_request_end_turn.rpc_id(1)
	else:
		_execute_end_turn()


@rpc("any_peer", "reliable")
func rpc_request_end_turn() -> void:
	if not multiplayer.is_server():
		return
	_execute_end_turn()


func _execute_end_turn() -> void:
	print("[TurnManager] Ending turn for player: ", current_player_id)
	turn_ended.emit(current_player_id)

	# ---- Doubles: same player goes again ----
	if doubles_count > 0:
		print("[TurnManager] Doubles! Player %d rolls again." % current_player_id)
		# Reset has_rolled so the dice UI re-enables.
		has_rolled_this_turn = false
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			rpc_begin_turn.rpc(current_player_id)
		else:
			begin_turn(current_player_id)
		return

	if turn_order.is_empty():
		return

	# ---- Advance to next player ----
	_turn_order_index = (_turn_order_index + 1) % turn_order.size()
	var next_player_id: int = turn_order[_turn_order_index]

	# In multiplayer the host drives all turn transitions via RPC so every
	# client processes the same turn order simultaneously.
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc_begin_turn.rpc(next_player_id)
	else:
		# Single-player or offline mode.
		begin_turn(next_player_id)

# ---------------------------------------------------------------------------
# IDLE HANDLING
# ---------------------------------------------------------------------------

## Connected to IdleTimer's timeout signal (set up in the scene).
## Fires when the current player has not rolled within 5 seconds.
## The AnimationManager listens to idle_detected to play a waiting animation
## on the player's token (tapping foot, looking around, etc.).
func _on_idle_timer_timeout() -> void:
	print("[TurnManager] Idle detected for player: ", current_player_id)
	idle_detected.emit(current_player_id)
	# NOTE: We do NOT end the turn automatically here — a human-controlled
	# player might just be reading the board.  Auto-end could be added as
	# a configurable game option in a future iteration.

# ---------------------------------------------------------------------------
# JAIL
# ---------------------------------------------------------------------------

## Sends the given player directly to Jail (tile 10, "Just Visiting / Jail").
## Sets the in_jail flag in GameState and immediately ends their turn.
##
## Called either from on_dice_rolled() (three doubles) or from a "Go to Jail"
## tile landing (tile 30) handled by BoardManager which calls back here.
##
## @param player_id  Peer ID of the player being jailed.
func send_to_jail(player_id: int) -> void:
	const JAIL_TILE: int = 10  # Standard Monopoly jail position.

	print("[TurnManager] Sending player %d to Jail (tile %d)." \
		% [player_id, JAIL_TILE])

	# Teleport the player to the jail tile (no GO bonus for this move).
	GameState.set_player_position(player_id, JAIL_TILE)
	GameState.set_in_jail(player_id, true)

	# Reset the doubles streak — jailed players start fresh.
	doubles_count = 0

	var ui: Node = get_tree().root.find_child("UIManager", true, false)
	if ui and ui.has_method("show_go_to_jail_modal"):
		ui.show_go_to_jail_modal(player_id)

	# End the turn without allowing another roll.
	end_turn()

# ---------------------------------------------------------------------------
# TRANSACTIONS & GAMEPLAY ACTIONS
# ---------------------------------------------------------------------------

## purchase_property
## Deducts property cost, assigns ownership, updates player inventory
func purchase_property(player_id: int, tile_index: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_request_purchase.rpc_id(1, tile_index)
	else:
		_execute_purchase(player_id, tile_index)


@rpc("any_peer", "reliable")
func rpc_request_purchase(tile_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_execute_purchase(sender_id, tile_index)


func _execute_purchase(player_id: int, tile_index: int) -> void:
	var tile: BoardTileData = BoardManager.get_tile(tile_index)
	if not tile:
		return
	var player: Dictionary = GameState.get_player(player_id)
	if player.is_empty():
		return

	if player.get("money", 0) >= tile.purchase_price:
		GameState.update_player_money(player_id, -tile.purchase_price)
		BoardManager.set_tile_owner(tile_index, player_id)
		GameState.add_player_property(player_id, tile_index)
		print("[TurnManager] Player %d purchased %s for $%d" % [player_id, tile.tile_name, tile.purchase_price])

		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			rpc_sync_state.rpc(GameState.players, BoardManager.get_all_owners())
		else:
			# Local update for offline or single-player
			var inv: Node = get_tree().root.find_child("InventoryPanel", true, false)
			if inv and inv.has_method("refresh_inventory"):
				inv.refresh_inventory(player_id)
			var spawner: Node = get_tree().root.find_child("BuildingSpawner", true, false)
			if spawner and spawner.has_method("sync_buildings"):
				spawner.sync_buildings()


## upgrade_property
## Upgrades house / hotel on property
func upgrade_property(player_id: int, tile_index: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_request_upgrade.rpc_id(1, tile_index)
	else:
		_execute_upgrade(player_id, tile_index)


@rpc("any_peer", "reliable")
func rpc_request_upgrade(tile_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_execute_upgrade(sender_id, tile_index)


func _execute_upgrade(player_id: int, tile_index: int) -> void:
	if not BoardManager.can_build_house(player_id, tile_index):
		return
	var success: bool = BoardManager.build_house(player_id, tile_index)
	if success:
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			rpc_sync_state.rpc(GameState.players, BoardManager.get_all_owners())
		else:
			var inv: Node = get_tree().root.find_child("InventoryPanel", true, false)
			if inv and inv.has_method("refresh_inventory"):
				inv.refresh_inventory(player_id)
			var spawner: Node = get_tree().root.find_child("BuildingSpawner", true, false)
			if spawner and spawner.has_method("sync_buildings"):
				spawner.sync_buildings()


## pay_rent
## Transfers rent amount from player to owner
func pay_rent(player_id: int, owner_id: int, rent_amount: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_request_pay_rent.rpc_id(1, owner_id, rent_amount)
	else:
		_execute_pay_rent(player_id, owner_id, rent_amount)


@rpc("any_peer", "reliable")
func rpc_request_pay_rent(owner_id: int, rent_amount: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_execute_pay_rent(sender_id, owner_id, rent_amount)


func _execute_pay_rent(player_id: int, owner_id: int, rent_amount: int) -> void:
	GameState.transfer_money(player_id, owner_id, rent_amount)
	print("[TurnManager] Player %d paid $%d rent to Player %d" % [player_id, rent_amount, owner_id])
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc_sync_state.rpc(GameState.players, BoardManager.get_all_owners())


@rpc("authority", "call_local", "reliable")
func rpc_sync_state(synced_players: Array, synced_owners: Dictionary) -> void:
	GameState.set_players(synced_players)
	BoardManager.set_all_owners(synced_owners)
	var ui: Node = get_tree().root.find_child("UIManager", true, false)
	if ui and ui.has_method("refresh_all_hud"):
		ui.refresh_all_hud()
	var inv: Node = get_tree().root.find_child("InventoryPanel", true, false)
	if inv and inv.has_method("refresh_inventory"):
		inv.refresh_inventory(multiplayer.get_unique_id())
	var spawner: Node = get_tree().root.find_child("BuildingSpawner", true, false)
	if spawner and spawner.has_method("sync_buildings"):
		spawner.sync_buildings()


## apply_money_delta
func apply_money_delta(player_id: int, delta: int) -> void:
	GameState.update_player_money(player_id, delta)
	print("[TurnManager] Applied $%d delta to player %d" % [delta, player_id])


## move_player_to_tile
func move_player_to_tile(player_id: int, target_tile: int, pass_go: bool = false) -> void:
	if pass_go:
		GameState.add_money(player_id, 200)
	GameState.set_player_position(player_id, target_tile)
	var board_node: Node = get_tree().root.find_child("Board", true, false)
	if board_node and board_node.has_method("move_pawn"):
		board_node.move_pawn(player_id, target_tile, pass_go)
	else:
		_handle_landing(player_id, target_tile)


## move_player_relative
func move_player_relative(player_id: int, delta_steps: int) -> void:
	var cur_pos: int = GameState.get_player_position(player_id)
	var new_pos: int = (cur_pos + delta_steps + GameState.board_size) % GameState.board_size
	GameState.set_player_position(player_id, new_pos)
	var board_node: Node = get_tree().root.find_child("Board", true, false)
	if board_node and board_node.has_method("move_pawn"):
		board_node.move_pawn(player_id, new_pos, false)
	else:
		_handle_landing(player_id, new_pos)


## move_to_nearest_railroad
## Advances player to the nearest railroad space (5, 15, 25, 35)
func move_to_nearest_railroad(player_id: int) -> void:
	var cur_pos: int = GameState.get_player_position(player_id)
	const RAILROADS: Array[int] = [5, 15, 25, 35]
	var target: int = RAILROADS[0]
	for rr in RAILROADS:
		if rr > cur_pos:
			target = rr
			break
	var pass_go: bool = target < cur_pos
	move_player_to_tile(player_id, target, pass_go)


## apply_chance_card / apply_community_chest_card
func apply_chance_card(player_id: int, card: Dictionary) -> void:
	if card.get("delta", 0) != 0:
		GameState.update_player_money(player_id, card["delta"])


func apply_community_chest_card(player_id: int, card: Dictionary) -> void:
	if card.get("delta", 0) != 0:
		GameState.update_player_money(player_id, card["delta"])

## Host → all clients: synchronises the start of a new turn.
## The host calls this instead of begin_turn() directly so that every client
## updates its local current_player_id and UI simultaneously.
##
## "authority" means only the multiplayer authority (host) may invoke this RPC.
## "reliable" ensures the packet is delivered even on lossy connections.
##
## Clients receive this call and run begin_turn() locally, which updates their
## UI (highlights the correct player, activates the dice for the local player
## if they are the active one, etc.).
@rpc("authority", "call_local", "reliable")
func rpc_begin_turn(player_id: int) -> void:
	begin_turn(player_id)
