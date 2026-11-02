@tool
extends Node3D

const UNode = preload("uid://bnf4h0107r8b4") #! resolve UtilR.UNode


const SCENE_EXTENSIONS = ["tscn", "scn", "glb", "gltf", "fbx"]

var decal_preview:Mesh

var _scene_cache:= {}
var current_scene:String=""

#^ impl
var show_only_active:=false
var collision_shapes_toggled:=true

#^ not impl
var label_height:float = 1
var label_size = 1
var label_current:=false
var show_labels:=true

var _current_mesh_index:=0

signal active_scene_set(scene, stats)

signal meshes_shown(scene_paths)

func _ready() -> void:
	decal_preview = PlaneMesh.new()



func load_scenes(scenes_to_load:PackedStringArray):
	_clean_cache(scenes_to_load)
	_get_or_inst_scenes(scenes_to_load)
	_current_mesh_index = 0
	
	await get_tree().process_frame
	
	show_scene(scenes_to_load[0], scenes_to_load)
	
	await get_tree().process_frame
	self.meshes_shown.emit()

func clear_cache():
	current_scene = ""
	_clean_cache([])

func _clean_cache(current_paths:PackedStringArray):
	for path in _scene_cache.keys():
		#if path in current_paths:
			#continue
		var scene_data = _scene_cache.get(path)
		if scene_data == null:
			continue
		var ins = scene_data.get(Keys.INSTANCE)
		if is_instance_valid(ins):
			if ins.is_inside_tree():
				remove_child(ins)
			ins.queue_free()
		_scene_cache.erase(path)


func _get_or_inst_scenes(current_paths:PackedStringArray):
	for path:String in current_paths:
		if _scene_cache.has(path):
			continue
		var scn = null
		if path.get_extension() in SCENE_EXTENSIONS:
			var pck:PackedScene = ResourceLoader.load(path)
			scn = pck.instantiate()
		else:
			var res = load(path)
			if res is Mesh:
				scn = MeshInstance3D.new()
				scn.mesh = res
			else:
				continue
		
		if scn == null:
			continue
		if scn is not Node3D:
			continue
		
		_scene_cache[path] = {
			Keys.INSTANCE: scn
		}


func _remove_current_scenes_from_tree(scns_to_keep:=PackedStringArray()):
	var remove_all = scns_to_keep.is_empty()
	var children = get_children()
	for c in children:
		if not remove_all and c.scene_file_path in scns_to_keep:
			continue
		c.owner = null
		remove_child(c)

func refresh():
	if _scene_cache.has(current_scene):
		show_scene(current_scene)

func show_scene(scene_path:String, scenes_to_show:Array=_scene_cache.keys()):
	current_scene = scene_path
	_remove_current_scenes_from_tree()
	if show_only_active:
		scenes_to_show = [scene_path]
	_show_scenes(scene_path, scenes_to_show)

func _show_scenes(current_scene_path:String, scns_to_show:Array):
	#_remove_current_scenes_from_tree() # not sure about this
	
	var extra_space_mul = 1 # HelperInst.ABConfig.space_between_scenes
	var pos_offset = Vector3.ZERO
	var first_scn = true
	for path in scns_to_show:
		_process_scene(path)
		var scene_data = _scene_cache[path]
		var scn_aabb = scene_data.get(Keys.SCN_AABB)
		if scn_aabb == null:
			continue
		var aabb_adj_size = scn_aabb.size.x * extra_space_mul
		if first_scn:
			first_scn = false
		else:
			pos_offset += Vector3(aabb_adj_size * 2, 0, 0)
		
		scene_data[Keys.POS_OFFSET] = pos_offset
	
	var current_scn_data = _scene_cache[current_scene_path]
	var current_scn_ins = current_scn_data.get(Keys.INSTANCE)
	var current_scn_pos = current_scn_data.get(Keys.POS_OFFSET, Vector3.ZERO)
	var adjusted_offset = Vector3.ZERO - current_scn_pos
	_set_label_settings(current_scene_path, true)
	
	add_child(current_scn_ins)
	current_scn_ins.position = Vector3.ZERO
	
	if current_scn_ins is Decal:
		active_scene_set.emit(current_scene_path, {})
	else:
		active_scene_set.emit(current_scene_path, get_current_scene_stats(current_scn_ins))
	
	for path in scns_to_show:
		if path == current_scene_path:
			continue
		_set_label_settings(path, false)
		var scene_data = _scene_cache[path]
		var ins = scene_data.get(Keys.INSTANCE)
		var offset = scene_data.get(Keys.POS_OFFSET)
		
		var new_position = offset + adjusted_offset
		add_child(ins)
		ins.position = new_position


func _process_scene(path):
	var scene_data = _scene_cache[path]
	if scene_data.get(Keys.PROCESSED, false) == true:
		return
	
	var ins = scene_data.get(Keys.INSTANCE)
	var scn_aabb:AABB

	var has_mesh = is_instance_valid(UNode.find_first_node_of_type(ins, MeshInstance3D))
	if has_mesh:
		scn_aabb = _get_scene_aabb(ins)
		scene_data[Keys.SCN_AABB] = scn_aabb
	
	elif ins is Decal:
		var new_mesh = MeshInstance3D.new()
		var decal_prev_mesh = decal_preview.duplicate()
		new_mesh.mesh = decal_prev_mesh
		
		scn_aabb.size = Vector3(ins.size.x, ins.size.y, ins.size.z)
		new_mesh.mesh.size = Vector2(ins.size.x, ins.size.z)
		scene_data[Keys.SCN_AABB] = scn_aabb
		ins.add_child(new_mesh)
	
	var collision_shapes = UNode.get_all_nodes_of_type(ins, CollisionShape3D)
	if not collision_shapes.is_empty():
		scene_data[Keys.COLLISION] = collision_shapes
	for col_shape:CollisionShape3D in collision_shapes:
		add_debug_shape(col_shape)
	
	var label = Label3D.new()
	ins.add_child(label)
	label.text = ins.name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	#label.fixed_size = true
	#label.pixel_size = 0.1
	if scn_aabb:
		label.position = Vector3(0 ,scn_aabb.size.y * label_height, 0)
	else:
		label.position = Vector3(0,1,0)
	
	scene_data[Keys.PROCESSED] = true


