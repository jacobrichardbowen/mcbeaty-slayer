class_name AmmoPickup
extends Area3D
## Shotgun shells. Static crates respawn; shotguns dropped by the dead vanish
## once taken (Halo 2 lets you walk over a matching gun to strip its ammo).

var amount := 12
var respawn_time := 25.0
var dropped := false

var _lifetime := 30.0
var _active := true
var _cool := 0.0
var _visual: Node3D


func _ready() -> void:
	collision_layer = GameConfig.LAYER_PICKUP
	collision_mask = GameConfig.LAYER_SOLDIER
	monitorable = false
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	cs.shape = sphere
	cs.position.y = 0.6
	add_child(cs)
	_visual = Node3D.new()
	add_child(_visual)
	if dropped:
		_part(_box(Vector3(0.07, 0.09, 0.32)), Color(0.15, 0.15, 0.16), Vector3(0, 0.06, 0))
		_part(_box(Vector3(0.05, 0.05, 0.55)), Color(0.15, 0.15, 0.16), Vector3(0, 0.06, -0.42))
		_part(_box(Vector3(0.06, 0.09, 0.3)), Color(0.42, 0.27, 0.14), Vector3(0, 0.05, 0.3))
		_visual.rotation.y = randf() * TAU
	else:
		_part(_box(Vector3(0.7, 0.32, 0.45)), Color(0.28, 0.33, 0.22), Vector3(0, 0.16, 0))
		for i in 5:
			_part(_box(Vector3(0.06, 0.12, 0.06)), Color(0.75, 0.15, 0.1), Vector3(-0.2 + i * 0.1, 0.38, 0))


func _part(mesh: Mesh, color: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	mi.position = pos
	_visual.add_child(mi)


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _physics_process(delta: float) -> void:
	if dropped:
		_lifetime -= delta
		if _lifetime <= 0.0:
			queue_free()
			return
	if not _active:
		_cool -= delta
		if _cool > 0.0:
			return
		_active = true
		_visual.visible = true
	if not dropped:
		_visual.rotation.y += delta * 1.2
	for b in get_overlapping_bodies():
		var s := b as Soldier
		if s == null or not s.alive or s.weapon.ammo_room() <= 0:
			continue
		if s.weapon.add_ammo(amount) > 0:
			if s.is_player:
				Sfx.play_2d(self, "pickup", -6.0)
			if dropped:
				queue_free()
			else:
				_active = false
				_cool = respawn_time
				_visual.visible = false
			return
