# ResourceView

Reusable editor viewers for scenes, materials, text, and node hierarchies.

## NodeTree

`ResourceView.NodeTree` displays a live node and its non-internal descendants,
including children created by code without a scene owner:

```gdscript
var tree = ResourceView.NodeTree.new()
add_child(tree)
tree.set_root_node(preview_root)
tree.object_selected.connect(func(object): EditorInterface.inspect_object(object, "", true))
tree.path_activated.connect(func(path): EditorInterface.edit_resource(load(path)))
```

The caller owns roots supplied to `set_root_node()`. `clear_root()` disconnects
the hierarchy and clears its rows without freeing those nodes. Hierarchy,
name, and visibility changes refresh automatically; `refresh()` also rebuilds
explicitly. Selection, collapsed branches, and scrolling survive refreshes.

`owned_only` restricts traversal to the root and nodes owned by it.
`show_resources` includes meshes and surface materials. Both default to `false`.
`show_scripts` adds attached-script buttons and defaults to `true`.
Visibility buttons support `CanvasItem` and `Node3D` nodes.

`path_activated(path)` handles resource and script buttons and row activation.
`item_right_clicked(path)` lets the host provide a resource context menu.
`tooltip_callable(path)` can return a custom resource tooltip.
The component emits selection and path signals; hosts choose how to inspect
objects or open resources.

`send_scene_path(path)` loads and retains its own scene instance until the root
changes, is cleared, or the viewer is freed. `send_scene_instance()` and
`clear_tree(message, true)` remain available for existing scene-viewer callers.

Run hierarchy tests with `test resource_view` in Editor Console or:

```sh
godot --headless --path . --script res://addons/_lib/resource_view/_export_ignore/test/run_headless.gd
```
