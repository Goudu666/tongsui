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
const Icons := preload("res://scripts/ui/icons.gd")

var goal: Variant = null        ## 我的 { id, title, age, turns, lines:[{id,text,by,unit,have,need,ok}] }，没有带线的关口了是 null
var their_goal: Variant = null  ## 对门的。两个人的关口可能不一样（一个辍学了、一个去了外地）
var my_color := P.QING
var their_color := P.MEI
var their_name := "TA"
var eff := 1.0                  ## 现在做事的效率（1.0 上下）
var track := ""                 ## 现在走在哪条路上（上小学 / 机关上班）
var stats: Dictionary = {}      ## 我的属性（0~10），没有关口时显示
var _sig: Array = []
## 「还差几分」跟着动（爽感层，ui/juice.gd）：我的分涨了，先等飘字飞到（LAND 秒），再一格一格拨上去，
## 分数后面挂一个「+3」，那一截纸带闪一下；拨过线的那一下写「够着了」
const LAND := 1.55
var land_in := LAND      ## 这一回等多久（juice.gd 按飘字什么时候落下来设）
var _line_id := ""
var _have := -1.0        ## 正在显示的我的分
var _from := 0.0         ## 这一回从多少开始拨
var _roll_at := 0.0      ## 什么时候开始拨
var _gain := 0           ## 这一回涨了几分
var _t := 0.0


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


func _process(delta: float) -> void:
	_t += delta
	var line := target_line(goal)
	var animating := false
	if line.is_empty():
		_line_id = ""
	else:
		var real := float(line.have)
		if str(line.id) != _line_id or real < _have - 0.01 or _have < 0.0:
			_line_id = str(line.id)
			_have = real  # 换了一条线、掉了分：直接到位
			_gain = 0
		elif real > _have + 0.01 and (_gain == 0 or _t > _roll_at + 2.0):
			_from = _have
			_gain = int(round(real - _have))
			_roll_at = _t + land_in
			land_in = LAND
		if _gain != 0 and _t >= _roll_at and _have < real:
			_have = minf(real, _from + (real - _from) * clampf((_t - _roll_at) / 0.5, 0.0, 1.0))
		animating = _gain != 0 and _t < _roll_at + 1.8
		if not animating and _gain != 0:
			_gain = 0
			_have = real
	var sig := [str(goal), str(their_goal), my_color, eff, track, str(stats), their_name, size]
	if animating or sig != _sig:
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


const BAND_W := 200.0  ## 左边色条：关口名 + 还剩几个日子
const SIDE := 196.0    ## 两头各留给一个人的数


