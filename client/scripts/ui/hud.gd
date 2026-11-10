extends Control
## 河畔里的 HUD（横屏）。全部自己画，垫着纸片，压在地图上也看得清。
## 构图是「对门」：我的东西靠左，对门的靠右，中间留给河畔里。
##   左上：日历牌（节气 / 年纪 / 钟点，白天一个太阳，夜里一弯月亮），下面一排四个圆表
##         （饱腹、精力、心情、清洁），低了变梅红并且抖一下；旁边是零花钱
##   中上：下一个关口的纸带（goal_panel.gd，main.gd 按 strip_rect() 摆）；
##         纸带底下，零花钱旁边是主线的一张小签：第几章，今天的「下一件事」在哪张图、哪一段
##   右上：两个圆，越亲近叠得越多；再往右是对门的牌：TA 在哪、在做什么
##   屏幕边上：对门走出画面时，一个 TA 颜色的小箭头指着方向
## 刘海和圆角在左右两边，inset 是要让开的宽度（Kit.safe_sides）。

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const NEED_GLYPH := {"hunger": "饱", "energy": "精", "mood": "心", "clean": "净"}
const STAGE_NAME := {"childhood": "童年", "teen": "少年", "young": "青年", "middle": "中年", "old": "老年"}

const LOW := 30.0          ## 需求低于这个数：圆表变梅红并抖动
const TOP := 40.0          ## 顶上那条横带的上沿
const SIDE := 40.0         ## 离屏幕左右边的距离（再加上 inset）
const CARD := Vector2(320, 156)   ## 日历牌、对门的牌
const BOND_W := 128.0
const GAP := 16.0
const STRIP_H := 96.0      ## 关口纸带的高
const STRIP_MAX := 1280.0  ## 关口纸带最宽这么多（再长尺子就空了）
const CHAPTER_NUM := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

var time_label := ""    ## LifeTime.at().label，例如 "7 岁 · 立夏"
var stage := "childhood"
var minute := 390.0
var slot_name := ""     ## 一天五段里的哪一段（早上 / 上午……）。还没定的时候日历牌上写它，这一段在过的时候写钟点
var playing := false
var tag := ""           ## 日历牌色条上额外的一个词（上学日、预览）
var note := ""          ## 日历牌底下的一行小字（网络延迟）
var needs: Dictionary = {}
var money := -1
var bond: Dictionary = {}
var partner: Dictionary = {}  ## 对门的牌 { name, color, online, big, small }；空的不画（离线逛逛）
var pointer: Dictionary = {}  ## 对门走出画面了 { at: 屏幕上贴边的位置, dir: 方向, color, name }；在画面里是空的
var inset := Vector2.ZERO     ## (左, 右) 给刘海让开的宽度
var story: Dictionary = {}    ## 主线 { chapter, title, next, force }（WORLD 的 story，next 是我这一句）；空的不画
var _shown: Dictionary = {}   ## 圆表上正在显示的值（慢慢追上真实值）
var _t := 0.0
var _idle := 0.0
var _sig: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 只在有东西在动时每帧重画：圆表还在追数、有需求见底在抖、显示的内容变了。
## 其余时候一秒画十次，够两个圆慢慢呼吸。
func _process(delta: float) -> void:
	_t += delta
	_idle += delta
	var moving := false
	for k in needs:
		var target := float(needs[k])
		var cur := float(_shown.get(k, target))
		if absf(cur - target) > 0.05:
			cur = lerpf(cur, target, 1.0 - exp(-6.0 * delta))
			moving = true
		else:
			cur = target
		_shown[k] = cur
		if target < LOW:
			moving = true
	var sig := [time_label, stage, int(minute), slot_name, playing, tag, note, money, bond.hash(), partner.hash(), pointer.hash(), story.hash(), inset, size]
	if moving or _idle >= 0.1 or sig != _sig:
		_sig = sig
		_idle = 0.0
		queue_redraw()


func left() -> float:
	return SIDE + inset.x


func right() -> float:
	return size.x - SIDE - inset.y


## 关口纸带该摆在哪：紧挨日历牌往右铺，到「两个圆」为止
func strip_rect() -> Rect2:
	var x := left() + CARD.x + GAP
	var end := right() - CARD.x - GAP - BOND_W - GAP
	return Rect2(x, TOP, clampf(end - x, 420.0, STRIP_MAX), STRIP_H)


## 右上角那两张牌下面第一个空着的位置（音量按钮放这儿）
func right_slot_top() -> float:
	return TOP + CARD.y + GAP


