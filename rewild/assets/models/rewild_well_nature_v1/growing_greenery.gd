@tool
extends Node3D
## Plant-only overlay. Each Patch mesh grows around its own surface anchor.
## Ground greenness and timing match systems/world_objects/restorable.gd.
@export_range(0.0, 1.0) var threshold: float = 0.6
@export var pop_time: float = 0.8
@export var max_delay: float = 1.2
@export var preview_green: bool = true:
 set(value):
  preview_green = value
  if Engine.is_editor_hint() and is_inside_tree():
   for patch in _patches: patch.visible = value
## Optional sample anchor for islands/platforms outside waterable soil.
## Empty: every patch samples its own world XZ, including raised roof patches.
@export var sample_anchor: NodePath
var _patches: Array[Node3D] = []
var _full_scales: Array[Vector3] = []
var _active: Array[bool] = []
var _tweens: Array = []
var _growth: Node
var _elapsed: float = 0.0
func _ready() -> void:
 _collect(self)
 for p in _patches:
  _full_scales.append(p.scale)
  _active.append(false)
  _tweens.append(null)
 if Engine.is_editor_hint():
  for p in _patches:p.visible = preview_green
  set_process(false)
  return
 _growth = get_node_or_null('/root/GrowthMap')
 # No growth system: useful full-green static preview, not a permanently hidden prop.
 if _growth == null:
  show_all_instant()
  set_process(false)
 else:
  for p in _patches:p.hide()
  refresh(true)
func _collect(n: Node) -> void:
 for c in n.get_children():
  if c is Node3D and String(c.name).begins_with('Patch_'):
   _patches.append(c)
  else:_collect(c)
func _process(delta: float) -> void:
 _elapsed += delta
 if _elapsed >= 0.3:
  _elapsed = 0.0
  refresh(false)
func refresh(instant: bool = false) -> void:
 if not is_instance_valid(_growth):return
 var anchor = get_node_or_null(sample_anchor) if not sample_anchor.is_empty() else null
 for i in _patches.size():
  var point: Vector3 = anchor.global_position if anchor is Node3D else _patches[i].global_position
  _set_patch(i, float(_growth.sample(point)) >= threshold, instant)
func _set_patch(i: int, green: bool, instant: bool) -> void:
 if _active[i] == green:return
 _active[i] = green
 if _tweens[i] != null and _tweens[i].is_valid():_tweens[i].kill()
 _tweens[i] = null
 var p = _patches[i]
 p.visible = green
 p.scale = _full_scales[i]
 if green and not instant:
  p.scale = _full_scales[i] * 0.05
  var tween = create_tween()
  _tweens[i] = tween
  tween.tween_interval(randf() * max_delay)
  tween.tween_property(p, 'scale', _full_scales[i], pop_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
func show_all_instant() -> void:
 for i in _patches.size():_set_patch(i, true, true)
func patch_count() -> int:return _patches.size()
func active_patch_count() -> int:
 var total = 0
 for active in _active:
  if active:total += 1
 return total