func _draw() -> void:
	var f := P.font()
	var r := Rect2(Vector2.ZERO, size)
	# 一张纸 + 错位色块，和「我」的牌一个做法
	Kit.draw_sheet(self, r, my_color)
	var band := BAND_W
	draw_rect(Rect2(0, 0, band, size.y), my_color)
	draw_line(Vector2(band, 0), Vector2(band, size.y), P.INK, P.LINE, true)
	Kit.ink_frame(self, r)
	var top := size.y / 2.0 - 4.0  ## 第一行字的基线
	var low := size.y - 22.0       ## 第二行
	var line := target_line(goal)
	if line.is_empty():
		# 没有非过不可的关了：写现在走的路和三项属性
		Kit.text(self, Vector2(20, top), track if track != "" else "日子", P.FS_H - 8, P.PAPER_HI, false, band - 32)
		Kit.text(self, Vector2(20, low), "照常过", P.FS_CAPTION, Color(P.PAPER_HI, 0.85), false, band - 32)
		var parts: Array = []
		for k in ["body", "mind", "charm"]:
			if stats.has(k):
				parts.append("%s %d" % [P.STAT_NAME[k], int(floor(float(stats[k]) * 10.0 + 0.001))])
		Kit.text(self, Vector2(band + 26, top), "  ·  ".join(parts), P.FS_LABEL + 2, P.INK)
		Kit.text(self, Vector2(band + 26, low), "往后没有非过不可的关了。" + _eff_text(), P.FS_CAPTION, P.INK_MID, false, size.x - band - 60)
		return
	Kit.text(self, Vector2(20, top), str(goal.title), P.FS_H - 6, P.PAPER_HI, false, band - 32)
	Kit.text(self, Vector2(20, low), turns_text(int(goal.turns)), P.FS_CAPTION, Color(P.PAPER_HI, 0.88), false, band - 32)
	var unit := str(line.get("unit", "分"))
	var side := SIDE
	var x0 := band + 24.0
	var tx := size.x - 44.0 - side
	var both := size.x >= band + side * 2.0 + 170.0  ## 太窄（小屏加刘海）就只写我的，对门只剩尺上的空心点
	if not both:
		tx = size.x - 44.0
	# 靠左：我。实心点 + 我的分 / 线
	var dot_y := top - 14.0
	draw_circle(Vector2(x0 + 10, dot_y) + Vector2(2, 2), 9.0, my_color, true, -1.0, true)
	draw_arc(Vector2(x0 + 10, dot_y), 9.0, 0, TAU, 20, P.INK, 2.5, true)
	var have := _have if _line_id == str(line.id) and _have >= 0.0 else float(line.have)
	var k := clampf((_t - _roll_at) / 1.8, 0.0, 1.0) if _gain != 0 and _t >= _roll_at else (0.0 if _gain != 0 else 1.0)
	if _gain != 0 and _t >= _roll_at and k < 1.0:
		# 涨分的那一下：分数底下垫一块自己的颜色，慢慢淡掉
		draw_rect(Rect2(x0 - 8, 10, side - 4.0, size.y - 20.0), Color(my_color, 0.28 * (1.0 - k)))
	var sw := _score(f, x0 + 28.0, top, str(int(have)), " / %d %s" % [int(line.need), unit])
	if _gain != 0 and _t >= _roll_at and k < 1.0:
		Kit.text(self, Vector2(x0 + 36.0 + sw, top - 16.0 - k * 10.0), "+%d" % _gain, P.FS_LABEL, Color(my_color, 1.0 - k * k))
	var reached := have >= float(line.need) - 0.001
	var sub := "够着了" if reached else "还差 %d %s" % [int(ceil(float(line.need) - have)), unit]
	var eff_text := _eff_text(" · ")
	if f.get_string_size(sub + eff_text, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION).x > side - 6.0:
		eff_text = ""  # 放不下就只说还差多少
	Kit.text(self, Vector2(x0, low), sub + eff_text, P.FS_CAPTION, my_color.darkened(0.25) if not reached else P.INK, false, side - 6.0)
	# 靠右：对门。空心点 + TA 在这条线上的分
	var theirs := their_have(their_goal if _same_gate() else null, str(line.id))
	if both:
		Kit.hair(self, Vector2(tx - 18, 16), Vector2(tx - 18, size.y - 16))
		draw_circle(Vector2(tx + 10, dot_y), 9.0, P.PAPER_HI, true, -1.0, true)
		draw_arc(Vector2(tx + 10, dot_y), 9.0, 0, TAU, 20, their_color, 3.5, true)
		if theirs >= 0.0:
			_score(f, tx + 28.0, top, str(int(theirs)), " / %d %s" % [int(line.need), unit])
			var gap := int(ceil(float(line.need) - theirs))
			Kit.text(self, Vector2(tx, low), "%s %s" % [their_name, "够着了" if gap <= 0 else "还差 %d %s" % [gap, unit]], P.FS_CAPTION, P.INK_MID, false, side - 6.0)
		elif their_goal is Dictionary and not _same_gate():
			Kit.text(self, Vector2(tx + 28.0, top), str(their_goal.title), P.FS_LABEL, P.INK, false, side - 34.0)
			Kit.text(self, Vector2(tx, low), "%s 过的是另一关" % their_name, P.FS_CAPTION, P.INK_MID, false, side - 6.0)
		else:
			Kit.text(self, Vector2(tx + 28.0, top), "不走这条", P.FS_LABEL, P.INK_MID, false, side - 34.0)
			Kit.text(self, Vector2(tx, low), their_name, P.FS_CAPTION, P.INK_MID, false, side - 6.0)
	# 中间：哪条线、看什么、一把尺
	var rx := x0 + side + 6.0
	var rw := tx - 30.0 - rx
	var name_text := str(line.text)
	Kit.hair(self, Vector2(rx - 16, 16), Vector2(rx - 16, size.y - 16))
	if rw < 230.0:
		# 小屏再加刘海，中间放不下一把尺：只写线的名字，两头的数照样能比
		Kit.text(self, Vector2(rx, top), name_text, P.FS_LABEL, P.INK, false, rw)
		Kit.text(self, Vector2(rx, low), "看" + str(line.by), P.FS_CAPTION, P.INK_MID, false, rw)
	else:
		var name_w := minf(f.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_LABEL).x, rw - 90.0)
		Kit.text(self, Vector2(rx, top - 6.0), name_text, P.FS_LABEL, P.INK, false, name_w)
		Kit.text(self, Vector2(rx + name_w + 12, top - 6.0), "看" + str(line.by), P.FS_CAPTION, P.INK_MID, false, rw - name_w - 12.0)
		var shown_line := line.duplicate()
		shown_line["have"] = have
		draw_ruler(self, Vector2(rx + 6, low - 6.0), rw - 12.0, shown_line, their_have(their_goal, str(line.id)), my_color, their_color)
	# 可以点开
	Icons.draw(self, "chevron", Vector2(size.x - 22.0, size.y / 2.0), 22.0, Color(0, 0, 0, 0), P.INK_MID)


## 两个人过的是不是同一关
func _same_gate() -> bool:
	return goal is Dictionary and their_goal is Dictionary and str(their_goal.get("id", "")) == str(goal.get("id", ""))


## 「58 / 64 分」：前面的数大，后面的线小。返回整串的宽
func _score(f: Font, x: float, y: float, have_text: String, need_text: String) -> float:
	var hw := Kit.text(self, Vector2(x, y), have_text, 44, P.INK)
	return hw + Kit.text(self, Vector2(x + hw + 2, y), need_text, P.FS_CAPTION, P.INK_MID)


func _eff_text(lead := "") -> String:
	if absf(eff - 1.0) < 0.045:
		return ""
	return "%s状态 ×%.1f" % [lead, eff]
