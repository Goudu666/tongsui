extends RefCounted
## 界面小部件：主题、按钮、标签、纸卡片，还有到处都用的"两个圆"。
## 所有界面只有四种颜色（纸、墨、青、梅）和一种框（riso_box.gd）。
## accent 是当前玩家自己的颜色：知道自己是青还是梅以后，按钮的色块、HUD 都跟着换。

const P := preload("res://scripts/ui/palette.gd")
const RisoBox := preload("res://scripts/ui/riso_box.gd")

static var accent := P.QING
static var _accent_boxes: Array = []  ## 换 accent 时要跟着变的框（只有主题里那三个，不会涨）


static func set_accent(c: Color) -> void:
	if c == accent:
		return
	accent = c
	for b in _accent_boxes:
		b.block = c
		b.emit_changed()


static func _box(margin_h := 40.0, margin_v := 26.0, offset := 7.0, follow_accent := true) -> StyleBox:
	var b := RisoBox.make(accent, offset)
	b.content_margin_left = margin_h
	b.content_margin_right = margin_h
	b.content_margin_top = margin_v
	b.content_margin_bottom = margin_v
	if follow_accent:
		_accent_boxes.append(b)
	return b


static func theme() -> Theme:
	_accent_boxes.clear()
	var th := Theme.new()
	th.default_font = P.font()
	th.default_font_size = 40
	# 按钮：纸 + 墨框 + 错开的色块；按下去整个压到色块上
	var normal := _box()
	var hover := _box()
	hover.fill = P.PAPER.lerp(Color.WHITE, 0.35)
	var pressed := _box()
	pressed.shift = Vector2(5, 5)
	pressed.fill = P.PAPER_DARK
	var disabled := _box(40.0, 26.0, 7.0, false)
	disabled.ink = P.INK_SOFT
	disabled.block = Color(P.INK_SOFT, 0.25)
	disabled.hatch = true
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		th.set_color(c, "Button", P.INK)
	th.set_color("font_disabled_color", "Button", P.INK_SOFT)
	# 输入框：只有一条底线，像表格里等着填的那一栏
	var edit := StyleBoxFlat.new()
	edit.bg_color = Color(P.PAPER, 0.0)
	edit.border_color = P.INK
	edit.border_width_bottom = 3
	edit.content_margin_left = 8
	edit.content_margin_right = 8
	edit.content_margin_top = 22
	edit.content_margin_bottom = 18
	th.set_stylebox("normal", "LineEdit", edit)
	th.set_stylebox("focus", "LineEdit", edit)
	th.set_color("font_color", "LineEdit", P.INK)
	th.set_color("font_placeholder_color", "LineEdit", P.INK_SOFT)
	th.set_color("caret_color", "LineEdit", accent)
	th.set_color("font_color", "Label", P.INK)
	return th


## 主要按钮：整块墨底，纸色的字
## 这里的框不登记进 _accent_boxes：页面每次都重建，登记了只会越攒越多
static func make_primary(b: Button) -> void:
	var normal := _box(40.0, 26.0, 7.0, false)
	normal.fill = P.INK
	var hover := _box(40.0, 26.0, 7.0, false)
	hover.fill = P.INK.lerp(P.OVERLAP, 0.6)
	var pressed := _box(40.0, 26.0, 7.0, false)
	pressed.fill = P.OVERLAP
	pressed.shift = Vector2(5, 5)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(c, P.PAPER)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER


## 把一个按钮的色块钉成某个颜色，不再跟着 accent 走（大厅里"我是青 / 我是梅"、各条人生线）
static func tint(b: Button, color: Color) -> void:
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBox = b.get_theme_stylebox(st).duplicate()
		sb.block = color
		b.add_theme_stylebox_override(st, sb)


## 次要按钮：没有框，只有一条虚的底线（返回、取消）
static func make_quiet(b: Button) -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_top = 18
	empty.content_margin_bottom = 18
	for s in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(s, empty)
	b.add_theme_font_size_override("font_size", 34)
	for c in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(c, P.INK_SOFT)
	b.add_theme_color_override("font_hover_color", P.INK)
	b.add_theme_color_override("font_pressed_color", P.INK)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER


