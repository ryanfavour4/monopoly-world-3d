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
	if not join_button.pressed.is_connected(_on_join_button_pressed):
		join_button.pressed.connect(_on_join_button_pressed)

	# ── NetworkUtility signal connections ──────────────────────────────────
	# connection_succeeded: fired on this client when the host accepts us.
	if not NetworkUtility.connection_succeeded.is_connected(_on_connection_succeeded):
		NetworkUtility.connection_succeeded.connect(_on_connection_succeeded)

	# connection_failed: fired on this client when the connection times out
	# or is refused.
	if not NetworkUtility.connection_failed.is_connected(_on_connection_failed):
		NetworkUtility.connection_failed.connect(_on_connection_failed)

	# lobby_updated: fired whenever the player list changes. Connected here
	# so signals don't stack if the user returns to the main menu.
	if not NetworkUtility.lobby_updated.is_connected(_on_lobby_updated):
		NetworkUtility.lobby_updated.connect(_on_lobby_updated)

	# Clear any leftover status text from a previous session.
	status_label.text = ""

	# Pre-fill the IP field with localhost for convenience during development.
	if ip_field.text.is_empty():
		ip_field.text = "127.0.0.1"


# ---------------------------------------------------------------------------
# _on_host_button_pressed
# Called when the player clicks "Host Game".
#
# Behaviour:
#   1. Validates that the player has entered a non-empty username.
#   2. Instructs NetworkUtility to open a server socket.
#   3. Updates the status label so the host knows they are waiting.
#   4. Navigates immediately to the Lobby scene (host does not need to wait
#      for a connection_succeeded signal — they ARE the server).
# ---------------------------------------------------------------------------
func _on_host_button_pressed() -> void:
	# ── Validation ─────────────────────────────────────────────────────────
	var username: String = username_field.text.strip_edges()
	if username.is_empty():
		_show_status("⚠️ Please enter a username before hosting.", Color.YELLOW)
		return

	# ── Start the server via NetworkUtility ────────────────────────────────
	var success: bool = NetworkUtility.host_game(username)
	if not success:
		_show_status("❌ Failed to bind server on port 7777 (already in use?).", Color.RED)
		host_button.disabled = false
		join_button.disabled = false
		return

	# ── UI feedback ────────────────────────────────────────────────────────
	_show_status("🎲 Hosting… Waiting for players.", Color.GREEN)
	host_button.disabled = true
	join_button.disabled = true

	# ── Navigate to the Lobby ──────────────────────────────────────────────
	get_tree().change_scene_to_file("res://scenes/lobby/Lobby.tscn")


# ---------------------------------------------------------------------------
# _on_join_button_pressed
# ---------------------------------------------------------------------------
func _on_join_button_pressed() -> void:
	# ── Validation ─────────────────────────────────────────────────────────
	var username: String = username_field.text.strip_edges()
	if username.is_empty():
		_show_status("⚠️ Please enter a username before joining.", Color.YELLOW)
		return

	var ip: String = ip_field.text.strip_edges()
	if ip.is_empty():
		_show_status("⚠️ Please enter the host IP address.", Color.YELLOW)
		return

	# ── Attempt connection via NetworkUtility ──────────────────────────────
	var success: bool = NetworkUtility.join_game(ip, username)
	if not success:
		_show_status("❌ Could not initiate connection to %s." % ip, Color.RED)
		return

	# ── UI feedback ────────────────────────────────────────────────────────
	_show_status("🔄 Connecting to %s…" % ip, Color.CYAN)
	host_button.disabled = true
	join_button.disabled = true
	ip_field.editable = false
	username_field.editable = false


# ---------------------------------------------------------------------------
# _on_connection_succeeded
# Slot connected to NetworkUtility.connection_succeeded.
# Called on the CLIENT only — the host never fires this signal.
#
# Navigates to the Lobby scene now that the connection is confirmed.
# ---------------------------------------------------------------------------
func _on_connection_succeeded() -> void:
	_show_status("✅ Connected! Entering lobby…", Color.GREEN)
	# Brief visual confirmation before switching scenes.
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://scenes/lobby/Lobby.tscn")


# ---------------------------------------------------------------------------
# _on_connection_failed
# Slot connected to NetworkUtility.connection_failed.
# Called on the CLIENT when the connection attempt times out or is refused.
#
# Re-enables the UI so the player can try a different IP or username.
# ---------------------------------------------------------------------------
func _on_connection_failed() -> void:
	_show_status("❌ Connection failed. Check IP and try again.", Color.RED)

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
