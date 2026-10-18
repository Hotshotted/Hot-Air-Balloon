class_name ShapeMesh
extends RefCounted
## Builds ONE ArrayMesh out of low-poly shapes: filled polygons (triangulated), circles and thick lines, outlines
## included (as black quads), so a whole bird / kite / drone is a single mesh and all of them draw as one
## MultiMesh. Painter's order is the order the shapes are added. Each vertex also carries an animation id and
## weight in its UV, which shaders/hazard.gdshader reads (wing flap, tail wave, ...). Built once at start-up.

const BLACK := Color(0, 0, 0, 1)

var outline_w := 4.5
var verts := PackedVector2Array()
var cols := PackedColorArray()
var uvs := PackedVector2Array()
var idx := PackedInt32Array()

func _add_vertex(p: Vector2, c: Color, anim: float, weight: float) -> int:
	verts.append(p)
	cols.append(c)
	uvs.append(Vector2(anim, weight))
	return verts.size() - 1

## A filled polygon with an outline.
func poly(points: Array, fill: Color, line: bool = true, anim: float = 0.0, weight: float = 0.0) -> void:
	var p := PackedVector2Array(points)
	var tri := Geometry2D.triangulate_polygon(p)
	var base := verts.size()
	for v in p:
		_add_vertex(v, fill, anim, weight)
	for t in tri:
		idx.append(base + t)
	if line:
		var closed: Array = points.duplicate()
		closed.append(points[0])
		polyline(closed, outline_w, BLACK, anim, weight)

## A filled regular polygon (a circle), with an outline.
func circle(c: Vector2, r: float, fill: Color, line: bool = true, anim: float = 0.0, weight: float = 0.0, sides: int = 10) -> void:
	var pts: Array = []
	for i in sides:
		var a := TAU * float(i) / float(sides)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	poly(pts, fill, line, anim, weight)

## A thick line through the points; weights (optional) give each point's animation weight.
func polyline(points: Array, w: float, col: Color, anim: float = 0.0, weight: float = 0.0, weights: Array = []) -> void:
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * w * 0.5
		var ext := d * w * 0.5   # extended a little at both ends, so corners join up
		var wa := float(weights[i]) if not weights.is_empty() else weight
		var wb := float(weights[i + 1]) if not weights.is_empty() else weight
		var base := verts.size()
		_add_vertex(a - ext + n, col, anim, wa)
		_add_vertex(a - ext - n, col, anim, wa)
		_add_vertex(b + ext - n, col, anim, wb)
		_add_vertex(b + ext + n, col, anim, wb)
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

## A thick line segment.
func line(a: Vector2, b: Vector2, w: float, col: Color, anim: float = 0.0, weight: float = 0.0) -> void:
	polyline([a, b], w, col, anim, weight)

## An axis-aligned rectangle (filled, outlined).
func rect(x: float, y: float, w: float, h: float, fill: Color, line: bool = true, anim: float = 0.0, weight: float = 0.0) -> void:
	poly([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)], fill, line, anim, weight)

func build() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
