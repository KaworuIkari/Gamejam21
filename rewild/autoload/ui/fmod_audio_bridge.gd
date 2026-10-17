extends Node
## User volume and temporary gameplay mix are independent gains.
## FMOD bank loading is scene-owned, so discover buses again after a late load.
const BUS_KEYS := {
	"bus:/": "master_volume",
	"bus:/BGM": "music_volume",
	"bus:/SFX": "sfx_volume",
	"bus:/Ambient": "ambient_volume",
}
var _mix: Dictionary = {}
var _buses: Dictionary = {}
var _poll := 0.0
@onready var _settings: Node = get_parent()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings.setting_changed.connect(_setting_changed)
	refresh.call_deferred()

func _process(delta: float) -> void:
	_poll += delta
	if _poll >= 0.5:
		_poll = 0.0
		refresh()

func _setting_changed(section: String, key: String, _value: Variant) -> void:
	if section == "audio" and key in BUS_KEYS.values():
		apply_volumes()

func refresh() -> void:
	_buses.clear()
	# Enumerating loaded buses avoids missing-path warnings in the main menu,
	# where no FMOD banks are loaded. Reverb is intentionally not an ambient bus.
	for bank in FmodServer.get_all_banks():
		for bus in bank.get_bus_list():
			if bus.is_valid() and BUS_KEYS.has(bus.get_path()):
				_buses[bus.get_path()] = bus
	apply_volumes()

func apply_volumes() -> void:
	for path in _buses:
		var bus = _buses[path]
		if bus.is_valid():
			var volume := clampf(float(_settings.get_value("audio",BUS_KEYS[path]))/100.0,0,1)
			bus.set_volume(volume * float(_mix.get(path,1.0)))

func set_mix(path: String, gain: float) -> void:
	if not BUS_KEYS.has(path):
		return
	var value := clampf(gain,0,1)
	if _mix.has(path) and is_equal_approx(float(_mix[path]),value):
		return
	_mix[path] = value
	apply_volumes()

func reset_mix() -> void:
	_mix.clear()
	refresh()
