extends SubViewport
## The scope's render target. Holds the drawing layers (map, targets, chrome)
## and renders only when one of them changed: render_target_update_mode is set
## to UPDATE_ONCE on demand, so an idle scope costs nothing per frame.
## Sized in physical pixels to match its on-screen rect (pixel-exact text).

const Ctx := preload("res://scenes/controller/scope/scope_ctx.gd")
const Look := preload("res://scenes/controller/scope/scope_theme.gd")
const ScopeInput := preload("res://scenes/controller/scope/scope_input.gd")
const MapLayer := preload("res://scenes/controller/scope/map_layer.gd")
const TargetLayer := preload("res://scenes/controller/scope/target_layer.gd")
const ChromeLayer := preload("res://scenes/controller/scope/chrome_layer.gd")

signal alerts(kinds: PackedStringArray)

const DEFAULT_RANGE_NM := 37.0
const FLASH_PERIOD_MS := 800
const FLASH_ON_MS := 560
const DECAY_SEC := 1.3

var ctx := Ctx.new()
var input: ScopeInput

var _bg: ColorRect
var _map: MapLayer
var _targets: TargetLayer
var _chrome: ChromeLayer
var _dirty := true
var _last_flash := true
var _last_tick := -1
var _decaying := false


func _ready() -> void:
	disable_3d = true
	transparent_bg = false
	render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	render_target_update_mode = SubViewport.UPDATE_ONCE
	canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	_bg = ColorRect.new()
	_bg.color = Look.BG
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_map = MapLayer.new()
	_targets = TargetLayer.new()
	_chrome = ChromeLayer.new()
	for layer: Control in [_map, _targets, _chrome]:
		layer.set("ctx", ctx)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
	input = ScopeInput.new(ctx)
	input.default_range_nm = DEFAULT_RANGE_NM
	input.view_changed = redraw_all
	input.chrome_changed = func() -> void: _redraw(_chrome)
	ctx.model.changed.connect(func() -> void:
		_redraw(_targets)
		_redraw(_chrome))
	resize_to(Vector2i(size), 1.0)


func set_world(world: Dictionary) -> void:
	ctx.world = world
	redraw_all()


## Match the on-screen rect: `px` physical pixels, `ui_scale` px per canvas unit.
func resize_to(px: Vector2i, ui_scale: float) -> void:
	px = Vector2i(maxi(px.x, 64), maxi(px.y, 64))
	if px == size and is_equal_approx(ui_scale, ctx.ui_scale) and _bg.size == Vector2(px):
		return
	size = px
	ctx.size = Vector2(px)
	ctx.ui_scale = ui_scale
	ctx.dcb_h = round(36.0 * maxf(ui_scale, 0.82))
	ctx.foot_h = round(26.0 * maxf(ui_scale, 0.82))
	for c: Control in [_bg, _map, _targets, _chrome]:
		c.position = Vector2.ZERO
		c.size = Vector2(px)
	var plot := Rect2(0, ctx.dcb_h, px.x, px.y - ctx.dcb_h - ctx.foot_h)
	var was := ctx.xform.plot
	ctx.xform.plot = plot
	if not ctx.xform.user_moved:
		ctx.xform.reset(DEFAULT_RANGE_NM)
	elif was.size.y > 0.0:
		ctx.xform.k *= plot.size.y / was.size.y
	redraw_all()


func ingest(targets: Array) -> void:
	var kinds := ctx.model.ingest(targets, Time.get_ticks_msec())
	_decaying = true
	if not kinds.is_empty():
		alerts.emit(kinds)


func redraw_all() -> void:
	_redraw(_map)
	_redraw(_targets)
	_redraw(_chrome)


func _redraw(c: CanvasItem) -> void:
	if c != null:
		c.queue_redraw()
	_dirty = true


func _process(_delta: float) -> void:
	ctx.now_ms = Time.get_ticks_msec()
	var flash := (ctx.now_ms % FLASH_PERIOD_MS) < FLASH_ON_MS
	if flash != _last_flash:
		_last_flash = flash
		ctx.flash_on = flash
		if ctx.model.has_alert():
			_redraw(_targets)
			_redraw(_chrome)
	if _decaying:
		var age := ctx.model.sweep_age_sec(ctx.now_ms)
		_redraw(_targets)
		if age > DECAY_SEC:
			_decaying = false
	var tick := ctx.now_ms / 250
	if tick != _last_tick:
		_last_tick = tick
		_redraw(_chrome)
		if not ctx.model.landed_ms.is_empty():
			_redraw(_targets)
	if _dirty:
		_dirty = false
		render_target_update_mode = SubViewport.UPDATE_ONCE
