class_name MeshKit
extends RefCounted
## Thin SurfaceTool wrapper for hand-built geometry. Callers pass triangles in
## any order plus the direction the face should point; MeshKit fixes the
## winding (Godot treats clockwise as front-facing) and writes flat normals.

var _st := SurfaceTool.new()
var _count := 0


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func tri(a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	if n.dot(outward) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	_st.set_normal(n)
	_st.add_vertex(a)
	_st.set_normal(n)
	_st.add_vertex(c)
	_st.set_normal(n)
	_st.add_vertex(b)
	_count += 1


## Quad given as four corners in perimeter order.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	tri(a, b, c, outward)
	tri(a, c, d, outward)


func is_empty() -> bool:
	return _count == 0


func commit() -> ArrayMesh:
	return _st.commit()
