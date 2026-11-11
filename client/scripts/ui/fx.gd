extends CanvasLayer
## 转场，盖在所有界面上面。
##   print_in()   新画面像印刷一样从网点里显出来（每次换页、进出河畔里）
##   stage_card() 长大了：一整版墨盖下来，写上年纪，再揭开（这一天也进了新的一章，卡上再多章名和章首那一句）
##   chapter_card() 进了新的一章（没赶上长大的那几章：6 岁、45 岁，还有头一天）

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const SHADER := preload("res://shaders/print_in.gdshader")

var _sheet: ColorRect
var _mat: ShaderMaterial
var _tween: Tween
var _card: VBoxContainer
var _busy_card := false
## 盖卡的时候问一句要不要多写几行：返回 [[字, 字号, 颜色], …]（guide.gd 的 card_lines，进了新的一章就有）
var card_hook: Callable
## 长大的墨卡上要不要放一张阶段成绩单：返回一个 Control 或 null（juice.gd 的 stage_report）。有就放在字的右边，卡多停一会儿，点一下就揭开
var report_hook: Callable
var _hold_tween: Tween
var _report_up := false
signal report_shown  ## 成绩单露出来了（声音跟着响）


func is_busy() -> bool:
	return _busy_card


func _ready() -> void:
	layer = 50
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_sheet = ColorRect.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.material = _mat
	_sheet.visible = false
	_sheet.gui_input.connect(_on_sheet_input)
	add_child(_sheet)
	_card = VBoxContainer.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_theme_constant_override("separation", 24)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	add_child(_card)


## 成绩单那张卡：点一下就揭开（剩下的动画快放）
func _on_sheet_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if tap and _report_up and _tween != null and _tween.is_valid():
		_tween.set_speed_scale(6.0)


func _set_progress(v: float) -> void:
	_mat.set_shader_parameter("progress", v)


func _start(color: Color, from: float) -> void:
	if _tween:
		_tween.kill()
	# 网点大小跟着真实分辨率走，手机和电脑上看起来一样大
	_mat.set_shader_parameter("cell", maxf(14.0, 30.0 * get_viewport().get_visible_rect().size.y / 1080.0 * _pixel_ratio()))
	_mat.set_shader_parameter("ink", color)
	_set_progress(from)
	_sheet.visible = true
	_tween = create_tween()
	_tween.set_speed_scale(1.0)


func _pixel_ratio() -> float:
	var win := get_window()
	return float(win.size.x) / maxf(1.0, get_viewport().get_visible_rect().size.x)


## 新画面已经搭好了：盖一张白纸，再把它"印"出来
func print_in(duration := 0.6, color := P.PAPER) -> void:
	if _busy_card:
		return
	_start(color, 0.0)
	_tween.tween_method(_set_progress, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func(): _sheet.visible = false)


## 长大了。swap 在整版盖住以后调用（换精灵、换年代都放这里）
func stage_card(big: String, small: String, color: Color, swap := Callable()) -> void:
	_busy_card = true
	for c in _card.get_children():
		c.queue_free()
	var specs: Array = [[small, 40, Color(P.PAPER, 0.75)], [big, 150, P.PAPER]]
	var extra: Array = card_hook.call() if card_hook.is_valid() else []
	var report: Variant = report_hook.call() if report_hook.is_valid() else null
	var hold := 1.5 + (1.2 if not extra.is_empty() else 0.0)
	if report is Control:
		hold = maxf(hold, 4.6)
	_show_card(specs + extra, color, swap, hold, report if report is Control else null)


## 进了新的一章：上面一行小字（几岁），然后「第几章」、章名、章首那一句，最底下七个点
## pair：两个圆隔多远（按半径算，0.5 叠得多、2.5 分得最开），这一章两个人大概的远近；less 是底下一行小字（新去处、这一章到哪道关）
## art：第几章（1~7），卡上放这一章的画（res://art/keyart/ch{N}.jpg，tools/art/keyart.py 出的横条）
func chapter_card(num: String, title: String, intro: String, dots: String, small := "", pair := -1.0, less := "", art := 0) -> void:
	_busy_card = true
	var specs: Array = []
	if small != "":
		specs.append([small, 36, Color(P.PAPER, 0.7)])
	if art > 0:
		specs.append(["@art", art, 800.0])
	if pair >= 0.0:
		specs.append(["@pair", pair])
	specs.append([num, 44, Color(P.PAPER, 0.8)])
	specs.append([title, 150, P.PAPER])
	specs.append([intro, 38, Color(P.PAPER, 0.85)])
	if less != "":
		specs.append([less, 28, Color(P.PAPER, 0.6)])
	specs.append([dots, 34, Color(P.PAPER, 0.6)])
	_show_card(specs, P.INK, Callable(), 2.6)


