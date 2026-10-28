## BuildingSpawner.gd
## Dynamically instantiates and synchronizes 3D stylized building models
## (houses, hotels, skyscrapers, and ownership flags) directly on board tiles.

extends Node3D

# Cache of spawned building nodes keyed by tile_index (int) -> Node3D
var _spawned_buildings: Dictionary = {}

# Materials cache
var _mat_house_body: StandardMaterial3D
var _mat_house_roof: StandardMaterial3D
var _mat_hotel_body: StandardMaterial3D
var _mat_hotel_roof: StandardMaterial3D
var _mat_chimney: StandardMaterial3D


func _ready() -> void:
	_init_materials()
	# Call initial sync after board is constructed
	call_deferred("sync_buildings")


func _init_materials() -> void:
	# House stucco wall (warm ivory)
	_mat_house_body = StandardMaterial3D.new()
	_mat_house_body.albedo_color = Color(0.92, 0.90, 0.82)
	_mat_house_body.roughness = 0.85

	# House pitched roof (terracotta orange-red)
	_mat_house_roof = StandardMaterial3D.new()
	_mat_house_roof.albedo_color = Color(0.85, 0.28, 0.16)
	_mat_house_roof.roughness = 0.6

	# Hotel / Skyscraper body (glazed modern blue glass)
	_mat_hotel_body = StandardMaterial3D.new()
	_mat_hotel_body.albedo_color = Color(0.12, 0.35, 0.65)
	_mat_hotel_body.metallic = 0.5
	_mat_hotel_body.roughness = 0.2
	_mat_hotel_body.emission_enabled = true
	_mat_hotel_body.emission = Color(0.08, 0.22, 0.38)
	_mat_hotel_body.emission_energy_multiplier = 0.8

	# Hotel roof & spire
	_mat_hotel_roof = StandardMaterial3D.new()
	_mat_hotel_roof.albedo_color = Color(0.95, 0.75, 0.15)
	_mat_hotel_roof.metallic = 0.7
	_mat_hotel_roof.roughness = 0.3

	# Chimney / metal
	_mat_chimney = StandardMaterial3D.new()
	_mat_chimney.albedo_color = Color(0.3, 0.3, 0.35)


## sync_buildings
## Reads authoritative BoardManager state and updates all 3D building visuals on the board
func sync_buildings() -> void:
	var bm = get_node_or_null("/root/BoardManager")
	if not bm or bm.tiles.is_empty():
		return

	for i in range(bm.tiles.size()):
		var tile: BoardTileData = bm.tiles[i]
		if tile.tile_type in ["property", "railroad", "utility"]:
			_update_tile_visual(tile)


func _update_tile_visual(tile: BoardTileData) -> void:
	var tile_idx: int = tile.tile_index
	var owner_id: int = tile.owner_id
	var house_count: int = tile.house_count

	# If currently unowned, clear existing visuals if any
	if owner_id <= 0:
		if _spawned_buildings.has(tile_idx):
			var old_node = _spawned_buildings[tile_idx]
			if is_instance_valid(old_node):
				old_node.queue_free()
			_spawned_buildings.erase(tile_idx)
		return

	# Retrieve world position for this tile
	var bm = get_node_or_null("/root/BoardManager")
	if not bm or tile_idx >= bm.tile_world_positions.size():
		return

	var tile_center: Vector3 = bm.tile_world_positions[tile_idx]
	# Offset inward toward board center so buildings don't occlude pawn movement line
	var to_center: Vector3 = (Vector3(0, 0, 0) - tile_center).normalized()
	var building_spot: Vector3 = tile_center + to_center * 0.45 + Vector3(0, 0.1, 0)

	# Fetch owner color
	var owner_color: Color = Color(0.2, 0.6, 1.0)
	var p_data: Dictionary = GameState.get_player(owner_id)
	if not p_data.is_empty() and p_data.has("color"):
		owner_color = p_data["color"]

	# Check if existing node needs replacement
	if _spawned_buildings.has(tile_idx):
		var old = _spawned_buildings[tile_idx]
		if is_instance_valid(old):
			old.queue_free()
		_spawned_buildings.erase(tile_idx)

	# Create new root for this tile's buildings
	var root := Node3D.new()
	root.name = "Building_Tile%d" % tile_idx
	root.position = building_spot
	add_child(root)
	_spawned_buildings[tile_idx] = root

	# Spawn appropriate 3D model
	if house_count >= 5:
		# Hotel / Skyscraper
		_create_hotel_model(root)
	elif house_count > 0:
		# 1 to 4 Houses
		_create_houses_cluster(root, house_count)
	else:
		# Level 0 (Land purchased) -> Flagpole with player color
		_create_ownership_flag(root, owner_color)

	# Animated scale pop-in
	root.scale = Vector3.ZERO
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(root, "scale", Vector3.ONE, 0.45)


