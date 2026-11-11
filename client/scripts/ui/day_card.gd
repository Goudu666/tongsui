extends RefCounted
## 一天收工的小结卡（服务器 lifeEndDay 的 "day" 条）：今天的时间花在了哪、长了多少、朝下一道关挪了几分、照这样还要几个日子。
## 是「再过一天」的钩子：玩家合上这一页的时候，心里要有一个数（还差 5 分，还剩 3 个日子）。
## 只管摆内容，弹窗、信、按钮由 main.gd 的 _on_log_entries 摆。

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")

const DAY_FROM := 390.0   ## 06:30
const DAY_TO := 1320.0    ## 22:00
const SLOT_EDGES := [480.0, 720.0, 930.0, 1110.0]
const SLOT_NAMES := ["早上", "上午", "下午", "傍晚", "晚上"]


## 往 parent 里摆：今天的一条时间、长了什么、下一道关
## goal_parent：下一道关摆在哪（宽卡右栏）；不给就接着摆在 parent 里
static func build(parent: Container, e: Dictionary, me: String, other: String, names: Dictionary, goal_parent: Container = null) -> void:
	var spent: Dictionary = _d(e.get("spent"))
	var mine: Array = spent.get(me, []) if spent.get(me) is Array else []
	var theirs: Array = spent.get(other, []) if spent.get(other) is Array else []
	if not mine.is_empty() or not theirs.is_empty():
		var strip := DayStrip.new()
		strip.mine = mine
		strip.theirs = theirs
		strip.my_color = P.role_color(me)
		strip.their_color = P.role_color(other)
		strip.their_name = str(names.get(other, "TA"))
		strip.custom_minimum_size = Vector2(0, 150 if not theirs.is_empty() else 112)
		parent.add_child(strip)
		var busy := 0.0
		var tg := 0.0
		for s in mine:
			busy += float(s.t) - float(s.f)
			if bool(s.get("tg", false)):
				tg += float(s.t) - float(s.f)
		var line := "今天花在正经事上 %s" % _hours(busy)
		if tg > 0.0:
			line += "，和 TA 一起 %s" % _hours(tg)
		Kit.label(parent, line + "。", P.FS_LABEL, P.INK_MID)
	var grew := gains_text(_d(_d(e.get("gains")).get(me)))
	Kit.label(parent, ("这一天你长了：" + grew) if grew != "" else "这一天没长什么，日子照样过去。", P.FS_BODY - 2, P.INK)
	var g: Dictionary = _d(_d(e.get("goal")).get(me))
	var gp: Container = goal_parent if goal_parent != null else parent
	if not g.is_empty():
		if goal_parent == null:
			Kit.rule(parent, P.HAIR)
		goal_block(gp, g, P.role_color(me))
	var tg2: Dictionary = _d(_d(e.get("goal")).get(other))
	if not tg2.is_empty():
		Kit.label(gp, "%s：%s" % [str(names.get(other, "TA")), goal_line(tg2)], P.FS_CAPTION, P.INK_MID)


## 下一道关：哪条线、今天从几分挪到几分、还差几分、照这样还要几个日子
static func goal_block(parent: Container, g: Dictionary, color: Color) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	parent.add_child(head)
	Kit.chip(head, str(g.get("title", "")), color, P.FS_LABEL)
	var when := Kit.label(head, countdown(int(g.get("turns", 0))), P.FS_LABEL, P.INK_MID)
	when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar := GoalBar.new()
	bar.have0 = float(g.get("have0", 0))
	bar.have = float(g.get("have", 0))
	bar.need = float(g.get("need", 1))
	bar.unit = str(g.get("unit", "分"))
	bar.label = str(g.get("line", ""))
	bar.color = color
	bar.custom_minimum_size = Vector2(0, 96)
	parent.add_child(bar)
	var crossed: Array = g.get("crossed", []) if g.get("crossed") is Array else []
	if not crossed.is_empty():
		Kit.label(parent, "今天够上了：%s。" % "、".join(crossed), P.FS_BODY - 2, P.OVERLAP)
	Kit.label(parent, pace_text(g), P.FS_LABEL, color.darkened(0.2) if not bool(g.get("ok", false)) else P.INK)


## 照这样还要几个日子，来不来得及。纯文字，单测好测
static func pace_text(g: Dictionary) -> String:
	var turns := int(g.get("turns", 0))
	var short := int(g.get("need", 0)) - int(g.get("have", 0))
	var unit := str(g.get("unit", "分"))
	if bool(g.get("ok", false)):
		return "这条线已经够着了。还想往上够，就看还剩的日子。" if turns > 0 else "这条线够着了。"
	if not g.has("pace"):
		if turns <= 0:
			return "还差 %d %s，明天就是那一天了。" % [short, unit]
		return "还差 %d %s。今天没往上挪，还剩 %d 个日子。" % [short, unit, turns]
	var pace := int(g.pace)
	if pace <= turns:
		return "还差 %d %s。照今天这样，再过 %d 个日子就够上了，来得及。" % [short, unit, pace]
	return "还差 %d %s。照今天这样要 %d 个日子，可只剩 %d 个了，得再加把劲。" % [short, unit, pace, turns]


