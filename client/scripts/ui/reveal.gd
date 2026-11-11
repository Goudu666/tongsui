extends Control
## 关口揭晓：一个人这一场的分，像拨算盘一样一颗一颗数上去。
##   尺子和纸带上的是同一把（20~100 分，钱按线放），墨线小旗是走的这条路的线
##   数过线的那一下小旗翻成自己的颜色；数完了：够着线的盖一方印（有成绩档就印成绩档），
##   够着名次档的（考进年级前十）再砸一条横章，
##   差一点没够上的，停在那条线前面，灰旗子抖两下，写「差 3 分」
##   底下一行小字：这一场的临场发挥，默契替你托住了多少
##   对门拉了一把的（server/src/pull.ts）：自己的数完，对门颜色的那一截再接上去，接过线才盖印
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
var pull := 0                 ## 对门拉过来的那一截（和 score 同一个口径；钱就是塞过来的块数）
var pull_color := P.MEI
var pull_who := ""
var rank := ""                ## 够着的名次档（关口 grades 里兜底以上那几档：考进年级前十、过了本科线）：数完再砸一条横章
var delay := 0.25
var sound := Callable()       ## func(cue, db, pitch)：main 把声音导演的 cue 递进来
var _t := -1.0
var _dur := 1.2
var _end := 1.2                ## 数完、对门那截也接完
var _lo := 20.0
var _hi := 100.0
var _last_bead := -1
var _bead_at := -1.0
var _crossed := false
var _done := false
var _skip := false
var _rank_hit := false
const RANK_AT := 0.32           ## 数完多久砸名次章（方印先落）
const PULL_DUR := 0.7           ## 对门那一截接上来要多久


func _ready() -> void:
	custom_minimum_size = Vector2(custom_minimum_size.x if custom_minimum_size.x > 0.0 else 720.0, 126)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if unit != "分":
		_lo = 0.0
		_hi = maxf(maxf(float(line) * 1.3, float(score) * 1.12), maxf(float(miss.get("need", 0)) * 1.15, 10.0))
	_dur = clampf(0.65 + absf(float(score) - _lo) / 70.0, 0.8, 1.7)
	_end = _dur + (PULL_DUR if pull > 0 else 0.0)
	_t = -delay


func _gui_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if tap and not _done:
		accept_event()
		_skip = true


func passed() -> bool:
	return line >= 0 and score + pull >= line


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
	if _skip and _t < _end:
		_t = _end
	_t += delta
	if _t < 0.0:
		return
	if scored and _t <= _dur + delta:
		var v := _value()
		# 算盘珠：每两分响一颗，越往上音越高。珠子调在 D6，pitch 按 D 宫五声一级一级上：B D E F# A（停在 5 上，不解决）
		var step := int(floor(v / (2.0 if unit == "分" else maxf(1.0, (_hi - _lo) / 40.0))))
		if step != _last_bead and _t - _bead_at > 0.035 and not _skip:
			_last_bead = step
			_bead_at = _t
			_cue("bead", -2.0, [0.8409, 1.0, 1.1225, 1.2599, 1.4983][mini(int(_k() * 5.0), 4)])
		if line >= 0 and not _crossed and v >= float(line):
			_crossed = true
			_cue("gain", -2.0, 1.5)
	# 对门那一截：自己的数完了，换对门的颜色接上去
	if pull > 0 and _t > _dur and line >= 0 and not _crossed and float(score) + float(pull) * _pull_k() >= float(line) - 0.001:
		_crossed = true
		_cue("gain", -1.0, 1.7)
	if not _done and _t >= _end:
		_done = true
		_skip = false
		if passed():
			_cue("pass", 0.0)
		elif not miss.is_empty() or (line >= 0 and score < line):
			_cue("miss", -1.0)
		finished.emit(passed())
	if rank != "" and not _rank_hit and _t >= _end + RANK_AT:
		_rank_hit = true
		_cue("seal", -1.0, 1.12)
	if _t < _end + 1.6:
		queue_redraw()


## 对门那一截接上来接到哪了（0~1）
func _pull_k() -> float:
	if pull <= 0:
		return 0.0
	var x := clampf((_t - _dur) / PULL_DUR, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func _x(v: float, r: Rect2) -> float:
	return r.position.x + clampf((v - _lo) / maxf(1.0, _hi - _lo), 0.0, 1.0) * r.size.x


func _draw() -> void:
	var f := P.font()
	var w := size.x
	var ruler := Rect2(0, 76, w - 300, 0)
	var v := _value() if _t >= 0.0 else _lo
	var since := _t - _end  # 数完（连对门那截）多久了
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
		# 对门拉的那一截：接在自己的后头，对门的颜色，上面写谁拉的
		var pk := _pull_k()
		if pk > 0.0:
			var px := _x(float(score) + float(pull) * pk, ruler)
			draw_line(Vector2(head, ruler.position.y), Vector2(px, ruler.position.y), pull_color, 12.0)
			var ptxt := "%s%s %d %s" % [pull_who, "垫了" if unit == "块" else "拉了", pull, unit]
			var pw := f.get_string_size(ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
			draw_string(f, Vector2(clampf((head + px) / 2.0 - pw / 2.0, 0.0, ruler.size.x - pw), ruler.position.y + 38), ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(pull_color, clampf(pk * 2.0, 0.0, 1.0)))
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
		if pull > 0 and _t > _dur:
			draw_string(f, Vector2(ux + 6, 58), "+%d" % pull, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(pull_color, clampf((_t - _dur) / 0.3, 0.0, 1.0)))
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
	# 名次章：一条横的，实心，挨着名字（尺子右上头留给「差 3 分」）
	if rank != "" and since > RANK_AT:
		var nx := (f.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 24.0 + 22.0) if who != "" else 0.0
		_rank_stamp(f, Vector2(nx, 25), since - RANK_AT)


func _rank_stamp(f: Font, left_mid: Vector2, since: float) -> void:
	var k := clampf(since / 0.13, 0.0, 1.0)
	var s := lerpf(2.2, 1.0, 1.0 - pow(1.0 - k, 3.0))
	var a := clampf(since / 0.07, 0.0, 1.0)
	var fs := 26
	var tw := f.get_string_size(rank, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Vector2(tw + 34.0, 44.0)
	var c := left_mid + Vector2(box.x / 2.0, 0)
	draw_set_transform(c, 0.05, Vector2.ONE * s)
	var r := Rect2(-box / 2.0, box)
	draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color(P.INK, 0.3 * a))
	draw_rect(r, Color(color, 0.95 * a))
	draw_rect(r.grow(-5.0), Color(P.PAPER, 0.55 * a), false, 1.5)
	draw_string(f, Vector2(-tw / 2.0, 9), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(P.PAPER, a))
	draw_set_transform(Vector2.ZERO)


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
