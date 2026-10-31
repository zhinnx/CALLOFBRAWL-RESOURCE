## CALLOFBRAWL — baked navigation data for de_dust2.
##
## The navigation mesh was baked offline from the *actual* map geometry
## (de_dust2_-_cs_map.glb): a 0.5 m walkable lattice, eroded by the agent radius,
## with cells under low overhangs and on steep ledges removed. The result is one
## large connected surface (6 348 of 6 657 polygons) covering ~1 660 m² of the map.
##
## Baking offline keeps start-up instant on phones (no runtime bake) and guarantees
## every spawn and every tactical point is reachable. The file also ships the
## adjacency graph itself, so the bot pathfinder is a plain A* over integers and
## never has to re-derive connectivity from mesh geometry.
class_name CBNavMeshData
extends RefCounted

const DATA_PATH := "res://resources/navigation/navmesh_dust2.json"

static var _cache: Dictionary = {}
static var _centers: PackedVector3Array = PackedVector3Array()
static var _adjacency: Array = []
static var _adjacency_ready: bool = false


static func load_data() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	if not FileAccess.file_exists(DATA_PATH):
		push_error("CBNavMeshData: missing %s" % DATA_PATH)
		return {}
	var text := FileAccess.get_file_as_string(DATA_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CBNavMeshData: could not parse navigation data")
		return {}
	_cache = parsed
	return _cache


static func vertices() -> PackedVector3Array:
	var data := load_data()
	var out := PackedVector3Array()
	for v: Array in data.get("vertices", []):
		out.append(Vector3(float(v[0]), float(v[1]), float(v[2])))
	return out


static func polygons() -> Array:
	return load_data().get("polygons", [])


## Centre of every navigation polygon in the same order as `polygons()`.
static func polygon_centers() -> PackedVector3Array:
	if not _centers.is_empty():
		return _centers
	var verts := vertices()
	var out := PackedVector3Array()
	for poly: Array in polygons():
		var c := Vector3.ZERO
		for idx: int in poly:
			c += verts[idx]
		out.append(c / float(maxi(1, poly.size())))
	_centers = out
	return _centers


## Polygon adjacency as an array of PackedInt32Array neighbour lists.
static func adjacency() -> Array:
	if _adjacency_ready:
		return _adjacency
	var count := polygons().size()
	_adjacency = []
	_adjacency.resize(count)
	for i in count:
		_adjacency[i] = PackedInt32Array()
	for link: Array in load_data().get("links", []):
		var a := int(link[0])
		var b := int(link[1])
		if a < 0 or b < 0 or a >= count or b >= count:
			continue
		_adjacency[a].append(b)
		_adjacency[b].append(a)
	_adjacency_ready = true
	return _adjacency


## Index of the polygon whose centre is closest to `pos` (height is used as a soft
## tie-breaker so a spawn on an upper walkway never snaps to the floor below it).
static func nearest_polygon(pos: Vector3) -> int:
	var centers := polygon_centers()
	if centers.is_empty():
		return -1
	_build_lookup()
	var bucket := Vector2i(int(floor(pos.x / LOOKUP_CELL)), int(floor(pos.z / LOOKUP_CELL)))
	var best := -1
	var best_dist := INF
	for ring in 4:
		# only widen the search when nothing was found in the inner rings
		if best >= 0 and ring > 0:
			break
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var key := Vector2i(bucket.x + dx, bucket.y + dz)
				var list: PackedInt32Array = _lookup.get(key, PackedInt32Array())
				for i: int in list:
					var c := centers[i]
					var ddx := c.x - pos.x
					var ddz := c.z - pos.z
					var dy := absf(c.y - pos.y)
					var penalty := maxf(0.0, dy - 2.0) * 12.0
					var d := ddx * ddx + ddz * ddz + penalty * penalty
					if d < best_dist:
						best_dist = d
						best = i
	if best >= 0:
		return best
	# fallback: full scan (only happens for points far outside the map)
	for i in centers.size():
		var c := centers[i]
		var d := Vector2(c.x - pos.x, c.z - pos.z).length_squared()
		if d < best_dist:
			best_dist = d
			best = i
	return best


const LOOKUP_CELL := 4.0
static var _lookup: Dictionary = {}


static func _build_lookup() -> void:
	if not _lookup.is_empty():
		return
	var centers := polygon_centers()
	for i in centers.size():
		var c := centers[i]
		var key := Vector2i(int(floor(c.x / LOOKUP_CELL)), int(floor(c.z / LOOKUP_CELL)))
		var list: PackedInt32Array = _lookup.get(key, PackedInt32Array())
		list.append(i)
		_lookup[key] = list


## True when `pos` is on (or very close to) the navigation surface.
static func is_on_mesh(pos: Vector3, tolerance: float = 1.2) -> bool:
	var idx := nearest_polygon(pos)
	if idx < 0:
		return false
	return absf(polygon_centers()[idx].y - pos.y) <= tolerance


## A* over the shipped adjacency graph. Returns the polygon index path (start and
## goal included) or an empty array when the goal is unreachable.
##
## `max_expansions` keeps the worst case bounded on a phone: a full cross-map path
## explores ~4 600 nodes at worst, so 12 000 is a comfortable ceiling.
static func find_path(from_pos: Vector3, to_pos: Vector3, max_expansions: int = 12000) -> PackedInt32Array:
	var empty := PackedInt32Array()
	var start := nearest_polygon(from_pos)
	var goal := nearest_polygon(to_pos)
	if start < 0 or goal < 0:
		return empty
	if start == goal:
		var single := PackedInt32Array()
		single.append(start)
		return single
	var centers := polygon_centers()
	var adj := adjacency()
	var count := centers.size()

	var g_score := PackedFloat32Array()
	g_score.resize(count)
	g_score.fill(INF)
	var came := PackedInt32Array()
	came.resize(count)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count)
	closed.fill(0)

	g_score[start] = 0.0
	# Binary heap of (f, polygon). Keeps the worst case at a handful of milliseconds
	# even for a full cross-map path, which matters on a phone with nine bots.
	var heap := PackedFloat64Array()
	var heap_poly := PackedInt32Array()
	var in_open := PackedByteArray()
	in_open.resize(count)
	in_open.fill(0)
	_heap_push(heap, heap_poly, in_open, _heuristic(centers, start, goal), start)
	var expansions := 0
	while not heap.is_empty():
		var current := _heap_pop(heap, heap_poly, in_open)
		if closed[current] == 1:
			continue
		if current == goal:
			return _reconstruct(came, current)
		closed[current] = 1
		expansions += 1
		if expansions > max_expansions:
			break
		for nb: int in adj[current]:
			if closed[nb] == 1:
				continue
			var a := centers[current]
			var b := centers[nb]
			var step := Vector2(b.x - a.x, b.z - a.z).length() + absf(b.y - a.y) * 0.5
			var tentative := g_score[current] + step
			if tentative < g_score[nb] - 0.0001:
				g_score[nb] = tentative
				came[nb] = current
				_heap_push(heap, heap_poly, in_open, tentative + _heuristic(centers, nb, goal), nb)
	return empty


