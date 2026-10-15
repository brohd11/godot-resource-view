#! namespace ResourceView class SceneViewer
extends VBoxContainer

#! import_p Keys,

const PluginButton = preload("uid://redtm8tuamgm") #! resolve UIPlugin.PluginButton
const EditorIcons = preload("uid://viocyrti6wce") #! resolve UIPlugin.EditorIcons
const SettingHelperSingleton = preload("uid://60187tsv40mq") #! resolve SettingHelper.Singleton
const SettingHelperJson = preload("uid://dku4srj2t8htd") #! resolve SettingHelper.Json
const Options = preload("uid://dxdxq2n3imf4q") #! resolve UtilR.Nodes.PopupMenus.Options

const MeshManager = preload("res://addons/_lib/resource_view/src/scene_viewer/components/mesh_manager.gd")
const NodeTree = preload("res://addons/_lib/resource_view/src/scene_viewer/components/node_tree.gd")
const ControllerFreeView = preload("uid://chvmdxo2kpwt3") #! resolve CamControl.Mouse.FreeView



const LONGEST_SLIDER_LAB = "Camera Rotate Sens"

const SETTING_FILE_PATH = "user://addons/config/scene_viewer/config.json"

enum PanelMode {
	FULL,
	SINGLE,
}

var _dock_data:Dictionary = {}

var setting_helper:SettingHelperJson

var right_click_handler:UtilR.Nodes.PopupMenus.Placer

var toolbar:HBoxContainer

var next_mesh_button:Button
var prev_mesh_button:Button
var list_scene_button:Button
var options_button:Button

var main_split_container:SplitContainer

var sub_viewport_root:Control
var sub_viewport_container:SubViewportContainer
var sub_viewport:SubViewport

var mouse_detector:Control
var sub_viewport_overlay:HBoxContainer

var stats_panel:StatsPanel
var tools_panel:HBoxContainer
var light_panel:VBoxContainer
var camera_panel:CameraPanel

var model_rotate_slider: ToolSlider

var root_3d:Node3D
var world_env:WorldEnvironment
var directional_light:DirectionalLight3D
var controller:ControllerFreeView
var camera:Camera3D

var mesh_manager:MeshManager

var node_tree:NodeTree

## Host overrides, so a filesystem plugin can supply richer behaviour without this package depending on it.
## Unset = native EditorInterface behaviour.
var activate_path_callable:Callable # (path)
var navigate_path_callable:Callable # (path, calling_node)
var tooltip_callable:Callable # (path) -> Control or null

#^ settings
var _global_settings = {}

var panel_mode:PanelMode

func _ready() -> void:
	_build_nodes()
	
	setting_helper = SettingHelperSingleton.get_file_helper(SETTING_FILE_PATH)
	setting_helper.subscribe_property(self, "_global_settings", "global_settings", {})
	setting_helper.settings_changed.connect(_on_global_settings_changed)
	setting_helper.object_initialize(self)
	
	
	mesh_manager.show_only_active = _dock_data.get(Keys.SHOW_ONLY_ACTIVE, false)
	mesh_manager.collision_shapes_toggled = _dock_data.get(Keys.COLLISIONS_TOGGLED, true)
	main_split_container.split_offset = _dock_data.get(Keys.SPLIT_OFFSET, 0)
	node_tree.visible = _dock_data.get(Keys.NODE_TREE_VISIBLE, false)
	
	light_panel.visible = _dock_data.get(Keys.LIGHT_PANEL_VIS, false)
	var light_setting = _dock_data.get(Keys.LIGHT_SETTINGS)
	if light_setting != null:
		set_light_settings(str_to_var(light_setting))
	camera_panel.visible = _dock_data.get(Keys.CAMERA_PANEL_VIS, false)


func set_dock_data(data:Dictionary):
	_dock_data = data

