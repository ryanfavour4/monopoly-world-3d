## CasinoModal.gd
## ============================================================
## Scene: scenes/ui/CasinoModal.tscn
## Node type: Control  (root of the modal overlay)
##
## PURPOSE:
##   The CasinoModal is the CENTRAL DRAMA-DRIVER of the game's UI.
##   Every financial event — rent payment, property purchase, tax, GO
##   salary, Chance/Community Chest reveals, and bankruptcy — is
##   communicated to the player through this single, styled popup.
##
##   Why centralise everything here?
##   - One place to tweak styling and animation.
##   - A single source-of-truth for "is a modal currently open?".
##   - Makes it impossible for two modals to fight for screen real estate.
##
## SCENE TREE EXPECTED:
##   CasinoModal (Control)          ← this script
##   └─ Background (ColorRect)      ← full-screen dim overlay (z-ordering)
##      └─ Panel (PanelContainer)   ← white/dark card, centered on screen
##         └─ VBox (VBoxContainer)
##            ├─ TitleLabel (Label)
##            ├─ MessageLabel (Label)
##            ├─ PayButton (Button)
##            └─ CloseButton (Button)
##
## NETWORK:
##   This script is CLIENT-SIDE ONLY. It never calls RPCs directly.
##   The callbacks passed to it (e.g. pay_callback) are responsible
##   for any network communication needed after the player clicks.
## ============================================================
class_name CasinoModal
extends Control


# ---------------------------------------------------------------------------
# Node references — resolved at runtime via $Path shortcuts.
# @onready ensures they are populated after _ready() runs so Godot can find
# them in the scene tree. Using typed references gives us autocompletion and
# safety warnings if the node path is wrong.
# ---------------------------------------------------------------------------

## Full-screen semi-transparent black rectangle that dims everything behind
## the modal, drawing attention to the card. Clicking it can optionally close
## the modal (handled in _ready).
@onready var background: ColorRect = $Background

## Large, bold label at the top of the card (e.g. "🎰 RENT DUE!").
@onready var title_label: Label = $Background/Panel/VBox/TitleLabel

## Secondary label below the title; carries the detailed narrative
## (e.g. "Alice owns Boardwalk! You owe $50!").
@onready var message_label: Label = $Background/Panel/VBox/MessageLabel

## Primary action button — used for payment or purchase confirmation.
## Hidden for info-only modals.
@onready var pay_button: Button = $Background/Panel/VBox/PayButton

## Secondary/dismiss button — always present so players can close the modal.
## Label text is changed per context ("Close", "Pass", etc.).
@onready var close_button: Button = $Background/Panel/VBox/CloseButton


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

## Stores the Callable that was passed in at show-time.
## When the player clicks PayButton, this callable is invoked.
## Storing it here (rather than passing it as a parameter to the button's
## signal) avoids the "lambda capture in signal" pitfall in GDScript 4.
var _callback: Callable


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Start hidden — the modal is not shown until show_casino_modal() is
	# explicitly called by UIManager or a game system.
	hide()

	# Wire up button signals to our private handlers.
	# Using signal connections in code (rather than the editor) keeps the
	# setup self-contained — anyone reading this file can see the full wiring.
	pay_button.pressed.connect(_on_pay_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)

	# Optionally, a click on the dim background also closes the modal.
	# We only do this for "close" (not pay), because an accidental click
	# should never trigger a financial transaction.
	background.gui_input.connect(_on_background_gui_input)


# ---------------------------------------------------------------------------
# Core public API
# ---------------------------------------------------------------------------

