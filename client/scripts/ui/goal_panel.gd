extends Control
## 下一个人生关口：常驻在河畔里画面上的一条纸带（横屏时在顶上，日历牌和对门的牌之间）。
## 它回答「我今天干这些是为了什么」：下一关是哪个、还有几个日子、离最近的那条线还差多少、对门走到哪了。
##   左边色条：关口的名字和还剩几个日子
##   靠左是我：我的分 / 线，还差多少，和今天的状态（心情、饿、困折出来的效率）
##   中间一把尺：缺口是那条线，实心点是我，空心点是 TA
##   靠右是对门：TA 在同一条线上的分，还差多少；TA 过的是另一关就写那一关
## 点一下展开全部的线（main.gd → _show_goal_detail）。数据来自服务器 WORLD 里的 goals / stats / eff / tracks。

signal pressed

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")

var goal: Variant = null        ## 我的 { id, title, age, turns, lines:[{id,text,by,unit,have,need,ok}] }，没有带线的关口了是 null
var their_goal: Variant = null  ## 对门的。两个人的关口可能不一样（一个辍学了、一个去了外地）
var my_color := P.QING
var their_color := P.MEI
var their_name := "TA"
var eff := 1.0                  ## 现在做事的效率（1.0 上下）
var track := ""                 ## 现在走在哪条路上（上小学 / 机关上班）
var stats: Dictionary = {}      ## 我的属性（0~10），没有关口时显示
var _sig: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()
	elif event is InputEventScreenTouch and event.pressed:
		accept_event()
		pressed.emit()


func _process(_delta: float) -> void:
	var sig := [str(goal), str(their_goal), my_color, eff, track, str(stats), their_name, size]
	if sig != _sig:
		_sig = sig
		queue_redraw()


## 现在最该盯的那条线：还没够着的里面差得最少的；都够着了就是最高的那条
static func target_line(g: Variant) -> Dictionary:
	if not g is Dictionary:
		return {}
	var best: Dictionary = {}
	var best_gap := INF
	for l in g.get("lines", []):
		if bool(l.ok):
			continue
		var gap := (float(l.need) - float(l.have)) / maxf(1.0, float(l.need))
		if gap < best_gap:
			best_gap = gap
			best = l
	if best.is_empty():
		for l in g.get("lines", []):
			if best.is_empty() or float(l.need) > float(best.need):
				best = l
	return best


## 同一条线上对门的数（对门没有这条线返回 -1：TA 过的不是这一关，或者这条路不给 TA 留）
static func their_have(g: Variant, line_id: String) -> float:
	if g is Dictionary:
		for l in g.get("lines", []):
			if str(l.id) == line_id:
				return float(l.have)
	return -1.0


static func turns_text(turns: int) -> String:
	return "就是今天" if turns <= 0 else "还有 %d 个日子" % turns


## 一把尺：从 lo 到 hi，need 处一个缺口，mine 是实心点，theirs 是空心点（< 0 不画）。
## 分数的尺固定 20~100，钱的尺跟着线走，所以同一个关口里几条线的尺可以上下对齐着看。
static func draw_ruler(c: CanvasItem, at: Vector2, width: float, line: Dictionary, theirs: float, mine_color: Color, theirs_color: Color) -> void:
	var need := float(line.get("need", 0))
	var have := float(line.get("have", 0))
	var lo := 20.0
	var hi := 100.0
	if str(line.get("unit", "分")) != "分":
		lo = 0.0
		hi = maxf(maxf(need * 1.35, have * 1.1), maxf(theirs * 1.1, 10.0))
	var x := func(v: float) -> float: return at.x + clampf((v - lo) / (hi - lo), 0.0, 1.0) * width
	# 底线和刻度
	c.draw_line(at, at + Vector2(width, 0), Color(P.INK, 0.35), 2.0)
	var step := (hi - lo) / 8.0
	for i in 9:
		var tx: float = x.call(lo + step * i)
		c.draw_line(Vector2(tx, at.y - 4), Vector2(tx, at.y + 4), Color(P.INK, 0.3), 1.5)
	# 我已经走到的地方：一段实色
	var mx: float = x.call(have)
	c.draw_line(at + Vector2(0, 0), Vector2(mx, at.y), mine_color, 7.0)
	# 那条线：一根墨线，顶上一面小旗
	if need > 0.0:
		var nx: float = x.call(need)
		c.draw_line(Vector2(nx, at.y - 20), Vector2(nx, at.y + 12), P.INK, 3.0)
		c.draw_colored_polygon(PackedVector2Array([Vector2(nx, at.y - 20), Vector2(nx + 14, at.y - 14), Vector2(nx, at.y - 8)]), P.INK)
	# 对门：空心点，画在我的下面一层
	if theirs >= 0.0:
		var ox: float = x.call(theirs)
		c.draw_circle(Vector2(ox, at.y), 9.0, P.PAPER, true, -1.0, true)
		c.draw_arc(Vector2(ox, at.y), 9.0, 0, TAU, 24, theirs_color, 3.5, true)
	# 我：实心点，色版错开一点
	c.draw_circle(Vector2(mx + 2, at.y + 2), 10.0, mine_color, true, -1.0, true)
	c.draw_arc(Vector2(mx, at.y), 10.0, 0, TAU, 24, P.INK, 2.5, true)


