extends Control
## Covers the live preview so its controls don't receive mouse input; clicks
## pick the control underneath instead (left selects, right is for a menu).

signal picked(control: Control)
signal context_requested(control: Control, screen_position: Vector2)

var root: Control


func _init() -> void:
	name = "PickOverlay"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _gui_input(event: InputEvent) -> void:
	var button = event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
		return
	accept_event()
	var control = pick(root, get_global_transform() * button.position) if is_instance_valid(root) else null
	if control == null:
		return
	if button.button_index == MOUSE_BUTTON_LEFT:
		picked.emit(control)
	else:
		context_requested.emit(control, get_screen_transform() * button.position)


## Deepest visible control under [param point] (canvas space). mouse_filter is ignored
## so labels and other pass-through controls stay pickable.
static func pick(control: Control, point: Vector2) -> Control:
	if not control.visible:
		return null
	var inside = Rect2(Vector2.ZERO, control.size).has_point(control.get_global_transform().affine_inverse() * point)
	if control.clip_contents and not inside:
		return null
	# Later siblings draw on top, so they win.
	for i in range(control.get_child_count() - 1, -1, -1):
		var child = control.get_child(i) as Control
		if child == null:
			continue
		var hit = pick(child, point)
		if hit != null:
			return hit
	return control if inside else null
