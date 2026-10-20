extends Node
## Versioned settings save with migration. Phase 1: settings only.
const SAVE_VERSION := 3
const SETTINGS_PATH := "user://settings.json"
var settings: Dictionary = {}

func _ready() -> void:
	load_settings()

func default_settings() -> Dictionary:
	return {"version": SAVE_VERSION, "sfx_volume_db": -10.0, "show_perf": false, "screen_shake": true, "reduce_flash": false}

func load_settings() -> void:
	settings = default_settings()
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			settings.merge(_migrate(d), true)
	AudioManager.sfx_volume_db = float(settings["sfx_volume_db"])
	save_settings()

func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	if v < 2:
		# v1 stored "volume" as 0..1 linear
		if d.has("volume"):
			d["sfx_volume_db"] = linear_to_db(maxf(0.001, float(d["volume"])))
			d.erase("volume")
	if v < 3:
		d["reduce_flash"] = false
	d["version"] = SAVE_VERSION
	return d

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))

func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	save_settings()
