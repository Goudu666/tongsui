extends CanvasLayer
## 转场，盖在所有界面上面。
##   print_in()   新画面像印刷一样从网点里显出来（每次换页、进出河畔里）
##   stage_card() 长大了：一整版墨盖下来，写上年纪，再揭开

const P := preload("res://scripts/ui/palette.gd")
const SHADER := preload("res://shaders/print_in.gdshader")

var _sheet: ColorRect
var _mat: ShaderMaterial
var _tween: Tween
var _card: VBoxContainer
var _busy_card := false


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
	_mat.set_shader_parameter("cell", maxf(14.0, 30.0 * get_viewport().get_visible_rect().size.x / 1080.0 * _pixel_ratio()))
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
	var f := P.font()
	for spec in [[small, 40, Color(P.PAPER, 0.75)], [big, 150, P.PAPER]]:
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
	_tween.tween_interval(1.5)
	_tween.tween_property(_card, "modulate:a", 0.0, 0.3)
	_tween.tween_method(_set_progress, 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(func():
		_sheet.visible = false
		_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_busy_card = false)
