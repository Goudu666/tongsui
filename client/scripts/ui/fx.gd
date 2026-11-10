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
	add_child(_sheet)
	_card = VBoxContainer.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_theme_constant_override("separation", 24)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	add_child(_card)


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
	_show_card(specs + extra, color, swap, 1.5 + (1.2 if not extra.is_empty() else 0.0))


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


func _show_card(specs: Array, color: Color, swap: Callable, hold: float) -> void:
	for c in _card.get_children():
		c.queue_free()
	var f := P.font()
	for spec in specs:
		if str(spec[0]) == "@pair":
			var pd := _Pair.new()
			pd.gap = float(spec[1])
			_card.add_child(pd)
			continue
		var l := Label.new()
		l.text = spec[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", f)
		l.add_theme_font_size_override("font_size", spec[1])
		l.add_theme_color_override("font_color", spec[2])
		_card.add_child(l)
	_start(color, 1.0)
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_tween.tween_method(_set_progress, 1.0, 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(func():
		if swap.is_valid():
			swap.call())
	_tween.tween_property(_card, "modulate:a", 1.0, 0.35)
	_tween.tween_interval(hold)
	_tween.tween_property(_card, "modulate:a", 0.0, 0.3)
	_tween.tween_method(_set_progress, 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(func():
		_sheet.visible = false
		_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_busy_card = false)


## 章首卡上的两个圆：这一章两个人隔多远
class _Pair extends Control:
	var gap := 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(240, 90)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := 30.0
		Kit.draw_pair(self, size / 2.0, r, r * gap, 0.95, 0.0)

