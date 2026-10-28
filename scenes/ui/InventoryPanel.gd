## InventoryPanel.gd
## ============================================================
## Scene: scenes/ui/InventoryPanel.tscn
## Node type: Control  (anchored to bottom-left or bottom-right of the HUD)
##
## PURPOSE:
##   Displays the local player's owned properties as a scrollable grid of
##   PropertyCard widgets, together with their name and current balance.
##
##   Why is this a separate panel rather than part of CasinoModal?
##   - It is always visible during a player's turn, not modal/blocking.
##   - It should update reactively whenever GameState changes (purchases,
##     rent payments, mortgages) without interrupting gameplay.
##
## SCENE TREE EXPECTED:
##   InventoryPanel (Control)            ← this script
##   ├─ PlayerNameLabel (Label)          ← shows whose inventory is displayed
##   ├─ MoneyLabel (Label)               ← live balance (e.g. "$1,500")
##   └─ ScrollContainer (ScrollContainer)
##      └─ GridContainer (GridContainer) ← auto-wraps PropertyCard children
##
## DATA FLOW:
##   GameState.player_state_changed signal
##        │
##        ▼
##   _on_game_state_changed(player_id)
##        │  (only if player_id == displayed_peer_id)
##        ├─ refresh_inventory()   — rebuilds PropertyCard grid
##        └─ update_money_display()
##
## EDITOR SETUP:
##   - Set `property_card_scene` in the Inspector to PropertyCard.tscn.
##   - InventoryPanel is added as a child of UIManager in the Board scene.
## ============================================================
class_name InventoryPanel
extends Control


# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

## PackedScene reference to PropertyCard.tscn.
## Set this in the Inspector — drag PropertyCard.tscn into the slot.
## Why an export? It lets the designer swap the card scene without touching code.
@export var property_card_scene: PackedScene


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

## ScrollContainer wrapping the grid — enables scrolling when the player has
## many properties (late game, e.g. owning a full monopoly group + railroads).
@onready var scroll_container: ScrollContainer = find_child("ScrollContainer", true, false)
@onready var grid_container: GridContainer = find_child("GridContainer", true, false)
@onready var player_name_label: Label = find_child("PlayerNameLabel", true, false)
@onready var money_label: Label = find_child("MoneyLabel", true, false)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## The peer ID of the player whose inventory is currently shown.
## Defaults to 0 (unset). UIManager sets this to multiplayer.get_unique_id()
## for the local player on game start.
var displayed_peer_id: int = 0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Connect to the GameState signal so the panel auto-updates whenever any
	# player's state changes (money, property list, mortgage status).
	# The filter in _on_game_state_changed ensures we only redraw when the
	# DISPLAYED player's data changed, avoiding unnecessary work.
	if GameState.has_signal("player_state_changed"):
		GameState.player_state_changed.connect(_on_game_state_changed)
	else:
		push_warning("InventoryPanel: GameState does not expose 'player_state_changed' signal.")


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## refresh_inventory — Rebuild the PropertyCard grid for the given player.
##
## Clears all existing cards and instantiates fresh ones from GameState data.
## This is a "nuclear rebuild" approach — simpler than diffing and more
## reliable when ownership changes (mortgages, auctions, trades in the future).
##
## Parameters:
##   peer_id — Multiplayer peer ID of the player to display.
##             Typically multiplayer.get_unique_id() for the local player,
##             but could be any connected peer (for spectator mode).
func refresh_inventory(peer_id: int) -> void:
	# Track which player we are showing.
	displayed_peer_id = peer_id

	# --- Clear old cards ---
	# Freeing all children before re-populating avoids stale cards sticking
	# around if the player sold / traded properties.
	for child in grid_container.get_children():
		child.queue_free()

	# --- Validate data sources ---
	if not GameState.has_player(peer_id):
		push_warning("InventoryPanel.refresh_inventory: peer_id %d not in GameState." % peer_id)
		return

	if property_card_scene == null:
		push_error("InventoryPanel: property_card_scene is not assigned in the Inspector!")
		return

	# --- Fetch player data ---
	var player_data := GameState.get_player(peer_id)
	# player_data.owned_properties is an Array[int] of tile indices.
	var owned: Array = player_data.get("owned_properties", [])

	# Update the header label with the player's username.
	player_name_label.text = "%s's Properties" % player_data.get("username", "Player")

	# --- Instantiate one PropertyCard per owned tile ---
	for tile_index: int in owned:
		# Fetch TileData from the board manager (the authoritative tile registry).
		var tile_data: BoardTileData = BoardManager.get_tile(tile_index)
		if tile_data == null:
			push_warning("InventoryPanel: BoardManager returned null for tile_index=%d" % tile_index)
			continue

		# Instantiate the card scene.
		var card: PropertyCard = property_card_scene.instantiate() as PropertyCard
		if card == null:
			push_error("InventoryPanel: property_card_scene did not instantiate as PropertyCard.")
			continue

		# Set the tile index BEFORE adding to the tree, so @onready vars in
		# PropertyCard are already initialised when populate() runs.
		card.tile_index = tile_index

		# Add to the grid first (so _ready fires and @onready vars resolve).
		grid_container.add_child(card)

		# Now populate with tile data.
		card.populate(tile_data)

		# Connect PropertyCard signals to our handlers.
		card.card_selected.connect(_on_card_selected)
		card.mortgage_requested.connect(_on_mortgage_requested)

	# Refresh money display alongside the grid.
	update_money_display(peer_id)


