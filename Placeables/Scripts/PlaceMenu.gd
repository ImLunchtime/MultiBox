extends Node

var canvas: CanvasLayer
var root: Control
var grid: GridContainer
var remove_button: Button
var visible_menu := false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	_build_ui()
	if PlaceableRegistry.has_signal("changed"):
		PlaceableRegistry.changed.connect(_rebuild_grid)
	call_deferred("_rebuild_grid")

func _build_ui():
	canvas = CanvasLayer.new()
	add_child(canvas)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	canvas.add_child(root)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_right = 360.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	root.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Place Menu"
	header.add_child(title)
	remove_button = Button.new()
	remove_button.text = "Remove Mode"
	remove_button.toggle_mode = true
	remove_button.button_pressed = false
	remove_button.toggled.connect(_on_remove_toggled)
	header.add_child(remove_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

func _rebuild_grid():
	if grid == null:
		return
	for c in grid.get_children():
		c.queue_free()
	for item in PlaceableRegistry.get_items():
		var btn := Button.new()
		btn.text = str(item.get("name", item.get("id", "")))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_item_pressed.bind(String(item.get("id", ""))))
		grid.add_child(btn)

func _on_item_pressed(id: String):
	PlacementManager.begin_place(id)

func _on_remove_toggled(pressed: bool):
	if pressed:
		PlacementManager.begin_remove()
	else:
		PlacementManager.cancel()

func _input(event):
	if event.is_action_pressed("open_place_menu"):
		_toggle_menu()

func _toggle_menu():
	if get_tree().current_scene and get_tree().current_scene.name != "GameMode":
		return
	if visible_menu:
		_hide_menu()
	else:
		_show_menu()

func _show_menu():
	visible_menu = true
	root.visible = true
	_rebuild_grid()
	PlacementManager._update_player_input(false)
	PlacementManager._show_mouse(true)

func _hide_menu():
	visible_menu = false
	root.visible = false
	remove_button.button_pressed = false
	PlacementManager.pause_preview()
	PlacementManager._update_player_input(true)
	PlacementManager._show_mouse(false)
