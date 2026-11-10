extends Control
## 河畔里的 HUD。全部自己画，垫着纸片，压在地图上也看得清。
##   左上：日历牌（节气 / 年纪 / 钟点，白天一个太阳，夜里一弯月亮）
##   右边：四个圆表（饱腹、精力、心情、清洁），低了变梅红并且抖一下
##   右上：两个圆，越亲近叠得越多；下面是默契和零花钱

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const NEED_GLYPH := {"hunger": "饱", "energy": "精", "mood": "心", "clean": "净"}
const STAGE_NAME := {"childhood": "童年", "teen": "少年", "young": "青年", "middle": "中年", "old": "老年"}

var time_label := ""    ## LifeTime.at().label，例如 "7 岁 · 立夏"
var stage := "childhood"
var minute := 390.0
var tag := ""           ## 日历牌色条上额外的一个词（上学日、预览）
var note := ""          ## 日历牌底下的一行小字（网络延迟）
var needs: Dictionary = {}
var money := -1
var bond: Dictionary = {}
var _shown: Dictionary = {}   ## 圆表上正在显示的值（慢慢追上真实值）
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	for k in needs:
		var cur := float(_shown.get(k, needs[k]))
		_shown[k] = lerpf(cur, float(needs[k]), 1.0 - exp(-6.0 * delta))
	queue_redraw()


func _draw() -> void:
	var f := P.font()
	var top := 64.0
	_calendar(f, Vector2(40, top))
	if not needs.is_empty():
		var x := 356.0
		for k in ["hunger", "energy", "mood", "clean"]:
			_gauge(f, Vector2(x + 44, top + 52), k)
			x += 104.0
		_bond(f, Vector2(size.x - 40 - 128, top))
	if money >= 0:
		_money(f, Vector2(356, top + 114))
	if note != "":
		var nw := f.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_rect(Rect2(40, top + 172, nw + 20, 32), Color(P.PAPER, 0.85))
		draw_string(f, Vector2(50, top + 196), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.INK_SOFT)


func _paper(r: Rect2, block := Color(0, 0, 0, 0)) -> void:
	if block.a > 0.0:
		draw_rect(Rect2(r.position + Vector2(6, 6), r.size), block)
	draw_rect(r, P.PAPER)
	draw_rect(r, P.INK, false, 3.0)


func _calendar(f: Font, at: Vector2) -> void:
	var parts := time_label.split(" · ")
	var age_text := str(parts[0]) if parts.size() > 0 else ""
	var fs := 60 if age_text.length() <= 4 else 44
	var clock := P.clock(minute)
	var cw := f.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var aw := f.get_string_size(age_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(at, Vector2(minf(maxf(292.0, aw + cw + 64.0), 300.0), 156))
	_paper(r, Kit.accent)
	# 色条：节气 / 学期 / 人生阶段
	var band := str(parts[1]) if parts.size() > 1 else str(STAGE_NAME.get(stage, ""))
	if tag != "":
		band += " · " + tag
	draw_rect(Rect2(at, Vector2(r.size.x, 50)), Kit.accent)
	draw_line(at + Vector2(0, 50), at + Vector2(r.size.x, 50), P.INK, 3.0)
	draw_string(f, at + Vector2(18, 37), band, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, P.PAPER)
	# 撕日历的两个孔
	for hx in [r.size.x - 64.0, r.size.x - 28.0]:
		draw_circle(at + Vector2(hx, 25), 7.0, P.PAPER, true, -1.0, true)
		draw_arc(at + Vector2(hx, 25), 7.0, 0, TAU, 16, P.INK, 2.0, true)
	# 年纪
	# 年纪长了（"34 岁那几年"）就把钟点挪到色条里
	var long := aw + cw + 64.0 > 300.0
	draw_string(f, at + Vector2(18, 122 if fs == 60 else 116), age_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, P.INK)
	var sky := at + Vector2(r.size.x - 40, 84)
	if long:
		draw_string(f, at + Vector2(r.size.x - cw * 28.0 / 34.0 - 92, 37), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, P.PAPER)
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
	var low := float(needs.get(key, 100.0)) < 30.0
	var r := 40.0
	if low:
		c += Vector2(sin(_t * 22.0) * 1.6 * maxf(0.0, sin(_t * 2.2)), 0.0)
	draw_circle(c + Vector2(4, 4), r, Color(P.MEI if low else P.INK, 0.9 if low else 0.18), true, -1.0, true)
	draw_circle(c, r, P.PAPER, true, -1.0, true)
	draw_arc(c, r, 0, TAU, 40, P.INK, 2.5, true)
	if v > 0.005:
		draw_arc(c, r - 9.0, -PI / 2.0, -PI / 2.0 + TAU * v, 40, P.MEI if low else P.INK, 7.0, true)
	var g: String = NEED_GLYPH[key]
	var w := f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	draw_string(f, c + Vector2(-w / 2.0, 11), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, P.MEI if low else P.INK)


func _money(f: Font, at: Vector2) -> void:
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
