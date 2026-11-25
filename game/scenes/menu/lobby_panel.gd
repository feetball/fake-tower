class_name LobbyPanel
extends Control
## Lobby (phase "lobby"): who is on frequency, the address others should join,
## microphone status with a live meter, Start Round for the host (with the
## reason while it is disabled), Leave, and a short how-to-play.

var _players: VBoxContainer
var _count: Label
var _address_box: VBoxContainer
var _address_head: Label
var _mic_status: Label
var _meter: LevelMeter
var _start: Button
var _reason: Label
var _sig := ""
var _addr_sig := ""
var _poll := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var head := UiKit.hbox(22)
	var title := UiKit.label("FAKE TOWER", &"Title")
	title.add_theme_font_override(&"font", UiTheme.display(200, 14))
	title.add_theme_font_size_override(&"font_size", 46)
	var lobby_tag := UiKit.heading("Lobby")
	lobby_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	head.add_child(lobby_tag)
	head.position = Vector2(150.0, 96.0)
	add_child(head)

	var column := UiKit.vbox(20)
	column.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = 150.0
	column.offset_right = 150.0 + 1160.0
	column.offset_top = 196.0
	column.offset_bottom = -80.0
	add_child(column)

	var grid := UiKit.hbox(44)
	column.add_child(UiKit.panel(&"Glass", grid))

	# --- on frequency
	var left := UiKit.vbox(12)
	left.custom_minimum_size = Vector2(380.0, 0.0)
	left.add_child(UiKit.heading("On frequency"))
	_count = UiKit.label("", &"Small", true)
	left.add_child(_count)
	_players = UiKit.vbox(6)
	left.add_child(_players)
	grid.add_child(left)
	grid.add_child(VSeparator.new())

	# --- connection + audio
	var mid := UiKit.vbox(12)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_head = UiKit.heading("Others join at")
	mid.add_child(_address_head)
	_address_box = UiKit.vbox(4)
	mid.add_child(_address_box)
	mid.add_child(UiKit.spacer(10.0))
	mid.add_child(UiKit.heading("Microphone"))
	_mic_status = UiKit.label("", &"", true)
	mid.add_child(_mic_status)
	_meter = LevelMeter.new()
	_meter.custom_minimum_size = Vector2(300.0, 10.0)
	mid.add_child(_meter)
	mid.add_child(UiKit.label("The lobby is open mic: everyone hears everyone. In the round you only transmit while holding Space.", &"Small", true))
	grid.add_child(mid)
	grid.add_child(VSeparator.new())

	# --- round
	var right := UiKit.vbox(12)
	right.custom_minimum_size = Vector2(250.0, 0.0)
	right.add_child(UiKit.heading("Round"))
	_start = UiKit.button("Start Round", &"Primary", func() -> void: Sess.invoke(&"start_round"))
	right.add_child(_start)
	_reason = UiKit.label("", &"Small", true)
	right.add_child(_reason)
	right.add_child(UiKit.spacer(0.0, true))
	right.add_child(UiKit.button("Leave", &"Danger", func() -> void: Sess.invoke(&"leave")))
	grid.add_child(right)

	var howto := UiKit.vbox(14, [UiKit.heading("How to play"), HowToPlay.build(true)])
	column.add_child(UiKit.panel(&"Glass", howto))

	Sess.connect_signal(&"lobby_changed", refresh)
	Sess.connect_voice_signal(&"status_changed", refresh)
	refresh()


func focus_default() -> void:
	if _start.visible and not _start.disabled:
		_start.grab_focus()


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.5
		refresh()


func refresh() -> void:
	var players := Sess.players()
	var me := Sess.my_id()
	var connected := 0
	var host_name := ""
	for p: Variant in players:
		if p is Dictionary:
			if bool(p.get("connected", true)):
				connected += 1
			if bool(p.get("host", false)):
				host_name = str(p.get("name", ""))
	var sig := JSON.stringify(players) + str(me)
	if sig != _sig:
		_sig = sig
		for c in _players.get_children():
			c.queue_free()
		for p: Variant in players:
			if p is Dictionary:
				_players.add_child(_player_row(p, int(p.get("id", 0)) == me))
	var need := Sess.min_players()
	_count.text = "%d connected · %d needed to start (2 controllers + at least 2 pilots)" % [connected, need]

	var host := Sess.is_host()
	_address_head.text = "OTHERS JOIN AT" if host else "CONNECTED TO"
	var addr_sig := "%s|%s|%s" % [host, host_name, ",".join(local_ipv4_addresses())]
	if addr_sig != _addr_sig:
		_addr_sig = addr_sig
		_fill_addresses(host, host_name)
	_refresh_mic_and_round(host, connected, need, host_name)


