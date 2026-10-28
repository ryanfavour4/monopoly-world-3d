## Dice3D.gd
## Manages 3D physical-style dice roll animations in the 3D board world.
## When roll() is triggered, two 3D dice tumble, spin, and bounce onto the
## board surface, settling on the authoritative values.

extends Node3D

signal roll_animation_finished(die1: int, die2: int, total: int)

var _die1_node: Node3D
var _die2_node: Node3D
var _is_rolling: bool = false

# Pre-computed Euler rotations that put face N facing UP (+Y)
# Standard d6 mapping where opposite faces sum to 7:
# 1 (Top) <-> 6 (Bottom)
# 2 (Right) <-> 5 (Left)
# 3 (Front) <-> 4 (Back)
const FACE_ROTATIONS = {
	1: Vector3(0.0, 0.0, 0.0),
	6: Vector3(PI, 0.0, 0.0),
	2: Vector3(0.0, 0.0, PI * 0.5),
	5: Vector3(0.0, 0.0, -PI * 0.5),
	3: Vector3(PI * 0.5, 0.0, 0.0),
	4: Vector3(-PI * 0.5, 0.0, 0.0)
}


func _ready() -> void:
	_build_dice()


func _build_dice() -> void:
	_die1_node = _create_single_die("Die1")
	_die1_node.position = Vector3(-0.6, 0.3, 0.0)
	add_child(_die1_node)

	_die2_node = _create_single_die("Die2")
	_die2_node.position = Vector3(0.6, 0.3, 0.0)
	add_child(_die2_node)


func _create_single_die(die_name: String) -> Node3D:
	var die := Node3D.new()
	die.name = die_name

	# Main cube body (ivory white with rounded feel)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.52, 0.52, 0.52)
	body.mesh = box

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.96, 0.95, 0.92)
	body_mat.roughness = 0.35
	body_mat.metallic = 0.1
	body.material_override = body_mat
	die.add_child(body)

	# Add pip dots for all 6 faces
	_add_pips_to_die(die)

	return die


func _add_pips_to_die(die: Node3D) -> void:
	var pip_mat := StandardMaterial3D.new()
	pip_mat.albedo_color = Color(0.12, 0.12, 0.14)
	pip_mat.roughness = 0.5

	# Helper to place a pip dot
	var place_pip = func(pos: Vector3, face_dir: Vector3):
		var pip := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.042
		s.height = 0.04
		pip.mesh = s
		pip.position = pos
		pip.material_override = pip_mat
		die.add_child(pip)

	var d: float = 0.262 # offset to surface of 0.52 cube
	var s: float = 0.13  # pip spacing

	# Face 1 (+Y) -> 1 center pip
	place_pip.call(Vector3(0, d, 0), Vector3.UP)

	# Face 6 (-Y) -> 6 pips (2 rows of 3)
	place_pip.call(Vector3(-s, -d, -s), -Vector3.UP)
	place_pip.call(Vector3(-s, -d, 0),  -Vector3.UP)
	place_pip.call(Vector3(-s, -d, s),  -Vector3.UP)
	place_pip.call(Vector3(s, -d, -s),  -Vector3.UP)
	place_pip.call(Vector3(s, -d, 0),   -Vector3.UP)
	place_pip.call(Vector3(s, -d, s),   -Vector3.UP)

	# Face 3 (+Z) -> 3 diagonal pips
	place_pip.call(Vector3(-s, -s, d), Vector3.FORWARD)
	place_pip.call(Vector3(0, 0, d),   Vector3.FORWARD)
	place_pip.call(Vector3(s, s, d),   Vector3.FORWARD)

	# Face 4 (-Z) -> 4 corner pips
	place_pip.call(Vector3(-s, -s, -d), -Vector3.FORWARD)
	place_pip.call(Vector3(-s, s, -d),  -Vector3.FORWARD)
	place_pip.call(Vector3(s, -s, -d),  -Vector3.FORWARD)
	place_pip.call(Vector3(s, s, -d),   -Vector3.FORWARD)

	# Face 2 (+X) -> 2 diagonal pips
	place_pip.call(Vector3(d, -s, -s), Vector3.RIGHT)
	place_pip.call(Vector3(d, s, s),   Vector3.RIGHT)

	# Face 5 (-X) -> 5 pips (4 corners + 1 center)
	place_pip.call(Vector3(-d, -s, -s), -Vector3.RIGHT)
	place_pip.call(Vector3(-d, s, -s),  -Vector3.RIGHT)
	place_pip.call(Vector3(-d, 0, 0),   -Vector3.RIGHT)
	place_pip.call(Vector3(-d, -s, s),  -Vector3.RIGHT)
	place_pip.call(Vector3(-d, s, s),   -Vector3.RIGHT)


## play_roll
## Triggers an animated physical bounce & tumble of the two 3D dice, settling on (die1, die2)
func play_roll(die1: int, die2: int) -> void:
	if _is_rolling:
		return
	_is_rolling = true

	var final_rot1: Vector3 = FACE_ROTATIONS.get(die1, Vector3.ZERO)
	var final_rot2: Vector3 = FACE_ROTATIONS.get(die2, Vector3.ZERO)

	# Add random Y yaw twist so dice don't look identically aligned
	final_rot1.y += randf_range(-0.4, 0.4)
	final_rot2.y += randf_range(-0.4, 0.4)

	var target_pos1 := Vector3(-0.65 + randf_range(-0.15, 0.15), 0.28, randf_range(-0.2, 0.2))
	var target_pos2 := Vector3(0.65 + randf_range(-0.15, 0.15), 0.28, randf_range(-0.2, 0.2))

	# Launch dice into the air above the board
	_die1_node.position = Vector3(-0.8, 3.2, -0.2)
	_die2_node.position = Vector3(0.8, 3.5, 0.3)

	# Initial tumble spins
	var spin1 := Vector3(randf_range(12.0, 18.0), randf_range(10.0, 16.0), randf_range(12.0, 18.0))
	var spin2 := Vector3(randf_range(-18.0, -12.0), randf_range(10.0, 16.0), randf_range(-18.0, -12.0))

	# Tween sequence for Die 1
	var tween1 := create_tween()
	tween1.set_parallel(true)
	# Y bounce trajectory
	tween1.tween_property(_die1_node, "position:y", 0.28, 0.95).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween1.tween_property(_die1_node, "position:x", target_pos1.x, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween1.tween_property(_die1_node, "position:z", target_pos1.z, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Rotation spin into final face
	tween1.tween_property(_die1_node, "rotation", final_rot1 + Vector3(PI * 4, PI * 2, PI * 4), 0.95).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Tween sequence for Die 2
	var tween2 := create_tween()
	tween2.set_parallel(true)
	tween2.tween_property(_die2_node, "position:y", 0.28, 1.05).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween2.tween_property(_die2_node, "position:x", target_pos2.x, 1.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween2.tween_property(_die2_node, "position:z", target_pos2.z, 1.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween2.tween_property(_die2_node, "rotation", final_rot2 + Vector3(-PI * 4, PI * 3, -PI * 4), 1.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Audio feedback
	if Engine.has_singleton("AudioManager") or has_node("/root/AudioManager"):
		if AudioManager.has_method("play_dice_roll"):
			AudioManager.play_dice_roll()

	# Complete after both finish
	await tween2.finished
	_is_rolling = false
	var total: int = die1 + die2
	roll_animation_finished.emit(die1, die2, total)
