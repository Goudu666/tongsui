extends Control
## HUD 左边、四个圆表底下的一条「成长账」：体魄 / 心智 / 魅力，按百分制。
## 做完一件事长了几分，飘字（ui/juice.gd）飞到这一格上，落下来的那一刻数字才往上拨，格子闪一下。
## 点一下打开成长曲线（main.gd → _show_growth）。
##
## 数字只在「有东西飞过来」的时候等一等（hold），别的时候直接追上服务器给的数。
## 每一格底下一道细条是「攒着的」那零点几分（服务器 WORLD 的 fine）：小时候一回只长零点三分，
## 数字不动，细条往前走一截；攒满一分，数字跳一下、细条从头来。

signal pressed

const P := preload("res://scripts/ui/palette.gd")
const KEYS := ["body", "mind", "charm"]
const SIZE := Vector2(320, 52)

var stats: Dictionary = {}      ## 服务器给的属性（0~10），空的不画
var fine: Dictionary = {}       ## 百分制带一位小数（服务器 WORLD 的 fine），有就按它：整数部分和关口纸带一个口径
var _bit: Dictionary = {}       ## key -> 正在显示的「攒着的」那一截（0~1）
var _bit_flash: Dictionary = {} ## key -> 细条亮到多久
var color := P.QING             ## 我的颜色
var _shown: Dictionary = {}     ## 正在显示的分（慢慢追上 stats×10）
var _hold: Dictionary = {}      ## key -> 到这个时刻以前别追（飘字还在路上）
var _flash: Dictionary = {}     ## key -> 闪到多久
var _delta: Dictionary = {}     ## key -> 刚落下来的那一截（+3），在格子上方挂一会儿
var _t := 0.0
var _sig: Array = []


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _gui_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if tap:
		accept_event()
		pressed.emit()


static func points(v: Variant) -> int:
	return int(floor(float(v) * 10.0 + 0.001))


## 这一格在屏幕（界面坐标）上的位置：飘字往这儿飞
func cell_rect(key: String) -> Rect2:
	var i := KEYS.find(key)
	var sz := size if size.x > 0.0 else SIZE
	var w := sz.x / KEYS.size()
	return Rect2(global_position + Vector2(w * maxi(i, 0), 0), Vector2(w, sz.y))


## 有一截正往这一格飞：sec 秒以内先别拨数字
func hold(key: String, sec: float) -> void:
	_hold[key] = maxf(float(_hold.get(key, 0.0)), _t + sec)


## 这一格现在的分（百分制，带小数）
func _value(k: String) -> float:
	if fine.has(k):
		return float(fine[k])
	return float(points(stats.get(k, 0)))


## 零点几分飞到了：细条亮一下往前走，上面挂一个「+0.3」
func land_bit(key: String, amount: float) -> void:
	_hold[key] = 0.0
	_bit_flash[key] = _t + 0.7
	var prev: Array = _delta.get(key, [0, 0.0])
	if float(prev[1]) > _t and float(prev[0]) >= 1.0:
		return  # 刚有整分挂着，别拿小数顶掉
	var sum := amount + (float(prev[0]) if float(prev[1]) > _t else 0.0)
	_delta[key] = [snappedf(sum, 0.1), _t + 1.6]


## 飞到了：数字拨上去，格子闪一下，上面挂一个「+3」
func land(key: String, amount: int) -> void:
	_hold[key] = 0.0
	_flash[key] = _t + 0.55
	var prev: Array = _delta.get(key, [0, 0.0])
	var sum := amount + (int(prev[0]) if float(prev[1]) > _t else 0)
	_delta[key] = [sum, _t + 1.6]


