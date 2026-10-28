###############################################################################
# DiceRoller.gd
# Path: scenes/board/DiceRoller.gd
#
# PURPOSE:
#   A Control node that owns the dice UI and all dice-rolling logic.
#   It provides:
#     • An animated "roll" that rapidly cycles random numbers before settling
#       on the final result (giving visual excitement to the roll).
#     • Guards against double-tapping or rolling out of turn.
#     • A clean interface for the host to broadcast the authoritative result
#       to all clients (show_result via RPC).
#
# MULTIPLAYER ARCHITECTURE:
#   ┌─────────────────────────────────────────────────────────────────┐
#   │  HOST                            │  CLIENTS                    │
#   │  ─────────────────────────────── │  ──────────────────────────  │
#   │  1. Player presses Roll button.  │                             │
#   │  2. on_roll_pressed() runs.      │                             │
#   │  3. _animate_roll() plays.       │                             │
#   │  4. roll_dice() generates the    │                             │
#   │     authoritative result.        │                             │
#   │  5. RPC → show_result(d1, d2)   │  show_result(d1, d2) called  │
#   │     called on all clients.       │  by RPC — labels update.    │
#   │  6. roll_completed signal emits. │                             │
#   │  7. TurnManager.on_dice_rolled() │                             │
#   │     processes the roll.          │                             │
#   └─────────────────────────────────────────────────────────────────┘
#
#   Only the HOST computes the roll result.  Clients NEVER call roll_dice()
#   directly — they only display whatever the host sends via show_result().
#   This prevents desync and cheating.
#
# DEPENDENCIES:
#   - TurnManager : sibling node; connects to roll_completed signal.
###############################################################################

extends Control

# ---------------------------------------------------------------------------
# EXPORTED REFERENCES
# (Assigned in the Godot Inspector or via @export in the parent scene.)
# ---------------------------------------------------------------------------

## Label that displays the face value of the first die.
## In a polished version this could be replaced with a TextureRect or a 3-D
## sub-viewport, but a Label is sufficient for prototyping.
@export var die1_label: Label

## Label that displays the face value of the second die.
@export var die2_label: Label

## The Button (or TextureButton) the player taps/clicks to initiate a roll.
## Disabled when it is not the local player's turn.
@export var roll_button: Button

# ---------------------------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------------------------

## Emitted once the roll animation completes and the final values are settled.
## TurnManager connects to this signal and calls on_dice_rolled(die1, die2).
##
## @param die1   Final value of die 1 (1–6).
## @param die2   Final value of die 2 (1–6).
## @param total  Sum of die1 + die2 (convenience; avoids recalculation).
signal roll_completed(die1: int, die2: int, total: int)

# ---------------------------------------------------------------------------
# STATE VARIABLES
# ---------------------------------------------------------------------------

## Prevents the roll button from being pressed while an animation is playing.
## Set to true at the start of _animate_roll() and false after it finishes.
var is_rolling: bool = false

## True only when it is THIS local peer's turn to roll.
## Controlled by TurnManager (via set_my_turn()) and guards on_roll_pressed().
## Remote players should never be able to trigger a roll on behalf of others.
var is_my_turn: bool = false

## Stores the final roll result during the animation so we can reference it
## in the completion callback without passing it through a closure.
var _final_die1: int = 1
var _final_die2: int = 1

# ---------------------------------------------------------------------------
# LIFECYCLE
# ---------------------------------------------------------------------------

## Standard Godot entry point.
## Connects the roll button's pressed signal programmatically so that the
## connection survives scene reloads and does not depend on Inspector wiring.
func _ready() -> void:
	if die1_label == null:
		die1_label = find_child("Die1Label", true, false)
	if die2_label == null:
		die2_label = find_child("Die2Label", true, false)
	if roll_button == null:
		roll_button = find_child("RollButton", true, false)

	if roll_button == null:
		push_warning("[DiceRoller] roll_button is null — check scene exports.")
		return

	if not roll_button.pressed.is_connected(on_roll_pressed):
		roll_button.pressed.connect(on_roll_pressed)

	# Start with the button disabled; TurnManager will enable it via
	# set_my_turn(true) when it is the local player's turn.
	roll_button.disabled = true

	print("[DiceRoller] Ready. roll_button connected.")

