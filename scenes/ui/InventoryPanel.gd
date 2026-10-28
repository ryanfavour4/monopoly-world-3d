## InventoryPanel.gd
## ============================================================
## Dockable, Collapsible Property Management Drawer (Tycoon HUD)
##
## Features:
##   • Expandable / collapsible bottom drawer with smooth animation
##   • Live stats summary (Cash, Net Worth, Property Count)
##   • Horizontal scrolling shelf of owned PropertyCards
##   • Direct property upgrading (+ House / Hotel) & mortgaging
##   • Informative empty state for players who don't yet own land
## ============================================================

class_name InventoryPanel
extends Control

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var property_card_scene: PackedScene

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var toggle_button: Button = find_child("ToggleDockButton", true, false)
@onready var drawer_body: Control = find_child("DrawerBody", true, false)
@onready var cards_container: HBoxContainer = find_child("CardsContainer", true, false)
@onready var empty_label: Label = find_child("EmptyLabel", true, false)
@onready var player_name_label: Label = find_child("PlayerNameLabel", true, false)
@onready var money_label: Label = find_child("MoneyLabel", true, false)
@onready var net_worth_label: Label = find_child("NetWorthLabel", true, false)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var displayed_peer_id: int = 0
var is_expanded: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if toggle_button and not toggle_button.pressed.is_connected(_on_toggle_dock_pressed):
		toggle_button.pressed.connect(_on_toggle_dock_pressed)

	if GameState.has_signal("player_state_changed"):
		GameState.player_state_changed.connect(_on_game_state_changed)

	_update_drawer_visibility()


# ---------------------------------------------------------------------------
# Dock Expand / Collapse
# ---------------------------------------------------------------------------

func _on_toggle_dock_pressed() -> void:
	is_expanded = not is_expanded
	_update_drawer_visibility()


func _update_drawer_visibility() -> void:
	if drawer_body:
		drawer_body.visible = is_expanded

	if toggle_button:
		var p_data := GameState.get_player(displayed_peer_id) if GameState.has_player(displayed_peer_id) else {}
		var owned: Array = p_data.get("properties", p_data.get("owned_properties", []))
		if is_expanded:
			toggle_button.text = "▼ HIDE PROPERTY PORTFOLIO (%d)" % owned.size()
		else:
			toggle_button.text = "▲ MY PROPERTY PORTFOLIO (%d) — Click to View Rents & Upgrades" % owned.size()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func refresh_inventory(peer_id: int) -> void:
	displayed_peer_id = peer_id

	if not cards_container:
		return

	# Clear previous cards
	for child in cards_container.get_children():
		child.queue_free()

	if not GameState.has_player(peer_id):
		return

	if property_card_scene == null:
		push_error("InventoryPanel: property_card_scene is not assigned!")
		return

	var player_data := GameState.get_player(peer_id)
	var owned: Array = player_data.get("properties", player_data.get("owned_properties", []))

	# Authoritative fallback
	if owned.is_empty():
		var tiles_owned: Array[BoardTileData] = BoardManager.get_tiles_by_owner(peer_id)
		for t in tiles_owned:
			if not owned.has(t.tile_index):
				owned.append(t.tile_index)

	# Update header info
	var uname: String = player_data.get("username", "Player")
	if player_name_label:
		player_name_label.text = "👑 %s's Portfolio (%d)" % [uname, owned.size()]

	# Empty state handling
	if empty_label:
		empty_label.visible = owned.is_empty()

	# Instantiate property cards
	for tile_index: int in owned:
		var tile_data: BoardTileData = BoardManager.get_tile(tile_index)
		if tile_data == null:
			continue

		var card: PropertyCard = property_card_scene.instantiate() as PropertyCard
		if card == null:
			continue

		card.tile_index = tile_index
		cards_container.add_child(card)
		card.populate(tile_data)

		card.card_selected.connect(_on_card_selected)
		card.mortgage_requested.connect(_on_mortgage_requested)
		if card.has_signal("upgrade_requested"):
			card.upgrade_requested.connect(_on_upgrade_requested)

	update_money_display(peer_id)
	_update_drawer_visibility()


func update_money_display(peer_id: int) -> void:
	if not GameState.has_player(peer_id):
		return

	var player_data := GameState.get_player(peer_id)
	var balance: int = player_data.get("money", 0)
	var net_worth: int = GameState.get_player_net_worth(peer_id)

	if money_label:
		money_label.text = "💵 Cash: $%s" % _format_money(balance)
	if net_worth_label:
		net_worth_label.text = "💎 Net Worth: $%s" % _format_money(net_worth)


# ---------------------------------------------------------------------------
# Card Action Handlers
# ---------------------------------------------------------------------------

func _on_upgrade_requested(tile_index: int) -> void:
	TurnManager.upgrade_property(displayed_peer_id, tile_index)


func _on_card_selected(tile_index: int) -> void:
	var ui: Node = get_tree().root.find_child("UIManager", true, false)
	if ui and ui.has_method("show_tile_detail"):
		ui.show_tile_detail(tile_index)


func _on_mortgage_requested(tile_index: int) -> void:
	var tile_data: BoardTileData = BoardManager.get_tile(tile_index)
	if tile_data == null:
		return

	var mortgage_value: int = tile_data.purchase_price / 2
	var action_label: String
	if tile_data.is_mortgaged:
		var unmortgage_cost: int = int(mortgage_value * 1.1)
		action_label = "Unmortgage %s for $%d?" % [tile_data.display_name, unmortgage_cost]
	else:
		action_label = "Mortgage %s for $%d?" % [tile_data.display_name, mortgage_value]

	var ui: Node = get_tree().root.find_child("UIManager", true, false)
	if ui and ui.has_method("show_confirm_modal"):
		ui.show_confirm_modal(
			"Mortgage",
			action_label,
			func() -> void:
				BoardManager.mortgage_property(tile_index)
				refresh_inventory(displayed_peer_id)
		)


func _on_game_state_changed(player_id: int) -> void:
	if player_id == displayed_peer_id:
		refresh_inventory(displayed_peer_id)


func _format_money(amount: int) -> String:
	var s := str(abs(amount))
	var result := ""
	var count  := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	if amount < 0:
		result = "-" + result
	return result
