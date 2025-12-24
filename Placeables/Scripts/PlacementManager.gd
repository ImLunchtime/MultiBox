extends Node

var active := false
var remove_mode := false
var current_id := ""
var preview_instance: Node3D = null
var placed := {}
var _id_counter := 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_process_input(true)

func _spawn_item_instance(id: String, uuid: String, t: Transform3D) -> Node3D:
	var scene_path = PlaceableRegistry.get_scene_path(id)
	if scene_path == "":
		print("Placeables: spawn failed, empty scene_path for id=", id)
		return null
	var ps: PackedScene = load(scene_path)
	if ps == null:
		print("Placeables: spawn failed, cannot load PackedScene at ", scene_path)
		return null
	var node: Node3D = ps.instantiate()
	node.name = "Placeable_" + uuid
	_get_or_create_root().add_child(node, true)
	node.global_transform = t
	placed[uuid] = node.get_path()
	_ensure_collision_for_item(node)
	print("Placeables: spawned real item id=", id, " uuid=", uuid, " path=", placed[uuid], " pos=", t.origin)
	return node

@rpc("any_peer", "reliable")
func server_place_item(id: String, t: Transform3D):
	if multiplayer.is_server():
		_id_counter += 1
		var uuid = str(multiplayer.get_unique_id()) + "_" + str(_id_counter)
		print("Placeables: server_place_item id=", id, " uuid=", uuid, " pos=", t.origin)
		var node = _spawn_item_instance(id, uuid, t)
		if node == null:
			return
		rpc("client_spawn_item", uuid, id, t)

@rpc("any_peer", "reliable")
func client_spawn_item(uuid: String, id: String, t: Transform3D):
	if multiplayer.is_server():
		return
	print("Placeables: client_spawn_item id=", id, " uuid=", uuid, " pos=", t.origin)
	_spawn_item_instance(id, uuid, t)

func place_item(id: String, t: Transform3D):
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			server_place_item(id, t)
		else:
			print("Placeables: client request server_place_item id=", id, " pos=", t.origin)
			server_place_item.rpc(id, t)
	else:
		_id_counter += 1
		var uuid = "local_" + str(_id_counter)
		print("Placeables: local_place_item id=", id, " uuid=", uuid, " pos=", t.origin)
		_spawn_item_instance(id, uuid, t)

@rpc("any_peer", "reliable")
func server_remove_item(uuid: String):
	if multiplayer.is_server():
		var node = _find_placeable_by_uuid(uuid)
		if node:
			placed.erase(uuid)
			node.queue_free()
		rpc("client_remove_item", uuid)

@rpc("any_peer", "reliable")
func client_remove_item(uuid: String):
	if multiplayer.is_server():
		return
	var node = _find_placeable_by_uuid(uuid)
	if node:
		placed.erase(uuid)
		node.queue_free()

func _find_placeable_by_uuid(uuid: String) -> Node3D:
	var path = placed.get(uuid, null)
	if path:
		var n = get_node_or_null(path)
		if n and n is Node3D:
			return n
	var root = _get_or_create_root()
	if root:
		var direct = root.get_node_or_null("Placeable_" + uuid)
		if direct and direct is Node3D:
			return direct
		for c in root.get_children():
			if c is Node3D and c.name == "Placeable_" + uuid:
				return c
	return null
func begin_place(id: String):
	remove_mode = false
	current_id = id
	active = true
	set_process(true)
	_update_player_input(true)
	_show_mouse(false)
	_clear_all_previews()
	print("Placeables: begin_place id=", id)
	_create_preview(id)

func begin_remove():
	current_id = ""
	active = true
	remove_mode = true
	set_process(true)
	_update_player_input(false)
	_show_mouse(true)
	_clear_all_previews()
	print("Placeables: begin_remove")
	_clear_preview()

func cancel():
	active = false
	remove_mode = false
	current_id = ""
	set_process(false)
	_update_player_input(true)
	_show_mouse(false)
	_clear_preview()

func pause_preview():
	active = false
	remove_mode = false
	current_id = ""
	set_process(false)
	_update_player_input(true)
	_show_mouse(false)

func _process(delta):
	if not active:
		return
	if remove_mode:
		return
	if preview_instance:
		var res = _raycast_from_center(50.0)
		var cam = _get_local_camera()
		if cam:
			var pos: Vector3
			if res:
				pos = res.position
			else:
				var fwd: Vector3 = -cam.global_transform.basis.z.normalized()
				pos = cam.global_transform.origin + fwd * 2.0
			var yaw = cam.global_transform.basis.get_euler().y
			var basis = Basis.from_euler(Vector3(0, yaw, 0))
			preview_instance.global_transform = Transform3D(basis, pos)

