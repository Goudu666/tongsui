extends CanvasLayer
## 转场，盖在所有界面上面。
##   print_in()   新画面像印刷一样从网点里显出来（每次换页、进出河畔里）
##   stage_card() 长大了：一整版墨盖下来，写上年纪，再揭开（这一天也进了新的一章，卡上再多章名和章首那一句）
##   chapter_card() 进了新的一章（没赶上长大的那几章：6 岁、45 岁，还有头一天）
##   era_cards()    年代大事：一整版墨，上面年代名、大字标题、一段话、落到我头上的那一句；点一下揭开（ui/era.gd 排字）

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
## 年代卡：还没弹的几张（每张是 Era.specs 排好的字），正盖着的那一张，从什么时候起点得掉
var _era_pages: Array = []
var _era_now: Array = []
var _era_up := false
var _era_tap_at := 0.0
const ERA_WIDTH := 1180.0  ## 年代卡上的字最宽这么多（再宽一行太长，读着累）


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
	if tap and _era_up:
		_close_era()
		return
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
func chapter_card(num: String, title: String, intro: String, dots: String, small := "", pair := -1.0, less := "") -> void:
	_busy_card = true
	var specs: Array = []
	if small != "":
		specs.append([small, 36, Color(P.PAPER, 0.7)])
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
	# 年代卡正盖着，长大 / 新一章的卡插进来：年代卡退回去排第一个，这张揭开以后再弹
	if _era_up:
		_era_pages.push_front(_era_now)
		_era_up = false
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
		_busy_card = false
		_next_era())


# ---------------------------------------------------------------- 年代卡 ----

func era_up() -> bool:
	return _era_up


## 弹几张年代卡（pages：每张一组 Era.specs 排好的字），一张一张来，点一下下一张。
## 别的卡正盖着就排在它后面；弹窗（关口揭晓、收工小结）由 main.gd 等它关了才调这里
func era_cards(pages: Array) -> void:
	for pg in pages:
		if pg is Array and not pg.is_empty():
			_era_pages.append(pg)
	if not _busy_card:
		_next_era()


func _next_era() -> void:
	if _era_pages.is_empty():
		return
	_era_now = _era_pages.pop_front()
	_era_up = true
	_busy_card = true
	_report_up = false
	for c in _card.get_children():
		c.queue_free()
	var width := minf(ERA_WIDTH, get_viewport().get_visible_rect().size.x - 160.0)
	var col := era_column(_era_now, width, _era_pages.size())
	_card.add_child(col)
	_card.modulate.a = 0.0
	_start(P.INK, 1.0)
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_era_tap_at = Time.get_ticks_msec() / 1000.0 + 0.6  # 刚盖下来那一下的点击不算（多半是关上一张卡的手还没抬）
	_tween.tween_method(_set_progress, 1.0, 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_card, "modulate:a", 1.0, 0.35)


func _close_era() -> void:
	if Time.get_ticks_msec() / 1000.0 < _era_tap_at:
		return
	_era_up = false
	_start(P.INK, 0.0)
	_tween.tween_property(_card, "modulate:a", 0.0, 0.25)
	_tween.tween_method(_set_progress, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(func():
		_sheet.visible = false
		_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_busy_card = false
		_next_era())


## 年代卡上的一栏字（Era.specs 排好的 [[字, 字号, 颜色], …]，"@rule" 是两件大事中间的一道细线）。
## more：后面还有几张，底下的小字说一声
static func era_column(specs: Array, width: float, more := 0) -> VBoxContainer:
	var f := P.font()
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.custom_minimum_size.x = width
	for spec in specs:
		if str(spec[0]) == "@rule":
			var holder := CenterContainer.new()
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bar := ColorRect.new()
			bar.color = spec[2]
			bar.custom_minimum_size = Vector2(minf(420.0, width * 0.5), 3)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(bar)
			col.add_child(holder)
			continue
		var l := Label.new()
		l.text = spec[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = width
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", f)
		l.add_theme_font_size_override("font_size", spec[1])
		l.add_theme_color_override("font_color", spec[2])
		l.add_theme_constant_override("line_spacing", int(int(spec[1]) * 0.3))
		col.add_child(l)
	var cap := Label.new()
	cap.text = "点一下，还有 %d 张" % more if more > 0 else "点一下接着过"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_theme_font_override("font", f)
	cap.add_theme_font_size_override("font_size", 24)
	cap.add_theme_color_override("font_color", Color(P.PAPER, 0.45))
	col.add_child(Control.new())  # 和正文隔开一点
	col.get_child(-1).custom_minimum_size.y = 24
	col.add_child(cap)
	return col


## 章首卡上的两个圆：这一章两个人隔多远
class _Pair extends Control:
	var gap := 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(240, 90)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := 30.0
		Kit.draw_pair(self, size / 2.0, r, r * gap, 0.95, 0.0)

