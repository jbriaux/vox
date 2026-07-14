class_name VoxelWorld
extends Node3D
## Blocky voxel world: noise terrain, water, trees, chunked meshes with
## collision, and an A* walkability graph. Size and terrain character are
## set via configure() before generate() — see PRESETS.

enum B { AIR, GRASS, DIRT, STONE, SAND, WATER, WOOD, LEAVES }

const CHUNK := 16
var world_seed := 1337   # per-map; set via configure()

# Sea level is chosen per-map: the height percentile matching the requested
# water fraction, so "25% water" means 25% of columns are actually underwater.
var SEA := 14
var _water_pct := 0.20

# Terrain presets: noise amplitudes, base height, tree density, river carving.
const PRESETS := {
	"plains":    {"detail": 3.0, "hills": 5.0,  "base": 16.0, "trees_per_kcell": 3.0,
		"height": 48, "river": false},
	"hills":     {"detail": 6.0, "hills": 14.0, "base": 15.0, "trees_per_kcell": 4.3,
		"height": 48, "river": false},
	"rivers":    {"detail": 4.0, "hills": 9.0,  "base": 16.0, "trees_per_kcell": 5.5,
		"height": 48, "river": true},
	"mountains": {"detail": 7.0, "hills": 26.0, "base": 14.0, "trees_per_kcell": 3.5,
		"height": 64, "river": false},
}

# Sized by configure(); defaults match the classic 8-chunk hills world.
var CHUNKS := 8                # world is CHUNKS x CHUNKS chunks
var W := CHUNK * 8
var D := CHUNK * 8
var H := 48
var preset_name := "hills"
var _detail_amp := 6.0
var _hills_amp := 14.0
var _base_h := 15.0
var _trees_target := 70
var _river := false


func configure(size_chunks: int, p_preset: String, water_pct := 0.20) -> void:
	CHUNKS = clampi(size_chunks, 4, 64)   # 64 chunks = 1024 x 1024
	W = CHUNK * CHUNKS
	D = CHUNK * CHUNKS
	_water_pct = clampf(water_pct, 0.0, 0.7)
	preset_name = p_preset if PRESETS.has(p_preset) else "hills"
	var p: Dictionary = PRESETS[preset_name]
	_detail_amp = float(p.detail)
	_hills_amp = float(p.hills)
	_base_h = float(p.base)
	H = int(p.height)
	_river = bool(p.river)
	_trees_target = int(float(W * D) / 1000.0 * float(p.trees_per_kcell))

const COLORS := {
	B.GRASS: Color(0.36, 0.55, 0.25),
	B.DIRT: Color(0.45, 0.33, 0.22),
	B.STONE: Color(0.50, 0.50, 0.52),
	B.SAND: Color(0.78, 0.71, 0.50),
	B.WOOD: Color(0.42, 0.30, 0.18),
	B.LEAVES: Color(0.24, 0.42, 0.18),
}

var blocks := PackedByteArray()
var surface := PackedInt32Array()   # top solid y per column (terrain, pre-trees)
var astar := AStar3D.new()
var walkable_count := 0
var total_faces := 0
var trees: Array[Vector2i] = []     # trunk cells, for spawning fallen branches


func generate() -> void:
	var t0 := Time.get_ticks_msec()
	blocks.resize(W * H * D)
	surface.resize(W * D)
	_generate_terrain()
	if _river:
		_carve_river()
	_plant_trees()
	_build_chunks()
	_build_astar()
	var wet := 0
	for i in surface.size():
		if surface[i] < SEA - 1:
			wet += 1
	print("[VOX P0] generated %dx%dx%d (%s, %d%% water, sea=%d) in %d ms — %d faces, %d walkable cells"
		% [W, H, D, preset_name, roundi(100.0 * wet / surface.size()), SEA,
			Time.get_ticks_msec() - t0, total_faces, walkable_count])


# ---------------------------------------------------------------- terrain

