extends Node3D
## Builds a level from JSON and runs it: camera, lights, walls, blocks,
## hazard, planks, cloth, thief, input (tap raycast + swipe) and win/lose.
##
## Win  = enough hazard bodies inside the safe zone AND the exit cells are
##        clear AND the thief is alive -> thief runs out, win popup.
## Lose = hazard bodies touching the thief >= hazard.lose_contacts.

enum State { PLAYING, WON, LOST }

const CAMERA_DISTANCE := 30.0
## Slight tilt of the orthographic camera (degrees) so the depth of walls and
## blocks shows. Gameplay stays on the X/Y plane. Set to Vector3.ZERO for a
## perfectly straight-on view.
const CAMERA_TILT := Vector3(-9.0, 8.0, 0.0)
const WIN_HOLD_SECONDS := 0.6
const TAP_MAX_MOVE := 28.0  # Pixels a touch may move and still count as a tap.
## Any hazard contact lasting this long catches the thief.
const TOUCH_LOSE_SECONDS := 0.5

var level_index: int = 1
var level: Dictionary = {}
var state: State = State.PLAYING
var taps: int = 0

var camera: Camera3D
var grid: BlockGrid
var hazard: Hazard
var thief: Thief
var safe_zone: Area3D
var hud: Hud
var planks: Array[Plank] = []
var cloths: Array[Cloth] = []

var _exit_cells: Array[Vector2i] = []
var _exit_pos: Vector2 = Vector2.ZERO
var _pending_taps: Array[Vector2] = []  # Screen positions handled in the physics step.
var _touch_start: Vector2 = Vector2.ZERO
var _touch_moved: float = 0.0
var _touch_down: bool = false
var _win_hold: float = 0.0
var _touch_time: float = 0.0
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0


func _ready() -> void:
	level_index = GameState.current_level
	level = LevelLoader.load_level(level_index)
	if level.is_empty():
		push_error("Game: level %d missing, loading level 1" % level_index)
		level_index = 1
		level = LevelLoader.load_level(1)
	_build_environment()
	_build_level()
	_build_hud()
	AudioManager.play_music()


# ------------------------------------------------------------------- build --

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.04, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.88, 0.75)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	# Glow: only HDR-bright pixels (lava, flames, hint outline) bloom.
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	# SSAO only on Forward+ (desktop); the Mobile renderer skips it.
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		env.ssao_enabled = true
		env.ssao_radius = 0.8
		env.ssao_intensity = 1.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Warm key light from upper-left-front, soft shadows onto the back wall.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 80.0
	sun.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	add_child(sun)

	# Cool, dim fill light from the right so shadows aren't pitch black.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.6, 0.7, 1.0)
	fill.light_energy = 0.22
	fill.rotation_degrees = Vector3(-15.0, 40.0, 0.0)
	add_child(fill)

	# Full-screen blend is costly on phones; the scene reads fine without it.
	if not OS.has_feature("mobile"):
		Decor.add_vignette(self)


func _build_level() -> void:
	var grid_rows: Array = level.get("grid", [])
	grid = BlockGrid.new()
	grid.name = "BlockGrid"
	add_child(grid)
	grid.build(grid_rows)
	grid.group_removed.connect(_on_group_removed)
	grid.settled.connect(_wake_physics)

	_build_back_panel()
	_build_extra_walls()
	_build_safe_zone()
	_build_camera()

	_exit_cells = LevelLoader.to_cells(level.get("exit_cells", []))
	_exit_pos = LevelLoader.to_v2(level.get("exit"), Vector2(grid.cols + 2, 0.5))
	_build_exit_sign()

	for def: Variant in level.get("planks", []):
		var plank := Plank.new()
		add_child(plank)
		plank.build(def as Dictionary)
		planks.append(plank)

	for def: Variant in level.get("cloth", []):
		var cloth := Cloth.new()
		add_child(cloth)
		cloth.build(def as Dictionary)
		cloths.append(cloth)

	thief = Thief.new()
	thief.name = "Thief"
	var tp := LevelLoader.to_v2(level.get("thief"))
	thief.position = Vector3(tp.x, tp.y, 0.0)
	add_child(thief)
	thief.died.connect(_on_thief_died)
	thief.escaped.connect(_on_thief_escaped)

	var hazard_def: Dictionary = level.get("hazard", {})
	hazard = _make_hazard(String(hazard_def.get("type", "rocks")))
	add_child(hazard)
	hazard.spawn(hazard_def)
	hazard.impact.connect(_on_hazard_impact)

	# Atmosphere: lanterns on the frame's top corners + dust in the air.
	var top := float(grid.rows) - 2.5
	Decor.add_lantern(self, Vector3(0.0, top, BlockGrid.WALL_DEPTH * 0.5 + 0.25))
	Decor.add_lantern(self, Vector3(grid.cols - 1.0, top, BlockGrid.WALL_DEPTH * 0.5 + 0.25))
	Decor.add_dust(self, Rect2(0, 0, grid.cols, grid.rows))


