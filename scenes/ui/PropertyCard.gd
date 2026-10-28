## PropertyCard.gd
## ============================================================
## Scene: scenes/ui/PropertyCard.tscn
## Node type: PanelContainer  (one tile in the inventory grid)
##
## PURPOSE:
##   Represents a single owned property in a player's inventory panel.
##   Each PropertyCard is instantiated dynamically by InventoryPanel and
##   populated with data from a TileData resource.
##
##   Visual anatomy of the card:
##     ┌──────────────────────┐
##     │ ███ (color strip)    │  ← color_strip: group colour bar at the top
##     │ Boardwalk            │  ← property_name_label
##     │ Price: $400          │  ← price_label
##     │ Rent:  $50           │  ← rent_label
##     │ Houses: 0            │  ← house_count_label
##     │ [Mortgage]           │  ← mortgage_button
##     └──────────────────────┘
##
## SCENE TREE EXPECTED:
##   PropertyCard (PanelContainer)  ← this script
##   ├─ ColorStrip (ColorRect)      ← top colour band (group identifier)
##   └─ VBox (VBoxContainer)
##      ├─ NameLabel  (Label)
##      ├─ PriceLabel (Label)
##      ├─ RentLabel  (Label)
##      ├─ HouseLabel (Label)
##      └─ MortgageButton (Button)
##
## SIGNALS:
##   card_selected(tile_index)       — emitted when the card body is clicked.
##   mortgage_requested(tile_index)  — emitted when the Mortgage button is clicked.
##
## Both signals bubble up to InventoryPanel which decides what to do
## (show detail popup, confirm mortgage, etc.).
## ============================================================
class_name PropertyCard
extends PanelContainer


# ---------------------------------------------------------------------------
# Exports — set in editor or from code before populate() is called.
# ---------------------------------------------------------------------------

## The board tile index this card represents.
## -1 means "not yet assigned". InventoryPanel sets this after instantiation.
@export var tile_index: int = -1


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

## The top colour stripe that visually encodes the property group.
## Same colours as the physical Monopoly board (brown, light-blue, etc.).
@onready var color_strip: ColorRect = $ColorStrip

## Property name text (e.g. "Park Place", "Reading Railroad").
@onready var property_name_label: Label = $VBox/NameLabel

## Purchase price shown on the card (e.g. "Price: $350").
@onready var price_label: Label = $VBox/PriceLabel

## Base rent shown on the card. Note: actual rent varies with houses/hotels
## and monopoly ownership, but this shows the base for reference.
@onready var rent_label: Label = $VBox/RentLabel

## How many houses (or 🏨 for hotel) are on this property.
## Updated whenever the player adds/removes improvements.
@onready var house_count_label: Label = $VBox/HouseLabel
@onready var upgrade_button: Button = $VBox/UpgradeButton
@onready var mortgage_button: Button = $VBox/MortgageButton


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the player clicks the card body (not the mortgage button).
## InventoryPanel responds by opening a detail popup via UIManager.
signal card_selected(tile_index: int)

## Emitted when the player clicks the Mortgage button.
signal mortgage_requested(tile_index: int)

