extends CanvasLayer
## 菜单：右上角一颗小按钮（河畔里在「对门」那张牌底下），点开是一张从右边滑进来的纸。
## 手机的返回键、电脑上的 Esc 也能开、能关。
##
## 河畔里，左边压暗的那一半是「这会儿」：两个圆（亲近越多叠得越多）、两个人的名字、几岁几点；
## 右边那张纸：三条音量（音乐 / 街上的声音 / 动静）、这一世（成长账、下一道关），
## 最底下「接着过」，和回大厅、回标题、退出。
##
## 钟不会自己走（docs/GDD.md 一天的循环：你不点，这一段就等着你），所以这里不叫「暂停」，叫「歇一会儿」。
## 原来右上角那颗三档的「乐 / 响 / 静」按钮由它取代；老设置在 audio_director._load_settings 里换算。

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const Icons := preload("res://scripts/ui/icons.gd")

const LAYER := 8                 ## 界面（1）、开局纸条（4）、搭伴小游戏（5）上面，转场（50）下面
const BUTTON_SIZE := Vector2(88, 60)
const BUTTON_TOP_MENU := 28.0
const BUTTON_TOP_WORLD := 204.0  ## hud.gd right_slot_top()：对门那张牌底下
const SHEET_W := 720.0
const SHEET_MARGIN := 32.0       ## 那张纸离屏幕上下、右边
const ROW_H := 80.0              ## 一条音量的高：手指按得住
## 三条音量：总线、名字、底下一行小字
const VOLUMES := [
	["Music", "音乐", "配乐"],
	["Ambience", "街上", "叫卖、车、雨"],
	["Sfx", "动静", "按键、脚步"],
]

var main: Node                   ## scripts/main.gd
var button: Button
var _dim: Control
var _info: Control               ## 左边：两个圆、名字、几岁几点
var _sheet: PanelContainer
var _body: VBoxContainer
var _open := false
var _tween: Tween
var _quit_armed := false
var _toggled_at := -1.0          ## 返回键在有的手机上会同时来一个按键和一个通知：0.25 秒里只认一回
var _boxes: Array[StyleBox] = []
var _tint := Color.TRANSPARENT
var _themed := false


func _ready() -> void:
	layer = LAYER
	_make_button()
	_dim = _Dim.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	_dim.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_dim)
	_info = _Info.new()
	_info.visible = false
	add_child(_info)
	_sheet = Kit.card(Kit.accent, 44.0, true, 12.0)
	_sheet.anchor_left = 1.0
	_sheet.anchor_right = 1.0
	_sheet.anchor_bottom = 1.0
	_sheet.visible = false
	add_child(_sheet)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", P.SP_S)
	_sheet.add_child(_body)


func is_open() -> bool:
	return _open


func toggle() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _toggled_at < 0.25:
		return
	_toggled_at = now
	if _open:
		close()
	else:
		open()


# ---------------------------------------------------------------- 按钮 ----

func _make_button() -> void:
	button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "菜单（Esc）"
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.pressed.connect(toggle)
	add_child(button)
	var g := Icons.Glyph.new("menu", 46.0)
	g.anchor_left = 0.5
	g.anchor_right = 0.5
	g.anchor_top = 0.5
	g.anchor_bottom = 0.5
	g.offset_left = -23
	g.offset_right = 23
	g.offset_top = -23
	g.offset_bottom = 23
	button.add_child(g)
	button.set_meta("glyph", g)


## 按钮用主界面的主题（孔版框），框的留白收小一点；错开的色块是玩家自己的颜色
func _style_button() -> void:
	var ui: Control = main.get("ui") if main != null else null
	if not _themed and ui != null and ui.theme != null:
		_themed = true
		for st in ["normal", "hover", "pressed"]:
			if not ui.theme.has_stylebox(st, "Button"):
				continue
			var sb: StyleBox = ui.theme.get_stylebox(st, "Button").duplicate()
			sb.content_margin_left = 12
			sb.content_margin_right = 12
			sb.content_margin_top = 8
			sb.content_margin_bottom = 8
			button.add_theme_stylebox_override(st, sb)
			_boxes.append(sb)
	if Kit.accent != _tint:
		_tint = Kit.accent
		for sb in _boxes:
			if "block" in sb:
				sb.block = _tint
				sb.emit_changed()
		var g: Variant = button.get_meta("glyph")
		if g is Control:
			g.color = Color(_tint, 0.9)
			g.queue_redraw()


