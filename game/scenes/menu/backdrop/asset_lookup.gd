class_name AssetLookup
extends RefCounted
## Finds optional CC0 assets under res://assets by file name keywords, so the
## procedural scenes work with or without the asset pack.

const ROOT := "res://assets"
const IMAGE_EXT: Array[String] = ["png", "jpg", "jpeg", "webp", "exr", "hdr"]

static var _files: PackedStringArray = []
static var _scanned := false


static func all_files() -> PackedStringArray:
	if not _scanned:
		_scanned = true
		_scan(ROOT)
	return _files


## First texture whose path contains one of `subjects` and whose file name
## contains one of `maps` (both case-insensitive), or null.
static func find_texture(subjects: Array, maps: Array) -> Texture2D:
	var p := find_path(subjects, maps)
	if p == "":
		return null
	return load(p) as Texture2D


static func find_path(subjects: Array, maps: Array) -> String:
	for subject: String in subjects:
		for map: String in maps:
			for f in all_files():
				var lf := f.to_lower()
				if lf.get_extension() in IMAGE_EXT and subject in lf and map in lf.get_file():
					return f
	return ""


static func _scan(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories():
		_scan(dir_path.path_join(sub))
	for f in d.get_files():
		# Exported builds list "x.png.import" instead of the source file.
		var name := f.trim_suffix(".import") if f.ends_with(".import") else f
		var full := dir_path.path_join(name)
		if not _files.has(full) and ResourceLoader.exists(full):
			_files.append(full)
