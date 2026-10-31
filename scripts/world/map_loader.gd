## CALLOFBRAWL — loads de_dust2 and prepares it for gameplay.
##
## Responsibilities
##   * instantiate the provided de_dust2_-_cs_map.glb (original materials kept)
##   * generate one StaticBody3D with a triangle collision shape per map mesh so
##     players and bots cannot walk through walls, while keeping the shapes tagged
##     on the map's own collision layer
##   * add a solid safety floor so a player that squeezes through a seam never
##     falls out of the world
##   * build the NavigationRegion3D from the baked lattice
##   * expose spawn helpers that drop combatants onto the real floor
class_name CBMapLoader
extends Node3D

const MAP_SCENE_PATH := "res://de_dust2_-_cs_map.glb"

## Bit values (not indices): world geometry on layer 1, combatants + hitboxes on
## layer 2. Hitscan rays query both; navigation and spawn snapping query only world.
const LAYER_WORLD := 1 << 0
const LAYER_COMBATANT := 1 << 1

signal map_ready(nav_region: NavigationRegion3D)

var map_root: Node3D
var nav_region: NavigationRegion3D
var _spawn_points: Dictionary = {}
var space_state_world: World3D


func load_map() -> void:
	map_root = Node3D.new()
	map_root.name = "Dust2"
	add_child(map_root)

	var packed: PackedScene = load(MAP_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("CBMapLoader: could not load %s" % MAP_SCENE_PATH)
		return
	var instance: Node = packed.instantiate()
	map_root.add_child(instance)
	_optimise_meshes(instance)
	_build_collision(instance)
	_build_safety_floor(instance)
	_sync_transforms(map_root)

	nav_region = CBNavMeshBuilder.build(self)
	if nav_region != null:
		# The region must be inside the tree before agents query the map.
		nav_region.visible = false
	map_ready.emit(nav_region)


## Attach a triangle collision shape to every MeshInstance3D of the map and tag the
## resulting bodies so raycasts/character bodies resolve against real geometry.
func _build_collision(root: Node) -> void:
	var body := StaticBody3D.new()
	body.name = "MapCollision"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	var shapes := 0
	var body_inv = body.global_transform.affine_inverse()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# the exported GLB nests every wall under scaled/translated nodes, so the
		# collision shape must use the *global* transform of the mesh instance
		var shape = mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var cs := CollisionShape3D.new()
		cs.name = "Col_%s" % mi.name
		cs.shape = shape
		cs.transform = body_inv * mi.global_transform
		body.add_child(cs)
		shapes += 1
	if shapes == 0:
		push_warning("CBMapLoader: no collision shapes generated (map instantiated?)")
	body.add_to_group(Game.GROUP_WORLD)


## A very large box under the map catches any bug that would drop the player out.
func _build_safety_floor(root: Node) -> void:
	var bounds := _bounds_of(root)
	if bounds.size == Vector3.ZERO:
		return
	var min_y = bounds.position.y - 1.5
	var floor_body := StaticBody3D.new()
	floor_body.name = "SafetyFloor"
	floor_body.collision_layer = LAYER_WORLD
	floor_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(bounds.size.x + 60.0, 1.0, bounds.size.z + 60.0)
	cs.shape = box
	cs.position = Vector3(bounds.position.x + bounds.size.x * 0.5, min_y, bounds.position.z + bounds.size.z * 0.5)
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.add_to_group(Game.GROUP_WORLD)


func _bounds_of(root: Node) -> AABB:
	var acc := AABB()
	var first: bool = true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box = mi.global_transform * mi.mesh.get_aabb()
		acc = box if first else acc.merge(box)
		first = false
	return acc


## Trivial optimisation pass: the map materials are already shared per-object, so
## we only make sure meshes cast/receive shadows consistently and distance-sort
## decals after geometry. Keeps the draw-call budget predictable on GLES3.
func _optimise_meshes(root: Node) -> void:
	var shadows := Settings.get_int("graphics_quality") > 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# distance-fade is unnecessary for a small map; keep meshes always visible
		mi.visibility_range_end = 0.0
		if mi.mesh != null and mi.material_override == null:
			_apply_material_polish(mi)


## The GLB materials are kept exactly as authored; this only sets the mobile-friendly
## sampler settings (no cost, no visual change other than crisper texels at distance)
## and disables the per-pixel specular lobe that GLES3 otherwise evaluates on every
## map surface.
func _apply_material_polish(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var mat: Material = mi.mesh.surface_get_material(i)
		var std := mat as StandardMaterial3D
		if std == null:
			continue
		if Settings.get_int("graphics_quality") == 0:
			# duplicate so the change is local to this instance (the menu backdrop keeps
			# the pristine authored material)
			var local := std.duplicate() as StandardMaterial3D
			if local != null:
				local.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mi.set_surface_override_material(i, local)


func _sync_transforms(node: Node) -> void:
	if node is Node3D:
		(node as Node3D).force_update_transform()
	for child in node.get_children():
		_sync_transforms(child)


# ---------------------------------------------------------------- spawning
## Snap a requested spawn to the floor using a downward raycast. Falls back to a
## known-good baked spawn when the requested point is inside geometry.
func resolve_spawn(team: int, index: int, height_above: float = 0.05) -> Vector3:
	var points: Array = _spawn_points.get(team, [])
	if points.is_empty():
		points = CBNavMeshData.spawn_points(team)
		_spawn_points[team] = points
	if points.is_empty():
		return Vector3(0, 1010, 1200)
	var base: Vector3 = points[index % points.size()]
	for attempt in points.size():
		var candidate: Vector3 = points[(index + attempt) % points.size()]
		var grounded := _snap_to_floor(candidate, height_above)
		if grounded != Vector3.INF:
			return grounded
	return _snap_to_floor(base, height_above)


func _snap_to_floor(point: Vector3, height_above: float) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return Vector3(point.x, point.y + height_above, point.z)
	var from := Vector3(point.x, point.y + 3.0, point.z)
	var to := Vector3(point.x, point.y - 6.0, point.z)
	var query := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	var hit = space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	var pos: Vector3 = hit.get("position", Vector3.ZERO)
	return Vector3(point.x, pos.y + height_above, point.z)


## Random spawn point for a team that is clear of other combatants.
func pick_spawn(team: int, avoid: Array[Node3D]) -> Vector3:
	var count = CBNavMeshData.spawn_points(team).size()
	var offset = randi() % maxi(1, count)
	var space := get_world_3d().direct_space_state
	for i in count:
		var pos := resolve_spawn(team, offset + i)
		if _spawn_is_clear(pos, avoid):
			return pos
	# Every candidate was occupied: fall back to the least crowded one so the respawn
	# always happens on valid floor geometry.
	var best := resolve_spawn(team, offset)
	var best_dist := -1.0
	for i in count:
		var pos := resolve_spawn(team, offset + i)
		var nearest := 999.0
		for other in avoid:
			if other == null or not is_instance_valid(other):
				continue
			nearest = minf(nearest, other.global_position.distance_squared_to(pos))
		if nearest > best_dist:
			best_dist = nearest
			best = pos
	return best


## A spawn is valid when no other combatant is within 1.6 m and the space a 1.75 m
## capsule would occupy is empty (the baked spawns are already on open floor, this
## guards against a body standing on the spot).
func _spawn_is_clear(pos: Vector3, avoid: Array[Node3D]) -> bool:
	for other in avoid:
		if other == null or not is_instance_valid(other):
			continue
		if other.global_position.distance_squared_to(pos) < 1.6 * 1.6:
			return false
	return _capsule_space_free(pos)


func _capsule_space_free(pos: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var space := world.direct_space_state
	if space == null:
		return true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.7
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.85, 0))
	params.collision_mask = LAYER_WORLD | LAYER_COMBATANT
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hits = space.intersect_shape(params, 1)
	return hits.is_empty()
