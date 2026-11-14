class_name ToonMaterial
extends RefCounted
## Materials using vfx/shaders/toon.gdshader (soft 3-band ramp + warm rim) for the beans
## (docs/ART_DIRECTION.md: "lightly stylised lit materials, soft toon ramp allowed"). Headless runs
## (dedicated server, tests) get a plain StandardMaterial3D instead, so nothing compiles there.

const SHADER: Shader = preload("res://vfx/shaders/toon.gdshader")
const VERTEX_COLOR_SHADER: Shader = preload("res://vfx/shaders/toon_vertex_color.gdshader")
const CLOTH_SHADER: Shader = preload("res://vfx/shaders/toon_cloth.gdshader")
const SKIN_SHADER: Shader = preload("res://vfx/shaders/bean_skin.gdshader")
## Animated skins (`CosmeticDef.KIND_SKIN`): the shader's `mode` per item, and a flat colour for
## when the toon shaders are off.
const SKIN_MODES: Dictionary = {
	&"skin_gold": 0, &"skin_rainbow": 1, &"skin_lava": 2, &"skin_galaxy": 3,
	&"skin_felt": 4, &"skin_candy": 5, &"skin_ocean": 6, &"skin_marble": 7,
}
const SKIN_FLAT: Array[Color] = [
	Color("#D9AE52"), Color("#C8503A"), Color("#5A2A1E"), Color("#2A2A5A"),
	Color("#275E49"), Color("#E39AA6"), Color("#1F4E6B"), Color("#EDE6DA"),
]

## Off switch (side-by-side comparison shots).
static var enabled: bool = true


## A toon material in `color`, or a StandardMaterial3D when effects are off.
static func make(color: Color, rim: float = 0.3) -> Material:
	if not enabled or not Vfx.enabled():
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.8
		return m
	var s := ShaderMaterial.new()
	s.shader = SHADER
	s.set_shader_parameter(&"albedo", color)
	s.set_shader_parameter(&"rim_strength", rim)
	return s


## The same look coloured by the mesh's vertex colours (outfit pieces, `OutfitMeshes`).
static func make_vertex_colored(rim: float = 0.3) -> Material:
	if not enabled or not Vfx.enabled():
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.8
		return m
	var s := ShaderMaterial.new()
	s.shader = VERTEX_COLOR_SHADER
	s.set_shader_parameter(&"albedo", Color.WHITE)
	s.set_shader_parameter(&"rim_strength", rim)
	return s


## The material of animated skin `id` (null for unknown ids): moving patterns over the bean
## (vfx/shaders/bean_skin.gdshader), or its flat colour when effects are off.
static func make_skin(id: StringName) -> Material:
	var mode: int = SKIN_MODES.get(id, -1)
	if mode < 0:
		return null
	if not enabled or not Vfx.enabled():
		var m := StandardMaterial3D.new()
		m.albedo_color = SKIN_FLAT[mode]
		m.roughness = 0.6
		return m
	var s := ShaderMaterial.new()
	s.shader = SKIN_SHADER
	s.set_shader_parameter(&"mode", mode)
	return s


## A cape's own material: `make_vertex_colored` plus the cloth deformation (`CapeCloth`). Null
## when the toon shaders are off (the cape then just swings).
static func make_cloth(rim: float = 0.3) -> ShaderMaterial:
	if not enabled or not Vfx.enabled():
		return null
	var s := ShaderMaterial.new()
	s.shader = CLOTH_SHADER
	s.set_shader_parameter(&"albedo", Color.WHITE)
	s.set_shader_parameter(&"rim_strength", rim)
	return s


## Recolours a material made by `make`.
static func set_color(mat: Material, color: Color) -> void:
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter(&"albedo", color)
	elif mat is BaseMaterial3D:
		(mat as BaseMaterial3D).albedo_color = color
