extends Node
## Central material + mesh factory.
## Textures are loaded from res://assets/textures/<file_name>. When a PNG is
## missing, a procedural fallback (seamless noise wood grain, stone, etc.) is
## generated so the game looks decent before any art exists. When a PNG is
## present it is used automatically, plus a normal map generated from it.

const TEX_DIR := "res://assets/textures/"

## Block colour ids: 0 red, 1 blue, 2 yellow, 3 green.
const BLOCK_COLORS: Array[Color] = [
	Color(0.93, 0.18, 0.16),
	Color(0.15, 0.45, 0.97),
	Color(1.0, 0.78, 0.1),
	Color(0.22, 0.78, 0.28),
]
const BLOCK_TEXTURES: Array[String] = [
	"block_red.png", "block_blue.png", "block_yellow.png", "block_green.png",
]

var _cache: Dictionary = {}
## Phones skip normal maps on the large wood surfaces (big fill-rate saving).
var _mobile: bool = OS.has_feature("mobile")


# ---------------------------------------------------------------- textures --

## Returns the texture res://assets/textures/<file_name> or null if it doesn't exist.
func texture(file_name: String) -> Texture2D:
	var key := "tex:" + file_name
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var path := TEX_DIR + file_name
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[key] = tex
	return tex


## Builds a normal map from a texture's brightness (bump -> normal).
## Returns null if the image can't be read (e.g. unsupported compression).
func normal_from_texture(tex: Texture2D, strength: float = 4.0) -> Texture2D:
	var key := "nrm:%s:%s" % [tex.resource_path, strength]
	if _cache.has(key):
		return _cache[key]
	var result: Texture2D = null
	var img := tex.get_image()
	if img != null:
		var ok := true
		if img.is_compressed():
			ok = img.decompress() == OK
		if ok:
			if img.get_width() > 512:
				img.resize(512, maxi(1, int(512.0 * img.get_height() / img.get_width())))
			img.convert(Image.FORMAT_RGBA8)
			img.bump_map_to_normal_map(strength)
			img.generate_mipmaps()
			result = ImageTexture.create_from_image(img)
	_cache[key] = result
	return result


## Seamless procedural noise texture. width/height ratio stretches the noise,
## which is how the wood grain streaks are made.
func noise_texture(width: int, height: int, frequency: float, ramp: Gradient,
		noise_seed: int, ridged: bool = false, as_normal: bool = false,
		bump: float = 6.0) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.seed = noise_seed
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = width
	t.height = height
	t.seamless = true
	t.noise = n
	if as_normal:
		t.as_normal_map = true
		t.bump_strength = bump
	else:
		t.color_ramp = ramp
	return t


