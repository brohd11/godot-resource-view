#! namespace ResourceView class NodeTree
@tool
extends Tree

signal object_selected(object: Object)
signal item_right_clicked(path: String)
signal path_activated(path: String)

const PATH_BUTTON = 0
const SCRIPT_BUTTON = 1
const EDIT_BUTTON = 2
const VISIBILITY_BUTTON = 5

var owned_only := false
var show_resources := false
var show_scripts := true
var tooltip_callable: Callable

var current_scene_path := ""
var current_scene_instance: Node
var tree_items: Dictionary = {}

var _owned_root: Node
var _watched: Array[Node] = []
var _refresh_queued := false
var _rebuilding := false
var _empty_message := "No node loaded"
# Applied by the next refresh, which waits until the tree is visible.
var _pending_state: Dictionary = {}
var _state_pending := false


func _init() -> void:
	allow_rmb_select = true
	item_selected.connect(_on_item_selected)
	item_activated.connect(_on_item_activated)
	item_mouse_selected.connect(_on_item_mouse_selected)
	button_clicked.connect(_on_button_clicked)
	visibility_changed.connect(_queue_refresh)
	clear_tree()


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
	_queue_refresh()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_on_filesystem_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_disconnect_watched()
		if is_instance_valid(_owned_root):
			_owned_root.free()


## The caller owns this root. No scene ownership is required for its descendants.
## [param state] comes from [method get_tree_state], restoring collapse and selection for this root.
func set_root_node(root: Node, state: Dictionary = {}) -> void:
	if is_instance_valid(root) and root == current_scene_instance:
		refresh()
		return
	clear_root()
	_pending_state = state
	_state_pending = not state.is_empty()
	if is_instance_valid(root):
		current_scene_instance = root
		current_scene_path = root.scene_file_path
	refresh()


func clear_root(message := "No node loaded") -> void:
	_disconnect_watched()
	_state_pending = false
	_pending_state = {}
	current_scene_instance = null
	current_scene_path = ""
	clear_tree(message)
	object_selected.emit(null)
	if is_instance_valid(_owned_root):
		_owned_root.free()
	_owned_root = null


func send_scene_instance(scene_instance: Node) -> void:
	set_root_node(scene_instance)


func send_scene_path(path: String) -> void:
	clear_root()
	current_scene_path = path
	var packed = ResourceLoader.load(path, "PackedScene") as PackedScene if ResourceLoader.exists(path) else null
	if packed == null:
		clear_tree("Could not load path: %s" % path)
		return
	_owned_root = packed.instantiate()
	current_scene_instance = _owned_root
	refresh()


func clear_tree(message := "No node loaded", clear_current_scene := false) -> void:
	if clear_current_scene:
		clear_root(message)
		return
	_empty_message = message
	clear()
	tree_items.clear()
	var item = create_item()
	item.set_text(0, message)
	item.set_selectable(0, false)


func refresh() -> void:
	if not visible:
		return
	var had_selection = get_selected() != null
	var selected_object = _item_object(get_selected())
	var collapsed: Dictionary = {}
	_capture_collapsed(get_root(), collapsed)
	if _state_pending:
		collapsed = _pending_state.get("collapsed", {})
		selected_object = instance_from_id(_pending_state.get("selected", 0))
		_state_pending = false
		_pending_state = {}
	_rebuilding = true
	_disconnect_watched()
	clear()
	tree_items.clear()
	if is_instance_valid(current_scene_instance):
		_read_node(current_scene_instance, null, collapsed, selected_object)
	else:
		current_scene_instance = null
		clear_tree(_empty_message)
	_rebuilding = false
	if had_selection and get_selected() == null:
		object_selected.emit(null)


## Reveals and selects [param object]'s row, emitting [signal object_selected] like a click.
func select_object(object: Object) -> bool:
	var item: TreeItem = tree_items.get(object)
	if item == null:
		return false
	var parent = item.get_parent()
	while parent != null:
		parent.collapsed = false
		parent = parent.get_parent()
	set_selected(item, 0)
	scroll_to_item(item)
	queue_redraw()
	return true