func get_dock_data() -> Dictionary:
	var data = {}
	data[Keys.SHOW_ONLY_ACTIVE] = mesh_manager.show_only_active
	data[Keys.COLLISIONS_TOGGLED] = mesh_manager.collision_shapes_toggled
	data[Keys.SPLIT_OFFSET] = main_split_container.split_offset
	data[Keys.NODE_TREE_VISIBLE] = node_tree.visible
	
	data[Keys.LIGHT_PANEL_VIS] = light_panel.visible
	data[Keys.LIGHT_SETTINGS] = var_to_str(get_light_settings())
	data[Keys.CAMERA_PANEL_VIS] = camera_panel.visible
	
	return data

func get_tab_title():
	return "Scene Viewer"

func set_panel_mode(mode:PanelMode):
	panel_mode = mode
	if panel_mode == PanelMode.FULL:
		list_scene_button.show()
		prev_mesh_button.show()
		next_mesh_button.show()
	elif panel_mode == PanelMode.SINGLE:
		list_scene_button.hide()
		prev_mesh_button.hide()
		next_mesh_button.hide()

func set_scene_paths(scene_paths:Array):
	mesh_manager.load_scenes(scene_paths)
	

func clear_scenes():
	_on_clear_pressed()

func _on_active_scene_set(_scene_path:String, data:Dictionary):
	var active_scene = mesh_manager.get_active_scene_instance()
	stats_panel.set_text(data)
	node_tree.send_scene_instance(active_scene)
	model_rotate_slider.visible = not data.is_empty()
	model_rotate_slider.slider.value = rad_to_deg(active_scene.rotation.y) #^ reset slider
	#active_scene.rotation.y = deg_to_rad(model_rotate_slider.slider.value) #^ set model to slider


func _on_options_button_clicked():
	var options = Options.new()
	
	options.add_option("Toggle SceneTree", _on_node_tree_button_pressed, ["FileTree"])
	var col_icon = EditorIcons.get_icon_white("CollisionShape3D")
	options.add_option("Toggle Collision", _on_toggle_collision, [col_icon])
	options.add_option("Toggle Camera Controls", func():camera_panel.visible = not camera_panel.visible, ["Camera"])
	var light_icon = EditorIcons.get_icon_white("DirectionalLight3D")
	options.add_option("Toggle Light Controls", func():light_panel.visible = not light_panel.visible, [light_icon])
	if panel_mode == PanelMode.FULL:
		options.add_option("Clear Scenes", _on_clear_pressed, ["Clear"])
	
	right_click_handler.display_on_control(options, options_button)

func _on_node_tree_button_pressed():
	node_tree.visible = not node_tree.visible
	node_tree.refresh()

func _on_clear_pressed():
	stats_panel.set_text({})
	model_rotate_slider.hide()
	mesh_manager.clear_cache()
	node_tree.clear_tree("Scene cleared", true)

func _on_toggle_collision():
	mesh_manager.toggle_collision_shapes()
	node_tree.refresh()

func _list_loaded_scenes():
	var options = Options.new()
	
	var show_icon = EditorIcons.get_visibility_icon(not mesh_manager.show_only_active)
	var show_text = "Show only active scene"
	if mesh_manager.show_only_active:
		show_text = "Show all scenes"
	options.add_option(show_text, func():mesh_manager.show_only_active = not mesh_manager.show_only_active;mesh_manager.refresh(), [show_icon])
	
	options.add_separator()
	
	var loaded_scenes = mesh_manager.get_loaded_paths()
	if loaded_scenes.is_empty():
		options.add_option("No scenes loaded.", null)
	else:
		for path in loaded_scenes:
			var ins = mesh_manager.get_scene_instance(path)
			var root_icon = EditorIcons.get_class_icon(ins)
			options.add_option(path.get_file(), mesh_manager.show_scene.bind(path), [root_icon])
	
	right_click_handler.display_on_control(options, list_scene_button)


