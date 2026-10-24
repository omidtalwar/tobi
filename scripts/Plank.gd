class_name Plank
extends Node3D
## Wooden plank on an iron pivot (HingeJoint3D around Z). Tips when weight
## lands on it or when the blocks supporting it are removed.
##
## Level data: {"pivot": [x, y], "length": 4.0, "offset": 1.2,
##              "angle": 0, "min": -35, "max": 35, "mass": 3}
##   offset = plank centre distance from the pivot along the plank
##   (negative = plank extends to the left), min/max = hinge limits in degrees.

const THICKNESS := 0.32
const DEPTH := 1.1

var body: RigidBody3D
var _creak_cooldown: float = 0.0
var _half_length: float = 2.0
var _two_way: bool = false   # Seesaw that can tip both ways (min < 0 < max).
var _support_check: int = 0  # Physics frames until the support check runs.


func build(def: Dictionary) -> void:
	var pivot := LevelLoader.to_v2(def.get("pivot"))
	var length := float(def.get("length", 4.0))
	var offset := float(def.get("offset", 0.0))
	var angle := deg_to_rad(float(def.get("angle", 0.0)))
	var pivot3 := Vector3(pivot.x, pivot.y, 0.0)
	_half_length = length * 0.5
	_two_way = float(def.get("min", -35.0)) < 0.0 and float(def.get("max", 35.0)) > 0.0

	# Static anchor the hinge attaches to (no collision of its own).
	var anchor := StaticBody3D.new()
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	anchor.position = pivot3
	add_child(anchor)
	var pin := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.13
	cyl.bottom_radius = 0.13
	cyl.height = DEPTH + 0.5
	pin.mesh = cyl
	pin.material_override = Materials.iron()
	pin.rotation.x = PI * 0.5
	anchor.add_child(pin)

	body = RigidBody3D.new()
	body.collision_layer = PhysLayers.WORLD
	body.collision_mask = PhysLayers.HAZARD | PhysLayers.BLOCKS
	body.mass = float(def.get("mass", 3.0))
	body.axis_lock_linear_z = true
	body.axis_lock_angular_x = true
	body.axis_lock_angular_y = true
	body.angular_damp = 1.5
	body.position = pivot3 + Vector3(cos(angle), sin(angle), 0.0) * offset
	body.rotation.z = angle
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, THICKNESS, DEPTH)
	cs.shape = box
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = Materials.rounded_box(Vector3(length, THICKNESS, DEPTH), 0.08, 5)
	mi.material_override = Materials.wood_plank()
	body.add_child(mi)
	# Iron bands near both ends.
	for side: float in [-1.0, 1.0]:
		var band := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, THICKNESS + 0.04, DEPTH + 0.04)
		band.mesh = bm
		band.material_override = Materials.iron()
		band.position.x = side * (length * 0.5 - 0.3)
		body.add_child(band)
	add_child(body)

	var joint := HingeJoint3D.new()
	joint.position = pivot3
	add_child(joint)
	joint.node_a = joint.get_path_to(anchor)
	joint.node_b = joint.get_path_to(body)
	# Limits are relative to the starting angle. The hinge measures the angle
	# with the opposite sign to the plank's own rotation.z, so negate and swap.
	var lo := deg_to_rad(float(def.get("min", -35.0))) - angle
	var hi := deg_to_rad(float(def.get("max", 35.0))) - angle
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -hi)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, -lo)


## Called whenever the blocks change. A balanced seesaw has no torque of its
## own, so after the change we check which end lost its support and start it
## tipping that way (the supported end can't move down, so this is the only
## direction it could fall anyway).
func wake() -> void:
	body.sleeping = false
	if _two_way:
		_support_check = 3


func _physics_process(delta: float) -> void:
	_creak_cooldown -= delta
	if _creak_cooldown <= 0.0 and absf(body.angular_velocity.z) > 1.2:
		_creak_cooldown = 0.8
		AudioManager.play("creak")
	if _support_check > 0:
		_support_check -= 1
		if _support_check == 0:
			_tip_toward_free_end()


func _tip_toward_free_end() -> void:
	var left := _end_supported(-1.0)
	var right := _end_supported(1.0)
	if left == right:
		return
	# Positive rotation around Z lowers the left end.
	body.angular_velocity.z += 0.45 if not left else -0.45


func _end_supported(side: float) -> bool:
	var probe := body.global_transform * Vector3(side * (_half_length - 0.3), -THICKNESS * 0.5, 0.0)
	var query := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 0.05,
			probe + Vector3.DOWN * 0.3, PhysLayers.BLOCKS | PhysLayers.WORLD)
	query.exclude = [body.get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
