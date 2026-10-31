class_name Fx
extends RefCounted
## Cheap one-shot visual effects: impact puffs, bullet marks, tracers, flashes.
## Everything parents to the game's fx root and frees itself.

const MAX_MARKS := 80

static var _marks: Array = []
static var _cache := {}


## Forget marks from a previous match (their nodes are already freed).
static func reset() -> void:
	_marks.clear()


static func _unshaded(color: Color, billboard := false) -> StandardMaterial3D:
	var key := "%s%s" % [color.to_html(), billboard]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = billboard
	_cache[key] = m
	return m


static func _expire(node: Node, seconds: float) -> void:
	node.get_tree().create_timer(seconds, false).timeout.connect(node.queue_free)


static func puff(root: Node3D, pos: Vector3, normal: Vector3, color: Color, amount := 8, speed := 3.0) -> void:
	var p := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	qm.material = _unshaded(Color.WHITE, true)
	p.mesh = qm
	p.amount = amount
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = normal
	p.spread = 40.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.color = color
	root.add_child(p)
	p.global_position = pos + normal * 0.03
	p.emitting = true
	_expire(p, 1.0)


static func impact(root: Node3D, pos: Vector3, normal: Vector3) -> void:
	puff(root, pos, normal, Color(0.75, 0.72, 0.65), 6, 3.0)
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.07)
	mi.mesh = qm
	mi.material_override = _unshaded(Color(0.08, 0.08, 0.08, 0.85))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var up := Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT
	mi.global_position = pos + normal * 0.01
	mi.look_at(pos - normal, up)
	_marks.append(mi)
	while _marks.size() > MAX_MARKS:
		var old: Variant = _marks.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()


static func blood(root: Node3D, pos: Vector3, dir: Vector3) -> void:
	puff(root, pos, -dir, Color(0.6, 0.05, 0.03), 10, 2.5)


static func tracer(root: Node3D, from: Vector3, to: Vector3, color := Color(1.0, 0.85, 0.45)) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.035, minf(length, 6.0))
	mi.mesh = bm
	mi.material_override = _unshaded(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# Show a short streak part-way down the line, like a fast bullet.
	var dir := (to - from) / length
	var head := from + dir * minf(length, randf_range(3.0, 12.0))
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	mi.global_position = head - dir * bm.size.z * 0.5
	mi.look_at(head, up)
	_expire(mi, 0.045)


## A muzzle flash: a glare at the muzzle and a burst of warm light on
## everything around, fading over a few frames so it registers at any frame
## rate (and through temporal anti-aliasing).
static func flash(root: Node3D, pos: Vector3, energy := 4.0, size := 0.35) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.38)
	light.light_energy = energy * 2.5
	light.omni_range = 10.0
	light.light_volumetric_fog_energy = 2.0
	light.light_bake_mode = Light3D.BAKE_DISABLED  # too brief to feed the bounced light
	root.add_child(light)
	light.global_position = pos
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size * 0.5
	sm.height = size
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = _unshaded(Color(1.0, 0.85, 0.5))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light.add_child(mi)
	var fade := light.create_tween()
	fade.tween_property(light, "light_energy", 0.0, 0.1).set_ease(Tween.EASE_IN)
	fade.parallel().tween_callback(mi.hide).set_delay(0.05)
	_expire(light, 0.1)


static func ring_burst(root: Node3D, pos: Vector3, color: Color) -> void:
	puff(root, pos + Vector3(0, 0.6, 0), Vector3.UP, color, 24, 4.0)