## Collapse and selection keyed by instance id, for handing back to [method set_root_node].
func get_tree_state() -> Dictionary:
	if _state_pending:
		return _pending_state
	var collapsed: Dictionary = {}
	_capture_collapsed(get_root(), collapsed)
	var selected = _item_object(get_selected())
	return {"collapsed": collapsed, "selected": selected.get_instance_id() if selected != null else 0}


func _capture_collapsed(item: TreeItem, collapsed: Dictionary) -> void:
	if item == null:
		return
	var object = _item_object(item)
	if object != null:
		collapsed[object.get_instance_id()] = item.collapsed
	for child in item.get_children():
		_capture_collapsed(child, collapsed)


func build_tree() -> void:
	refresh()


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()


func _flush_refresh() -> void:
	_refresh_queued = false
	refresh()


func _on_filesystem_changed() -> void:
	if is_instance_valid(_owned_root):
		send_scene_path(current_scene_path)
	else:
		_queue_refresh()


func _disconnect_watched() -> void:
	for node in _watched:
		if not is_instance_valid(node):
			continue
		node.child_order_changed.disconnect(_queue_refresh)
		node.renamed.disconnect(_queue_refresh)
		node.tree_exiting.disconnect(_queue_refresh)
		if node is Node3D or node is CanvasItem:
			node.visibility_changed.disconnect(_queue_refresh)
	_watched.clear()


func _read_node(node: Node, parent: TreeItem, collapsed: Dictionary, selected_object: Object) -> void:
	node.child_order_changed.connect(_queue_refresh)
	node.renamed.connect(_queue_refresh)
	node.tree_exiting.connect(_queue_refresh)
	if node is Node3D or node is CanvasItem:
		node.visibility_changed.connect(_queue_refresh)
	_watched.append(node)
	if owned_only and node != current_scene_instance and node.owner != current_scene_instance:
		return
	var item = create_item(parent)
	tree_items[node] = item
	_set_item(item, node, str(node.name), node.scene_file_path)
	item.collapsed = collapsed.get(node.get_instance_id(), false)
	if node == selected_object:
		item.select(0)
	if show_scripts:
		var script = node.get_script() as Script
		if script != null and not script.resource_path.is_empty():
			var script_scene = _embedded_scene(script.resource_path)
			if script_scene.is_empty():
				_add_button(item, &"Script", SCRIPT_BUTTON, "Open attached script:\n%s" % script.resource_path)
			elif _is_edited_scene(script_scene):
				_add_button(item, &"Script", SCRIPT_BUTTON, "Open built-in script of:\n%s" % script_scene)
	if node is Node3D or node is CanvasItem:
		_add_button(item, &"GuiVisibilityVisible" if node.visible else &"GuiVisibilityHidden", VISIBILITY_BUTTON, "Toggle visibility")
	if show_resources and node is MeshInstance3D and node.mesh != null:
		var mesh_item = _add_resource(item, node.mesh, collapsed, selected_object)
		for surface in node.mesh.get_surface_count():
			var _material = node.mesh.surface_get_material(surface)
			if _material != null:
				_add_resource(mesh_item, _material, collapsed, selected_object)
	for child in node.get_children():
		_read_node(child, item, collapsed, selected_object)


func _add_resource(parent: TreeItem, resource: Resource, collapsed: Dictionary, selected_object: Object) -> TreeItem:
	var item = create_item(parent)
	var label = resource.resource_name if not resource.resource_name.is_empty() else resource.get_class()
	_set_item(item, resource, label, resource.resource_path)
	item.collapsed = collapsed.get(resource.get_instance_id(), false)
	if resource == selected_object:
		item.select(0)
	return item