# ---------------------------------------------------------------------------
# ROLL INITIATION
# ---------------------------------------------------------------------------

## Called when the player taps the roll button.
## Guards:
##   • is_rolling  — animation already in progress, ignore.
##   • is_my_turn  — this is not the local player's turn, ignore.
##
## If guards pass, triggers the roll animation.
func on_roll_pressed() -> void:
	# Guard: already mid-animation (double-tap protection).
	if is_rolling:
		print("[DiceRoller] Roll ignored — animation already in progress.")
		return

	# Guard: not the local player's turn.
	if not is_my_turn:
		print("[DiceRoller] Roll ignored — not this player's turn.")
		return

	print("[DiceRoller] Roll button pressed — delegating to TurnManager.")
	is_rolling = true
	roll_button.disabled = true

	var tm: Node = get_node_or_null("/root/TurnManager")
	if not tm:
		tm = get_tree().root.find_child("TurnManager", true, false)
	if tm and tm.has_method("request_roll"):
		tm.request_roll()
	else:
		_animate_roll()


## play_roll
## Plays the visual flicker animation using the server-determined dice values
func play_roll(die1: int, die2: int) -> void:
	is_rolling = true
	if roll_button:
		roll_button.disabled = true
	_final_die1 = die1
	_final_die2 = die2

	const STEPS: int = 16
	const INTERVAL: float = 0.05

	var tween: Tween = create_tween()
	for i in range(STEPS):
		tween.tween_callback(func() -> void:
			if die1_label:
				die1_label.text = str(randi_range(1, 6))
			if die2_label:
				die2_label.text = str(randi_range(1, 6))
		).set_delay(INTERVAL * (i + 1))

	tween.tween_callback(_on_animation_finished).set_delay(INTERVAL * (STEPS + 1))

# ---------------------------------------------------------------------------
# ANIMATION
# ---------------------------------------------------------------------------

## Animates the dice roll by rapidly cycling random numbers in the Labels
## for approximately 1 second (20 steps × 0.05 s each), then settling on
## the final authoritative result generated by roll_dice().
##
## Design notes:
##   • A Tween is used instead of a Timer loop so that the animation is
##     frame-rate-independent and cancellable if needed.
##   • The authoritative values are generated ONCE at the start and stored
##     in _final_die1 / _final_die2.  The intermediate frames show random
##     "flicker" values — purely cosmetic.
##   • In multiplayer, the HOST generates the authoritative values and RPCs
##     them to clients via show_result() AFTER the animation finishes here.
func _animate_roll() -> void:
	# Lock the button and set the rolling flag.
	is_rolling     = true
	roll_button.disabled = true

	# Generate the authoritative roll NOW (on the host).
	# Clients will never reach this function — they call show_result() instead.
	var result: Array[int] = roll_dice()
	_final_die1 = result[0]
	_final_die2 = result[1]

	print("[DiceRoller] Authoritative roll: %d + %d" % [_final_die1, _final_die2])

	# ---- Tween-based flicker animation ----
	# We create 20 incremental tweens, each separated by 0.05 s, that update
	# the labels with a random value.  The 21st step (the callback) shows the
	# final real values.
	const STEPS:    int   = 20
	const INTERVAL: float = 0.05  # seconds between each flicker frame

	var tween: Tween = create_tween()

	for i in range(STEPS):
		# Each step: call a lambda that sets the labels to random flicker values.
		# The tween delays each call by (i + 1) * INTERVAL seconds from the
		# animation start.
		tween.tween_callback(
			func() -> void:
				if die1_label:
					die1_label.text = str(randi_range(1, 6))
				if die2_label:
					die2_label.text = str(randi_range(1, 6))
		).set_delay(INTERVAL * (i + 1))

	# After all flicker steps, settle on the final values and emit the signal.
	tween.tween_callback(_on_animation_finished).set_delay(INTERVAL * (STEPS + 1))