func _generate_terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = world_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.015
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4

	var hills := FastNoiseLite.new()
	hills.seed = world_seed + 7
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX
	hills.frequency = 0.004

	# pass 1: heights only, so the sea level can be set at the exact
	# percentile matching the requested water fraction
	var heights := PackedInt32Array()
	heights.resize(W * D)
	for x in W:
		for z in D:
			var n := noise.get_noise_2d(x, z)
			var m := hills.get_noise_2d(x, z)
			heights[x * D + z] = clampi(
				int(round(_base_h + n * _detail_amp + m * _hills_amp)), 3, H - 8)
	if _water_pct <= 0.001:
		SEA = 2   # below the lowest possible ground: a dry world
	else:
		var sorted := heights.duplicate()
		sorted.sort()
		var idx := clampi(int(sorted.size() * _water_pct), 0, sorted.size() - 1)
		SEA = clampi(sorted[idx], 3, H - 10)

	# pass 2: blocks
	for x in W:
		for z in D:
			var h := heights[x * D + z]
			for y in h:
				var b := B.STONE
				if y >= h - 4:
					b = B.DIRT
				if y == h - 1:
					b = B.SAND if h - 1 <= SEA else B.GRASS
				blocks[_idx(x, y, z)] = b
			for y in range(h, SEA):
				blocks[_idx(x, y, z)] = B.WATER
			surface[x * D + z] = h - 1


func _plant_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	# imported tree models (assets/trees/tree_*.glb) replace voxel trees, up
	# to a scene-node budget; huge maps fall back to cheap voxel trees
	var kinds: Array[Node3D] = []
	if _trees_target <= 900:
		for c in "abcde":
			var proto := AssetLib.instantiate("trees/tree_" + c)
			if proto != null:
				kinds.append(proto)
	var placed := 0
	for i in _trees_target * 8:
		if placed >= _trees_target:
			break
		var x := rng.randi_range(3, W - 4)
		var z := rng.randi_range(3, D - 4)
		var s := surface[x * D + z]
		if get_block(x, s, z) != B.GRASS:
			continue
		var th := rng.randi_range(3, 5)
		if s + th + 4 >= H:
			continue
		trees.append(Vector2i(x, z))
		placed += 1
		if not kinds.is_empty():
			var tree: Node3D = kinds[rng.randi_range(0, kinds.size() - 1)].duplicate()
			AssetLib.fit(tree, float(th) + rng.randf_range(1.0, 2.5))
			tree.position = Vector3(x + 0.5, s + 1, z + 0.5)
			tree.rotation.y = rng.randf() * TAU
			add_child(tree)
			continue
		for y in range(s + 1, s + 1 + th):
			blocks[_idx(x, y, z)] = B.WOOD
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for dy in range(th - 1, th + 3):
					if absi(dx) + absi(dz) + maxi(dy - th, 0) > 3:
						continue
					var px := x + dx
					var pz := z + dz
					var py := s + 1 + dy
					if get_block(px, py, pz) == B.AIR:
						blocks[_idx(px, py, pz)] = B.LEAVES
	for proto in kinds:
		proto.free()   # prototypes were only templates for duplicate()


func _carve_river() -> void:
	## Cut a winding river across the map (west to east). Every ~20-30 columns
	## a shallow ford crosses it, and banks are GRADED one block per column so
	## the walk graph stays connected from water's edge to the hills.
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 11
	var rnoise := FastNoiseLite.new()
	rnoise.seed = world_seed + 11
	rnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	rnoise.frequency = 0.012
	var base_z := D * rng.randf_range(0.35, 0.65)
	var ford_countdown := rng.randi_range(14, 24)
	for x in W:
		var center := int(base_z + rnoise.get_noise_1d(float(x)) * D * 0.3)
		ford_countdown -= 1
		var is_ford := ford_countdown <= 0
		if ford_countdown <= -2:   # fords are 3 columns wide
			ford_countdown = rng.randi_range(18, 30)
		if is_ford:
			_build_ford(x, center)
		else:
			for dz in range(-2, 3):
				_lower_column(x, center + dz, SEA - 3)
			for side: int in [-1, 1]:
				var prev := SEA - 3
				for step in range(3, 14):
					var z: int = center + side * step
					if z < 1 or z >= D - 1:
						break
					if surface[x * D + z] <= prev + 1:
						break   # already a gentle slope from here on
					_lower_column(x, z, prev + 1)
					prev += 1


