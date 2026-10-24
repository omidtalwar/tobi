class_name Thief
extends Node3D
## The thief. Uses res://assets/models/thief.glb automatically when it exists
## (animations found through ANIM_KEYWORDS), otherwise builds a placeholder
## from primitives with procedural animation.
## Origin = feet. Faces the camera (+Z).

signal escaped
signal died

enum State { IDLE, SCARED, HAPPY, RUN, DEAD }

const MODEL_PATH := "res://assets/models/thief.glb"
const HEIGHT := 1.7
## Animation lookup for imported models: first animation whose name contains
## one of these words (case-insensitive) is used. Mixamo names work as-is.
const ANIM_KEYWORDS := {
	State.IDLE: ["idle", "breath", "stand"],
	State.SCARED: ["scared", "fear", "afraid", "terrified", "cower"],
	State.HAPPY: ["cheer", "happy", "victory", "celebrat", "dance"],
	State.RUN: ["run", "sprint", "jog"],
	State.DEAD: ["fall", "death", "die", "dying", "knock"],
}
const LOOPING_STATES: Array[State] = [State.IDLE, State.SCARED, State.RUN, State.HAPPY]

var state: State = State.IDLE

var _hurt_area: Area3D
var _danger_area: Area3D
var _visual: Node3D        # Root of whatever model is shown (rotated for running).
var _anim: AnimationPlayer  # Only set when a .glb model is used.
var _anim_names: Dictionary = {}  # State -> animation name
var _t: float = 0.0

# Placeholder parts (procedural animation).
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _eyes: Array[Node3D] = []


func _ready() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if not _try_load_model():
		_build_placeholder()
	_build_areas()
	set_state(State.IDLE)


# ------------------------------------------------------------- model setup --

func _try_load_model() -> bool:
	if not ResourceLoader.exists(MODEL_PATH):
		return false
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	if model == null:
		return false
	_visual.add_child(model)
	_fit_model_height(model)
	_anim = _find_animation_player(model)
	if _anim != null:
		var names := _anim.get_animation_list()
		for st: State in ANIM_KEYWORDS.keys():
			for keyword: String in ANIM_KEYWORDS[st]:
				var found := _find_anim(names, keyword)
				if found != "":
					_anim_names[st] = found
					break
		# Imported clips often aren't set to loop; force it for looping states.
		for st in LOOPING_STATES:
			if _anim_names.has(st):
				var a := _anim.get_animation(String(_anim_names[st]))
				if a != null:
					a.loop_mode = Animation.LOOP_LINEAR
	return true


func _find_anim(names: PackedStringArray, keyword: String) -> String:
	for n in names:
		if n.to_lower().contains(keyword):
			return n
	return ""


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


## Scales the imported model so it's HEIGHT tall with its feet at y = 0.
func _fit_model_height(model: Node3D) -> void:
	var box := _merged_aabb(model, Transform3D.IDENTITY)
	if box.size.y <= 0.001:
		return
	var s := HEIGHT / box.size.y
	model.scale = Vector3.ONE * s
	model.position.y = -box.position.y * s


