## BoardManager.gd
## Node that lives inside the Board scene (not an autoload).
##
## Responsibilities:
##   - Owns the canonical Array[TileData] for all 40 board tiles.
##   - Owns the 3D world positions for each tile so pawns know where to move.
##   - Implements every property/tile rule: landing dispatch, rent calculation,
##     purchasing, mortgaging.
##   - Emits signals so UI and GameManager can react without tight coupling.
##
## NOT responsible for:
##   - Turn management or dice rolling (GameManager handles those).
##   - Pawn animation (Pawn3D handles that).
##   - Card drawing (CardManager handles that).
##   - Network replication (MultiplayerSynchronizer / GameManager handle that).
##
## Node path assumed by other scenes: /root/Game/Board/BoardManager
## (adjust to match your scene tree if different)

extends Node

# ---------------------------------------------------------------------------
# SIGNALS
# Signals decouple BoardManager from the systems that react to events.
# GameManager connects to these in its _ready().
# ---------------------------------------------------------------------------

## Emitted after a player's pawn has finished moving to tile_index.
## GameManager listens to trigger handle_landing() and update the UI.
## Parameters:
##   player_id  — the peer_id of the moving player
##   tile_index — destination tile index 0–39
signal player_landed(player_id: int, tile_index: int)

## Emitted when a purchase transaction completes successfully.
## UI listens to update property deed cards and ownership display.
## Parameters:
##   player_id  — buyer's peer_id
##   tile_index — purchased tile index
signal property_purchased(player_id: int, tile_index: int)

## Emitted after rent has been deducted from payer and added to owner.
## UI listens to show a "You paid $X rent" notification.
## Parameters:
##   from_id — the peer_id of the player paying rent
##   to_id   — the peer_id of the owner receiving rent
##   amount  — dollar amount transferred
signal rent_collected(from_id: int, to_id: int, amount: int)

# ---------------------------------------------------------------------------
# DATA
# ---------------------------------------------------------------------------

## The 40 BoardTileData objects in board order (index 0 = GO, index 39 = Boardwalk).
## Populated once in _ready() by _build_board(); mutated during gameplay by
## set_tile_owner(), mortgage_property(), and house-building logic.
var tiles: Array[BoardTileData] = []

## 3D world positions for each of the 40 tiles.
## Index matches tiles[]. Populated once in _ready() by _build_tile_positions().
## Used by Pawn3D.move_to_tile() and camera framing.
var tile_world_positions: Array[Vector3] = []

# ---------------------------------------------------------------------------
# LIFECYCLE
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Build the data arrays once when the board scene loads.
	# Order matters: _build_board() first so tiles[] has 40 entries before
	# any other system queries them.
	_build_board()
	_build_tile_positions()

# ---------------------------------------------------------------------------
# BOARD CONSTRUCTION
# ---------------------------------------------------------------------------

