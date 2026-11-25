extends RefCounted
## State shared by the scope's drawing layers and its input handler: model,
## view transform, world data, text scale and transient interaction state.

const Model := preload("res://scenes/controller/scope/scope_model.gd")
const Xform := preload("res://scenes/controller/scope/scope_xform.gd")
const Look := preload("res://scenes/controller/scope/scope_theme.gd")

var model := Model.new()
var xform := Xform.new()
var world: Dictionary = {}
var size := Vector2(1000, 800) ## scope pixels
var ui_scale := 1.0 ## physical pixels per 1080p canvas unit
var now_ms := 0
var flash_on := true
var force_flash := false
var mouse := Vector2(-1, -1) ## scope pixels, x < 0 when outside
var rbl_active := false
var rbl_live := false
var rbl_a := Vector2.ZERO ## world nm
var rbl_b := Vector2.ZERO
var block_rects: Dictionary = {} ## callsign -> Rect2, filled by the target layer
var dcb_rects: Array[Dictionary] = [] ## {id, rect}, filled by the chrome layer
var dcb_h := 36.0
var status: Dictionary = {} ## icao, time, atis_letter, qnh, transition_alt


## Geometry in physical pixels for a 1080p-canvas length.
func px(v: float) -> float:
	return v * ui_scale


## Font size with a floor so text stays legible when the window is small.
func fs(v: float) -> int:
	return int(round(v * maxf(ui_scale, 0.82)))


func mono(weight: int = 500) -> Font:
	return Look.mono(weight)


func sep() -> Dictionary:
	return world.get("separation", {"lateral_nm": 3.0, "vertical_ft": 1000.0})
