class_name Teleporter
extends Area3D
## One-way Halo-style teleporter (sender node); destination is the receiver.

var destination := Transform3D.IDENTITY


func _ready() -> void:
	collision_layer = GameConfig.LAYER_PICKUP
	collision_mask = GameConfig.LAYER_SOLDIER
	monitorable = false
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.9
	cyl.height = 2.0
	cs.shape = cyl
	cs.position.y = 1.0
	add_child(cs)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.85
	cm.bottom_radius = 0.85
	cm.height = 2.4
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.4, 0.85, 1.0, 0.18)
	beam.material_override = m
	beam.position.y = 1.2
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.85, 1.0)
	light.light_energy = 1.5
	light.omni_range = 5.0
	light.position.y = 1.0
	add_child(light)


func _physics_process(_delta: float) -> void:
	for b in get_overlapping_bodies():
		var s := b as Soldier
		if s and s.alive:
			_send(s)


func _send(s: Soldier) -> void:
	Sfx.play_3d(self, "teleport", global_position + Vector3.UP, -2.0)
	s.global_position = destination.origin
	s.look_yaw = destination.basis.get_euler().y
	s.look_pitch = 0.0
	s.velocity = Vector3.ZERO
	s.snap_interpolation()
	Fx.ring_burst(s.fx_root(), destination.origin, Color(0.4, 0.85, 1.0))
	Sfx.play_3d(s, "teleport", destination.origin + Vector3.UP, -2.0)