## _build_board() — populates tiles[] with all 40 standard Monopoly tiles.
##
## Data sourced from the official Hasbro Monopoly deed cards (US edition).
## house_rents layout: [1_house, 2_houses, 3_houses, 4_houses, hotel]
## house_cost is per-house; same cost applies to building a hotel.
## mortgage_value = purchase_price / 2 (rounded to nearest $5 per rules).
##
## Output: tiles[] contains exactly 40 TileData objects on return.
func _build_board() -> void:
	tiles.clear()

	# -----------------------------------------------------------------------
	# Helper lambda — creates and appends one TileData to tiles[].
	# Using a callable avoids 40 repetitive TileData.new() + property-set blocks.
	# Parameters mirror TileData fields; omitted params keep their defaults.
	# -----------------------------------------------------------------------
	var add = func(
		idx: int, name: String, type: String,
		group: String = "",
		price: int = 0, rent: int = 0,
		h_rents: Array[int] = [],
		h_cost: int = 0, mort: int = 0
	) -> void:
		var td := BoardTileData.new()
		td.tile_index     = idx
		td.tile_name      = name
		td.tile_type      = type
		td.color_group    = group
		td.purchase_price = price
		td.base_rent      = rent
		td.house_rents    = h_rents
		td.house_cost     = h_cost
		td.mortgage_value = mort
		# Non-purchasable tiles start at owner_id -1 (bank); purchasable start at 0.
		td.owner_id       = 0 if price > 0 else -1
		tiles.append(td)

	# -----------------------------------------------------------------------
	# TILE 0 — GO
	# Players collect $200 salary when they pass or land on GO.
	# Handled in handle_landing() action "collect_go".
	# -----------------------------------------------------------------------
	add.call(0, "GO", "go")

	# -----------------------------------------------------------------------
	# BROWN GROUP — cheapest properties; $50 house cost
	# Monopoly grants double base rent when owner holds full group.
	# -----------------------------------------------------------------------
	# Tile 1 — Mediterranean Avenue
	add.call(1, "Mediterranean Avenue", "property", "brown",
		60, 2, [10, 30, 90, 160, 250] as Array[int], 50, 30)

	# Tile 2 — Community Chest (first of three)
	add.call(2, "Community Chest", "community_chest")

	# Tile 3 — Baltic Avenue
	add.call(3, "Baltic Avenue", "property", "brown",
		60, 4, [20, 60, 180, 320, 450] as Array[int], 50, 30)

	# -----------------------------------------------------------------------
	# TILE 4 — Income Tax
	# Player pays $200 (classic rules; some editions allow 10% of net worth).
	# purchase_price field reused to store the tax amount for simplicity.
	# -----------------------------------------------------------------------
	add.call(4, "Income Tax", "tax", "", 200)

	# -----------------------------------------------------------------------
	# RAILROADS — $200 each; rent = $25 × count owned by same player
	# calculate_rent() implements the multiplier logic.
	# -----------------------------------------------------------------------
	add.call(5, "Reading Railroad", "railroad", "railroad",
		200, 25, [] as Array[int], 0, 100)

	# -----------------------------------------------------------------------
	# LIGHT BLUE GROUP — $50 house cost
	# -----------------------------------------------------------------------
	add.call(6, "Oriental Avenue", "property", "light_blue",
		100, 6, [30, 90, 270, 400, 550] as Array[int], 50, 50)

	# Tile 7 — Chance (first of three)
	add.call(7, "Chance", "chance")

	add.call(8, "Vermont Avenue", "property", "light_blue",
		100, 6, [30, 90, 270, 400, 550] as Array[int], 50, 50)

	add.call(9, "Connecticut Avenue", "property", "light_blue",
		120, 8, [40, 100, 300, 450, 600] as Array[int], 50, 60)

	# -----------------------------------------------------------------------
	# TILE 10 — Jail / Just Visiting
	# Landing here normally (not sent to jail) has no effect.
	# Players sent to jail land on this same tile but in_jail = true.
	# -----------------------------------------------------------------------
	add.call(10, "Jail / Just Visiting", "jail")

	# -----------------------------------------------------------------------
	# PINK (MAGENTA) GROUP — $100 house cost
	# -----------------------------------------------------------------------
	add.call(11, "St. Charles Place", "property", "pink",
		140, 10, [50, 150, 450, 625, 750] as Array[int], 100, 70)

	# -----------------------------------------------------------------------
	# UTILITIES — $150 each; rent = dice × 4 (or × 10 if both owned)
	# calculate_rent() handles the dice-total multiplication.
	# -----------------------------------------------------------------------
	add.call(12, "Electric Company", "utility", "utility",
		150, 0, [] as Array[int], 0, 75)

	add.call(13, "States Avenue", "property", "pink",
		140, 10, [50, 150, 450, 625, 750] as Array[int], 100, 70)

	add.call(14, "Virginia Avenue", "property", "pink",
		160, 12, [60, 180, 500, 700, 900] as Array[int], 100, 80)

	add.call(15, "Pennsylvania Railroad", "railroad", "railroad",
		200, 25, [] as Array[int], 0, 100)

	# -----------------------------------------------------------------------
	# ORANGE GROUP — $100 house cost
	# -----------------------------------------------------------------------
	add.call(16, "St. James Place", "property", "orange",
		180, 14, [70, 200, 550, 750, 950] as Array[int], 100, 90)

	# Tile 17 — Community Chest (second)
	add.call(17, "Community Chest", "community_chest")

	add.call(18, "Tennessee Avenue", "property", "orange",
		180, 14, [70, 200, 550, 750, 950] as Array[int], 100, 90)

	add.call(19, "New York Avenue", "property", "orange",
		200, 16, [80, 220, 600, 800, 1000] as Array[int], 100, 100)

	# -----------------------------------------------------------------------
	# TILE 20 — Free Parking
	# Standard rules: nothing happens. House-rule variants (pot money) can be
	# implemented by reacting to the "nothing" action in GameManager.
	# -----------------------------------------------------------------------
	add.call(20, "Free Parking", "free_parking")

	# -----------------------------------------------------------------------
	# RED GROUP — $150 house cost
	# -----------------------------------------------------------------------
	add.call(21, "Kentucky Avenue", "property", "red",
		220, 18, [90, 250, 700, 875, 1050] as Array[int], 150, 110)

	# Tile 22 — Chance (second)
	add.call(22, "Chance", "chance")

	add.call(23, "Indiana Avenue", "property", "red",
		220, 18, [90, 250, 700, 875, 1050] as Array[int], 150, 110)

	add.call(24, "Illinois Avenue", "property", "red",
		240, 20, [100, 300, 750, 925, 1100] as Array[int], 150, 120)

	add.call(25, "B&O Railroad", "railroad", "railroad",
		200, 25, [] as Array[int], 0, 100)

	# -----------------------------------------------------------------------
	# YELLOW GROUP — $150 house cost
	# -----------------------------------------------------------------------
	add.call(26, "Atlantic Avenue", "property", "yellow",
		260, 22, [110, 330, 800, 975, 1150] as Array[int], 150, 130)

	add.call(27, "Ventnor Avenue", "property", "yellow",
		260, 22, [110, 330, 800, 975, 1150] as Array[int], 150, 130)

	add.call(28, "Water Works", "utility", "utility",
		150, 0, [] as Array[int], 0, 75)

	add.call(29, "Marvin Gardens", "property", "yellow",
		280, 24, [120, 360, 850, 1025, 1200] as Array[int], 150, 140)

	# -----------------------------------------------------------------------
	# TILE 30 — Go to Jail
	# Immediately moves player to tile 10 and sets in_jail = true.
	# -----------------------------------------------------------------------
	add.call(30, "Go to Jail", "go_to_jail")

	# -----------------------------------------------------------------------
	# GREEN GROUP — $200 house cost
	# -----------------------------------------------------------------------
	add.call(31, "Pacific Avenue", "property", "green",
		300, 26, [130, 390, 900, 1100, 1275] as Array[int], 200, 150)

	add.call(32, "North Carolina Avenue", "property", "green",
		300, 26, [130, 390, 900, 1100, 1275] as Array[int], 200, 150)

	# Tile 33 — Community Chest (third)
	add.call(33, "Community Chest", "community_chest")

	add.call(34, "Pennsylvania Avenue", "property", "green",
		320, 28, [150, 450, 1000, 1200, 1400] as Array[int], 200, 160)

	add.call(35, "Short Line Railroad", "railroad", "railroad",
		200, 25, [] as Array[int], 0, 100)

	# Tile 36 — Chance (third)
	add.call(36, "Chance", "chance")

	# -----------------------------------------------------------------------
	# DARK BLUE GROUP — $200 house cost; highest rents on the board
	# -----------------------------------------------------------------------
	add.call(37, "Park Place", "property", "dark_blue",
		350, 35, [175, 500, 1100, 1300, 1500] as Array[int], 200, 175)

	# -----------------------------------------------------------------------
	# TILE 38 — Luxury Tax
	# Flat $100 payment to the bank.
	# -----------------------------------------------------------------------
	add.call(38, "Luxury Tax", "tax", "", 100)

	add.call(39, "Boardwalk", "property", "dark_blue",
		400, 50, [200, 600, 1400, 1700, 2000] as Array[int], 200, 200)

	# Sanity check: we must always have exactly 40 tiles.
	assert(tiles.size() == 40, "BoardManager: Expected 40 tiles, got %d" % tiles.size())