func _draw() -> void:
	var f := P.font()
	var r := Rect2(Vector2.ZERO, size)
	# 纸片 + 错位色块，和日历牌一个做法
	draw_rect(Rect2(r.position + Vector2(6, 6), r.size), my_color)
	draw_rect(r, P.PAPER)
	draw_rect(r, P.INK, false, 3.0)
	var band := 232.0
	draw_rect(Rect2(0, 0, band, size.y), my_color)
	draw_line(Vector2(band, 0), Vector2(band, size.y), P.INK, 3.0)
	var line := target_line(goal)
	if line.is_empty():
		# 没有非过不可的关了：写现在走的路和三项属性
		draw_string(f, Vector2(18, 42), track if track != "" else "日子", HORIZONTAL_ALIGNMENT_LEFT, band - 28, 30, P.PAPER)
		draw_string(f, Vector2(18, 76), "照常过", HORIZONTAL_ALIGNMENT_LEFT, band - 28, 22, Color(P.PAPER, 0.85))
		var parts: Array = []
		for k in ["body", "mind", "charm"]:
			if stats.has(k):
				parts.append("%s %d" % [P.STAT_NAME[k], int(floor(float(stats[k]) * 10.0 + 0.001))])
		draw_string(f, Vector2(band + 24, 44), " · ".join(parts), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, P.INK)
		draw_string(f, Vector2(band + 24, 78), "往后没有非过不可的关了。" + _eff_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.INK_SOFT)
		return
	draw_string(f, Vector2(18, 42), str(goal.title), HORIZONTAL_ALIGNMENT_LEFT, band - 28, 32, P.PAPER)
	draw_string(f, Vector2(18, 76), turns_text(int(goal.turns)), HORIZONTAL_ALIGNMENT_LEFT, band - 28, 22, Color(P.PAPER, 0.85))
	var unit := str(line.get("unit", "分"))
	var side := 212.0 if size.x >= 900.0 else 196.0  ## 两头各留给一个人的数
	var x0 := band + 22.0
	var tx := size.x - 38.0 - side
	var both := size.x >= band + side * 2.0 + 170.0  ## 太窄（小屏加刘海）就只写我的，对门只剩尺上的空心点
	if not both:
		tx = size.x - 38.0
	# 靠左：我。实心点 + 我的分 / 线
	draw_circle(Vector2(x0 + 12, 34) + Vector2(2, 2), 9.0, my_color, true, -1.0, true)
	draw_arc(Vector2(x0 + 12, 34), 9.0, 0, TAU, 20, P.INK, 2.5, true)
	_score(f, x0 + 32.0, str(int(line.have)), " / %d %s" % [int(line.need), unit])
	var sub := "够着了" if bool(line.ok) else "还差 %d %s" % [int(ceil(float(line.need) - float(line.have))), unit]
	var eff_text := _eff_text(" · ")
	if f.get_string_size(sub + eff_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x > side - 6.0:
		eff_text = ""  # 放不下就只说还差多少
	draw_string(f, Vector2(x0, 78), sub + eff_text, HORIZONTAL_ALIGNMENT_LEFT, side - 6.0, 20, P.INK_SOFT)
	# 靠右：对门。空心点 + TA 在这条线上的分
	var theirs := their_have(their_goal if _same_gate() else null, str(line.id))
	if both:
		draw_circle(Vector2(tx + 12, 34), 9.0, P.PAPER, true, -1.0, true)
		draw_arc(Vector2(tx + 12, 34), 9.0, 0, TAU, 20, their_color, 3.5, true)
		if theirs >= 0.0:
			_score(f, tx + 32.0, str(int(theirs)), " / %d %s" % [int(line.need), unit])
			var gap := int(ceil(float(line.need) - theirs))
			draw_string(f, Vector2(tx, 78), "%s %s" % [their_name, "够着了" if gap <= 0 else "还差 %d %s" % [gap, unit]], HORIZONTAL_ALIGNMENT_LEFT, side - 6.0, 20, P.INK_SOFT)
		elif their_goal is Dictionary and not _same_gate():
			draw_string(f, Vector2(tx + 32.0, 44), str(their_goal.title), HORIZONTAL_ALIGNMENT_LEFT, side - 38.0, 28, P.INK)
			draw_string(f, Vector2(tx, 78), "%s 过的是另一关" % their_name, HORIZONTAL_ALIGNMENT_LEFT, side - 6.0, 20, P.INK_SOFT)
		else:
			draw_string(f, Vector2(tx + 32.0, 44), "不走这条", HORIZONTAL_ALIGNMENT_LEFT, side - 38.0, 28, P.INK_SOFT)
			draw_string(f, Vector2(tx, 78), their_name, HORIZONTAL_ALIGNMENT_LEFT, side - 6.0, 20, P.INK_SOFT)
	# 中间：哪条线、看什么、一把尺
	var rx := x0 + side + 6.0
	var rw := tx - 22.0 - rx
	var name_text := str(line.text)
	if rw < 230.0:
		# 小屏再加刘海，中间放不下一把尺：只写线的名字，两头的数照样能比
		draw_string(f, Vector2(rx, 44), name_text, HORIZONTAL_ALIGNMENT_LEFT, rw, 26, P.INK)
		draw_string(f, Vector2(rx, 78), "看" + str(line.by), HORIZONTAL_ALIGNMENT_LEFT, rw, 20, P.INK_SOFT)
	else:
		var name_w := minf(f.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x, rw - 96.0)
		draw_string(f, Vector2(rx, 36), name_text, HORIZONTAL_ALIGNMENT_LEFT, name_w, 26, P.INK)
		draw_string(f, Vector2(rx + name_w + 14, 36), "看" + str(line.by), HORIZONTAL_ALIGNMENT_LEFT, rw - name_w - 14.0, 20, P.INK_SOFT)
		draw_ruler(self, Vector2(rx + 6, 68), rw - 12.0, line, their_have(their_goal, str(line.id)), my_color, their_color)
	# 可以点开
	var cx := size.x - 20.0
	var cy := size.y / 2.0
	draw_polyline(PackedVector2Array([Vector2(cx - 6, cy - 12), Vector2(cx + 6, cy), Vector2(cx - 6, cy + 12)]), Color(P.INK, 0.6), 3.0, true)


## 两个人过的是不是同一关
func _same_gate() -> bool:
	return goal is Dictionary and their_goal is Dictionary and str(their_goal.get("id", "")) == str(goal.get("id", ""))


## 「58 / 64 分」：前面的数大，后面的线小
func _score(f: Font, x: float, have_text: String, need_text: String) -> void:
	var hw := f.get_string_size(have_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(f, Vector2(x, 48), have_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, P.INK)
	draw_string(f, Vector2(x + hw, 48), need_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, P.INK_SOFT)


func _eff_text(lead := "") -> String:
	if absf(eff - 1.0) < 0.045:
		return ""
	return "%s状态 ×%.1f" % [lead, eff]
