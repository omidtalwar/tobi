class_name RockHazard
extends Hazard
## 150-250 small stone spheres that pour through openings by gravity.

const DEFAULT_COUNT := 160

var _rumble_timer: float = 0.0


func spawn(def: Dictionary) -> void:
	var rect := LevelLoader.to_rect(def.get("spawn"))
	var count := int(def.get("count", DEFAULT_COUNT))
	win_count = ceili(count * float(def.get("win_ratio", 0.6)))
	lose_contacts = int(def.get("lose_contacts", 3))

	var pm := PhysicsMaterial.new()
	pm.friction = 0.55
	pm.bounce = 0.05

	# Fill the spawn rect with a jittered lattice; spacing chosen from area/count.
	var spacing := sqrt(rect.get_area() / float(count))
	var nx := maxi(1, floori(rect.size.x / spacing))
	var sx := rect.size.x / float(nx)
	var base_r := minf(spacing, sx) * 0.42
	var radii: Array[float] = []
	var tints := PackedColorArray()
	for i in count:
		var ix := i % nx
		var iy := floori(float(i) / float(nx))
		var pos := rect.position + Vector2((ix + 0.5) * sx, (iy + 0.5) * spacing)
		pos += Vector2(randf_range(-0.01, 0.01), randf_range(-0.01, 0.01))
		var r := base_r * randf_range(0.88, 1.12)
		var b := make_sphere_body(pos, r, 0.25, pm)
		b.gravity_scale = 1.6
		b.angular_damp = 0.6
		radii.append(r)
		var shade := randf_range(0.75, 1.1)
		tints.append(Color(shade, shade * randf_range(0.95, 1.0), shade * randf_range(0.88, 0.98)))

	# Faceted, noise-displaced stone. Visual slightly larger than the collider
	# so rocks look packed without gaps.
	var visual_radii: Array[float] = []
	for r in radii:
		visual_radii.append(r * 1.12)
	setup_multimesh(Materials.rock_mesh(true, 9, 6, 0.35, 4), Materials.stone(), visual_radii, tints, 0.14)


func _process(delta: float) -> void:
	super._process(delta)
	# Rumble volume follows how many rocks are moving.
	_rumble_timer -= delta
	if _rumble_timer <= 0.0:
		_rumble_timer = 0.2
		var ratio := moving_ratio()
		AudioManager.set_loop("rumble", ratio > 0.03, linear_to_db(clampf(ratio * 3.0, 0.05, 1.0)))


func _exit_tree() -> void:
	AudioManager.set_loop("rumble", false)
