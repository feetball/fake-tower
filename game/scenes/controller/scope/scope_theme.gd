extends RefCounted
## Colours, fonts and sizes of the radar scope and the flight-data display.
## STARS/Eurocat-like: near-black green field, muted map, bright targets.
## Sizes are physical pixels at scale 1.0 (1920x1080); callers multiply by
## the scope's text scale.

const BG := Color(0.008, 0.02, 0.014)
const RING := Color(0.09, 0.2, 0.13)
const RING_10 := Color(0.12, 0.26, 0.17)
const RING_LABEL := Color(0.24, 0.45, 0.3)
const COMPASS := Color(0.2, 0.42, 0.27)
const CL := Color(0.22, 0.47, 0.3)
const RWY := Color(0.82, 0.93, 0.85)
const MAP := Color(0.27, 0.56, 0.36)
const FIX := Color(0.38, 0.68, 0.46)
const TERR := Color(0.55, 0.42, 0.16)
const TERR_FILL := Color(0.55, 0.42, 0.16, 0.06)
const TERR_LABEL := Color(0.78, 0.6, 0.25)
const TERR_NAME := Color(0.55, 0.43, 0.2)
const MSA := Color(0.43, 0.34, 0.12)
const MSA_LABEL := Color(0.72, 0.57, 0.2)
const HOLD := Color(0.24, 0.53, 0.6)
const TARGET := Color(0.55, 1.0, 0.62)
const BLOCK := Color(0.58, 1.0, 0.64)
const HIST := Color(0.25, 0.75, 0.4)
const PTL := Color(0.33, 0.75, 0.42)
const SEL := Color(0.96, 1.0, 0.97)
const CA := Color(1.0, 0.25, 0.22)
const LA := Color(1.0, 0.7, 0.13)
const RBL := Color(0.94, 0.89, 0.42)
const HUD := Color(0.4, 0.76, 0.48)
const HUD_DIM := Color(0.22, 0.43, 0.29)
const CRASH := Color(0.9, 0.24, 0.22)
const LANDED := Color(0.3, 0.5, 0.36)
const DCB_BG := Color(0.03, 0.07, 0.05)
const DCB_ON := Color(0.1, 0.3, 0.17)
const DCB_EDGE := Color(0.18, 0.4, 0.25)
const DCB_TEXT := Color(0.72, 0.95, 0.76)
const DCB_TEXT_OFF := Color(0.32, 0.5, 0.37)
const BLOCK_BACK := Color(0.0, 0.02, 0.01, 0.82)

# Flight-data display (side panel).
const FDD_BG := Color(0.035, 0.045, 0.055)
const FDD_LINE := Color(0.25, 0.32, 0.38, 0.55)
const FDD_HEAD := Color(0.45, 0.62, 0.72)
const FDD_TEXT := Color(0.84, 0.88, 0.9)
const FDD_DIM := Color(0.5, 0.56, 0.6)
const FDD_FAINT := Color(0.32, 0.37, 0.41)
const FDD_ACCENT := Color(0.56, 0.93, 0.7)
const FDD_AMBER := Color(1.0, 0.74, 0.3)
const FDD_RED := Color(1.0, 0.38, 0.32)
const FDD_STRIP := Color(0.075, 0.09, 0.1)
const FDD_STRIP_SEL := Color(0.1, 0.125, 0.135)

const MONO_NAMES: PackedStringArray = ["JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"]
const SANS_NAMES: PackedStringArray = ["Inter", "DejaVu Sans", "Liberation Sans", "Arial", "sans-serif"]

static var _fonts: Dictionary = {}


static func mono(weight: int = 500) -> Font:
	return _font("mono", MONO_NAMES, weight)


static func sans(weight: int = 400) -> Font:
	return _font("sans", SANS_NAMES, weight)


static func _font(kind: String, names: PackedStringArray, weight: int) -> Font:
	var key := "%s-%d" % [kind, weight]
	if not _fonts.has(key):
		var f := SystemFont.new()
		f.font_names = names
		f.font_weight = weight
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.allow_system_fallback = true
		_fonts[key] = BundledFonts.or_system(f)
	return _fonts[key]
