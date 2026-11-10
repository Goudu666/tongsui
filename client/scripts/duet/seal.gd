extends Control
## 两个人这一回对上了没有，画成两枚套色的圆：
##   共鸣（res）   两个圆叠成一个
##   搭上了（catch）两个圆扣在一起，中间一瓣叠印
##   错位（miss）  两个圆各在一边，中间留着缝
## 圆里的小点是「猜中了」：青猜中梅，梅的圆里就落一个青色的点。懂是有方向的。

const P := preload("res://scripts/ui/palette.gd")

const R_FULL := 78.0
## 两个圆心的距离（以半径为单位）
const SPREAD := {"res": 0.0, "catch": 1.15, "miss": 2.7}

var outcome := "miss"
var knew := {}
var R := R_FULL
## 入场动画的进度 0→1：两个圆从两边走过来，停在该停的地方
var t := 0.0:
	set(v):
		t = v
		queue_redraw()


func _init(p_outcome := "miss", p_knew: Variant = null, p_scale := 1.0) -> void:
	outcome = p_outcome if SPREAD.has(p_outcome) else "miss"
	knew = p_knew if p_knew is Dictionary else {}
	R = R_FULL * p_scale
	custom_minimum_size = Vector2(0, R * 2 + 44)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var tw := create_tween()
	tw.tween_property(self, "t", 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 不等动画，直接画成最后的样子（截图和测试用）
func settle() -> void:
	t = 1.0


func _draw() -> void:
	var c := size / 2.0
	var d := lerpf(4.2, float(SPREAD[outcome]), t) * R / 2.0
	var a := c + Vector2(-d, 0)
	var b := c + Vector2(d, 0)
	# 套印总会差一点：先印的那一色往左上偏两个像素
	draw_circle(a + Vector2(-2, -2), R, Color(P.QING, 0.92))
	draw_circle(b, R, Color(P.MEI, 0.92))
	if d < 0.5:
		draw_circle(c, R, P.OVERLAP)
	elif d < R:
		draw_colored_polygon(_lens(a, b, d), P.OVERLAP)
	if t < 1.0:
		return
	# 猜中的点：落在对方的圆里。两个圆叠成一个时，两个点也挨着扣在一起
	var off := 8.0 * clampf(1.0 - d / R, 0.0, 1.0)
	var dots := []
	if knew.get("mei") == true:
		dots.append([a + Vector2(off, 0), P.MEI])
	if knew.get("qing") == true:
		dots.append([b + Vector2(-off, 0), P.QING])
	for dot in dots:
		draw_circle(dot[0], 17.0, P.PAPER)
	for dot in dots:
		draw_circle(dot[0], 12.0, Color(dot[1], 0.9))


## 两个等大的圆相交的那一瓣
func _lens(a: Vector2, b: Vector2, d: float) -> PackedVector2Array:
	var th := acos(clampf(d / R, 0.0, 1.0))
	var pts := PackedVector2Array()
	var n := 20
	for i in n + 1:
		var ang := -th + 2.0 * th * i / n
		pts.append(a + Vector2(cos(ang), sin(ang)) * R)
	for i in n + 1:
		var ang := PI - th + 2.0 * th * i / n
		pts.append(b + Vector2(cos(ang), sin(ang)) * R)
	return pts