## TA 那边一行字
static func goal_line(g: Dictionary) -> String:
	var short := int(g.get("need", 0)) - int(g.get("have", 0))
	if bool(g.get("ok", false)):
		return "%s，%s已经够着了" % [str(g.get("title", "")), str(g.get("line", ""))]
	var moved := int(g.get("have", 0)) - int(g.get("have0", 0))
	return "离%s「%s」还差 %d %s%s" % [str(g.get("title", "")), str(g.get("line", "")), short, str(g.get("unit", "分")), ("，今天 +%d" % moved) if moved > 0 else ""]


static func countdown(turns: int) -> String:
	if turns <= 0:
		return "明天就是那一天"
	return "还剩 %d 个日子" % turns


## 一天下来长了多少（百分制，不到 1 分的写「一点」）
static func gains_text(gains: Dictionary) -> String:
	var parts: Array = []
	for k in ["body", "mind", "charm"]:
		var v := float(gains.get(k, 0.0)) * 10.0
		if v >= 0.95:
			parts.append("%s +%d" % [P.STAT_NAME[k], int(round(v))])
		elif v >= 0.15:
			parts.append("%s 一点" % P.STAT_NAME[k])
	return "　".join(parts)


static func _hours(mins: float) -> String:
	var half := int(round(mins / 30.0))
	if half % 2 == 0:
		return "%d 个钟头" % (half / 2)
	return ("%d 个半钟头" % (half / 2)) if half > 1 else "半个钟头"


static func _d(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## 今天的一条时间：06:30 到 22:00，五段的分界画短线，做了事的地方是色块（搭伴是叠印色），上面写做了什么。对门的在底下细一条
class DayStrip extends Control:
	var mine: Array = []
	var theirs: Array = []
	var my_color := P.QING
	var their_color := P.MEI
	var their_name := "TA"

	func _x(m: float) -> float:
		return clampf((m - DAY_FROM) / (DAY_TO - DAY_FROM), 0.0, 1.0) * size.x

	func _draw() -> void:
		var f := P.font()
		var top := 30.0
		var h := 56.0
		draw_rect(Rect2(0, top, size.x, h), Color(P.INK, 0.06))
		for s in mine:
			var r := Rect2(_x(float(s.f)), top, maxf(2.0, _x(float(s.t)) - _x(float(s.f))), h)
			var c: Color = P.OVERLAP if bool(s.get("tg", false)) else my_color
			draw_rect(r, Color(c, 0.85))
			var label := str(s.get("l", ""))
			var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION).x
			if w + 12.0 < r.size.x:
				draw_string(f, Vector2(r.position.x + (r.size.x - w) / 2.0, top + h / 2.0 + 9.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION, P.PAPER_HI)
		for i in SLOT_EDGES.size():
			var x := _x(SLOT_EDGES[i])
			draw_line(Vector2(x, top - 6.0), Vector2(x, top + h + 6.0), Color(P.INK, 0.5), 2.0)
		# 段名写在每一段的中间，上面一行
		var edges: Array = [DAY_FROM] + SLOT_EDGES + [DAY_TO]
		for i in SLOT_NAMES.size():
			var mid := (_x(edges[i]) + _x(edges[i + 1])) / 2.0
			var nw := f.get_string_size(SLOT_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION).x
			draw_string(f, Vector2(mid - nw / 2.0, 22.0), SLOT_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION, P.INK_MID)
		if theirs.is_empty():
			return
		var t2 := top + h + 18.0
		var h2 := 14.0
		draw_rect(Rect2(0, t2, size.x, h2), Color(P.INK, 0.06))
		for s in theirs:
			var c2: Color = P.OVERLAP if bool(s.get("tg", false)) else their_color
			draw_rect(Rect2(_x(float(s.f)), t2, maxf(2.0, _x(float(s.t)) - _x(float(s.f))), h2), Color(c2, 0.7))
		draw_string(f, Vector2(0, t2 + h2 + 26.0), their_name, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION, P.INK_MID)


## 一条线：从今天早上的分到现在的分（今天挪的那一截用实色），线的位置画一道竖杠写着要几分
class GoalBar extends Control:
	var have0 := 0.0
	var have := 0.0
	var need := 1.0
	var unit := "分"
	var label := ""
	var color := P.QING

	func _draw() -> void:
		var f := P.font()
		var top := 40.0
		var h := 26.0
		# 刻度从 0 到线再往上留两成：够着了也看得出多出来多少
		var top_v := maxf(need * 1.2, have * 1.05)
		var xs := func(v: float) -> float: return clampf(v / maxf(top_v, 1.0), 0.0, 1.0) * size.x
		draw_rect(Rect2(0, top, size.x, h), Color(P.INK, 0.07))
		draw_rect(Rect2(0, top, xs.call(have0), h), Color(color, 0.45))
		if have > have0:
			draw_rect(Rect2(xs.call(have0), top, xs.call(have) - xs.call(have0), h), color)
		var lx: float = xs.call(need)
		draw_line(Vector2(lx, top - 8.0), Vector2(lx, top + h + 8.0), P.INK, 3.0)
		var moved := int(have) - int(have0)
		var head := "%s　%d%s%s" % [label, int(have), unit, ("（今天 +%d）" % moved) if moved > 0 else ""]
		draw_string(f, Vector2(0, 28.0), head, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.75, P.FS_LABEL, P.INK)
		var need_s := "线 %d" % int(need)
		var nw := f.get_string_size(need_s, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION).x
		draw_string(f, Vector2(clampf(lx - nw / 2.0, 0.0, size.x - nw), top + h + 30.0), need_s, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION, P.INK_MID)