func _process(delta: float) -> void:
	_t += delta
	var moving := false
	for k in KEYS:
		if not stats.has(k):
			continue
		var value := _value(k)
		var target: float = floor(value + 0.001)
		var bit_target := clampf(value - target, 0.0, 1.0)
		if not _shown.has(k):
			_shown[k] = target
			_bit[k] = bit_target
		if _t < float(_hold.get(k, 0.0)):
			moving = true
			continue
		var b := float(_bit.get(k, bit_target))
		if bit_target < b - 0.001:
			b = 0.0 if target > float(_shown[k]) + 0.5 else bit_target  # 攒满了一分：从头来
		if absf(b - bit_target) > 0.002:
			b = move_toward(b, bit_target, delta * 1.6)
			moving = true
		_bit[k] = b
		var cur := float(_shown[k])
		if absf(cur - target) > 0.02:
			# 一格一格往上跳，不是滑过去：像拨算盘
			cur = move_toward(cur, target, maxf(1.0, absf(target - cur) * 6.0) * delta * 4.0)
			moving = true
		else:
			cur = target
		_shown[k] = cur
	for k in _flash:
		if _t < float(_flash[k]):
			moving = true
	for k in _bit_flash:
		if _t < float(_bit_flash[k]):
			moving = true
	for k in _delta:
		if _t < float(_delta[k][1]):
			moving = true
	var sig := [stats.hash(), fine.hash(), color, size]
	if moving or sig != _sig:
		_sig = sig
		queue_redraw()


func _draw() -> void:
	if stats.is_empty():
		return
	var f := P.font()
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(Rect2(r.position + Vector2(5, 5), r.size), Color(P.INK, 0.22))
	draw_rect(r, P.PAPER)
	var w := size.x / KEYS.size()
	for i in KEYS.size():
		var k: String = KEYS[i]
		var cell := Rect2(Vector2(w * i, 0), Vector2(w, size.y))
		var fl := clampf((float(_flash.get(k, 0.0)) - _t) / 0.55, 0.0, 1.0)
		if fl > 0.0:
			draw_rect(cell.grow(-3.0), Color(color, 0.85 * fl))
		if i > 0:
			draw_line(Vector2(w * i, 10), Vector2(w * i, size.y - 10), Color(P.INK, 0.3), 1.5)
		var name: String = P.STAT_NAME[k]
		var num := str(int(round(float(_shown.get(k, 0.0)))))
		var ink := P.PAPER if fl > 0.45 else P.INK
		# 刚长的那一截：顶替名字挂一会儿（「+4  61」），再换回「心智 61」
		var d: Variant = _delta.get(k)
		var fresh: bool = d is Array and _t < float(d[1])
		if fresh:
			var dv := float(d[0])
			var txt := ("+%.1f" % dv) if dv > 0.0 and dv < 1.0 else (("+%d" % int(dv)) if dv >= 0.0 else ("−%d" % -int(dv)))
			var a := clampf((float(d[1]) - _t) / 0.4, 0.0, 1.0)
			var small := dv > 0.0 and dv < 1.0  # 「+0.3」比「+3」长，小一号免得压到右边的数
			draw_string(f, cell.position + Vector2(10 if small else 12, 34 if small else 36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20 if small else 26, Color(P.PAPER if fl > 0.45 else color, a))
		else:
			draw_string(f, cell.position + Vector2(12, 34), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, P.INK_SOFT)
		var nw := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		draw_string(f, cell.position + Vector2(w - nw - 12, 37), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
		# 攒着的那零点几分：贴着格子底边一道细条
		var bw := (w - 20.0) * float(_bit.get(k, 0.0))
		var bf := clampf((float(_bit_flash.get(k, 0.0)) - _t) / 0.7, 0.0, 1.0)
		var by := size.y - 9.0
		draw_line(Vector2(w * i + 10.0, by), Vector2(w * i + w - 10.0, by), Color(P.INK, 0.12), 4.0)
		if bw > 0.5:
			draw_line(Vector2(w * i + 10.0, by), Vector2(w * i + 10.0 + bw, by), Color(color, 0.55 + 0.45 * bf), 4.0 + 2.0 * bf)
	draw_rect(r, P.INK, false, 2.5)
