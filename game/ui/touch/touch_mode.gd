class_name TouchMode
extends RefCounted
## Whether the touch UI is shown, and the shared touch metrics.
##
## Active when the device has a touchscreen (DisplayServer.is_touchscreen_available())
## or the user arg `--touch` is given (testing / screenshots on a desktop).
## `--no-touch` forces it off. Desktop behaviour is unchanged when inactive.
##
## Touch handling rule used by every touch widget and gesture in the game:
## work from InputEventScreenTouch / InputEventScreenDrag by finger index and
## ignore the mouse events Godot emulates from touch (device ==
## InputEvent.DEVICE_ID_EMULATION). The emulated mouse only follows the first
## finger, so anything built on it breaks as soon as a second finger is down
## (e.g. holding PTT with one thumb). Real mouse events (device 0) are still
## accepted, so `--touch` on a desktop stays clickable.

## Minimum touch target in canvas units: 9 mm on a 6-inch 16:9 phone showing
## the 1920x1080 canvas (1920 px over 133 mm = 14.5 px/mm).
const TARGET_PX := 130.0
## Gap between neighbouring targets and from the screen edge.
const GAP := 10.0
const EDGE := 16.0

static var _active: int = -1 ## -1 = not decided yet


static func active() -> bool:
	if _active < 0:
		var args := OS.get_cmdline_user_args()
		if args.has("--no-touch"):
			_active = 0
		elif args.has("--touch"):
			_active = 1
		else:
			_active = 1 if DisplayServer.is_touchscreen_available() else 0
	return _active == 1


## For tests: force the mode on or off (pass -1 to re-detect).
static func force(on: int) -> void:
	_active = on


## Minimum touch target edge in canvas units: the larger of TARGET_PX and 9 mm
## computed from the screen DPI (capped so a bogus DPI cannot explode layouts).
static func target_px(vp: Viewport = null) -> float:
	var t := TARGET_PX
	var mm := mm_to_canvas(9.0, vp)
	if mm > 0.0:
		t = clampf(maxf(t, mm), TARGET_PX, TARGET_PX * 1.35)
	return t


## Millimetres to canvas units on this screen, or -1 when the DPI is unknown.
static func mm_to_canvas(mm: float, vp: Viewport = null) -> float:
	if DisplayServer.get_name() == "headless":
		return -1.0
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		return -1.0
	var px := mm / 25.4 * float(dpi) # physical pixels
	return px / _canvas_scale(vp)


## Physical pixels per canvas unit.
static func _canvas_scale(vp: Viewport) -> float:
	if vp == null:
		var tree := Engine.get_main_loop() as SceneTree
		vp = tree.root if tree != null else null
	if vp == null:
		return 1.0
	var vis := vp.get_visible_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	if vis.y <= 0.0 or win.y <= 0.0:
		return 1.0
	return win.y / vis.y


## The display's safe area (notches, rounded corners, home indicator) as a
## rect in canvas units of `vp`. The whole visible rect when unknown.
static func safe_rect(vp: Viewport) -> Rect2:
	var vis := vp.get_visible_rect()
	if DisplayServer.get_name() == "headless":
		return vis
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return vis
	var win_pos := Vector2(DisplayServer.window_get_position())
	var win_size := Vector2(DisplayServer.window_get_size())
	if win_size.x <= 0.0 or win_size.y <= 0.0:
		return vis
	# Insets in window pixels, clamped (a desktop window inside the screen has none).
	var left := maxf(0.0, safe.position.x - win_pos.x)
	var top := maxf(0.0, safe.position.y - win_pos.y)
	var right := maxf(0.0, (win_pos.x + win_size.x) - safe.end.x)
	var bottom := maxf(0.0, (win_pos.y + win_size.y) - safe.end.y)
	var k := vis.size / win_size
	var r := Rect2(vis.position + Vector2(left, top) * k,
		vis.size - Vector2(left + right, top + bottom) * k)
	return r if r.size.x > 100.0 and r.size.y > 100.0 else vis


## True for the mouse events Godot synthesises from touch (first finger only).
static func is_emulated(e: InputEvent) -> bool:
	return e is InputEventMouse and e.device == InputEvent.DEVICE_ID_EMULATION


## Raise the minimum height of buttons, text fields and sliders under `root`
## (menus and dialogs) so they are comfortable to hit with a finger.
static func enlarge_targets(root: Node, min_h: float) -> void:
	if root is BaseButton or root is LineEdit or root is HSlider:
		var c := root as Control
		c.custom_minimum_size.y = maxf(c.custom_minimum_size.y, min_h)
	for ch in root.get_children():
		enlarge_targets(ch, min_h)
