class_name Block
extends AnimatableBody3D
## One tappable coloured cube. Lives at integer cell coordinates inside a
## BlockGrid (cell (c, r) is at local position (c, r, 0)).
## AnimatableBody3D so falling blocks push hazard bodies physically.

const SIZE := 0.94
const RADIUS := 0.12
const FALL_SPEED := 9.0  # cells per second

var color_id: int = 0
var cell: Vector2i = Vector2i.ZERO
var removed: bool = false

var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _hint_tween: Tween


func setup(p_color: int, p_cell: Vector2i) -> void:
	color_id = p_color
	cell = p_cell
	position = Vector3(p_cell.x, p_cell.y, 0.0)
	collision_layer = PhysLayers.BLOCKS
	collision_mask = 0
	sync_to_physics = true

	_mesh = MeshInstance3D.new()
	_mesh.mesh = Materials.rounded_box(Vector3.ONE * SIZE, RADIUS)
	_mesh.material_override = Materials.block(p_color)
	add_child(_mesh)

	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, SIZE)  # Full cell so small rocks can't slip between blocks.
	_shape.shape = box
	add_child(_shape)


## Pops the block after `delay` seconds: collision off, squash, burst, free.
func pop(delay: float) -> void:
	removed = true
	set_hint(false)
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(_on_pop_start)
	tw.tween_property(_mesh, "scale", Vector3.ONE * 1.22, 0.06)
	tw.tween_property(_mesh, "scale", Vector3.ZERO, 0.14) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _on_pop_start() -> void:
	_shape.set_deferred("disabled", true)
	Fx.burst(get_parent(), global_position, Materials.BLOCK_COLORS[color_id])


## Animates the block down to a new cell (gravity). Returns the duration.
func fall_to(target: Vector2i, delay: float) -> float:
	var distance := float(cell.y - target.y)
	cell = target
	var duration := sqrt(maxf(distance, 0.0) / FALL_SPEED) * 0.55 + 0.05
	var tw := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_interval(delay)
	tw.tween_property(self, "position:y", float(target.y), duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Little squash on landing.
	tw.tween_property(_mesh, "scale", Vector3(1.08, 0.88, 1.08), 0.05)
	tw.tween_property(_mesh, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK)
	return delay + duration + 0.17


## Single blocks can't be removed: shake to show it.
func wobble() -> void:
	var tw := create_tween()
	tw.tween_property(_mesh, "rotation:z", 0.2, 0.05)
	tw.tween_property(_mesh, "rotation:z", -0.16, 0.08)
	tw.tween_property(_mesh, "rotation:z", 0.1, 0.07)
	tw.tween_property(_mesh, "rotation:z", 0.0, 0.07)


## Glowing pulsing outline used by the hint button.
func set_hint(on: bool) -> void:
	if _hint_tween != null:
		_hint_tween.kill()
		_hint_tween = null
	if on and not removed:
		_mesh.material_overlay = Materials.outline()
		_hint_tween = create_tween().set_loops()
		_hint_tween.tween_property(_mesh, "scale", Vector3.ONE * 1.07, 0.35)
		_hint_tween.tween_property(_mesh, "scale", Vector3.ONE, 0.35)
	else:
		_mesh.material_overlay = null
		_mesh.scale = Vector3.ONE
