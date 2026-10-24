class_name LevelBuilder
extends RefCounted
## Helpers that turn blockout primitives into meshes plus static collision.
## Every collider goes on one StaticBody3D so the navmesh bake can parse it.

# name: [albedo, roughness, metallic, triplanar uv scale (0 = untextured), emission energy]
const MAT_DEFS := {
	"ground": [Color(0.53, 0.5, 0.45), 0.95, 0.0, 0.05, 0.0],
	"rock": [Color(0.45, 0.42, 0.39), 0.95, 0.0, 0.035, 0.0],
	"rock_far": [Color(0.34, 0.34, 0.37), 1.0, 0.0, 0.0, 0.0],
	"snow": [Color(0.9, 0.92, 0.96), 0.8, 0.0, 0.0, 0.0],
	"dish": [Color(0.7, 0.72, 0.74), 0.45, 0.5, 0.08, 0.0],
	"paving": [Color(0.6, 0.59, 0.56), 0.85, 0.05, 0.12, 0.0],
	"metal": [Color(0.6, 0.64, 0.68), 0.5, 0.55, 0.1, 0.0],
	"metal_dark": [Color(0.29, 0.32, 0.36), 0.55, 0.6, 0.1, 0.0],
	"trim": [Color(0.18, 0.2, 0.23), 0.6, 0.4, 0.0, 0.0],
	"glow": [Color(0.35, 0.85, 1.0), 0.4, 0.0, 0.0, 2.5],
	"glow_warm": [Color(1.0, 0.72, 0.32), 0.4, 0.0, 0.0, 2.0],
	"pad_mark": [Color(0.85, 0.7, 0.2), 0.7, 0.0, 0.0, 0.3],
	"sandbag": [Color(0.6, 0.53, 0.39), 1.0, 0.0, 0.25, 0.0],
	"wood": [Color(0.46, 0.33, 0.2), 0.9, 0.0, 0.3, 0.0],
	"cloth_white": [Color(0.93, 0.93, 0.9), 0.9, 0.0, 0.0, 0.0],
	"cloth_red": [Color(0.8, 0.1, 0.08), 0.9, 0.0, 0.0, 0.0],
	"cloth_grey": [Color(0.45, 0.45, 0.45), 0.9, 0.0, 0.0, 0.0],
}

static var _noise: NoiseTexture2D
static var _mats := {}

var geo_root: Node3D
var body: StaticBody3D


func _init(p_geo_root: Node3D, p_body: StaticBody3D) -> void:
	geo_root = p_geo_root
	body = p_body


static func mat(mat_name: String) -> StandardMaterial3D:
	if _mats.has(mat_name):
		return _mats[mat_name]
	var d: Array = MAT_DEFS.get(mat_name, MAT_DEFS["metal"])
	var m := StandardMaterial3D.new()
	m.albedo_color = d[0]
	m.roughness = d[1]
	m.metallic = d[2]
	if d[3] > 0.0:
		m.albedo_texture = noise_texture()
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * float(d[3])
	if d[4] > 0.0:
		m.emission_enabled = true
		m.emission = d[0]
		m.emission_energy_multiplier = d[4]
	_mats[mat_name] = m
	return m


static func noise_texture() -> NoiseTexture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.02
		n.fractal_octaves = 5
		var g := Gradient.new()
		g.set_color(0, Color(0.64, 0.64, 0.64))
		g.set_color(1, Color(1, 1, 1))
		_noise = NoiseTexture2D.new()
		_noise.width = 512
		_noise.height = 512
		_noise.seamless = true
		_noise.noise = n
		_noise.color_ramp = g
	return _noise


