extends VBoxContainer
## A node tree bound to one ControlViewer at a time. It is repointed at the active
## viewer rather than each viewer owning a tree, so it can also live in a separate dock.

const NodeTree = preload("uid://dsbpnuf6nc8l8") #! resolve ResourceView.NodeTree

const ControlViewer = preload("uid://bd2dhwch6o144") #! resolve ResourceView.ControlViewer

var node_tree: NodeTree
## Optional drop handling for the tree: (position, data) -> bool and (position, data, host) -> void.
var can_drop_callable: Callable
var drop_callable: Callable
## Optional (path: String) handler for activated paths; defaults to opening them in the editor.
var activate_path_callable: Callable

var _host: ControlViewer


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	node_tree = NodeTree.new()
	node_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node_tree.object_selected.connect(_on_object_selected)
	node_tree.path_activated.connect(_activate_path)
	node_tree.set_drag_forwarding(Callable(), _can_drop, _drop)
	add_child(node_tree)


func get_host() -> ControlViewer:
	return _host if is_instance_valid(_host) else null


func set_host(host: ControlViewer) -> void:
	if not is_instance_valid(host):
		host = null
	if host == get_host():
		return
	var old = get_host()
	# Unrouted while repointing: clearing the old root emits a null selection meant for nobody.
	_host = null
	if old != null:
		old.tree_state = node_tree.get_tree_state()
		old.preview_changed.disconnect(node_tree.set_root_node)
		old.object_picked.disconnect(_on_object_picked)
	if host != null:
		node_tree.set_root_node(host.preview, host.tree_state)
		host.preview_changed.connect(node_tree.set_root_node)
		host.object_picked.connect(_on_object_picked)
	else:
		node_tree.clear_root()
	_host = host


func _on_object_selected(object: Object) -> void:
	if get_host() != null:
		_host.select_object(object)


# Re-selecting the current row emits nothing, and a missing row can't, so select directly then.
func _on_object_picked(object: Object) -> void:
	var item = node_tree.tree_items.get(object)
	var already = item != null and node_tree.get_selected() == item
	if (not node_tree.select_object(object) or already) and get_host() != null:
		_host.select_object(object)


func _activate_path(path: String) -> void:
	if activate_path_callable.is_valid():
		activate_path_callable.call(path)
		return
	if not Engine.is_editor_hint() or not ResourceLoader.exists(path):
		return
	if path.get_extension().to_lower() in ["tscn", "scn"]:
		EditorInterface.open_scene_from_path(path)
	else:
		var resource = load(path)
		if resource is Script:
			EditorInterface.edit_script(resource)
		else:
			EditorInterface.edit_resource(resource)


func _can_drop(position: Vector2, data: Variant) -> bool:
	return can_drop_callable.is_valid() and drop_callable.is_valid() and can_drop_callable.call(position, data)


func _drop(position: Vector2, data: Variant) -> void:
	if _can_drop(position, data):
		drop_callable.call(position, data, get_host())
