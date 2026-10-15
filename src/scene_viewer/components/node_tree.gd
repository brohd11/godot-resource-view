@tool
extends Tree

const EditorIcons = preload("uid://viocyrti6wce") #! resolve UIPlugin.EditorIcons

var scene_info = {}
var tree_items = {}

var current_scene_path:String = ""
var current_scene_instance:Node

## Rich tooltip for file paths, set by SceneViewer; null falls back to the plain-text one.
var tooltip_callable:Callable

signal item_right_clicked(path:String)
signal path_activated(path:String)

func _ready() -> void:
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_scan_files_complete)
	clear_tree()
	allow_rmb_select = true
	item_activated.connect(_on_item_activated)
	item_mouse_selected.connect(_on_item_mouse_selected)
	button_clicked.connect(_on_button_clicked)

func _on_item_mouse_selected(mouse_pos:Vector2, mouse_button_index:int):
	if mouse_button_index == 2:
		var selected = get_item_at_position(mouse_pos)
		var meta = selected.get_metadata(0)
		var path = meta.get("path", "")
		if path != "":
			item_right_clicked.emit(path)

func _on_button_clicked(item:TreeItem, _col:int, id:int, mouse_button_index:int):
	var meta = item.get_metadata(0)
	if mouse_button_index == 1:
		if id == 0:
			var path = meta.get("path", "")
			path_activated.emit(path)
		elif id == 5:
			var object = meta.get("object")
			if is_instance_valid(object) and object is Node3D:
				object.visible = not object.visible
				refresh()

func _on_item_activated():
	var selected = get_selected()
	var meta = selected.get_metadata(0)
	if meta:
		var path = meta.get("path", "")
		if FileAccess.file_exists(path):
			path_activated.emit(path)


func clear_tree(msg:="No scene loaded", clear_current_scene:=false):
	clear()
	scene_info.clear()
	tree_items.clear()
	var item = create_item()
	item.set_text(0, msg)
	if clear_current_scene:
		current_scene_path = ""
		current_scene_instance = null

func refresh():
	build_tree()

func _on_scan_files_complete():
	build_tree()

func send_scene_instance(scene_instance:Node):
	current_scene_instance = scene_instance
	current_scene_path = scene_instance.scene_file_path
	build_tree()

func send_scene_path(preview_scene_path):
	current_scene_instance = null
	current_scene_path = preview_scene_path
	build_tree()

func build_tree():
	if not visible:
		clear_tree()
		return
	
	clear()
	scene_info.clear()
	tree_items.clear()
	var ins_scene
	if current_scene_instance == null:
		if current_scene_path == "":
			clear_tree()
			return
		var pck:PackedScene = ResourceLoader.load(current_scene_path)
		if not pck:
			clear_tree("Could not load path: %s" % current_scene_path)
			return
		ins_scene = pck.instantiate()
	else:
		ins_scene = current_scene_instance
	
	_read_scene(ins_scene, ins_scene)
	
	for node in scene_info:
		var node_data = scene_info.get(node)
		#var node_name = node_data.get("name")
		#var node_class = node_data.get("node_class")
		var node_parent = node_data.get("parent")
		var item:TreeItem
		if not node_parent in tree_items.keys():
			item = create_item()
			tree_items[node] = item
		else:
			var parent = tree_items.get(node_parent)
			item = create_item(parent)
			tree_items[node] = item
		
		_set_node_item_params(item, node)
		if node is MeshInstance3D:
			var mesh = node.mesh
			var mesh_item = create_item(item)
			_set_resource_item_params(mesh_item, mesh)
			
			var surface_count = mesh.get_surface_count()
			for i in range(surface_count):
				var mat:Material = mesh.surface_get_material(i)
				
				if not mat:
					continue
				
				var mat_item = create_item(mesh_item)
				_set_resource_item_params(mat_item, mat)
	
	if current_scene_instance == null:
		ins_scene.queue_free()

func _set_node_item_params(item:TreeItem, node:Node):
	item.set_text(0, node.name)
	item.set_icon(0, EditorIcons.get_class_icon(node))
	var meta = {"path":node.scene_file_path, "object": node}
	item.set_metadata(0, meta)
	if node.scene_file_path != "" and FileAccess.file_exists(node.scene_file_path):
		item.add_button(0, EditorInterface.get_editor_theme().get_icon("Load", "EditorIcons"), 0)
	if node is Node3D:#EditorInterface.get_editor_theme().get_icon("GuiVisibilityVisible", "EditorIcons")
		item.add_button(0, EditorIcons.get_visibility_icon(node.visible), 5)

func _set_resource_item_params(item:TreeItem, resource:Resource):
	item.set_text(0, _get_resource_name(resource))
	item.set_icon(0, EditorIcons.get_class_icon(resource))
	var meta = {"path":resource.resource_path, "object": resource}
	item.set_metadata(0, meta)
	if resource.resource_path != "" and FileAccess.file_exists(resource.resource_path):
		item.add_button(0, EditorInterface.get_editor_theme().get_icon("Load", "EditorIcons"), 0)

func _get_resource_name(resource:Resource):
	var res_name = resource.resource_name
	if res_name == "":
		res_name = "No resource name."
	return res_name

func _make_custom_tooltip(for_text:String):
	var item = get_item_at_position(get_local_mouse_position())
	if not item:
		return
	var meta = item.get_metadata(0)
	var path = meta.get("path")
	if FileAccess.file_exists(path):
		return tooltip_callable.call(path) if tooltip_callable.is_valid() else null

	var object = meta.get("object") as Object
	var _class = object.get_class()
	
	var label = Label.new()
	label.text = for_text
	label.text += "\nLocal to Scene"
	label.text += "\nClass: %s" % _class
	return label


func _read_scene(node:Node, root_node:Node):
	if node != root_node and node.owner != root_node:
		return
	var parent = node.get_parent()
	var node_name = node.name
	var node_class = node.get_class()
	scene_info[node] = {
		"parent": parent,
		"name": node_name,
		"node_class": node_class,
	}
	var node_children = node.get_children()
	for n in node_children:
		_read_scene(n, root_node)
