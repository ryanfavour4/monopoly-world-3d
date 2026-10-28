## BoardTile.gd
## Attached to each of the 40 visual tile Node3Ds in the Board scene.
##
## PURPOSE — PURELY VISUAL
## ========================
## This script is responsible ONLY for visual feedback on the 3D tile mesh:
##   - Flashing the tile with a colour when a pawn lands on it.
##   - Resetting the tile's appearance after the flash finishes.
##
## It holds NO game logic, NO state about ownership or rent, and makes NO
## decisions. All game rules live in BoardManager.gd. BoardTile.gd simply
## receives instructions ("highlight with this colour") and executes them
## via Godot's Tween system.
##
## Scene tree expectation:
##   BoardTile (Node3D, this script)
##   └── MeshInstance3D  ← must be a direct child named "MeshInstance3D"
##                          (or override the name in _ready())
##
## How to set up in the editor:
##   1. Add this script to each tile Node3D.
##   2. Set tile_index in the Inspector (0–39, matching BoardManager.tiles[]).
##   3. Optionally assign highlight_material in the Inspector; if left null
##      the script will duplicate the mesh's existing surface material so
##      the highlight doesn't affect other tiles that share the same material.

extends Node3D

# ---------------------------------------------------------------------------
# EXPORTS — configurable per-tile in the Godot Inspector
# ---------------------------------------------------------------------------

## The board index (0–39) of this tile.
## Must match the corresponding TileData.tile_index in BoardManager.
## BoardManager.get_tile_world_position(tile_index) uses this to find
## where to place pawns.
@export var tile_index: int = 0

## Optional pre-assigned highlight material.
## If provided, this StandardMaterial3D is used directly for emission pulses.
## If null, _ready() duplicates the MeshInstance3D's surface 0 material so
## that the highlight is local to this tile only (prevents all tiles sharing
## one material from flashing simultaneously).
@export var highlight_material: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# PRIVATE REFERENCES
# ---------------------------------------------------------------------------

## Reference to the child MeshInstance3D node whose material we animate.
## Populated in _ready(). Kept as a member so highlight() / reset_highlight()
## don't need to re-fetch it on every call.
var mesh_instance: MeshInstance3D

## The active Tween for the current flash animation.
## Stored so we can kill an in-progress flash before starting a new one,
## preventing material state from getting stuck mid-animation.
var _active_tween: Tween = null

# ---------------------------------------------------------------------------
# LIFECYCLE
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Locate the MeshInstance3D child. Adjust the node name if your scene
	# tree uses a different name (e.g. "TileMesh").
	mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D

	if mesh_instance == null:
		push_error("BoardTile [%s]: No MeshInstance3D child found. " \
			% name + "Highlight effects will not work.")
		return

	# If no highlight_material was assigned in the Inspector, duplicate the
	# mesh's existing material. Duplication is CRITICAL here — without it,
	# modifying the material's emission would affect every tile that shares
	# the same material resource, causing all tiles to flash at once.
	if highlight_material == null:
		var existing: Material = mesh_instance.get_surface_override_material(0)
		if existing == null:
			# Fall back to the mesh's own material if no surface override exists.
			existing = mesh_instance.mesh.surface_get_material(0) if mesh_instance.mesh else null

		if existing is StandardMaterial3D:
			# .duplicate() creates a unique copy local to this tile instance.
			highlight_material = existing.duplicate() as StandardMaterial3D
		else:
			# Create a blank StandardMaterial3D as a last resort.
			highlight_material = StandardMaterial3D.new()
			push_warning("BoardTile [%s]: Created fallback highlight material." % name)

	# Apply the (possibly duplicated) material as a surface override so only
	# this tile's mesh is affected by future emission changes.
	mesh_instance.set_surface_override_material(0, highlight_material)

	# Ensure emission starts disabled so tiles look normal at game start.
	highlight_material.emission_enabled = false

# ---------------------------------------------------------------------------
# PUBLIC API — called by GameManager or PawnController after a pawn lands
# ---------------------------------------------------------------------------

## highlight(color) → void
## Briefly flashes this tile by animating the material's emission colour.
##
## Animation sequence:
##   0.0 s — enable emission, set emission colour to `color`
##   0.3 s — fade emission energy from 1.0 → 0.0 (smooth pulse)
##   0.3 s — disable emission flag (clean state for next highlight)
##
## Any in-progress highlight is cancelled before the new one begins, so
## rapid consecutive calls (e.g. player bounces between tiles) never stack.
##
## Input:
##   color — the Color to flash (e.g. player's pawn_color, or red for rent)
## Output: none (animation runs asynchronously via Tween)
func highlight(color: Color) -> void:
	# Guard: no material means nothing to animate.
	if highlight_material == null:
		return

	# Kill any running tween to avoid overlapping emission states.
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()

	# Configure emission on the material before starting the tween.
	highlight_material.emission_enabled = true
	highlight_material.emission         = color
	highlight_material.emission_energy  = 1.0

	# Create a new Tween bound to this node so it auto-cleans up if the
	# node is freed. TRANS_SINE gives a pleasant pulse feel.
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_SINE)
	_active_tween.set_ease(Tween.EASE_OUT)

	# Animate emission_energy from 1.0 → 0.0 over 0.3 seconds.
	_active_tween.tween_property(
		highlight_material,
		"emission_energy",
		0.0,   # target value
		0.3    # duration in seconds
	)

	# After the fade, disable emission entirely so the material is clean.
	# Using a callable avoids leaving emission_enabled = true with 0 energy.
	_active_tween.tween_callback(reset_highlight)

## reset_highlight() → void
## Immediately disables the emission on this tile's material.
## Called automatically at the end of highlight()'s tween, but can also be
## called externally if you need to force-clear a highlight
## (e.g. end-of-turn cleanup sweep over all tiles).
##
## Input:  none
## Output: none
func reset_highlight() -> void:
	if highlight_material == null:
		return

	highlight_material.emission_enabled = false
	highlight_material.emission_energy  = 0.0