func add_mesh(mesh: Mesh, mat_name: String, xform := Transform3D.IDENTITY, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(mat_name)
	mi.transform = xform
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	geo_root.add_child(mi)
	return mi


func add_shape(shape: Shape3D, xform := Transform3D.IDENTITY) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xform
	body.add_child(cs)
	return cs


## Mesh with matching trimesh collision (both faces collide).
func add_static_mesh(mesh: ArrayMesh, mat_name: String, collide := true) -> MeshInstance3D:
	var mi := add_mesh(mesh, mat_name)
	if collide:
		var shape := mesh.create_trimesh_shape()
		shape.backface_collision = true
		add_shape(shape)
	return mi


func box(center: Vector3, size: Vector3, mat_name: String, basis := Basis.IDENTITY, collide := true) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var xf := Transform3D(basis, center)
	var mi := add_mesh(bm, mat_name, xf)
	if collide:
		var bs := BoxShape3D.new()
		bs.size = size
		add_shape(bs, xf)
	return mi


## Axis-aligned box between two corners.
func block(a: Vector3, b: Vector3, mat_name: String, collide := true) -> MeshInstance3D:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	return box((lo + hi) * 0.5, hi - lo, mat_name, Basis.IDENTITY, collide)


## Sloped slab whose top surface runs along the centerline from -> to.
func ramp(from: Vector3, to: Vector3, width: float, mat_name: String, thickness := 0.4, collide := true) -> MeshInstance3D:
	var d := to - from
	var f := d.normalized()
	var r := f.cross(Vector3.UP).normalized()
	var u := r.cross(f).normalized()
	var basis := Basis(r, u, r.cross(u))
	var center := (from + to) * 0.5 - u * (thickness * 0.5)
	return box(center, Vector3(width, thickness, d.length()), mat_name, basis, collide)


## Thin box laid along a horizontal segment (walls, sandbags, rails).
func strip(from: Vector3, to: Vector3, width: float, height: float, mat_name: String, collide := true) -> MeshInstance3D:
	var d := to - from
	d.y = 0.0
	var basis := Basis(Vector3.UP, atan2(d.x, d.z))
	var center := (from + to) * 0.5 + Vector3(0, height * 0.5, 0)
	return box(center, Vector3(width, height, d.length()), mat_name, basis, collide)


func cylinder(base: Vector3, radius: float, height: float, mat_name: String, collide := true, top_radius := -1.0, segments := 16) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	var xf := Transform3D(Basis.IDENTITY, base + Vector3(0, height * 0.5, 0))
	var mi := add_mesh(cm, mat_name, xf)
	if collide:
		add_shape(cm.create_convex_shape(true, false), xf)
	return mi


## A cluster of faceted, slightly tilted pillars: reads as a rock outcrop.
func rock(base: Vector3, radius: float, height: float, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for i in 3:
		var r := radius * rng.randf_range(0.55, 1.0)
		var h := height * rng.randf_range(0.6, 1.0)
		var off := Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5)) * radius
		var cm := CylinderMesh.new()
		cm.bottom_radius = r
		cm.top_radius = r * rng.randf_range(0.35, 0.7)
		cm.height = h
		cm.radial_segments = 6
		cm.rings = 1
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12)))
		var xf := Transform3D(basis, base + off + Vector3(0, h * 0.5 - 0.25, 0))
		add_mesh(cm, "rock", xf)
		add_shape(cm.create_convex_shape(true, false), xf)


func sandbags(from: Vector3, to: Vector3, height := 1.15) -> void:
	strip(from, to, 0.75, height, "sandbag")
	strip(from + Vector3(0, height, 0), to + Vector3(0, height, 0), 0.55, 0.18, "sandbag", false)


func crate(pos: Vector3, size := 1.2, yaw := 0.0) -> void:
	box(pos + Vector3(0, size * 0.5, 0), Vector3.ONE * size, "wood", Basis(Vector3.UP, yaw))


## Flat polygon floor at top_y with trimesh collision.
func flat_top(outline: PackedVector2Array, top_y: float, mat_name: String) -> void:
	var kit := MeshKit.new()
	var idx := Geometry2D.triangulate_polygon(outline)
	if idx.is_empty():
		for i in range(1, outline.size() - 1):
			idx.append_array(PackedInt32Array([0, i, i + 1]))
	for t in range(0, idx.size(), 3):
		var a := outline[idx[t]]
		var b := outline[idx[t + 1]]
		var c := outline[idx[t + 2]]
		kit.tri(Vector3(a.x, top_y, a.y), Vector3(b.x, top_y, b.y), Vector3(c.x, top_y, c.y), Vector3.UP)
	add_static_mesh(kit.commit(), mat_name)