func _show_card(specs: Array, color: Color, swap: Callable, hold: float, report: Control = null) -> void:
	for c in _card.get_children():
		c.queue_free()
	var f := P.font()
	# 有成绩单：字在左、成绩单在右，中间一道竖线
	var into: Container = _card
	if report != null:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 72)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card.add_child(row)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 20)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		var bar := ColorRect.new()
		bar.color = Color(P.PAPER, 0.35)
		bar.custom_minimum_size = Vector2(3, 520)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		row.add_child(report)
		into = col
		var cap := Label.new()
		cap.text = "点一下接着过"
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_override("font", f)
		cap.add_theme_font_size_override("font_size", 24)
		cap.add_theme_color_override("font_color", Color(P.PAPER, 0.45))
		_card.add_child(cap)
		var wide := get_viewport().get_visible_rect().size.x
		# 窄屏上字号收一收，别和成绩单挤
		for spec in specs:
			if spec.size() >= 3 and int(spec[1]) >= 100 and wide < 2100.0:
				spec[1] = 120
	for spec in specs:
		if str(spec[0]) == "@pair":
			var pd := _Pair.new()
			pd.gap = float(spec[1])
			into.add_child(pd)
			continue
		if str(spec[0]) == "@art":
			var tex := chapter_art(int(spec[1]))
			if tex != null:
				var ad := _Art.new()
				ad.tex = tex
				# 有成绩单时字那一栏窄，画也跟着小
				var w := minf(float(spec[2]), 600.0) if report != null else float(spec[2])
				ad.custom_minimum_size = Vector2(w, w * 0.3)
				ad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				into.add_child(ad)
			continue
		var l := Label.new()
		l.text = spec[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", f)
		l.add_theme_font_size_override("font_size", spec[1])
		l.add_theme_color_override("font_color", spec[2])
		if report != null:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 640.0
		into.add_child(l)
	_start(color, 1.0)
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_report_up = report != null
	_tween.tween_method(_set_progress, 1.0, 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(func():
		if swap.is_valid():
			swap.call())
	_tween.tween_property(_card, "modulate:a", 1.0, 0.35)
	if report != null:
		_tween.tween_callback(func(): report_shown.emit())
	_tween.tween_interval(hold)
	_tween.tween_property(_card, "modulate:a", 0.0, 0.3)
	_tween.tween_method(_set_progress, 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(func():
		_sheet.visible = false
		_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_report_up = false
		_busy_card = false)


## 第几章的画（没有就是 null）
static func chapter_art(ch: int) -> Texture2D:
	var path := "res://art/keyart/ch%d.jpg" % ch
	return load(path) if ch > 0 and ResourceLoader.exists(path) else null


## 章首卡上那一章的画：墨底上一张没裁的打样（纸色细框、四角裁切线），画面慢慢横移
class _Art extends Control:
	var tex: Texture2D
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if tex == null:
			return
		var ts := Vector2(tex.get_size())
		# 取 94% 宽的一截，从右往左慢慢挪（人在中间，挪不出画）
		var src_w := ts.x * 0.94
		var src_h := src_w * size.y / size.x
		var k := clampf(_t / 4.0, 0.0, 1.0)
		var src := Rect2((ts.x - src_w) * lerpf(0.8, 0.2, k), (ts.y - src_h) * 0.5, src_w, src_h)
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(r.position + Vector2(8, 8), r.size), Color(P.QING, 0.85))
		draw_texture_rect_region(tex, r, src)
		draw_rect(r, P.PAPER, false, 2.0)
		for corner in [r.position, Vector2(r.end.x, 0), Vector2(0, r.end.y), r.end]:
			var sx := -1.0 if corner.x < 1.0 else 1.0
			var sy := -1.0 if corner.y < 1.0 else 1.0
			draw_line(corner + Vector2(sx * 10, 0), corner + Vector2(sx * 30, 0), Color(P.PAPER, 0.7), 2.0)
			draw_line(corner + Vector2(0, sy * 10), corner + Vector2(0, sy * 30), Color(P.PAPER, 0.7), 2.0)


## 章首卡上的两个圆：这一章两个人隔多远
class _Pair extends Control:
	var gap := 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(240, 90)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := 30.0
		Kit.draw_pair(self, size / 2.0, r, r * gap, 0.95, 0.0)

