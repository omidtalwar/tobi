class_name BoulderHazard
extends Hazard
## One big heavy stone ball. Rolls when its support is removed.
## Any contact with the thief kills him; it must end up in the safe zone.

var _boulder: RigidBody3D
var _last_velocity: Vector3 = Vector3.ZERO
var _impact_cooldown: float = 0.0


func spawn(def: Dictionary) -> void:
	var pos := LevelLoader.to_v2(def.get("position"))
	var radius := float(def.get("radius", 0.8))
	win_count = 1
	lose_contacts = 1

	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.08
	_boulder = make_sphere_body(pos, radius, 25.0, pm)
	_boulder.gravity_scale = 2.0
	_boulder.angular_damp = 0.05
	_boulder.continuous_cd = true

	var mi := MeshInstance3D.new()
	mi.mesh = Materials.rock_mesh(false, 32, 18, 0.12, 21)
	mi.material_override = Materials.stone()
	mi.scale = Vector3.ONE * radius
	mi.rotation = Vector3(0.4, 0.9, 0.0)
	_boulder.add_child(mi)


## Detects hard landings from sudden velocity changes.
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_impact_cooldown -= delta
	var v := _boulder.linear_velocity
	var change := (v - _last_velocity).length()
	_last_velocity = v
	if change > 4.0 and _impact_cooldown <= 0.0:
		_impact_cooldown = 0.35
		var strength := clampf((change - 4.0) / 8.0, 0.2, 1.0)
		AudioManager.play("thud", linear_to_db(strength))
		impact.emit(strength)


func _process(_delta: float) -> void:
	# Rolling rumble follows the boulder's spin speed.
	var spin := absf(_boulder.angular_velocity.z) if not _boulder.sleeping else 0.0
	AudioManager.set_loop("roll", spin > 0.6, linear_to_db(clampf(spin / 6.0, 0.05, 1.0)))


func _exit_tree() -> void:
	AudioManager.set_loop("roll", false)
