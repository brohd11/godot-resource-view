#! namespace ResourceView class ControlViewer
extends VBoxContainer
## Live preview of a Control script or a Control/Node2D scene, with pick-to-select,
## selection highlight and inspection. Pair with ControlTreeView for a node tree.

const PickOverlay = preload("res://addons/_lib/resource_view/src/control_viewer/pick_overlay.gd")
const ControlTreeView = preload("res://addons/_lib/resource_view/src/control_viewer/control_tree_view.gd")

## Set on every preview root, so preview code can tell it is running in a viewer.
const EDITOR_META = &"ui_editor"
const SCENE_EXTENSIONS = ["tscn", "scn"]

## The root the node tree should show; null once the preview is cleared.
signal preview_changed(root: Node)
## A control clicked in the preview, for the bound tree view to select.
signal object_picked(object: Object)
## Right click on the preview; the hook for a future context menu.
signal context_requested(control: Control, screen_position: Vector2)

const HIGHLIGHT_ALPHA = 0.25

## A Control script (.gd) or a scene (.tscn/.scn) with a CanvasItem root.
var source_path: String
## Shown while nothing is loaded.
var placeholder_text := "":
	set(value):
		placeholder_text = value
		if not is_instance_valid(preview):
			_show_status(value)
var preview: CanvasItem
var status: Label
var canvas: Control
var highlight: ColorRect
var overlay: PickOverlay
## Collapse/selection parked here by the tree view while another tab is shown.
var tree_state: Dictionary = {}

var _inspected_node: WeakRef
var _selected: WeakRef
var _inspect_enabled := true
var _highlight_enabled := true
var _highlighted: WeakRef

var _fingerprint: String
var _rebuild_queued := false
var _stopped := false


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.hide()
	add_child(status)
	canvas = Control.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.clip_contents = true
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	# A canvas sibling of the preview stays out of the node tree and the user's hierarchy.
	highlight = ColorRect.new()
	highlight.name = "Highlight"
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight.color = Color(0.4, 0.6, 1.0, HIGHLIGHT_ALPHA)
	highlight.hide()
	canvas.add_child(highlight)
	# Canvas order stays [preview, highlight, overlay] so the overlay is first to receive clicks.
	overlay = PickOverlay.new()
	overlay.picked.connect(_on_picked)
	overlay.context_requested.connect(context_requested.emit)
	canvas.add_child(overlay)
	set_process(false)


func _ready() -> void:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var accent = Engine.get_singleton(&"EditorInterface").get_editor_theme().get_color(&"accent_color", &"Editor")
		highlight.color = Color(accent, HIGHLIGHT_ALPHA)
	if not source_path.is_empty():
		queue_rebuild()


func _process(_delta: float) -> void:
	_update_highlight()


func poll_saved_file() -> void:
	if source_path.is_empty():
		return
	var fingerprint = _saved_fingerprint()
	if fingerprint != _fingerprint:
		_fingerprint = fingerprint
		queue_rebuild()


func queue_rebuild() -> void:
	if _stopped or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


## Frees the preview and forgets the source; the viewer stays usable.
func clear_source() -> void:
	source_path = ""
	_fingerprint = ""
	_clear_preview()
	_show_status(placeholder_text)


func clean_up() -> void:
	_stopped = true
	_clear_preview()


func _rebuild() -> void:
	_rebuild_queued = false
	if _stopped or not is_inside_tree():
		return
	_fingerprint = _saved_fingerprint()
	_clear_preview()
	if source_path.is_empty():
		_show_status(placeholder_text)
		return
	if not FileAccess.file_exists(source_path):
		_show_status("File not found: %s" % source_path)
		return

	var instance: CanvasItem
	if source_path.get_extension().to_lower() in SCENE_EXTENSIONS:
		instance = _instantiate_scene()
	else:
		instance = _instantiate_script()
	if instance == null:
		return
	preview = instance
	if preview.name.is_empty():
		preview.name = source_path.get_file().get_basename()
	preview.set_meta(EDITOR_META, true)
	status.hide()
	canvas.add_child(preview)
	canvas.move_child(preview, 0)
	# Picking walks Controls only, so a Node2D root shows but can't be picked in the canvas.
	overlay.root = preview as Control
	preview_changed.emit(preview)


