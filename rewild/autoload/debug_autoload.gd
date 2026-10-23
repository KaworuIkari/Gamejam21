extends Node
class_name DebugNode

const DEBUG_MENU = preload("res://ui/debug/debug_menu.gd")
## Set false to hide the F1 cheat menu (e.g. for launch builds).
const DEBUG_MENU_ENABLED := true

func _init() -> void:
	RenderingServer.set_debug_generate_wireframes(true)

## Debug builds get the floating cheat menu (F1), see ui/debug/debug_menu.gd.
func _ready() -> void:
	if DEBUG_MENU_ENABLED and OS.is_debug_build():
		add_child.call_deferred(DEBUG_MENU.new()) # after the later autoloads (Quests)
	
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4:
		var root := get_tree().root
		var mode := (Viewport.DEBUG_DRAW_DISABLED
				if root.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME
				else Viewport.DEBUG_DRAW_WIREFRAME)
		root.debug_draw = mode
		for vp: SubViewport in root.find_children("*", "SubViewport", true, false):
			vp.debug_draw = mode

static func draw_vector(tree: SceneTree, start: Vector3, vector: Vector3, color: Color = Color.RED, scale: float = 1.0) -> void:
	if not tree or vector.length_squared() < 0.0001:
		return
	var end: Vector3 = start + (vector.normalized() * scale)
	# Create temporary mesh instance for 1 frame
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true # Visible through terrain/meshes for easy debugging
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	immediate_mesh.surface_add_vertex(start)
	immediate_mesh.surface_add_vertex(end)
	immediate_mesh.surface_end()
	mesh_instance.mesh = immediate_mesh
	var root: Node = tree.root
	root.add_child.call_deferred(mesh_instance)
	tree.process_frame.connect(mesh_instance.queue_free, CONNECT_ONE_SHOT)