## Private callback invoked by the Tween after all animation steps complete.
## Displays the final dice values, unlocks state, and emits roll_completed.
func _on_animation_finished() -> void:
	# ---- Show the final, authoritative values ----
	if die1_label:
		die1_label.text = str(_final_die1)
	if die2_label:
		die2_label.text = str(_final_die2)

	# ---- Unlock rolling state ----
	# NOTE: We do NOT re-enable roll_button here.  TurnManager controls that
	# via set_my_turn().  The button only re-enables if the player rolls
	# doubles and gets another turn.
	is_rolling = false

	var total: int = _final_die1 + _final_die2
	print("[DiceRoller] Animation finished. Result: %d + %d = %d" \
		% [_final_die1, _final_die2, total])

	# ---- Notify TurnManager ----
	roll_completed.emit(_final_die1, _final_die2, total)

	# ---- In multiplayer: broadcast the authoritative result to all clients ----
	# The host calls rpc_show_result() so that every client's DiceRoller
	# displays the same numbers.  Clients will NOT re-emit roll_completed;
	# they only update their visual labels.
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc_show_result(_final_die1, _final_die2)

# ---------------------------------------------------------------------------
# PURE DICE UTILITY
# ---------------------------------------------------------------------------

## Generates a fresh pair of random die values and returns them as an Array.
## This is the SINGLE SOURCE OF TRUTH for randomness on the host.
##
## For deterministic/reproducible games (e.g., replays, testing), the caller
## can set a seed with `randomize()` or `seed(n)` before calling this function.
## In a networked game the host sets the seed and communicates it to clients
## before the game starts so replays are possible, but clients still do not
## call roll_dice() themselves.
##
## @return Array[int] with two elements: [die1_value, die2_value], each 1–6.
func roll_dice() -> Array[int]:
	return [randi_range(1, 6), randi_range(1, 6)]

# ---------------------------------------------------------------------------
# TURN AWARENESS
# ---------------------------------------------------------------------------

## Called by TurnManager (via the dice_roll_requested signal or directly)
## to toggle whether the local player can interact with the dice UI.
##
## @param is_turn  true  → enable the button and mark this as the player's turn.
##                 false → disable the button (e.g., it is another player's turn).
func set_my_turn(is_turn: bool) -> void:
	is_my_turn = is_turn

	if roll_button:
		# Only enable the button when it is this player's turn AND we are not
		# currently mid-animation.
		roll_button.disabled = not is_turn or is_rolling

	# Optionally show/hide the entire dice panel for a cleaner UI.
	# visible = is_turn   ← uncomment if you prefer hiding over disabling.

	print("[DiceRoller] set_my_turn(%s)" % is_turn)

# ---------------------------------------------------------------------------
# REMOTE RESULT DISPLAY
# ---------------------------------------------------------------------------

## Displays a roll result sent by the host without triggering any local roll
## logic.  Called on CLIENT peers via rpc_show_result().
##
## This function is intentionally "dumb" — it only updates the visual labels.
## The actual game-state changes (moving the pawn, paying rent, etc.) are
## driven by the host's TurnManager through its own RPCs.
##
## @param die1  The authoritative value of die 1 as computed by the host.
## @param die2  The authoritative value of die 2 as computed by the host.
func show_result(die1: int, die2: int) -> void:
	# Store so that _on_animation_finished (if somehow called) uses these
	# values rather than a locally generated pair.
	_final_die1 = die1
	_final_die2 = die2

	if die1_label:
		die1_label.text = str(die1)
	if die2_label:
		die2_label.text = str(die2)

	print("[DiceRoller] show_result(%d, %d) — displaying host's authoritative roll." \
		% [die1, die2])

	# NOTE: We do NOT emit roll_completed here on the client.
	# Only the HOST's TurnManager should drive game-state changes.
	# If you need the client to react to the visual display (e.g., play a
	# sound), do so here without touching GameState.

# ---------------------------------------------------------------------------
# MULTIPLAYER RPC
# ---------------------------------------------------------------------------

## Host → all clients: synchronises the dice result display.
## "authority"  — only the multiplayer authority (host/server) may call this.
## "call_local" — the RPC also fires on the host itself, so show_result() is
##                called uniformly everywhere.
## "reliable"   — guaranteed delivery; important so every client sees the roll.
##
## IMPORTANT: The host generates the roll, sends it here, and THEN processes
## the game logic.  Do not reverse this order — clients must see the dice
## update before the pawn starts moving.
@rpc("authority", "call_local", "reliable")
func rpc_show_result(die1: int, die2: int) -> void:
	show_result(die1, die2)
