extends Control
## 关口揭晓：一个人这一场的分，像拨算盘一样一颗一颗数上去。
##   尺子和纸带上的是同一把（20~100 分，钱按线放），墨线小旗是走的这条路的线
##   数过线的那一下小旗翻成自己的颜色；数完了：够着线的盖一方印（有成绩档就印成绩档），
##   差一点没够上的，停在那条线前面，灰旗子抖两下，写「差 3 分」
##   底下一行小字：这一场的临场发挥，默契替你托住了多少
## 两个人的同时开始数（main.gd 的 _show_milestone_result 一人一把），点一下直接跳到数完。
## 分数口径和服务器 lifePoints 一样（百分制往下取整），线和「差一点」由服务器给（sim.ts → lifeReveal），这里不算。

signal finished(passed: bool)

const P := preload("res://scripts/ui/palette.gd")

var who := ""                 ## 名字（左上）
var color := P.QING
var score := 0
var unit := "分"
var scored := true
var line := -1                ## 走的这条路的线（没有：-1）
var miss: Dictionary = {}     ## { need, have, text } 差一点没够上的那条
var luck := 0                 ## 临场发挥（已经算在 score 里）
var steady := 0               ## 默契托住的（算在 luck 里）
var grade := ""               ## 成绩档（印在章上）
var delay := 0.25
var sound := Callable()       ## func(cue, db, pitch)：main 把声音导演的 cue 递进来
var _t := -1.0
var _dur := 1.2
var _lo := 20.0
var _hi := 100.0
var _last_bead := -1
var _bead_at := -1.0
var _crossed := false
var _done := false
var _skip := false


func _ready() -> void:
	custom_minimum_size = Vector2(custom_minimum_size.x if custom_minimum_size.x > 0.0 else 720.0, 126)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if unit != "分":
		_lo = 0.0
		_hi = maxf(maxf(float(line) * 1.3, float(score) * 1.12), maxf(float(miss.get("need", 0)) * 1.15, 10.0))
	_dur = clampf(0.65 + absf(float(score) - _lo) / 70.0, 0.8, 1.7)
	_t = -delay


func _gui_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if tap and not _done:
		accept_event()
		_skip = true


func passed() -> bool:
	return line >= 0 and score >= line


func _cue(name: String, db := 0.0, pitch := 1.0) -> void:
	if sound.is_valid():
		sound.call(name, db, pitch)


## 数到哪了（0~1）
func _k() -> float:
	var x := clampf(_t / _dur, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 2.6)


func _value() -> float:
	return lerpf(_lo, float(score), _k()) if scored else _lo


func _process(delta: float) -> void:
	if _skip and _t < _dur:
		_t = _dur
	_t += delta
	if _t < 0.0:
		return
	if scored and _t <= _dur + delta:
		var v := _value()
		# 算盘珠：每两分响一颗，越往上音越高
		var step := int(floor(v / (2.0 if unit == "分" else maxf(1.0, (_hi - _lo) / 40.0))))
		if step != _last_bead and _t - _bead_at > 0.035 and not _skip:
			_last_bead = step
			_bead_at = _t
			_cue("bead", -2.0, 0.85 + 0.5 * _k())
		if line >= 0 and not _crossed and v >= float(line):
			_crossed = true
			_cue("gain", -2.0, 1.5)
	if not _done and _t >= _dur:
		_done = true
		_skip = false
		if passed():
			_cue("pass", 0.0)
		elif not miss.is_empty() or (line >= 0 and score < line):
			_cue("miss", -1.0)
		finished.emit(passed())
	if _t < _dur + 1.6:
		queue_redraw()


func _x(v: float, r: Rect2) -> float:
	return r.position.x + clampf((v - _lo) / maxf(1.0, _hi - _lo), 0.0, 1.0) * r.size.x


