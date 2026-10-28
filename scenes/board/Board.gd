###############################################################################
# Board.gd
# Attached to: scenes/board/Board.tscn  →  root node "Board" (Node3D)
#
# PURPOSE:
#   Top-level orchestrator for the 3-D Monopoly board scene. Responsible for:
#     • Spawning a PlayerPawn for every registered player.
#     • Wiring signals between subsystems (TurnManager, BoardManager, UIManager,
#       GameState, individual pawns).
#     • Delegating landing-tile logic to BoardManager and UI feedback to
#       UIManager.
#     • Handling idle detection and game-over events.
#
# EXPECTED NODE TREE (create this structure in the Godot editor):
#
#   Board  (Node3D)  ← this script goes here
#   │
#   ├── Camera3D
#   │       Position  = Vector3(0, 15, 0)
#   │       Rotation  = Vector3(-90, 0, 0)   ← looks straight down
#   │       Projection = ORTHOGONAL
#   │       Size (orthographic) ≈ 22          ← adjust until board fills view
#   │
#   ├── DirectionalLight3D
#   │       Rotation  = Vector3(-60, 30, 0)  ← angled "sunlight"
#   │       Shadow enabled for visual depth.
#   │
#   ├── BoardMesh  (MeshInstance3D)
#   │       A flat PlaneMesh (or imported board model) centred at origin.
#   │       Attach a collision shape if ray-casting tile positions.
#   │
#   ├── TileMarkers  (Node3D)
#   │       Contains exactly 40 child nodes of type BoardTile (Area3D or
#   │       Marker3D). Each child is named "Tile0" … "Tile39" and is
#   │       positioned at the correct world-space location on the board mesh.
#   │       BoardManager reads these positions to move pawns.
#   │
#   ├── Pawns  (Node3D)
#   │       Empty at edit time — PlayerPawn instances are added here at
#   │       runtime by _spawn_pawns().
#   │
#   ├── BoardManager  (Node)
#   │       Script: res://scripts/board/BoardManager.gd
#   │       Signals emitted:
#   │           player_landed(player_id: int, tile_index: int)
#   │
#   ├── TurnManager  (Node)
#   │       Script: res://scripts/board/TurnManager.gd
#   │       Signals emitted:
#   │           turn_started(player_id: int)
#   │           idle_detected(player_id: int)
#   │       Child nodes:
#   │           └── IdleTimer  (Timer)
#   │                   Wait time = 30.0 s (configurable in inspector)
#   │                   One-shot = true
#   │
#   └── UI  (CanvasLayer)
#           ├── UIManager  (Control)
#           │       Script: res://scripts/ui/UIManager.gd
#           │       Manages HUD, notifications, and modal routing.
#           │
#           ├── CasinoModal  (Control)
#           │       Script: res://scripts/ui/CasinoModal.gd
#           │       Pop-up for casino mini-game results and winner screen.
#           │
#           ├── InventoryPanel  (Control)
#           │       Script: res://scripts/ui/InventoryPanel.gd
#           │       Shows the local player's owned properties.
#           │
#           ├── DiceRoller  (Control)
#           │       Script: res://scripts/ui/DiceRoller.gd
#           │       Animated dice display + "Roll" button.
#           │
#           └── TurnBanner  (Label)
#                   Displayed at the top of the screen.
#                   Text updated by UIManager.show_turn_notification().
#
# DEPENDENCIES (autoloads / singletons):
#   • GameState    — Dictionary of players, current turn, game-over signal
#   • TurnManager  — also available as a node child (see tree above)
#   • BoardManager — also available as a node child (see tree above)
#
# EXPORTS:
#   player_pawn_scene  — drag res://scenes/pawns/PlayerPawn.tscn here in the
#                        Godot inspector before running the game.
###############################################################################

extends Node3D

# ---------------------------------------------------------------------------
# Exports — set in the Godot inspector.
# ---------------------------------------------------------------------------

## The PackedScene for a single player pawn.
## Assign res://scenes/pawns/PlayerPawn.tscn in the inspector.
@export var player_pawn_scene: PackedScene


# ---------------------------------------------------------------------------
# Node references — resolved at runtime via @onready.
# ---------------------------------------------------------------------------

## Handles tile data, property ownership, and landing rules.
@onready var board_manager: Node = get_node_or_null("/root/BoardManager") if has_node("/root/BoardManager") else $BoardManager

## Manages whose turn it is, dice rolls, and idle timeouts.
@onready var turn_manager: Node = get_node_or_null("/root/TurnManager") if has_node("/root/TurnManager") else $TurnManager

## Root of the 2-D HUD overlay; routes UI events and shows modals.
@onready var ui_manager: Node = $UI/UIManager

## Container that holds all spawned PlayerPawn instances.
@onready var pawns_container: Node3D = $Pawns

## Parent of the 40 BoardTile child nodes; used by BoardManager to get
## world-space positions for moving pawns.
@onready var tile_markers: Node3D = $TileMarkers


# ---------------------------------------------------------------------------
# State — internal data used during gameplay.
# ---------------------------------------------------------------------------

## Dictionary mapping peer_id (int) → PlayerPawn node.
## Populated by _spawn_pawns() and used throughout the session.
var pawns: Dictionary = {}


