## BoardWorld.gd
## Procedurally constructs the rich 3D city environment:
##   • Outer perimeter roadway loop with lane markings
##   • Central park with fountain, pathways, and stylized trees
##   • Downtown financial district with glazed commercial skyscrapers
##   • Coastal beach resort strip with palm trees & ocean water
##   • Thematic corner landmarks (GO Triumphal Arch, Prison Yard, Free Parking Lot, Police Station)

extends Node3D

func _ready() -> void:
	_build_roads()
	_build_central_park()
	_build_downtown_skyline()
	_build_beach_resort()
	_build_corner_landmarks()


# ---------------------------------------------------------------------------
# 1. PERIMETER ROADWAY LOOP
# ---------------------------------------------------------------------------
func _build_roads() -> void:
	var road_parent := Node3D.new()
	road_parent.name = "RoadwaySystem"
	add_child(road_parent)

	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.13, 0.14, 0.16)
	road_mat.roughness = 0.85

	var curb_mat := StandardMaterial3D.new()
	curb_mat.albedo_color = Color(0.8, 0.8, 0.85)
	curb_mat.roughness = 0.6

	# 4 road segments forming the outer perimeter loop (10 tiles per side)
	var sides = [
		{"pos": Vector3(0, 0.03, 4.5), "size": Vector3(10.2, 0.04, 1.2)},
		{"pos": Vector3(4.5, 0.03, 0), "size": Vector3(1.2, 0.04, 10.2)},
		{"pos": Vector3(0, 0.03, -4.5), "size": Vector3(10.2, 0.04, 1.2)},
		{"pos": Vector3(-4.5, 0.03, 0), "size": Vector3(1.2, 0.04, 10.2)}
	]

	for s in sides:
		var road := MeshInstance3D.new()
		var b_mesh := BoxMesh.new()
		b_mesh.size = s["size"]
		road.mesh = b_mesh
		road.position = s["pos"]
		road.material_override = road_mat
		road_parent.add_child(road)


# ---------------------------------------------------------------------------
# 2. CENTRAL PARK & FOUNTAIN
# ---------------------------------------------------------------------------
func _build_central_park() -> void:
	var park := Node3D.new()
	park.name = "CentralPark"
	add_child(park)

	# Lush park grass lawn
	var grass := MeshInstance3D.new()
	var g_mesh := BoxMesh.new()
	g_mesh.size = Vector3(6.4, 0.06, 6.4)
	grass.mesh = g_mesh
	grass.position = Vector3(0, 0.03, 0)

	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.18, 0.62, 0.28)
	grass_mat.roughness = 0.9
	grass.material_override = grass_mat
	park.add_child(grass)

	# Cross park walkways (cobblestone)
	var path_mat := StandardMaterial3D.new()
	path_mat.albedo_color = Color(0.72, 0.68, 0.60)
	path_mat.roughness = 0.8

	var path1 := MeshInstance3D.new()
	var p1_mesh := BoxMesh.new()
	p1_mesh.size = Vector3(6.4, 0.07, 0.8)
	path1.mesh = p1_mesh
	path1.position = Vector3(0, 0.035, 0)
	path1.material_override = path_mat
	park.add_child(path1)

	var path2 := MeshInstance3D.new()
	var p2_mesh := BoxMesh.new()
	p2_mesh.size = Vector3(0.8, 0.07, 6.4)
	path2.mesh = p2_mesh
	path2.position = Vector3(0, 0.035, 0)
	path2.material_override = path_mat
	park.add_child(path2)

	# Central Fountain Plaza
	var fountain_basin := MeshInstance3D.new()
	var f_mesh := CylinderMesh.new()
	f_mesh.top_radius = 0.75
	f_mesh.bottom_radius = 0.8
	f_mesh.height = 0.25
	fountain_basin.mesh = f_mesh
	fountain_basin.position = Vector3(0, 0.15, 0)

	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.85, 0.85, 0.88)
	stone_mat.roughness = 0.5
	fountain_basin.material_override = stone_mat
	park.add_child(fountain_basin)

	# Water disk
	var water := MeshInstance3D.new()
	var w_mesh := CylinderMesh.new()
	w_mesh.top_radius = 0.68
	w_mesh.bottom_radius = 0.68
	w_mesh.height = 0.06
	water.mesh = w_mesh
	water.position = Vector3(0, 0.24, 0)

	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.1, 0.55, 0.85, 0.85)
	water_mat.roughness = 0.1
	water_mat.metallic = 0.4
	water.material_override = water_mat
	park.add_child(water)

	# Water Jet
	var spout := MeshInstance3D.new()
	var sp_mesh := CylinderMesh.new()
	sp_mesh.top_radius = 0.04
	sp_mesh.bottom_radius = 0.08
	sp_mesh.height = 0.45
	spout.mesh = sp_mesh
	spout.position = Vector3(0, 0.45, 0)
	spout.material_override = water_mat
	park.add_child(spout)

	# Park Trees
	var tree_spots = [
		Vector3(-1.8, 0, -1.8),
		Vector3(1.8, 0, -1.8),
		Vector3(-1.8, 0, 1.8),
		Vector3(1.8, 0, 1.8),
		Vector3(-2.2, 0, 0.0),
		Vector3(2.2, 0, 0.0)
	]

	for spot in tree_spots:
		_spawn_park_tree(park, spot)


