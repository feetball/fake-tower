class_name MainMenuPanel
extends Control
## Title, tagline, name field and the main menu items, laid out in a column
## on the left over the backdrop. Join opens an inline address/port form.
## On the web, hosting is disabled (browsers cannot accept connections) and the join
## form is open, defaulting to WebSocket.

signal settings_requested
signal how_to_play_requested

const NAME_MAX := 16
const WEB_DEFAULT_PORT := 27271 ## Session.DEFAULT_WS_PORT

var _name: LineEdit
var _join_form: VBoxContainer
var _address: LineEdit
var _port: LineEdit
var _status: Label
var _items: Array[Button] = []
var _web := OS.has_feature("web")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UiKit.vbox(0)
	col.position = Vector2(150.0, 0.0)
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 150.0
	col.offset_right = 150.0 + 620.0
	col.offset_top = 150.0
	col.offset_bottom = -90.0
	add_child(col)

	var title := UiKit.label("FAKE TOWER", &"Title")
	col.add_child(title)
	col.add_child(UiKit.spacer(4.0))
	var tagline := UiKit.label("Two voices claim to be the tower. One is lying.", &"Tagline")
	col.add_child(tagline)
	col.add_child(UiKit.spacer(64.0))

	col.add_child(UiKit.heading("Your name on the frequency"))
	col.add_child(UiKit.spacer(10.0))
	_name = UiKit.line_edit("Name", UiSettings.get_value("name", ""), NAME_MAX)
	_name.custom_minimum_size = Vector2(440.0, 0.0)
	_name.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_name.text_submitted.connect(func(_t: String) -> void: _first_item().grab_focus())
	col.add_child(_name)
	col.add_child(UiKit.spacer(34.0))

	var menu := UiKit.vbox(2)
	# Pull the items left by their hover-rule padding so their text lines up with the title.
	var menu_margin := MarginContainer.new()
	menu_margin.add_theme_constant_override(&"margin_left", -22)
	menu_margin.add_child(menu)
	col.add_child(menu_margin)
	_add_item(menu, "Host Game", _on_host)
	if _web:
		_items[0].disabled = true
		var note := UiKit.label("Browsers can only join games: someone else hosts, or runs a server.", &"Small")
		var note_margin := MarginContainer.new()
		note_margin.add_theme_constant_override(&"margin_left", 24)
		note_margin.add_theme_constant_override(&"margin_bottom", 8)
		note_margin.add_child(note)
		menu.add_child(note_margin)
	_add_item(menu, "Join Game", _toggle_join)
	_join_form = _build_join_form()
	menu.add_child(_join_form)
	if _web:
		_join_form.visible = true
	_add_item(menu, "Solo Practice", _on_solo)
	_add_item(menu, "How to Play", func() -> void: how_to_play_requested.emit())
	_add_item(menu, "Settings", func() -> void: settings_requested.emit())
	_add_item(menu, "Quit", func() -> void: get_tree().quit())

	col.add_child(UiKit.spacer(24.0))
	_status = UiKit.label("", &"Dim", true)
	_status.custom_minimum_size = Vector2(560.0, 0.0)
	col.add_child(_status)

	var footer := UiKit.label("KFTW  ·  FALLOW RIDGE REGIONAL  ·  ILS RWY 27", &"MonoSmall")
	footer.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.offset_right = -60.0
	footer.offset_bottom = -44.0
	footer.modulate = Color(1, 1, 1, 0.55)
	add_child(footer)

	Sess.connect_signal(&"error", _on_session_error)


func focus_default() -> void:
	if _name.text.strip_edges() == "":
		_name.grab_focus()
	elif _web:
		_address.grab_focus()
	else:
		_first_item().grab_focus()


func _first_item() -> Button:
	for b in _items:
		if not b.disabled:
			return b
	return _items[0]


func show_message(msg: String, warn: bool = true) -> void:
	_status.text = msg
	_status.add_theme_color_override(&"font_color", UiTheme.AMBER if warn else UiTheme.DIM)


func open_join_form() -> void:
	_join_form.visible = true


