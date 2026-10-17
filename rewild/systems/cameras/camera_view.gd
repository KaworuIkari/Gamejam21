extends Node
class_name CameraView
## Makes the parent PhantomCamera3D addressable by name.

@export var view_name: StringName = &""
@export var activate_on_ready := false  ## true on exactly one view — the player's


func _ready() -> void:
	var pcam := get_parent() as PhantomCamera3D
	if pcam == null:
		push_error("%s: CameraView must be a child of a PhantomCamera3D" % get_path())
		return
	if view_name == &"":
		push_error("%s: view_name is empty" % get_path())
		return
	CameraDirector.register(view_name, pcam)
	if activate_on_ready:
		CameraDirector.activate(view_name)


func _exit_tree() -> void:
	if view_name != &"" and is_instance_valid(CameraDirector):
		CameraDirector.unregister(view_name)