# ---------------------------------------------------------------------------
# TILE POSITION GENERATION
# ---------------------------------------------------------------------------

## _build_tile_positions() — generates 3D world positions for all 40 tiles.
##
## Board layout (top-down view):
##
##   Tiles 30–39 ←←← (left column, top to bottom, X = -4.5)
##        ↑                                              ↓
##   Tiles 20–29                               Tiles 10–19
##   (top row,                                 (right column,
##    right to left,                            bottom to top,
##    Z = -4.5)                                 X = +4.5)
##        ↑                                              ↓
##   Tiles 0–9  →→→ (bottom row, left to right, Z = +4.5)
##
## The board is conceptually 10 tiles wide × 10 tiles tall.
## Each tile occupies 1 world unit. Corner tiles sit at the true corners.
## Y = 0.1 lifts positions just above the board mesh surface.
##
## Output: tile_world_positions[] has 40 Vector3 values matching tiles[].
func _build_tile_positions() -> void:
	tile_world_positions.clear()
	tile_world_positions.resize(40)

	# Half-extent of the board in world units.
	# With 10 tiles per side and 1 unit per tile, the board spans ±4.5 units.
	const HALF: float = 4.5
	const Y: float = 0.1  # Slight elevation above the board surface mesh.

	# -----------------------------------------------------------------------
	# Bottom row: tiles 0–9, left → right
	# Z is fixed at +HALF (near edge of board from default camera).
	# X runs from -HALF (tile 0, GO) to +HALF (tile 9).
	# -----------------------------------------------------------------------
	for i in range(10):
		var x: float = -HALF + float(i)
		tile_world_positions[i] = Vector3(x, Y, HALF)

	# -----------------------------------------------------------------------
	# Right column: tiles 10–19, bottom → top
	# X is fixed at +HALF (right edge).
	# Z runs from +HALF - 1 (tile 10) to -HALF (tile 19).
	# We subtract 1 because tile 9 already occupies (HALF, Y, HALF).
	# -----------------------------------------------------------------------
	for i in range(10):
		var z: float = HALF - 1.0 - float(i)
		tile_world_positions[10 + i] = Vector3(HALF, Y, z)

	# -----------------------------------------------------------------------
	# Top row: tiles 20–29, right → left
	# Z is fixed at -HALF (far edge).
	# X runs from +HALF - 1 (tile 20) to -HALF (tile 29).
	# -----------------------------------------------------------------------
	for i in range(10):
		var x: float = HALF - 1.0 - float(i)
		tile_world_positions[20 + i] = Vector3(x, Y, -HALF)

	# -----------------------------------------------------------------------
	# Left column: tiles 30–39, top → bottom
	# X is fixed at -HALF (left edge).
	# Z runs from -HALF + 1 (tile 30) to +HALF - 1 (tile 39).
	# -----------------------------------------------------------------------
	for i in range(10):
		var z: float = -HALF + 1.0 + float(i)
		tile_world_positions[30 + i] = Vector3(-HALF, Y, z)

