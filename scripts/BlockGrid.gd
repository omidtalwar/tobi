class_name BlockGrid
extends Node3D
## Builds the level grid: wooden wall cells ('#') and coloured blocks.
## Handles flood-fill removal and block gravity.
##
## Grid strings are listed TOP row first. Cell (col, row) has its centre at
## world (col, row) with row 0 at the bottom, so level coordinates == world.
## Characters: '#' wall, '.' empty, R/B/Y/G coloured blocks.

signal group_removed(count: int)
signal single_tapped
signal settled  ## Emitted when all fall animations of a removal are done.

const COLOR_CHARS := {"R": 0, "B": 1, "Y": 2, "G": 3}
const WALL_DEPTH := 1.5
const NEIGHBOURS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var cols: int = 0
var rows: int = 0
var blocks: Dictionary = {}  # Vector2i -> Block
var solid: Dictionary = {}   # Vector2i -> true for wall cells

var _busy_time: float = 0.0
var _walls: StaticBody3D


func build(grid: Array) -> void:
	rows = grid.size()
	for line: Variant in grid:
		cols = maxi(cols, String(line).length())
	for i in rows:
		var line := String(grid[i])
		var r := rows - 1 - i
		for c in line.length():
			var ch := line[c]
			var cell := Vector2i(c, r)
			if ch == "#":
				solid[cell] = true
			elif COLOR_CHARS.has(ch):
				_spawn_block(int(COLOR_CHARS[ch]), cell)
	_build_walls()
	# Normalise authoring mistakes: floating blocks drop instantly.
	for move: Array in _compute_gravity():
		var b: Block = move[0]
		var target: Vector2i = move[1]
		b.cell = target
		b.position = Vector3(target.x, target.y, 0.0)
		blocks[target] = b


func _spawn_block(color_id: int, cell: Vector2i) -> void:
	var b := Block.new()
	b.name = "Block_%d_%d" % [cell.x, cell.y]
	b.setup(color_id, cell)
	add_child(b)
	blocks[cell] = b


## Greedy-merges '#' cells into as few rectangles as possible: fewer physics
## shapes and draw calls, and the bevel seams read as carved wooden panels.
func _build_walls() -> void:
	_walls = StaticBody3D.new()
	_walls.name = "Walls"
	_walls.collision_layer = PhysLayers.WORLD
	_walls.collision_mask = 0
	add_child(_walls)
	var mat := Materials.wood_wall()
	var used: Dictionary = {}
	for r in rows:
		for c in cols:
			var start := Vector2i(c, r)
			if not solid.has(start) or used.has(start):
				continue
			var w := 1
			while _free_wall(Vector2i(c + w, r), used):
				w += 1
			var h := 1
			while _free_wall_row(c, r + h, w, used):
				h += 1
			for y in range(r, r + h):
				for x in range(c, c + w):
					used[Vector2i(x, y)] = true
			var centre := Vector3(c + w * 0.5 - 0.5, r + h * 0.5 - 0.5, 0.0)
			add_wall_box(_walls, centre, Vector3(w, h, WALL_DEPTH), 0.0, mat)


func _free_wall(cell: Vector2i, used: Dictionary) -> bool:
	return solid.has(cell) and not used.has(cell)


func _free_wall_row(c: int, r: int, w: int, used: Dictionary) -> bool:
	for x in range(c, c + w):
		if not _free_wall(Vector2i(x, r), used):
			return false
	return true


## Adds one bevelled wooden box (mesh + exact box collision) to `body`.
## Also used for ramps and ledges from the level's "walls" list.
static func add_wall_box(body: StaticBody3D, centre: Vector3, box_size: Vector3,
		angle_deg: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bevel := minf(0.14, minf(box_size.x, box_size.y) * 0.3)
	mi.mesh = Materials.rounded_box(box_size, bevel, 5)
	mi.material_override = mat
	mi.position = centre
	mi.rotation.z = deg_to_rad(angle_deg)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	cs.shape = shape
	cs.position = centre
	cs.rotation.z = deg_to_rad(angle_deg)
	body.add_child(cs)


func is_busy() -> bool:
	return _busy_time > 0.0


func _physics_process(delta: float) -> void:
	if _busy_time > 0.0:
		_busy_time -= delta
		if _busy_time <= 0.0:
			settled.emit()


## Called by Game when the player taps a block. Returns true if a group popped.
func tap(block: Block) -> bool:
	if block.removed or is_busy():
		return false
	var group := find_group(block.cell)
	if group.size() < 2:
		block.wobble()
		AudioManager.play("wobble")
		Haptics.play("tick")
		single_tapped.emit()
		return false
	remove_group(group, block.cell)
	return true


## 4-direction flood fill of same-coloured blocks starting at `start`.
func find_group(start: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not blocks.has(start):
		return result
	var color_id: int = (blocks[start] as Block).color_id
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		result.append(cur)
		for d in NEIGHBOURS:
			var n := cur + d
			if seen.has(n) or not blocks.has(n):
				continue
			if (blocks[n] as Block).color_id == color_id:
				seen[n] = true
				queue.append(n)
	return result


## Pops a group in a ripple from the tapped cell, then drops blocks above.
func remove_group(group: Array[Vector2i], origin: Vector2i) -> void:
	var longest := 0.0
	for cell in group:
		var b: Block = blocks[cell]
		blocks.erase(cell)
		var delay := 0.035 * float(absi(cell.x - origin.x) + absi(cell.y - origin.y))
		longest = maxf(longest, delay)
		b.pop(delay)
	# Staggered pop sounds (max 4 so it doesn't get noisy).
	for i in mini(group.size(), 4):
		get_tree().create_timer(0.05 * i).timeout.connect(
				AudioManager.play.bind("pop", -2.0, 1.0 + 0.08 * i))
	var fall_start := longest + 0.12
	var finish := fall_start + 0.2
	for move: Array in _compute_gravity():
		var b: Block = move[0]
		var target: Vector2i = move[1]
		blocks[target] = b
		finish = maxf(finish, b.fall_to(target, fall_start))
	_busy_time = finish
	group_removed.emit(group.size())


## Returns [[Block, target_cell], ...] for every block that must fall.
## Blocks fall onto other blocks, wall cells or the grid bottom.
## Moved blocks are removed from `blocks`; the caller re-inserts them.
func _compute_gravity() -> Array:
	var moves: Array = []
	for c in cols:
		var landing := 0  # Lowest free row in the current column segment.
		for r in rows:
			var cell := Vector2i(c, r)
			if solid.has(cell):
				landing = r + 1
				continue
			if blocks.has(cell):
				if r != landing:
					var b: Block = blocks[cell]
					blocks.erase(cell)
					moves.append([b, Vector2i(c, landing)])
				landing += 1
	return moves


## True when none of the given cells holds a block (exit door open).
func cells_clear(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if blocks.has(cell):
			return false
	return true


func block_at(cell: Vector2i) -> Block:
	return blocks.get(cell) as Block


func clear_hints() -> void:
	for b: Block in blocks.values():
		b.set_hint(false)


## Highlights the group containing `cell`. Returns false if no valid group there.
func show_hint(cell: Vector2i) -> bool:
	clear_hints()
	var group := find_group(cell)
	if group.size() < 2:
		return false
	for g in group:
		(blocks[g] as Block).set_hint(true)
	return true