func _on_node_tree_right_clicked(path:String):
	var options = Options.new()
	var file_type = EditorInterface.get_resource_filesystem().get_file_type(path)
	if ClassDB.is_parent_class("Resource", file_type):
		options.add_option("Edit", _activate_path.bind(path), ["Edit"])
	else:
		options.add_option("Open", _activate_path.bind(path), ["Load"])

	options.add_option("Show in FileSystem", _navigate_to_path.bind(path), ["Filesystem"])

	right_click_handler.display_popup(options)

func _activate_path(path:String):
	if activate_path_callable.is_valid():
		activate_path_callable.call(path)
	elif path.get_extension() in ["tscn", "scn"]:
		EditorInterface.open_scene_from_path(path)
	else:
		EditorInterface.edit_resource(load(path))

func _navigate_to_path(path:String):
	if navigate_path_callable.is_valid():
		navigate_path_callable.call(path, self)
	else:
		EditorInterface.get_file_system_dock().navigate_to_path(path)

func _get_path_tooltip(path:String):
	if tooltip_callable.is_valid():
		return tooltip_callable.call(path)
	return null


func _on_global_settings_changed():
	camera_panel.load_settings(_global_settings[Keys.CAMERA_SETTINGS])

func _on_camera_settings_changed():
	_global_settings[Keys.CAMERA_SETTINGS] = camera_panel.get_settings()
	setting_helper.set_setting("global_settings", _global_settings)

func get_light_settings():
	var x_slider = light_panel.get_child(0)
	var y_slider = light_panel.get_child(1)
	return Vector2(x_slider.get_value(), y_slider.get_value())

func set_light_settings(setting:Vector2):
	var x_slider = light_panel.get_child(0)
	var y_slider = light_panel.get_child(1)
	x_slider.set_value(setting.x)
	y_slider.set_value(setting.y)
	directional_light.rotation = Vector3(setting.x, setting.y, 0)


func _on_sub_viewport_can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data.get("type") == "files":
		var res_fs = EditorInterface.get_resource_filesystem()
		var files = data.get("files")
		for f in files:
			if res_fs.get_file_type(f) == "PackedScene":
				return true
	return false

func _on_sub_viewport_drop_data(_at_position: Vector2, data: Variant) -> void:
	stats_panel.set_text({})
	var files = data.get("files")
	mesh_manager.load_scenes(files)

func _on_sub_viewport_get_drag_data(_at_position: Vector2) -> Variant:
	return null


class StatsPanel extends VBoxContainer:
	var _face_label:Label
	var _vert_label:Label
	var _edge_label:Label
	
	func _ready() -> void:
		var vbox = VBoxContainer.new()
		add_child(vbox)
		vbox.add_theme_constant_override("separation", 0)
		var max_size = ThemeDB.fallback_font.get_string_size("Faces:")
		var empty = StyleBoxEmpty.new()
		var data = {"_face_label":"Faces:", "_vert_label":"Verts:", "_edge_label":"Edges:"}
		for _var_name in data.keys():
			var hbox = HBoxContainer.new()
			
			vbox.add_child(hbox)
			hbox.add_theme_constant_override("separation", 0)
			var text_label = Label.new()
			hbox.add_child(text_label)
			text_label.text = data[_var_name]
			text_label.custom_minimum_size.x = max_size.x + 5
			text_label.add_theme_stylebox_override("normal", empty)
			var num_label = Label.new()
			set(_var_name, num_label)
			hbox.add_child(num_label)
			num_label.add_theme_stylebox_override("normal", empty)
			num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		
	func set_text(data:Dictionary):
		visible = not data.is_empty()
		if data.is_empty():
			return
		_face_label.text = str(data.get(MeshManager.Keys.FACE_COUNT))
		_vert_label.text = str(data.get(MeshManager.Keys.VERT_COUNT))
		_edge_label.text = str(data.get(MeshManager.Keys.EDGE_COUNT))