# ---------------------------------------------------------------------------
# TILE ACCESSORS
# ---------------------------------------------------------------------------

## get_tile(index) → TileData
## Returns the TileData for the given board index.
## Wraps with modulo 40 so callers can safely pass raw position values
## without needing to clamp themselves (e.g. after adding dice roll).
##
## Input:  index — any integer (may be > 39 or negative)
## Output: TileData reference from tiles[]
func get_tile(index: int) -> BoardTileData:
	return tiles[index % 40]

## get_tile_world_position(index) → Vector3
## Returns the 3D world position for a given tile index.
## Pawn3D calls this to determine where to tween the pawn mesh.
## Also used by camera framing when following a pawn.
##
## Input:  index — tile index 0–39 (modulo-safe)
## Output: Vector3 world position (Y = 0.1 above board surface)
func get_tile_world_position(index: int) -> Vector3:
	return tile_world_positions[index % 40]

# ---------------------------------------------------------------------------
# OWNERSHIP
# ---------------------------------------------------------------------------

## get_tile_owner(tile_index) → int
## Returns the peer_id of who owns the tile.
##   0  = unowned / available for purchase
##  -1  = bank or non-purchasable (GO, jail, etc.)
## >0   = owning player's peer_id
func get_tile_owner(tile_index: int) -> int:
	return tiles[tile_index % 40].owner_id

## set_tile_owner(tile_index, peer_id) → void
## Sets the owner of a tile and emits property_purchased so UI and
## GameManager can update ownership displays and monopoly checks.
func set_tile_owner(tile_index: int, peer_id: int) -> void:
	var tile: BoardTileData = tiles[tile_index % 40]
	tile.owner_id = peer_id
	emit_signal("property_purchased", peer_id, tile_index)

