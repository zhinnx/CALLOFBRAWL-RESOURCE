## CALLOFBRAWL — builds AK-47 view models from the provided asset.
##
## The provided ak47_with_scope.glb is a Sketchfab FBX export whose glTF units are
## effectively centimetres-metres: measured directly from the binary (not assumed):
##   * scene-root bounding box: 970.1 x 86.6 x 386.2 units (length x width x height)
##   * the barrel runs along X with the muzzle at POSITIVE X (+485) and the stock at
##     -485; the magazine and scope give the 386-unit height
##   * therefore the model must be scaled by ~0.00102 to become a ~1.0 m rifle, and
##     rotated +90 deg around Y so the muzzle points along -Z (Godot forward)
##   * pistol grip / receiver centre sits at x = +50 units, so the mesh is shifted
##     +50 * scale along the barrel axis to put the grip on the rig origin
##
## All constants below are derived from those measurements; MUZZLE_LOCAL is the
## muzzle tip expressed in the built root's local space (barrel axis at y = 0).
class_name CBWeaponModelFactory
extends RefCounted

const GUN_SCENE_PATH := "res://ak47_with_scope.glb"

## Uniform scale that turns the 970-unit export into a ~0.99 m rifle.
const GUN_SCALE := 0.00102
## Where the mesh sits relative to the rig origin (grip on the origin, barrel axis
## at y = 0). Model-space grip = x 50 (= z -0.051 after the +90 deg yaw),
## muzzle tip y = 149 units (= -0.152 m below the origin).
const GUN_OFFSET := Vector3(0.0, -0.152, 0.051)
## Muzzle tip in rifle-local space: 435 units ahead of the grip, on the barrel axis.
const MUZZLE_LOCAL := Vector3(0.0, 0.0, -0.438)
## Distance from the grip to the muzzle (metres), used for tracer start points.
const BARREL_LENGTH := 0.438

static var _packed_cache: PackedScene


static func load_packed() -> PackedScene:
	if _packed_cache == null:
		_packed_cache = load(GUN_SCENE_PATH) as PackedScene
	return _packed_cache


## Returns a ready-to-parent Node3D whose origin is the grip and whose muzzle faces -Z.
## `tint` is applied as a very light modulate for team identification of bot Rifles.
static func build_rifle(tint: Color = Color.WHITE, with_flash: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "AK47Model"
	var packed := load_packed()
	if packed == null:
		push_error("CBWeaponModelFactory: could not load %s" % GUN_SCENE_PATH)
		return root
	var model: Node3D = packed.instantiate() as Node3D
	model.name = "AK47"
	model.scale = Vector3.ONE * GUN_SCALE
	# +90 deg about Y sends the model's +X muzzle to -Z (forward).
	model.rotation_degrees = Vector3(0, 90, 0)
	model.position = GUN_OFFSET
	root.add_child(model)
	if tint != Color.WHITE:
		_apply_tint(model, tint)
	if with_flash:
		var flash := Fx.make_muzzle_flash()
		flash.position = MUZZLE_LOCAL
		root.add_child(flash)
	return root


static func _apply_tint(model: Node3D, tint: Color) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.get_active_material(0)
		if mat is StandardMaterial3D:
			var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.albedo_color = tint
			mi.material_override = dup


## A lightweight copy for characters (bots and third-person players): no flash rig,
## no duplicated materials unless tinted.
static func build_world_rifle(tint: Color = Color.WHITE) -> Node3D:
	return build_rifle(tint, false)
