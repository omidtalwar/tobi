class_name Fx
## Small reusable visual effects. Concurrent particle bursts are capped so a
## big chain of pops never tanks the frame rate on phones.

const MAX_BURSTS := 10

static var _active_bursts: int = 0
static var _process_material: ParticleProcessMaterial
static var _meshes: Dictionary = {}  # Color html -> BoxMesh


## Cube-chip burst at a world position (used when a block pops).
static func burst(parent: Node, pos: Vector3, color: Color, amount: int = 14) -> void:
	if _active_bursts >= MAX_BURSTS or parent == null or not parent.is_inside_tree():
		return
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.process_material = _get_process_material()
	p.draw_pass_1 = _get_mesh(color)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_active_bursts += 1
	p.finished.connect(func() -> void:
		_active_bursts -= 1
		p.queue_free())


static func _get_process_material() -> ParticleProcessMaterial:
	if _process_material == null:
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0.3)
		pm.spread = 180.0
		pm.initial_velocity_min = 2.5
		pm.initial_velocity_max = 5.5
		pm.gravity = Vector3(0, -16, 0)
		pm.angular_velocity_min = -360.0
		pm.angular_velocity_max = 360.0
		pm.scale_min = 0.5
		pm.scale_max = 1.2
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.35, 0.35, 0.2)
		_process_material = pm
	return _process_material


static func _get_mesh(color: Color) -> Mesh:
	var key := color.to_html()
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = Vector3.ONE * 0.17
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.3
		m.material = mat
		_meshes[key] = m
	return _meshes[key]
