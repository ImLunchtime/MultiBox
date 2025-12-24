extends Node

var items := {}
signal changed


func _enter_tree():
	register_item("k_claw_machine", "res://Placeables/KClawMachine.tscn", "[Kenney] Claw Machine", "", "Props")
	register_item("k_cash_register", "res://Placeables/KCashRegister.tscn", "[Kenney] Cash Register", "", "Props")

func register_item(id: String, scene_path: String, display_name: String, icon_path: String = "", category: String = "Props"):
	items[id] = {
		"id": id,
		"scene_path": scene_path,
		"name": display_name,
		"icon_path": icon_path,
		"category": category
	}
	changed.emit()

func get_items() -> Array:
	return items.values()

func get_item(id: String):
	return items.get(id, null)

func get_scene_path(id: String) -> String:
	var it = get_item(id)
	if it:
		return it.get("scene_path", "")
	return ""