class CameraPanel extends VBoxContainer:
	signal settings_changed
	
	var camera_rot_sens:ToolSlider
	var camera_zoom_sens:ToolSlider
	var camera_pan_sens:ToolSlider
	
	var _controller:ControllerFreeView
	
	func _init(controller:ControllerFreeView) -> void:
		_controller = controller
	
	func _ready() -> void:
		var font = EditorInterface.get_editor_theme().get_font("default_font", "")
		var min_size = font.get_string_size(LONGEST_SLIDER_LAB)
		camera_rot_sens = ToolSlider.new(Vector2(1, 10), 5)
		camera_rot_sens.label_min_size.x = min_size.x
		camera_rot_sens.expand = false
		camera_rot_sens.label_text = "Camera Rotate Sens"
		camera_rot_sens.step = 0.2
		add_child(camera_rot_sens)
		camera_rot_sens.slider.drag_ended.connect(set_settings.bind(true))
		
		camera_zoom_sens = ToolSlider.new(Vector2(1, 10), 5)
		camera_zoom_sens.label_text = "Camera Zoom Sens"
		camera_zoom_sens.label_min_size.x = min_size.x
		camera_zoom_sens.expand = false
		camera_zoom_sens.step = 0.2
		add_child(camera_zoom_sens)
		camera_zoom_sens.slider.drag_ended.connect(set_settings.bind(true))
		
		camera_pan_sens = ToolSlider.new(Vector2(1, 10), 5)
		camera_pan_sens.label_min_size.x = min_size.x
		camera_pan_sens.expand = false
		camera_pan_sens.label_text = "Camera Pan Sens"
		camera_pan_sens.step = 0.2
		add_child(camera_pan_sens)
		camera_pan_sens.slider.drag_ended.connect(set_settings.bind(true))
	
	func load_settings(_settings:Dictionary):
		camera_rot_sens.set_value(_settings.get("rot", 5))
		camera_zoom_sens.set_value(_settings.get("zoom", 5))
		camera_pan_sens.set_value(_settings.get("pan", 5))
		set_settings(true)
	
	func set_settings(val_changed, _emit_signal:=false):
		if val_changed:
			_controller.mouse_rot_sens = camera_rot_sens.get_value()
			_controller.mouse_zoom_sens = camera_zoom_sens.get_value()
			_controller.mouse_pan_sens = camera_pan_sens.get_value()
			if _emit_signal:
				settings_changed.emit()
	
	func get_settings():
		var data = {
			"rot":camera_rot_sens.get_value(),
			"zoom":camera_zoom_sens.get_value(),
			"pan":camera_pan_sens.get_value(),
		}
		return data


class ToolSlider extends HBoxContainer:
	var slider:=HSlider.new()
	var slider_min_size:= Vector2(100, 0)
	
	var expand:= true
	var use_label:= true
	var label_min_size:= Vector2(0,0)
	var label_text:String = ""
	
	var custom_min_value = -180
	var custom_max_value = 180
	var default_slide_val = 0
	
	var step = 1
	
	func _init(slider_values:=Vector2(-180, 180), default_val:=0) -> void:
		custom_min_value = slider_values.x
		custom_max_value = slider_values.y
		default_slide_val = default_val
	
	func _ready() -> void:
		if label_text != "" and use_label:
			var label = Label.new()
			label.text = label_text
			add_child(label)
			label.custom_minimum_size = label_min_size
			label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			if expand:
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			if expand:
				slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		add_child(slider)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size = slider_min_size
		slider.min_value = custom_min_value
		slider.max_value = custom_max_value
		slider.step = step
		slider.set_value_no_signal(default_slide_val)
		slider.gui_input.connect(_on_slider_gui)
		
		
		var tt_call = func(_state):
			var text = "Value: %s\nMin: %s\nMax: %s\nRight click to reset." % [slider.value, slider.min_value, slider.max_value]
			if not use_label:
				text = "%s\n" % label_text + text
			slider.tooltip_text = text
			
		tt_call.call(false)
		slider.drag_ended.connect(tt_call)
		
	
	func _on_slider_gui(event:InputEvent):
		if event is InputEventMouseButton:
			if event.button_index == 2:
				slider.value = default_slide_val
	
	func set_value(val:float):
		slider.set_value_no_signal(val)
	
	func get_value():
		return slider.value