static func _heap_push(keys: PackedFloat64Array, values: PackedInt32Array, in_open: PackedByteArray,
		key: float, value: int) -> void:
	keys.append(key)
	values.append(value)
	in_open[value] = 1
	var i := keys.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if keys[parent] <= keys[i]:
			break
		var k := keys[parent]
		keys[parent] = keys[i]
		keys[i] = k
		var v := values[parent]
		values[parent] = values[i]
		values[i] = v
		i = parent


static func _heap_pop(keys: PackedFloat64Array, values: PackedInt32Array, in_open: PackedByteArray) -> int:
	var top := values[0]
	in_open[top] = 0
	var last_key := keys[keys.size() - 1]
	var last_val := values[values.size() - 1]
	keys.remove_at(keys.size() - 1)
	values.remove_at(values.size() - 1)
	var size := keys.size()
	if size == 0:
		return top
	keys[0] = last_key
	values[0] = last_val
	var i := 0
	while true:
		var left := i * 2 + 1
		if left >= size:
			break
		var right := left + 1
		var smallest := left
		if right < size and keys[right] < keys[left]:
			smallest = right
		if keys[i] <= keys[smallest]:
			break
		var k := keys[i]
		keys[i] = keys[smallest]
		keys[smallest] = k
		var v := values[i]
		values[i] = values[smallest]
		values[smallest] = v
		i = smallest
	return top


static func _heuristic(centers: PackedVector3Array, a: int, b: int) -> float:
	var ca := centers[a]
	var cb := centers[b]
	return Vector2(cb.x - ca.x, cb.z - ca.z).length()


static func _reconstruct(came: PackedInt32Array, goal: int) -> PackedInt32Array:
	var path := PackedInt32Array()
	var cur := goal
	var guard := 0
	while cur != -1 and guard < 100000:
		path.append(cur)
		cur = came[cur]
		guard += 1
	path.reverse()
	return path


## Converts a polygon path into world-space waypoints, simplifying straight
## sections so agents do not zig-zag across every 0.5 m cell.
static func path_points(path: PackedInt32Array, corner_degrees: float = 25.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var centers := polygon_centers()
	if path.size() <= 2:
		for idx: int in path:
			out.append(centers[idx])
		return out
	out.append(centers[path[0]])
	var limit := cos(deg_to_rad(corner_degrees))
	for i in range(1, path.size() - 1):
		var prev := centers[path[i - 1]]
		var cur := centers[path[i]]
		var next := centers[path[i + 1]]
		var d0 := (cur - prev).normalized()
		var d1 := (next - cur).normalized()
		if d0.dot(d1) < limit:
			out.append(cur)
	out.append(centers[path[path.size() - 1]])
	return out


static func spawn_points(team: int) -> Array:
	var data := load_data()
	var key := "spawn_a" if team == CBTeam.ALPHA else "spawn_b"
	var out: Array = []
	for p: Array in data.get(key, []):
		out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return out


static func points_of_interest() -> Array:
	var out: Array = []
	for p: Array in load_data().get("pois", []):
		out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return out