func _build_ford(x: int, center: int) -> void:
	## A dry sand causeway at SEA-1 straight across the river, extended over
	## any naturally low/wet ground on either side, then graded up the banks.
	for dz in range(-2, 3):
		_level_column(x, center + dz, SEA - 1)
	for side: int in [-1, 1]:
		var prev := SEA - 1
		var z := center + side * 3
		var causeway := 0
		while z > 0 and z < D - 1:
			var orig := surface[x * D + z]
			if orig < prev:              # water or low mud: keep the causeway going
				if causeway >= 24:
					break
				_level_column(x, z, prev)
				causeway += 1
			elif orig > prev + 1:        # bank rising too fast: cut a step into it
				prev += 1
				_level_column(x, z, prev)
			else:
				break                     # gentle ground reached: connected
			z += side


func _lower_column(x: int, z: int, new_s: int) -> void:
	if x < 0 or x >= W or z < 1 or z >= D - 1 or surface[x * D + z] <= new_s:
		return
	for y in range(new_s + 1, H):
		blocks[_idx(x, y, z)] = B.AIR
	blocks[_idx(x, new_s, z)] = B.SAND
	for y in range(new_s + 1, SEA):
		blocks[_idx(x, y, z)] = B.WATER
	surface[x * D + z] = new_s


func _level_column(x: int, z: int, new_s: int) -> void:
	## Cut OR fill a column to an exact surface height (used by fords).
	if x < 0 or x >= W or z < 1 or z >= D - 1:
		return
	var s := surface[x * D + z]
	if s > new_s:
		_lower_column(x, z, new_s)
	elif s < new_s:
		for y in range(s + 1, new_s + 1):
			blocks[_idx(x, y, z)] = B.SAND
		for y in range(new_s + 1, SEA):
			blocks[_idx(x, y, z)] = B.AIR
		surface[x * D + z] = new_s
	else:
		blocks[_idx(x, s, z)] = B.SAND


# ---------------------------------------------------------------- meshing

func _build_chunks() -> void:
	var solid_mat := StandardMaterial3D.new()
	solid_mat.vertex_color_use_as_albedo = true
	solid_mat.roughness = 1.0

	var water_mat := StandardMaterial3D.new()
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.albedo_color = Color(0.20, 0.45, 0.70, 0.55)
	water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_mat.roughness = 0.1

	for cx in CHUNKS:
		for cz in CHUNKS:
			var result: Dictionary = ChunkMesher.build(self, cx, cz, solid_mat, water_mat)
			total_faces += result.faces
			for node in result.nodes:
				add_child(node)


# ---------------------------------------------------------------- queries

func _idx(x: int, y: int, z: int) -> int:
	return (x * D + z) * H + y


func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return B.STONE  # cull all bottom faces
	if y >= H or x < 0 or x >= W or z < 0 or z >= D:
		return B.AIR
	return blocks[_idx(x, y, z)]


func is_walkable(x: int, z: int) -> bool:
	if x < 1 or z < 1 or x >= W - 1 or z >= D - 1:
		return false
	var s := surface[x * D + z]
	if s < SEA - 1:
		return false  # underwater
	var top := get_block(x, s, z)
	if top != B.GRASS and top != B.DIRT and top != B.STONE and top != B.SAND:
		return false
	return get_block(x, s + 1, z) == B.AIR and get_block(x, s + 2, z) == B.AIR


func cell_pos(x: int, z: int) -> Vector3:
	return Vector3(x + 0.5, surface[x * D + z] + 1, z + 0.5)


func surface_block(x: int, z: int) -> int:
	if x < 0 or x >= W or z < 0 or z >= D:
		return B.AIR
	return get_block(x, surface[x * D + z], z)


func is_water(x: int, z: int) -> bool:
	## True where water stands: the surface array stores the topmost SOLID
	## block, so "underwater" means that solid lies below sea level.
	if x < 0 or x >= W or z < 0 or z >= D:
		return false
	return surface[x * D + z] < SEA - 1


func find_spawn() -> Vector3:
	## Center-out search for a walkable cell that is actually CONNECTED to the
	## walk graph — river maps have isolated bank slivers that would strand
	## the whole village.
	var cx := int(W * 0.5)
	var cz := int(D * 0.5)
	var fallback := Vector3(cx, H, cz)
	var have_fallback := false
	for r in int(maxf(W, D) * 0.5):
		for x in range(cx - r, cx + r + 1):
			for z in range(cz - r, cz + r + 1):
				if not is_walkable(x, z):
					continue
				if astar.get_point_connections(_pid(x, z)).size() >= 3:
					return cell_pos(x, z)
				if not have_fallback:
					fallback = cell_pos(x, z)
					have_fallback = true
	return fallback


