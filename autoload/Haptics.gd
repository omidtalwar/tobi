extends Node
## Phone vibration with named intensities so every feedback in the game feels
## consistent. Silently does nothing on desktop or when disabled in settings.
## Android needs the VIBRATE permission (set in the export preset).

## Duration (ms) and amplitude (0..1) per feedback type.
const PRESETS := {
	"tick": [12, 0.25],     # button press, single block wobble
	"light": [20, 0.45],    # block group pop
	"medium": [35, 0.7],    # cloth tear, big group
	"heavy": [70, 1.0],     # boulder impact
}

var _cooldown_until: float = 0.0


func _can_vibrate() -> bool:
	return GameState.vibration_on and OS.has_feature("mobile")


func play(kind: String) -> void:
	if not _can_vibrate() or not PRESETS.has(kind):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _cooldown_until:
		return  # Avoid a buzzing mess when many events fire together.
	var p: Array = PRESETS[kind]
	_cooldown_until = now + float(p[0]) / 1000.0 + 0.03
	Input.vibrate_handheld(int(p[0]), float(p[1]))


## Short rhythmic patterns: [[ms, amplitude, gap_ms], ...]
func pattern(steps: Array) -> void:
	if not _can_vibrate():
		return
	for step: Variant in steps:
		var s: Array = step
		Input.vibrate_handheld(int(s[0]), float(s[1]))
		await get_tree().create_timer((float(s[0]) + float(s[2])) / 1000.0).timeout


func win() -> void:
	pattern([[25, 0.5, 70], [25, 0.5, 70], [60, 0.8, 0]])


func lose() -> void:
	pattern([[90, 1.0, 60], [140, 0.8, 0]])
