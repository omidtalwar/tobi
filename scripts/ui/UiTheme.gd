class_name UiTheme
## Wood-themed UI styling. Uses ui_button.png / ui_panel.png from
## res://assets/textures/ as 9-slice textures when present, otherwise
## procedural rounded StyleBoxFlat in warm wood colours.

const WOOD := Color(0.55, 0.33, 0.16)
const WOOD_LIGHT := Color(0.72, 0.47, 0.24)
const WOOD_DARK := Color(0.3, 0.17, 0.08)
const CREAM := Color(1.0, 0.94, 0.8)
const GOLD := Color(1.0, 0.8, 0.2)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 44
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_outline_color", "Label", WOOD_DARK)
	t.set_constant("outline_size", "Label", 10)

	t.set_stylebox("normal", "Button", button_box(WOOD))
	t.set_stylebox("hover", "Button", button_box(WOOD_LIGHT))
	t.set_stylebox("pressed", "Button", button_box(WOOD_DARK))
	t.set_stylebox("disabled", "Button", button_box(Color(0.35, 0.3, 0.27)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", CREAM)
	t.set_color("font_outline_color", "Button", WOOD_DARK)
	t.set_constant("outline_size", "Button", 8)
	t.set_font_size("font_size", "Button", 46)

	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	_theme = t
	return t


static func button_box(color: Color) -> StyleBox:
	var tex := Materials.texture("ui_button.png")
	if tex != null:
		var sbt := StyleBoxTexture.new()
		sbt.texture = tex
		_set_margins(sbt, 40.0)
		sbt.modulate_color = Color.WHITE.lerp(color, 0.25) if color != WOOD else Color.WHITE
		sbt.content_margin_left = 36
		sbt.content_margin_right = 36
		sbt.content_margin_top = 18
		sbt.content_margin_bottom = 22
		return sbt
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(28)
	sb.border_color = WOOD_DARK
	sb.set_border_width_all(6)
	sb.border_width_bottom = 12  # Chunky bottom edge = 3D button look.
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 6)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 18
	sb.content_margin_bottom = 22
	return sb


static func panel_box() -> StyleBox:
	var tex := Materials.texture("ui_panel.png")
	if tex != null:
		var sbt := StyleBoxTexture.new()
		sbt.texture = tex
		_set_margins(sbt, 64.0)
		sbt.content_margin_left = 60
		sbt.content_margin_right = 60
		sbt.content_margin_top = 50
		sbt.content_margin_bottom = 50
		return sbt
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.42, 0.25, 0.12, 0.97)
	sb.set_corner_radius_all(40)
	sb.border_color = Color(0.85, 0.6, 0.3)
	sb.set_border_width_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	sb.content_margin_left = 60
	sb.content_margin_right = 60
	sb.content_margin_top = 50
	sb.content_margin_bottom = 50
	return sb


static func _set_margins(sbt: StyleBoxTexture, m: float) -> void:
	sbt.texture_margin_left = m
	sbt.texture_margin_right = m
	sbt.texture_margin_top = m
	sbt.texture_margin_bottom = m


## Press/hover bounce for any button. Plays the click sound.
static func animate_button(button: Button) -> void:
	button.pivot_offset = button.size * 0.5
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	button.button_down.connect(func() -> void:
		var tw := button.create_tween()
		tw.tween_property(button, "scale", Vector2.ONE * 0.9, 0.06))
	button.button_up.connect(func() -> void:
		var tw := button.create_tween()
		tw.tween_property(button, "scale", Vector2.ONE, 0.25) \
				.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	button.pressed.connect(func() -> void:
		AudioManager.play("click")
		Haptics.play("tick"))


static func make_button(text: String, min_size: Vector2 = Vector2(220, 120)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	animate_button(b)
	return b


## Pops a control in with a bouncy scale.
static func pop_in(control: Control) -> void:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * 0.6
	control.modulate.a = 0.0
	var tw := control.create_tween().set_parallel()
	tw.tween_property(control, "scale", Vector2.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(control, "modulate:a", 1.0, 0.2)
