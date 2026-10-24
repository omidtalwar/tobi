class_name LavaHazard
extends Hazard
## 200-300 small low-friction balls drawn larger than their colliders with a
## world-space lava shader, so neighbours overlap into one glowing liquid.
## An OmniLight3D follows the lava's centre and lights the walls orange.

const DEFAULT_COUNT := 240
const VISUAL_SCALE := 1.8

var _light: OmniLight3D
var _sizzle_timer: float = 0.0
var _t: float = 0.0


func spawn(def: Dictionary) -> void:
	var rect := LevelLoader.to_rect(def.get("spawn"))
	var count := int(def.get("count", DEFAULT_COUNT))
	win_count = ceili(count * float(def.get("win_ratio", 0.55)))
	lose_contacts = int(def.get("lose_contacts", 2))

	var pm := PhysicsMaterial.new()
	pm.friction = 0.0
	pm.bounce = 0.0

	var spacing := sqrt(rect.get_area() / float(count))
	var nx := maxi(1, floori(rect.size.x / spacing))
	var sx := rect.size.x / float(nx)
	var base_r := minf(spacing, sx) * 0.44
	var radii: Array[float] = []
	for i in count:
		var ix := i % nx
		var iy := floori(float(i) / float(nx))
		var pos := rect.position + Vector2((ix + 0.5) * sx, (iy + 0.5) * spacing)
		pos.x += randf_range(-0.02, 0.02)
		var r := base_r * randf_range(0.92, 1.08)
		var b := make_sphere_body(pos, r, 0.12, pm)
		b.gravity_scale = 1.4
		b.linear_damp = 0.25
		b.angular_damp = 2.0
		radii.append(r * VISUAL_SCALE)
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	setup_multimesh(mesh, Materials.lava(), radii, PackedColorArray(), 0.05)
	_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.45, 0.12)
	_light.light_energy = 2.2
	_light.omni_range = 7.0
	_light.omni_attenuation = 1.2
	_light.position = Vector3(rect.get_center().x, rect.get_center().y, 1.8)
	add_child(_light)


func _process(delta: float) -> void:
	super._process(delta)
	_t += delta
	# Light glides after the lava's centre and flickers like heat.
	var target := centre() + Vector3(0, 0, 1.8)
	_light.position = _light.position.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	_light.light_energy = 2.2 + sin(_t * 7.0) * 0.15 + sin(_t * 13.0) * 0.1
	_sizzle_timer -= delta
	if _sizzle_timer <= 0.0:
		_sizzle_timer = 0.25
		var ratio := moving_ratio(0.8)
		AudioManager.set_loop("sizzle", true, linear_to_db(clampf(0.25 + ratio * 2.5, 0.05, 1.0)))


func _exit_tree() -> void:
	AudioManager.set_loop("sizzle", false)
