###############################################################################
# MainMenu.gd
# Attached to: scenes/main_menu/MainMenu.tscn  →  root node "MainMenu" (Control)
#
# PURPOSE:
#   Drives the main menu UI. Lets players enter a username, host a new game,
#   or join an existing game by IP address. Delegates all networking to the
#   NetworkUtility autoload singleton.
#
# EXPECTED NODE TREE (create this structure in the Godot editor):
#
#   MainMenu  (Control)  ← this script goes here
#   ├── Background  (TextureRect or ColorRect)
#   │       Fills the viewport; set a background texture or solid color.
#   ├── Title  (Label)
#   │       Text = "MONOPOLY WORLD 3D"
#   │       Style with a large, bold font in the inspector.
#   └── VBox  (VBoxContainer)
#           Centered on screen; contains all interactive widgets.
#       ├── UsernameField  (LineEdit)
#       │       PlaceholderText = "Enter your name"
#       │       MaxLength = 20 (recommended)
#       ├── HostButton  (Button)
#       │       Text = "Host Game"
#       ├── JoinButton  (Button)
#       │       Text = "Join Game"
#       ├── IPAddressField  (LineEdit)
#       │       PlaceholderText = "Enter IP Address"
#       │       Text = "127.0.0.1" (default for local testing)
#       └── StatusLabel  (Label)
#               Text = ""  (updated at runtime with feedback messages)
#
# DEPENDENCIES (autoloads / singletons – must be registered in Project Settings):
#   • NetworkUtility  — handles ENet peer creation, RPC signals
#   • GameState       — global game data (players, money, etc.)
#
# SIGNALS CONSUMED FROM NetworkUtility:
#   • connection_succeeded()  — emitted on the client when the server accepts it
#   • connection_failed()     — emitted on the client when connection times out
#   • lobby_updated()         — emitted when the player list changes (not used
#                               here directly, but connected for future use)
###############################################################################

extends Control

# ---------------------------------------------------------------------------
# Node references — resolved at runtime via @onready.
# These paths MUST match the node names in the .tscn file exactly.
# ---------------------------------------------------------------------------

## The text field where the player types their display name.
@onready var username_field: LineEdit = find_child("UsernameField", true, false)

## Button that creates a new hosted (server) game session.
@onready var host_button: Button = find_child("HostButton", true, false)

## Button that plays solo offline.
@onready var solo_button: Button = find_child("SoloButton", true, false)

## Button that attempts to connect to a remote host as a client.
@onready var join_button: Button = find_child("JoinButton", true, false)

## Text field for the host's IP address (used when joining a game).
@onready var ip_field: LineEdit = find_child("IPAddressField", true, false)

## Feedback label shown beneath the buttons (errors, status messages, etc.).
@onready var status_label: Label = find_child("StatusLabel", true, false)


# ---------------------------------------------------------------------------
# _ready — called once when the node enters the scene tree.
# Hooks up button click signals and NetworkUtility event signals.
# ---------------------------------------------------------------------------
func _ready() -> void:
	# ── Button signal connections ──────────────────────────────────────────
	if not host_button.pressed.is_connected(_on_host_button_pressed):
		host_button.pressed.connect(_on_host_button_pressed)
	if solo_button and not solo_button.pressed.is_connected(_on_solo_button_pressed):
		solo_button.pressed.connect(_on_solo_button_pressed)
	if not join_button.pressed.is_connected(_on_join_button_pressed):
		join_button.pressed.connect(_on_join_button_pressed)

	# ── NetworkUtility signal connections ──────────────────────────────────
	if not NetworkUtility.connection_succeeded.is_connected(_on_connection_succeeded):
		NetworkUtility.connection_succeeded.connect(_on_connection_succeeded)

	if not NetworkUtility.connection_failed.is_connected(_on_connection_failed):
		NetworkUtility.connection_failed.connect(_on_connection_failed)

	if not NetworkUtility.lobby_updated.is_connected(_on_lobby_updated):
		NetworkUtility.lobby_updated.connect(_on_lobby_updated)

	status_label.text = ""

	if ip_field.text.is_empty():
		ip_field.text = "127.0.0.1"


# ---------------------------------------------------------------------------
# _on_host_button_pressed
# ---------------------------------------------------------------------------
func _on_host_button_pressed() -> void:
	var username: String = username_field.text.strip_edges()
	if username.is_empty():
		username = "Host"
		username_field.text = username

	var success: bool = NetworkUtility.host_game(username)
	if not success:
		_show_status("❌ Failed to bind server on port 7777 (already in use?).", Color.RED)
		host_button.disabled = false
		join_button.disabled = false
		return

	# Retrieve local IP
	var addresses: Array = IP.get_local_addresses()
	var lan_ip: String = "127.0.0.1"
	for addr in addresses:
		if (addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172.")) and not ":" in addr:
			lan_ip = addr
			break

	_show_status("🎲 Server running on port 7777 (LAN IP: %s)\nWaiting for peer to join (auto-starts on connect)..." % lan_ip, Color.GREEN)
	host_button.disabled = true
	join_button.disabled = true
	if solo_button:
		solo_button.text = "▶️ Start Now (Solo)"


func _on_solo_button_pressed() -> void:
	var username: String = username_field.text.strip_edges()
	if username.is_empty():
		username = "Player"
	NetworkUtility.start_solo_game(username)


# ---------------------------------------------------------------------------
# _on_join_button_pressed
# ---------------------------------------------------------------------------
func _on_join_button_pressed() -> void:
	var username: String = username_field.text.strip_edges()
	if username.is_empty():
		username = "Guest"
		username_field.text = username

	var ip: String = ip_field.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
		ip_field.text = ip

	var success: bool = NetworkUtility.join_game(ip, username)
	if not success:
		_show_status("❌ Could not initiate connection to %s." % ip, Color.RED)
		return

	_show_status("🔄 Connecting to %s:7777 …" % ip, Color.CYAN)
	host_button.disabled = true
	join_button.disabled = true
	if solo_button:
		solo_button.disabled = true
	ip_field.editable = false
	username_field.editable = false


func _on_connection_succeeded() -> void:
	_show_status("✅ Connected! Loading 3D Board scene…", Color.GREEN)


# ---------------------------------------------------------------------------
# _on_connection_failed
# Slot connected to NetworkUtility.connection_failed.
# Called on the CLIENT when the connection attempt times out or is refused.
#
# Re-enables the UI so the player can try a different IP or username.
# ---------------------------------------------------------------------------
func _on_connection_failed() -> void:
	_show_status("❌ Connection failed or timed out. Check IP and port 7777.", Color.RED)

	# Re-enable all interactive elements so the player can retry.
	host_button.disabled = false
	join_button.disabled = false
	ip_field.editable = true
	username_field.editable = true


# ---------------------------------------------------------------------------
# _on_lobby_updated
# Slot connected to NetworkUtility.lobby_updated.
# Not heavily used on the main menu, but keeping the connection alive avoids
# duplicate-connection errors if the user navigates back from the lobby.
# ---------------------------------------------------------------------------
func _on_lobby_updated() -> void:
	# Nothing to display on the main menu when the lobby list changes.
	# The Lobby scene handles its own refresh.
	pass


# ---------------------------------------------------------------------------
# _show_status  (private helper)
# Updates the status label with a message and optional colour tint.
#
# Parameters:
#   message : String — the text to display
#   colour  : Color  — modulate colour for the label (default white)
# ---------------------------------------------------------------------------
func _show_status(message: String, colour: Color = Color.WHITE) -> void:
	status_label.text = message
	status_label.modulate = colour
