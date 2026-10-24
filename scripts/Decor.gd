class_name Decor
## Atmosphere pieces: lanterns with flickering warm light, floating dust
## motes and a screen vignette. All cheap enough for mobile.


## Iron lantern on a bracket with a flickering OmniLight3D (no shadows).
static func add_lantern(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	root.scale = Vector3.ONE * 1.8
	parent.add_child(root)

	var bracket := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.5, 0.08)
	bracket.mesh = bm
	bracket.material_override = Materials.iron()
	bracket.position = Vector3(0, 0.45, 0)
	root.add_child(bracket)

	var cage := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16
	cm.bottom_radius = 0.2
	cm.height = 0.45
	cm.radial_segments = 6
	cage.mesh = cm
	cage.material_override = Materials.iron()
	cage.transparency = 0.55
	root.add_child(cage)

	var flame := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.1
	fm.height = 0.24
	flame.mesh = fm
	flame.material_override = Materials.glow(Color(1.0, 0.65, 0.25), 3.0)
	root.add_child(flame)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.68, 0.35)
	light.light_energy = 1.5
	light.omni_range = 5.0
	light.omni_attenuation = 1.4
	light.position = Vector3(0, 0, 0.6)
	root.add_child(light)

	# Endless irregular flicker.
	var tw := light.create_tween().set_loops()
	for i in 4:
		tw.tween_property(light, "light_energy", randf_range(1.25, 1.75), randf_range(0.08, 0.22))
	var ftw := flame.create_tween().set_loops()
	ftw.tween_property(flame, "scale", Vector3(1.0, 1.25, 1.0), 0.15)
	ftw.tween_property(flame, "scale", Vector3(0.9, 0.95, 0.9), 0.2)


## Slow floating dust specks lit by the warm light.
static func add_dust(parent: Node3D, area: Rect2) -> void:
	var p := GPUParticles3D.new()
	p.amount = 36
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.visibility_aabb = AABB(Vector3(-area.size.x, -area.size.y, -2), Vector3(area.size.x * 2, area.size.y * 2, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(area.size.x * 0.5, area.size.y * 0.5, 0.3)
	pm.direction = Vector3(0.3, 1.0, 0.0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.2
	pm.gravity = Vector3(0, 0.02, 0)
	pm.turbulence_enabled = false
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.05
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 0.85, 0.6, 0.5)
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(area.get_center().x, area.get_center().y, 1.2)
	parent.add_child(p)


## Darkened screen corners (CanvasLayer under the HUD).
static func add_vignette(parent: Node) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	parent.add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float strength = 0.6;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.85);
	float v = smoothstep(0.32, 0.8, length(d));
	COLOR = vec4(0.06, 0.02, 0.0, v * strength);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	layer.add_child(rect)
