#! namespace ResourceView class MaterialViewer
extends VBoxContainer

const ControllerFreeView = preload("uid://chvmdxo2kpwt3") #! resolve CamControl.Mouse.FreeView

enum ModelType{
	SPHERE,
	
}

var subview_container:SubViewportContainer
var mouse_detector:Control
var subview:SubViewport
var root_3d:Node3D

var cam_controller:ControllerFreeView
var camera:Camera3D
var light:DirectionalLight3D

var preview_mesh:MeshInstance3D

func _ready() -> void:
	# tool header?
	
	subview_container = SubViewportContainer.new()
	add_child(subview_container)
	subview_container.stretch = true
	subview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	mouse_detector = Control.new()
	subview_container.add_child(mouse_detector)
	mouse_detector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	subview = SubViewport.new()
	subview_container.add_child(subview)
	subview.own_world_3d = true
	
	root_3d = Node3D.new()
	subview.add_child(root_3d)
	
	cam_controller = ControllerFreeView.new()
	root_3d.add_child(cam_controller)
	mouse_detector.gui_input.connect(cam_controller.mouse_input)
	
	camera = Camera3D.new()
	cam_controller.add_child(camera)
	cam_controller.camera = camera
	_reset_camera()
	
	light = DirectionalLight3D.new()
	root_3d.add_child(light)
	_set_light_pos()
	
	preview_mesh = MeshInstance3D.new()
	root_3d.add_child(preview_mesh)
	_set_preview_mesh_shape(ModelType.SPHERE)


func _set_preview_mesh_shape(type:ModelType=ModelType.SPHERE):
	var mesh:Mesh
	if type == ModelType.SPHERE:
		mesh = SphereMesh.new()
		mesh.height = 2
		mesh.radius = 1
	
	preview_mesh.mesh = mesh

func set_material_path(path:String):
	var mat = load(path)
	if not is_instance_valid(preview_mesh.mesh):
		_set_preview_mesh_shape(ModelType.SPHERE)
	
	preview_mesh.mesh.surface_set_material(0, mat)
	
	_set_light_pos()
	_reset_camera()
	

func _reset_camera():
	camera.position.z = 3
	cam_controller.rotation = Vector3.ZERO

func _set_light_pos():
	var light_pos = Vector3(1.5, 2, 1) * 10
	light.position = light_pos
	light.look_at(-light_pos)
	#print(light.rotation_degrees)
	
