extends Control
## 默契时刻揭晓：两个圆从两边靠拢。
##   共鸣（res）：叠在一起，中间印出第三种颜色，再"咚"地弹一下
##   搭上了（catch）：一个先到，一个跟上来扣住，只叠一瓣——选得不一样，但接住了
##   错位（miss）：擦肩而过，停在各自那边，中间一条虚线
## 圆里的小点是「猜中了」：青猜中梅，梅的圆里就落一个青色的点。懂是有方向的。（见 docs/DUET.md）

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")

const SETTLE := 1.15  ## 两个圆停稳的时刻（秒）

var outcome := "res"
var hit := true
var knew := {}
var r := 88.0
var _t := 0.0


## p_outcome：true / false（共鸣 / 错位），或者 "res" / "catch" / "miss"
func _init(p_outcome: Variant = true, p_knew: Variant = null, p_scale := 1.0) -> void:
	if p_outcome is String:
		outcome = p_outcome if p_outcome in ["res", "catch", "miss"] else "miss"
	else:
		outcome = "res" if p_outcome else "miss"
	hit = outcome != "miss"
	knew = p_knew if p_knew is Dictionary else {}
	r = 88.0 * p_scale
	custom_minimum_size = Vector2(0, r * 2.0 + 74.0 * p_scale)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## 不等动画，直接画成最后的样子（截图和测试用）
func settle() -> void:
	_t = 10.0
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var k := clampf((_t - 0.25) / 0.9, 0.0, 1.0)
	var ease_k := 1.0 - pow(1.0 - k, 3.0)
	var since := _t - SETTLE
	var gap := 0.0
	var tilt := 0.0
	if outcome == "res":
		gap = lerpf(r * 4.2, r * 0.85, ease_k)
		var pop := 1.0
		if since > 0.0:
			pop += 0.12 * exp(-since * 7.0) * sin(since * 18.0)
		Kit.draw_pair(self, c, r * pop, gap * pop, 1.0, 3.0)
		# 叠住以后，一圈墨线散开
		if since > 0.0 and since < 0.8:
			draw_arc(c, r * 0.9 + since * 190.0, 0, TAU, 64, Color(P.OVERLAP, 0.7 * (1.0 - since / 0.8)), 3.0, true)
	elif outcome == "catch":
		# 斜着扣上：一个高一点、一个低一点，像递过去、接过来
		gap = lerpf(r * 4.2, r * 1.5, ease_k)
		tilt = lerpf(0.0, 0.2, ease_k)
		var nudge := 1.0
		if since > 0.0:
			nudge += 0.06 * exp(-since * 8.0) * sin(since * 16.0)
		Kit.draw_pair(self, c, r, gap * nudge, 1.0, 3.0, tilt)
	else:
		gap = lerpf(r * 4.2, r * 2.5, ease_k)
		tilt = lerpf(0.0, -0.16, ease_k)
		Kit.draw_pair(self, c, r, gap, 1.0, 3.0, tilt)
		var a := clampf(_t - 1.1, 0.0, 1.0)
		var x := -18.0
		while x < 18.0:
			draw_line(c + Vector2(x, 0), c + Vector2(x + 7, 0), Color(P.INK_SOFT, a), 2.5)
			x += 13.0
	# 猜中的点：停稳以后落在对方那个圆靠外的一侧（两个圆叠着时，那里还是对方自己的颜色）
	var show := clampf((since - 0.15) / 0.25, 0.0, 1.0)
	if show <= 0.0:
		return
	var dir := Vector2(1, 0).rotated(tilt)
	var half := dir * gap / 2.0
	if knew.get("qing") == true:
		_dot(c + half + dir * r * 0.5, P.QING, show)
	if knew.get("mei") == true:
		_dot(c - half - dir * r * 0.5, P.MEI, show)


func _dot(at: Vector2, color: Color, show: float) -> void:
	var s := r / 88.0 * (0.6 + 0.4 * show)
	draw_circle(at, 19.0 * s, Color(P.PAPER, show), true, -1.0, true)
	draw_circle(at, 13.0 * s, Color(color, show), true, -1.0, true)
	draw_arc(at, 19.0 * s, 0, TAU, 32, Color(P.INK, show), 2.0, true)
