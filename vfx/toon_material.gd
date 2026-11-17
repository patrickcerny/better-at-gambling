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
	&"skin_the_house": 8, &"skin_fortune": 9,
	# Achievement rewards (AchievementMeshes).
	&"skin_bronze": 10, &"skin_source": 11, &"skin_crystal": 12,
}
const SKIN_FLAT: Array[Color] = [
	Color("#D9AE52"), Color("#C8503A"), Color("#5A2A1E"), Color("#2A2A5A"),
	Color("#275E49"), Color("#E39AA6"), Color("#1F4E6B"), Color("#EDE6DA"),
	Color("#16100E"), Color("#681F2C"), Color("#9C6A35"), Color("#1A1412"),
	Color("#B9AFCF"),
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


## Animated skin `id` on a casino chip (`ChipStack`, `PlinkoChip`): the bean pattern laid over the
## chip's face (`face_radius` in mesh units; `upright` when the face looks along local Z), `shade`
## darkens it (alternate chips in a stack). The skin's flat colour when effects are off, null for
## unknown ids.
static func make_chip_skin(id: StringName, face_radius: float, upright: bool = false, shade: float = 1.0) -> Material:
	var mode: int = SKIN_MODES.get(id, -1)
	if mode < 0:
		return null
	if not enabled or not Vfx.enabled():
		var m := StandardMaterial3D.new()
		m.albedo_color = SKIN_FLAT[mode].darkened(1.0 - shade)
		m.roughness = 0.6
		return m
	var s := ShaderMaterial.new()
	s.shader = SKIN_SHADER
	s.set_shader_parameter(&"mode", mode)
	s.set_shader_parameter(&"chip", true)
	s.set_shader_parameter(&"chip_face", face_radius)
	s.set_shader_parameter(&"chip_upright", upright)
	s.set_shader_parameter(&"shade", shade)
	s.set_shader_parameter(&"rim_strength", 0.25)
	return s


## The flat colour standing in for skin `id` (`SKIN_FLAT`), transparent for unknown ids.
static func skin_flat(id: StringName) -> Color:
	var mode: int = SKIN_MODES.get(id, -1)
	return SKIN_FLAT[mode] if mode >= 0 else Color(0, 0, 0, 0)


## A cape's own material: `make_vertex_colored` plus the cloth deformation (`CapeCloth`). Null
## when the toon shaders are off (the cape then just swings).
static func make_cloth(rim: float = 0.3, cape: StringName = &"") -> ShaderMaterial:
	if not enabled or not Vfx.enabled():
		return null
	var s := ShaderMaterial.new()
	s.shader = CLOTH_SHADER
	s.set_shader_parameter(&"albedo", Color.WHITE)
	s.set_shader_parameter(&"rim_strength", rim)
	var fx: Array = CAPE_FX.get(cape, [])
	if not fx.is_empty():
		s.set_shader_parameter(&"sheen_color", fx[0])
		s.set_shader_parameter(&"sheen", fx[1])
		s.set_shader_parameter(&"sparkle_color", fx[2])
		s.set_shader_parameter(&"sparkle", fx[3])
		s.set_shader_parameter(&"sheen_speed", fx[4])
	return s


## The expensive capes come alive (Patrick 2026-11-17: "Animiere paar teure capes ... vorallen die
## teuren für echtgeld"): [sheen colour, sheen strength, sparkle colour, sparkle strength, sheen
## sweeps per second]. Warm gold light, no neon (ART_DIRECTION.md).
const CAPE_FX: Dictionary = {
	&"cape_high_roller": [Color(1.0, 0.86, 0.52), 0.55, Color(1.0, 0.95, 0.75), 1.6, 0.24],  # Gold: a glint over the gold, sparkles
	&"cape_royal": [Color(0.95, 0.75, 0.95), 0.35, Color(1.0, 0.85, 0.5), 1.2, 0.16],  # Gold: velvet sheen, gold dust
	&"cape_money": [Color(0.8, 1.0, 0.75), 0.3, Color(1.0, 0.92, 0.6), 0.9, 0.2],  # crisp bills glinting
	&"cape_card_shark": [Color(1.0, 0.55, 0.45), 0.3, Color(1.0, 0.88, 0.6), 0.7, 0.18],
	&"cape_legend": [Color(1.0, 0.85, 0.55), 0.35, Color(1.0, 0.9, 0.65), 1.0, 0.2],
	&"cape_jackpot": [Color(1.0, 0.85, 0.5), 0.3, Color(1.0, 0.9, 0.6), 1.0, 0.22],
}


## Recolours a material made by `make`.
static func set_color(mat: Material, color: Color) -> void:
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter(&"albedo", color)
	elif mat is BaseMaterial3D:
		(mat as BaseMaterial3D).albedo_color = color
