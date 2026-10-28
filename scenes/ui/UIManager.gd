## UIManager.gd
## ============================================================
## Scene: Added as a child node of the main Board scene.
## Node type: Node  (no visual presence itself; owns UI children)
##
## PURPOSE:
##   UIManager is the MASTER ORCHESTRATOR of all in-game UI.
##   It sits between the game-logic layer (TurnManager, BoardManager,
##   GameState) and the visual layer (CasinoModal, InventoryPanel,
##   HUD banners, dice roller) so that neither side needs to know
##   the internals of the other.
##
##   Responsibilities:
##     1. Translate TurnManager "landing results" into appropriate modals.
##     2. Show turn-transition banners with animations.
##     3. Trigger random Chance / Community Chest card draws and apply effects.
##     4. Delegate end-turn requests from the HUD button.
##
## SCENE TREE EXPECTED:
##   UIManager (Node)                    ← this script
##   ├─ CasinoModal (CasinoModal)        ← full-screen modal overlay
##   ├─ InventoryPanel (InventoryPanel)  ← property grid panel
##   ├─ TurnBanner (Label)               ← "Alice's Turn!" HUD label
##   ├─ DiceRoller (Node)                ← reference only; UIManager doesn't
##   │                                      control dice — TurnManager does.
##   └─ EndTurnButton (Button)           ← only visible for the local player
##
## NETWORK NOTES:
##   UIManager runs on every client. It receives `handle_landing_result()`
##   from TurnManager (which coordinates over the network) and applies
##   LOCAL effects only (showing modals, updating labels).
##   All money transfers and state mutations go through TurnManager RPCs.
## ============================================================
class_name UIManager
extends Node


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var casino_modal: Control = get_node_or_null("../CasinoModal")
@onready var inventory_panel: Control = get_node_or_null("../InventoryPanel")
@onready var turn_banner: Label = get_node_or_null("../TurnBanner")
@onready var dice_roller: Node = get_node_or_null("../DiceRoller")
@onready var end_turn_button: Button = get_node_or_null("../EndTurnButton")


# ---------------------------------------------------------------------------
# Constants — Chance card deck
# ---------------------------------------------------------------------------
## Each entry is a Dictionary:
##   { "text": String displayed in the modal,
##     "delta": int  money change (+positive / -negative),
##     "move_to": int  tile index (-1 = no move),
##     "go_to_jail": bool }
##
## Why define cards here rather than in a JSON resource?
##   For a first pass, inline data is faster to iterate. In a future module
##   these could be loaded from a data file so designers can edit without code.
const CHANCE_CARDS: Array[Dictionary] = [
	{
		"text": "Advance to GO! Collect $200.",
		"delta": 200,
		"move_to": 0,
		"go_to_jail": false
	},
	{
		"text": "Bank pays you a dividend of $50.",
		"delta": 50,
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "Pay a $50 fine or take a Chance.",
		"delta": -50,
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "Go Back 3 Spaces.",
		"delta": 0,
		"move_to": -3,   # Negative = relative move back; TurnManager handles this.
		"go_to_jail": false
	},
	{
		"text": "Speeding fine — pay $15.",
		"delta": -15,
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "Your building loan matures — collect $150.",
		"delta": 150,
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "Make general repairs on all your properties: pay $25 per house, $100 per hotel.",
		"delta": 0,        # TurnManager calculates actual amount based on holdings.
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "Go to Jail. Go directly to Jail. Do not pass GO. Do not collect $200.",
		"delta": 0,
		"move_to": -1,
		"go_to_jail": true
	},
	{
		"text": "Advance to the nearest railroad and pay double rent.",
		"delta": 0,
		"move_to": -2,   # Special sentinel: TurnManager looks for nearest railroad.
		"go_to_jail": false
	},
	{
		"text": "You have been elected chairman of the board — pay each player $50.",
		"delta": 0,       # TurnManager distributes $50 to each other player.
		"move_to": -1,
		"go_to_jail": false
	},
]


# ---------------------------------------------------------------------------
# Constants — Community Chest card deck
# ---------------------------------------------------------------------------
const COMMUNITY_CHEST_CARDS: Array[Dictionary] = [
	{
		"text": "Bank error in your favour — collect $200.",
		"delta": 200,
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "Doctor's fee — pay $50.",
		"delta": -50,
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "From sale of stock — you get $45.",
		"delta": 45,
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "Grand Opera Night — collect $50 from every player for opening night seats.",
		"delta": 0,       # TurnManager collects from each other player.
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "Holiday fund matures — receive $100.",
		"delta": 100,
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "Income tax refund — collect $20.",
		"delta": 20,
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "It is your birthday — collect $10 from every other player.",
		"delta": 0,       # TurnManager handles per-player collection.
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "Life insurance matures — collect $100.",
		"delta": 100,
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "Pay hospital fees of $50.",
		"delta": -50,
		"move_to": -1,
		"go_to_jail": false
	},
	{
		"text": "Go to Jail. Go directly to Jail. Do not pass GO. Do not collect $200.",
		"delta": 0,
		"move_to": -1,
		"go_to_jail": true
	},
]


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if end_turn_button:
		end_turn_button.hide()
		if not end_turn_button.pressed.is_connected(_on_end_turn_button_pressed):
			end_turn_button.pressed.connect(_on_end_turn_button_pressed)

	if turn_banner:
		turn_banner.modulate.a = 0.0


