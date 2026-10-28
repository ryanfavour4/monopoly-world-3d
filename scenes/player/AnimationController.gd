# =============================================================================
# AnimationController.gd
# =============================================================================
# Attached to a Node that is a child of the PlayerPawn scene.
# This script provides a unified animation state interface so that ANY character
# model (human, horse, car, iron, etc.) can be driven with the same function
# names. As long as every character's AnimationPlayer contains clips named
# exactly "Idle", "Walk", "Dance", "Sad", and "Celebrate", this controller
# works without modification for any pawn model.
#
# Hierarchy expectation (inside PlayerPawn.tscn):
#   PlayerPawn (CharacterBody3D)
#   └── AnimationController (Node)          ← this script
#       ├── AnimationPlayer                 ← required; holds named clips
#       └── AnimationTree                   ← optional; used only when
#                                             cross-fade blending is needed
# =============================================================================

class_name AnimationController
extends Node

# ---------------------------------------------------------------------------
# Animation state name constants
# ---------------------------------------------------------------------------
# All character model AnimationPlayers MUST contain clips with these exact
# names. This is the contract between the art pipeline and this controller.
# If a clip is missing the engine will print a warning and the pawn will stay
# in whatever state it was last in.
const STATE_IDLE      = "Idle"
const STATE_WALK      = "Walk"
const STATE_DANCE     = "Dance"
const STATE_SAD       = "Sad"
const STATE_CELEBRATE = "Celebrate"

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

# Primary playback node. Every character model must expose an AnimationPlayer
# as a direct child of this AnimationController node.
@onready var anim_player: AnimationPlayer = $AnimationPlayer

# Optional AnimationTree — when the character model uses blend spaces or state
# machines for smooth transitions (e.g., walk ↔ idle blending) this reference
# is used instead of calling anim_player.play() directly. Left as null by
# default; the parent scene assigns it only when blending is required.
@onready var anim_tree: AnimationTree = null   # assign in _ready() if present

# ---------------------------------------------------------------------------
# State tracking
# ---------------------------------------------------------------------------

# Tracks the currently active animation state name.
# Used by set_state() to avoid calling play() on a clip that is already running
# (which would restart it from the beginning, causing a visible stutter).
var current_state: String = "Idle"

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Connect the animation_finished signal so we can auto-return from
	# transient states (Dance, Sad, Celebrate) back to Idle.
	# Using a Callable avoids string-based signal connections (Godot 4 style).
	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)

	# Start in Idle so the character isn't frozen in a T-pose while waiting
	# for the game to assign movement.
	play_idle()


# ---------------------------------------------------------------------------
# Core state machine
# ---------------------------------------------------------------------------

## set_state
## ---------
## Input : state_name — one of the STATE_* constants defined above.
## Output: none (side-effect: drives AnimationPlayer to the requested clip).
##
## Transitions the character to the requested animation state. The guard
## (current_state == state_name) prevents restarting a clip that is already
## playing, which would cause the animation to snap back to frame 0 mid-play.
func set_state(state_name: String) -> void:
	# Guard: do nothing if we're already in this state.
	if current_state == state_name:
		return

	# Update our internal tracker BEFORE calling play() so that any signal
	# handlers fired synchronously during play() see the correct state.
	current_state = state_name

	# All character models must have identically named animation clips for this
	# to work. If the clip does not exist on the AnimationPlayer an engine
	# warning will appear in the Output panel, but the game will not crash.
	if anim_player and anim_player.has_animation(state_name):
		anim_player.play(state_name)
	else:
		push_warning(
			"AnimationController: AnimationPlayer has no clip named '%s'. "
			% state_name +
			"Ensure the character model's AnimationPlayer contains this clip."
		)


# ---------------------------------------------------------------------------
# Convenience wrappers
# ---------------------------------------------------------------------------
# These thin wrappers exist so calling code never needs to type raw string
# literals, eliminating typo-related bugs and making refactoring easier.

## play_idle
## ---------
## Transitions to the looping Idle animation (breathing, subtle sway, etc.).
## Called at startup and after any transient state finishes.
func play_idle() -> void:
	set_state(STATE_IDLE)


## play_walk
## ---------
## Transitions to the looping Walk animation.
## Called by PlayerPawn while the pawn is stepping across board tiles.
func play_walk() -> void:
	set_state(STATE_WALK)


## play_dance
## ----------
## Plays the one-shot Dance animation, then auto-returns to Idle.
## Used when the player lands on a tile where a property is available to buy,
## or when they collect Go salary.
## Auto-return is handled by on_animation_finished() via the signal connection.
func play_dance() -> void:
	set_state(STATE_DANCE)


## play_sad
## --------
## Plays the one-shot Sad animation (drooping shoulders, head shake, etc.),
## then auto-returns to Idle after the clip finishes.
## Used when the player must pay rent or a tax.
func play_sad() -> void:
	set_state(STATE_SAD)


## play_celebrate
## --------------
## Plays the one-shot Celebrate animation (arms raised, jump, etc.),
## then auto-returns to Idle after the clip finishes.
## Used for special win/collect events.
func play_celebrate() -> void:
	set_state(STATE_CELEBRATE)


# ---------------------------------------------------------------------------
# Signal handler
# ---------------------------------------------------------------------------

## _on_animation_finished
## ----------------------
## Input : anim_name — the name of the clip that just finished playing.
##                     Provided automatically by the animation_finished signal.
## Output: none (side-effect: may call play_idle() to restore default stance).
##
## Connected to anim_player.animation_finished in _ready().
## Handles auto-return logic for transient (non-looping) states:
##   Dance, Sad, Celebrate → return to Idle when the clip ends.
## Looping states (Idle, Walk) never fire animation_finished because they loop,
## so they are intentionally excluded from this handler.
func _on_animation_finished(anim_name: String) -> void:
	match anim_name:
		STATE_DANCE, STATE_SAD, STATE_CELEBRATE:
			# Transient animation is done — restore the default stance so the
			# pawn doesn't freeze on the last frame of the finished clip.
			play_idle()
		# Idle and Walk are looping — they never trigger this signal.
		# Any unknown clip name is silently ignored.
