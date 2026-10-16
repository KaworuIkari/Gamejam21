extends Node3D
## Isolated demonstration: uses the project's real GrowthMap, no save or quest changes.
const DIR='res://objects/restorable/overgrown/'
var _growth:Node
var _points:Array[Vector3]=[]
var _label:Label
var _time:float=0.0
var _watered:bool=false
func _ready():
 _growth=get_node_or_null('/root/GrowthMap')
 var names=['wooden/restorable_timber_bench','wooden/restorable_wayside_shelter','industrial/restorable_power_cabinet','deadwood/restorable_fallen_log']
 for i in names.size():
  var p=load(DIR+names[i]+'.tscn').instantiate()
  p.position=Vector3((i%2)*4-2,0,(i/2)*4-2);add_child(p);_points.append(p.global_position)
 var floor_mesh=MeshInstance3D.new();var plane=PlaneMesh.new();plane.size=Vector2(24,24);floor_mesh.mesh=plane
 var material=StandardMaterial3D.new();material.albedo_color=Color(.37,.31,.21);floor_mesh.material_override=material;floor_mesh.position.y=-.025;add_child(floor_mesh)
 var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.18,.21,.19);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.8,.85,.75);env.environment.ambient_light_energy=.7;add_child(env)
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-35,0);light.light_energy=1.5;add_child(light)
 var camera=Camera3D.new();add_child(camera);camera.position=Vector3(10,10,13);camera.look_at(Vector3(0,.6,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=13;camera.current=true
 var ui=CanvasLayer.new();add_child(ui);_label=Label.new();_label.position=Vector2(24,22);_label.add_theme_font_size_override('font_size',22);ui.add_child(_label)
 _label.text='Barren structures — greenery grows after watering'
 if not _growth:_label.text='Open this demo inside Rewild to use its GrowthMap.'
func _process(dt):
 _time+=dt
 if _time>1.5 and not _watered and _growth:
  _watered=true
  for point in _points:_growth.water(point,4.0)
  _label.text='Water applied — waiting for local ground to turn green'
 if _time>6 and _growth:_label.text='Greenery grows in patches; structures and collision remain fixed'
func _unhandled_input(event):
 if event is InputEventKey and event.pressed and event.keycode==KEY_SPACE and _growth:
  _growth.clear();_time=0;_watered=false