func _draw() -> void:
	var f := P.font()
	_calendar(f, Vector2(left(), TOP))
	if not needs.is_empty():
		var i := 0
		for k in ["hunger", "energy", "mood", "clean"]:
			_gauge(f, Vector2(left() + 36.0 + i * 82.0, TOP + CARD.y + GAP + 34.0), k)
			i += 1
		_bond(f, Vector2(right() - CARD.x - GAP - BOND_W, TOP))
	var x := left() + CARD.x + GAP
	var y := TOP + STRIP_H + 14.0
	if money >= 0:
		x += _money(f, Vector2(x, y)) + 12.0
	if not story.is_empty():
		x += _story(f, Vector2(x, y)) + 12.0
	if note != "":
		var nw := f.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_rect(Rect2(x, y + 5, nw + 20, 32), Color(P.PAPER, 0.85))
		draw_string(f, Vector2(x + 10, y + 29), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.INK_SOFT)
	if not partner.is_empty():
		_partner(f, Vector2(right() - CARD.x, TOP))
	if not pointer.is_empty():
		_pointer(f)


func _paper(r: Rect2, block := Color(0, 0, 0, 0)) -> void:
	if block.a > 0.0:
		draw_rect(Rect2(r.position + Vector2(6, 6), r.size), block)
	draw_rect(r, P.PAPER)
	draw_rect(r, P.INK, false, 3.0)


