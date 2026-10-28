# =============================================================================
# PlayerPawn.gd
# =============================================================================
# Represents a single player's game piece on the 3-D Monopoly board.
# Visual Overhaul:
#   • Procedural 3D Roadster Car token replacing generic cylinders
#   • Dynamic player body color with metallic lacquer
#   • Tinted cabin windshield, chrome grille, glowing headlights & taillights
#   • 4 rotating wheels with chrome hubcaps that spin during movement
#   • Suspension bob and forward-facing directional steering
#   • Animated landing reactions (wheelie celebrations, sad suspension sag)
#   • Idle engine breathing vibration
#   • Floating billboard username label
# =============================================================================

extends CharacterBody3D

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal movement_finished(player_id: int, final_tile: int)

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var player_id: int = 0
@export var pawn_color: Color = Color(0.2, 0.6, 1.0)

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var anim_controller: Node = get_node_or_null("AnimationController")
@onready var name_label: Label3D = get_node_or_null("NameLabel")
@onready var idle_timer: Timer = get_node_or_null("IdleTimer")

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var current_tile: int = 0
var is_moving: bool = false
var _active_tween: Tween = null

# 3D Roadster Car visual components
var _car_root: Node3D = null
var _car_body_mesh: MeshInstance3D = null
var _wheel_nodes: Array[Node3D] = []
var _headlights: Array[MeshInstance3D] = []
var _taillights: Array[MeshInstance3D] = []
var _is_idle_anim_active: bool = false
var _idle_time: float = 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if not _car_root:
		_build_roadster_model()

	# Hide any legacy cylinder mesh if present in scene
	var old_cylinder := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if old_cylinder and old_cylinder != _car_body_mesh:
		old_cylinder.visible = false

	if idle_timer:
		if not idle_timer.timeout.is_connected(_on_idle_timer_timeout):
			idle_timer.timeout.connect(_on_idle_timer_timeout)
		idle_timer.one_shot = true
		reset_idle_timer()


func _process(delta: float) -> void:
	# Subtle engine idle breathing when parked
	if not is_moving and _car_root:
		_idle_time += delta
		var breath := sin(_idle_time * 3.5) * 0.015
		_car_root.position.y = 0.12 + breath
		_car_root.rotation.z = sin(_idle_time * 2.0) * 0.01


# ---------------------------------------------------------------------------
# 3D ROADSTER CAR PROCEDURAL MODEL
# ---------------------------------------------------------------------------

