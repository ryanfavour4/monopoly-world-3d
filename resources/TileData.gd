## TileData.gd
## A Resource representing a single board tile on the Monopoly board.
## Resources in Godot are data containers that can be saved to disk (.tres/.res)
## and loaded/shared at runtime. By extending Resource we get:
##   - @export support for the Godot Inspector
##   - Serialization / deserialization for free
##   - Easy duplication via .duplicate() so each game instance has its own copy
##
## Every tile on the board (all 40 of them) gets one TileData instance,
## populated by BoardManager._build_board(). TileData is PURE DATA — no logic.
## All game-rule logic lives in BoardManager.gd.
##
## Usage:
##   var td: TileData = TileData.new()
##   td.tile_name = "Boardwalk"
##   td.purchase_price = 400

class_name BoardTileData
extends Resource

# ---------------------------------------------------------------------------
# IDENTITY
# ---------------------------------------------------------------------------

## Unique index 0–39 around the board (clockwise starting at GO).
## Used as the primary key to look up this tile in BoardManager.tiles[].
@export var tile_index: int = 0

## Human-readable display name shown in the UI (e.g. "Boardwalk", "GO", "Chance").
@export var tile_name: String = ""

## Tile category — drives which branch of handle_landing() fires.
## Valid values:
##   "property"        — purchasable colour-group street
##   "railroad"        — purchasable railroad (4 on board)
##   "utility"         — Electric Company or Water Works
##   "chance"          — draw a Chance card
##   "community_chest" — draw a Community Chest card
##   "tax"             — mandatory payment (Income Tax or Luxury Tax)
##   "go"              — collect $200 salary when passing / landing
##   "jail"            — Just Visiting (no effect on landing; jail logic is separate)
##   "free_parking"    — house rule hook; base game: nothing happens
##   "go_to_jail"      — immediately send player to jail
@export var tile_type: String = "property"

# ---------------------------------------------------------------------------
# COLOUR GROUP (properties only)
# ---------------------------------------------------------------------------

## The colour group this property belongs to (e.g. "brown", "light_blue",
## "pink", "orange", "red", "yellow", "green", "dark_blue").
## Empty string for non-property tiles. BoardManager uses this to check
## whether an owner holds a monopoly (all tiles in the group).
@export var color_group: String = ""

# ---------------------------------------------------------------------------
# FINANCIAL DATA
# ---------------------------------------------------------------------------

## Cost to purchase this tile from the bank on first landing.
## 0 for non-purchasable tiles (GO, tax, jail, etc.).
@export var purchase_price: int = 0

## Rent charged to a player who lands on this property when it is:
##   - unimproved (0 houses) and NOT part of a complete colour-group monopoly.
## For railroads and utilities this field is not used directly — see
## BoardManager.calculate_rent() for their special rent formulae.
@export var base_rent: int = 0

## Progressive rents indexed by improvement level.
## Index layout: [1_house, 2_houses, 3_houses, 4_houses, hotel]
## So house_rents[0] = rent with 1 house, house_rents[4] = rent with hotel.
## Empty array for non-property tiles.
## Source: official Monopoly deed cards.
@export var house_rents: Array[int] = []

## Cost to build ONE house on this property (same for all houses / hotel).
## $50 for brown & light_blue, $100 for pink & orange,
## $150 for red & yellow, $200 for green & dark_blue.
## 0 for non-improvable tiles.
@export var house_cost: int = 0

## Amount received from the bank when this property is mortgaged
## (typically half the purchase_price, rounded to nearest $5).
## 0 for non-purchasable tiles.
@export var mortgage_value: int = 0

# ---------------------------------------------------------------------------
# RUNTIME STATE (changes during gameplay)
# ---------------------------------------------------------------------------

## Whether this property is currently mortgaged.
## A mortgaged property cannot collect rent until un-mortgaged by paying
## mortgage_value + 10% interest back to the bank.
@export var is_mortgaged: bool = false

## The peer_id of the player who owns this tile.
##   0  = unowned (available for purchase)
##  -1  = bank / non-purchasable tile (default)
## >0   = a connected player's ENet peer ID
@export var owner_id: int = -1

## Number of houses currently built on this property.
## Valid range: 0 (unimproved) → 4 (four houses) → 5 (hotel).
## 5 represents a hotel in Monopoly rules.
## Only meaningful for "property" tiles with house_cost > 0.
@export var house_count: int = 0
