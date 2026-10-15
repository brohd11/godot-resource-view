@tool
extends Node

const UNode = preload("uid://bnf4h0107r8b4") #! resolve UtilR.UNode

var viewport:SubViewport

var tools:Node3D

var hide_node:Node3D
var world_env:WorldEnvironment
var light_pivot:Node3D
var light:DirectionalLight3D
var cam_pivot:Node3D
var cam:Camera3D

var decal_preview_mesh:Mesh

var scene_target:Node3D

var scene_instance:Node
var mesh_nodes = []

var is_decal:bool = false

func _ready():
	_build_nodes()


func instance_scene(scene_path:String):
	var scn_pck:PackedScene = ResourceLoader.load(scene_path)
	scene_instance = scn_pck.instantiate()
	
	if not scene_instance is Node3D:
		return false
	if scene_instance is Decal:
		is_decal = true
		return true
	
	var all_nodes = UNode.recursive_get_nodes(scene_instance)
	mesh_nodes = []
	for node in all_nodes:
		if node is MeshInstance3D:
			mesh_nodes.append(node)
	
	if mesh_nodes.is_empty():
		return false
	
	return true

func free_scene():
	if is_instance_valid(scene_instance):
		if scene_instance.is_inside_tree():
			scene_instance.get_parent().remove_child(scene_instance)
		scene_instance.queue_free()
	return true

func _reset_viewport():
	_new_viewport()
	viewport.transparent_bg = true
	cam_pivot.position = Vector3.ZERO
	cam_pivot.rotation_degrees = Vector3.ZERO
	cam.position = Vector3.ZERO
	cam.rotation_degrees = Vector3.ZERO
	light_pivot.rotation_degrees = Vector3.ZERO
	light.position = Vector3.ZERO


func create_preview(resolution:int=128) -> ViewportTexture:
	_reset_viewport()
	scene_target.add_child(scene_instance)
	
	
	var vp_size:int = resolution
	viewport.size = Vector2(vp_size,vp_size)
	light.light_energy = 1
	viewport.render_target_clear_mode = viewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = viewport.UPDATE_DISABLED
	viewport.render_target_update_mode = viewport.UPDATE_ALWAYS
	
	if is_decal:
		_decal_preview()
	else:
		_scene_preview()
	
	await get_tree().process_frame
	
	await RenderingServer.frame_post_draw
	var tex:ViewportTexture = viewport.get_texture()
	
	#await get_tree().process_frame
	return tex


func _scene_preview():
	var first_aabb:AABB
	for mesh_instance:MeshInstance3D in mesh_nodes:
		var mesh:Mesh = mesh_instance.mesh
		var aabb:AABB = mesh.get_aabb()
		if not first_aabb:
			first_aabb = aabb
		else:
			first_aabb.merge(aabb)
	
	var aabb_center_pos = first_aabb.get_center()
	var aabb_size = first_aabb.size
	var aabb_size_x = aabb_size.x
	var aabb_size_y = aabb_size.y
	
	var fov = deg_to_rad(cam.fov)
	var distance = (aabb_size.length() / 2) / tan(fov / 2)
	
	cam_pivot.position = aabb_center_pos
	cam_pivot.rotation_degrees = Vector3(-30,35, 0)
	cam.position.z = distance
	cam.look_at(aabb_center_pos)
	
	#light_pivot.rotation_degrees = Vector3(0, -65, 0)
	light.position = aabb_center_pos + Vector3(10,20,10)
	light.look_at(aabb_center_pos)


func _decal_preview():
	var decal_instance = scene_instance as Decal
	var decal_vec_size = Vector2(decal_instance.size.x, decal_instance.size.z)
	
	var decal_target = MeshInstance3D.new()
	var decal_target_mesh = decal_preview_mesh.duplicate()
	decal_target_mesh.size = decal_vec_size
	decal_target.mesh = decal_target_mesh
	
	decal_instance.add_child(decal_target)
	decal_instance.rotate_x(deg_to_rad(-90))
	
	var decal_vec_length = decal_vec_size.length()
	var fov = cam.fov
	var distance = (decal_vec_length / 2) / tan(fov / 2) * 1.5 # 1.5 magic number
	
	cam.position.z = distance
	cam.look_at(Vector3.ZERO)
	
	light.position.z = distance
	light.look_at(Vector3.ZERO)


func delete_gen_preview():
	if not scene_instance.is_inside_tree():
		scene_instance.queue_free()
	queue_free()

func _new_viewport():
	var new_viewport = SubViewport.new()
	if is_instance_valid(viewport):
		viewport.replace_by(new_viewport)
		viewport.queue_free()
	else:
		add_child(new_viewport)
	viewport = new_viewport

func _build_nodes():
	if is_instance_valid(tools):
		remove_child(tools)
		tools.queue_free()
	if is_instance_valid(scene_target):
		remove_child(scene_target)
		scene_target.queue_free()
	
	_new_viewport()
	
	tools = Node3D.new()
	viewport.add_child(tools)
	
	hide_node = Node3D.new()
	tools.add_child(hide_node)
	hide_node.hide()
	
	world_env = WorldEnvironment.new()
	tools.add_child(world_env)
	world_env.environment = Environment.new()
	
	light_pivot = Node3D.new()
	tools.add_child(light_pivot)
	
	light = DirectionalLight3D.new()
	light_pivot.add_child(light)
	
	cam_pivot = Node3D.new()
	tools.add_child(cam_pivot)
	
	cam = Camera3D.new()
	cam_pivot.add_child(cam)
	
	scene_target = Node3D.new()
	viewport.add_child(scene_target)
	
	decal_preview_mesh = PlaneMesh.new()
	decal_preview_mesh.size = Vector2(2,2)