func _input(event):
	if not active:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if remove_mode:
				var hit = _raycast_from_center(100.0)
				if hit and hit.collider:
					var node = _get_placeable_root(hit.collider)
					if node:
						var uuid = _uuid_from_name(node.name)
						if uuid != "":
							print("Placeables: request remove uuid=", uuid)
							server_remove_item.rpc(uuid)
			else:
				# In preview placement mode, ignore left click (use E to confirm)
				pass
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			print("Placeables: right click cancel")
			cancel()
	if event.is_action_pressed("open_place_menu") and active and not remove_mode:
		if preview_instance:
			var t = preview_instance.global_transform
			print("Placeables: confirm via E, placing id=", current_id)
			place_item(current_id, t)
		cancel()
	if event.is_action_pressed("cancel_preview") and active:
		print("Placeables: cancel via Q")
		cancel()

func _get_local_camera() -> Camera3D:
	var scene = get_tree().current_scene
	if not scene:
		return null
	var best: Camera3D = null
	for n in scene.get_children():
		if n is Node3D:
			var cam: Camera3D = n.get_node_or_null("Camera3D")
			if cam and n.has_method("is_multiplayer_authority") and n.is_multiplayer_authority():
				best = cam
				break
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority() and p.has_node("Camera3D"):
			return p.get_node("Camera3D")
	return best

func _raycast_from_center(max_distance: float):
	var cam = _get_local_camera()
	if not cam:
		return null
	var vp = get_viewport()
	var size = vp.get_visible_rect().size
	var center = Vector2(size.x * 0.5, size.y * 0.5)
	var from = cam.project_ray_origin(center)
	var dir = cam.project_ray_normal(center)
	var to = from + dir * max_distance
	var space = cam.get_world_3d().direct_space_state
	var params = PhysicsRayQueryParameters3D.create(from, to)
	var hit = space.intersect_ray(params)
	return hit

func _update_player_input(enabled: bool):
	var scene = get_tree().current_scene
	if not scene:
		return
	for n in scene.get_children():
		if n.has_method("is_multiplayer_authority") and n.is_multiplayer_authority():
			if n.has_method("set_input_enabled"):
				n.set_input_enabled(enabled)

func _show_mouse(visible: bool):
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED)

func _create_preview(id: String):
	_clear_preview()
	var scene_path = PlaceableRegistry.get_scene_path(id)
	if scene_path == "":
		return
	var ps: PackedScene = load(scene_path)
	if ps == null:
		return
	var inst: Node3D = ps.instantiate()
	_disable_collision_recursive(inst)
	_get_or_create_preview_root().add_child(inst)
	inst.set_meta("is_preview", true)
	preview_instance = inst
	print("Placeables: created preview id=", id, " name=", inst.name)
	_add_preview_outline(inst)

func _clear_preview():
	if preview_instance and preview_instance.is_inside_tree():
		if preview_instance.has_meta("is_preview") and preview_instance.get_meta("is_preview") == true:
			var out = preview_instance.get_node_or_null("__PreviewOutline")
			if out:
				out.queue_free()
			preview_instance.queue_free()
			print("Placeables: cleared preview name=", preview_instance.name)
	preview_instance = null

func _clear_all_previews():
	var root = _get_or_create_preview_root()
	if not root:
		return
	var count := 0
	for c in root.get_children():
		if c.has_meta("is_preview") and c.get_meta("is_preview") == true:
			var out = c.get_node_or_null("__PreviewOutline")
			if out:
				out.queue_free()
			c.queue_free()
			count += 1
	if count > 0:
		print("Placeables: cleared stray previews count=", count)

func _add_preview_outline(inst: Node3D):
	var aabb := _compute_preview_aabb(inst)
	var center := aabb.position + aabb.size * 0.5
	var box := BoxMesh.new()
	box.size = aabb.size + Vector3(0.05, 0.05, 0.05)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0, 1, 0, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var outline := MeshInstance3D.new()
	outline.name = "__PreviewOutline"
	outline.mesh = box
	outline.material_override = mat
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline.transform.origin = center
	inst.add_child(outline)

func _compute_preview_aabb(root: Node3D) -> AABB:
	var min := Vector3(1e20, 1e20, 1e20)
	var max := Vector3(-1e20, -1e20, -1e20)
	_collect_aabb(root, Transform3D.IDENTITY, min, max)
	if min.x > 9e19:
		return AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))
	return AABB(min, max - min)

