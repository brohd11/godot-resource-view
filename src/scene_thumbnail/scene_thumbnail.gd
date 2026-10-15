#! namespace ResourceView class SceneThumbnail
extends Node

const UString = preload("uid://dce8d0wuh35gs") #! resolve UtilR.Strings.UString
const PackedSceneReadFile = preload("uid://cx8sx32appge5") #! resolve UtilR.Resources.Read.Tscn

const SceneThumbnailViewport = preload("res://addons/_lib/resource_view/src/scene_thumbnail/scene_thumbnail_viewport.gd")

const VALID_ROOTS = ["Node3D", "MeshInstance3D", "Decal", "StaticBody3D", "Character"]

const TEXTURE_DIR = "user://addons/resource_view/scn_thumb_cache"

const PREVIEW = &"preview"
const PREVIEW_PATH = &"preview_path"

var thread = Thread.new()

var scene_preview_viewport:SceneThumbnailViewport

var preview_size:int = 64

signal queue_processed
signal cache_loaded

var cache:= {}
var hash_cache:={}

var preview_queue: Array[String] = []
var _is_processing = false

func _ready() -> void:
	_pre_checks()
	threaded_load_cache()


func _pre_checks():
	if not DirAccess.dir_exists_absolute(TEXTURE_DIR):
		DirAccess.make_dir_recursive_absolute(TEXTURE_DIR)
	if not is_instance_valid(scene_preview_viewport):
		scene_preview_viewport = SceneThumbnailViewport.new()
		add_child(scene_preview_viewport)

func queue_paths(file_paths:PackedStringArray):
	for p in file_paths:
		queue_path(p)

func queue_path(scene_path: String):
	preview_queue.append(scene_path)
	if not _is_processing:
		_process_queue()

func _process_queue():
	_is_processing = true
	var valid_roots = ClassDB.get_inheriters_from_class("Node3D")
	valid_roots.append("Node3D")
	
	var gen_count = 0
	var fail_count = 0
	
	while preview_queue.size() > 0:
		await get_tree().process_frame
		var path = preview_queue.pop_front()
		
		# 1. Do the heavy work
		if path.get_extension() == "tscn": 
			
			if not PackedSceneReadFile.check_root(path, valid_roots):
				print("Path is not valid 3D scene: %s" % path)
				fail_count += 1
				continue
		
		var instanced = scene_preview_viewport.instance_scene(path)
		if not instanced:
			scene_preview_viewport.free_scene()
			print("Scene does not have mesh or decal node: %s" % path)
			fail_count += 1
			continue
		
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		
		var texture = await scene_preview_viewport.create_preview(preview_size)
		
		if texture.get_image().is_invisible():
			print("Preview generated but invisible for: ", path)
			fail_count += 1
			continue
		
		# 2. Emit/Save result
		
		# emit_signal("preview_ready", path, texture)
		
		_save_texture(path, texture)
		scene_preview_viewport.free_scene()
		gen_count += 1
		
		print("Generated preview for: ", path)
		
		# 3. CRITICAL: Let the UI breathe!
		# This prevents the loop from hogging the CPU.
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
	
	print("Generation finished. Success: %s Failed: %s" % [gen_count, fail_count])
	queue_processed.emit()
	_is_processing = false



func _save_texture(path:String, texture):
	var _hash = get_path_hash(path)
	var file_name = "%s.png" % _hash
	#var file_name = path.get_file().get_basename() + "_%s.png" % _hash
	var save_path = TEXTURE_DIR.path_join(file_name)
	texture.get_image().save_png(save_path)
	
	cache[_hash] = texture


func threaded_load_cache():
	thread.start(load_texture_cache)
	while thread.is_alive():
		await get_tree().process_frame
	thread.wait_to_finish()
	await get_tree().process_frame
	cache_loaded.emit()

func load_texture_cache():
	var files = DirAccess.get_files_at(TEXTURE_DIR)
	for f in files:
		var path = TEXTURE_DIR.path_join(f)
		var _hash = f.get_basename()
		var image = Image.load_from_file(path)
		var texture = ImageTexture.create_from_image(image)
		cache[_hash] = {PREVIEW_PATH:path, PREVIEW:texture}



func hash_file_paths(paths:PackedStringArray):
	hash_cache = {}
	for path:String in paths:
		var _hash = get_path_hash(path)
		hash_cache[path] = _hash


func get_path_hash(path:String):
	if hash_cache.has(path):
		return hash_cache[path]
	var _hash:String = get_path_hash_static(path)
	hash_cache[path] = _hash
	return _hash

func clear_texture_cache():
	if not DirAccess.dir_exists_absolute(TEXTURE_DIR):
		return
	var files = DirAccess.get_files_at(TEXTURE_DIR)
	for f in files:
		var path = TEXTURE_DIR.path_join(f)
		DirAccess.remove_absolute(path)
	
	cache.clear()

static func get_path_hash_static(path:String):
	return UString.hash_string(path, HashingContext.HashType.HASH_SHA256, 10)