func _draw() -> void:
	var f := P.font()
	var w := size.x
	var ruler := Rect2(0, 76, w - 300, 0)
	var v := _value() if _t >= 0.0 else _lo
	var since := _t - _dur  # 数完多久了
	# 名字
	if who != "":
		var nw := f.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_rect(Rect2(0, 6, nw + 24, 38), color)
		draw_string(f, Vector2(12, 34), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, P.PAPER)
	# 尺子
	draw_line(ruler.position, ruler.position + Vector2(ruler.size.x, 0), Color(P.INK, 0.3), 2.0)
	for i in 9:
		var tx := ruler.position.x + ruler.size.x * i / 8.0
		draw_line(Vector2(tx, ruler.position.y - 5), Vector2(tx, ruler.position.y + 5), Color(P.INK, 0.28), 1.5)
	var head := _x(v, ruler)
	if scored:
		draw_line(Vector2(ruler.position.x + 2, ruler.position.y + 3), Vector2(head + 2, ruler.position.y + 3), Color(P.INK, 0.3), 12.0)
		draw_line(ruler.position, Vector2(head, ruler.position.y), color, 12.0)
	# 差一点的那条线：灰旗子，数完了抖两下
	if not miss.is_empty() and scored:
		var mx := _x(float(miss.need), ruler)
		var shake := sin(since * 40.0) * 5.0 * clampf(1.0 - since / 0.5, 0.0, 1.0) if since > 0.0 else 0.0
		_flag(Vector2(mx + shake, ruler.position.y), P.INK_SOFT, false)
		if since > 0.0:
			var gap := int(miss.need) - int(miss.have)
			var txt := "差 %d %s" % [gap, unit]
			var a := clampf(since / 0.25, 0.0, 1.0)
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			draw_string(f, Vector2(clampf(mx - tw / 2.0, 0.0, ruler.size.x - tw), ruler.position.y - 34), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(P.MEI, a))
	# 走的这条路的线：墨旗，数过去的那一下翻成自己的颜色
	if line >= 0:
		var lx := _x(float(line), ruler)
		_flag(Vector2(lx, ruler.position.y), color if _crossed else P.INK, _crossed)
	# 数字
	if scored:
		var num := str(int(floor(v + 0.001)))
		var big := 64
		var nw := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
		var ux := w - 170.0
		var pop := 1.0 + 0.18 * clampf(1.0 - since / 0.25, 0.0, 1.0) if since > 0.0 else 1.0
		draw_set_transform(Vector2(ux - nw / 2.0, 92), 0.0, Vector2.ONE * pop)
		draw_string(f, Vector2(-nw / 2.0 + 3, 3), num, HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color(P.INK, 0.35))
		draw_string(f, Vector2(-nw / 2.0, 0), num, HORIZONTAL_ALIGNMENT_LEFT, -1, big, P.INK)
		draw_set_transform(Vector2.ZERO)
		draw_string(f, Vector2(ux + 6, 92), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, P.INK_SOFT)
	# 底下一行：发挥和托底
	if since > 0.1:
		var parts: Array = []
		if luck != 0:
			parts.append("临场 %s%d" % ["+" if luck > 0 else "−", absi(luck)])
		if steady > 0:
			parts.append("默契托住 %d" % steady)
		if not miss.is_empty() and str(miss.get("text", "")) != "":
			parts.append("够不着「%s」" % str(miss.text))
		if not parts.is_empty():
			draw_string(f, Vector2(0, 120), "　·　".join(parts), HORIZONTAL_ALIGNMENT_LEFT, w, 24, Color(P.INK_SOFT, clampf((since - 0.1) / 0.3, 0.0, 1.0)))
	# 印：够着线的盖一方，压在数字上
	if passed() and since > 0.0:
		_seal(f, Vector2(w - 50.0, 66), since)


func _flag(at: Vector2, c: Color, up: bool) -> void:
	var top := at + Vector2(0, -26)
	draw_line(top, at + Vector2(0, 14), c, 3.0)
	var lift := 1.25 if up else 1.0
	draw_colored_polygon(PackedVector2Array([top, top + Vector2(18 * lift, 7 * lift), top + Vector2(0, 14 * lift)]), c)


## 一方印：从大到小砸下来，落定以后墨色微微晕开
func _seal(f: Font, c: Vector2, since: float) -> void:
	var k := clampf(since / 0.14, 0.0, 1.0)
	var s := lerpf(2.4, 1.0, 1.0 - pow(1.0 - k, 3.0))
	var a := clampf(since / 0.08, 0.0, 1.0)
	var txt := grade if grade != "" and grade.length() <= 4 else "过线"
	var side := 84.0
	draw_set_transform(c, -0.2, Vector2.ONE * s)
	var r := Rect2(-side / 2.0, -side / 2.0, side, side)
	draw_rect(r, Color(color, 0.16 * a))
	draw_rect(r, Color(color, 0.92 * a), false, 5.0)
	draw_rect(r.grow(-9.0), Color(color, 0.7 * a), false, 2.0)
	var fs := 32 if txt.length() <= 2 else 22
	if txt.length() <= 2:
		for i in txt.length():
			var ch := txt.substr(i, 1)
			var cw := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(-cw / 2.0, -5 + i * 34), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color, a))
	else:
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(-tw / 2.0, 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color, a))
	draw_set_transform(Vector2.ZERO)
	# 落下的那一下：四周溅几个墨点
	if since < 0.45 and since > 0.1:
		var e := (since - 0.1) / 0.35
		for i in 8:
			var ang := TAU * i / 8.0 + 0.3
			var d := 60.0 + e * 34.0
			draw_circle(c + Vector2(cos(ang), sin(ang)) * d, 5.0 * (1.0 - e), Color(color, 0.8 * (1.0 - e)), true, -1.0, true)
