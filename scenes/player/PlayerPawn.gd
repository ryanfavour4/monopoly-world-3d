# =============================================================================
# PlayerPawn.gd
# =============================================================================
# Represents a single player's game piece on the 3-D Monopoly board.
# Handles:
#   • Visual setup (color, username label)
#   • Smooth step-by-step tile traversal via Tween
#   • Landing animations that reflect the game outcome
#   • Idle timeout animation so parked pawns stay lively
#   • Instant jail teleport
#
# Expected scene hierarchy (PlayerPawn.tscn):
#   PlayerPawn (CharacterBody3D)          ← this script
#   ├── AnimationController (Node)        ← AnimationController.gd
#   │   └── AnimationPlayer
#   ├── MeshInstance3D                    ← the visible 3-D pawn mesh
#   ├── NameLabel (Label3D)               ← floating username above the pawn
#   └── IdleTimer (Timer)                 ← fires after 5 s of inactivity
#
# Multiplayer note: This node is spawned and driven by the authority peer that
# owns it (player_id == multiplayer.get_unique_id()). Visual updates (Tween,
# animations) run locally on every client for smooth presentation; the
# authoritative game state lives in PlayerData resources synced by GameManager.
# =============================================================================

extends CharacterBody3D

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## movement_finished
## -----------------
## Emitted when the pawn has finished stepping through every tile along its
## path and is now resting on final_tile.
## BoardManager / GameManager listen to this signal to know when it is safe
## to evaluate the landing tile and advance the turn.
##
## Parameters:
##   player_id  — the peer ID that owns this pawn (mirrors @export var below)
##   final_tile — the board tile index (0–39) where the pawn came to rest
signal movement_finished(player_id: int, final_tile: int)

# ---------------------------------------------------------------------------
# Exports — configured in the editor or by the spawner
# ---------------------------------------------------------------------------

## peer_id
## -------
## The ENet / WebRTC peer ID of the player who owns this pawn.
## Set by GameManager when the pawn is instantiated so that movement_finished
## carries the correct identity back to the turn manager.
@export var player_id: int = 0

## pawn_color
## ----------
## The unique color assigned to this player (distinct across all players in
## the lobby). Applied to the pawn's StandardMaterial3D in setup().
@export var pawn_color: Color = Color.WHITE

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

## anim_controller
## ---------------
## Provides the unified animation interface (play_walk, play_idle, etc.).
## See AnimationController.gd for the full state contract.
@onready var anim_controller: Node = $AnimationController

## name_label
## ----------
## A Label3D that floats above the pawn showing the player's username.
## Configured in setup() so it is always correct even if pawn scenes are
## reused across sessions.
@onready var name_label: Label3D = $NameLabel

## idle_timer
## ----------
## A one-shot Timer (wait_time = 5.0 s, autostart = false).
## Restarted on every player action. When it fires the pawn plays a subtle
## idle tap-feet animation so it doesn't look frozen during long turns.
@onready var idle_timer: Timer = $IdleTimer

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## current_tile
## ------------
## The board tile index (0–39) where this pawn currently stands.
## Updated after each step inside move_to_tile() and after teleport_to_jail().
var current_tile: int = 0

## is_moving
## ---------
## True while move_to_tile() is executing its Tween coroutine.
## Other systems check this flag to avoid issuing a second move command while
## the first is still in progress.
var is_moving: bool = false

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

# Reference to the active Tween so it can be killed cleanly if needed (e.g.,
# the player is sent to jail mid-move by a Chance card).
var _active_tween: Tween = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Connect the idle timer's timeout signal using a Callable (Godot 4 style).
	idle_timer.timeout.connect(_on_idle_timer_timeout)

	# Ensure the timer is not auto-starting in the scene; we manage it manually.
	idle_timer.one_shot = true

	# Start the idle timer immediately so the pawn starts its idle animation
	# if nothing happens within the first 5 seconds of the game.
	reset_idle_timer()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## setup