func _in_world() -> bool:
	if main == null:
		return false
	var world: Variant = main.get("world")
	var screen: Control = main.get("screen")
	return world != null and is_instance_valid(world) and (screen == null or not screen.visible)


func _process(_delta: float) -> void:
	if main == null:
		return
	_style_button()
	var modal: Control = main.get("modal")
	var page := str(main.get("_page_id"))
	# 弹窗（事件、结算）出来的时候让开；人生长卷那一页整屏都是那张纸，也让开；菜单开着就不用它了
	button.visible = not _open and not (modal != null and modal.visible) and page != "scroll"
	var top := BUTTON_TOP_WORLD if _in_world() and main.get("offline_preview") != true else BUTTON_TOP_MENU
	var edge := -32.0 - Kit.safe_sides(button).y  # 刘海在右边时让开（和 HUD 的 SIDE 对齐）
	button.offset_left = edge - BUTTON_SIZE.x
	button.offset_right = edge
	button.offset_top = top
	button.offset_bottom = top + BUTTON_SIZE.y
	if _sheet.visible:
		# 纸的上下边钉在屏幕上：刚建好内容那一帧，自动换行的字还不知道多宽，会把纸撑得老长，之后不会自己缩回来
		_sheet.offset_top = SHEET_MARGIN
		_sheet.offset_bottom = -SHEET_MARGIN


# ---------------------------------------------------------------- 返回键 / Esc ----

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		# 输入框里按 Esc 是不想打字了，不是要菜单
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit and not _open:
			return
		get_viewport().set_input_as_handled()
		toggle()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		toggle()


# ---------------------------------------------------------------- 开 / 关 ----