func _fill_addresses(host: bool, host_name: String) -> void:
	for c in _address_box.get_children():
		c.queue_free()
	if host:
		var port := int(UiSettings.get_value("host_port", Sess.default_port()))
		var addrs := local_ipv4_addresses()
		if addrs.is_empty():
			_address_box.add_child(UiKit.label("No network address found", &"Dim"))
		for a in addrs:
			var l := UiKit.label("%s : %d" % [a, port], &"MonoLarge")
			_address_box.add_child(l)
		_address_box.add_child(UiKit.label("Same network: use the address above. Over the internet the host must forward UDP port %d." % port, &"Small", true))
	else:
		var a := str(UiSettings.get_value("join_address", ""))
		var l := UiKit.label(a if a != "" else host_name, &"MonoLarge")
		_address_box.add_child(l)
		_address_box.add_child(UiKit.label("Host: %s" % host_name, &"Small"))


func _refresh_mic_and_round(host: bool, connected: int, need: int, host_name: String) -> void:
	if not Sess.has_voice():
		_mic_status.text = "Voice is not available in this build."
		_mic_status.add_theme_color_override(&"font_color", UiTheme.DIM)
	elif Sess.mic_ok():
		_mic_status.text = "Microphone OK — speak to test the meter."
		_mic_status.add_theme_color_override(&"font_color", UiTheme.ACCENT)
	else:
		_mic_status.text = "No microphone — you can listen but not transmit."
		_mic_status.add_theme_color_override(&"font_color", UiTheme.AMBER)

	_start.visible = host
	var enough := connected >= need
	_start.disabled = not (host and enough)
	if host:
		_reason.text = "Roles are assigned at random when you start." if enough \
			else "Waiting for players: %d of %d." % [connected, need]
	else:
		_reason.text = "Waiting for the host (%s) to start the round." % (host_name if host_name != "" else "—")


func _player_row(p: Dictionary, is_me: bool) -> HBoxContainer:
	var online := bool(p.get("connected", true))
	var dot := UiKit.label("●", &"Small")
	dot.add_theme_color_override(&"font_color", UiTheme.ACCENT if online else UiTheme.FAINT)
	dot.tooltip_text = "Connected" if online else "Disconnected"
	dot.mouse_filter = Control.MOUSE_FILTER_PASS
	var nm := UiKit.label(str(p.get("name", "?")), &"")
	if not online:
		nm.add_theme_color_override(&"font_color", UiTheme.FAINT)
	var row := UiKit.hbox(12, [dot, nm])
	if bool(p.get("host", false)):
		row.add_child(_badge("HOST", UiTheme.AMBER))
	if is_me:
		row.add_child(_badge("YOU", UiTheme.BLUE))
	if not online:
		row.add_child(_badge("OFFLINE", UiTheme.RED))
	return row


func _badge(text: String, col: Color) -> PanelContainer:
	var l := UiKit.label(text, &"MonoSmall")
	l.add_theme_font_size_override(&"font_size", 12)
	l.add_theme_color_override(&"font_color", col)
	var p := UiKit.panel(&"Inset", l)
	p.add_theme_stylebox_override(&"panel", UiTheme.flat(Color(col, 0.08), Color(col, 0.5), 1, 2, 7, 2))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


## Local IPv4 addresses others could join, private LAN ranges first.
static func local_ipv4_addresses() -> PackedStringArray:
	var lan := PackedStringArray()
	var other := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") != 3 or ":" in a:
			continue
		if a.begins_with("127.") or a.begins_with("169.254.") or a.begins_with("0."):
			continue
		var parts := a.split(".")
		var b := int(parts[1])
		var is_private := a.begins_with("10.") or a.begins_with("192.168.") \
			or (a.begins_with("172.") and b >= 16 and b <= 31)
		if is_private:
			if not lan.has(a):
				lan.append(a)
		elif not other.has(a):
			other.append(a)
	lan.append_array(other)
	return lan
