extends Control
## 阶段成绩单：一个人生阶段过完（长大的那张墨卡上），或者点开 HUD 的「成长账」时看的那一张。
##   上面：这一阶段三项各从多少长到多少（灰的是进这一阶段时就有的，彩色是这几年长的；空心圈是 TA 现在在哪）
##   下面：一路过来的长势（三项平均，百分制）：实线是我，细线是 TA；竖线隔开人生阶段，这一阶段垫一层底
##   最底下一行：这一阶段搭伴做了几回事、想到一块儿几回、过了几道关
## 数据来自 juice.gd 记的成长账（每个日子一个点，存在 user://growth/）。on_ink：画在墨卡上（纸色字）还是纸上（墨色字）。

const P := preload("res://scripts/ui/palette.gd")
const KEYS := ["body", "mind", "charm"]
const STAGE_NAME := {"childhood": "童年", "teen": "少年", "young": "青年", "middle": "中年", "old": "老年"}
const ORDER := ["childhood", "teen", "young", "middle", "old"]

var pts: Array = []          ## [[turn, age, stage, 我 b, m, c, TA b, m, c], …]（TA 不在了是 -1）
var stage := "childhood"     ## 讲哪一阶段
var done := true             ## 这一阶段过完了（墨卡上）还是正在过（点开看）
var mine := P.QING
var theirs := P.MEI
var counts: Dictionary = {}  ## { tg 搭伴几回, res 想到一块儿几回, ms 过了几道关 }
var on_ink := true
var _t := 0.0
var _fg := P.PAPER
var _soft := Color(P.PAPER, 0.6)


func setup(p_pts: Array, p_stage: String, p_mine: Color, p_theirs: Color, p_counts: Dictionary, p_on_ink := true, p_done := true, w := 860.0) -> void:
	pts = p_pts
	stage = p_stage
	mine = p_mine
	theirs = p_theirs
	counts = p_counts
	on_ink = p_on_ink
	done = p_done
	_fg = P.PAPER if on_ink else P.INK
	_soft = Color(P.PAPER, 0.62) if on_ink else P.INK_SOFT
	custom_minimum_size = Vector2(w, 560)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 这一阶段有没有东西可讲（成长账里至少有一个点）
static func has_stage(p_pts: Array, p_stage: String) -> bool:
	for p in p_pts:
		if str(p[2]) == p_stage:
			return true
	return false


func _process(delta: float) -> void:
	if _t < 3.0:
		_t += delta
		queue_redraw()