func _spawn_park_tree(parent: Node3D, pos: Vector3) -> void:
	var tree := Node3D.new()
	tree.position = pos + Vector3(0, 0.06, 0)

	# Trunk
	var trunk := MeshInstance3D.new()
	var t_mesh := CylinderMesh.new()
	t_mesh.top_radius = 0.05
	t_mesh.bottom_radius = 0.07
	t_mesh.height = 0.35
	trunk.mesh = t_mesh
	trunk.position.y = 0.175

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.42, 0.28, 0.15)
	trunk_mat.roughness = 0.9
	trunk.material_override = trunk_mat
	tree.add_child(trunk)

	# Foliage Sphere / Cone
	var foliage := MeshInstance3D.new()
	var f_mesh := SphereMesh.new()
	f_mesh.radius = 0.28
	f_mesh.height = 0.45
	foliage.mesh = f_mesh
	foliage.position.y = 0.48

	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = Color(0.15, 0.65, 0.25)
	foliage_mat.roughness = 0.75
	foliage.material_override = foliage_mat
	tree.add_child(foliage)

	parent.add_child(tree)


# ---------------------------------------------------------------------------
# 3. DOWNTOWN FINANCIAL DISTRICT SKYSCRAPERS
# ---------------------------------------------------------------------------
func _build_downtown_skyline() -> void:
	var skyline := Node3D.new()
	skyline.name = "DowntownSkyline"
	add_child(skyline)

	var towers = [
		{"pos": Vector3(-1.2, 0, -2.4), "size": Vector3(0.65, 2.2, 0.65), "col": Color(0.12, 0.28, 0.55)},
		{"pos": Vector3(-0.4, 0, -2.5), "size": Vector3(0.75, 2.8, 0.75), "col": Color(0.10, 0.35, 0.65)},
		{"pos": Vector3(0.5, 0, -2.4),  "size": Vector3(0.60, 1.8, 0.60), "col": Color(0.15, 0.45, 0.70)},
		{"pos": Vector3(1.3, 0, -2.4),  "size": Vector3(0.55, 1.4, 0.55), "col": Color(0.20, 0.30, 0.45)}
	]

	for t in towers:
		var tower := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = t["size"]
		tower.mesh = mesh
		tower.position = t["pos"] + Vector3(0, t["size"].y * 0.5 + 0.05, 0)

		var mat := StandardMaterial3D.new()
		mat.albedo_color = t["col"]
		mat.metallic = 0.6
		mat.roughness = 0.2
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.25, 0.4)
		mat.emission_energy_multiplier = 0.5
		tower.material_override = mat
		skyline.add_child(tower)


# ---------------------------------------------------------------------------
# 4. COASTAL BEACH RESORT (BOARDWALK SIDE)
# ---------------------------------------------------------------------------
func _build_beach_resort() -> void:
	var beach := Node3D.new()
	beach.name = "BeachResortDistrict"
	add_child(beach)

	# Sandy beach strip along side 4 (near Boardwalk / Park Place, +Z side)
	var sand := MeshInstance3D.new()
	var s_mesh := BoxMesh.new()
	s_mesh.size = Vector3(4.0, 0.05, 1.2)
	sand.mesh = s_mesh
	sand.position = Vector3(0.5, 0.04, 2.8)

	var sand_mat := StandardMaterial3D.new()
	sand_mat.albedo_color = Color(0.92, 0.85, 0.65)
	sand_mat.roughness = 0.95
	sand.material_override = sand_mat
	beach.add_child(sand)

	# Ocean Water strip
	var ocean := MeshInstance3D.new()
	var o_mesh := BoxMesh.new()
	o_mesh.size = Vector3(4.0, 0.04, 0.8)
	ocean.mesh = o_mesh
	ocean.position = Vector3(0.5, 0.035, 3.6)

	var ocean_mat := StandardMaterial3D.new()
	ocean_mat.albedo_color = Color(0.08, 0.55, 0.75, 0.9)
	ocean_mat.metallic = 0.5
	ocean_mat.roughness = 0.15
	ocean.material_override = ocean_mat
	beach.add_child(ocean)


