#! namespace ResourceView class SceneViewer
extends VBoxContainer
## One preview for any scene: 3D roots go to Node3DViewer, Control/Node2D roots to a
## ControlViewer with its own toolbar and node tree. Shows whichever view fits the subject.

const SceneReadFile = preload("uid://cx8sx32appge5") #! resolve UtilR.Resources.Read.Tscn
const PluginButton = preload("uid://redtm8tuamgm") #! resolve UIPlugin.PluginButton
const Placer = preload("uid://cs6pl78crcr0g") #! resolve UtilR.Nodes.PopupMenus.Placer
const Options = preload("uid://dxdxq2n3imf4q") #! resolve UtilR.Nodes.PopupMenus.Options
const Node3DViewer = preload("uid://c7kqsm24o7mlm") #! resolve ResourceView.Node3DViewer
const ControlViewer = preload("uid://bd2dhwch6o144") #! resolve ResourceView.ControlViewer

enum Kind {NONE, SCENE_3D, SCENE_2D}

## Host overrides, passed through to both views; unset = native EditorInterface behaviour.
var activate_path_callable:Callable: # (path)
	set(value):
		activate_path_callable = value
		_apply_callables()
var navigate_path_callable:Callable: # (path, calling_node)
	set(value):
		navigate_path_callable = value
		_apply_callables()
var tooltip_callable:Callable: # (path) -> Control or null
	set(value):
		tooltip_callable = value
		_apply_callables()

var node_3d_viewer:Node3DViewer
var canvas_view:VBoxContainer
var canvas_toolbar:HBoxContainer
var canvas_options_button:Button
var control_viewer:ControlViewer
var control_tree:ControlViewer.ControlTreeView

var _placer:Placer


## Recursive, so inherited scenes report their base's root type rather than its path.
static func get_root_type(path:String) -> String:
	var root_type = SceneReadFile.get_root_type(path, true)
	return root_type if root_type is String else ""

static func get_kind(root_type:String) -> Kind:
	if not ClassDB.class_exists(root_type):
		return Kind.NONE
	if ClassDB.is_parent_class(root_type, &"Node3D"):
		return Kind.SCENE_3D
	if ClassDB.is_parent_class(root_type, &"Control") or ClassDB.is_parent_class(root_type, &"Node2D"):
		return Kind.SCENE_2D
	return Kind.NONE


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_placer = Placer.new()
	add_child(_placer)

	# Node3DViewer builds its nodes in _ready, so it must enter the tree before set_panel_mode.
	node_3d_viewer = Node3DViewer.new()
	add_child(node_3d_viewer)
	node_3d_viewer.set_panel_mode(Node3DViewer.PanelMode.SINGLE)
	node_3d_viewer.hide()

	canvas_view = VBoxContainer.new()
	canvas_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(canvas_view)
	canvas_view.hide()

	canvas_toolbar = HBoxContainer.new()
	canvas_view.add_child(canvas_toolbar)
	canvas_toolbar.add_spacer(false)
	canvas_options_button = PluginButton.new("TripleBar", _on_canvas_options_pressed).get_button()
	canvas_toolbar.add_child(canvas_options_button)

	var split = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_view.add_child(split)
	control_viewer = ControlViewer.new()
	control_viewer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control_viewer.set_interact_enabled(false)
	split.add_child(control_viewer)
	control_tree = ControlViewer.ControlTreeView.new()
	control_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control_tree.size_flags_stretch_ratio = 0.3 # same split as Node3DViewer's tree
	control_tree.set_host(control_viewer)
	control_tree.hide()
	split.add_child(control_tree)

	_apply_callables()


func show_scene(path:String, kind:Kind) -> void:
	if kind == Kind.SCENE_3D:
		show_3d([path])
	elif kind == Kind.SCENE_2D:
		show_2d(path)

## Scenes, imported models and Mesh resources.
func show_3d(paths:Array) -> void:
	control_viewer.clear_source()
	canvas_view.hide()
	node_3d_viewer.show()
	node_3d_viewer.set_scene_paths(paths)

## Call once this preview is inside the tree; ControlViewer only instances while it is.
func show_2d(path:String) -> void:
	node_3d_viewer.hide()
	canvas_view.show()
	control_viewer.source_path = path
	control_viewer.queue_rebuild()

## Frees the 2D instance; the 3D viewer keeps its own cache as before.
func clear() -> void:
	if is_instance_valid(control_viewer):
		control_viewer.clear_source()


func _on_canvas_options_pressed() -> void:
	var options = Options.new()
	options.add_option("Toggle SceneTree", func(): control_tree.visible = not control_tree.visible, ["FileTree"])
	_placer.display_on_control(options, canvas_options_button)


func _apply_callables() -> void:
	if not is_instance_valid(node_3d_viewer):
		return
	node_3d_viewer.activate_path_callable = activate_path_callable
	node_3d_viewer.navigate_path_callable = navigate_path_callable
	node_3d_viewer.tooltip_callable = tooltip_callable
	control_tree.activate_path_callable = activate_path_callable
