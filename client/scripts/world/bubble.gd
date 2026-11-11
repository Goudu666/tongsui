extends RefCounted
## 头顶的情绪气泡：一张纸片 + 墨线 + 错开一点的色版影子（和名字牌、界面框一个印法），里面一个小图样。
## 主角（actor.gd）和街坊（folks.gd）共用。都是即时画（_draw 里调 draw），不占贴图。
##   heart 心、note 音符、bang 「！」、ask 「？」、dots 「…」、sweat 汗珠、spark 亮晶晶、bulb 灯泡（想到了）、
##   zzz 困、pair 两个圆（搭伴，全局标志）、steam 热气、cloud 一小片雨云（泄气）、talk 一句话（街坊搭腔）

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")

const POP := 0.22      ## 冒出来的那一下（秒）
const FADE := 0.3      ## 最后这么久淡掉


## 气泡在 [0, life] 里的样子：t 已经过了多久。返回 [缩放, 透明度, 往上漂了多少]
static func envelope(t: float, life: float) -> Array:
	var s := 1.0
	if t < POP:
		var u := t / POP
		s = 0.35 + 0.65 * u + sin(u * PI) * 0.22  # 冒出来稍微过一点再回来
	var a := clampf((life - t) / FADE, 0.0, 1.0)
	return [s, a, t * 6.0]


## 在 c 上以 at 为气泡中心画一个。r 是半径（画布坐标），accent 是色版影子的颜色，tail 是尾巴朝哪边（-1 左下 / 1 右下）
static func draw(c: CanvasItem, kind: String, at: Vector2, r: float, accent: Color, t: float, life: float, tail := -1.0) -> void:
	var env := envelope(t, life)
	var s: float = env[0]
	var a: float = env[1]
	if a <= 0.0:
		return
	at.y -= float(env[2])
	r *= s
	# 尾巴：一个小三角指着脑袋
	var tip := at + Vector2(tail * r * 0.9, r * 1.25)
	var tri := PackedVector2Array([at + Vector2(tail * r * 0.15, r * 0.55), tip, at + Vector2(tail * r * 0.7, r * 0.35)])
	var shadow := Vector2(r * 0.14, r * 0.14)
	_blob(c, at + shadow, r, Color(accent, 0.9 * a))
	c.draw_colored_polygon(_shift(tri, shadow), Color(accent, 0.9 * a))
	_blob(c, at, r, Color(P.PAPER, a))
	c.draw_colored_polygon(tri, Color(P.PAPER, a))
	_blob_line(c, at, r, Color(P.INK, 0.85 * a), maxf(1.4, r * 0.09))
	c.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2]]), Color(P.INK, 0.85 * a), maxf(1.4, r * 0.09), true)
	_glyph(c, kind, at, r * 0.62, a, t)