func add_debug_shape(collision_node: CollisionShape3D):
	if not collision_node.shape:
		return
	var debug_mesh = collision_node.shape.get_debug_mesh()
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = debug_mesh
	collision_node.add_child(mesh_instance)
	if not collision_shapes_toggled:
		collision_node.hide()


func _set_label_settings(path:String, is_current:=false):
	var scene_data = _scene_cache[path]
	
	
	var ins = scene_data.get(Keys.INSTANCE)
	var scn_label = UNode.find_first_node_of_type(ins, Label3D)
	if scn_label is Label3D:
		if not show_labels:
			scn_label.hide()
		else:
			scn_label.show()
		if is_current:
			scn_label.modulate = Color(0.4,0.8,0.2)
		else:
			scn_label.modulate = Color.WHITE
		
		var aabb:AABB = scene_data.get(Keys.SCN_AABB, AABB())
		if aabb.size == Vector3.ZERO:
			if not scn_label.text.ends_with(" (Empty AABB)"):
				scn_label.text = scn_label.text + " (Empty AABB)"
		else:
			scn_label.position = Vector3(0, aabb.size.y * label_height + 0.25, 0)
			#if HelperInst.ABConfig.label_adaptive_size:
				#current_scn_label.pixel_size = 0.005 * aabb.x * label_size
			#else:
			scn_label.pixel_size = 0.005 * label_size
			scn_label.pixel_size = clampf(scn_label.pixel_size, 0.001, 0.1)



func show_next_mesh():
	if _scene_cache.is_empty():
		return
	_current_mesh_index += 1
	if _current_mesh_index >= _scene_cache.size():
		_current_mesh_index = 0
	var paths = _scene_cache.keys()
	show_scene(paths[_current_mesh_index], paths)

func show_prev_mesh():
	if _scene_cache.is_empty():
		return
	_current_mesh_index -= 1
	if _current_mesh_index < 0 :
		_current_mesh_index = _scene_cache.size() - 1
	var paths = _scene_cache.keys()
	show_scene(paths[_current_mesh_index], paths)

func rotate_active_mesh(rotate_val:float):
	var ins = get_active_scene_instance() as Node3D
	if is_instance_valid(ins):
		ins.rotation.y = deg_to_rad(rotate_val)

func toggle_collision_shapes():
	collision_shapes_toggled = not collision_shapes_toggled
	for scene in _scene_cache.keys():
		var scene_data = _scene_cache[scene]
		var collisions = scene_data.get(Keys.COLLISION, [])
		for c in collisions:
			c.visible = collision_shapes_toggled

func _get_mesh_nodes(scn_ins):
	return UNode.get_all_nodes_of_type(scn_ins, MeshInstance3D)

func _get_collision_nodes(scn_ins):
	return UNode.get_all_nodes_of_type(scn_ins, CollisionShape3D)

func get_active_scene_instance():
	return _scene_cache.get(current_scene, {}).get(Keys.INSTANCE)

func get_loaded_paths():
	return _scene_cache.keys()

func get_scene_instance(path:String):
	return _scene_cache.get(path, {}).get(Keys.INSTANCE)

func get_current_scene_stats(scene:Node3D):
	var m = UNode.find_first_node_of_type(scene, MeshInstance3D)
	if not m:
		return {}
	var mesh:MeshInstance3D = m
	if not mesh.mesh is ArrayMesh:
		return {}
	var mesh_surf_count = mesh.mesh.get_surface_count()
	var m_tool = MeshDataTool.new()
	#print("mtool ",mesh)
	var face_count = 0
	var vert_count = 0
	var edge_count = 0
	for ms in mesh_surf_count:
		var err = m_tool.create_from_surface(mesh.mesh, ms)
		#print("errr ",err)
		if not err == OK:
			continue
		face_count += m_tool.get_face_count()
		vert_count += m_tool.get_vertex_count()
		edge_count += m_tool.get_edge_count()
	
	var scn_stats ={
		Keys.FACE_COUNT: face_count,
		Keys.VERT_COUNT: vert_count,
		Keys.EDGE_COUNT: edge_count,
	}
	return scn_stats


class Keys:
	const INSTANCE = &"INSTANCE"
	const POS_OFFSET = &"POS_OFFSET"
	const SCN_AABB = &"SCN_AABB"
	const COLLISION = &"COLLISION"
	const PROCESSED = &"PROCESSED"
	
	const FACE_COUNT = &"FACE_COUNT"
	const VERT_COUNT = &"VERT_COUNT"
	const EDGE_COUNT = &"EDGE_COUNT"


## Union of every MeshInstance3D's mesh AABB under scene_root, in mesh-local space.
static func _get_scene_aabb(scene_root:Node) -> AABB:
	var first_aabb:AABB
	for mesh_instance:MeshInstance3D in UNode.get_all_nodes_of_type(scene_root, MeshInstance3D):
		var aabb:AABB = mesh_instance.mesh.get_aabb()
		if not first_aabb:
			first_aabb = aabb
		else:
			first_aabb.merge(aabb)
	return first_aabb
