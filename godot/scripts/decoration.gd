class_name Decoration
extends Node3D
## Pure-visual ground cover: grass tufts, flowers, mushrooms, pebbles, stumps.
## Every .glb in assets/decor/ becomes a MultiMesh scattered over walkable
## grass — thousands of instances at negligible cost. No gameplay meaning.



# per-1000-cells densities by filename prefix; anything unlisted gets DEFAULT
const DENSITY := {
	"grass": 26.0, "flower": 7.0, "mushroom": 2.5, "stone": 5.0, "stump": 0.8,
}
const DEFAULT_DENSITY := 4.0
const TARGET_HEIGHT := {
	"grass": 0.35, "flower": 0.42, "mushroom": 0.28, "stone": 0.22, "stump": 0.45,
}
const MAX_PER_TYPE := 40000


func setup(world: VoxelWorld) -> void:
	var dir := DirAccess.open("res://assets/decor")
	if dir == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world.world_seed + 9090
	var kcells := float(world.W * world.D) / 1000.0
	var total := 0
	for file in dir.get_files():
		# in exported builds GLBs appear as .glb.import; normalize
		var fname := file.trim_suffix(".import")
		if not fname.ends_with(".glb") and not fname.ends_with(".gltf"):
			continue
		var slot := fname.get_basename()
		var prefix := slot.split("_")[0]
		var count := mini(int(kcells * float(DENSITY.get(prefix, DEFAULT_DENSITY))),
			MAX_PER_TYPE)
		total += _scatter_type("decor/" + slot, prefix, count, world, rng)
	if total > 0:
		print("[VOX P7] decoration: %d instances scattered" % total)


func _scatter_type(slot: String, prefix: String, count: int,
		world: VoxelWorld, rng: RandomNumberGenerator) -> int:
	var proto := AssetLib.instantiate(slot)
	if proto == null or count <= 0:
		return 0
	var mesh := _first_mesh(proto)
	if mesh == null:
		proto.free()
		return 0
	# base scale from the model's own size toward the target height
	var aabb := mesh.get_aabb()
	var base := 1.0
	if aabb.size.y > 0.001:
		base = float(TARGET_HEIGHT.get(prefix, 0.35)) / aabb.size.y
	proto.free()

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var xforms: Array[Transform3D] = []
	for i in count * 3:
		if xforms.size() >= count:
			break
		var x := rng.randi_range(2, world.W - 3)
		var z := rng.randi_range(2, world.D - 3)
		if not world.is_walkable(x, z) or world.surface_block(x, z) != VoxelWorld.B.GRASS:
			continue
		var s := base * rng.randf_range(0.7, 1.35)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
			world.cell_pos(x, z) + Vector3(rng.randf_range(-0.4, 0.4), 0,
				rng.randf_range(-0.4, 0.4)))
		xforms.append(t)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return xforms.size()


func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var m := _first_mesh(child)
		if m != null:
			return m
	return null