func _collect_aabb(n: Node, xform: Transform3D, min: Vector3, max: Vector3):
	if n is Node3D:
		var nn: Node3D = n
		var nxform: Transform3D = xform * nn.transform
		for c in nn.get_children():
			_collect_aabb(c, nxform, min, max)
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		if mi.mesh:
			var a: AABB = mi.mesh.get_aabb()
			_update_min_max_aabb(a, xform * mi.transform, min, max)
	elif n is CollisionShape3D:
		var cs: CollisionShape3D = n
		var he: Vector3 = Vector3(0.5, 0.5, 0.5)
		if cs.shape is BoxShape3D:
			var bx: BoxShape3D = cs.shape
			he = bx.size * 0.5
		elif cs.shape is SphereShape3D:
			var sr: SphereShape3D = cs.shape
			var rr: float = sr.radius
			he = Vector3(rr, rr, rr)
		elif cs.shape is CapsuleShape3D:
			var cap: CapsuleShape3D = cs.shape
			var rc: float = cap.radius
			var hc: float = cap.height * 0.5 + rc
			he = Vector3(rc, hc, rc)
		elif cs.shape is CylinderShape3D:
			var cyl: CylinderShape3D = cs.shape
			var rcyl: float = cyl.radius
			var hcyl: float = cyl.height * 0.5
			he = Vector3(rcyl, hcyl, rcyl)
		var a2: AABB = AABB(-he, he * 2.0)
		_update_min_max_aabb(a2, xform * cs.transform, min, max)

func _update_min_max_aabb(a: AABB, xf: Transform3D, min: Vector3, max: Vector3):
	for dx in range(2):
		for dy in range(2):
			for dz in range(2):
				var p: Vector3 = a.position + Vector3(dx, dy, dz) * a.size
				var wp: Vector3 = xf * p
				min.x = min(min.x, wp.x)
				min.y = min(min.y, wp.y)
				min.z = min(min.z, wp.z)
				max.x = max(max.x, wp.x)
				max.y = max(max.y, wp.y)
				max.z = max(max.z, wp.z)

func _disable_collision_recursive(n: Node):
	if n is CollisionObject3D:
		n.collision_layer = 0
		n.collision_mask = 0
	for c in n.get_children():
		_disable_collision_recursive(c)

func _has_collision_recursive(n: Node) -> bool:
	if n is CollisionObject3D:
		return true
	if n is Node:
		for c in n.get_children():
			if _has_collision_recursive(c):
				return true
	return false

func _normalize_collision_recursive(n: Node):
	if n is CollisionObject3D:
		var co: CollisionObject3D = n
		if co.collision_layer == 0:
			co.collision_layer = 1
		if co.collision_mask == 0:
			co.collision_mask = 1
	if n is Node:
		for c in n.get_children():
			_normalize_collision_recursive(c)

func _ensure_collision_for_item(inst: Node3D):
	if _has_collision_recursive(inst):
		_normalize_collision_recursive(inst)
		print("Placeables: normalized existing colliders for ", inst.name)
		return
	var aabb := _compute_preview_aabb(inst)
	var center := aabb.position + aabb.size * 0.5
	var body := StaticBody3D.new()
	body.name = "__AutoStaticBody"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := BoxShape3D.new()
	shape.size = aabb.size
	var col := CollisionShape3D.new()
	col.name = "__AutoCollision"
	col.shape = shape
	body.transform.origin = center
	body.add_child(col)
	inst.add_child(body)
	print("Placeables: added auto collider to ", inst.name, " size=", aabb.size, " center=", center)

func _get_or_create_root() -> Node3D:
	var scene = get_tree().current_scene
	if not scene:
		return null
	var root = scene.get_node_or_null("PlaceablesRoot")
	if not root:
		root = Node3D.new()
		root.name = "PlaceablesRoot"
		scene.add_child(root, true)
	return root

func _get_or_create_preview_root() -> Node3D:
	var scene = get_tree().current_scene
	if not scene:
		return null
	var root = scene.get_node_or_null("PlacePreviewRoot")
	if not root:
		root = Node3D.new()
		root.name = "PlacePreviewRoot"
		scene.add_child(root, true)
	return root

func _get_placeable_root(n: Node) -> Node3D:
	var cur = n
	while cur:
		if cur.name.begins_with("Placeable_"):
			return cur
		cur = cur.get_parent()
	return null

func _uuid_from_name(name: String) -> String:
	if name.begins_with("Placeable_"):
		return name.substr(10, name.length() - 10)
	return ""
