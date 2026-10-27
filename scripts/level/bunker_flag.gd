class_name BunkerFlag
extends Node3D
## The holder's colours, flown high over the Big Tower so everyone can see who
## has the bunker: the Whites' tricolour (white, blue, red) or the Reds' red
## banner with a gold star. When the bunker changes hands the old flag drops
## and the new one runs up the pole. Purely visual: nothing collides with it.

const POLE_HEIGHT := 30.0
const FLAG_SIZE := Vector2(12.0, 8.0)
const RAISE_TIME := 3.0
const LOWER_TIME := 1.0

const SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform int team = 0;
uniform float flag_length = 9.0;
varying vec2 cloth_uv;

// Height of the wave at x along the flag, and its slope, for lighting.
float wave(float x, float y, float t) {
	return sin(x * 0.9 - t * 3.6) * 0.55 + sin(x * 1.9 - t * 5.7 + y * 0.5) * 0.2;
}

void vertex() {
	float x = VERTEX.x;
	float k = x / flag_length;  // 0 at the pole, 1 at the free end
	float z = wave(x, VERTEX.y, TIME) * k;
	float slope = (wave(x + 0.05, VERTEX.y, TIME) - wave(x - 0.05, VERTEX.y, TIME)) / 0.1 * k;
	VERTEX.z += z;
	VERTEX.y -= k * k * 0.5;
	NORMAL = normalize(vec3(-slope, 0.0, 1.0));
	cloth_uv = UV;
}

// Signed distance to a five-pointed star (Inigo Quilez).
float star5(vec2 p, float r, float rf) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-k1.x, k1.y);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

void fragment() {
	vec3 c;
	if (team == 0) {
		float v = cloth_uv.y;
		c = v < 1.0 / 3.0 ? vec3(0.95, 0.95, 0.93) : (v < 2.0 / 3.0 ? vec3(0.05, 0.22, 0.62) : vec3(0.78, 0.08, 0.06));
	} else {
		c = vec3(0.74, 0.05, 0.04);
		vec2 p = (cloth_uv - vec2(0.27, 0.45)) * vec2(1.5, -1.0);
		if (star5(p, 0.2, 0.42) < 0.0) {
			c = vec3(1.0, 0.78, 0.12);
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
	EMISSION = c * 0.3;  // readable against the bright sky from across the map
}
"""

var team := -1
var _cloth: MeshInstance3D
var _material: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.16
	cyl.height = POLE_HEIGHT
	cyl.radial_segments = 8
	pole.mesh = cyl
	pole.position.y = POLE_HEIGHT * 0.5
	pole.material_override = LevelBuilder.mat("metal")
	add_child(pole)
	var finial := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.35
	ball.height = 0.7
	finial.mesh = ball
	finial.position.y = POLE_HEIGHT + 0.3
	finial.material_override = LevelBuilder.mat("glow_warm")
	add_child(finial)

	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Z
	plane.size = FLAG_SIZE
	plane.subdivide_width = 36
	plane.subdivide_depth = 12
	plane.center_offset = Vector3(FLAG_SIZE.x * 0.5, -FLAG_SIZE.y * 0.5, 0)  # hoist edge on the pole
	_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER
	_material.shader = shader
	_material.set_shader_parameter("flag_length", FLAG_SIZE.x)
	_cloth = MeshInstance3D.new()
	_cloth.mesh = plane
	_cloth.material_override = _material
	_cloth.extra_cull_margin = 2.0  # the waves move it outside its box
	_cloth.visible = false
	add_child(_cloth)


func _top() -> float:
	return POLE_HEIGHT - 0.4


func _bottom() -> float:
	return 1.5 + FLAG_SIZE.y


## Lowers whatever flies now, then runs `new_team`'s colours up (none for -1).
func set_team(new_team: int, instant := false) -> void:
	if new_team == team:
		return
	team = new_team
	if _tween:
		_tween.kill()
	if instant:
		_show(new_team)
		_cloth.position.y = _top()
		return
	_tween = create_tween()
	if _cloth.visible:
		_tween.tween_property(_cloth, "position:y", _bottom(), LOWER_TIME * (_cloth.position.y - _bottom()) / (_top() - _bottom()))
	_tween.tween_callback(_show.bind(new_team))
	if new_team >= 0:
		_tween.tween_property(_cloth, "position:y", _top(), RAISE_TIME).set_trans(Tween.TRANS_SINE)


func _show(t: int) -> void:
	_cloth.visible = t >= 0
	_cloth.position.y = _bottom()
	_material.set_shader_parameter("team", maxi(t, 0))


## Height of the top of the cloth above the pole's foot, for tests.
func cloth_top() -> float:
	return _cloth.position.y if _cloth.visible else -1.0
