###############################################################################
# Lobby.gd
# Attached to: scenes/lobby/Lobby.tscn  →  root node "Lobby" (Control)
#
# PURPOSE:
#   Displays the pre-game lobby where players wait before the match begins.
#   The host can see a "Start Game" button; clients see a read-only list of
#   who has joined. The host's local IP is displayed so others can join.
#
# EXPECTED NODE TREE (create this structure in the Godot editor):
#
#   Lobby  (Control)  ← this script goes here
#   ├── Background  (ColorRect)
#   │       FullRect anchors; set Color to a dark shade (e.g. #1a1a2e).
#   ├── Title  (Label)
#   │       Text = "GAME LOBBY"
#   │       Centered at the top; large, bold font.
#   ├── PlayerListVBox  (VBoxContainer)
#   │       Populated at runtime with one Label per connected player.
#   │       Place it in the center of the screen.
#   ├── StartButton  (Button)
#   │       Text = "Start Game"
#   │       Visible only to the host (hidden via script).
#   ├── IPDisplayLabel  (Label)
#   │       Shows the server's local IP address so others can connect.
#   │       Example text after script runs: "Your IP: 192.168.1.5"
#   └── StatusLabel  (Label)
#           Text = ""  — runtime messages (e.g. "Waiting for host…")
#
# DEPENDENCIES (autoloads / singletons):
#   • NetworkUtility  — peer management helpers and signals
#   • GameState       — Dictionary of players keyed by peer_id
#                       Each value is a Dictionary with at least:
#                           { "username": String, "money": int }
#   • TurnManager     — autoload; setup_turn_order() called here by host
#
# SIGNALS CONSUMED FROM NetworkUtility:
#   • lobby_updated()          — emitted when a player joins or leaves
#   • game_start_requested()   — emitted on ALL peers when host starts game
###############################################################################

extends Control

# ---------------------------------------------------------------------------
# Node references — resolved at runtime via @onready.
# Path strings MUST match the node names in the .tscn exactly.
# ---------------------------------------------------------------------------

## VBoxContainer that is cleared and repopulated whenever the player list
## changes. Each child will be a Label showing one player's info.
@onready var player_list: VBoxContainer = find_child("PlayerListVBox", true, false)

## "Start Game" button — shown only to the host, hidden for clients.
@onready var start_button: Button = find_child("StartButton", true, false)

## Label that displays the server's local IP address for easy sharing.
@onready var ip_label: Label = find_child("IPDisplayLabel", true, false)

## General-purpose status / hint label at the bottom of the screen.
@onready var status_label: Label = find_child("StatusLabel", true, false)


# ---------------------------------------------------------------------------
# _ready — called once when the node enters the scene tree.
# Sets up UI visibility, displays the host IP, and wires all signals.
# ---------------------------------------------------------------------------
func _ready() -> void:
	# ── Host vs Client UI ─────────────────────────────────────────────────
	# Only the host (server peer, peer_id == 1) should see the Start button.
	start_button.visible = NetworkUtility.is_host()

	if NetworkUtility.is_host():
		status_label.text = "Waiting for players to join…"
		start_button.pressed.connect(_on_start_button_pressed)
	else:
		status_label.text = "Waiting for the host to start the game…"

	var leave_btn: Button = find_child("LeaveButton", true, false)
	if leave_btn and not leave_btn.pressed.is_connected(_on_leave_button_pressed):
		leave_btn.pressed.connect(_on_leave_button_pressed)

	# ── Display local IP ──────────────────────────────────────────────────
	# Fetch all local IPv4 addresses and show the first non-loopback one.
	# Players share this address so others can join.
	_display_local_ip()

	# ── NetworkUtility signal connections ─────────────────────────────────
	# lobby_updated: refresh the player list whenever someone joins/leaves.
	if not NetworkUtility.lobby_updated.is_connected(_refresh_player_list):
		NetworkUtility.lobby_updated.connect(_refresh_player_list)

	# game_start_requested: fired on ALL peers (via RPC) when host starts.
	if not NetworkUtility.game_start_requested.is_connected(_on_game_starting):
		NetworkUtility.game_start_requested.connect(_on_game_starting)

	# ── Initial population ────────────────────────────────────────────────
	# Populate the list immediately in case players are already registered
	# (e.g. host's own entry was added in MainMenu before navigating here).
	_refresh_player_list()