class Keys:
	
	const SHOW_ONLY_ACTIVE = &"SHOW_ONLY_ACTIVE"
	const SPLIT_OFFSET = &"SPLIT_OFFSET"
	const NODE_TREE_VISIBLE = &"NODE_TREE_VISIBLE"
	const COLLISIONS_TOGGLED = &"COLLISIONS_TOGGLED"
	
	const LIGHT_PANEL_VIS = &"LIGHT_PANEL_VIS"
	const LIGHT_SETTINGS = &"LIGHT_SETTINGS"
	const CAMERA_PANEL_VIS = &"CAMERA_PANEL_VIS"
	
	const CAMERA_SETTINGS = &"CAMERA_SETTINGS"


func _build_nodes():
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	right_click_handler = UtilR.Nodes.PopupMenus.Placer.new()
	add_child(right_click_handler)
	
	var font = EditorInterface.get_editor_theme().get_font("default_font", "")
	var min_slider_lab_size = font.get_string_size(LONGEST_SLIDER_LAB)
	
	
	toolbar = HBoxContainer.new()
	add_child(toolbar)
	
	var fov_slider:=HSlider.new()
	toolbar.add_child(fov_slider)
	fov_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fov_slider.min_value = 15
	fov_slider.max_value = 135
	fov_slider.custom_minimum_size.x = 100
	fov_slider.gui_input.connect(func(e):if e is InputEventMouseButton and e.button_index == 2: fov_slider.value=100)
	var fov_label:= Label.new()
	toolbar.add_child(fov_label)
	
	toolbar.add_spacer(false)
	
	var reset_button = PluginButton.new("Camera", null, "Reset camera").get_button()
	toolbar.add_child(reset_button)
	
	prev_mesh_button = PluginButton.new("PagePrevious", null, "Make next scene active.").get_button()
	toolbar.add_child(prev_mesh_button)
	
	next_mesh_button = PluginButton.new("PageNext", null, "Make next scene active.").get_button()
	toolbar.add_child(next_mesh_button)
	
	list_scene_button = PluginButton.new("PackedScene", null, "Make scene active.").get_button()
	toolbar.add_child(list_scene_button)
	
	options_button = PluginButton.new("TripleBar", _on_options_button_clicked).get_button()
	toolbar.add_child(options_button)
	
	
	main_split_container = SplitContainer.new()
	main_split_container.vertical = false
	add_child(main_split_container)
	main_split_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	sub_viewport_root = Control.new()
	main_split_container.add_child(sub_viewport_root)
	sub_viewport_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sub_viewport_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	sub_viewport_container = SubViewportContainer.new()
	sub_viewport_root.add_child(sub_viewport_container)
	sub_viewport_container.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	sub_viewport_container.stretch = true
	
	
	sub_viewport = SubViewport.new()
	sub_viewport_container.add_child(sub_viewport)
	sub_viewport.own_world_3d = true
	
	mouse_detector = Control.new()
	sub_viewport_root.add_child(mouse_detector)
	mouse_detector.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_detector.set_drag_forwarding(func(_a):return null, _on_sub_viewport_can_drop_data, _on_sub_viewport_drop_data)
	
	sub_viewport_overlay = HBoxContainer.new()
	mouse_detector.add_child(sub_viewport_overlay)
	sub_viewport_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	sub_viewport_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var left_panel = VBoxContainer.new()
	sub_viewport_overlay.add_child(left_panel)
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var center_panel = VBoxContainer.new()
	sub_viewport_overlay.add_child(center_panel)
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right_panel = VBoxContainer.new()
	sub_viewport_overlay.add_child(right_panel)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var _center_spacer = center_panel.add_spacer(true)
	var _right_spacer = right_panel.add_spacer(true)
	
	
	root_3d = Node3D.new()
	sub_viewport.add_child(root_3d)
	
	var env = Environment.new()
	var sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	
	world_env = WorldEnvironment.new()
	root_3d.add_child(world_env)
	world_env.environment = env
	
	directional_light = DirectionalLight3D.new()
	root_3d.add_child(directional_light)
	directional_light.rotation = Vector3(deg_to_rad(-20), deg_to_rad(-30), 0)
	
	light_panel = VBoxContainer.new()
	left_panel.add_child(light_panel)
	light_panel.hide()
	
	var sun_rotate_x_slider = ToolSlider.new()
	sun_rotate_x_slider.expand = false
	sun_rotate_x_slider.label_min_size.x = min_slider_lab_size.x
	sun_rotate_x_slider.label_text = "Light Rotate X"
	light_panel.add_child(sun_rotate_x_slider)
	sun_rotate_x_slider.default_slide_val = directional_light.rotation_degrees.x
	sun_rotate_x_slider.slider.value = directional_light.rotation_degrees.x
	
	var sun_rotate_y_slider = ToolSlider.new()
	sun_rotate_y_slider.expand = false
	sun_rotate_y_slider.label_min_size.x = min_slider_lab_size.x
	sun_rotate_y_slider.label_text = "Light Rotate Y"
	light_panel.add_child(sun_rotate_y_slider)
	sun_rotate_y_slider.default_slide_val = directional_light.rotation_degrees.y
	sun_rotate_y_slider.slider.value = directional_light.rotation_degrees.y
	
	
	controller = ControllerFreeView.new()
	root_3d.add_child(controller)
	
	camera_panel = CameraPanel.new(controller)
	left_panel.add_child(camera_panel)
	camera_panel.hide()
	
	var _left_spacer = left_panel.add_spacer(false)
	
	stats_panel = StatsPanel.new()
	left_panel.add_child(stats_panel)
	stats_panel.hide()
	
	model_rotate_slider = ToolSlider.new()
	model_rotate_slider.slider_min_size.x = 200
	model_rotate_slider.label_text = "Active Model Rotate"
	model_rotate_slider.use_label = false
	center_panel.add_child(model_rotate_slider)
	model_rotate_slider.hide()
	
	
	camera = Camera3D.new()
	controller.add_child(camera)
	camera.position = Vector3(0, 1.6, 10)
	
	controller.camera = camera
	camera.fov = 50
	
	fov_slider.value = (fov_slider.max_value + fov_slider.min_value) - camera.fov
	fov_label.text="(%s deg)" % camera.fov
	
	
	mesh_manager = MeshManager.new()
	root_3d.add_child(mesh_manager)
	
	node_tree = NodeTree.new()
	main_split_container.add_child(node_tree)
	node_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_tree.size_flags_stretch_ratio = 0.3
	node_tree.tooltip_callable = _get_path_tooltip

	
	
	
	
	camera_panel.settings_changed.connect(_on_camera_settings_changed)
	
	mesh_manager.active_scene_set.connect(_on_active_scene_set)
	
	node_tree.item_right_clicked.connect(_on_node_tree_right_clicked)
	node_tree.path_activated.connect(_activate_path)
	
	next_mesh_button.pressed.connect(mesh_manager.show_next_mesh)
	prev_mesh_button.pressed.connect(mesh_manager.show_prev_mesh)
	list_scene_button.pressed.connect(_list_loaded_scenes)
	
	reset_button.pressed.connect(controller.camera_reset)
	mouse_detector.gui_input.connect(controller.mouse_input)
	
	
	sun_rotate_x_slider.slider.value_changed.connect(func(val):directional_light.rotation.x = deg_to_rad(val))
	sun_rotate_y_slider.slider.value_changed.connect(func(val):directional_light.rotation.y = deg_to_rad(val))
	model_rotate_slider.slider.value_changed.connect(mesh_manager.rotate_active_mesh)
	
	fov_slider.value_changed.connect(func(val):camera.fov = (fov_slider.max_value + fov_slider.min_value) - val;fov_label.text="(%s deg)" % camera.fov)