## show_casino_modal — THE SINGLE ENTRY POINT for ALL financial/event popups.
##
## Why one entry point? Because every popup in Monopoly follows the same
## structure: title → narrative message → optional action button → dismiss.
## Specialised helpers (show_rent_modal, show_purchase_modal, etc.) simply
## format data and delegate here.
##
## Parameters:
##   title           — Bold header text shown at the top of the card.
##   message         — Body text with narrative detail.
##   callback_action — Callable run when PayButton is pressed. May be a
##                     lambda, a method reference, or Callable() (empty) for
##                     info-only modals.
##   show_pay_button — If false, the pay/action button is hidden so only
##                     the close button remains (used for pure info modals).
func show_casino_modal(
		title: String,
		message: String,
		callback_action: Callable,
		show_pay_button: bool = true
) -> void:
	# Populate text content first, before the animation starts, so there is
	# never a frame where the modal is visible but empty.
	title_label.text   = title
	message_label.text = message

	# Store the callback so _on_pay_button_pressed can access it later.
	_callback = callback_action

	# Show or hide the pay button based on context.
	# The close button is always visible so the modal is never a dead end.
	pay_button.visible = show_pay_button

	# Make the node visible before animating — Tween on a hidden node does
	# nothing (modulate alpha 0 keeps it invisible while the tree is shown).
	show()
	_animate_in()


# ---------------------------------------------------------------------------
# Animation helpers
# ---------------------------------------------------------------------------

## _animate_in — Scale-up + fade-in entrance for the panel card.
##
## Why animate? A pop-in animation signals "something important happened" to
## the player, especially useful in the chaotic middle of a turn transition.
##
## Technique:
##   - The Background (dim overlay) fades from alpha 0 → 0.7.
##   - The Panel card scales from 0.8 → 1.0 (pivot at center).
##   - Duration: 0.3 s feels snappy without being abrupt.
func _animate_in() -> void:
	# Grab the inner Panel node to animate its scale independently.
	# Using a typed cast here so GDScript catches errors if the tree changes.
	var panel: Control = $Background/Panel

	# Reset to pre-animation state so the effect always plays from scratch,
	# even if the modal was previously closed mid-animation.
	background.modulate.a = 0.0
	panel.scale          = Vector2(0.8, 0.8)
	panel.pivot_offset   = panel.size / 2.0  # Scale from center, not top-left.

	# Create a one-shot Tween owned by this node.
	# Using create_tween() binds the tween's lifetime to this node — it is
	# automatically freed when the node is freed.
	var tween: Tween = create_tween()
	tween.set_parallel(true)   # Both tweens run simultaneously.
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)  # Slight overshoot for a "pop" feel.

	# Fade in the dim background.
	tween.tween_property(background, "modulate:a", 0.7, 0.3)

	# Scale the card up.
	tween.tween_property(panel, "scale", Vector2.ONE, 0.3)


## _animate_out — Reverse of _animate_in; optionally hides the node after.
##
## Parameters:
##   then_hide — If true (default), node.hide() is called after the tween
##               completes. Pass false if you want to chain another animation.
func _animate_out(then_hide: bool = true) -> void:
	var panel: Control = $Background/Panel
	panel.pivot_offset = panel.size / 2.0

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)

	# Reverse: fade dim overlay back to transparent.
	tween.tween_property(background, "modulate:a", 0.0, 0.25)

	# Scale card back down.
	tween.tween_property(panel, "scale", Vector2(0.8, 0.8), 0.25)

	if then_hide:
		# Wait for the tween to finish before hiding to avoid a visible pop.
		# tween.finished fires after ALL parallel tracks complete.
		tween.finished.connect(hide, CONNECT_ONE_SHOT)


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

## _on_pay_button_pressed — called when the player clicks Pay / Buy / Confirm.
##
## Flow:
##   1. Execute the stored callback (e.g. deduct rent, purchase property).
##   2. Animate out and hide — the turn continues.
##
## Why call callback BEFORE animating out?
##   The callback may itself open another modal (e.g. "You went bankrupt!").
##   Closing first, then opening, would cause a flicker. Instead we let the
##   new modal's _animate_in overlap with this one's _animate_out.
func _on_pay_button_pressed() -> void:
	# Guard: only call if the callback is actually bound. An unbound Callable
	# would silently do nothing, but logging helps during development.
	if _callback.is_valid():
		_callback.call()
	else:
		push_warning("CasinoModal: pay button pressed but _callback is not valid.")

	_animate_out()