func _calendar(f: Font, at: Vector2) -> void:
	var parts := time_label.split(" · ")
	var age_text := str(parts[0]) if parts.size() > 0 else ""
	var fs := 60 if age_text.length() <= 4 else 44
	var clock := P.clock(minute) if playing or slot_name == "" else slot_name
	var cw := f.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var aw := f.get_string_size(age_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(at, CARD)
	# 年纪长了（"34 岁那几年"）一行放不下年纪和钟点：钟点挪到色条右头，顶掉那两个孔
	var long := aw + cw + 64.0 > r.size.x
	var cw_band := cw * 28.0 / 34.0
	_paper(r, Kit.accent)
	# 色条：节气 / 学期 / 人生阶段
	var band := str(parts[1]) if parts.size() > 1 else str(STAGE_NAME.get(stage, ""))
	if tag != "":
		band += " · " + tag
	draw_rect(Rect2(at, Vector2(r.size.x, 50)), Kit.accent)
	draw_line(at + Vector2(0, 50), at + Vector2(r.size.x, 50), P.INK, 3.0)
	draw_string(f, at + Vector2(18, 37), band, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - (cw_band + 46.0 if long else 96.0), 28, P.PAPER)
	# 撕日历的两个孔
	if not long:
		for hx in [r.size.x - 64.0, r.size.x - 28.0]:
			draw_circle(at + Vector2(hx, 25), 7.0, P.PAPER, true, -1.0, true)
			draw_arc(at + Vector2(hx, 25), 7.0, 0, TAU, 16, P.INK, 2.0, true)
	# 年纪
	draw_string(f, at + Vector2(18, 122 if fs == 60 else 116), age_text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 30.0, fs, P.INK)
	var sky := at + Vector2(r.size.x - 40, 84)
	if long:
		draw_string(f, at + Vector2(r.size.x - cw_band - 16, 37), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, P.PAPER)
	else:
		draw_string(f, at + Vector2(r.size.x - cw - 16, 134), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, P.INK_SOFT)
	if long:
		return
	if minute >= 1110.0 or minute < 360.0:
		draw_circle(sky, 13.0, P.INK, true, -1.0, true)
		draw_circle(sky + Vector2(6, -4), 11.0, P.PAPER, true, -1.0, true)
	else:
		draw_circle(sky + Vector2(2, 2), 12.0, P.MEI, true, -1.0, true)
		draw_arc(sky, 12.0, 0, TAU, 20, P.INK, 2.0, true)


func _gauge(f: Font, c: Vector2, key: String) -> void:
	var v := clampf(float(_shown.get(key, 0.0)) / 100.0, 0.0, 1.0)
	var low := float(needs.get(key, 100.0)) < LOW
	var r := 32.0
	if low:
		c += Vector2(sin(_t * 22.0) * 1.6 * maxf(0.0, sin(_t * 2.2)), 0.0)
	draw_circle(c + Vector2(4, 4), r, Color(P.MEI if low else P.INK, 0.9 if low else 0.18), true, -1.0, true)
	draw_circle(c, r, P.PAPER, true, -1.0, true)
	draw_arc(c, r, 0, TAU, 40, P.INK, 2.5, true)
	if v > 0.005:
		draw_arc(c, r - 8.0, -PI / 2.0, -PI / 2.0 + TAU * v, 40, P.MEI if low else P.INK, 6.0, true)
	var g: String = NEED_GLYPH[key]
	var w := f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	draw_string(f, c + Vector2(-w / 2.0, 10), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, P.MEI if low else P.INK)


func _money(f: Font, at: Vector2) -> float:
	var text := "%d 块" % money
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var r := Rect2(at, Vector2(w + 64, 42))
	draw_rect(r, P.PAPER)
	draw_rect(r, P.INK, false, 2.0)
	# 一枚钢镚儿
	draw_circle(at + Vector2(22, 21), 11.0, P.PAPER_DARK, true, -1.0, true)
	draw_arc(at + Vector2(22, 21), 11.0, 0, TAU, 20, P.INK, 2.0, true)
	draw_arc(at + Vector2(22, 21), 6.0, 0, TAU, 14, P.INK, 1.2, true)
	draw_string(f, at + Vector2(44, 31), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, P.INK)
	return r.size.x


## 主线的小签：左边一块色印着「第几章」，右边是章名和今天的下一件事（没排上就只写章名）。
## 章末躲不过去的那一件，签头换成梅红，写「今天」：到了它那一段，人在哪儿都会被叫过去
static func story_text(st: Dictionary) -> Array:
	var n := int(st.get("chapter", 0))
	var head := "第%s章" % (CHAPTER_NUM[n] if n > 0 and n < CHAPTER_NUM.size() else str(n))
	var next: Variant = st.get("next")
	var body := str(st.get("title", ""))
	if next is String and next != "":
		body += " · 下一件事 " + ("今天" if bool(st.get("force", false)) else "") + next
	return [head, body]


func _story(f: Font, at: Vector2) -> float:
	var parts := story_text(story)
	var hw := f.get_string_size(parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 24.0
	var bw := f.get_string_size(parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 28.0
	var r := Rect2(at, Vector2(hw + bw, 42))
	draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color(P.INK, 0.25))
	draw_rect(r, P.PAPER)
	draw_rect(Rect2(at, Vector2(hw, 42)), P.MEI if bool(story.get("force", false)) else P.INK)
	draw_rect(r, P.INK, false, 2.0)
	draw_string(f, at + Vector2(12, 30), parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, P.PAPER)
	draw_string(f, at + Vector2(hw + 14, 31), parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, P.INK)
	return r.size.x


## 两个圆：亲近决定叠多少，默契写在下面
func _bond(f: Font, at: Vector2) -> void:
	var r := Rect2(at, Vector2(128, 156))
	_paper(r)
	var close := clampf(float(bond.get("close", 0)) / 100.0, 0.0, 1.0)
	var rad := 27.0
	var gap := lerpf(rad * 2.15, rad * 0.5, close) + sin(_t * 1.4) * 1.2
	Kit.draw_pair(self, at + Vector2(64, 50), rad, gap, 1.0, 1.8)
	for i in 2:
		var text := ("亲近 %d" % int(bond.get("close", 0))) if i == 0 else ("默契 %d" % int(bond.get("sync", 0)))
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(f, at + Vector2(64 - w / 2.0, 112 + i * 28), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.INK)


## 对门的牌：和日历牌一个做法，色条是 TA 的颜色。大字是 TA 在做什么（闲着就写在哪），小字补一句
func _partner(f: Font, at: Vector2) -> void:
	var color: Color = partner.get("color", P.MEI)
	var r := Rect2(at, CARD)
	_paper(r, color)
	draw_rect(Rect2(at, Vector2(r.size.x, 50)), color)
	draw_line(at + Vector2(0, 50), at + Vector2(r.size.x, 50), P.INK, 3.0)
	draw_string(f, at + Vector2(18, 37), "对门 · %s" % str(partner.get("name", "TA")), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 70.0, 28, P.PAPER)
	# 在线是一个实心的点；人不在、影子替着，是一个空圈
	var dot := at + Vector2(r.size.x - 28.0, 25)
	if bool(partner.get("online", false)):
		draw_circle(dot, 8.0, P.PAPER, true, -1.0, true)
	else:
		draw_arc(dot, 7.0, 0, TAU, 16, P.PAPER, 2.5, true)
	var big := str(partner.get("big", ""))
	var fs := 44
	while fs > 28 and f.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x - 36.0:
		fs -= 4
	draw_string(f, at + Vector2(18, 104), big, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36.0, fs, P.INK)
	draw_string(f, at + Vector2(18, 140), str(partner.get("small", "")), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36.0, 24, P.INK_SOFT)


## 对门不在画面里：贴着屏幕边一个 TA 颜色的圆，尖儿朝着 TA 的方向
func _pointer(f: Font) -> void:
	var at: Vector2 = pointer.at
	var dir: Vector2 = pointer.dir
	var color: Color = pointer.get("color", P.MEI)
	var r := 30.0 + sin(_t * 2.4) * 1.5
	var tip := at + dir * (r + 22.0)
	var side := dir.orthogonal() * 15.0
	var base := at + dir * (r - 6.0)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(3, 3), base + side + Vector2(3, 3), base - side + Vector2(3, 3)]), Color(P.INK, 0.25))
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), color)
	draw_circle(at + Vector2(3, 3), r, Color(P.INK, 0.25), true, -1.0, true)
	draw_circle(at, r, color, true, -1.0, true)
	draw_arc(at, r, 0, TAU, 32, P.INK, 2.5, true)
	var ch := str(pointer.get("name", "TA")).left(1)
	var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(f, at + Vector2(-w / 2.0, 11), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, P.PAPER)
