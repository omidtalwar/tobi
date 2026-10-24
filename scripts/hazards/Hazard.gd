class_name Hazard
extends Node3D
## Base class for rocks / boulder / lava.
## Many-body hazards render all their spheres with ONE MultiMeshInstance3D
## (one draw call) and copy each RigidBody3D transform into it every frame.

## Emitted by subclasses on hard hits (boulder landing) with a 0..1 strength.
@warning_ignore("unused_signal")
signal impact(strength: float)

## Bodies needed in the safe zone to win.
var win_count: int = 1
## Hazard bodies touching the thief that kill him.
var lose_contacts: int = 1
var bodies: Array[RigidBody3D] = []

var _multimesh: MultiMeshInstance3D
var _visual_basis: Array[Basis] = []  # Per-body visual scale/rotation variation.
var _kill_y: float = -8.0


## Override: create bodies from the level's hazard definition.
func spawn(_def: Dictionary) -> void:
	pass


func total() -> int:
	return bodies.size()


## Creates a Z-locked rigid sphere so all physics stays on the X/Y plane.
func make_sphere_body(pos: Vector2, radius: float, mass: float,
		material: PhysicsMaterial) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.collision_layer = PhysLayers.HAZARD
	b.collision_mask = PhysLayers.HAZARD_MASK
	b.axis_lock_linear_z = true
	b.axis_lock_angular_x = true
	b.axis_lock_angular_y = true
	b.mass = mass
	b.physics_material_override = material
	b.can_sleep = true
	b.position = Vector3(pos.x, pos.y, 0.0)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	cs.shape = shape
	b.add_child(cs)
	add_child(b)
	bodies.append(b)
	return b


## Sets up the shared MultiMesh after bodies were spawned.
## `unit_mesh` must be sized for radius 1; `radii` holds each body's radius.
func setup_multimesh(unit_mesh: Mesh, mat: Material, radii: Array[float],
		tints: PackedColorArray, squash: float = 0.12) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = tints.size() > 0
	mm.mesh = unit_mesh
	mm.instance_count = bodies.size()
	# Big fixed AABB: instances move every frame, don't let culling hide them.
	mm.custom_aabb = AABB(Vector3(-60, -60, -10), Vector3(120, 120, 20))
	_visual_basis.clear()
	for i in bodies.size():
		var r := radii[i]
		# Non-uniform scale + random 3D rotation so spheres read as rough rocks.
		var s := Vector3(r * randf_range(1.0 - squash, 1.0 + squash),
				r * randf_range(1.0 - squash, 1.0 + squash),
				r * randf_range(1.0 - squash, 1.0 + squash))
		var rot := Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
		_visual_basis.append(rot.scaled(s))
		if mm.use_colors:
			mm.set_instance_color(i, tints[i])
	_multimesh = MultiMeshInstance3D.new()
	_multimesh.multimesh = mm
	_multimesh.material_override = mat
	add_child(_multimesh)
	_sync_multimesh()


func _process(_delta: float) -> void:
	if _multimesh != null:
		_sync_multimesh()


func _sync_multimesh() -> void:
	var mm := _multimesh.multimesh
	for i in bodies.size():
		var b := bodies[i]
		if b.freeze:
			continue
		var t := b.transform  # Bodies and the MultiMesh share the same parent.
		mm.set_instance_transform(i, Transform3D(t.basis * _visual_basis[i], t.origin))


func _physics_process(_delta: float) -> void:
	# Bodies that fell out of the level are frozen and hidden.
	for i in bodies.size():
		var b := bodies[i]
		if not b.freeze and b.global_position.y < _kill_y:
			b.freeze = true
			b.collision_layer = 0
			b.collision_mask = 0
			if _multimesh != null:
				_multimesh.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))


## Wakes sleeping bodies (call after the terrain changes).
func wake_all() -> void:
	for b in bodies:
		if not b.freeze:
			b.sleeping = false


## Average position of active bodies (lava light follows it).
func centre() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for b in bodies:
		if not b.freeze:
			sum += b.global_position
			n += 1
	return sum / float(n) if n > 0 else global_position


## Fraction of bodies moving faster than `speed` (drives rumble volume).
func moving_ratio(speed: float = 1.2) -> float:
	if bodies.is_empty():
		return 0.0
	var n := 0
	var sq := speed * speed
	for b in bodies:
		if not b.freeze and not b.sleeping and b.linear_velocity.length_squared() > sq:
			n += 1
	return float(n) / float(bodies.size())