## 纸卡片（弹窗、抽卡的家庭卡）。block 传透明就没有色块
static func card(block: Color, margin := 48.0, hatch := true, offset := 12.0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := RisoBox.make(block, offset, margin)
	sb.hatch = hatch
	sb.line = 4.0
	sb.overshoot = 10.0
	p.add_theme_stylebox_override("panel", sb)
	return p


static func label(parent: Node, text: String, font_size := 40, color := P.INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", int(font_size * 0.28))
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## 反白的小标签：色底纸字（"默契时刻"、角色名、季节）
static func chip(parent: Node, text: String, bg: Color, font_size := 28) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", P.PAPER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.content_margin_left = font_size * 0.6
	sb.content_margin_right = font_size * 0.6
	sb.content_margin_top = font_size * 0.18
	sb.content_margin_bottom = font_size * 0.22
	l.add_theme_stylebox_override("normal", sb)
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func button(parent: Node, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


static func gap(parent: Node, h := 40) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


## 一条墨线分隔，两头不顶格
static func rule(parent: Node, color := P.INK, width := 2.0) -> Control:
	var r := _Rule.new()
	r.color = color
	r.width = width
	r.custom_minimum_size = Vector2(0, 8)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


class _Rule extends Control:
	var color := Color.BLACK
	var width := 2.0

	func _draw() -> void:
		draw_line(Vector2(0, size.y / 2.0), Vector2(size.x, size.y / 2.0 + 1.0), color, width, true)


# ----------------------------------------------------------------------
# 两个圆：青和梅各一个，叠在一起的地方是第三种颜色。
# 这是整个游戏的标志：标题、默契、共鸣、结局都是它。
# gap 是两个圆心的距离（0 = 完全重合，>= 2r = 分开）
# ----------------------------------------------------------------------

static func draw_pair(c: CanvasItem, center: Vector2, r: float, gap_px: float, alpha := 1.0, outline := 0.0, tilt := 0.0) -> void:
	var half := Vector2(gap_px / 2.0, 0.0).rotated(tilt)
	var a := center - half
	var b := center + half
	c.draw_circle(a, r, Color(P.QING, alpha), true, -1.0, true)
	c.draw_circle(b, r, Color(P.MEI, alpha), true, -1.0, true)
	if gap_px < 2.0 * r - 3.0:
		if gap_px < 1.0:
			c.draw_circle(center, r, Color(P.OVERLAP, alpha), true, -1.0, true)
		else:
			var th := acos(clampf(gap_px / (2.0 * r), 0.0, 1.0))
			var pts := PackedVector2Array()
			var n := 20
			for i in n + 1:
				var ang := -th + 2.0 * th * i / n + tilt
				pts.append(a + Vector2(cos(ang), sin(ang)) * r)
			for i in range(1, n):  # 两头的交点上一段弧已经有了，不能重复
				var ang := PI - th + 2.0 * th * i / n + tilt
				pts.append(b + Vector2(cos(ang), sin(ang)) * r)
			c.draw_colored_polygon(pts, Color(P.OVERLAP, alpha))
	if outline > 0.0:
		# 墨线版故意印歪一点
		var slip := Vector2(-r * 0.045, r * 0.03)
		c.draw_arc(a + slip, r, 0, TAU, 64, Color(P.INK, alpha), outline, true)
		c.draw_arc(b + slip, r, 0, TAU, 64, Color(P.INK, alpha), outline, true)


## 属性：十个圆点，印了几个算几分
class StatDots extends Control:
	const P := preload("res://scripts/ui/palette.gd")
	var stats: Dictionary = {}
	var color := P.QING
	var compact := false

	func _init(p_stats: Dictionary, p_color: Color, p_compact := false) -> void:
		stats = p_stats
		color = p_color
		compact = p_compact
		custom_minimum_size = Vector2(0, 4 * _row())
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _row() -> float:
		return 44.0 if compact else 56.0

	func _draw() -> void:
		var f := P.font()
		var fs := 28 if compact else 34
		var r := 9.0 if compact else 12.0
		var pitch := 30.0 if compact else 40.0
		var y := 0.0
		for k in ["body", "mind", "charm", "luck"]:
			var v := float(stats.get(k, 0))
			var mid := y + _row() / 2.0
			draw_string(f, Vector2(0, mid + fs * 0.36), str(P.STAT_NAME[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, P.INK)
			var x0 := fs * 2.0 + 30.0
			for i in 10:
				var at := Vector2(x0 + i * pitch + r, mid)
				if i < int(v):
					draw_circle(at + Vector2(2, 2), r, color, true, -1.0, true)  # 色版错开一点
					draw_arc(at, r, 0, TAU, 24, P.INK, 2.0, true)
				else:
					draw_arc(at, r, 0, TAU, 24, Color(P.INK_SOFT, 0.7), 1.5, true)
			draw_string(f, Vector2(x0 + 10 * pitch + 14, mid + fs * 0.36), str(int(v)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, P.INK_SOFT)
			y += _row()