# ---------------------------------------------------------------------------
# 5. THEMATIC CORNER LANDMARKS
# ---------------------------------------------------------------------------
func _build_corner_landmarks() -> void:
	var corners := Node3D.new()
	corners.name = "CornerLandmarks"
	add_child(corners)

	# ── Tile 0 (GO Plaza): Golden Triumphal Arch ─────────────────────────
	var arch := Node3D.new()
	arch.name = "GoArch"
	arch.position = Vector3(-4.5, 0.05, 4.5)

	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color(0.95, 0.80, 0.20)
	gold_mat.metallic = 0.8
	gold_mat.roughness = 0.25

	# Left pillar
	var p_left := MeshInstance3D.new()
	var p_mesh := BoxMesh.new()
	p_mesh.size = Vector3(0.18, 0.8, 0.18)
	p_left.mesh = p_mesh
	p_left.position = Vector3(-0.35, 0.4, 0)
	p_left.material_override = gold_mat
	arch.add_child(p_left)

	# Right pillar
	var p_right := MeshInstance3D.new()
	p_right.mesh = p_mesh
	p_right.position = Vector3(0.35, 0.4, 0)
	p_right.material_override = gold_mat
	arch.add_child(p_right)

	# Crossbeam
	var beam := MeshInstance3D.new()
	var b_mesh := BoxMesh.new()
	b_mesh.size = Vector3(0.95, 0.18, 0.24)
	beam.mesh = b_mesh
	beam.position = Vector3(0, 0.85, 0)
	beam.material_override = gold_mat
	arch.add_child(beam)

	corners.add_child(arch)

	# ── Tile 10 (Jail Yard): Concrete & Watchtower ────────────────────────
	var jail := Node3D.new()
	jail.name = "JailWatchtower"
	jail.position = Vector3(4.5, 0.05, 4.5)

	var tower_mat := StandardMaterial3D.new()
	tower_mat.albedo_color = Color(0.45, 0.47, 0.50)
	tower_mat.roughness = 0.85

	var tower := MeshInstance3D.new()
	var tw_mesh := CylinderMesh.new()
	tw_mesh.top_radius = 0.22
	tw_mesh.bottom_radius = 0.28
	tw_mesh.height = 0.95
	tower.mesh = tw_mesh
	tower.position.y = 0.475
	tower.material_override = tower_mat
	jail.add_child(tower)

	corners.add_child(jail)

	# ── Tile 20 (Free Parking): Parked Micro-Cars ─────────────────────────
	var parking := Node3D.new()
	parking.name = "FreeParkingLot"
	parking.position = Vector3(4.5, 0.05, -4.5)

	var car1 := MeshInstance3D.new()
	var c1_mesh := BoxMesh.new()
	c1_mesh.size = Vector3(0.32, 0.18, 0.5)
	car1.mesh = c1_mesh
	car1.position = Vector3(-0.2, 0.12, 0)

	var c1_mat := StandardMaterial3D.new()
	c1_mat.albedo_color = Color(0.85, 0.15, 0.15)
	car1.material_override = c1_mat
	parking.add_child(car1)

	var car2 := MeshInstance3D.new()
	car2.mesh = c1_mesh
	car2.position = Vector3(0.2, 0.12, 0)

	var c2_mat := StandardMaterial3D.new()
	c2_mat.albedo_color = Color(0.15, 0.75, 0.25)
	car2.material_override = c2_mat
	parking.add_child(car2)

	corners.add_child(parking)

	# ── Tile 30 (Go To Jail): Police Siren Pedestal ──────────────────────
	var police := Node3D.new()
	police.name = "PolicePedestal"
	police.position = Vector3(-4.5, 0.05, -4.5)

	var beacon := MeshInstance3D.new()
	var bc_mesh := CylinderMesh.new()
	bc_mesh.top_radius = 0.14
	bc_mesh.bottom_radius = 0.18
	bc_mesh.height = 0.35
	beacon.mesh = bc_mesh
	beacon.position.y = 0.2

	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(0.15, 0.35, 0.85)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(0.2, 0.5, 1.0)
	beacon_mat.emission_energy_multiplier = 1.5
	beacon.material_override = beacon_mat
	police.add_child(beacon)

	corners.add_child(police)