## get_tiles_by_owner(peer_id) → Array[BoardTileData]
## Filter helper that returns all tiles currently owned by the given peer.
## Used by:
##   - BoardManager.calculate_rent() to count railroads / utilities.
##   - GameManager to check if a player owns a full colour group (monopoly).
##   - UI to populate the deed-card inventory panel.
##
## Input:  peer_id — player's ENet peer_id
## Output: Array of BoardTileData references (may be empty if player owns nothing)
func get_tiles_by_owner(peer_id: int) -> Array[BoardTileData]:
	var result: Array[BoardTileData] = []
	for tile in tiles:
		if tile.owner_id == peer_id:
			result.append(tile)
	return result

# ---------------------------------------------------------------------------
# RENT CALCULATION
# ---------------------------------------------------------------------------

## calculate_rent(tile_index, player_id, dice_total) → int
## Returns the rent amount the landing player must pay to the tile's owner.
##
## Rules implemented:
##   Mortgaged property → $0 (no rent on mortgaged tiles)
##   Property (0 houses, monopoly owned) → base_rent × 2
##   Property (houses built) → house_rents[house_count - 1]
##   Railroad → $25 × number of railroads the same owner has
##   Utility → dice_total × 4 (one utility) or dice_total × 10 (both owned)
##
## Input:
##   tile_index — 0–39, the tile that was landed on
##   player_id  — peer_id of the player who landed (used to avoid self-rent)
##   dice_total — sum of both dice this turn (needed for utility rent)
## Output:
##   int — dollar amount of rent owed; 0 if no rent applies
func calculate_rent(tile_index: int, player_id: int, dice_total: int = 0) -> int:
	var tile: BoardTileData = get_tile(tile_index)

	# Mortgaged properties collect no rent.
	if tile.is_mortgaged:
		return 0

	# Player landing on their own property pays nothing.
	if tile.owner_id == player_id:
		return 0

	# No owner → nothing to pay.
	if tile.owner_id <= 0:
		return 0

	match tile.tile_type:

		# ---------------------------------------------------------------
		# PROPERTY RENT
		# ---------------------------------------------------------------
		"property":
			# With houses or a hotel, use the deed-card progressive rate.
			if tile.house_count > 0:
				# house_count 1–4 → index 0–3; house_count 5 (hotel) → index 4
				var rent_idx: int = min(tile.house_count - 1, 4)
				return tile.house_rents[rent_idx]

			# Unimproved — check for monopoly (owner holds all tiles in group).
			var owner_tiles := get_tiles_by_owner(tile.owner_id)
			var group_owned_count: int = 0
			var group_total_count: int = 0
			for t in tiles:
				if t.color_group == tile.color_group and t.tile_type == "property":
					group_total_count += 1
					if t.owner_id == tile.owner_id:
						group_owned_count += 1
			var has_monopoly: bool = (group_owned_count == group_total_count)

			# Double rent on unimproved monopoly (standard Monopoly rule).
			return tile.base_rent * (2 if has_monopoly else 1)

		# ---------------------------------------------------------------
		# RAILROAD RENT — $25, $50, $100, $200 for 1–4 railroads owned
		# ---------------------------------------------------------------
		"railroad":
			var owner_tiles := get_tiles_by_owner(tile.owner_id)
			var rr_count: int = 0
			for t in owner_tiles:
				if t.tile_type == "railroad" and not t.is_mortgaged:
					rr_count += 1
			# $25 × 2^(rr_count-1) is equivalent to $25, $50, $100, $200
			return 25 * (1 << (rr_count - 1))

		# ---------------------------------------------------------------
		# UTILITY RENT — dice-based; 4× or 10× depending on ownership
		# ---------------------------------------------------------------
		"utility":
			var owner_tiles := get_tiles_by_owner(tile.owner_id)
			var util_count: int = 0
			for t in owner_tiles:
				if t.tile_type == "utility" and not t.is_mortgaged:
					util_count += 1
			# 1 utility owned → 4× dice; both → 10× dice
			var multiplier: int = 10 if util_count >= 2 else 4
			return dice_total * multiplier

	# Any other tile type (GO, tax, etc.) — rent not applicable.
	return 0

# ---------------------------------------------------------------------------
# MORTGAGE
# ---------------------------------------------------------------------------

