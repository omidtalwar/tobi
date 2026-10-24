class_name Hud
extends CanvasLayer
## In-game HUD: level name, tap counter, restart, and win/lose popups.
## (Step 5 adds pause, hint and the ad-retry button.)

signal restart_pressed
signal next_pressed

var _taps_label: Label
var _title_label: Label
var _popup_layer: Control


func _ready() -> void:
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 30
	bar.offset_right = -30
	bar.offset_top = 40
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 20)
	root.add_child(bar)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 50)
	bar.add_child(_title_label)

	_taps_label = Label.new()
	_taps_label.add_theme_font_size_override("font_size", 50)
	bar.add_child(_taps_label)

	var restart := UiTheme.make_button("Restart", Vector2(120, 110))
	restart.pressed.connect(restart_pressed.emit)
	bar.add_child(restart)

	_popup_layer = Control.new()
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_popup_layer)
	set_taps(0)


func set_title(text: String) -> void:
	_title_label.text = text


func set_taps(taps: int) -> void:
	_taps_label.text = "Taps: %d" % taps


func show_win(stars: int, has_next: bool) -> void:
	var box := _popup("ESCAPED!")
	var star_label := Label.new()
	star_label.text = "★".repeat(stars) + "☆".repeat(3 - stars)
	star_label.add_theme_font_size_override("font_size", 120)
	star_label.add_theme_color_override("font_color", UiTheme.GOLD)
	star_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(star_label)
	var row := _button_row(box)
	var retry := UiTheme.make_button("Retry")
	retry.pressed.connect(restart_pressed.emit)
	row.add_child(retry)
	if has_next:
		var next := UiTheme.make_button("Next")
		next.pressed.connect(next_pressed.emit)
		row.add_child(next)


func show_lose() -> void:
	var box := _popup("CAUGHT!")
	var row := _button_row(box)
	var retry := UiTheme.make_button("Retry")
	retry.pressed.connect(restart_pressed.emit)
	row.add_child(retry)


## Dimmed full-screen popup with a centred wooden panel. Returns its VBox.
func _popup(title: String) -> VBoxContainer:
	for c in _popup_layer.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 30)
	panel.add_child(box)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 90)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	UiTheme.pop_in.call_deferred(panel)
	AudioManager.play("swoosh")
	return box


func _button_row(box: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	box.add_child(row)
	return row
