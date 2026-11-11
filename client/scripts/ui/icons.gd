extends RefCounted
## 界面上的小图标：都是一笔一笔画的墨线，底下错开半格印一块专色（和 riso_box 一个画法）。
## 一个图标占一个直径 2r 的圆，c 是圆心。color 是那块专色，传透明就只有墨线。
## 用法：Icons.draw(canvas, "clock", center, 18.0, Kit.accent)

const P := preload("res://scripts/ui/palette.gd")

const KINDS := ["clock", "coin", "flag", "sun", "moon", "play", "pause", "chevron", "lock", "check", "pair", "book", "bed", "walk", "star"]


static func draw(c: CanvasItem, kind: String, at: Vector2, r: float, color := Color(0, 0, 0, 0), ink := P.INK) -> void:
	var w := maxf(1.5, r * 0.13)
	var slip := Vector2(r, r) * 0.14
	match kind:
		"clock":
			if color.a > 0.0:
				c.draw_circle(at + slip, r * 0.86, color, true, -1.0, true)
			c.draw_arc(at, r * 0.86, 0, TAU, 32, ink, w, true)
			c.draw_line(at, at + Vector2(0, -r * 0.55), ink, w, true)
			c.draw_line(at, at + Vector2(r * 0.4, r * 0.12), ink, w, true)
		"coin":
			if color.a > 0.0:
				c.draw_circle(at + slip, r * 0.82, color, true, -1.0, true)
			c.draw_arc(at, r * 0.82, 0, TAU, 28, ink, w, true)
			c.draw_rect(Rect2(at - Vector2(r, r) * 0.22, Vector2(r, r) * 0.44), ink, false, w * 0.8)
		"flag":
			var top := at + Vector2(-r * 0.45, -r * 0.8)
			var pts := PackedVector2Array([top, top + Vector2(r * 1.25, r * 0.32), top + Vector2(0, r * 0.7)])
			if color.a > 0.0:
				c.draw_colored_polygon(_moved(pts, slip), color)
			c.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), ink, w, true)
			c.draw_line(top, at + Vector2(-r * 0.45, r * 0.85), ink, w, true)
		"sun":
			c.draw_circle(at + slip * 0.6, r * 0.5, color if color.a > 0.0 else P.MEI, true, -1.0, true)
			c.draw_arc(at, r * 0.5, 0, TAU, 24, ink, w, true)
			for i in 8:
				var d := Vector2.from_angle(TAU * i / 8.0)
				c.draw_line(at + d * r * 0.7, at + d * r * 0.95, ink, w * 0.8, true)
		"moon":
			c.draw_circle(at, r * 0.7, ink, true, -1.0, true)
			c.draw_circle(at + Vector2(r * 0.34, -r * 0.24), r * 0.6, P.PAPER_HI, true, -1.0, true)
		"play":
			var pts := PackedVector2Array([at + Vector2(-r * 0.32, -r * 0.5), at + Vector2(r * 0.52, 0), at + Vector2(-r * 0.32, r * 0.5)])
			c.draw_colored_polygon(pts, ink)
		"pause":
			c.draw_rect(Rect2(at + Vector2(-r * 0.4, -r * 0.5), Vector2(r * 0.26, r)), ink)
			c.draw_rect(Rect2(at + Vector2(r * 0.14, -r * 0.5), Vector2(r * 0.26, r)), ink)
		"chevron":
			c.draw_polyline(PackedVector2Array([at + Vector2(-r * 0.25, -r * 0.5), at + Vector2(r * 0.25, 0), at + Vector2(-r * 0.25, r * 0.5)]), ink, w, true)
		"lock":
			var body := Rect2(at + Vector2(-r * 0.55, -r * 0.1), Vector2(r * 1.1, r * 0.85))
			if color.a > 0.0:
				c.draw_rect(Rect2(body.position + slip, body.size), color)
			c.draw_rect(body, ink, false, w)
			c.draw_arc(at + Vector2(0, -r * 0.1), r * 0.36, PI, TAU, 16, ink, w, true)
		"check":
			c.draw_polyline(PackedVector2Array([at + Vector2(-r * 0.55, 0), at + Vector2(-r * 0.15, r * 0.42), at + Vector2(r * 0.6, -r * 0.48)]), ink, w * 1.3, true)
		"pair":
			c.draw_circle(at + Vector2(-r * 0.3, 0), r * 0.55, P.QING, true, -1.0, true)
			c.draw_circle(at + Vector2(r * 0.3, 0), r * 0.55, P.MEI, true, -1.0, true)
		"book":
			var lp := PackedVector2Array([at + Vector2(-r * 0.85, -r * 0.55), at + Vector2(0, -r * 0.4), at + Vector2(0, r * 0.65), at + Vector2(-r * 0.85, r * 0.5)])
			var rp := PackedVector2Array([at + Vector2(r * 0.85, -r * 0.55), at + Vector2(0, -r * 0.4), at + Vector2(0, r * 0.65), at + Vector2(r * 0.85, r * 0.5)])
			if color.a > 0.0:
				c.draw_colored_polygon(_moved(rp, slip), color)
			lp.append(lp[0])
			rp.append(rp[0])
			c.draw_polyline(lp, ink, w, true)
			c.draw_polyline(rp, ink, w, true)
		"bed":
			c.draw_line(at + Vector2(-r * 0.9, r * 0.5), at + Vector2(r * 0.9, r * 0.5), ink, w, true)
			c.draw_line(at + Vector2(-r * 0.9, -r * 0.4), at + Vector2(-r * 0.9, r * 0.7), ink, w, true)
			var quilt := Rect2(at + Vector2(-r * 0.4, -r * 0.05), Vector2(r * 1.3, r * 0.5))
			if color.a > 0.0:
				c.draw_rect(Rect2(quilt.position + slip, quilt.size), color)
			c.draw_rect(quilt, ink, false, w)
			c.draw_circle(at + Vector2(-r * 0.62, r * 0.12), r * 0.2, ink, true, -1.0, true)
		"walk":
			c.draw_circle(at + Vector2(r * 0.1, -r * 0.62), r * 0.2, ink, true, -1.0, true)
			c.draw_polyline(PackedVector2Array([at + Vector2(r * 0.05, -r * 0.35), at + Vector2(-r * 0.1, r * 0.2), at + Vector2(-r * 0.45, r * 0.8)]), ink, w, true)
			c.draw_line(at + Vector2(-r * 0.1, r * 0.2), at + Vector2(r * 0.35, r * 0.8), ink, w, true)
			c.draw_line(at + Vector2(-r * 0.45, -r * 0.05), at + Vector2(r * 0.45, -r * 0.15), ink, w, true)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var rr := r * (0.9 if i % 2 == 0 else 0.4)
				pts.append(at + Vector2.from_angle(-PI / 2.0 + TAU * i / 10.0) * rr)
			if color.a > 0.0:
				c.draw_colored_polygon(_moved(pts, slip), color)
			pts.append(pts[0])
			c.draw_polyline(pts, ink, w, true)


static func _moved(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out


## 一个装图标的小控件（按钮里、标签前面）
class Glyph extends Control:
	const Icons := preload("res://scripts/ui/icons.gd")
	var kind := "play"
	var color := Color(0, 0, 0, 0)
	var ink := Color("#2B2A33")
	var disc := Color(0, 0, 0, 0)  ## 垫一个圆：主按钮右头那颗「按」

	func _init(p_kind := "play", p_size := 48.0) -> void:
		kind = p_kind
		custom_minimum_size = Vector2(p_size, p_size)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_look(p_kind: String, p_ink: Color, p_disc: Color) -> void:
		if p_kind == kind and p_ink == ink and p_disc == disc:
			return
		kind = p_kind
		ink = p_ink
		disc = p_disc
		queue_redraw()

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0
		var c := size / 2.0
		if disc.a > 0.0:
			draw_circle(c, r, disc, true, -1.0, true)
		Icons.draw(self, kind, c, r * (0.62 if disc.a > 0.0 else 0.9), color, ink)