func _add_item(box: VBoxContainer, text: String, cb: Callable) -> void:
	var b := UiKit.button(text, &"MenuItem", cb)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380.0, 0.0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(b)
	_items.append(b)


func _build_join_form() -> VBoxContainer:
	_address = UiKit.line_edit("wss://server or host" if _web else "Host address", UiSettings.get_value("join_address", ""), 128)
	_address.custom_minimum_size = Vector2(270.0, 0.0)
	_address.text_submitted.connect(func(_t: String) -> void: _on_join())
	_port = UiKit.line_edit("Port", str(UiSettings.get_value("join_port", _default_join_port())), 5)
	_port.custom_minimum_size = Vector2(96.0, 0.0)
	_port.text_submitted.connect(func(_t: String) -> void: _on_join())
	var connect_btn := UiKit.button("Connect", &"Primary", _on_join)
	var row := UiKit.hbox(10, [_address, _port, connect_btn])
	var hint := UiKit.label("Ask the host for the address shown in their lobby: host, host:port, or a ws:// / wss:// address (the port box is used when the address has none).", &"Small", true)
	hint.custom_minimum_size = Vector2(520.0, 0.0)
	var form := UiKit.vbox(10, [row, hint])
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 24)
	margin.add_theme_constant_override(&"margin_top", 6)
	margin.add_theme_constant_override(&"margin_bottom", 14)
	margin.add_child(form)
	var wrap := UiKit.vbox(0, [margin])
	wrap.visible = false
	return wrap


func _player_name() -> String:
	var n := _name.text.strip_edges()
	n = " ".join(n.split(" ", false))
	if n == "":
		show_message("Enter your name first.")
		_name.grab_focus()
		return ""
	UiSettings.set_value("name", n)
	return n


func _on_host() -> void:
	var n := _player_name()
	if n == "":
		return
	if Sess.session() == null:
		show_message("Networking is not available in this build.")
		return
	if _web:
		show_message("Browsers can only join games.")
		return
	var port := Sess.default_port()
	UiSettings.set_value("host_port", port)
	show_message("Opening a game on port %d…" % port, false)
	var err: Variant = Sess.invoke(&"host_game", [n, port])
	if err is int and err != OK:
		show_message("Could not host on port %d (%s). Is another game already running?" % [port, error_string(err)])


func _toggle_join() -> void:
	_join_form.visible = not _join_form.visible
	if _join_form.visible:
		_address.grab_focus()


func _on_join() -> void:
	var n := _player_name()
	if n == "":
		return
	var addr := _address.text.strip_edges()
	if addr == "":
		show_message("Enter the host's address.")
		_address.grab_focus()
		return
	var port := int(_port.text) if _port.text.is_valid_int() else _default_join_port()
	if port < 1 or port > 65535:
		show_message("Port must be between 1 and 65535.")
		return
	UiSettings.set_value("join_address", addr)
	UiSettings.set_value("join_port", port)
	if Sess.session() == null:
		show_message("Networking is not available in this build.")
		return
	show_message("Connecting to %s…" % addr, false)
	var err: Variant = Sess.invoke(&"join_game", [n, addr, port])
	if err is int and err != OK:
		# Session has emitted the reason (bad address, unreachable) through `error`.
		if err != ERR_INVALID_PARAMETER and err != ERR_UNAVAILABLE:
			show_message("Could not connect to %s (%s)." % [addr, error_string(err)])
		return
	var target: String = Sess.val(&"server_address", "")
	if target != "":
		show_message("Connecting to %s…" % target, false)


## The port box default: ENet's on desktop/mobile, WebSocket's on the web.
func _default_join_port() -> int:
	return WEB_DEFAULT_PORT if _web else Sess.default_port()


func _on_solo() -> void:
	var n := _name.text.strip_edges()
	if n != "":
		UiSettings.set_value("name", n)
	show_message("Starting solo practice…", false)
	Sess.invoke(&"start_demo", ["pilot_far"])


func _on_session_error(msg: String) -> void:
	if is_visible_in_tree():
		show_message(msg)
