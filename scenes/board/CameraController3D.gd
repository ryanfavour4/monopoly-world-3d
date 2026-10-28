## CameraController3D.gd
## Provides fluid chess-board style panning, orbiting, zooming, and pawn-focusing.
##
## Controls:
##   • Right-Click + Drag: Pan across the board plane (aligned to camera orientation)
##   • Middle-Click + Drag (or Alt + Right-Click): Orbit yaw & pitch around the board
##   • Mouse Wheel Up / Down: Smooth zoom in & out
##   • WASD / Arrow Keys: Pan smoothly
##   • Q / E: Rotate camera view left / right
##   • R: Reset camera view to default
##   • F: Focus camera on the current active player's pawn

extends Node3D

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------

@export_group("Pan Settings")
@export var pan_speed: float = 0.015
@export var key_pan_speed: float = 12.0
@export var pan_bounds_min: Vector2 = Vector2(-12.0, -12.0)
@export var pan_bounds_max: Vector2 = Vector2(12.0, 12.0)

@export_group("Orbit & Rotation")
@export var orbit_speed: float = 0.005
@export var key_rotate_speed: float = 2.5
@export var pitch_min_deg: float = 20.0
@export var pitch_max_deg: float = 85.0
@export var default_pitch_deg: float = 55.0
@export var default_yaw_deg: float = 0.0

@export_group("Zoom Settings")
@export var zoom_speed: float = 1.2
@export var zoom_min: float = 5.0
@export var zoom_max: float = 26.0
@export var default_zoom: float = 14.0

@export_group("Smoothing")
@export var smoothness: float = 12.0

# ---------------------------------------------------------------------------
# STATE
# ---------------------------------------------------------------------------

var _target_pan: Vector3 = Vector3.ZERO
var _current_pan: Vector3 = Vector3.ZERO

var _target_yaw: float = 0.0
var _current_yaw: float = 0.0

var _target_pitch: float = deg_to_rad(55.0)
var _current_pitch: float = deg_to_rad(55.0)

var _target_zoom: float = 14.0
var _current_zoom: float = 14.0

var _is_panning: bool = false
var _is_orbiting: bool = false

@onready var camera_node: Camera3D = find_child("Camera3D", true, false)


func _ready() -> void:
	_target_pitch = deg_to_rad(default_pitch_deg)
	_current_pitch = _target_pitch
	_target_yaw = deg_to_rad(default_yaw_deg)
	_current_yaw = _target_yaw
	_target_zoom = default_zoom
	_current_zoom = default_zoom
	_update_camera_transform(1.0)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse button pressed / released
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if Input.is_key_pressed(KEY_ALT) or Input.is_key_pressed(KEY_SHIFT):
					_is_orbiting = true
				else:
					_is_panning = true
			else:
				_is_panning = false
				_is_orbiting = false

		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_is_orbiting = mb.pressed

		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_zoom = clampf(_target_zoom - zoom_speed, zoom_min, zoom_max)

		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_zoom = clampf(_target_zoom + zoom_speed, zoom_min, zoom_max)

	# Mouse motion
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _is_orbiting:
			_target_yaw -= mm.relative.x * orbit_speed
			_target_pitch = clampf(
				_target_pitch - mm.relative.y * orbit_speed,
				deg_to_rad(pitch_min_deg),
				deg_to_rad(pitch_max_deg)
			)
		elif _is_panning:
			var zoom_scale: float = _current_zoom / 15.0
			var forward := -Vector3(sin(_current_yaw), 0.0, cos(_current_yaw)).normalized()
			var right := Vector3(cos(_current_yaw), 0.0, -sin(_current_yaw)).normalized()
			var move := (-right * mm.relative.x + forward * mm.relative.y) * pan_speed * zoom_scale
			_target_pan += move
			_target_pan.x = clampf(_target_pan.x, pan_bounds_min.x, pan_bounds_max.x)
			_target_pan.z = clampf(_target_pan.z, pan_bounds_min.y, pan_bounds_max.y)

	# Keyboard shortcuts
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			reset_view()
		elif event.keycode == KEY_F:
			focus_active_pawn()
		elif event.keycode == KEY_T:
			toggle_top_down()


func _process(delta: float) -> void:
	# Continuous keyboard panning (WASD / Arrows)
	var key_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		key_dir.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		key_dir.y -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		key_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		key_dir.x += 1.0

	if key_dir != Vector2.ZERO:
		key_dir = key_dir.normalized()
		var forward := -Vector3(sin(_current_yaw), 0.0, cos(_current_yaw)).normalized()
		var right := Vector3(cos(_current_yaw), 0.0, -sin(_current_yaw)).normalized()
		var pan_vec := (forward * key_dir.y + right * key_dir.x) * key_pan_speed * delta
		_target_pan += pan_vec
		_target_pan.x = clampf(_target_pan.x, pan_bounds_min.x, pan_bounds_max.x)
		_target_pan.z = clampf(_target_pan.z, pan_bounds_min.y, pan_bounds_max.y)

	# Q / E continuous rotation
	if Input.is_key_pressed(KEY_Q):
		_target_yaw += key_rotate_speed * delta
	if Input.is_key_pressed(KEY_E):
		_target_yaw -= key_rotate_speed * delta

	# Smooth interpolation
	var t: float = clampf(delta * smoothness, 0.0, 1.0)
	_current_pan = _current_pan.lerp(_target_pan, t)
	_current_yaw = lerp_angle(_current_yaw, _target_yaw, t)
	_current_pitch = lerp(_current_pitch, _target_pitch, t)
	_current_zoom = lerp(_current_zoom, _target_zoom, t)

	_update_camera_transform()


func _update_camera_transform(_weight: float = 1.0) -> void:
	if not camera_node:
		return

	# Spherical orbit position relative to focal center
	var offset_x: float = _current_zoom * cos(_current_pitch) * sin(_current_yaw)
	var offset_y: float = _current_zoom * sin(_current_pitch)
	var offset_z: float = _current_zoom * cos(_current_pitch) * cos(_current_yaw)

	var cam_pos := _current_pan + Vector3(offset_x, offset_y, offset_z)
	camera_node.global_position = cam_pos
	camera_node.look_at(_current_pan, Vector3.UP)


## reset_view
## Restores default top-down angled perspective
func reset_view() -> void:
	_target_pan = Vector3.ZERO
	_target_yaw = deg_to_rad(default_yaw_deg)
	_target_pitch = deg_to_rad(default_pitch_deg)
	_target_zoom = default_zoom


## focus_active_pawn
## Centers camera on current active player's pawn
func focus_active_pawn() -> void:
	var tm = get_node_or_null("/root/TurnManager")
	if not tm:
		return
	var cur_pid: int = tm.get_current_player_id()
	var board: Node = get_parent()
	if board and "pawns" in board and board.pawns.has(cur_pid):
		var pawn_node = board.pawns[cur_pid]
		if pawn_node:
			_target_pan = pawn_node.global_position


func focus_on_active_pawn() -> void:
	focus_active_pawn()


## toggle_top_down
## Toggles between straight top-down (85°) and angled view (55°)
func toggle_top_down() -> void:
	if abs(_target_pitch - deg_to_rad(85.0)) < 0.1:
		_target_pitch = deg_to_rad(55.0)
	else:
		_target_pitch = deg_to_rad(85.0)
