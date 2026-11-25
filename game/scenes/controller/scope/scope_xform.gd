extends RefCounted
## World (nm, y north) <-> scope pixels (y down). `plot` is the pixel rect the
## map is fitted into by default (the glass minus the menu bar).

const DEFAULT_CENTER := Vector2(6.0, 0.0)
const MIN_K := 1.5
const MAX_K := 160.0

var center := DEFAULT_CENTER ## world point drawn at the plot centre
var k := 12.0 ## pixels per nm
var plot := Rect2(0, 0, 1000, 800)
var user_moved := false


func to_screen(p: Vector2) -> Vector2:
	var c := plot.get_center()
	return Vector2(c.x + (p.x - center.x) * k, c.y - (p.y - center.y) * k)


func to_world(s: Vector2) -> Vector2:
	var c := plot.get_center()
	return Vector2(center.x + (s.x - c.x) / k, center.y - (s.y - c.y) / k)


func reset(range_nm: float) -> void:
	center = DEFAULT_CENTER
	k = minf(plot.size.x, plot.size.y) * 0.5 / maxf(range_nm, 1.0)
	user_moved = false


func zoom_at(s: Vector2, factor: float) -> void:
	var before := to_world(s)
	k = clampf(k * factor, MIN_K, MAX_K)
	center += before - to_world(s)
	user_moved = true


func pan_pixels(d: Vector2) -> void:
	center += Vector2(-d.x / k, d.y / k)
	user_moved = true


## Displayed range: half the shorter side of the plot, in nm.
func range_nm() -> float:
	return minf(plot.size.x, plot.size.y) * 0.5 / k
