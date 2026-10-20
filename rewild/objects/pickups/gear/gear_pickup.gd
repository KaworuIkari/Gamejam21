class_name GearPickup
extends InteractTrigger
## Floating brass gear picked up with the interact key. Reports `event` (the counted total)
## and `saved_event` (this gear only, so it is not respawned after loading) to the quests;
## the count is saved with the quests, so collected gears stay with LIRA.
## The gear is built from simple meshes in _ready; the SoftSparkles child is the same
## glimmer as the readables: hide it or set `emitting` off to remove the highlight.

signal collected(gear: GearPickup)

@export var event: StringName = &"factory_gear"
@export var saved_event: StringName = &""
@export var bob_height := 0.12
@export var bob_speed := 2.0
@export var spin_speed := 1.4
@export var color := Color(0.82, 0.62, 0.28)
@export var gear_radius := 0.26
@export var teeth := 10

@onready var _visual: Node3D = $Visual

var _time := randf() * TAU


func _init() -> void:
	message_key = "INTERACT_GEAR_PICKUP"


func _ready() -> void:
	super._ready()
	_build_gear()
	interacted.connect(_collect)


func _process(delta: float) -> void:
	super._process(delta)
	if _used:
		return
	_time += delta
	_visual.position.y = sin(_time * bob_speed) * bob_height
	_visual.rotation.y += spin_speed * delta


func _build_gear() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = color
	metal.metallic = 0.8
	metal.roughness = 0.35
	var dark := StandardMaterial3D.new()
	dark.albedo_color = color.darkened(0.6)
	dark.roughness = 0.6
	# Stands upright: the wheel's axis is the gear node's Y, tipped onto its side.
	var gear := Node3D.new()
	gear.name = "Gear"
	gear.rotation.x = PI / 2
	_visual.add_child(gear)
	gear.add_child(_part(_cylinder(gear_radius, 0.08), metal))
	gear.add_child(_part(_cylinder(gear_radius * 0.3, 0.1), dark))
	var tooth := BoxMesh.new()
	tooth.size = Vector3(gear_radius * 0.38, 0.08, gear_radius * 0.38)
	for i in teeth:
		var a := TAU * i / teeth
		var t := _part(tooth, metal)
		t.position = Vector3(cos(a), 0.0, sin(a)) * gear_radius
		t.rotation.y = -a
		gear.add_child(t)


func _cylinder(r: float, h: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 24
	return mesh


func _part(mesh: Mesh, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	return part


func _collect() -> void:
	$SoftSparkles.emitting = false
	UIAudio.play_sfx(UIAudio.GEAR_PICKUP)
	Quests.report(saved_event)
	Quests.report(event)
	collected.emit(self)
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "scale", Vector3.ONE * 1.3, 0.1)
	tween.tween_property(_visual, "scale", Vector3.ZERO, 0.2)
	tween.tween_callback(queue_free)
