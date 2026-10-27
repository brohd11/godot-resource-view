extends RefCounted

const NodeTree = preload("res://addons/_lib/resource_view/src/node_tree/node_tree.gd")
const SCENE = "res://addons/_lib/resource_view/_export_ignore/test/fixtures/tree_scene.tscn"

static var _checks: int
static var _failures: Array[String]


static func run_tests() -> Dictionary:
	_checks = 0
	_failures = []
	await _test_subtree()
	await _test_scene_mode()
	await _test_lifecycle()
	await _test_scroll()
	var output: Array = ["ResourceView node tree: %d checks, %d failures" % [_checks, _failures.size()]]
	output.append_array(_failures)
	return {"result": _failures.size(), "output": output, "completed": true}


static func _test_subtree() -> void:
	var scene_tree = Engine.get_main_loop() as SceneTree
	var outer = Node.new()
	var root = Control.new()
	root.name = "Preview"
	outer.add_child(root)
	var branch = Control.new()
	branch.name = "Branch"
	root.add_child(branch)
	var leaf = Label.new()
	leaf.name = "Leaf"
	branch.add_child(leaf)
	outer.add_child(Node.new())
	root.add_child(Node.new(), false, Node.INTERNAL_MODE_BACK)
	var viewer = NodeTree.new()
	scene_tree.root.add_child(outer)
	scene_tree.root.add_child(viewer)
	viewer.set_root_node(root)
	_check("arbitrary root includes unowned descendants only", viewer.tree_items.size() == 3 and viewer.get_root().get_metadata(0).object == root)
	_check("nested row follows parent", viewer.tree_items[leaf].get_parent() == viewer.tree_items[branch])
	viewer.tree_items[branch].collapsed = true
	viewer.tree_items[root].select(0)
	var selections: Array = []
	viewer.object_selected.connect(func(object: Object): selections.append(object))
	viewer.item_selected.emit()
	_check("selection exposes the live object", selections.back() == root)
	var added = Button.new()
	added.name = "Added"
	root.add_child(added)
	await _settle()
	_check("added child appears live", viewer.tree_items.has(added))
	_check("surviving selection is preserved without another selection event", viewer.get_selected().get_metadata(0).object == root and selections.size() == 1)
	_check("collapsed branch survives refresh", viewer.tree_items[branch].collapsed)
	leaf.name = "Renamed"
	leaf.reparent(root)
	root.move_child(leaf, 0)
	await _settle()
	_check("rename is reflected live", viewer.tree_items[leaf].get_text(0) == "Renamed")
	_check("reparent and ordering are reflected live", viewer.tree_items[leaf].get_parent() == viewer.tree_items[root] and viewer.tree_items[root].get_first_child() == viewer.tree_items[leaf])
	viewer._on_button_clicked(viewer.tree_items[added], 0, NodeTree.VISIBILITY_BUTTON, MOUSE_BUTTON_LEFT)
	_check("CanvasItem visibility can be toggled", not added.visible)
	viewer.tree_items[leaf].select(0)
	root.remove_child(leaf)
	await _settle()
	_check("removed subtree leaves no row or selection", not viewer.tree_items.has(leaf) and viewer.get_selected() == null and selections.back() == null)
	_check("removed descendants are disconnected", not leaf.renamed.is_connected(viewer._queue_refresh))
	leaf.free()
	viewer.hide()
	var hidden_child = Node.new()
	root.add_child(hidden_child)
	await _settle()
	viewer.show()
	await _settle()
	_check("showing the tree catches hidden changes", viewer.tree_items.has(hidden_child))
	viewer.set_root_node(branch)
	_check("rebasing excludes ancestors and siblings", viewer.tree_items.size() == 1 and viewer.tree_items.has(branch))
	_check("old root subscriptions are released", not root.child_order_changed.is_connected(viewer._queue_refresh))
	viewer.clear_root()
	_check("clearing leaves caller nodes alive", is_instance_valid(branch) and viewer.tree_items.is_empty())
	viewer._on_item_activated()
	viewer._on_item_mouse_selected(Vector2.ZERO, MOUSE_BUTTON_RIGHT)
	viewer.free()
	outer.free()
	await _settle()