## Emitted when the player clicks the Upgrade button.
signal upgrade_requested(tile_index: int)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if mortgage_button and not mortgage_button.pressed.is_connected(_on_mortgage_pressed):
		mortgage_button.pressed.connect(_on_mortgage_pressed)
	if upgrade_button and not upgrade_button.pressed.is_connected(_on_upgrade_pressed):
		upgrade_button.pressed.connect(_on_upgrade_pressed)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func populate(tile_data: BoardTileData) -> void:
	if tile_data == null:
		push_error("PropertyCard.populate() received null TileData for tile_index=%d" % tile_index)
		property_name_label.text = "ERROR"
		return

	property_name_label.text = tile_data.tile_name
	price_label.text = "Price: $%d" % tile_data.purchase_price
	rent_label.text = "Rent: $%d" % tile_data.base_rent

	if tile_data.house_count == 5:
		house_count_label.text = "🏨 Hotel"
	elif tile_data.house_count > 0:
		house_count_label.text = "Houses: %d" % tile_data.house_count
	else:
		house_count_label.text = "Houses: none"

	# Mortgage button
	if tile_data.is_mortgaged:
		mortgage_button.text = "Unmortgage"
		modulate = Color(0.7, 0.7, 0.7, 1.0)
	else:
		mortgage_button.text = "Mortgage"
		modulate = Color.WHITE

	# Upgrade button logic
	if tile_data.tile_type == "property":
		upgrade_button.show()
		var local_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		if tile_data.house_count >= 5:
			upgrade_button.text = "Max Level"
			upgrade_button.disabled = true
		elif BoardManager.can_build_house(local_id, tile_index):
			if tile_data.house_count == 4:
				upgrade_button.text = "+ Hotel ($%d)" % tile_data.house_cost
			else:
				upgrade_button.text = "+ House ($%d)" % tile_data.house_cost
			upgrade_button.disabled = false
		else:
			upgrade_button.text = "+ House ($%d)" % tile_data.house_cost
			upgrade_button.disabled = true
	else:
		upgrade_button.hide()

	color_strip.color = get_group_color(tile_data.color_group)


func _on_upgrade_pressed() -> void:
	emit_signal("upgrade_requested", tile_index)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

## _on_mortgage_pressed — relay the mortgage request upward.
##
## We do NOT perform the mortgage here. PropertyCard is a "dumb" display
## widget. Decisions (confirm dialog, RPC call) are made by InventoryPanel.
func _on_mortgage_pressed() -> void:
	emit_signal("mortgage_requested", tile_index)


## _gui_input — detect a click on the card body to emit card_selected.
##
## Using _gui_input rather than a Button wrapper because PanelContainer
## is not a Button. We respond only to left-click presses to avoid reacting
## to scrolls or releases.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			emit_signal("card_selected", tile_index)
			# Accept the event so parent containers don't also handle it.
			accept_event()


# ---------------------------------------------------------------------------
# Colour mapping
# ---------------------------------------------------------------------------

## get_group_color — map a group name string to its standard Monopoly colour.
##
## Why store colours here rather than in TileData?
##   TileData is a data resource (ideally serializable as JSON/cfg).
##   Colour is a presentation concern — it belongs in the UI layer.
##   This function is the single place to adjust colours without touching data.
##
## Parameters:
##   group_name — The string key used in TileData.color_group
##                (e.g. "brown", "light_blue", "railroad").
##
## Returns:
##   A Color matching the standard Monopoly board palette, or Color.WHITE
##   for unknown groups (safe fallback).
func get_group_color(group_name: String) -> Color:
	match group_name:
		"brown":
			# Mediterranean / Baltic Avenue — dark earthy brown.
			return Color(0.58, 0.33, 0.21)

		"light_blue":
			# Oriental / Vermont / Connecticut — pale sky blue.
			return Color(0.67, 0.88, 0.98)

		"pink":
			# St. Charles / States / Virginia — hot magenta-pink.
			return Color(0.85, 0.23, 0.59)

		"orange":
			# St. James / Tennessee / New York — vivid orange.
			return Color(0.97, 0.58, 0.11)

		"red":
			# Kentucky / Indiana / Illinois — bold red.
			return Color(0.93, 0.11, 0.14)

		"yellow":
			# Atlantic / Ventnor / Marvin Gardens — bright yellow.
			return Color(0.99, 0.95, 0.0)

		"green":
			# Pacific / N. Carolina / Pennsylvania — forest green.
			return Color(0.12, 0.70, 0.35)

		"dark_blue":
			# Park Place / Boardwalk — deep navy blue.
			return Color(0.13, 0.20, 0.58)

		"railroad":
			# All four railroads — neutral dark grey (train aesthetic).
			return Color(0.2, 0.2, 0.2)

		"utility":
			# Electric Company / Water Works — light grey.
			return Color(0.8, 0.8, 0.8)

		_:
			# Unknown group — white is a safe, obvious "something is wrong" fallback.
			push_warning("PropertyCard.get_group_color: unknown group '%s'" % group_name)
			return Color.WHITE