## update_money_display — Refresh the balance label for the given player.
##
## Called independently so money can update without rebuilding the entire grid
## (e.g. after paying rent — properties haven't changed, but balance has).
##
## Parameters:
##   peer_id — Peer ID of the player whose balance to display.
func update_money_display(peer_id: int) -> void:
	if not GameState.has_player(peer_id):
		money_label.text = "$???"
		return

	var player_data := GameState.get_player(peer_id)
	var balance: int = player_data.get("money", 0)

	# Format with comma separators for large amounts (e.g. "$1,500").
	# GDScript doesn't have a built-in thousands formatter, so we do it manually.
	money_label.text = "$%s" % _format_money(balance)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

## _on_card_selected — route a card click to UIManager for a detail popup.
##
## InventoryPanel doesn't know HOW to show a detail modal — that's UIManager's
## job. Delegating keeps responsibilities separated.
##
## Parameters:
##   tile_index — The tile index the player clicked on.
func _on_card_selected(tile_index: int) -> void:
	var ui: Node = get_tree().root.find_child("UIManager", true, false)
	if ui and ui.has_method("show_tile_detail"):
		ui.show_tile_detail(tile_index)


## _on_mortgage_requested — confirm then execute a mortgage/unmortgage action.
##
## The flow:
##   1. UIManager shows a Yes/No confirmation modal.
##   2. If confirmed, BoardManager.mortgage_property() handles the logic
##      and emits the GameState change (which triggers a refresh here).
##
## Parameters:
##   tile_index — Tile to mortgage or unmortgage.
func _on_mortgage_requested(tile_index: int) -> void:
	var tile_data: BoardTileData = BoardManager.get_tile(tile_index)
	if tile_data == null:
		return

	# Build context-appropriate confirmation message.
	var action_label: String
	var mortgage_value: int = tile_data.purchase_price / 2  # Standard Monopoly rule.

	if tile_data.is_mortgaged:
		# Unmortgaging costs 110% of mortgage value (10% interest).
		var unmortgage_cost: int = int(mortgage_value * 1.1)
		action_label = "Unmortgage %s for $%d?" % [tile_data.display_name, unmortgage_cost]
	else:
		action_label = "Mortgage %s for $%d?" % [tile_data.display_name, mortgage_value]

	# Ask UIManager to show a confirmation modal.
	var ui: Node = get_tree().root.find_child("UIManager", true, false)
	if ui and ui.has_method("show_confirm_modal"):
		ui.show_confirm_modal(
			"Mortgage",
			action_label,
			func() -> void:
				BoardManager.mortgage_property(tile_index)
		)


## _on_game_state_changed — reactive refresh triggered by GameState signal.
##
## Called whenever ANY player's state changes in GameState.
## We check if the changed player is the one we're displaying and only then
## redraw — avoiding O(n) redraws on every state change.
##
## Parameters:
##   player_id — The peer ID of the player whose state just changed.
func _on_game_state_changed(player_id: int) -> void:
	# Only refresh if the data belongs to the player currently displayed.
	if player_id == displayed_peer_id:
		refresh_inventory(displayed_peer_id)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## _format_money — add comma thousands separator to an integer.
##
## e.g. 1500 → "1,500", 200 → "200", 1000000 → "1,000,000"
##
## Why not use String formatting? GDScript's `%d` doesn't add commas.
## A custom formatter keeps the display consistent across the entire UI.
func _format_money(amount: int) -> String:
	var s := str(abs(amount))
	var result := ""
	var count  := 0

	# Walk backwards through the digit string, inserting commas every 3 digits.
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1

	if amount < 0:
		result = "-" + result

	return result
