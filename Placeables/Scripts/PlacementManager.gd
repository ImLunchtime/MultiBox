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
		return null
	var ps: PackedScene = load(scene_path)
	if ps == null:
		return null
	var node: Node3D = ps.instantiate()
	node.name = "Placeable_" + uuid
	_get_or_create_root().add_child(node, true)
	node.global_transform = t
	placed[uuid] = node.get_path()
	return node

@rpc("any_peer", "reliable")
func server_place_item(id: String, t: Transform3D):
	if multiplayer.is_server():
		_id_counter += 1
		var uuid = str(multiplayer.get_unique_id()) + "_" + str(_id_counter)
		var node = _spawn_item_instance(id, uuid, t)
		if node == null:
			return
		rpc("client_spawn_item", uuid, id, t)

@rpc("any_peer", "reliable")
func client_spawn_item(uuid: String, id: String, t: Transform3D):
	if multiplayer.is_server():
		return
	_spawn_item_instance(id, uuid, t)

func place_item(id: String, t: Transform3D):
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			server_place_item(id, t)
		else:
			server_place_item.rpc(id, t)
	else:
		_id_counter += 1
		var uuid = "local_" + str(_id_counter)
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
	_update_player_input(false)
	_show_mouse(true)
	_create_preview(id)

func begin_remove():
	current_id = ""
	active = true
	remove_mode = true
	set_process(true)
	_update_player_input(false)
	_show_mouse(true)
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
		if res:
			var pos: Vector3 = res.position
			var cam = _get_local_camera()
			if cam:
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
							server_remove_item.rpc(uuid)
			else:
				if preview_instance:
					var t = preview_instance.global_transform
					place_item(current_id, t)
					_clear_preview()
					_create_preview(current_id)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
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
	return space.intersect_ray(params)

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

func _clear_preview():
	if preview_instance and preview_instance.is_inside_tree():
		if preview_instance.has_meta("is_preview") and preview_instance.get_meta("is_preview") == true:
			preview_instance.queue_free()
	preview_instance = null

func _disable_collision_recursive(n: Node):
	if n is CollisionObject3D:
		n.collision_layer = 0
		n.collision_mask = 0
	for c in n.get_children():
		_disable_collision_recursive(c)

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