# ---------------------------------------------------------------------------
# _ready — called once when the Board scene is fully loaded.
#
# Execution order:
#   1. Spawn a pawn for every player in GameState.players.
#   2. Wire all cross-system signals.
#   3. Hand the ordered peer_id list to TurnManager.
#   4. Kick off the first turn.
# ---------------------------------------------------------------------------
func _ready() -> void:
	# ── 1. Spawn pawns ────────────────────────────────────────────────────
	_spawn_pawns()

	# ── 2. Signal wiring ──────────────────────────────────────────────────

	# TurnManager.turn_started → UIManager: show whose turn it is.
	turn_manager.turn_started.connect(func(pid: int):
		var p_data: Dictionary = GameState.get_player(pid)
		var uname: String = p_data.get("username", "Player %d" % pid)
		var is_local: bool = (pid == multiplayer.get_unique_id())
		ui_manager.show_turn_notification(pid, uname, is_local)
		var dice_node = get_node_or_null("UI/DiceRoller")
		if dice_node and dice_node.has_method("set_my_turn"):
			dice_node.set_my_turn(is_local)
	)

	# Dice roll completed → TurnManager.on_dice_rolled
	var dice_node = get_node_or_null("UI/DiceRoller")
	if dice_node and dice_node.has_signal("roll_completed"):
		dice_node.roll_completed.connect(func(d1: int, d2: int, _tot: int):
			turn_manager.on_dice_rolled(d1, d2)
		)

	# TurnManager.idle_detected → Board: animate the idle pawn.
	# Fired after IdleTimer expires without a dice roll from the active player.
	turn_manager.idle_detected.connect(_on_player_idle)

	# BoardManager.player_landed → Board: resolve landing consequences.
	# Fired after a pawn finishes moving to its destination tile.
	board_manager.player_landed.connect(_on_player_landed)

	# GameState.game_over → Board: show the winner screen.
	# Fired when a player's money drops to 0 (or another end condition).
	GameState.game_over.connect(_on_game_over)

	# ── 3. TurnManager setup ──────────────────────────────────────────────
	var peer_ids: Array[int] = GameState.get_player_ids()

	if turn_manager.get_turn_order().is_empty():
		peer_ids.shuffle()
		turn_manager.setup_turn_order(peer_ids)

	# ── 4. Begin the first turn ───────────────────────────────────────────
	var first_player_id: int = turn_manager.get_current_player_id()
	if first_player_id != 0:
		turn_manager.begin_turn(first_player_id)


# ---------------------------------------------------------------------------
# _spawn_pawns  (private)
# ---------------------------------------------------------------------------
func _spawn_pawns() -> void:
	if player_pawn_scene == null:
		push_error("Board: player_pawn_scene export is not set! Assign PlayerPawn.tscn in inspector.")
		return

	# Retrieve the world-space position of Tile 0
	var start_position: Vector3 = Vector3.ZERO
	if board_manager and board_manager.tile_world_positions.size() > 0:
		start_position = board_manager.tile_world_positions[0]
	elif tile_markers:
		var start_tile: Node = tile_markers.get_node_or_null("Tile0")
		if start_tile:
			start_position = start_tile.global_position

	var player_index: int = 0
	var total_players: int = max(GameState.players.size(), 1)

	for player_data in GameState.players:
		if not (player_data is Dictionary):
			continue
		var peer_id: int = player_data.get("id", 0)

		# ── Instantiate ───────────────────────────────────────────────────
		var pawn: Node3D = player_pawn_scene.instantiate()
		pawns_container.add_child(pawn)

		# Small positional offset so pawns don't overlap on GO
		var offset := Vector3(
			cos(player_index * TAU / total_players) * 0.35,
			0.0,
			sin(player_index * TAU / total_players) * 0.35
		)

		# Setup pawn
		var p_color: Color = player_data.get("color", Color.WHITE)
		var p_name: String = player_data.get("username", "Player %d" % peer_id)
		pawn.setup(peer_id, p_name, p_color, start_position + offset)

		# Connect movement finished to landing handler
		if pawn.has_signal("movement_finished"):
			pawn.movement_finished.connect(_on_player_landed)

		pawns[peer_id] = pawn
		player_index += 1


## move_pawn
## Called by TurnManager to move a pawn across board spaces
func move_pawn(player_id: int, new_tile: int, passed_go: bool) -> void:
	if pawns.has(player_id):
		pawns[player_id].move_to_tile(new_tile, board_manager.tile_world_positions, passed_go)
	else:
		# Fallback if pawn not found
		_on_player_landed(player_id, new_tile)


# ---------------------------------------------------------------------------
# _on_player_landed
# ---------------------------------------------------------------------------
func _on_player_landed(player_id: int, tile_index: int) -> void:
	var result: Dictionary = board_manager.handle_landing(player_id, tile_index, 0)
	ui_manager.handle_landing_result(player_id, result)

	if pawns.has(player_id):
		pawns[player_id].play_land_animation(result)
	else:
		push_warning("Board: No pawn found for player_id %d" % player_id)


# ---------------------------------------------------------------------------
# _on_player_idle
# ---------------------------------------------------------------------------
func _on_player_idle(player_id: int) -> void:
	if not pawns.has(player_id):
		return

	var pawn = pawns[player_id]
	if pawn.has_method("get_anim_controller"):
		pawn.get_anim_controller().play_idle()
	elif "anim_controller" in pawn and pawn.anim_controller != null:
		pawn.anim_controller.play_idle()


# ---------------------------------------------------------------------------
# _on_game_over
# ---------------------------------------------------------------------------
func _on_game_over(winner_id: int) -> void:
	var winner_data: Dictionary = GameState.get_player(winner_id)
	var winner_name: String = winner_data.get("username", "Player %d" % winner_id)
	var announcement: String = "🏆 %s WINS!" % winner_name

	if ui_manager.has_method("show_winner_modal"):
		ui_manager.show_winner_modal(winner_id, announcement)
	else:
		var casino_modal: Node = get_node_or_null("UI/CasinoModal")
		if casino_modal and casino_modal.has_method("show_info_modal"):
			casino_modal.show_info_modal("🏆 GAME OVER", announcement)
