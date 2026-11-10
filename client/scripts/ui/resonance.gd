extends Control
## 默契时刻揭晓：两个圆从两边靠拢。
##   共鸣：叠在一起，中间印出第三种颜色，再"咚"地弹一下
##   错位：擦肩而过，停在各自那边，中间一条虚线

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")

var hit := true
var _t := 0.0


func _init(p_hit: bool) -> void:
	hit = p_hit
	custom_minimum_size = Vector2(0, 250)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := 88.0
	var k := clampf((_t - 0.25) / 0.9, 0.0, 1.0)
	var ease_k := 1.0 - pow(1.0 - k, 3.0)
	if hit:
		var gap := lerpf(r * 4.2, r * 0.85, ease_k)
		var since := _t - 1.15
		var pop := 1.0
		if since > 0.0:
			pop += 0.12 * exp(-since * 7.0) * sin(since * 18.0)
		Kit.draw_pair(self, c, r * pop, gap * pop, 1.0, 3.0)
		# 叠住以后，一圈墨线散开
		var ring := _t - 1.15
		if ring > 0.0 and ring < 0.8:
			draw_arc(c, r * 0.9 + ring * 190.0, 0, TAU, 64, Color(P.OVERLAP, 0.7 * (1.0 - ring / 0.8)), 3.0, true)
	else:
		var gap := lerpf(r * 4.2, r * 2.5, ease_k)
		Kit.draw_pair(self, c, r, gap, 1.0, 3.0, lerpf(0.0, -0.16, ease_k))
		var a := clampf(_t - 1.1, 0.0, 1.0)
		var x := -18.0
		while x < 18.0:
			draw_line(c + Vector2(x, 0), c + Vector2(x + 7, 0), Color(P.INK_SOFT, a), 2.5)
			x += 13.0
