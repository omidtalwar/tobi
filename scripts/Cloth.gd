class_name Cloth
extends Node3D
## Fabric cover hanging over part of the wall. Blocks behind it can't be
## tapped until the player swipes across it to tear it away.
##
## Level data: {"rect": [x, y, w, h]} (min corner, world units)

signal torn

const Z := 0.95
const PIECES := 10

var rect: Rect2
var is_torn: bool = false
var _mesh: MeshInstance3D
var _mat: ShaderMaterial


func build(def: Dictionary) -> void:
	rect = LevelLoader.to_rect(def.get("rect"))
	position = Vector3(rect.get_center().x, rect.get_center().y, Z)
	_mat = Materials.fabric()
	_mat.set_shader_parameter("size", rect.size)
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Z
	plane.size = rect.size
	plane.subdivide_width = 10
	plane.subdivide_depth = 10
	_mesh = MeshInstance3D.new()
	_mesh.mesh = plane
	_mesh.material_override = _mat
	add_child(_mesh)
	# Iron nails along the top edge.
	var nails := maxi(2, int(rect.size.x))
	for i in nails:
		var nail := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.09
		s.height = 0.18
		nail.mesh = s
		nail.material_override = Materials.iron()
		var t := float(i) / float(nails - 1)
		nail.position = Vector3(lerpf(-rect.size.x * 0.5 + 0.15, rect.size.x * 0.5 - 0.15, t),
				rect.size.y * 0.5 - 0.1, 0.05)
		add_child(nail)


## True if the (untorn) cloth hides this grid cell.
func covers(cell: Vector2i) -> bool:
	return not is_torn and rect.has_point(Vector2(cell.x, cell.y))


## Swipe segment in world X/Y. Tears the cloth if the swipe crosses it.
func try_swipe(a: Vector2, b: Vector2) -> bool:
	if is_torn or a.distance_to(b) < 0.25:
		return false
	var grown := rect.grow(0.2)
	var hit_point := Vector2.INF
	for i in 9:
		var p := a.lerp(b, float(i) / 8.0)
		if grown.has_point(p):
			hit_point = p
			break
	if hit_point == Vector2.INF:
		return false
	tear(hit_point)
	return true


func tear(world_point: Vector2) -> void:
	if is_torn:
		return
	is_torn = true
	var uv := (world_point - rect.position) / rect.size
	# Plane UV.y runs top -> bottom.
	_mat.set_shader_parameter("tear_origin", Vector2(clampf(uv.x, 0.0, 1.0), 1.0 - clampf(uv.y, 0.0, 1.0)))
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("dissolve", v), 0.0, 1.0, 0.7) \
			.set_ease(Tween.EASE_IN)
	tw.tween_callback(_mesh.hide)
	_spawn_pieces(world_point)
	AudioManager.play("tear")
	Haptics.play("medium")
	torn.emit()


## Torn scraps flutter down and fade out.
func _spawn_pieces(origin: Vector2) -> void:
	var mat := StandardMaterial3D.new()
	var tex := Materials.texture("fabric.png")
	if tex != null:
		mat.albedo_texture = tex
	else:
		mat.albedo_color = Color(0.62, 0.1, 0.12)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.95
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in PIECES:
		var piece := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(randf_range(0.35, 0.8), randf_range(0.3, 0.7))
		piece.mesh = q
		piece.material_override = mat
		var start := Vector3(
				randf_range(rect.position.x, rect.end.x) * 0.7 + origin.x * 0.3,
				randf_range(rect.position.y, rect.end.y) * 0.7 + origin.y * 0.3, Z + 0.1)
		get_parent().add_child(piece)
		piece.global_position = start
		piece.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var dur := randf_range(1.0, 1.6)
		var tw := piece.create_tween().set_parallel()
		tw.tween_property(piece, "global_position",
				start + Vector3(randf_range(-1.5, 1.5), -randf_range(4.0, 7.0), randf_range(0.5, 1.5)), dur) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(piece, "rotation",
				piece.rotation + Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)), dur)
		tw.tween_property(piece, "transparency", 1.0, dur).set_delay(dur * 0.5)
		tw.chain().tween_callback(piece.queue_free)


## Little shake when the player taps a hidden block.
func nudge() -> void:
	var tw := create_tween()
	tw.tween_property(_mesh, "position:x", 0.08, 0.05)
	tw.tween_property(_mesh, "position:x", -0.06, 0.07)
	tw.tween_property(_mesh, "position:x", 0.0, 0.06)