func _set_item(item: TreeItem, object: Object, label: String, path: String) -> void:
	var embedded_in = _embedded_scene(path)
	item.set_text(0, label)
	item.set_metadata(0, {"object": object, "path": path if embedded_in.is_empty() else "", "embedded_in": embedded_in})
	var tooltip = "%s\nClass: %s" % [label, object.get_class()]
	if not embedded_in.is_empty():
		tooltip += "\nEmbedded in: %s" % embedded_in
	item.set_tooltip_text(0, tooltip)
	if not Engine.is_editor_hint():
		return
	var editor_theme = EditorInterface.get_editor_theme()
	var icon_name = object.get_class()
	item.set_icon(0, editor_theme.get_icon(icon_name if editor_theme.has_icon(icon_name, &"EditorIcons") else "Node", &"EditorIcons"))
	if not embedded_in.is_empty():
		if _is_edited_scene(embedded_in):
			_add_button(item, &"Edit", EDIT_BUTTON, "Edit embedded resource")
	elif not path.is_empty() and ResourceLoader.exists(path):
		_add_button(item, &"Load", PATH_BUTTON, "Open resource:\n%s" % path)


# ResourceLoader.exists passes for cached "::" sub-resource paths, so they need their own check.
func _embedded_scene(path: String) -> String:
	return path.get_slice("::", 0) if path.contains("::") else ""


func _is_edited_scene(scene_path: String) -> bool:
	if scene_path.is_empty() or not Engine.is_editor_hint():
		return false
	var edited = EditorInterface.get_edited_scene_root()
	return edited != null and edited.scene_file_path == scene_path


func _edit_embedded(object: Object, scene_path: String) -> void:
	if object is Resource and _is_edited_scene(scene_path):
		EditorInterface.edit_resource(object)


func _add_button(item: TreeItem, icon_name: StringName, id: int, tooltip: String) -> void:
	if Engine.is_editor_hint():
		item.add_button(0, EditorInterface.get_editor_theme().get_icon(icon_name, &"EditorIcons"), id, false, tooltip)


func _item_object(item: TreeItem) -> Object:
	if item == null:
		return null
	var metadata = item.get_metadata(0)
	if metadata is Dictionary:
		var object = metadata.get("object")
		if is_instance_valid(object):
			return object
	return null


func _on_item_selected() -> void:
	if not _rebuilding:
		object_selected.emit(_item_object(get_selected()))


func _on_item_mouse_selected(mouse_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var item = get_item_at_position(mouse_position)
	if _item_object(item) != null:
		var path: String = item.get_metadata(0).get("path", "")
		if not path.is_empty():
			item_right_clicked.emit(path)


func _on_item_activated() -> void:
	var item = get_selected()
	var object = _item_object(item)
	if object == null:
		return
	var metadata: Dictionary = item.get_metadata(0)
	var path: String = metadata.get("path", "")
	if not path.is_empty() and ResourceLoader.exists(path):
		path_activated.emit(path)
	else:
		_edit_embedded(object, metadata.get("embedded_in", ""))


func _on_button_clicked(item: TreeItem, _column: int, id: int, mouse_button_index: int) -> void:
	var object = _item_object(item)
	if mouse_button_index != MOUSE_BUTTON_LEFT or object == null:
		return
	if id == PATH_BUTTON:
		path_activated.emit(item.get_metadata(0).get("path", ""))
	elif id == EDIT_BUTTON:
		_edit_embedded(object, item.get_metadata(0).get("embedded_in", ""))
	elif id == SCRIPT_BUTTON and object is Node:
		var script = object.get_script() as Script
		if script == null:
			return
		var script_scene = _embedded_scene(script.resource_path)
		if script_scene.is_empty():
			path_activated.emit(script.resource_path)
		elif _is_edited_scene(script_scene):
			EditorInterface.edit_script(script)
	elif id == VISIBILITY_BUTTON and (object is Node3D or object is CanvasItem):
		object.visible = not object.visible
		_queue_refresh()


func _make_custom_tooltip(_for_text: String) -> Object:
	var item = get_item_at_position(get_local_mouse_position())
	if not is_instance_valid(item):
		return null
	var b_id = get_button_id_at_position(get_local_mouse_position())
	var button = item.get_button_by_id(0, b_id)
	if button > -1:
		return null
	var object = _item_object(item)
	if object == null:
		return null
	var path: String = item.get_metadata(0).get("path", "")
	if not path.is_empty() and tooltip_callable.is_valid() and ResourceLoader.exists(path):
		return tooltip_callable.call(path)
	return null