# ---------------------------------------------------------------------------
# _display_local_ip  (private helper)
# Iterates IP.get_local_addresses() and picks the most useful address to
# display — prefers 192.168.x.x / 10.x.x.x LAN addresses over loopback.
# ---------------------------------------------------------------------------
func _display_local_ip() -> void:
	var addresses: Array = IP.get_local_addresses()
	var chosen: String = "127.0.0.1"  # fallback

	for addr in addresses:
		# Skip loopback and IPv6 (colons indicate IPv6).
		if addr == "127.0.0.1" or ":" in addr:
			continue
		# Prefer private LAN ranges that are most likely reachable by peers.
		if addr.begins_with("192.168.") or addr.begins_with("10.") \
				or addr.begins_with("172."):
			chosen = addr
			break

	ip_label.text = "Your IP: %s" % chosen


# ---------------------------------------------------------------------------
# _refresh_player_list
# Slot connected to NetworkUtility.lobby_updated.
# Also called manually in _ready() for the initial render.
#
# Clears the VBoxContainer and rebuilds it from GameState.players, which is
# a Dictionary of the form:
#   { peer_id: { "username": String, "money": int, ... }, … }
#
# The server's own peer_id is always 1 in ENet; we label that player "(Host)".
# ---------------------------------------------------------------------------
func _refresh_player_list() -> void:
	# ── Clear existing children ───────────────────────────────────────────
	for child in player_list.get_children():
		child.queue_free()

	# ── Rebuild from GameState.players ───────────────────────────────────
	var players_list: Array = GameState.players

	if players_list.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No players yet…"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		player_list.add_child(empty_label)
		return

	for player_data in players_list:
		if not (player_data is Dictionary):
			continue
		var peer_id: int = player_data.get("id", 0)
		var username: String = player_data.get("username", "Unknown")
		var money: int = player_data.get("money", 0)
		var player_col: Color = player_data.get("color", Color.WHITE)

		# Build a display string for this player.
		var suffix: String = " (Host)" if peer_id == 1 else ""
		var entry_text: String = "🎲 %s%s  —  $%d" % [username, suffix, money]

		# Create a Label node dynamically and style it.
		var label := Label.new()
		label.text = entry_text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		# Give host gold tint, others their assigned player colour
		if peer_id == 1:
			label.modulate = Color(1.0, 0.85, 0.2)
		else:
			label.modulate = player_col

		player_list.add_child(label)

	# ── Update start button state ─────────────────────────────────────────
	if NetworkUtility.is_host():
		# Allow 1 or more players so solo testing is possible, but encourage 2+
		start_button.disabled = players_list.is_empty()
		if players_list.size() < 2:
			status_label.text = "1 player in lobby. You can start solo or wait for friends."
		else:
			status_label.text = "Ready! Press Start Game to begin."


# ---------------------------------------------------------------------------
# _on_start_button_pressed
# ---------------------------------------------------------------------------
func _on_start_button_pressed() -> void:
	if not NetworkUtility.is_host():
		push_warning("Lobby: Non-host tried to start the game — ignoring.")
		return

	if GameState.players.is_empty():
		status_label.text = "⚠️ No players in lobby!"
		return

	# Disable button to prevent double-clicks
	start_button.disabled = true
	status_label.text = "Starting game…"

	# Command all peers (and local host via call_local) to transition to Board scene
	NetworkUtility.start_game.rpc()


func _on_leave_button_pressed() -> void:
	NetworkUtility.disconnect_from_game()
	GameState.reset_game()
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")


# ---------------------------------------------------------------------------
# _on_game_starting
# ---------------------------------------------------------------------------
func _on_game_starting() -> void:
	status_label.text = "🚀 Game starting! Loading 3D board…"