func _instantiate_script() -> Control:
	# A new node resets instance state; bypassing the cache also refreshes saved code.
	var script = ResourceLoader.load(source_path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if script == null:
		_show_status("Could not load script. See Godot's debugger for details.")
		return null
	var error = script.reload(true)
	if error != OK:
		_show_status("Could not compile script (%s). See Godot's debugger for details." % error_string(error))
		return null
	if not ClassDB.is_parent_class(script.get_instance_base_type(), &"Control"):
		_show_status("Preview scripts must extend Control.")
		return null
	for method in script.get_script_method_list():
		if method.name == &"_init" and method.args.size() > method.default_args.size():
			_show_status("Preview scripts need a constructor with no required arguments.")
			return null

	# Explicit new() executes non-tool scripts too; can_instantiate() rejects them in the editor.
	var instance = script.new()
	if not is_instance_valid(instance) or not instance is Control:
		if is_instance_valid(instance) and instance is Node:
			instance.free()
		_show_status("Could not construct Control. See Godot's debugger for details.")
		return null
	instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return instance


func _instantiate_scene() -> CanvasItem:
	var packed = ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		_show_status("Could not load scene. See Godot's debugger for details.")
		return null
	var instance = packed.instantiate()
	if not instance is CanvasItem:
		if is_instance_valid(instance):
			instance.free()
		_show_status("Preview scenes must have a Control or Node2D root.")
		return null
	return instance


func _clear_preview() -> void:
	_inspect_object(null)
	_highlight_object(null)
	tree_state = {}
	overlay.root = null
	if is_instance_valid(preview):
		preview_changed.emit(null)
		if preview.get_parent() != null:
			preview.get_parent().remove_child(preview)
		preview.free()
	preview = null


## Called by whichever tree view currently shows this viewer.
func select_object(object: Object) -> void:
	_inspect_object(object)
	_highlight_object(object)


## Hidden, the overlay lets clicks reach the live preview.
func set_interact_enabled(enabled: bool) -> void:
	overlay.visible = not enabled


func _on_picked(control: Control) -> void:
	# The tree routes its selection back through select_object; without one, select directly.
	if object_picked.get_connections().is_empty():
		select_object(control)
	else:
		object_picked.emit(control)


func set_inspect_enabled(enabled: bool) -> void:
	_inspect_enabled = enabled
	if not enabled:
		_release_inspected_node()
	elif _selected != null and is_visible_in_tree():
		# Only the visible tab reclaims the inspector, so hidden tabs don't override it.
		_inspect_object(_selected.get_ref())


func _inspect_object(object: Object) -> void:
	_selected = weakref(object) if is_instance_valid(object) else null
	_release_inspected_node()
	if not _inspect_enabled or not Engine.is_editor_hint() or not is_instance_valid(object):
		return
	if object is Node:
		_inspected_node = weakref(object)
		object.tree_exiting.connect(_release_inspected_node)
	EditorInterface.inspect_object(object, "", true)


func _release_inspected_node() -> void:
	if _inspected_node == null:
		return
	var object = _inspected_node.get_ref() as Node
	_inspected_node = null
	if is_instance_valid(object):
		object.tree_exiting.disconnect(_release_inspected_node)
		if Engine.is_editor_hint() and EditorInterface.get_inspector().get_edited_object() == object:
			EditorInterface.inspect_object(null)


func set_highlight_enabled(enabled: bool) -> void:
	_highlight_enabled = enabled
	_update_highlight()


func _highlight_object(object: Object) -> void:
	_highlighted = weakref(object) if object is Control else null
	_update_highlight()


## Polled while a target is selected, so relayout, ancestor moves and tab switches are followed.
func _update_highlight() -> void:
	var target = _highlighted.get_ref() as Control if _highlighted != null else null
	var tracking = _highlight_enabled and is_instance_valid(target)
	set_process(tracking)
	highlight.visible = tracking and target.is_visible_in_tree()
	if not highlight.visible:
		return
	var rect = target.get_global_rect()
	highlight.global_position = rect.position
	highlight.size = rect.size


func _show_status(message: String) -> void:
	status.text = message
	status.visible = not message.is_empty()


func _saved_fingerprint() -> String:
	return FileAccess.get_sha256(source_path) if FileAccess.file_exists(source_path) else "missing"