func open() -> void:
	if main == null or _open:
		return
	_open = true
	_quit_armed = false
	_build()
	var side := Kit.safe_sides(_sheet).y
	_sheet.custom_minimum_size = Vector2(SHEET_W, 0)
	_sheet.offset_left = -SHEET_W - SHEET_MARGIN - side
	_sheet.offset_right = -SHEET_MARGIN - side
	_sheet.offset_top = SHEET_MARGIN
	_sheet.offset_bottom = -SHEET_MARGIN
	_info.anchor_bottom = 1.0
	_info.anchor_right = 1.0
	_info.offset_left = 0
	_info.offset_top = 0
	_info.offset_bottom = 0
	_info.offset_right = _sheet.offset_left - 20.0
	_info.set("inset", Kit.safe_sides(_info).x)
	_fill_info()
	_dim.visible = true
	_info.visible = true
	_sheet.visible = true
	_cue("page")
	# 纸从右边滑进来，落定时稍微歪一下再摆正；左边那一半淡进来
	if _tween != null:
		_tween.kill()
	_dim.modulate.a = 0.0
	_info.modulate.a = 0.0
	_sheet.pivot_offset = Vector2(SHEET_W / 2.0, 0)
	_sheet.position.x += SHEET_W * 0.6
	_sheet.rotation = 0.02
	var to_x := _sheet.position.x - SHEET_W * 0.6
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_dim, "modulate:a", 1.0, P.T_BASE)
	_tween.tween_property(_info, "modulate:a", 1.0, P.T_SLOW).set_delay(0.08)
	_tween.tween_property(_sheet, "position:x", to_x, P.T_SLOW).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_sheet, "rotation", -0.006, P.T_SLOW).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not _open:
		return
	_open = false
	_cue("back")
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_dim, "modulate:a", 0.0, P.T_FAST)
	_tween.tween_property(_info, "modulate:a", 0.0, P.T_FAST)
	_tween.tween_property(_sheet, "position:x", _sheet.position.x + SHEET_W * 0.7, P.T_BASE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(_hide_all)


func _hide_all() -> void:
	_dim.visible = false
	_info.visible = false
	_sheet.visible = false
	_sheet.rotation = 0.0


## 关菜单、再做一件事（换页、开弹窗）：不等滑出去的动画，免得纸还挂在新页面上
func _then(f: Callable) -> void:
	_open = false
	if _tween != null:
		_tween.kill()
	_hide_all()
	f.call()


func _audio() -> Node:
	return main.get_node_or_null("Audio") if main != null else null


func _cue(name: String) -> void:
	var a := _audio()
	if a != null and a.has_method("cue"):
		if name == "back":
			a.cue("tap", -2.0, 0.84)
		else:
			a.cue(name)


# ---------------------------------------------------------------- 内容 ----

func _mode() -> String:
	if not _in_world():
		return "page"
	if main.get("offline_preview") == true:
		return "preview"
	var net: Variant = main.get("net")
	return "solo" if net != null and net.has_method("is_local") and net.is_local() else "online"


func _build() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var mode := _mode()
	(_sheet.get_theme_stylebox("panel") as StyleBox).set("block", Kit.accent)
	var ui: Control = main.get("ui")
	_sheet.theme = ui.theme if ui != null else null

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", P.SP_S)
	_body.add_child(head)
	var title := Kit.label(head, "歇一会儿" if mode != "page" else "设置", P.FS_TITLE, P.INK)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var keys := Kit.label(head, "Esc / 返回键", P.FS_CAPTION, P.INK_SOFT, HORIZONTAL_ALIGNMENT_RIGHT)
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Kit.rule(_body, P.INK, P.LINE)

	_section("声音")
	var a := _audio()
	for v in VOLUMES:
		var s := InkSlider.new()
		s.title = v[1]
		s.note = v[2]
		s.value = float(a.volume.get(v[0], 1.0)) if a != null and "volume" in a else 1.0
		s.custom_minimum_size = Vector2(0, ROW_H)
		var bus: String = v[0]
		s.changed.connect(func(val: float, done: bool):
			var au := _audio()
			if au != null and au.has_method("set_volume"):
				au.set_volume(bus, val, done)
			if done and bus != "Music":
				_cue_at(bus))
		_body.add_child(s)

	if mode == "online" or mode == "solo":
		Kit.gap(_body, P.SP_XS)
		_section("这一世")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", P.SP_M)
		_body.add_child(row)
		for pair in [["成长账", "_show_growth"], ["下一道关", "_show_goal_detail"]]:
			var fn: String = pair[1]
			var b := Kit.button(row, pair[0], func(): _then(func(): main.call(fn)))
			Kit.make_option(b)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(fill)

	var go := Button.new()
	go.text = "接着过" if mode != "page" else "回去"
	go.focus_mode = Control.FOCUS_NONE
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(close)
	Kit.make_primary(go)
	_body.add_child(go)

	var leave := HBoxContainer.new()
	leave.alignment = BoxContainer.ALIGNMENT_CENTER
	leave.add_theme_constant_override("separation", P.SP_L)
	_body.add_child(leave)
	if mode == "online" or mode == "solo":
		_quiet(leave, "回大厅", func(): _then(main.leave_to_lobby))
	if mode != "page" or str(main.get("_page_id")) != "title":
		_quiet(leave, "回标题", func(): _then(main._show_title))
	if not OS.has_feature("web"):
		var q := _quiet(leave, "退出游戏", Callable())
		q.pressed.connect(func():
			if _quit_armed:
				main.get_tree().quit()
				return
			_quit_armed = true
			q.text = "再点一下退出"
			q.add_theme_color_override("font_color", P.MEI))
	if mode == "online":
		Kit.label(_body, "离开以后，影子替你照常过；回大厅点这条人生线就接上", P.FS_CAPTION, P.INK_MID, HORIZONTAL_ALIGNMENT_CENTER)
	elif mode == "solo":
		Kit.label(_body, "存档在这个浏览器里；回大厅点这条人生线就接上", P.FS_CAPTION, P.INK_MID, HORIZONTAL_ALIGNMENT_CENTER)


func _section(text: String) -> void:
	Kit.label(_body, text, P.FS_LABEL, P.INK_MID)


func _quiet(parent: Container, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	Kit.make_quiet(b)
	b.add_theme_font_size_override("font_size", P.FS_LABEL + 2)
	b.set_meta("sfx", "back")
	if on_press.is_valid():
		b.pressed.connect(on_press)
	parent.add_child(b)
	return b


## 松手时放一声那条总线上的声音，听听现在多响
func _cue_at(bus: String) -> void:
	var a := _audio()
	if a == null:
		return
	if bus == "Sfx":
		a.cue("tap")
	elif bus == "Ambience":
		a.cue("toast")


func _fill_info() -> void:
	var mode := _mode()
	var d := {}
	if mode == "page":
		pass  # 标题、大厅这些页自己有标志和字，左边只压暗，不再叠一套
	else:
		var names: Dictionary = main.get("names")
		var me := str(main.get("my_role"))
		var other := "mei" if me == "qing" else "qing"
		var hud: Variant = main.get("hud")
		var when := str(hud.time_label) if hud != null else ""
		var minute := float(hud.minute) if hud != null else 390.0
		var bond: Dictionary = hud.bond if hud != null else {}
		var near := clampf(float(bond.get("close", 0)) / 100.0, 0.0, 1.0)
		d = {
			"title": "%s · %s" % [str(names.get(me, P.ROLE_NAME.get(me, ""))), str(names.get(other, P.ROLE_NAME.get(other, "")))],
			"line": ("%s · %s" % [when, P.clock(minute)]) if when != "" else P.clock(minute),
			"bond": ("亲近 %d · 默契 %d" % [int(bond.get("close", 0)), int(bond.get("sync", 0))]) if not bond.is_empty() else "",
			"note": "钟不会自己走：你不点，这一段就一直等着你。" if mode != "preview" else "这会儿没联网，只是在河畔里逛逛。",
			# 亲近越多，两个圆叠得越多（和 HUD 对门那张牌上的两个圆一个意思）
			"gap": lerpf(1.7, 0.55, near),
			"me": me,
		}
	_info.set("data", d)
	_info.queue_redraw()


# ---------------------------------------------------------------- 画 ----

## 压暗：一层墨，上面一层很淡的网点（和转场「印出来」的网点一个意思）。网点在 shaders/menu_dim.gdshader 里算
class _Dim extends ColorRect:
	const P := preload("res://scripts/ui/palette.gd")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		color = Color(P.INK, 0.8)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/menu_dim.gdshader")
		mat.set_shader_parameter("ink", Color(P.INK, 0.8))
		mat.set_shader_parameter("dot_color", Color(P.OVERLAP, 0.55))
		material = mat
		resized.connect(_fit_cell)

	## 网点大小跟着真实分辨率走，手机和电脑上看起来一样大（同 fx.gd _start）
	func _fit_cell() -> void:
		if not is_inside_tree():
			return
		var vis := get_viewport().get_visible_rect().size
		var ratio := float(get_window().size.x) / maxf(1.0, vis.x)
		(material as ShaderMaterial).set_shader_parameter("cell", maxf(10.0, 22.0 * vis.y / 1080.0 * ratio))


## 左边那一半：两个圆、名字、几岁几点、一句话。都印在压暗的墨上，纸色的字
class _Info extends Control:
	const P := preload("res://scripts/ui/palette.gd")
	const Kit := preload("res://scripts/ui/kit.gd")
	var data: Dictionary = {}
	var inset := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if data.is_empty():
			return
		var left := 120.0 + inset
		var w := maxf(size.x - left - 40.0, 200.0)
		var r := 92.0
		var gap := float(data.get("gap", 1.0)) * r
		var cy := size.y * 0.5 - 118.0
		var center := Vector2(left + r + gap / 2.0, cy)
		Kit.draw_pair(self, center, r, gap, 1.0, 3.0)
		# 我是哪个圆：底下一道我的颜色
		if data.has("me"):
			var mine: Vector2 = center + Vector2((-gap / 2.0) if data.me == "qing" else (gap / 2.0), 0)
			draw_line(mine + Vector2(-r * 0.5, r + 22), mine + Vector2(r * 0.5, r + 22), P.PAPER_HI, 4.0, true)
		var y := cy + r + 104.0
		y += _line(left, y, str(data.get("title", "")), P.FS_HERO, P.PAPER_HI, w)
		y += _line(left, y, str(data.get("line", "")), P.FS_H, Color(P.PAPER_HI, 0.86), w)
		if str(data.get("bond", "")) != "":
			y += _line(left, y, str(data.bond), P.FS_LABEL, Color(P.PAPER_HI, 0.66), w)
		if str(data.get("note", "")) != "":
			y += 18.0
			draw_line(Vector2(left, y - 30.0), Vector2(left + 64.0, y - 30.0), Color(P.PAPER_HI, 0.5), 2.0, true)
			_line(left, y, str(data.note), P.FS_LABEL, Color(P.PAPER_HI, 0.7), w)

	func _line(x: float, y: float, s: String, fs: int, color: Color, w: float) -> float:
		if s == "":
			return 0.0
		draw_string(P.font(), Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, w, fs, color)
		return fs * 1.55


## 一条音量：左边名字和一行小字，中间一把尺（十一道刻度，拖过的地方印我的颜色），右边数
class InkSlider extends Control:
	const P := preload("res://scripts/ui/palette.gd")
	const Kit := preload("res://scripts/ui/kit.gd")
	signal changed(value: float, done: bool)
	var title := ""
	var note := ""
	var value := 1.0
	var _drag := false
	const LABEL_W := 196.0
	const VALUE_W := 84.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _track() -> Rect2:
		var x0 := LABEL_W + 16.0
		return Rect2(x0, size.y * 0.5 - 8.0, maxf(size.x - x0 - VALUE_W - 28.0, 40.0), 16.0)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_set_from(mb.position.x, false)
			elif _drag:
				_drag = false
				_set_from(mb.position.x, true)
			accept_event()
		var mm := event as InputEventMouseMotion
		if mm != null and _drag:
			_set_from(mm.position.x, false)
			accept_event()

	func _set_from(x: float, done: bool) -> void:
		var t := _track()
		var v := clampf((x - t.position.x) / t.size.x, 0.0, 1.0)
		v = roundf(v * 20.0) / 20.0  # 五格一档，拖到头一定是 0 和 100
		var moved := not is_equal_approx(v, value)
		value = v
		if moved or done:
			changed.emit(value, done)
		queue_redraw()

	func _draw() -> void:
		var f := P.font()
		var mid := size.y * 0.5
		draw_string(f, Vector2(0, mid - 4.0), title, HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, P.FS_BODY, P.INK)
		draw_string(f, Vector2(0, mid + 30.0), note, HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, P.FS_CAPTION, P.INK_MID)
		var t := _track()
		var y := t.position.y + t.size.y * 0.5
		# 尺：一道细线和十一道刻度，逢五长一点
		draw_line(Vector2(t.position.x, y), Vector2(t.end.x, y), P.HAIR, P.LINE_HAIR, true)
		for i in 11:
			var x := t.position.x + t.size.x * i / 10.0
			var h := 14.0 if i % 5 == 0 else 7.0
			draw_line(Vector2(x, y + 12.0), Vector2(x, y + 12.0 + h), Color(P.INK, 0.35), P.LINE_HAIR, true)
		# 拖过的地方：一条我的颜色（错开一点，像第二块版），上面压一道墨
		var kx := t.position.x + t.size.x * value
		if value > 0.0:
			draw_rect(Rect2(t.position.x + 3.0, y - 6.0 + 3.0, kx - t.position.x, 12.0), Color(Kit.accent, 0.85))
			draw_line(Vector2(t.position.x, y), Vector2(kx, y), P.INK, P.LINE, true)
		# 把手：一张小纸片
		var knob := Rect2(kx - 16.0, y - 24.0, 32.0, 48.0)
		Kit.draw_sheet(self, knob, Kit.accent if value > 0.0 else Color(P.INK_SOFT, 0.4), 4.0)
		draw_line(Vector2(kx, y - 12.0), Vector2(kx, y + 12.0), Color(P.INK, 0.5), P.LINE_HAIR, true)
		# 数：拖到底写「关」
		var s := "关" if value <= 0.0 else str(int(roundf(value * 100.0)))
		var sw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_H).x
		draw_string(f, Vector2(size.x - sw, mid + P.FS_H * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_H, P.INK if value > 0.0 else P.MEI)