# ---------------------------------------------------------------------------
# Turn-transition HUD
# ---------------------------------------------------------------------------

## show_turn_notification — Update the HUD banner and end-turn button visibility.
##
## Called by TurnManager at the START of each player's turn, on ALL clients.
##
## Design intent:
##   - Green banner + End Turn button = "it's me, I need to act."
##   - Grey banner, no button         = "watching someone else play."
##
## Parameters:
##   player_id — Peer ID of the player whose turn it now is.
##   username  — Display name for that player (from GameState).
##   is_local  — True if player_id == multiplayer.get_unique_id().
func show_turn_notification(player_id: int, username: String = "", is_local: bool = false) -> void:
	if username.is_empty():
		var p_data: Dictionary = GameState.get_player(player_id)
		username = p_data.get("username", "Player %d" % player_id)
		is_local = (player_id == multiplayer.get_unique_id())

	# Compose banner text. Using ALL-CAPS when local creates a sense of urgency.
	if is_local:
		turn_banner.text = "🎲 YOUR TURN, %s!" % username.to_upper()
		turn_banner.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))  # Green
		end_turn_button.show()
	else:
		turn_banner.text = "%s's Turn..." % username
		turn_banner.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))  # Grey
		end_turn_button.hide()

	# Animate: fade in → hold → fade out.
	# The tween is non-blocking; the rest of the turn setup continues while it plays.
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)

	# 1. Fade in over 0.3 s.
	tween.tween_property(turn_banner, "modulate:a", 1.0, 0.3)

	# 2. Hold visible for 2 s.
	tween.tween_interval(2.0)

	# 3. Fade out over 0.5 s.
	tween.tween_property(turn_banner, "modulate:a", 0.0, 0.5)

	# Also refresh the inventory panel so it shows the local player's properties.
	# If it's a remote player's turn, we still show the local player's inventory
	# (they might want to plan mortgages etc. while waiting).
	var local_id: int = multiplayer.get_unique_id()
	inventory_panel.refresh_inventory(local_id)


# ---------------------------------------------------------------------------
# Landing result dispatcher
# ---------------------------------------------------------------------------

