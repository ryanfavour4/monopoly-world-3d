# =============================================================================
# PlayerData.gd
# =============================================================================
# A lightweight data-only Resource that holds the authoritative game state for
# a single player. Using a Resource (rather than a plain Dictionary or Node)
# gives us:
#   • Type safety via @export annotations
#   • Easy serialisation / deserialisation with ResourceSaver / ResourceLoader
#   • Clean signal-free storage that can be passed between functions and nodes
#     without coupling to the scene tree
#   • Compatibility with Godot's built-in multiplayer synchroniser if needed
#
# Instances of this class are created by GameManager at game start (one per
# player) and mutated by the relevant managers (BoardManager, BankManager,
# PropertyManager) as the game progresses. The PlayerPawn scene reads from
# this resource to drive its visual state but should NEVER write to it —
# all writes go through GameManager to keep authority clear.
# =============================================================================

class_name PlayerData
extends Resource

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

## peer_id
## -------
## The ENet / WebRTC unique peer ID assigned to this player by Godot's
## MultiplayerAPI. Used as the canonical key to look up this player across
## all managers and to route RPCs to the correct client.
## Value 1 is always the server/host in Godot's default MultiplayerAPI.
@export var peer_id: int = 0

## username
## --------
## The display name chosen by the player during lobby setup.
## Shown on the floating Label3D above their pawn and in the HUD scoreboard.
## Limited to ~16 characters by the lobby UI, but no hard limit enforced here.
@export var username: String = ""

# ---------------------------------------------------------------------------
# Economy
# ---------------------------------------------------------------------------

## money
## -----
## The player's current cash balance in the game's currency (Monopoly dollars).
## Starts at 1500 per the official Monopoly rules:
##   2x $500, 2x $100, 2x $50, 6x $20, 5x $10, 5x $5, 5x $1
## Modified by BankManager.pay() and BankManager.collect().
## If this reaches 0 or below and the player cannot sell/mortgage to cover a
## debt, is_bankrupt is set to true.
@export var money: int = 1500

# ---------------------------------------------------------------------------
# Board position
# ---------------------------------------------------------------------------

## board_position
## --------------
## The tile index (0-39) of the board tile this player currently occupies.
## 0  = Go
## 10 = Jail / Just Visiting
## 20 = Free Parking
## 30 = Go To Jail
## Updated by BoardManager after every move or teleport.
## The PlayerPawn's current_tile mirrors this value visually.
@export var board_position: int = 0

# ---------------------------------------------------------------------------
# Ownership
# ---------------------------------------------------------------------------

## owned_tiles
## -----------
## Array of board tile indices (0-39) that this player owns as properties,
## railroads, or utilities. Does NOT include mortgaged tiles (those remain in
## the list but PropertyManager checks the mortgage flag separately).
## Used by PropertyManager to calculate rent, check monopolies, and display
## colour groups on the HUD.
@export var owned_tiles: Array[int] = []

# ---------------------------------------------------------------------------
# Jail state
# ---------------------------------------------------------------------------

## in_jail
## -------
## True while the player is serving time in Jail (tile 10, jail mode -- not
## Just Visiting). When true, the turn manager applies jail turn rules:
##   - Must roll doubles to escape, OR
##   - Pay $50 fine, OR
##   - Use a Get Out of Jail Free card.
## Distinct from board_position == 10 because Just Visiting is also tile 10
## but in_jail = false.
@export var in_jail: bool = false

## jail_turns
## ----------
## Number of turns already spent in jail. The player is forced to pay the $50
## fine and exit after 3 consecutive jail turns without rolling doubles,
## per standard Monopoly rules.
## Reset to 0 whenever the player exits jail by any means.
@export var jail_turns: int = 0

# ---------------------------------------------------------------------------
# Bankruptcy
# ---------------------------------------------------------------------------

## is_bankrupt
## -----------
## Set to true when the player cannot pay a debt (rent, tax, mortgage interest)
## even after liquidating all assets (selling houses, mortgaging properties).
## When true, GameManager removes this player from the active turn order and
## transfers all remaining assets to the creditor (or back to the bank).
## The game ends when only one non-bankrupt player remains.
@export var is_bankrupt: bool = false

# ---------------------------------------------------------------------------
# Appearance
# ---------------------------------------------------------------------------

## pawn_color
## ----------
## The unique colour assigned to this player in the lobby colour-picker.
## Passed to PlayerPawn.setup() to tint the 3-D mesh and used by the HUD
## scoreboard to colour-code the player's name and money display.
## Colours must be unique per session; LobbyManager enforces this constraint.
@export var pawn_color: Color = Color.WHITE

# ---------------------------------------------------------------------------
# Cards
# ---------------------------------------------------------------------------

## get_out_of_jail_cards
## ---------------------
## The number of "Get Out of Jail Free" cards currently held by this player.
## Cards are awarded by specific Chance and Community Chest tiles.
## When in_jail == true the player may spend one card (decrement this by 1)
## to exit jail immediately without rolling doubles or paying the $50 fine.
## Maximum theoretically holdable: 2 (one Chance, one Community Chest card).
@export var get_out_of_jail_cards: int = 0
