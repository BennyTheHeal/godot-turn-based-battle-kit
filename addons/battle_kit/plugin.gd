@tool
extends EditorPlugin
## Turn-Based Battle Kit needs Inventory Kit (addons/inventory_kit/) in the same project.


func _enter_tree() -> void:
	if not DirAccess.dir_exists_absolute("res://addons/inventory_kit/"):
		push_warning("Turn-Based Battle Kit needs Inventory Kit in res://addons/inventory_kit/ "
			+ "(pay what you want: https://banc-essai.site-testeurs.workers.dev/inventory-kit/).")