## handle_landing_result — Master dispatcher after a pawn lands on a tile.
##
## Called by TurnManager once the pawn animation settles on the new tile.
## `result` is a Dictionary whose "action" key determines what happens next.
##
## Expected result keys (varies by action):
##   action (String) — one of the cases below
##   tile_name (String)
##   price (int)             — for buy_available
##   owner_id (int)          — for pay_rent
##   owner_username (String) — for pay_rent
##   rent_amount (int)       — for pay_rent
##   tax_amount (int)        — for pay_tax
##   tax_name (String)       — for pay_tax
##
## Parameters:
##   player_id — The peer who just landed (used to build callbacks).
##   result    — Dictionary describing what should happen.
func handle_landing_result(player_id: int, result: Dictionary) -> void:
	var action: String = result.get("action", "")
	var tile: BoardTileData = result.get("tile", null)
	var local_id: int = multiplayer.get_unique_id()
	var is_local: bool = (player_id == local_id)

	# If event happened to a remote player, only notify local player if rent was paid to them
	if not is_local:
		if action == "pay_rent":
			var owner_id: int = result.get("target_id", result.get("owner_id", 0))
			if owner_id == local_id:
				var rent_amt: int = result.get("amount", result.get("rent_amount", 0))
				var t_name: String = tile.tile_name if tile else "Property"
				var p_data: Dictionary = GameState.get_player(player_id)
				var p_name: String = p_data.get("username", "Player %d" % player_id)
				casino_modal.show_info_modal("💸 Rent Received!", "%s landed on %s and paid you $%d rent." % [p_name, t_name, rent_amt])
		return

	match action:
		"buy_available":
			var tile_name: String = tile.tile_name if tile else result.get("tile_name", "Property")
			var price: int        = result.get("amount", result.get("price", 0))
			var tile_index: int   = tile.tile_index if tile else result.get("tile_index", -1)

			casino_modal.show_purchase_modal(
				tile_name,
				price,
				func() -> void:
					TurnManager.purchase_property(player_id, tile_index)
			)

		"pay_rent":
			var owner_id: int          = result.get("target_id", result.get("owner_id", 0))
			var rent_amount: int       = result.get("amount", result.get("rent_amount", 0))
			var tile_name: String      = tile.tile_name if tile else result.get("tile_name", "Property")
			var owner_data: Dictionary = GameState.get_player(owner_id)
			var owner_username: String = owner_data.get("username", "Player %d" % owner_id)

			casino_modal.show_rent_modal(
				owner_username,
				rent_amount,
				tile_name,
				func() -> void:
					TurnManager.pay_rent(player_id, owner_id, rent_amount)
			)

		"pay_tax":
			var tax_name: String = tile.tile_name if tile else "Tax"
			var tax_amount: int  = result.get("amount", result.get("tax_amount", 0))

			# Mandatory tax payment
			TurnManager.apply_money_delta(player_id, -tax_amount)
			casino_modal.show_info_modal(
				"💰 %s" % tax_name.to_upper(),
				"You paid $%d in %s." % [tax_amount, tax_name]
			)

		"go_to_jail":
			casino_modal.show_info_modal(
				"🚔 GO TO JAIL!",
				"Do not pass GO.\nDo not collect $200.\nGo directly to Jail!"
			)
			TurnManager.send_to_jail(player_id)

		"collect_go":
			casino_modal.show_info_modal(
				"💰 PASS GO!",
				"You collected $200 salary for passing GO!"
			)

		"chance":
			# Draw and resolve a Chance card.
			_handle_chance_card(player_id)

		"community_chest":
			# Draw and resolve a Community Chest card.
			_handle_community_chest(player_id)

		"free_parking":
			casino_modal.show_info_modal(
				"🅿️ FREE PARKING",
				"Enjoy the free space — nothing happens here!"
			)

		"jail_visiting":
			casino_modal.show_info_modal(
				"🔍 JUST VISITING",
				"You're just visiting the jail.\nNothing to pay today."
			)

		_:
			# Unknown action — log and continue so the game doesn't freeze.
			push_warning("UIManager.handle_landing_result: unknown action '%s'" % action)


# ---------------------------------------------------------------------------
# Card handlers
# ---------------------------------------------------------------------------

## _handle_chance_card — Draw a random Chance card, apply its effect, show modal.
##
## Why random here rather than a shuffled deck?
##   A shuffled deck requires per-client state sync to ensure all clients
##   see the same card. Using a seeded random (seeded by TurnManager per turn)
##   is simpler and gives statistically similar distribution without networked
##   deck state. Full deck logic is a future enhancement.
##
## Parameters:
##   player_id — Peer ID of the player who landed on Chance.
func _handle_chance_card(player_id: int) -> void:
	# Pick a random card from the deck.
	var card: Dictionary = CHANCE_CARDS[randi() % CHANCE_CARDS.size()]

	# Build a user-facing title with the card number for flavour.
	var title: String = "🎴 CHANCE!"

	# Apply the card effect through TurnManager (keeps logic server-authoritative).
	if card.go_to_jail:
		# Jail card — show the modal then move to jail.
		casino_modal.show_info_modal(title, card.text)
		TurnManager.send_to_jail(player_id)

	elif card.delta != 0:
		# Simple money delta — positive = collect, negative = pay.
		TurnManager.apply_money_delta(player_id, card.delta)
		var sign_str: String = "+" if card.delta > 0 else ""
		casino_modal.show_info_modal(
			title,
			"%s\n[%s$%d]" % [card.text, sign_str, abs(card.delta)]
		)

	elif card.move_to == 0:
		# Advance to GO — player also collects $200 if they weren't already there.
		TurnManager.move_player_to_tile(player_id, 0, true)   # true = collect GO salary
		casino_modal.show_info_modal(title, card.text)

	elif card.move_to == -2:
		# Special sentinel: advance to nearest railroad and pay double rent.
		TurnManager.move_to_nearest_railroad(player_id)
		casino_modal.show_info_modal(title, card.text)

	elif card.move_to == -3:
		# Go back 3 spaces.
		TurnManager.move_player_relative(player_id, -3)
		casino_modal.show_info_modal(title, card.text)

	else:
		# Cards with complex multi-player effects (chairman, repairs, etc.)
		# pass delta=0 and move_to=-1. TurnManager interprets these by card text.
		TurnManager.apply_chance_card(player_id, card)
		casino_modal.show_info_modal(title, card.text)


