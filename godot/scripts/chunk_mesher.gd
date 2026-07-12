class_name ChunkMesher
extends RefCounted
## Builds one chunk's meshes with naive face culling.
## Godot uses clockwise winding for front faces; quads below are CW seen from outside.

const FACES := [
	{ "dir": Vector3i(0, 1, 0), "shade": 1.0,
		"v": [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)] },
	{ "dir": Vector3i(0, -1, 0), "shade": 0.5,
		"v": [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0)] },
	{ "dir": Vector3i(1, 0, 0), "shade": 0.8,
		"v": [Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1)] },
	{ "dir": Vector3i(-1, 0, 0), "shade": 0.8,
		"v": [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), Vector3(0, 0, 0)] },
	{ "dir": Vector3i(0, 0, 1), "shade": 0.7,
		"v": [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(0, 0, 1)] },
	{ "dir": Vector3i(0, 0, -1), "shade": 0.7,
		"v": [Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0)] },
]


static func build(world, cx: int, cz: int, solid_mat: Material, water_mat: Material) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := 0
	var wfaces := 0
	var chunk: int = world.CHUNK
	var air: int = world.B.AIR
	var water: int = world.B.WATER

	for lx in chunk:
		var x: int = cx * chunk + lx
		for lz in chunk:
			var z: int = cz * chunk + lz
			for y in int(world.H):
				var b: int = world.get_block(x, y, z)
				if b == air:
					continue
				if b == water:
					if world.get_block(x, y + 1, z) == air:
						_add_face(wst, FACES[0], Vector3(x, y, z), Color.WHITE, true)
						wfaces += 1
					continue
				var col: Color = world.COLORS[b]
				for f in FACES:
					var d: Vector3i = f.dir
					var nb: int = world.get_block(x + d.x, y + d.y, z + d.z)
					if nb == air or nb == water:
						_add_face(st, f, Vector3(x, y, z), col, false)
						faces += 1

	var nodes: Array = []
	if faces > 0:
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = solid_mat
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		body.add_child(cs)
		mi.add_child(body)
		nodes.append(mi)
	if wfaces > 0:
		var wmesh := wst.commit()
		var wmi := MeshInstance3D.new()
		wmi.mesh = wmesh
		wmi.material_override = water_mat
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nodes.append(wmi)
	return { "nodes": nodes, "faces": faces + wfaces }


static func _add_face(
	st: SurfaceTool, f: Dictionary, origin: Vector3, col: Color, is_water: bool
) -> void:
	var n := Vector3(f.dir)
	var v: Array = f.v
	var c := col
	if not is_water:
		var s: float = f.shade
		c = Color(col.r * s, col.g * s, col.b * s)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_color(c)
		st.add_vertex(origin + v[i])