func _ease(a: float, b: float) -> float:
	var x := clampf((_t - a) / maxf(0.001, b - a), 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func _first_last() -> Array:
	var first: Variant = null
	var last: Variant = null
	for p in pts:
		if str(p[2]) != stage:
			continue
		if first == null:
			first = p
		last = p
	return [first, last]


func _draw() -> void:
	var fl := _first_last()
	if fl[0] == null:
		return
	var first: Array = fl[0]
	var last: Array = fl[1]
	var f := P.font()
	var w := size.x
	# 标题
	var title := "%s这些年" % str(STAGE_NAME.get(stage, ""))
	var span := "%d – %d 岁" % [int(first[1]), int(last[1])] if int(first[1]) != int(last[1]) else "%d 岁" % int(first[1])
	draw_string(f, Vector2(0, 40), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, _fg)
	var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(f, Vector2(tw + 18, 40), span + ("" if done else " · 还在过"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, _soft)
	# 三行：从多少到多少
	var bar_x := 110.0
	var bar_w := w - bar_x - 230.0
	for i in KEYS.size():
		var y := 96.0 + i * 64.0
		var a := float(first[3 + i])
		var b := float(last[3 + i])
		var them := float(last[6 + i])
		var k := _ease(0.25 + i * 0.18, 1.15 + i * 0.18)
		draw_string(f, Vector2(0, y + 10), P.STAT_NAME[KEYS[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, _fg)
		var x0 := bar_x
		var xa := bar_x + bar_w * clampf(a / 100.0, 0.0, 1.0)
		var xb := bar_x + bar_w * clampf(lerpf(a, b, k) / 100.0, 0.0, 1.0)
		draw_line(Vector2(x0, y), Vector2(bar_x + bar_w, y), Color(_fg, 0.25), 2.0)
		for tick in 11:
			var tx := bar_x + bar_w * tick / 10.0
			draw_line(Vector2(tx, y - 4), Vector2(tx, y + 4), Color(_fg, 0.22), 1.5)
		draw_line(Vector2(x0, y), Vector2(xa, y), Color(_fg, 0.45), 12.0)
		if xb > xa:
			# 这几年长的：彩色，错开一点像套印
			draw_line(Vector2(xa + 2, y + 3), Vector2(xb + 2, y + 3), Color(P.INK, 0.35), 12.0)
			draw_line(Vector2(xa, y), Vector2(xb, y), mine, 12.0)
		if them >= 0.0:
			var ox := bar_x + bar_w * clampf(them / 100.0, 0.0, 1.0)
			draw_circle(Vector2(ox, y), 9.0, P.INK if on_ink else P.PAPER, true, -1.0, true)
			draw_arc(Vector2(ox, y), 9.0, 0, TAU, 24, theirs, 3.5, true)
		var shown_b := int(round(lerpf(a, b, k)))
		var nums := "%d → %d" % [int(a), shown_b]
		draw_string(f, Vector2(bar_x + bar_w + 24, y + 11), nums, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, _fg)
		var dv := shown_b - int(a)
		if dv != 0:
			var dt := ("+%d" % dv) if dv > 0 else ("−%d" % -dv)
			var dw := f.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			draw_string(f, Vector2(w - dw, y + 12), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, mine if dv > 0 else _soft)
	_curve(f, Rect2(0, 300, w, 190))
	# 最底下一行
	var parts: Array = []
	if int(counts.get("tg", 0)) > 0:
		parts.append("搭伴做了 %d 回事" % int(counts.tg))
	if int(counts.get("res", 0)) > 0:
		parts.append("想到一块儿 %d 回" % int(counts.res))
	if int(counts.get("ms", 0)) > 0:
		parts.append("过了 %d 道关" % int(counts.ms))
	if not parts.is_empty():
		draw_string(f, Vector2(0, 545), "　·　".join(parts), HORIZONTAL_ALIGNMENT_LEFT, w, 26, _soft)


static func avg(p: Array, off: int) -> float:
	if float(p[off]) < 0.0:
		return -1.0
	return (float(p[off]) + float(p[off + 1]) + float(p[off + 2])) / 3.0


## 一路过来的长势：横轴是年纪，竖轴是三项平均
func _curve(f: Font, r: Rect2) -> void:
	if pts.size() < 2:
		return
	var a0 := float(pts[0][1])
	var a1 := maxf(a0 + 1.0, float(pts[-1][1]))
	var lo := 100.0
	var hi := 0.0
	for p in pts:
		for off in [3, 6]:
			var v := avg(p, off)
			if v >= 0.0:
				lo = minf(lo, v)
				hi = maxf(hi, v)
	lo = maxf(0.0, floor(lo - 3.0))
	hi = minf(100.0, ceil(hi + 3.0))
	var plot := Rect2(r.position + Vector2(0, 8), r.size - Vector2(0, 40))
	var at := func(age: float, v: float) -> Vector2:
		return Vector2(plot.position.x + (age - a0) / (a1 - a0) * plot.size.x, plot.end.y - (v - lo) / maxf(1.0, hi - lo) * plot.size.y)
	# 这一阶段垫一层底；阶段之间一根竖线，底下写阶段名
	var bounds: Dictionary = {}
	for p in pts:
		var st := str(p[2])
		if not bounds.has(st):
			bounds[st] = [float(p[1]), float(p[1])]
		bounds[st][1] = float(p[1])
	for st in ORDER:
		if not bounds.has(st):
			continue
		var x0: float = at.call(bounds[st][0], lo).x
		var x1: float = at.call(bounds[st][1], lo).x
		if st == stage:
			draw_rect(Rect2(x0, plot.position.y, maxf(4.0, x1 - x0), plot.size.y), Color(_fg, 0.08))
		if x0 > plot.position.x + 1.0:
			draw_dashed_line(Vector2(x0, plot.position.y), Vector2(x0, plot.end.y), Color(_fg, 0.3), 1.5, 6.0)
		var nm: String = STAGE_NAME.get(st, "")
		if x0 > plot.end.x - 50.0:
			continue  # 刚进的这一阶段只有一个点，挤在最右头，不写名字
		draw_string(f, Vector2(x0 + 6, plot.end.y + 30), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, _fg if st == stage else _soft)
	draw_line(Vector2(plot.position.x, plot.end.y), plot.end, Color(_fg, 0.35), 2.0)
	# 线一点点画出来
	var k := _ease(0.6, 1.8)
	for who in [[6, theirs, 3.0], [3, mine, 5.0]]:
		var line := PackedVector2Array()
		for p in pts:
			var v := avg(p, who[0])
			if v < 0.0:
				break
			line.append(at.call(float(p[1]), v))
		if line.size() < 2:
			continue
		var cut := plot.position.x + plot.size.x * k
		var shown := PackedVector2Array()
		for q in line:
			if q.x <= cut:
				shown.append(q)
		if shown.size() >= 2:
			if who[0] == 3:
				var sh := PackedVector2Array()
				for q in shown:
					sh.append(q + Vector2(2, 3))
				draw_polyline(sh, Color(P.INK, 0.35), who[2], true)
			draw_polyline(shown, who[1], who[2], true)
		if k >= 1.0:
			var end: Vector2 = line[-1]
			draw_circle(end, 7.0 if who[0] == 3 else 5.0, who[1], true, -1.0, true)
			var v_end := avg(pts[-1], who[0])
			if v_end >= 0.0:
				var label := str(int(round(v_end)))
				draw_string(f, end + Vector2(12, 30 if who[0] == 3 else -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, who[1])
