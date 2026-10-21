extends Node
## Localization without the import pipeline: parses data/i18n/strings.csv at runtime into Translation
## resources (works with no .godot cache). Also installs the bundled CJK pixel font as the default theme font.
const CSV_PATH := "res://data/i18n/strings.csv"
const FONT_PATH := "res://assets/fonts/fusion-pixel/fusion-pixel-12px-proportional-zh_hans.otf.woff2"
const FONT_SIZE := 12
const LANGS := ["zh", "en"]
signal language_changed(lang: String)
var keys: PackedStringArray = []
var table: Dictionary = {} # lang -> {key: text}
var language := "en"
var font: FontFile

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_csv()
	_install_font()
	var lang := str(SaveManager.settings.get("language", detect_os_language()))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			lang = a.split("=")[1]
	set_language(lang, false)

static func detect_os_language() -> String:
	return "zh" if OS.get_locale_language().begins_with("zh") else "en"

func _load_csv() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("Missing translations: " + CSV_PATH)
		return
	var header := f.get_csv_line()
	var trs: Array[Translation] = []
	for i in range(1, header.size()):
		var t := Translation.new()
		t.locale = header[i]
		trs.append(t)
		table[header[i]] = {}
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < header.size() or row[0] == "":
			continue
		keys.append(row[0])
		for i in range(1, header.size()):
			var text := row[i].replace("\\n", "\n")
			trs[i - 1].add_message(row[0], text)
			table[header[i]][row[0]] = text
	for t in trs:
		TranslationServer.add_translation(t)

var ui_theme: Theme

func _install_font() -> void:
	if not FileAccess.file_exists(FONT_PATH):
		push_error("Missing font: " + FONT_PATH)
		return
	font = FontFile.new()
	font.data = FileAccess.get_file_as_bytes(FONT_PATH)
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.force_autohinter = false
	font.generate_mipmaps = false
	font.multichannel_signed_distance_field = false
	ThemeDB.fallback_font = font
	ThemeDB.fallback_font_size = FONT_SIZE
	ui_theme = load("res://scripts/ui/ui_theme.gd").build(font)
	get_tree().root.theme = ui_theme

func set_language(lang: String, save := true) -> void:
	if not (lang in LANGS):
		lang = "en"
	language = lang
	TranslationServer.set_locale(lang)
	if save:
		SaveManager.set_setting("language", lang)
	language_changed.emit(lang)

func toggle_language() -> void:
	set_language("en" if language == "zh" else "zh")

func has_key(k: String, lang: String) -> bool:
	return table.has(lang) and table[lang].has(k) and str(table[lang][k]) != ""

## Static-context helper (RefCounted/static funcs): same as tr().
func t(k: String) -> String:
	return TranslationServer.translate(k)