func _make_hazard(type: String) -> Hazard:
	var h: Hazard
	match type:
		"boulder":
			h = BoulderHazard.new()
		"lava":
			h = LavaHazard.new()
		_:
			h = RockHazard.new()
	h.name = "Hazard"
	return h


## Dark carved wood behind everything.
func _build_back_panel() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "BackPanel"
	var bm := BoxMesh.new()
	bm.size = Vector3(float(grid.cols) + 30.0, float(grid.rows) + 30.0, 0.4)
	mi.mesh = bm
	mi.material_override = Materials.wood_wall_dark()
	mi.position = Vector3((grid.cols - 1) * 0.5, (grid.rows - 1) * 0.5, -BlockGrid.WALL_DEPTH * 0.5 - 0.2)
	add_child(mi)


## Ramps and other free-form wall pieces from the level's "walls" array.
func _build_extra_walls() -> void:
	var walls: Array = level.get("walls", [])
	if walls.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "ExtraWalls"
	body.collision_layer = PhysLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	for w: Variant in walls:
		var d: Dictionary = w
		var r := LevelLoader.to_rect(d.get("rect"))  # [cx, cy, w, h] centre-based
		BlockGrid.add_wall_box(body, Vector3(r.position.x, r.position.y, 0.0),
				Vector3(r.size.x, r.size.y, BlockGrid.WALL_DEPTH * 0.9),
				float(d.get("angle", 0.0)), Materials.wood_wall())


func _build_safe_zone() -> void:
	var rect := LevelLoader.to_rect(level.get("safe_zone"))
	safe_zone = Area3D.new()
	safe_zone.name = "SafeZone"
	safe_zone.collision_layer = 0
	safe_zone.collision_mask = PhysLayers.HAZARD
	safe_zone.monitorable = false
	safe_zone.position = Vector3(rect.get_center().x, rect.get_center().y, 0.0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, rect.size.y, 2.0)
	cs.shape = box
	safe_zone.add_child(cs)
	add_child(safe_zone)
	# Dark stone backing so the drain pit reads visually.
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(rect.size.x, rect.size.y, 0.1)
	mi.mesh = bm
	mi.material_override = Materials.pit()
	mi.position = Vector3(0, 0, -BlockGrid.WALL_DEPTH * 0.5 + 0.02)
	safe_zone.add_child(mi)


func _build_exit_sign() -> void:
	var exit_label := Label3D.new()
	exit_label.text = "EXIT"
	exit_label.font_size = 96
	exit_label.pixel_size = 0.004
	exit_label.modulate = Color(0.4, 1.0, 0.45)
	exit_label.outline_modulate = Color(0.05, 0.15, 0.05)
	exit_label.outline_size = 16
	var x := _exit_pos.x
	var y := _exit_pos.y + 2.4
	if not _exit_cells.is_empty():
		x = float(_exit_cells[0].x)
		var top := _exit_cells[0].y
		for c in _exit_cells:
			top = maxi(top, c.y)
		y = float(top) + 1.0
	exit_label.position = Vector3(x, y, BlockGrid.WALL_DEPTH * 0.5 + 0.1)
	add_child(exit_label)


## Orthographic camera fitted to the grid width, tilted slightly for depth.
func _build_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	var cam_def: Variant = level.get("camera")
	var width := float(grid.cols) + 1.0
	var centre := Vector2((grid.cols - 1) * 0.5, (grid.rows - 1) * 0.5)
	if cam_def is Array and (cam_def as Array).size() >= 3:
		var a: Array = cam_def
		centre = Vector2(float(a[0]), float(a[1]))
		width = float(a[2])
	camera.size = width
	camera.near = 0.1
	camera.far = 100.0
	camera.rotation_degrees = CAMERA_TILT
	# Look at the level centre on the gameplay plane (z = 0).
	camera.position = Vector3(centre.x, centre.y, 0.0) + camera.basis.z * CAMERA_DISTANCE
	add_child(camera)
	camera.make_current()


func _build_hud() -> void:
	hud = Hud.new()
	add_child(hud)
	hud.set_title("%d. %s" % [level_index, String(level.get("name", ""))])
	hud.restart_pressed.connect(restart)
	hud.next_pressed.connect(next_level)