func _build_roadster_model() -> void:
	_car_root = Node3D.new()
	_car_root.name = "RoadsterModel"
	_car_root.position = Vector3(0, 0.12, 0)
	add_child(_car_root)

	# --- 1. Materials ---
	# Glossy car lacquer paint
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = pawn_color
	body_mat.metallic = 0.55
	body_mat.roughness = 0.22
	body_mat.clearcoat_enabled = true
	body_mat.clearcoat = 0.8

	# Tinted glass cabin
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.12, 0.15, 0.20)
	glass_mat.metallic = 0.8
	glass_mat.roughness = 0.12

	# Chrome metal (grille, bumpers, hubcaps)
	var chrome_mat := StandardMaterial3D.new()
	chrome_mat.albedo_color = Color(0.92, 0.94, 0.96)
	chrome_mat.metallic = 0.95
	chrome_mat.roughness = 0.15

	# Dark rubber tires
	var rubber_mat := StandardMaterial3D.new()
	rubber_mat.albedo_color = Color(0.12, 0.13, 0.14)
	rubber_mat.roughness = 0.9

	# Headlight glow
	var light_mat := StandardMaterial3D.new()
	light_mat.albedo_color = Color(1.0, 0.96, 0.75)
	light_mat.emission_enabled = true
	light_mat.emission = Color(1.0, 0.95, 0.7)
	light_mat.emission_energy_multiplier = 2.0

	# Taillight glow
	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.9, 0.1, 0.1)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.1, 0.1)
	tail_mat.emission_energy_multiplier = 2.0

	# --- 2. Main Chassis Body ---
	_car_body_mesh = MeshInstance3D.new()
	_car_body_mesh.name = "Chassis"
	var body_box := BoxMesh.new()
	body_box.size = Vector3(0.42, 0.14, 0.72)
	_car_body_mesh.mesh = body_box
	_car_body_mesh.material_override = body_mat
	_car_body_mesh.position = Vector3(0, 0.07, 0)
	_car_root.add_child(_car_body_mesh)

	# --- 3. Front Engine Hood (Tapered) ---
	var hood := MeshInstance3D.new()
	hood.name = "EngineHood"
	var hood_box := BoxMesh.new()
	hood_box.size = Vector3(0.38, 0.10, 0.26)
	hood.mesh = hood_box
	hood.material_override = body_mat
	hood.position = Vector3(0, 0.05, 0.32)
	_car_root.add_child(hood)

	# --- 4. Cockpit / Windshield Cabin ---
	var cabin := MeshInstance3D.new()
	cabin.name = "Cockpit"
	var cabin_box := BoxMesh.new()
	cabin_box.size = Vector3(0.34, 0.13, 0.32)
	cabin.mesh = cabin_box
	cabin.material_override = glass_mat
	cabin.position = Vector3(0, 0.17, -0.06)
	_car_root.add_child(cabin)

	# Roof trim
	var roof := MeshInstance3D.new()
	var roof_box := BoxMesh.new()
	roof_box.size = Vector3(0.30, 0.03, 0.22)
	roof.mesh = roof_box
	roof.material_override = body_mat
	roof.position = Vector3(0, 0.24, -0.08)
	_car_root.add_child(roof)

	# --- 5. Chrome Front Grille ---
	var grille := MeshInstance3D.new()
	grille.name = "ChromeGrille"
	var g_box := BoxMesh.new()
	g_box.size = Vector3(0.28, 0.08, 0.04)
	grille.mesh = g_box
	grille.material_override = chrome_mat
	grille.position = Vector3(0, 0.04, 0.46)
	_car_root.add_child(grille)

	# --- 6. Headlights ---
	for x_offset in [-0.14, 0.14]:
		var hl := MeshInstance3D.new()
		var hl_mesh := CylinderMesh.new()
		hl_mesh.top_radius = 0.035
		hl_mesh.bottom_radius = 0.035
		hl_mesh.height = 0.04
		hl.mesh = hl_mesh
		hl.rotation.x = deg_to_rad(90.0)
		hl.material_override = light_mat
		hl.position = Vector3(x_offset, 0.06, 0.46)
		_car_root.add_child(hl)
		_headlights.append(hl)

	# --- 7. Taillights ---
	for x_offset in [-0.14, 0.14]:
		var tl := MeshInstance3D.new()
		var tl_box := BoxMesh.new()
		tl_box.size = Vector3(0.06, 0.04, 0.03)
		tl.mesh = tl_box
		tl.material_override = tail_mat
		tl.position = Vector3(x_offset, 0.08, -0.37)
		_car_root.add_child(tl)
		_taillights.append(tl)

	# --- 8. Rotating Wheels (4x) ---
	var wheel_offsets = [
		Vector3(-0.23, 0.0, 0.24),   # Front Left
		Vector3(0.23, 0.0, 0.24),    # Front Right
		Vector3(-0.23, 0.0, -0.24),  # Rear Left
		Vector3(0.23, 0.0, -0.24)    # Rear Right
	]

	_wheel_nodes.clear()
	for i in range(wheel_offsets.size()):
		var w_pivot := Node3D.new()
		w_pivot.name = "Wheel_%d" % i
		w_pivot.position = wheel_offsets[i]

		# Tire rubber cylinder
		var tire := MeshInstance3D.new()
		var tire_cyl := CylinderMesh.new()
		tire_cyl.top_radius = 0.095
		tire_cyl.bottom_radius = 0.095
		tire_cyl.height = 0.06
		tire.mesh = tire_cyl
		tire.rotation.z = deg_to_rad(90.0)
		tire.material_override = rubber_mat
		w_pivot.add_child(tire)

		# Chrome hubcap
		var hub := MeshInstance3D.new()
		var hub_cyl := CylinderMesh.new()
		hub_cyl.top_radius = 0.045
		hub_cyl.bottom_radius = 0.045
		hub_cyl.height = 0.065
		hub.mesh = hub_cyl
		hub.rotation.z = deg_to_rad(90.0)
		hub.material_override = chrome_mat
		w_pivot.add_child(hub)

		_car_root.add_child(w_pivot)
		_wheel_nodes.append(w_pivot)

	# Position floating billboard username label above car roof
	if name_label:
		name_label.position = Vector3(0, 0.72, 0)
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(id: int, username: String, color: Color, initial_pos: Vector3 = Vector3.ZERO) -> void:
	player_id = id
	pawn_color = color

	if initial_pos != Vector3.ZERO:
		global_position = initial_pos

	if name_label:
		name_label.text = username

	if not _car_root:
		_build_roadster_model()
	elif _car_body_mesh and _car_body_mesh.material_override:
		(_car_body_mesh.material_override as StandardMaterial3D).albedo_color = color


