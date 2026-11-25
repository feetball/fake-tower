class_name UiKit
extends RefCounted
## Tiny constructors for code-built UI, so screen scripts stay declarative.


static func label(text: String, variation: StringName = &"", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func heading(text: String) -> Label:
	return label(text.to_upper(), &"Heading")


static func button(text: String, variation: StringName = &"", cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func vbox(sep: int = 10, children: Array = []) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override(&"separation", sep)
	for c: Node in children:
		b.add_child(c)
	return b


static func hbox(sep: int = 10, children: Array = []) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override(&"separation", sep)
	for c: Node in children:
		b.add_child(c)
	return b


static func panel(variation: StringName, child: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.add_child(child)
	return p


static func spacer(h: float = 0.0, expand: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, h)
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hsep() -> HSeparator:
	return HSeparator.new()


static func line_edit(placeholder: String, text: String = "", max_len: int = 0) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.max_length = max_len
	e.caret_blink = true
	e.select_all_on_focus = true
	return e


## A bullet list as wrapped labels ("—" bullets in the dim colour).
static func bullets(lines: Array, variation: StringName = &"Dim") -> VBoxContainer:
	var box := vbox(8)
	for line: String in lines:
		var row := hbox(10)
		var dash := label("—", variation)
		dash.modulate = Color(1, 1, 1, 0.5)
		dash.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var l := label(line, variation, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(dash)
		row.add_child(l)
		box.add_child(row)
	return box


static func is_text_input_focused(vp: Viewport) -> bool:
	var f := vp.gui_get_focus_owner()
	return f is LineEdit or f is TextEdit
