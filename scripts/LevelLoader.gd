class_name LevelLoader
## Loads level data from res://levels/level_XX.json.
##
## Level format (all coordinates in world units == grid cells, y up,
## cell (c, r) centred at (c, r)):
##   name        : String
##   grid        : Array[String], TOP row first ('#', '.', R, B, Y, G)
##   walls       : Array of {"rect": [cx, cy, w, h], "angle": deg}  (ramps etc.)
##   hazard      : {"type": "rocks"|"boulder"|"lava", "count": int,
##                  "spawn": [x, y, w, h] (min corner), "win_ratio": 0..1,
##                  "lose_contacts": int}
##   thief       : [x, y]  feet position
##   exit        : [x, y]  where the thief runs to
##   exit_cells  : [[c, r], ...]  blocks that must be cleared to open the exit
##   safe_zone   : [x, y, w, h] (min corner) drain area that counts as safe
##   stars       : [taps_for_3, taps_for_2]
##   hints       : [[c, r], ...] solution taps in order (for the hint button)

const LEVEL_DIR := "res://levels/"


static func path_for(index: int) -> String:
	return "%slevel_%02d.json" % [LEVEL_DIR, index]


static func exists(index: int) -> bool:
	return FileAccess.file_exists(path_for(index))


static func load_level(index: int) -> Dictionary:
	var path := path_for(index)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("LevelLoader: cannot read %s" % path)
		return {}
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("LevelLoader: %s is not a valid JSON object" % path)
		return {}
	return data


# Helpers to read typed values from JSON arrays (JSON numbers are floats).

static func to_v2(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		var a: Array = value
		return Vector2(float(a[0]), float(a[1]))
	return fallback


static func to_rect(value: Variant) -> Rect2:
	if value is Array and (value as Array).size() >= 4:
		var a: Array = value
		return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return Rect2()


static func to_cells(value: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if value is Array:
		for item: Variant in value:
			var v := to_v2(item)
			out.append(Vector2i(roundi(v.x), roundi(v.y)))
	return out