func _merged_aabb(node: Node, xform: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is VisualInstance3D:
		var box := local * (node as VisualInstance3D).get_aabb()
		result = box
		first = false
	for child in node.get_children():
		var child_box := _merged_aabb(child, local)
		if child_box.size == Vector3.ZERO:
			continue
		result = child_box if first else result.merge(child_box)
		first = false
	return result


func _build_placeholder() -> void:
	var skin := Materials.solid(Color(0.98, 0.78, 0.6), 0.7)
	var black := Materials.solid(Color(0.06, 0.06, 0.07), 0.5)
	var pants := Materials.solid(Color(0.17, 0.2, 0.32), 0.8)
	var shirt := Materials.striped(Color(0.95, 0.95, 0.93), Color(0.08, 0.08, 0.1), 9.0)
	var white := Materials.solid(Color(1, 1, 1), 0.3)

	# Legs pivot at the hip so they can swing when running.
	_leg_l = _pivot(Vector3(-0.12, 0.62, 0))
	_leg_r = _pivot(Vector3(0.12, 0.62, 0))
	for leg: Node3D in [_leg_l, _leg_r]:
		_part(leg, _capsule(0.1, 0.62), pants, Vector3(0, -0.3, 0))
		_part(leg, _sphere(0.12, 0.09), black, Vector3(0, -0.6, 0.06))  # shoe

	_torso = _pivot(Vector3(0, 0.62, 0))
	_part(_torso, _capsule(0.27, 0.78), shirt, Vector3(0, 0.3, 0))

	_arm_l = _pivot(Vector3(-0.3, 1.0, 0))
	_arm_r = _pivot(Vector3(0.3, 1.0, 0))
	for arm: Node3D in [_arm_l, _arm_r]:
		_part(arm, _capsule(0.08, 0.5), shirt, Vector3(0, -0.22, 0))
		_part(arm, _sphere(0.08, 0.08), skin, Vector3(0, -0.47, 0))  # hand

	_head = _pivot(Vector3(0, 1.38, 0))
	_part(_head, _sphere(0.25, 0.25), skin, Vector3.ZERO)
	# Black eye mask band + beanie.
	var band := CylinderMesh.new()
	band.top_radius = 0.255
	band.bottom_radius = 0.255
	band.height = 0.11
	_part(_head, band, black, Vector3(0, 0.03, 0))
	var hat := SphereMesh.new()
	hat.radius = 0.26
	hat.height = 0.3
	hat.is_hemisphere = true
	_part(_head, hat, black, Vector3(0, 0.08, 0))
	for x: float in [-0.09, 0.09]:
		var eye := _part(_head, _sphere(0.05, 0.05), white, Vector3(x, 0.035, 0.235))
		_part(eye, _sphere(0.025, 0.025), black, Vector3(0, 0, 0.035))
		_eyes.append(eye)
	_part(_head, _sphere(0.045, 0.04), skin, Vector3(0, -0.04, 0.25))  # nose
	# Loot sack on the back.
	_part(_torso, _sphere(0.22, 0.2), Materials.solid(Color(0.6, 0.45, 0.25), 0.9), Vector3(0, 0.35, -0.3))


func _pivot(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	_visual.add_child(n)
	return n


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	return m


func _sphere(radius: float, half_height: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = half_height * 2.0
	return m


## Hurt box (touching = death) and a bigger danger zone (makes him scared).
func _build_areas() -> void:
	_hurt_area = _make_area(_capsule_shape(0.38, HEIGHT), Vector3(0, HEIGHT * 0.5, 0))
	var danger := SphereShape3D.new()
	danger.radius = 2.4
	_danger_area = _make_area(danger, Vector3(0, 1.0, 0))


func _capsule_shape(radius: float, height: float) -> CapsuleShape3D:
	var c := CapsuleShape3D.new()
	c.radius = radius
	c.height = height
	return c


func _make_area(shape: Shape3D, offset: Vector3) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = PhysLayers.HAZARD
	a.monitorable = false
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	a.add_child(cs)
	add_child(a)
	return a


# ------------------------------------------------------------------- state --

func is_alive() -> bool:
	return state != State.DEAD


func hazard_contacts() -> int:
	return _hurt_area.get_overlapping_bodies().size()


func hazard_near() -> int:
	return _danger_area.get_overlapping_bodies().size()


func set_state(new_state: State) -> void:
	if state == State.DEAD and new_state != State.DEAD:
		return
	if new_state == state and _t > 0.0:
		return
	state = new_state
	_t = 0.0
	if _anim != null and _anim_names.has(new_state):
		_anim.play(String(_anim_names[new_state]), 0.2)
	if _anim == null:
		_reset_pose()


## Plays the death animation and emits `died`.
func die() -> void:
	if state == State.DEAD:
		return
	set_state(State.DEAD)
	var tw := create_tween()
	if _anim == null or not _anim_names.has(State.DEAD):
		# Placeholder: hop, then fall flat backwards.
		tw.tween_property(_visual, "position:y", 0.4, 0.15).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_visual, "rotation:z", deg_to_rad(-90.0), 0.45) \
				.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_visual, "position:y", 0.25, 0.2)
	else:
		tw.tween_interval(1.0)
	tw.tween_callback(died.emit)


## Cheers briefly, then runs to `target_x` and emits `escaped`.
func run_to(target_x: float) -> void:
	set_state(State.HAPPY)
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_callback(func() -> void:
		set_state(State.RUN)
		_visual.rotation.y = deg_to_rad(90.0) * signf(target_x - position.x))
	var distance := absf(target_x - position.x)
	tw.tween_property(self, "position:x", target_x, maxf(distance / 4.5, 0.3))
	tw.tween_callback(escaped.emit)


# --------------------------------------------------- procedural animation --

func _process(delta: float) -> void:
	_t += delta
	if _anim != null:
		return
	match state:
		State.IDLE:
			var b := sin(_t * 2.2)
			_torso.position.y = 0.62 + b * 0.015
			_head.position.y = 1.38 + b * 0.02
			_head.rotation.z = sin(_t * 0.9) * 0.08
			_arm_l.rotation.z = -0.12 + b * 0.04
			_arm_r.rotation.z = 0.12 - b * 0.04
		State.SCARED:
			# Shiver, arms up, wide eyes.
			var shake := sin(_t * 45.0) * 0.025
			_visual.position.x = shake
			_arm_l.rotation.z = -2.6 + sin(_t * 30.0) * 0.1
			_arm_r.rotation.z = 2.6 - sin(_t * 30.0) * 0.1
			for e in _eyes:
				e.scale = Vector3.ONE * 1.5
		State.HAPPY:
			var hop := absf(sin(_t * 7.0))
			_visual.position.y = hop * 0.3
			_arm_l.rotation.z = -2.7
			_arm_r.rotation.z = 2.7
		State.RUN:
			var swing := sin(_t * 16.0)
			_leg_l.rotation.x = swing * 0.9
			_leg_r.rotation.x = -swing * 0.9
			_arm_l.rotation.x = -swing * 0.9
			_arm_r.rotation.x = swing * 0.9
			_visual.position.y = absf(swing) * 0.08
			_torso.rotation.x = 0.2
		State.DEAD:
			pass


func _reset_pose() -> void:
	if _torso == null:
		return
	_visual.position = Vector3.ZERO
	for n: Node3D in [_torso, _head, _arm_l, _arm_r, _leg_l, _leg_r]:
		n.rotation = Vector3.ZERO
	_torso.position.y = 0.62
	_head.position.y = 1.38
	for e in _eyes:
		e.scale = Vector3.ONE