# ------------------------------------------------------------------- input --

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index != 0:
			return
		if touch.pressed:
			_touch_down = true
			_touch_start = touch.position
			_touch_moved = 0.0
		elif _touch_down:
			_touch_down = false
			# Short touch without much movement = tap.
			if _touch_moved < TAP_MAX_MOVE and state == State.PLAYING:
				_pending_taps.append(touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != 0 or not _touch_down:
			return
		_touch_moved += drag.relative.length()
		if state == State.PLAYING and not cloths.is_empty():
			var a := _screen_to_plane(drag.position - drag.relative, Cloth.Z)
			var b := _screen_to_plane(drag.position, Cloth.Z)
			for cloth in cloths:
				cloth.try_swipe(a, b)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_handle_debug_key(key.keycode)


## R restarts. In debug builds N / P jump to the next / previous level.
func _handle_debug_key(keycode: Key) -> void:
	if keycode == KEY_R:
		restart()
	elif OS.is_debug_build() and keycode == KEY_N and LevelLoader.exists(level_index + 1):
		GameState.current_level = level_index + 1
		restart()
	elif OS.is_debug_build() and keycode == KEY_P and level_index > 1:
		GameState.current_level = level_index - 1
		restart()


## Projects a screen point onto the plane z = plane_z (world X/Y).
func _screen_to_plane(screen_pos: Vector2, plane_z: float) -> Vector2:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.z) < 0.0001:
		return Vector2(from.x, from.y)
	var t := (plane_z - from.z) / dir.z
	var p := from + dir * t
	return Vector2(p.x, p.y)


## Raycasts are done in the physics step (safe with Jolt).
func _physics_process(delta: float) -> void:
	while not _pending_taps.is_empty():
		_handle_tap(_pending_taps.pop_front())
	if state == State.PLAYING:
		_check_rules(delta)


func _handle_tap(screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysLayers.BLOCKS)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var block := hit.get("collider") as Block
	if block != null:
		tap_block(block)


## Taps a block unless a cloth hides it. Public so tests/hints can use it.
func tap_block(block: Block) -> bool:
	for cloth in cloths:
		if cloth.covers(block.cell):
			cloth.nudge()
			return false
	return grid.tap(block)


func _on_group_removed(count: int) -> void:
	# Bigger groups feel heavier.
	Haptics.play("medium" if count >= 5 else "light")
	shake(0.04 + 0.012 * minf(count, 8), 0.18)
	taps += 1
	hud.set_taps(taps)
	grid.clear_hints()
	_wake_physics()


func _wake_physics() -> void:
	hazard.wake_all()
	for plank in planks:
		plank.wake()


# ------------------------------------------------------------------- rules --

func _check_rules(delta: float) -> void:
	# Caught = several hazard bodies at once, or any contact that lingers.
	var contacts := thief.hazard_contacts()
	_touch_time = _touch_time + delta if contacts > 0 else 0.0
	if contacts >= hazard.lose_contacts or _touch_time >= TOUCH_LOSE_SECONDS:
		_lose()
		return
	var safe_count := safe_zone.get_overlapping_bodies().size()
	if thief.hazard_near() > 0:
		thief.set_state(Thief.State.SCARED)
	else:
		thief.set_state(Thief.State.IDLE)
	if safe_count >= hazard.win_count and grid.cells_clear(_exit_cells):
		_win_hold += delta
		if _win_hold >= WIN_HOLD_SECONDS:
			_win()
	else:
		_win_hold = 0.0


func _win() -> void:
	state = State.WON
	grid.clear_hints()
	AudioManager.play("win")
	AudioManager.duck_music(2.0)
	Haptics.win()
	thief.run_to(_exit_pos.x)


func _lose() -> void:
	state = State.LOST
	grid.clear_hints()
	AudioManager.play("lose")
	AudioManager.play("thud", -4.0)
	AudioManager.duck_music(2.0)
	Haptics.lose()
	shake(0.35, 0.5)
	thief.die()


func _on_thief_escaped() -> void:
	var stars := stars_for_taps(taps)
	GameState.complete_level(level_index, stars)
	hud.show_win(stars, GameState.has_next_level(level_index) and LevelLoader.exists(level_index + 1))


func _on_thief_died() -> void:
	await get_tree().create_timer(0.6).timeout
	hud.show_lose()


func _on_hazard_impact(strength: float) -> void:
	shake(0.12 + 0.3 * strength, 0.3)
	Haptics.play("heavy" if strength > 0.5 else "medium")


## Screen shake: offsets the camera's projection (doesn't move the world).
func shake(strength: float, duration: float) -> void:
	if strength >= _shake_strength * (_shake_time / maxf(_shake_duration, 0.001)):
		_shake_strength = strength
		_shake_duration = duration
		_shake_time = duration


func _process(delta: float) -> void:
	if _shake_time > 0.0:
		_shake_time = maxf(_shake_time - delta, 0.0)
		var k := _shake_strength * (_shake_time / _shake_duration)
		camera.h_offset = randf_range(-k, k)
		camera.v_offset = randf_range(-k, k)


func stars_for_taps(tap_count: int) -> int:
	var limits: Array = level.get("stars", [3, 5])
	if tap_count <= int(limits[0]):
		return 3
	if limits.size() > 1 and tap_count <= int(limits[1]):
		return 2
	return 1


func restart() -> void:
	AudioManager.stop_all_loops()
	get_tree().reload_current_scene()


func next_level() -> void:
	GameState.current_level = level_index + 1
	restart()