## -----
## Input : id       — peer ID of the owning player (stored in player_id)
##         username — display name shown on the floating label
##         color    — unique player color applied to the pawn mesh
## Output: none (side-effects: configures label text, mesh material color)
##
## Called once by GameManager / LobbyManager after the pawn scene is spawned.
## Separating initialisation from _ready() means the pawn can be pre-loaded
## and configured without being added to the scene tree first.
func setup(id: int, username: String, color: Color, initial_pos: Vector3 = Vector3.ZERO) -> void:
	player_id  = id
	pawn_color = color

	if initial_pos != Vector3.ZERO:
		global_position = initial_pos

	# Update the floating label so other players see this pawn's owner name.
	if name_label:
		name_label.text = username

	# Tint the pawn mesh with the player's unique color.
	# We create a new StandardMaterial3D so that each pawn has its own material
	# instance and changing one pawn's color never affects the others.
	var mesh_instance := find_child("MeshInstance3D", true, false) as MeshInstance3D
	if mesh_instance:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mesh_instance.material_override = mat


## move_to_tile
## ------------
## Input : target_tile     — destination board tile index (0–39)
##         board_positions — Array[Vector3] of world-space tile centres,
##                           indexed 0–39; provided by BoardManager
##         pass_go         — whether the pawn crosses tile 0 (Go) on this move,
##                           used for the celebrate animation when collecting \$200
## Output: none (async — emits movement_finished when done)
##
## The main movement coroutine. Steps the pawn tile-by-tile along the board
## path rather than teleporting directly to the destination. This keeps the
## visual traversal faithful to the physical board so all players can follow
## the movement clearly.
##
## We step tile-by-tile so the pawn visibly traverses the board path and every
## player at the table (local or remote) can watch the piece move naturally.
##
## Board wrap-around: tile 39 → tile 0 is a valid forward step (passing Go).
## The function computes the ordered list of tiles to visit before tweening.
func move_to_tile(target_tile: int, board_positions: Array, pass_go: bool) -> void:
	# Prevent overlapping move commands.
	if is_moving:
		push_warning("PlayerPawn: move_to_tile() called while already moving. Ignored.")
		return

	is_moving = true
	reset_idle_timer()   # reset inactivity clock while we're clearly active

	# Kill any leftover tween from a previous interrupted move.
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()

	# -----------------------------------------------------------------
	# Build the ordered list of intermediate tile indices to visit.
	# -----------------------------------------------------------------
	# We walk forward around the 40-tile board from current_tile toward
	# target_tile, wrapping through 0 when necessary. This naturally
	# handles the pass-Go scenario without special-casing directions.
	var steps: Array[int] = []
	var tile := current_tile
	while tile != target_tile:
		tile = (tile + 1) % 40   # advance one tile, wrap at 39 → 0
		steps.append(tile)

	# Safety: if current_tile == target_tile no steps are needed
	# (e.g., rolled doubles and landed on same spot via Chance).
	if steps.is_empty():
		is_moving = false
		movement_finished.emit(player_id, current_tile)
		return

	# Start the walk animation so the pawn looks like it is physically moving.
	anim_controller.play_walk()

	# -----------------------------------------------------------------
	# Step through each tile with a Tween for smooth motion.
	# -----------------------------------------------------------------
	# Each step creates a fresh Tween; awaiting tween_all_completed gives us
	# a simple sequential coroutine without a manual timer loop.
	for step_tile in steps:
		var dest: Vector3 = board_positions[step_tile]

		# Compute move duration proportional to distance so the speed stays
		# consistent regardless of tile spacing variation in the board mesh.
		var dist: float = global_position.distance_to(dest)
		var duration: float = clampf(dist / 4.0, 0.15, 0.5)   # 4 units/sec, capped

		_active_tween = create_tween()
		_active_tween.set_ease(Tween.EASE_IN_OUT)
		_active_tween.set_trans(Tween.TRANS_SINE)
		_active_tween.tween_property(self, "global_position", dest, duration)

		# Wait for this step's tween to complete before moving to the next tile.
		await _active_tween.finished

		# Update our tracked position after each step so intermediate state is
		# always accurate (useful if the pawn is interrupted mid-move).
		current_tile = step_tile

	# -----------------------------------------------------------------
	# Movement complete — play arrival / landing animation.
	# -----------------------------------------------------------------
	is_moving = false

	# Walk animation will be replaced by the landing animation below.
	# (play_land_animation calls anim_controller methods which handle the
	#  transition internally.)

	# Emit the signal so GameManager can evaluate the landing tile and
	# determine what action to take (buy, pay rent, tax, jail, etc.).
	movement_finished.emit(player_id, current_tile)