static func _test_scene_mode() -> void:
	var viewer = NodeTree.new()
	viewer.owned_only = true
	viewer.show_resources = true
	viewer.show_scripts = false
	viewer.send_scene_path(SCENE)
	var root = viewer.current_scene_instance
	_check("scene-path nodes remain alive", is_instance_valid(root) and viewer.tree_items.size() == 3)
	var mesh_item = viewer.tree_items[root.get_node("Mesh")].get_first_child()
	_check("mesh and material resource rows remain available", mesh_item.get_text(0) == "Test mesh" and mesh_item.get_first_child().get_text(0) == "Test material")
	mesh_item.collapsed = true
	viewer.refresh()
	_check("resource branch collapse survives refresh", viewer.tree_items[root.get_node("Mesh")].get_first_child().collapsed)
	_check("mesh-less nodes have no resource row", viewer.tree_items[root.get_node("EmptyMesh")].get_first_child() == null)
	var runtime_child = Node.new()
	root.add_child(runtime_child)
	await _settle()
	_check("scene mode excludes unowned children", not viewer.tree_items.has(runtime_child))
	viewer.owned_only = false
	viewer.refresh()
	_check("ownership filtering is configurable", viewer.tree_items.has(runtime_child))
	viewer.set_root_node(root)
	_check("rebinding the same root keeps its instance alive", is_instance_valid(root) and viewer.current_scene_instance == root)
	viewer.send_scene_path(SCENE)
	_check("replacing a scene frees the owned instance", not is_instance_valid(root))
	root = viewer.current_scene_instance
	viewer.clear_tree("Scene cleared", true)
	_check("legacy clear releases the owned scene", not is_instance_valid(root) and viewer.current_scene_path.is_empty())
	viewer.send_scene_path("res://addons/_lib/resource_view/_export_ignore/test/fixtures/missing.tscn")
	_check("missing scene has a nonselectable error row", viewer.get_root().get_text(0).begins_with("Could not load path:") and not viewer.get_root().is_selectable(0))
	viewer.send_scene_path(SCENE)
	root = viewer.current_scene_instance
	viewer.free()
	_check("destroying a viewer frees its owned scene", not is_instance_valid(root))
	await _settle()


static func _test_lifecycle() -> void:
	var scene_tree = Engine.get_main_loop() as SceneTree
	var root = Node.new()
	var viewer = NodeTree.new()
	scene_tree.root.add_child(root)
	scene_tree.root.add_child(viewer)
	viewer.set_root_node(root)
	root.free()
	await _settle()
	_check("freed root clears safely", viewer.current_scene_instance == null and viewer.tree_items.is_empty())
	root = Node.new()
	viewer.set_root_node(root)
	var child = Node.new()
	root.add_child(child)
	await _settle()
	_check("detached roots follow hierarchy changes", viewer.tree_items.has(child))
	viewer.free()
	_check("destroying viewer disconnects caller nodes", is_instance_valid(root) and not root.child_order_changed.has_connections())
	root.free()
	await _settle()


static func _test_scroll() -> void:
	var scene_tree = Engine.get_main_loop() as SceneTree
	var viewport = SubViewport.new()
	viewport.size = Vector2i(400, 300)
	scene_tree.root.add_child(viewport)
	var viewer = NodeTree.new()
	viewer.size = Vector2(200, 120)
	viewport.add_child(viewer)
	var root = Node.new()
	for i in 60:
		var child = Node.new()
		child.name = "Row%d" % i
		root.add_child(child)
	viewer.set_root_node(root)
	await _settle()
	viewer.scroll_to_item(viewer.tree_items[root.get_child(30)], true)
	await _settle()
	var scroll = viewer.get_scroll()
	root.get_child(59).name = "Changed"
	await _settle()
	_check("refresh preserves scroll position", scroll.y > 0 and viewer.get_scroll().is_equal_approx(scroll))
	viewer.clear_root()
	root.free()
	viewport.free()
	await _settle()


static func _settle() -> void:
	var tree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	await tree.process_frame


static func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures.append("FAIL " + label)