## mortgage_property(tile_index) → int
## Marks the tile as mortgaged and returns the cash value paid to the player.
## The caller (GameManager) is responsible for adding the returned amount
## to the player's money balance.
##
## Rules:
##   - Can only mortgage an unimproved property (no houses).
##   - Cannot mortgage if houses remain on any property in the same group.
##   - No rent is collected on a mortgaged property (handled in calculate_rent).
##
## Input:  tile_index — 0–39
## Output: mortgage_value (amount to give the player) or 0 if already mortgaged
func mortgage_property(tile_index: int) -> int:
	var tile: BoardTileData = get_tile(tile_index)

	# Guard: already mortgaged — caller shouldn't call again.
	if tile.is_mortgaged:
		push_warning("BoardManager.mortgage_property: tile %d is already mortgaged." % tile_index)
		return 0

	tile.is_mortgaged = true
	return tile.mortgage_value

# ---------------------------------------------------------------------------
# LANDING DISPATCHER
# ---------------------------------------------------------------------------

## handle_landing(player_id, tile_index, dice_total) → Dictionary
## The master landing dispatcher called by GameManager after a pawn arrives.
##
## This function does NOT mutate PlayerData money or position — that is
## GameManager's job. It returns a structured Dictionary so GameManager can
## apply the effects and show appropriate UI dialogs.
##
## Return Dictionary shape:
##   {
##     "action":    String,   # what should happen (see below)
##     "amount":    int,      # dollar figure relevant to the action (0 if N/A)
##     "target_id": int,      # peer_id of the rent recipient (0 if N/A)
##     "tile":      TileData  # the tile that was landed on (for UI reference)
##   }
##
## Action values:
##   "buy_available"   — tile is unowned; offer the player a purchase dialog
##   "pay_rent"        — player owes rent to target_id
##   "pay_tax"         — player owes tax amount to the bank
##   "go_to_jail"      — send player to jail (tile 10, in_jail = true)
##   "collect_go"      — player landed on GO; pay $200 salary
##   "chance"          — draw a Chance card
##   "community_chest" — draw a Community Chest card
##   "nothing"         — no financial effect (Just Visiting, Free Parking, etc.)
##
## Input:
##   player_id  — peer_id of the player who just landed
##   tile_index — 0–39, destination tile
##   dice_total — sum of both dice (needed for utility rent calculation)
## Output:
##   Dictionary with keys: action, amount, target_id, tile
func handle_landing(player_id: int, tile_index: int, dice_total: int = 0) -> Dictionary:
	var tile: BoardTileData = get_tile(tile_index)

	# Base result with safe defaults.
	var result: Dictionary = {
		"action":    "nothing",
		"amount":    0,
		"target_id": 0,
		"tile":      tile
	}

	# Emit the landed signal so Pawn3D/camera can react independently.
	emit_signal("player_landed", player_id, tile_index)

	match tile.tile_type:

		# ---------------------------------------------------------------
		# GO — collect $200 salary
		# ---------------------------------------------------------------
		"go":
			result["action"] = "collect_go"
			result["amount"] = 200

		# ---------------------------------------------------------------
		# PROPERTY / RAILROAD / UTILITY
		# ---------------------------------------------------------------
		"property", "railroad", "utility":
			var owner: int = tile.owner_id

			if owner == 0:
				# Tile is unowned — give player the option to buy.
				result["action"] = "buy_available"
				result["amount"] = tile.purchase_price

			elif owner == player_id:
				# Player owns this tile — nothing to pay.
				result["action"] = "nothing"

			else:
				# Someone else owns it — calculate and collect rent.
				var rent: int = calculate_rent(tile_index, player_id, dice_total)
				result["action"]    = "pay_rent"
				result["amount"]    = rent
				result["target_id"] = owner
				# Emit rent signal so GameManager can transfer money.
				emit_signal("rent_collected", player_id, owner, rent)

		# ---------------------------------------------------------------
		# TAX — mandatory bank payment
		# purchase_price is reused to store the tax amount.
		# ---------------------------------------------------------------
		"tax":
			result["action"] = "pay_tax"
			result["amount"] = tile.purchase_price

		# ---------------------------------------------------------------
		# GO TO JAIL
		# ---------------------------------------------------------------
		"go_to_jail":
			result["action"] = "go_to_jail"
			# GameManager will set player position to 10 and in_jail = true.

		# ---------------------------------------------------------------
		# CARD TILES
		# ---------------------------------------------------------------
		"chance":
			result["action"] = "chance"

		"community_chest":
			result["action"] = "community_chest"

		# ---------------------------------------------------------------
		# NOTHING TILES — Jail/Just Visiting, Free Parking
		# ---------------------------------------------------------------
		"jail", "free_parking":
			result["action"] = "nothing"

	return result
