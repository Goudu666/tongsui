extends Control
## HUD 左边、四个圆表底下的一条「成长账」：体魄 / 心智 / 魅力，按百分制。
## 做完一件事长了几分，飘字（ui/juice.gd）飞到这一格上，落下来的那一刻数字才往上拨，格子闪一下。
## 点一下打开成长曲线（main.gd → _show_growth）。
##
## 数字只在「有东西飞过来」的时候等一等（hold），别的时候直接追上服务器给的数。

signal pressed

const P := preload("res://scripts/ui/palette.gd")
const KEYS := ["body", "mind", "charm"]
const SIZE := Vector2(352, 60)  ## 和 hud.gd 的 ME_W × STATS_H 一样：框是 HUD 那张「我」的牌画的，这里只画字

var stats: Dictionary = {}      ## 服务器给的属性（0~10），空的不画
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
		var target := float(points(stats[k]))
		if not _shown.has(k):
			_shown[k] = target
		if _t < float(_hold.get(k, 0.0)):
			moving = true
			continue
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
	for k in _delta:
		if _t < float(_delta[k][1]):
			moving = true
	var sig := [stats.hash(), color, size]
	if moving or sig != _sig:
		_sig = sig
		queue_redraw()


func _draw() -> void:
	if stats.is_empty():
		return
	var f := P.font()
	var w := size.x / KEYS.size()
	for i in KEYS.size():
		var k: String = KEYS[i]
		var cell := Rect2(Vector2(w * i, 0), Vector2(w, size.y))
		var fl := clampf((float(_flash.get(k, 0.0)) - _t) / 0.55, 0.0, 1.0)
		if fl > 0.0:
			draw_rect(cell.grow(-5.0), Color(color, 0.85 * fl))
		if i > 0:
			draw_line(Vector2(w * i, 14), Vector2(w * i, size.y - 14), P.HAIR, P.LINE_HAIR, true)
		var name: String = P.STAT_NAME[k]
		var num := str(int(round(float(_shown.get(k, 0.0)))))
		var ink := P.PAPER_HI if fl > 0.45 else P.INK
		# 刚长的那一截：顶替名字挂一会儿（「+4  61」），再换回「心智 61」
		var d: Variant = _delta.get(k)
		var fresh: bool = d is Array and _t < float(d[1])
		var mid := size.y / 2.0
		if fresh:
			var txt := ("+%d" % int(d[0])) if int(d[0]) >= 0 else ("−%d" % -int(d[0]))
			var a := clampf((float(d[1]) - _t) / 0.4, 0.0, 1.0)
			draw_string(f, cell.position + Vector2(14, mid + 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_LABEL, Color(P.PAPER_HI if fl > 0.45 else color, a))
		else:
			draw_string(f, cell.position + Vector2(14, mid + 8), name, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION, P.INK_MID if fl <= 0.45 else P.PAPER_HI)
		var nw := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
		draw_string(f, cell.position + Vector2(w - nw - 12, mid + 11), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, ink)
