## CALLOFBRAWL — builds the runtime navigation for de_dust2.
##
## Two cooperating pieces:
##  1. `NavigationRegion3D` + `NavigationMesh` built from the baked lattice, so any
##     engine-side navigation (and the optional NavigationAgent3D debug view) matches
##     the same walkable surface the bots use.
##  2. The authoritative graph used by the bots is the baked adjacency list shipped
##     inside navmesh_dust2.json (CBNavMeshData.find_path): integer A*, no mesh
##     parsing cost, no dependence on the runtime mesh parser's edge requirements.
##
## Quad cells are emitted as two triangles each because a NavigationMesh polygon must
## be convex — that keeps the region valid even for cells that straddle a step.
class_name CBNavMeshBuilder
extends RefCounted

## Small height offset so navigation polygons sit just above the visual floor.
const Y_OFFSET := 0.05


static func build(parent: Node3D) -> NavigationRegion3D:
	var verts := CBNavMeshData.vertices()
	var polys: Array = CBNavMeshData.polygons()
	if verts.is_empty() or polys.is_empty():
		push_error("CBNavMeshBuilder: no navigation data available")
		return null

	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.1
	nav_mesh.agent_radius = 0.4
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.agent_max_slope = 50.0

	var out_verts := PackedVector3Array()
	var triangles: Array = []
	for poly: Array in polys:
		if poly.size() < 3:
			continue
		var base := out_verts.size()
		for v: Variant in poly:
			var p: Vector3 = verts[int(v)]
			out_verts.append(Vector3(p.x, p.y + Y_OFFSET, p.z))
		if poly.size() == 4:
			# quad -> two triangles (0,1,2) and (0,2,3)
			triangles.append(PackedInt32Array([base, base + 1, base + 2]))
			triangles.append(PackedInt32Array([base, base + 2, base + 3]))
		else:
			for i in range(1, poly.size() - 1):
				triangles.append(PackedInt32Array([base, base + i, base + i + 1]))

	nav_mesh.vertices = out_verts
	for tri: PackedInt32Array in triangles:
		nav_mesh.add_polygon(tri)

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	region.navigation_mesh = nav_mesh
	parent.add_child(region)

	var map := parent.get_world_3d().navigation_map
	NavigationServer3D.region_set_map(region.get_rid(), map)
	NavigationServer3D.region_set_enabled(region.get_rid(), true)
	return region