## _handle_community_chest — Draw a random Community Chest card, apply, show modal.
##
## Same approach as _handle_chance_card; see that function's doc for rationale.
##
## Parameters:
##   player_id — Peer ID of the player who landed on Community Chest.
func _handle_community_chest(player_id: int) -> void:
	var card: Dictionary = COMMUNITY_CHEST_CARDS[randi() % COMMUNITY_CHEST_CARDS.size()]
	var title: String    = "📦 COMMUNITY CHEST!"

	if card.go_to_jail:
		casino_modal.show_info_modal(title, card.text)
		TurnManager.send_to_jail(player_id)

	elif card.delta != 0:
		TurnManager.apply_money_delta(player_id, card.delta)
		var sign_str: String = "+" if card.delta > 0 else ""
		casino_modal.show_info_modal(
			title,
			"%s\n[%s$%d]" % [card.text, sign_str, abs(card.delta)]
		)

	else:
		# Multi-player effects (birthday, opera night, etc.) — let TurnManager
		# compute and distribute payments across all connected peers.
		TurnManager.apply_community_chest_card(player_id, card)
		casino_modal.show_info_modal(title, card.text)


# ---------------------------------------------------------------------------
# Helper — show a tile detail popup (called by InventoryPanel)
# ---------------------------------------------------------------------------

## show_tile_detail — Show an info modal with full stats for a tile.
##
## Called when the player clicks a PropertyCard in InventoryPanel.
## Gives them rent tables, mortgage value, etc., without leaving the board view.
##
## Parameters:
##   tile_index — Board tile index to look up.
func show_tile_detail(tile_index: int) -> void:
	var tile_data: BoardTileData = BoardManager.get_tile(tile_index)
	if tile_data == null:
		return

	var h_rents: Array[int] = tile_data.house_rents
	var r1 = h_rents[0] if h_rents.size() > 0 else 0
	var r2 = h_rents[1] if h_rents.size() > 1 else 0
	var r3 = h_rents[2] if h_rents.size() > 2 else 0
	var r4 = h_rents[3] if h_rents.size() > 3 else 0
	var r_hotel = h_rents[4] if h_rents.size() > 4 else 0

	var detail: String = (
		"Price: $%d\n" +
		"Base Rent: $%d\n" +
		"With 1 house: $%d\n" +
		"With 2 houses: $%d\n" +
		"With 3 houses: $%d\n" +
		"With 4 houses: $%d\n" +
		"Hotel: $%d\n" +
		"Mortgage value: $%d"
	) % [
		tile_data.purchase_price,
		tile_data.base_rent,
		r1, r2, r3, r4, r_hotel,
		tile_data.mortgage_value
	]

	casino_modal.show_info_modal("📋 " + tile_data.tile_name, detail)


## show_confirm_modal — Generic yes/no confirmation modal.
##
## Used by InventoryPanel for mortgage confirmation.
## Delegates to show_casino_modal with a pay button labelled "Confirm".
##
## Parameters:
##   title      — Modal title.
##   message    — Body text describing the action.
##   on_confirm — Callable to invoke if the player clicks Confirm.
func show_confirm_modal(title: String, message: String, on_confirm: Callable) -> void:
	casino_modal.pay_button.text   = "Confirm"
	casino_modal.close_button.text = "Cancel"
	casino_modal.show_casino_modal(title, message, on_confirm, true)


## show_passed_go_toast
## Notifies player that they passed GO and collected $200
func show_passed_go_toast(player_id: int) -> void:
	if player_id == multiplayer.get_unique_id():
		if casino_modal and casino_modal.has_method("show_info_modal"):
			casino_modal.show_info_modal("💰 COLLECT $200", "You passed GO and collected your $200 salary!")


## show_landing_ui
## Evaluates landing tile and displays appropriate interaction
func show_landing_ui(player_id: int, tile_index: int) -> void:
	var bm: Node = get_node_or_null("/root/BoardManager")
	if not bm:
		bm = get_tree().root.find_child("BoardManager", true, false)
	if bm and bm.has_method("handle_landing"):
		var result: Dictionary = bm.handle_landing(player_id, tile_index, 0)
		handle_landing_result(player_id, result)



# ---------------------------------------------------------------------------
# Button handler
# ---------------------------------------------------------------------------

## _on_end_turn_button_pressed — local player signals they are done with their turn.
##
## Why validate here?
##   The end-turn button should only be pressable when it is the local player's
##   turn (it's hidden otherwise), but we guard anyway against edge cases
##   (e.g. rapid double-clicks or network lag).
func _on_end_turn_button_pressed() -> void:
	# Hide the button immediately to prevent double-submissions.
	end_turn_button.hide()

	# Find TurnManager in the Board scene and advance the turn
	var turn_mgr: Node = get_node_or_null("../../TurnManager")
	if not turn_mgr:
		turn_mgr = get_tree().root.find_child("TurnManager", true, false)
	if turn_mgr and turn_mgr.has_method("end_turn"):
		turn_mgr.end_turn()
	else:
		push_warning("UIManager: TurnManager not found to end turn.")
