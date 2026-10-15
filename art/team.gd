class_name Team
extends RefCounted
## One shared material per player that paints that player's colour onto their units
## (team.gdshader), made on first use.

static var _materials := {}


## Forget the materials made so far (the colours were changed).
static func reset() -> void:
	_materials.clear()


static func material_for(owner: int) -> ShaderMaterial:
	if not _materials.has(owner):
		var base := Defs.color_of(owner)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/team.gdshader")
		mat.set_shader_parameter("team_light", base.lightened(0.35))
		mat.set_shader_parameter("team_mid", base)
		mat.set_shader_parameter("team_dark", base.darkened(0.4))
		_materials[owner] = mat
	return _materials[owner]