## Rock skirt hanging under a platform outline, tapering to a spire. Only the
## first band collides; the rest is scenery over the abyss.
func cliff_skirt(outline: PackedVector2Array, top_y: float, depth: float, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var c := Vector2.ZERO
	for p in outline:
		c += p
	c /= float(outline.size())
	# [y offset, scale toward centroid, jitter]
	var profile := [[0.0, 1.0, 0.0], [-2.5, 1.0, 0.2], [-depth * 0.15, 0.88, 1.2], [-depth * 0.45, 0.62, 2.0], [-depth, 0.22, 2.5]]
	var rings: Array = []
	for pr in profile:
		var ring: Array[Vector3] = []
		for p in outline:
			var q: Vector2 = c + (p - c) * float(pr[1])
			q += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * float(pr[2])
			ring.append(Vector3(q.x, top_y + float(pr[0]), q.y))
		rings.append(ring)
	var vis := MeshKit.new()
	var col := MeshKit.new()
	var n := outline.size()
	for k in rings.size() - 1:
		var ra: Array[Vector3] = rings[k]
		var rb: Array[Vector3] = rings[k + 1]
		for i in n:
			var j := (i + 1) % n
			var mid := (ra[i] + ra[j]) * 0.5
			var out := Vector3(mid.x - c.x, 0.0, mid.z - c.y)
			vis.quad(ra[i], ra[j], rb[j], rb[i], out)
			if k == 0:
				col.quad(ra[i], ra[j], rb[j], rb[i], out)
	var last: Array[Vector3] = rings[rings.size() - 1]
	var tip := Vector3(c.x, top_y - depth - 8.0, c.y)
	for i in n:
		vis.tri(last[i], last[(i + 1) % n], tip, Vector3.DOWN)
	add_mesh(vis.commit(), "rock")
	var shape := col.commit().create_trimesh_shape()
	shape.backface_collision = true
	add_shape(shape)


## Ribbon walkway along a 3D polyline with mitered joints.
func walkway(points: Array, width: float, mat_name: String, thickness := 0.6) -> void:
	var n := points.size()
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	var tangents: Array[Vector3] = []
	for i in n:
		var p: Vector3 = points[i]
		var t: Vector3
		if i == 0:
			t = (points[1] as Vector3) - p
		elif i == n - 1:
			t = p - (points[i - 1] as Vector3)
		else:
			var t_in: Vector3 = p - (points[i - 1] as Vector3)
			var t_out: Vector3 = (points[i + 1] as Vector3) - p
			t_in.y = 0.0
			t_out.y = 0.0
			t = t_in.normalized() + t_out.normalized()
		t.y = 0.0
		t = t.normalized()
		tangents.append(t)
		var s := Vector3(-t.z, 0.0, t.x)
		var miter := 1.0
		if i > 0 and i < n - 1:
			var seg: Vector3 = p - (points[i - 1] as Vector3)
			seg.y = 0.0
			seg = seg.normalized()
			miter = 1.0 / maxf(0.5, s.dot(Vector3(-seg.z, 0.0, seg.x)))
		lefts.append(p + s * width * 0.5 * miter)
		rights.append(p - s * width * 0.5 * miter)
	var kit := MeshKit.new()
	var down := Vector3(0, -thickness, 0)
	for i in n - 1:
		var l0 := lefts[i]
		var l1 := lefts[i + 1]
		var r0 := rights[i]
		var r1 := rights[i + 1]
		kit.quad(l0, l1, r1, r0, Vector3.UP)
		kit.quad(l0 + down, l1 + down, r1 + down, r0 + down, Vector3.DOWN)
		kit.quad(l0, l1, l1 + down, l0 + down, l0 - r0)
		kit.quad(r0, r1, r1 + down, r0 + down, r0 - l0)
	kit.quad(lefts[0], rights[0], rights[0] + down, lefts[0] + down, -tangents[0])
	kit.quad(lefts[n - 1], rights[n - 1], rights[n - 1] + down, lefts[n - 1] + down, tangents[n - 1])
	add_static_mesh(kit.commit(), mat_name)