## 气泡本身：横着略扁一点的圆角
static func _blob(c: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	c.draw_colored_polygon(_ring(at, r), col)


static func _blob_line(c: CanvasItem, at: Vector2, r: float, col: Color, w: float) -> void:
	var pts := _ring(at, r)
	pts.append(pts[0])
	c.draw_polyline(pts, col, w, true)


static func _ring(at: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 28:
		var ang := TAU * i / 28.0
		pts.append(at + Vector2(cos(ang) * r * 1.12, sin(ang) * r * 0.92))
	return pts


static func _shift(pts: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + d)
	return out


static func _glyph(c: CanvasItem, kind: String, at: Vector2, g: float, a: float, t: float) -> void:
	var ink := Color(P.INK, a)
	var mei := Color(P.MEI, a)
	var qing := Color(P.QING, a)
	var w := maxf(1.5, g * 0.16)
	match kind:
		"heart":
			var beat := 1.0 + 0.12 * sin(t * 9.0)
			var h := g * 0.5 * beat
			c.draw_circle(at + Vector2(-h * 0.5, -h * 0.25), h * 0.58, mei, true, -1.0, true)
			c.draw_circle(at + Vector2(h * 0.5, -h * 0.25), h * 0.58, mei, true, -1.0, true)
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-h * 1.05, -h * 0.05), at + Vector2(h * 1.05, -h * 0.05), at + Vector2(0, h * 1.05)]), mei)
		"note":
			var bob := sin(t * 7.0) * g * 0.06
			var o := at + Vector2(-g * 0.12, bob)
			c.draw_circle(o + Vector2(-g * 0.22, g * 0.42), g * 0.26, ink, true, -1.0, true)
			c.draw_line(o + Vector2(0.0, g * 0.42), o + Vector2(0.0, -g * 0.62), ink, w, true)
			c.draw_polyline(PackedVector2Array([o + Vector2(0, -g * 0.62), o + Vector2(g * 0.42, -g * 0.36), o + Vector2(g * 0.36, -g * 0.08)]), ink, w, true)
			c.draw_circle(at + Vector2(g * 0.55, -g * 0.5 - bob), g * 0.1, mei, true, -1.0, true)
		"bang":
			c.draw_line(at + Vector2(0, -g * 0.75), at + Vector2(0, g * 0.22), mei, g * 0.3, true)
			c.draw_circle(at + Vector2(0, g * 0.62), g * 0.17, mei, true, -1.0, true)
		"ask", "dots", "zzz", "talk":
			var s: String = {"ask": "？", "dots": "…", "zzz": "z z", "talk": "嗯"}[kind]
			var f := P.font()
			var fs := int(g * (1.5 if kind != "zzz" else 1.0))
			if kind == "dots":
				for i in 3:
					var k := clampf(t * 3.0 - i * 0.6, 0.0, 1.0)
					c.draw_circle(at + Vector2((i - 1) * g * 0.48, g * 0.08), g * 0.13 * k, ink, true, -1.0, true)
				return
			var sz := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			c.draw_string(f, at + Vector2(-sz.x / 2.0, fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, mei if kind == "ask" else ink)
		"sweat":
			var drip := fmod(t * 0.9, 1.0) * g * 0.25
			var o := at + Vector2(0, drip - g * 0.1)
			var pts := PackedVector2Array([o + Vector2(0, -g * 0.7)])
			for i in 13:
				var ang := PI * (-0.15 + 1.3 * i / 12.0)
				pts.append(o + Vector2(cos(ang) * g * 0.42, g * 0.18 + sin(ang) * g * 0.42))
			c.draw_colored_polygon(pts, qing)
			c.draw_circle(o + Vector2(-g * 0.12, g * 0.12), g * 0.08, Color(P.PAPER, a), true, -1.0, true)
		"spark":
			_star(c, at + Vector2(-g * 0.15, g * 0.05), g * (0.62 + 0.1 * sin(t * 10.0)), mei)
			_star(c, at + Vector2(g * 0.5, -g * 0.45), g * 0.3, qing)
		"bulb":
			c.draw_circle(at + Vector2(0, -g * 0.12), g * 0.48, Color(P.MEI, 0.35 * a), true, -1.0, true)
			c.draw_arc(at + Vector2(0, -g * 0.12), g * 0.48, 0, TAU, 24, ink, w * 0.8, true)
			c.draw_line(at + Vector2(-g * 0.22, g * 0.48), at + Vector2(g * 0.22, g * 0.48), ink, w, true)
			c.draw_line(at + Vector2(-g * 0.16, g * 0.68), at + Vector2(g * 0.16, g * 0.68), ink, w, true)
			for i in 3:
				var ang := -PI * (0.25 + 0.25 * i)
				var d := Vector2(cos(ang), sin(ang))
				c.draw_line(at + Vector2(0, -g * 0.12) + d * g * 0.66, at + Vector2(0, -g * 0.12) + d * g * 0.9, mei, w * 0.8, true)
		"pair":
			Kit.draw_pair(c, at + Vector2(0, g * 0.05), g * 0.42, g * 0.46 + sin(t * 4.0) * g * 0.08, a, 0.0)
		"steam":
			for i in 3:
				var pts := PackedVector2Array()
				for j in 7:
					var y := g * 0.6 - j * g * 0.2
					pts.append(at + Vector2((i - 1) * g * 0.42 + sin(t * 6.0 + j * 0.9 + i) * g * 0.1, y))
				c.draw_polyline(pts, Color(P.INK_SOFT, a), w * 0.8, true)
		"cloud":
			var o := at + Vector2(0, -g * 0.2)
			for p in [Vector2(-0.38, 0.05), Vector2(0.0, -0.18), Vector2(0.38, 0.05)]:
				c.draw_circle(o + p * g, g * 0.32, Color(P.INK_SOFT, a), true, -1.0, true)
			c.draw_rect(Rect2(o + Vector2(-g * 0.6, 0.0), Vector2(g * 1.2, g * 0.3)), Color(P.INK_SOFT, a))
			for i in 3:
				var x := (i - 1) * g * 0.36
				var fall := fmod(t * 1.6 + i * 0.3, 1.0) * g * 0.3
				c.draw_line(o + Vector2(x, g * 0.42 + fall), o + Vector2(x - g * 0.06, g * 0.62 + fall), qing, w * 0.8, true)


static func _star(c: CanvasItem, at: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var ang := TAU * i / 8.0 - PI / 2.0
		var rr := s if i % 2 == 0 else s * 0.3
		pts.append(at + Vector2(cos(ang), sin(ang)) * rr)
	c.draw_colored_polygon(pts, col)