func random_walkable_near(pos: Vector3, radius: float) -> Vector3:
	for i in 60:
		var x := int(pos.x + randf_range(-radius, radius))
		var z := int(pos.z + randf_range(-radius, radius))
		if is_walkable(x, z) and astar.get_point_connections(_pid(x, z)).size() >= 1:
			var p := cell_pos(x, z)
			if Vector2(p.x - pos.x, p.z - pos.z).length() > 4.0:
				return p
	return pos


# ---------------------------------------------------------------- A*

func _pid(x: int, z: int) -> int:
	return x * D + z


func _build_astar() -> void:
	astar = AStar3D.new()
	walkable_count = 0
	for x in W:
		for z in D:
			if is_walkable(x, z):
				astar.add_point(_pid(x, z), cell_pos(x, z))
				walkable_count += 1
	for x in W:
		for z in D:
			if not astar.has_point(_pid(x, z)):
				continue
			var s := surface[x * D + z]
			# orthogonal neighbors (step up/down max 1)
			for off in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nx: int = x + off.x
				var nz: int = z + off.y
				if astar.has_point(_pid(nx, nz)) and absi(surface[nx * D + nz] - s) <= 1:
					astar.connect_points(_pid(x, z), _pid(nx, nz))
			# diagonals, no corner cutting
			for off in [Vector2i(1, 1), Vector2i(1, -1)]:
				var nx: int = x + off.x
				var nz: int = z + off.y
				if nz < 1 or nz >= D - 1:
					continue
				if not astar.has_point(_pid(nx, nz)):
					continue
				if absi(surface[nx * D + nz] - s) > 1:
					continue
				var side_a := astar.has_point(_pid(nx, z)) and absi(surface[nx * D + z] - s) <= 1
				var side_b := astar.has_point(_pid(x, nz)) and absi(surface[x * D + nz] - s) <= 1
				if side_a and side_b:
					astar.connect_points(_pid(x, z), _pid(nx, nz))


var _reach := {}   # point ids of the village's walk component


func compute_best_component() -> Vector3:
	## Label every walk component, keep the LARGEST as the village's home
	## (terrain fragments naturally — the fire must not land in a pocket),
	## and return its centermost cell as the campfire spot. Resource spawning
	## then sticks to this component via is_reachable().
	_reach.clear()
	if astar.get_point_count() == 0:
		return find_spawn()
	var visited := {}
	var best: Array = []
	for pid in astar.get_point_ids():
		if visited.has(pid):
			continue
		visited[pid] = true
		var comp: Array = [pid]
		var queue: Array = [pid]
		while not queue.is_empty():
			var p: int = queue.pop_back()
			for n in astar.get_point_connections(p):
				if not visited.has(n):
					visited[n] = true
					comp.append(n)
					queue.append(n)
		if comp.size() > best.size():
			best = comp
	for p in best:
		_reach[p] = true
	var center := Vector3(W * 0.5, 0, D * 0.5)
	var best_pos := astar.get_point_position(best[0])
	var best_d := INF
	for p in best:
		var pos := astar.get_point_position(p)
		var d := Vector2(pos.x - center.x, pos.z - center.z).length_squared()
		if d < best_d:
			best_d = d
			best_pos = pos
	print("[VOX P7] village component: %d/%d walkable cells" % [best.size(), walkable_count])
	return best_pos


func is_reachable(x: int, z: int) -> bool:
	return _reach.is_empty() or _reach.has(_pid(x, z))


func farthest_reachable_from(pos: Vector3) -> Vector3:
	## The most distant walkable cell in the village's component — the natural
	## site for a SECOND village that is far away yet reachable on foot.
	var best_pos := pos
	var best_d := -1.0
	for p in _reach:
		var cell := astar.get_point_position(p)
		var d := Vector2(cell.x - pos.x, cell.z - pos.z).length_squared()
		if d > best_d:
			best_d = d
			best_pos = cell
	return best_pos


func find_path(from_pos: Vector3, to_pos: Vector3) -> PackedVector3Array:
	if astar.get_point_count() == 0:
		return PackedVector3Array()
	var a := astar.get_closest_point(from_pos)
	var b := astar.get_closest_point(to_pos)
	if a == -1 or b == -1:
		return PackedVector3Array()
	return astar.get_point_path(a, b)
