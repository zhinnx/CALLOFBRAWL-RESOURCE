## CALLOFBRAWL — in-engine self test.
##
## Run inside Godot (no window needed):
##
##   godot --headless --path . --script res://scripts/dev/selftest.gd
##
## It exercises the parts that a static parser cannot check: that every resource
## loads and instantiates, that the navmesh produces a connected graph with valid
## spawns, that the A* returns real paths, that the weapon resource matches the
## documented stats, that settings round-trip through the config file, and that the
## match rules (5 v 5, friendly fire off, score limit) behave as specified.
##
## Exit code 0 = all checks passed, 1 = at least one failure.
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	print("\n=== CALLOFBRAWL self test ===\n")
	_check_resources()
	_check_navmesh()
	_check_astar()
	_check_weapon()
	_check_settings()
	_check_teams()
	_check_instantiation()
	print("\n=== %d passed, %d failed ===\n" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  PASS  %s%s" % [label, "" if detail == "" else "  (%s)" % detail])
	else:
		_fail += 1
		printerr("  FAIL  %s%s" % [label, "" if detail == "" else "  (%s)" % detail])


# ---------------------------------------------------------------- resources
func _check_resources() -> void:
	print("[scripts + resources]")
	var script_dir := DirAccess.open("res://scripts")
	if script_dir != null:
		var missing_scripts := 0
		var count := 0
		for sub: String in script_dir.get_directories():
			var inner := DirAccess.open("res://scripts/%s" % sub)
			if inner == null:
				continue
			for f: String in inner.get_files():
				if not f.ends_with(".gd"):
					continue
				count += 1
				if load("res://scripts/%s/%s" % [sub, f]) == null:
					missing_scripts += 1
					printerr("    cannot load res://scripts/%s/%s" % [sub, f])
		_ok("all %d scripts load" % count, missing_scripts == 0, "%d failed" % missing_scripts)
	var paths := [
		"res://de_dust2_-_cs_map.glb",
		"res://army_character_1.glb",
		"res://ak47_with_scope.glb",
		"res://resources/weapons/ak47.tres",
		"res://resources/navigation/navmesh_dust2.json",
		"res://scenes/main/main.tscn",
		"res://scenes/menus/main_menu.tscn",
		"res://scenes/gameplay/gameplay.tscn",
		"res://icon.svg",
	]
	for p: String in paths:
		var res: Resource = load(p)
		_ok("load %s" % p, res != null)


# ---------------------------------------------------------------- navmesh
func _check_navmesh() -> void:
	print("[navmesh]")
	var verts := CBNavMeshData.vertices()
	var polys: Array = CBNavMeshData.polygons()
	var adj := CBNavMeshData.adjacency()
	_ok("vertices > 0", verts.size() > 1000, "%d" % verts.size())
	_ok("polygons > 0", polys.size() > 1000, "%d" % polys.size())
	_ok("adjacency matches polygons", adj.size() == polys.size())
	var isolated := 0
	for i in adj.size():
		var list: PackedInt32Array = adj[i]
		if list.size() == 0:
			isolated += 1
	_ok("no isolated polygons", isolated == 0, "%d isolated" % isolated)

	var spawn_a := CBNavMeshData.spawn_points(CBTeam.ALPHA)
	var spawn_b := CBNavMeshData.spawn_points(CBTeam.BRAVO)
	_ok(">= 5 spawns per team", spawn_a.size() >= 5 and spawn_b.size() >= 5,
			"A=%d B=%d" % [spawn_a.size(), spawn_b.size()])
	var min_sep := 999.0
	for a: Vector3 in spawn_a:
		for b: Vector3 in spawn_b:
			min_sep = minf(min_sep, a.distance_to(b))
	_ok("teams spawn apart", min_sep > 25.0, "%.1f m" % min_sep)
	var closest := 999.0
	for i in spawn_a.size():
		for j in range(i + 1, spawn_a.size()):
			closest = minf(closest, (spawn_a[i] as Vector3).distance_to(spawn_a[j] as Vector3))
	_ok("spawn spacing >= 1.5 m", closest >= 1.5, "%.2f m" % closest)

	for s: Vector3 in spawn_a + spawn_b:
		_ok("spawn on mesh %s" % str(s.round()), CBNavMeshData.is_on_mesh(s, 1.0))
	var pois := CBNavMeshData.points_of_interest()
	_ok("points of interest >= 20", pois.size() >= 20, "%d" % pois.size())


# ---------------------------------------------------------------- A*
func _check_astar() -> void:
	print("[pathfinding]")
	var spawn_a := CBNavMeshData.spawn_points(CBTeam.ALPHA)
	var spawn_b := CBNavMeshData.spawn_points(CBTeam.BRAVO)
	var found := 0
	var worst := 0
	for i in spawn_a.size():
		var from: Vector3 = spawn_a[i]
		var to: Vector3 = spawn_b[i % spawn_b.size()]
		var path := CBNavMeshData.find_path(from, to)
		if path.size() > 1:
			found += 1
			var points := CBNavMeshData.path_points(path)
			worst = maxi(worst, points.size())
	_ok("cross-map paths found for all spawn pairs", found == spawn_a.size(), "%d/%d" % [found, spawn_a.size()])
	_ok("path simplification keeps waypoints bounded", worst > 2 and worst < 200, "max %d waypoints" % worst)
	var pois := CBNavMeshData.points_of_interest()
	var reachable := 0
	for p: Vector3 in pois:
		if CBNavMeshData.find_path(spawn_a[0], p).size() > 1:
			reachable += 1
	_ok("most PoIs reachable from spawn A", reachable >= int(pois.size() * 0.8),
			"%d/%d" % [reachable, pois.size()])


# ---------------------------------------------------------------- weapon
func _check_weapon() -> void:
	print("[weapon data]")
	var data := load("res://resources/weapons/ak47.tres") as CBWeaponData
	_ok("resource typed CBWeaponData", data != null)
	if data == null:
		return
	_ok("600 RPM", is_equal_approx(data.rounds_per_minute, 600.0))
	_ok("fire interval = 0.1 s", is_equal_approx(data.fire_interval(), 0.1))
	_ok("30 round magazine", data.magazine_size == 30)
	_ok("120 reserve", data.reserve_ammo == 120)
	_ok("25 body damage", is_equal_approx(data.damage_body, 25.0))
	_ok("100 headshot damage", is_equal_approx(data.damage_head, 100.0))
	_ok("automatic", data.automatic)
	_ok("muzzle sound exists in the audio cache", Audio.has_sound(data.muzzle_sound))


# ---------------------------------------------------------------- settings
func _check_settings() -> void:
	print("[settings]")
	_ok("score limit default 50", Settings.get_int("score_limit") == 50)
	_ok("match length default 10 min", is_equal_approx(Settings.get_float("match_minutes"), 10.0))
	_ok("respawn default 3 s", is_equal_approx(Settings.get_float("respawn_delay"), 3.0))
	_ok("aim assist default on", Settings.get_bool("aim_assist"))
	var before := Settings.get_float("look_sensitivity")
	Settings.set_value("look_sensitivity", 0.77)
	Settings.save_settings()
	Settings.load_settings()
	_ok("settings persist through the config file",
			is_equal_approx(Settings.get_float("look_sensitivity"), 0.77),
			"value %s" % str(Settings.get_float("look_sensitivity")))
	Settings.set_value("look_sensitivity", before)
	Settings.save_settings()


# ---------------------------------------------------------------- teams / rules
func _check_teams() -> void:
	print("[team rules]")
	_ok("friendly fire rejected", CBTeam.is_friendly(CBTeam.ALPHA, CBTeam.ALPHA))
	_ok("enemy is not friendly", not CBTeam.is_friendly(CBTeam.ALPHA, CBTeam.BRAVO))
	_ok("NONE team is never friendly", not CBTeam.is_friendly(CBTeam.NONE, CBTeam.ALPHA))


# ---------------------------------------------------------------- scene instantiation
func _check_instantiation() -> void:
	print("[instantiation]")
	var map_scene := load("res://de_dust2_-_cs_map.glb") as PackedScene
	_ok("map GLB is a PackedScene", map_scene != null)
	if map_scene != null:
		var map: Node = map_scene.instantiate()
		_ok("map instantiates", map != null)
		var meshes := map.find_children("*", "MeshInstance3D", true, false)
		_ok("map has mesh instances", meshes.size() > 20, "%d meshes" % meshes.size())
		map.free()

	var char_scene := load("res://army_character_1.glb") as PackedScene
	if char_scene != null:
		var body: Node = char_scene.instantiate()
		var body_meshes := body.find_children("*", "MeshInstance3D", true, false)
		_ok("character has 7 mesh instances", body_meshes.size() == 7, "%d" % body_meshes.size())
		body.free()

	var gun_scene := load("res://ak47_with_scope.glb") as PackedScene
	if gun_scene != null:
		var gun: Node = gun_scene.instantiate()
		var gun_meshes := gun.find_children("*", "MeshInstance3D", true, false)
		_ok("rifle has mesh instances", gun_meshes.size() >= 2, "%d" % gun_meshes.size())
		gun.free()

	# nav region constructor must accept the baked lattice
	var host := Node3D.new()
	root.add_child(host)
	var region := CBNavMeshBuilder.build(host)
	_ok("NavigationRegion3D built", region != null)
	if region != null and region.navigation_mesh != null:
		var nm := region.navigation_mesh
		_ok("navmesh has vertices", nm.vertices.size() > 1000, "%d" % nm.vertices.size())
		_ok("navmesh has polygons", nm.get_polygon_count() > 1000, "%d" % nm.get_polygon_count())
		# every emitted triangle must resolve to real vertices
		var bad_index := 0
		var vcount := nm.vertices.size()
		for p_i in nm.get_polygon_count():
			for idx: int in nm.get_polygon(p_i):
				if idx < 0 or idx >= vcount:
					bad_index += 1
		_ok("navmesh polygon indices valid", bad_index == 0, "%d bad" % bad_index)
	host.queue_free()

	# the gameplay scene must instantiate and wire itself without a display
	var gp_scene := load("res://scenes/gameplay/gameplay.tscn") as PackedScene
	if gp_scene != null:
		var gp: Node = gp_scene.instantiate()
		_ok("gameplay scene instantiates", gp != null)
		gp.free()
