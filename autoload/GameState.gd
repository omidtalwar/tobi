extends Node
## Persistent player progress: unlocked levels, best stars and settings.
## Saved to user://save.cfg with ConfigFile.

signal progress_changed

const SAVE_PATH := "user://save.cfg"
const LEVEL_COUNT := 15

## Level the Game scene should load next (1-based).
var current_level: int = 1
## Highest unlocked level (1-based).
var unlocked: int = 1
## Best stars per level: int level -> int stars (0..3).
var stars: Dictionary = {}
var music_on: bool = true
var sfx_on: bool = true
var vibration_on: bool = true


func _ready() -> void:
	load_progress()


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # First launch: keep defaults.
	unlocked = clampi(int(cfg.get_value("progress", "unlocked", 1)), 1, LEVEL_COUNT)
	music_on = bool(cfg.get_value("settings", "music", true))
	sfx_on = bool(cfg.get_value("settings", "sfx", true))
	vibration_on = bool(cfg.get_value("settings", "vibration", true))
	for i in range(1, LEVEL_COUNT + 1):
		stars[i] = int(cfg.get_value("stars", str(i), 0))


func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("settings", "music", music_on)
	cfg.set_value("settings", "sfx", sfx_on)
	cfg.set_value("settings", "vibration", vibration_on)
	for key: Variant in stars.keys():
		cfg.set_value("stars", str(key), int(stars[key]))
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("GameState: could not save progress (error %d)" % err)


func get_stars(level: int) -> int:
	return int(stars.get(level, 0))


func total_stars() -> int:
	var total := 0
	for key: Variant in stars.keys():
		total += int(stars[key])
	return total


func is_unlocked(level: int) -> bool:
	return level <= unlocked


## Records a win. Keeps the best star count and unlocks the next level.
func complete_level(level: int, earned: int) -> void:
	if earned > get_stars(level):
		stars[level] = earned
	unlocked = maxi(unlocked, mini(level + 1, LEVEL_COUNT))
	save_progress()
	progress_changed.emit()


func has_next_level(level: int) -> bool:
	return level < LEVEL_COUNT


func reset_progress() -> void:
	unlocked = 1
	stars.clear()
	save_progress()
	progress_changed.emit()
