class_name BundledFonts
extends RefCounted
## The UI asks for its fonts by family name (SystemFont). Where the first-choice
## family is not installed (always on Web, which has no system fonts; usually on
## Android, iOS, Windows and macOS) the bundled OFL copy in assets/fonts is used
## instead, at the requested weight, so the game looks the same everywhere and
## glyphs such as the scope's trend arrows exist. Installed families still win.
## Usage: replace `_fonts[key] = system_font` with `_fonts[key] = BundledFonts.or_system(system_font)`.

const FILES := {
	"Inter": "res://assets/fonts/InterVariable.ttf",
	"Inter Display": "res://assets/fonts/InterVariable.ttf",
	"JetBrains Mono": "res://assets/fonts/JetBrainsMono-Variable.ttf",
	"B612 Mono": "res://assets/fonts/JetBrainsMono-Variable.ttf",
}

static var _installed: Dictionary = {}
static var _scanned := false
## One FontFile per file and rendering settings (the variations share it).
static var _data: Dictionary = {}


## `f` itself when its first family is installed (or not one we bundle), else a
## FontVariation of the bundled font with the same weight and rendering settings.
static func or_system(f: SystemFont) -> Font:
	if f.font_names.is_empty():
		return f
	var family: String = f.font_names[0]
	if not FILES.has(family) or is_installed(family):
		return f
	var data := _font_data(String(FILES[family]), f)
	if data == null:
		return f
	var v := FontVariation.new()
	v.base_font = data
	var axes := {"wght": clampi(f.font_weight, 100, 900)}
	if family == "Inter Display":
		axes["opsz"] = 32 # Inter's display optical size
	v.variation_opentype = axes
	return v


static func _font_data(path: String, f: SystemFont) -> FontFile:
	var key := "%s|%d|%d|%d|%s|%s" % [path, f.antialiasing, f.hinting, f.subpixel_positioning,
		f.generate_mipmaps, f.allow_system_fallback]
	if not _data.has(key):
		var src := load(path) as FontFile
		if src == null:
			return null
		var data := src.duplicate() as FontFile
		data.antialiasing = f.antialiasing
		data.hinting = f.hinting
		data.subpixel_positioning = f.subpixel_positioning
		data.generate_mipmaps = f.generate_mipmaps
		data.allow_system_fallback = f.allow_system_fallback
		_data[key] = data
	return _data[key]


static func is_installed(family: String) -> bool:
	if not _scanned:
		_scanned = true
		for n in OS.get_system_fonts():
			_installed[n] = true
	return _installed.has(family)