## _on_close_button_pressed — simply dismiss without any financial action.
##
## Used for:
##   - "Pass" on a property purchase.
##   - Acknowledging an info modal (GO salary, jail notice, etc.).
func _on_close_button_pressed() -> void:
	_animate_out()


## _on_background_gui_input — allows clicking the dim overlay to close.
##
## We only want a LEFT click (InputEventMouseButton, button_index == MOUSE_BUTTON_LEFT,
## and pressed == true) to avoid reacting to releases, scrolls, or right-clicks.
func _on_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# Clicking the dim area counts as "dismiss / close", not "pay".
			_on_close_button_pressed()


# ---------------------------------------------------------------------------
# Convenience wrappers — build formatted strings and delegate to show_casino_modal
# ---------------------------------------------------------------------------

## show_rent_modal — Tell the local player they owe rent.
##
## Parameters:
##   owner_username — Display name of the property owner (the peer who gets paid).
##   rent_amount    — Dollar amount due (int, Monopoly uses whole dollars).
##   tile_name      — Human-readable property name (e.g. "Boardwalk").
##   pay_callback   — Callable that transfers money from local player to owner.
##                    Should be a TurnManager method wrapped in a lambda with
##                    the relevant peer IDs captured.
func show_rent_modal(
		owner_username: String,
		rent_amount: int,
		tile_name: String,
		pay_callback: Callable
) -> void:
	var title   := "🎰 RENT DUE!"
	var message := "%s owns %s!\nYou owe $%d!" % [owner_username, tile_name, rent_amount]

	# The pay button label is changed here so the player knows exactly what
	# they are confirming. We change it back in show_casino_modal's reset path
	# if needed — but since we always set it before showing, order doesn't matter.
	pay_button.text = "Pay $%d" % rent_amount
	close_button.text = "Close"  # Closing without paying would be a bug in flow,
	                              # but keeping the button gives an escape during dev.

	show_casino_modal(title, message, pay_callback, true)


## show_purchase_modal — Offer the player a chance to buy an unowned property.
##
## Parameters:
##   tile_name    — The property name.
##   price        — Listed purchase price from TileData.
##   buy_callback — Callable that deducts purchase price and transfers ownership.
##                  Called only if the player clicks "Buy!".
##
## Choosing "Pass" (CloseButton) lets the property go to auction in full
## Monopoly rules — for this implementation, passing simply skips the purchase.
func show_purchase_modal(
		tile_name: String,
		price: int,
		buy_callback: Callable
) -> void:
	var title   := "🏠 PROPERTY AVAILABLE!"
	var message := "%s is for sale!\nPurchase for $%d?" % [tile_name, price]

	pay_button.text   = "Buy!"
	close_button.text = "Pass"

	show_casino_modal(title, message, buy_callback, true)


## show_info_modal — Display a narrative event with no financial action.
##
## Use this for:
##   - Passing GO (collecting $200 salary).
##   - Landing on Free Parking.
##   - Going to Jail notification (after TurnManager.send_to_jail() fires).
##   - Chance / Community Chest results that have already been applied.
##
## Parameters:
##   title   — Bold header (can include emoji for flavour).
##   message — Detailed body text.
func show_info_modal(title: String, message: String) -> void:
	close_button.text = "OK"

	# Passing Callable() (an invalid/empty callable) means the pay button
	# would do nothing, so we hide it entirely for clarity.
	show_casino_modal(title, message, Callable(), false)


## show_bankruptcy_modal — Announce that a player has run out of money.
##
## This is the most dramatic moment in Monopoly; the modal is styled the same
## but the emoji + language signal finality. After closing, the game removes
## the bankrupt player from the active player list.
##
## Parameters:
##   username — Display name of the bankrupt player (may be remote or local).
func show_bankruptcy_modal(username: String) -> void:
	var title   := "💸 BANKRUPT!"
	var message := "%s has run out of money and is out of the game!\nBetter luck next time..." % username

	close_button.text = "Continue"
	show_casino_modal(title, message, Callable(), false)