func gradient(colors: PackedColorArray, offsets: PackedFloat32Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	return g


# --------------------------------------------------------------- materials --

## Light carved wood used for walls ('#' cells, ramps).
func wood_wall() -> StandardMaterial3D:
	return _wood("wood_wall.png", Color(0.72, 0.47, 0.26), Color(0.45, 0.26, 0.12), 11, 0.5)


## Dark wood used for the back panel of the chamber.
func wood_wall_dark() -> StandardMaterial3D:
	return _wood("wood_wall_dark.png", Color(0.36, 0.21, 0.11), Color(0.19, 0.1, 0.05), 23, 0.35)


## Plank wood (step 3).
func wood_plank() -> StandardMaterial3D:
	return _wood("wood_plank.png", Color(0.82, 0.58, 0.32), Color(0.55, 0.33, 0.16), 37, 0.6)


func _wood(file_name: String, light: Color, dark: Color, noise_seed: int,
		uv_scale: float) -> StandardMaterial3D:
	var key := "mat:" + file_name
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var tex := texture(file_name)
	if tex != null:
		m.albedo_texture = tex
		m.normal_texture = normal_from_texture(tex, 3.0)
	else:
		# Grain: ridged noise squeezed vertically (64 x 512) = long horizontal streaks.
		var ramp := gradient(
			PackedColorArray([dark, light.lerp(dark, 0.35), light, light.lerp(dark, 0.2)]),
			PackedFloat32Array([0.0, 0.35, 0.7, 1.0]))
		m.albedo_texture = noise_texture(64, 512, 0.045, ramp, noise_seed, true)
		m.normal_texture = noise_texture(64, 512, 0.045, null, noise_seed, true, true, 4.0)
	m.normal_enabled = m.normal_texture != null and not _mobile
	m.normal_scale = 0.7
	m.roughness = 0.78
	# World triplanar so merged wall boxes of any size line up seamlessly.
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


## Glossy cube material for a block colour id.
func block(color_id: int) -> StandardMaterial3D:
	var key := "mat:block:%d" % color_id
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var tex := texture(BLOCK_TEXTURES[color_id])
	if tex != null:
		m.albedo_texture = tex
		m.normal_texture = normal_from_texture(tex, 1.5)
	else:
		m.albedo_color = BLOCK_COLORS[color_id]
		m.albedo_texture = _block_detail()
		m.normal_texture = noise_texture(128, 128, 0.06, null, 5, false, true, 1.5)
	m.normal_enabled = m.normal_texture != null
	m.normal_scale = 0.35
	m.roughness = 0.24
	m.metallic_specular = 0.6
	m.clearcoat_enabled = true
	m.clearcoat = 0.7
	m.clearcoat_roughness = 0.12
	m.rim_enabled = true
	m.rim = 0.2
	m.rim_tint = 0.6
	# Local triplanar so every face of the cube shows the full texture.
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * 1.06
	m.uv1_offset = Vector3.ONE * 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


## Subtle grey speckle multiplied over the block colour.
func _block_detail() -> Texture2D:
	var key := "tex:block_detail"
	if not _cache.has(key):
		var ramp := gradient(
			PackedColorArray([Color(0.78, 0.78, 0.78), Color(1, 1, 1)]),
			PackedFloat32Array([0.0, 1.0]))
		_cache[key] = noise_texture(128, 128, 0.05, ramp, 3)
	return _cache[key]


## Rough stone for rocks and the boulder. Uses vertex/instance colour as tint.
func stone() -> StandardMaterial3D:
	var key := "mat:stone"
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var tex := texture("stone.png")
	if tex != null:
		m.albedo_texture = tex
		m.normal_texture = normal_from_texture(tex, 5.0)
	else:
		var ramp := gradient(
			PackedColorArray([Color(0.32, 0.3, 0.29), Color(0.55, 0.52, 0.48), Color(0.7, 0.67, 0.62)]),
			PackedFloat32Array([0.0, 0.55, 1.0]))
		m.albedo_texture = noise_texture(128, 128, 0.08, ramp, 9)
		m.normal_texture = noise_texture(128, 128, 0.08, null, 9, false, true, 8.0)
	m.normal_enabled = m.normal_texture != null
	m.normal_scale = 1.0
	m.roughness = 0.95
	m.vertex_color_use_as_albedo = true
	m.uv1_scale = Vector3(2.0, 1.0, 1.0)
	_cache[key] = m
	return m


## Back stone floor tint for the safe drain pit.
func pit() -> StandardMaterial3D:
	var key := "mat:pit"
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var tex := texture("pit/pit_albedo.png")
	if tex != null:
		# PBR cave-floor set (assets/textures/pit/). Darkened so the pit reads
		# as a deep hole behind the wooden walls.
		m.albedo_texture = tex
		m.albedo_color = Color(0.62, 0.55, 0.5)
		m.normal_texture = texture("pit/pit_normal.png")
		m.normal_enabled = m.normal_texture != null
		m.normal_scale = 1.2
		m.roughness_texture = texture("pit/pit_roughness.png")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness = 1.0
		m.ao_texture = texture("pit/pit_ao.png")
		m.ao_enabled = m.ao_texture != null
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.uv1_scale = Vector3.ONE * 0.22
	else:
		m.albedo_color = Color(0.13, 0.11, 0.1)
		m.albedo_texture = stone().albedo_texture
		m.roughness = 1.0
		m.uv1_scale = Vector3.ONE * 0.5
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


## Glowing outline drawn over a block for hints (used as material_overlay).
func outline() -> StandardMaterial3D:
	var key := "mat:outline"
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = 0.07
	# HDR colour (> 1) so the WorldEnvironment glow makes it shine.
	m.albedo_color = Color(2.2, 1.9, 0.6)
	_cache[key] = m
	return m


## Simple solid colour material.
func solid(color: Color, roughness: float = 0.6) -> StandardMaterial3D:
	var key := "mat:solid:%s:%s" % [color.to_html(), roughness]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	_cache[key] = m
	return m


## Horizontal stripes for the thief's shirt (stripes follow the mesh's local Y).
func striped(color_a: Color, color_b: Color, stripes: float) -> ShaderMaterial:
	var key := "mat:stripes:%s:%s:%s" % [color_a.to_html(), color_b.to_html(), stripes]
	if _cache.has(key):
		return _cache[key]
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform vec4 color_a : source_color = vec4(0.95, 0.95, 0.95, 1.0);
uniform vec4 color_b : source_color = vec4(0.08, 0.08, 0.1, 1.0);
uniform float stripes = 7.0;
varying float local_y;
void vertex() {
	local_y = VERTEX.y;
}
void fragment() {
	float v = fract(local_y * stripes);
	float w = fwidth(local_y * stripes) * 1.5;
	float s = smoothstep(0.5 - w, 0.5 + w, v);
	ALBEDO = mix(color_a.rgb, color_b.rgb, s);
	ROUGHNESS = 0.85;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("color_a", color_a)
	m.set_shader_parameter("color_b", color_b)
	m.set_shader_parameter("stripes", stripes)
	_cache[key] = m
	return m


# ------------------------------------------------------------------ meshes --

## Rounded cube: a subdivided BoxMesh whose vertices are pushed onto a
## rounded-box surface. Subdivisions are biased toward the edges so the
## bevel looks smooth with few triangles.
func rounded_box(size: Vector3, radius: float, subdiv: int = 6) -> Mesh:
	var key := "mesh:rbox:%s:%s:%d" % [size, radius, subdiv]
	if _cache.has(key):
		return _cache[key]
	var box := BoxMesh.new()
	box.size = size
	box.subdivide_width = subdiv
	box.subdivide_height = subdiv
	box.subdivide_depth = subdiv
	var arrays := box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var half := size * 0.5
	var inner := half - Vector3.ONE * radius
	for i in verts.size():
		var p := verts[i]
		# Bias each coordinate toward the faces' edges.
		p = Vector3(_bias(p.x, half.x), _bias(p.y, half.y), _bias(p.z, half.z))
		var core := p.clamp(-inner, inner)
		var d := p - core
		var n := d.normalized() if d.length() > 0.0001 else normals[i]
		verts[i] = core + n * radius
		normals[i] = n
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[key] = mesh
	return mesh


func _bias(v: float, half: float) -> float:
	if half <= 0.0:
		return v
	var u := clampf(v / half, -1.0, 1.0)
	return signf(u) * pow(absf(u), 0.3) * half


## Irregular stone mesh (radius ~1): a sphere displaced by 3D noise.
## faceted = true gives flat-shaded low-poly rocks; false gives a smooth boulder.
func rock_mesh(faceted: bool, radial: int, rings: int, amount: float, noise_seed: int) -> Mesh:
	var key := "mesh:rock:%s:%d:%d:%s:%d" % [faceted, radial, rings, amount, noise_seed]
	if _cache.has(key):
		return _cache[key]
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = radial
	sphere.rings = rings
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.frequency = 0.9
	for i in verts.size():
		var v := verts[i]
		# Same position -> same displacement, so UV-seam duplicates stay welded.
		verts[i] = v * (1.0 - amount * 0.5 + amount * (n.get_noise_3dv(v * 1.7) * 0.5 + 0.5))
	arrays[Mesh.ARRAY_VERTEX] = verts
	var base := ArrayMesh.new()
	base.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(base, 0)
	if faceted:
		st.deindex()  # Unique vertices per triangle -> flat facets.
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## Animated lava: world-space noise so overlapping balls blend into one liquid.
## Bright HDR emission (> 1) makes the WorldEnvironment glow bloom it.
func lava() -> ShaderMaterial:
	var key := "mat:lava"
	if _cache.has(key):
		return _cache[key]
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D lava_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_lava_tex = false;
uniform float emission_strength = 2.1;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xy;
	float n1 = texture(noise_tex, p * 0.22 + vec2(TIME * 0.03, TIME * 0.05)).r;
	float n2 = texture(noise_tex, p * 0.55 - vec2(TIME * 0.06, -TIME * 0.02)).r;
	float heat = clamp(n1 * 0.65 + n2 * 0.55 - 0.1, 0.0, 1.0);
	// Dark cooled crust floats on top of the hot flow.
	float crust = smoothstep(0.42, 0.28, heat);
	vec3 hot;
	if (use_lava_tex) {
		hot = texture(lava_tex, p * 0.25 + vec2(TIME * 0.02, TIME * 0.04)).rgb * 1.3;
	} else {
		hot = mix(vec3(0.95, 0.18, 0.01), vec3(1.0, 0.7, 0.18), smoothstep(0.5, 0.95, heat));
	}
	vec3 crust_col = vec3(0.16, 0.05, 0.02);
	// Brighter towards the silhouette so blobs read as a rounded surface.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = mix(hot * 0.55, crust_col, crust);
	EMISSION = hot * emission_strength * (1.0 - crust * 0.85) * (0.85 + rim * 0.6);
	ROUGHNESS = mix(0.25, 0.9, crust);
	SPECULAR = 0.6;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	var ramp := gradient(PackedColorArray([Color.BLACK, Color.WHITE]), PackedFloat32Array([0.0, 1.0]))
	m.set_shader_parameter("noise_tex", noise_texture(256, 256, 0.012, ramp, 77))
	var tex := texture("lava.png")
	if tex != null:
		m.set_shader_parameter("lava_tex", tex)
		m.set_shader_parameter("use_lava_tex", true)
	_cache[key] = m
	return m


## Fabric cover with wind sway and a ragged dissolve used when it's torn.
## Returns a NEW material each call (each cloth animates its own dissolve).
func fabric() -> ShaderMaterial:
	var shader: Shader = _cache.get("shader:fabric")
	if shader == null:
		shader = Shader.new()
		shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D fabric_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_fabric_tex = false;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(0.62, 0.1, 0.12, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.95, 0.75, 0.3, 1.0);
uniform vec2 size = vec2(4.0, 4.0);
uniform float dissolve = 0.0;
uniform vec2 tear_origin = vec2(0.5, 0.5);
uniform float sway = 1.0;

void vertex() {
	// Pinned along the top edge (UV.y = 0), billows more towards the bottom.
	float w = sin(TIME * 1.8 + VERTEX.x * 1.3) * 0.06 + sin(TIME * 2.9 + VERTEX.y * 2.1) * 0.03;
	VERTEX.z += w * UV.y * sway;
}

void fragment() {
	vec2 uvw = UV * size;
	vec3 col;
	if (use_fabric_tex) {
		col = texture(fabric_tex, uvw * 0.5).rgb;
	} else {
		// Woven threads + a golden border stripe.
		vec2 g = uvw * 22.0;
		float weave = 0.86 + 0.14 * sin(g.x * 3.1416) * sin(g.y * 3.1416);
		col = base_color.rgb * weave;
		float border = step(min(min(UV.x, 1.0 - UV.x) * size.x, min(UV.y, 1.0 - UV.y) * size.y), 0.22);
		float inner = step(min(min(UV.x, 1.0 - UV.x) * size.x, min(UV.y, 1.0 - UV.y) * size.y), 0.12);
		col = mix(col, stripe_color.rgb * weave, border - inner);
	}
	// Soft vertical folds.
	float n = texture(noise_tex, UV * 0.8).r;
	col *= 0.78 + 0.22 * sin(UV.x * size.x * 5.0 + n * 4.0);
	// Ragged tear spreading from where the player swiped.
	float d = distance(UV * size, tear_origin * size) / max(size.x, size.y) + n * 0.35;
	float cut = dissolve * 1.5;
	if (dissolve > 0.0 && d < cut) {
		discard;
	}
	float edge = 1.0 - smoothstep(cut, cut + 0.05, d);
	ALBEDO = mix(col, vec3(0.95, 0.88, 0.7), edge * step(0.001, dissolve));
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
"""
		_cache["shader:fabric"] = shader
	var m := ShaderMaterial.new()
	m.shader = shader
	var ramp := gradient(PackedColorArray([Color.BLACK, Color.WHITE]), PackedFloat32Array([0.0, 1.0]))
	if not _cache.has("tex:fabric_noise"):
		_cache["tex:fabric_noise"] = noise_texture(128, 128, 0.05, ramp, 13)
	m.set_shader_parameter("noise_tex", _cache["tex:fabric_noise"])
	var tex := texture("fabric.png")
	if tex != null:
		m.set_shader_parameter("fabric_tex", tex)
		m.set_shader_parameter("use_fabric_tex", true)
	return m


## Dark iron for pins, brackets and lantern frames.
func iron() -> StandardMaterial3D:
	var key := "mat:iron"
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.15, 0.15)
	m.metallic = 0.85
	m.roughness = 0.4
	_cache[key] = m
	return m


## Unshaded HDR glow material (lantern flame, etc.).
func glow(color: Color, energy: float) -> StandardMaterial3D:
	var key := "mat:glow:%s:%s" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy)
	_cache[key] = m
	return m