func move_to_tile(target_tile: int, board_positions: Array, pass_go: bool) -> void:
	if is_moving:
		push_warning("PlayerPawn: move_to_tile() called while already moving. Ignored.")
		return

	is_moving = true
	reset_idle_timer()

	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()

	# Build path sequence
	var steps: Array[int] = []
	var tile := current_tile
	while tile != target_tile:
		tile = (tile + 1) % 40
		steps.append(tile)

	if steps.is_empty():
		is_moving = false
		movement_finished.emit(player_id, current_tile)
		return

	# Step-by-step traversal along the road path
	for step_tile in steps:
		var dest: Vector3 = board_positions[step_tile]
		var start_pos := global_position

		# Align car rotation smoothly towards destination tile
		var dir := (dest - start_pos)
		dir.y = 0.0
		if dir.length_squared() > 0.001 and _car_root:
			var target_yaw := atan2(dir.x, dir.z)
			var rot_tween := create_tween()
			rot_tween.tween_property(_car_root, "rotation:y", target_yaw, 0.12).set_trans(Tween.TRANS_SINE)

		var dist: float = start_pos.distance_to(dest)
		var duration: float = clampf(dist / 4.5, 0.18, 0.45)

		_active_tween = create_tween()
		_active_tween.set_parallel(true)
		_active_tween.set_ease(Tween.EASE_IN_OUT)
		_active_tween.set_trans(Tween.TRANS_SINE)

		# Horizontal position tween
		_active_tween.tween_property(self, "global_position:x", dest.x, duration)
		_active_tween.tween_property(self, "global_position:z", dest.z, duration)

		# Suspension hop bounce on each tile step
		if _car_root:
			var hop_tween := create_tween()
			hop_tween.tween_property(_car_root, "position:y", 0.22, duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			hop_tween.chain().tween_property(_car_root, "position:y", 0.12, duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

		# Spin wheels forward during movement
		for w in _wheel_nodes:
			_active_tween.tween_property(w, "rotation:x", w.rotation.x + deg_to_rad(180.0), duration)

		await _active_tween.finished
		current_tile = step_tile

	is_moving = false
	movement_finished.emit(player_id, current_tile)


func play_land_animation(landing_result: Dictionary) -> void:
	var action: String = landing_result.get("action", "idle")
	reset_idle_timer()

	if not _car_root:
		return

	match action:
		"buy_available", "collect_go", "celebrate":
			# Joyful celebratory car wheelie & 360 spin!
			var tw := create_tween()
			tw.set_parallel(true)
			tw.tween_property(_car_root, "rotation:x", deg_to_rad(-25.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(_car_root, "position:y", 0.35, 0.25)
			tw.chain().tween_property(_car_root, "rotation:y", _car_root.rotation.y + TAU, 0.5).set_trans(Tween.TRANS_CUBIC)
			tw.chain().tween_property(_car_root, "rotation:x", 0.0, 0.25)
			tw.tween_property(_car_root, "position:y", 0.12, 0.25)

		"pay_rent", "pay_tax":
			# Sad state: suspension drops low and front droops
			var tw := create_tween()
			tw.tween_property(_car_root, "rotation:x", deg_to_rad(15.0), 0.3).set_trans(Tween.TRANS_BOUNCE)
			tw.tween_property(_car_root, "position:y", 0.06, 0.3)
			tw.chain().tween_interval(0.6)
			tw.chain().tween_property(_car_root, "rotation:x", 0.0, 0.4)
			tw.tween_property(_car_root, "position:y", 0.12, 0.4)

		_:
			# Default settled stance
			var tw := create_tween()
			tw.tween_property(_car_root, "position:y", 0.12, 0.2)
			tw.tween_property(_car_root, "rotation:x", 0.0, 0.2)


func reset_idle_timer() -> void:
	if idle_timer:
		idle_timer.stop()
		idle_timer.start()


func teleport_to_jail() -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	is_moving = false
	current_tile = 10

	# Sad state drooping
	play_land_animation({"action": "pay_tax"})
	reset_idle_timer()


func _on_idle_timer_timeout() -> void:
	if not is_moving and anim_controller and anim_controller.has_method("play_idle"):
		anim_controller.play_idle()