func _create_houses_cluster(parent: Node3D, count: int) -> void:
	var offsets: Array[Vector3] = [
		Vector3(-0.16, 0.0, 0.0),
		Vector3(0.16, 0.0, 0.0),
		Vector3(-0.16, 0.0, 0.18),
		Vector3(0.16, 0.0, 0.18)
	]

	if count == 1:
		offsets = [Vector3.ZERO]
	elif count == 2:
		offsets = [Vector3(-0.14, 0.0, 0.0), Vector3(0.14, 0.0, 0.0)]
	elif count == 3:
		offsets = [Vector3(-0.18, 0.0, 0.0), Vector3(0.0, 0.0, 0.12), Vector3(0.18, 0.0, 0.0)]

	for i in range(min(count, offsets.size())):
		var house := _build_single_house()
		house.position = offsets[i]
		parent.add_child(house)


func _build_single_house() -> Node3D:
	var house := Node3D.new()

	# Body
	var body := MeshInstance3D.new()
	var b_mesh := BoxMesh.new()
	b_mesh.size = Vector3(0.24, 0.18, 0.24)
	body.mesh = b_mesh
	body.position.y = 0.09
	body.material_override = _mat_house_body
	house.add_child(body)

	# Pitch Roof
	var roof := MeshInstance3D.new()
	var r_mesh := PrismMesh.new()
	r_mesh.size = Vector3(0.26, 0.12, 0.26)
	roof.mesh = r_mesh
	roof.position.y = 0.23
	roof.material_override = _mat_house_roof
	house.add_child(roof)

	# Chimney
	var chim := MeshInstance3D.new()
	var c_mesh := BoxMesh.new()
	c_mesh.size = Vector3(0.05, 0.12, 0.05)
	chim.mesh = c_mesh
	chim.position = Vector3(0.07, 0.24, 0.05)
	chim.material_override = _mat_chimney
	house.add_child(chim)

	return house


func _create_hotel_model(parent: Node3D) -> void:
	# Main Skyscraper / Hotel Tower
	var tower := MeshInstance3D.new()
	var t_mesh := BoxMesh.new()
	t_mesh.size = Vector3(0.38, 0.72, 0.38)
	tower.mesh = t_mesh
	tower.position.y = 0.36
	tower.material_override = _mat_hotel_body
	parent.add_child(tower)

	# Roof structure & penthouse
	var roof := MeshInstance3D.new()
	var r_mesh := BoxMesh.new()
	r_mesh.size = Vector3(0.28, 0.12, 0.28)
	roof.mesh = r_mesh
	roof.position.y = 0.78
	roof.material_override = _mat_hotel_roof
	parent.add_child(roof)

	# Spire antenna
	var spire := MeshInstance3D.new()
	var s_mesh := CylinderMesh.new()
	s_mesh.top_radius = 0.01
	s_mesh.bottom_radius = 0.02
	s_mesh.height = 0.22
	spire.mesh = s_mesh
	spire.position.y = 0.94
	spire.material_override = _mat_hotel_roof
	parent.add_child(spire)


func _create_ownership_flag(parent: Node3D, flag_color: Color) -> void:
	# Pole
	var pole := MeshInstance3D.new()
	var p_mesh := CylinderMesh.new()
	p_mesh.top_radius = 0.015
	p_mesh.bottom_radius = 0.02
	p_mesh.height = 0.42
	pole.mesh = p_mesh
	pole.position.y = 0.21
	pole.material_override = _mat_chimney
	parent.add_child(pole)

	# Flag banner
	var flag := MeshInstance3D.new()
	var f_mesh := BoxMesh.new()
	f_mesh.size = Vector3(0.22, 0.14, 0.02)
	flag.mesh = f_mesh
	flag.position = Vector3(0.12, 0.34, 0.0)

	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = flag_color
	flag_mat.emission_enabled = true
	flag_mat.emission = flag_color
	flag_mat.emission_energy_multiplier = 0.3
	flag.material_override = flag_mat
	parent.add_child(flag)