## play_land_animation
## -------------------
## Input : landing_result — Dictionary produced by BoardManager / TileManager
##         after evaluating the tile the pawn stopped on. Expected keys:
##             "action"  : String — one of:
##                           "buy_available" | "pay_rent" | "pay_tax" |
##                           "collect_go"    | "go_to_jail" | "idle" | ...
##             (other keys such as "amount", "owner_id" are ignored here)
## Output: none (side-effect: drives AnimationController to appropriate state)
##
## Maps game outcomes to emotional animations so the pawn's body language
## immediately communicates what happened to all players watching.
func play_land_animation(landing_result: Dictionary) -> void:
	var action: String = landing_result.get("action", "idle")

	match action:
		"buy_available":
			# Property is unowned and can be purchased — exciting!
			anim_controller.play_dance()

		"collect_go":
			# Passed or landed on Go, collecting \$200 salary — celebrate!
			anim_controller.play_dance()

		"pay_rent":
			# Must pay rent to the property owner — unhappy reaction.
			anim_controller.play_sad()

		"pay_tax":
			# Landed on Income Tax or Luxury Tax — unhappy reaction.
			anim_controller.play_sad()

		"celebrate":
			# Generic positive event (Free Parking, lucky Chance, etc.).
			anim_controller.play_celebrate()

		_:
			# Community Chest, Chance (neutral), Just Visiting jail, etc.
			anim_controller.play_idle()

	# Any action counts as activity; reset idle clock so the pawn doesn't
	# immediately start its idle tap animation right after landing.
	reset_idle_timer()


## reset_idle_timer
## ----------------
## Input : none
## Output: none (side-effect: restarts IdleTimer from its configured wait_time)
##
## Call this whenever the player performs any visible action (move, card draw,
## purchase, etc.) so the 5-second idle timeout is pushed back appropriately.
func reset_idle_timer() -> void:
	if idle_timer:
		idle_timer.stop()
		idle_timer.start()   # restarts from wait_time (set to 5.0 s in scene)


## teleport_to_jail
## ----------------
## Input : none (uses board_positions index 10 which is the Jail/Just Visiting tile)
## Output: none (side-effect: instantly repositions pawn to tile 10)
##
## Used when the pawn is sent to jail by a card, tile, or three-doubles rule.
## No step-by-step movement animation is played — the instant teleport signals
## to all players that something dramatic has happened (matches physical board
## table-talk: "Go directly to jail, do not pass Go!").
##
## The caller (GameManager) is responsible for:
##   1. Updating the player's PlayerData.board_position to 10.
##   2. Setting PlayerData.in_jail = true.
##   3. Calling this function to move the visual pawn.
## We intentionally keep this function free of game-logic side-effects so it
## can also be used for scene setup / board reset without mutating game state.
func teleport_to_jail() -> void:
	# Stop any in-progress tween immediately to avoid fighting with the
	# teleport position assignment.
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	is_moving = false

	# Tile 10 is always the Jail / Just Visiting corner on a standard board.
	current_tile = 10

	# The pawn's world position is set directly by the caller after this
	# returns, OR the caller passes the board_positions array. Here we simply
	# flag readiness; if board_positions is needed, extend the signature.
	# For now the calling code is expected to set global_position directly:
	#   pawn.teleport_to_jail()
	#   pawn.global_position = board_positions[10]
	#
	# Play a sad animation to reinforce the punishment.
	anim_controller.play_sad()

	# Reset idle timer since the pawn just had an event.
	reset_idle_timer()


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

## _on_idle_timer_timeout
## ----------------------
## Fired by IdleTimer after 5 seconds of no activity.
## Plays the looping Idle animation (subtle breathing / tap-feet) to keep the
## pawn looking alive while its owner is deciding what to do or waiting for
## another player's turn to end.
func _on_idle_timer_timeout() -> void:
	# Only play idle if the pawn isn't currently moving — we don't want to
	# interrupt a walk animation that is mid-step.
	if not is_moving:
		anim_controller.play_idle()
