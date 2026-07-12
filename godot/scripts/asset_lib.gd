class_name AssetLib
extends RefCounted
## Drop-in 3D model support. Put .glb/.gltf/.tscn files under res://assets/
## and they replace the built-in box art automatically; missing files fall
## back to the procedural look. See assets/README.md for the naming map.

const EXTS := ["glb", "gltf", "tscn", "scn"]


static func instantiate(rel_path: String) -> Node3D:
	## e.g. instantiate("props/berry_bush") tries assets/props/berry_bush.glb etc.
	for ext in EXTS:
		var path := "res://assets/%s.%s" % [rel_path, ext]
		if ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res is PackedScene:
				var node: Node = (res as PackedScene).instantiate()
				if node is Node3D:
					if not _announced.has(path):
						_announced[path] = true
						print("[VOX] model loaded: ", path)
					return node
				node.queue_free()
	return null

static var _announced := {}


static func fit(node: Node3D, target_height: float) -> void:
	## Uniformly scale an imported model to a gameplay-sized height and drop
	## its feet to y=0 — generated/downloaded models arrive at wild scales.
	## The foot offset goes on the model's CHILDREN, not its root position,
	## so callers that place the node afterwards don't undo it (floating deer).
	var aabb := _merged_aabb(node, Transform3D.IDENTITY)
	if aabb.size.y <= 0.001:
		return
	node.scale = Vector3.ONE * (target_height / aabb.size.y)
	var shifted := false
	for child in node.get_children():
		if child is Node3D:
			(child as Node3D).position.y -= aabb.position.y
			shifted = true
	if not shifted:
		node.position.y = -aabb.position.y * node.scale.y   # bare-mesh fallback


static func find_animations(node: Node3D) -> Dictionary:
	## Locate an AnimationPlayer and guess walk/idle clips by name.
	var player := _find_player(node)
	if player == null:
		return {}
	var out := {"player": player}
	for anim_name in player.get_animation_list():
		var low := str(anim_name).to_lower()
		if not out.has("walk") and ("walk" in low or "run" in low):
			out["walk"] = anim_name
		if not out.has("idle") and "idle" in low:
			out["idle"] = anim_name
		if not out.has("work") and ("interact" in low or "attack" in low
				or "gather" in low or "chop" in low or "pick" in low):
			out["work"] = anim_name
		# generic fallback for models with unhelpfully named clips
		if not out.has("any") and "death" not in low and "die" not in low:
			out["any"] = anim_name
	return out


static func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


static func _merged_aabb(node: Node, xform: Transform3D) -> AABB:
	var box := AABB()
	var has_box := false
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		box = local * (node as MeshInstance3D).get_aabb()
		has_box = true
	for child in node.get_children():
		var child_box := _merged_aabb(child, local if node is Node3D else xform)
		if child_box.size != Vector3.ZERO:
			box = box.merge(child_box) if has_box else child_box
			has_box = true
	return box
