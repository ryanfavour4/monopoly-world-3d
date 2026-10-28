extends Node

func _ready() -> void:
	print("========================================")
	print("       MONOPOLY 3D MULTIPLAYER TEST     ")
	print("========================================")

	test_gamestate()
	test_board_manager()
	test_board_and_pawns()
	test_turn_and_gameplay_flow()

	print("========================================")
	print("   ALL TESTS PASSED SUCCESSFULLY! (0)   ")
	print("========================================")
	get_tree().quit(0)


func test_gamestate() -> void:
	print("[TEST] 1. GameState verification...")
	GameState.reset_game()
	assert(GameState.players.is_empty(), "GameState players should start empty")

	# Verify AudioManager methods
	assert(AudioManager.has_method("play_ding"), "AudioManager must have play_ding")
	assert(AudioManager.has_method("play_dice_roll"), "AudioManager must have play_dice_roll")
	AudioManager.play_dice_roll()
	AudioManager.play_ding()

	# Register Host and Client
	GameState.add_player(1, "Alice (Host)")
	GameState.add_player(2, "Bob (Client)")

	assert(GameState.players.size() == 2, "Should have 2 players")
	var p1: Dictionary = GameState.get_player(1)
	var p2: Dictionary = GameState.get_player(2)
	assert(p1["username"] == "Alice (Host)", "Host name match")
	assert(p2["username"] == "Bob (Client)", "Client name match")
	assert(p1["money"] == 1500, "Starting money should be 1500")
	assert(p2["money"] == 1500, "Starting money should be 1500")
	assert(p1["color"] != p2["color"], "Players must have distinct colors")
	print("  -> GameState passed.")


func test_board_manager() -> void:
	print("[TEST] 2. BoardManager verification...")
	assert(BoardManager.tiles.size() == 40, "Board must have 40 tiles")
	assert(BoardManager.tile_world_positions.size() == 40, "Board must have 40 world positions")

	# Tile 0: GO
	var go_tile = BoardManager.get_tile(0)
	assert(go_tile.tile_name == "GO", "Tile 0 must be GO")

	# Tile 39: Boardwalk
	var bw_tile = BoardManager.get_tile(39)
	assert(bw_tile.tile_name == "Boardwalk", "Tile 39 must be Boardwalk")
	assert(bw_tile.purchase_price == 400, "Boardwalk price must be 400")
	assert(bw_tile.base_rent == 50, "Boardwalk base rent must be 50")

	# Property ownership serialization test
	BoardManager.set_tile_owner(39, 1)
	var owners = BoardManager.get_all_owners()
	assert(owners.has(39) and owners[39] == 1, "Tile 39 owned by peer 1")

	# Reset and restore
	BoardManager.set_all_owners({})
	assert(BoardManager.get_tile_owner(39) == 0, "Tile 39 unowned after reset")
	BoardManager.set_all_owners(owners)
	assert(BoardManager.get_tile_owner(39) == 1, "Tile 39 restored to peer 1")
	print("  -> BoardManager passed.")


func test_board_and_pawns() -> void:
	print("[TEST] 3. Board & Player Pawn spawning verification...")
	var board_scene: PackedScene = load("res://scenes/board/Board.tscn")
	assert(board_scene != null, "Board.tscn must be loadable")

	var board_instance = board_scene.instantiate()
	add_child(board_instance)

	var pawns_container = board_instance.get_node("Pawns")
	assert(pawns_container != null, "Pawns container must exist")
	assert(pawns_container.get_child_count() == 2, "Should spawn 2 pawns for 2 players")

	var p1_pawn = board_instance.pawns.get(1)
	var p2_pawn = board_instance.pawns.get(2)
	assert(p1_pawn != null, "Pawn for peer 1 must exist")
	assert(p2_pawn != null, "Pawn for peer 2 must exist")
	assert(p1_pawn.name_label.text == "Alice (Host)", "Pawn 1 label check")
	assert(p2_pawn.name_label.text == "Bob (Client)", "Pawn 2 label check")
	print("  -> Board and pawns passed.")


func test_turn_and_gameplay_flow() -> void:
	print("[TEST] 4. TurnManager & gameplay flow verification...")
	var peer_ids: Array[int] = [1, 2]
	TurnManager.setup_turn_order(peer_ids)
	assert(TurnManager.turn_order.size() == 2, "Turn order size 2")

	# Start turn for player 1
	TurnManager.begin_turn(1)
	assert(TurnManager.current_player_id == 1, "Current player should be 1")

	# Simulate rolling dice (e.g. 3 and 4 -> 7)
	TurnManager.on_dice_rolled(3, 4)
	assert(GameState.get_player_position(1) == 7, "Player 1 should be at tile 7")

	# Simulate purchasing property at tile 39 (Boardwalk, $400)
	var p1_pre_cash = GameState.get_player(1)["money"]
	TurnManager.purchase_property(1, 39)
	var p1_post_cash = GameState.get_player(1)["money"]
	assert(p1_post_cash == p1_pre_cash - 400, "Player 1 money deducted by 400")
	assert(BoardManager.get_tile_owner(39) == 1, "Boardwalk owned by player 1")

	# Simulate player 2 landing on Boardwalk and paying rent ($50)
	var p2_pre_cash = GameState.get_player(2)["money"]
	TurnManager.pay_rent(2, 1, 50)
	var p2_post_cash = GameState.get_player(2)["money"]
	var p1_rent_cash = GameState.get_player(1)["money"]
	assert(p2_post_cash == p2_pre_cash - 50, "Player 2 lost $50 rent")
	assert(p1_rent_cash == p1_post_cash + 50, "Player 1 received $50 rent")

	# Simulate passing GO bonus
	var old_money = GameState.get_player(1)["money"]
	TurnManager._move_player(1, 35) # from 7 + 35 = 42 -> space 2 (passed GO)
	assert(GameState.get_player_position(1) == 2, "Wrapped to space 2")
	assert(GameState.get_player(1)["money"] == old_money + 200, "Collected $200 GO bonus")

	# End turn
	TurnManager.end_turn()
	print("  -> Gameplay flow passed.")
