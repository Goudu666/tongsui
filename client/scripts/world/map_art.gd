extends Node2D
## 河畔里的美术：孔版套色的地图切片 + 叠印层 + 会动的小东西 + 昼夜。
## 贴图由 tools/art/build_map.py 程序化生成（client/art/map/），这里只负责摆放和动画。
##
## 层级（z_index）：
##   -100 地面切片（角色在它上面走）
##      0 角色（world_view 里，按 y 排序）
##     40 环境动画（热气、风筝、鸽子……）
##     50 叠印层：树冠、电线、床单、雨棚、桥的钢架。用"正片叠底"盖在角色身上，像孔版套印
##     60 天上飞的鸽子

const P := preload("res://scripts/ui/palette.gd")
const DIR := "res://art/map/"
const TILE := 800.0
const ART_SCALE := 2.0

var anchors: Dictionary = {}
var minute := 390.0  ## 由 world_view 喂进来，决定昼夜
var night := 0.0     ## 0 白天 ~ 1 深夜
var _t := 0.0
var _flock_t := 0.0  ## 鸽群起飞的计时
var _flying := false
var _modulate: CanvasModulate
var _lights: Array[PointLight2D] = []
var _fx: Node2D
var _sky: Node2D
var has_art := false


func _ready() -> void:
	_load_tiles()
	_load_anchors()
	_fx = _Layer.new(self, false)
	_fx.z_index = 40
	add_child(_fx)
	_sky = _Layer.new(self, true)
	_sky.z_index = 60
	add_child(_sky)
	_modulate = CanvasModulate.new()
	add_child(_modulate)
	_make_lights()
	set_minute(minute)


func _load_tiles() -> void:
	var mul := CanvasItemMaterial.new()
	mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	for row in 2:
		for col in 3:
			var g := "%sground_%d_%d.png" % [DIR, col, row]
			if ResourceLoader.exists(g):
				has_art = true
				add_child(_tile(load(g), col, row, -100, null))
			var o := "%sover_%d_%d.png" % [DIR, col, row]
			if ResourceLoader.exists(o):
				add_child(_tile(load(o), col, row, 50, mul))


func _tile(tex: Texture2D, col: int, row: int, z: int, mat: Material) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = Vector2(col, row) * TILE
	s.scale = Vector2.ONE / ART_SCALE
	s.z_index = z
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if mat != null:
		s.material = mat
	return s


func _load_anchors() -> void:
	var path := DIR + "anchors.json"
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		anchors = parsed.get("anchors", {})


func pts(kind: String) -> Array:
	return anchors.get(kind, [])


# ----------------------------------------------------------------------
# 昼夜：白天是纸本来的颜色，傍晚泛一点梅红，夜里压成青灰，路灯和对岸的灯亮起来
# ----------------------------------------------------------------------

const SKY := [
	[390.0, Color(1.0, 0.975, 0.95)],   # 06:30 清早
	[540.0, Color(1.0, 1.0, 1.0)],     # 09:00
	[1020.0, Color(1.0, 0.97, 0.92)],  # 17:00
	[1110.0, Color(0.99, 0.91, 0.89)], # 18:30 傍晚
	[1200.0, Color(0.70, 0.74, 0.86)], # 20:00 天黑
	[1320.0, Color(0.56, 0.61, 0.76)], # 22:00
]


func set_minute(m: float) -> void:
	minute = m
	var c: Color = SKY[0][1]
	for i in SKY.size() - 1:
		var a: Array = SKY[i]
		var b: Array = SKY[i + 1]
		if m >= a[0] and m <= b[0]:
			c = (a[1] as Color).lerp(b[1], (m - a[0]) / (b[0] - a[0]))
			break
		if m > b[0]:
			c = b[1]
	if _modulate != null:
		_modulate.color = c
	night = clampf((m - 1110.0) / 120.0, 0.0, 1.0)
	for l in _lights:
		l.enabled = night > 0.01
		l.energy = night * float(l.get_meta("energy", 0.8))


func _make_lights() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	var spec := {
		"street_lamp": [Color("#E9B872"), 2.4, 0.45],
		"hall_lamp": [Color("#E9B872"), 1.2, 0.4],
		"far_light": [Color("#E9B872"), 0.6, 0.3],
		"window_light": [Color("#E9B872"), 1.4, 0.3],
		"stall_light": [Color("#E9B872"), 1.8, 0.4],
	}
	for kind in spec:
		for p in pts(kind):
			var l := PointLight2D.new()
			l.texture = tex
			l.position = Vector2(p.x, p.y)
			l.color = spec[kind][0]
			l.texture_scale = spec[kind][1]
			l.set_meta("energy", spec[kind][2])
			l.blend_mode = Light2D.BLEND_MODE_ADD
			l.enabled = false
			add_child(l)
			_lights.append(l)


func _process(delta: float) -> void:
	_t += delta
	_flock_t += delta
	if not _flying and _flock_t > 14.0:
		_flying = true
		_flock_t = 0.0
	elif _flying and _flock_t > 9.0:
		_flying = false
		_flock_t = 0.0
	_fx.queue_redraw()
	_sky.queue_redraw()


# ----------------------------------------------------------------------
# 会动的小东西。全部用墨线 + 专色画，和底图一个路子
# ----------------------------------------------------------------------

func draw_fx(c: CanvasItem) -> void:
	var t := _t
	# 早点铺的热气：早上浓，过了十点淡
	var steam_a := 0.45 if minute < 600.0 else 0.18
	for p in pts("steam"):
		for k in 3:
			var ph := fmod(t * 0.5 + k / 3.0, 1.0)
			var base := Vector2(p.x + (k - 1) * 10.0, p.y - ph * 70.0)
			var w := sin(t * 2.0 + k + ph * 6.0) * 6.0
			var col := Color(P.INK, steam_a * (1.0 - ph))
			c.draw_arc(base + Vector2(w, 0), 9.0, PI * 0.6, PI * 1.4, 8, col, 2.0)
			c.draw_arc(base + Vector2(w + 4, -14), 9.0, -PI * 0.4, PI * 0.4, 8, col, 2.0)
	# 烟囱冒烟：慢、大、淡
	for p in pts("smoke"):
		for k in 3:
			var ph := fmod(t * 0.22 + k / 3.0, 1.0)
			var at := Vector2(p.x + ph * 30.0 + sin(t + k) * 4.0, p.y - ph * 90.0)
			c.draw_circle(at, 6.0 + ph * 12.0, Color(P.INK, 0.14 * (1.0 - ph)))
	# 河面的涟漪
	for i in pts("ripple").size():
		var p: Dictionary = pts("ripple")[i]
		var ph := fmod(t * 0.35 + i * 0.37, 1.0)
		var r := 8.0 + ph * 30.0
		c.draw_arc(Vector2(p.x, p.y), r, PI * 1.15, PI * 1.85, 12, Color(P.QING, 0.7 * (1.0 - ph)), 2.0)
	# 旗杆上的红旗
	for p in pts("flag"):
		var o := Vector2(p.x, p.y)
		var poly := PackedVector2Array()
		for k in 7:
			var x := k * 7.0
			poly.append(o + Vector2(x, sin(t * 5.0 - k * 0.8) * k * 0.9))
		for k in range(6, -1, -1):
			var x := k * 7.0
			poly.append(o + Vector2(x, 26.0 + sin(t * 5.0 - k * 0.8) * k * 0.9))
		c.draw_colored_polygon(poly, Color(P.MEI, 0.92))
		c.draw_polyline(poly, P.INK, 1.5)
	# 收音机里飘出来的相声（音符）
	for p in pts("radio"):
		for k in 2:
			var ph := fmod(t * 0.4 + k * 0.5, 1.0)
			var at := Vector2(p.x + 10 + ph * 26.0 + k * 8, p.y - ph * 46.0)
			var col := Color(P.MEI, 0.85 * (1.0 - ph))
			c.draw_circle(at, 3.4, col)
			c.draw_line(at + Vector2(3, 0), at + Vector2(3, -12), col, 1.6)
			c.draw_line(at + Vector2(3, -12), at + Vector2(8, -9), col, 1.6)
	# 鱼缸里的小鱼
	for p in pts("fish"):
		var at := Vector2(p.x + sin(t * 0.9) * 10.0, p.y + sin(t * 1.7) * 2.0)
		var dir := 1.0 if cos(t * 0.9) > 0 else -1.0
		c.draw_circle(at, 3.0, P.MEI)
		c.draw_colored_polygon(PackedVector2Array([at - Vector2(dir * 2, 0), at - Vector2(dir * 7, 3), at - Vector2(dir * 7, -3)]), P.MEI)
	# 暖气片底下的猫（"暖气片后面的猫"），尾巴慢慢甩
	var cats := pts("radiator")
	if not cats.is_empty():
		var p: Dictionary = cats[0]
		var at := Vector2(p.x - 30, p.y + 10)
		_cat(c, at, t)
	# 倒放的自行车轮在转
	for p in pts("spoke"):
		var o := Vector2(p.x, p.y)
		for k in 4:
			var a := t * 4.0 + k * PI / 4.0
			c.draw_line(o - Vector2(cos(a), sin(a)) * 15.0, o + Vector2(cos(a), sin(a)) * 15.0, Color(P.INK, 0.7), 1.2)
	# 电线上的小鸟，偶尔蹦一下
	for i in pts("wire_bird").size():
		var p: Dictionary = pts("wire_bird")[i]
		var hop := maxf(0.0, sin(t * 1.3 + i * 2.1)) ** 12 * 6.0
		var at := Vector2(p.x, p.y - hop)
		c.draw_circle(at, 4.5, P.INK)
		c.draw_circle(at + Vector2(4, -4), 3.0, P.INK)
		c.draw_line(at + Vector2(-3, 1), at + Vector2(-9, 4), P.INK, 2.0)
	# 夜里对岸亮起来的窗
	if night > 0.05:
		for p in pts("far_light"):
			c.draw_rect(Rect2(p.x - 3, p.y - 4, 6, 8), Color("#F2C48D", night * 0.9))


func draw_sky(c: CanvasItem) -> void:
	var t := _t
	# 风筝：在步道上空，线拽到地上
	var kites := pts("kite")
	for i in kites.size():
		var p: Dictionary = kites[i]
		var sway := Vector2(sin(t * 0.8 + i) * 14.0, cos(t * 1.1 + i * 2.0) * 8.0)
		var at := Vector2(p.x, p.y) + sway
		var col := P.MEI if i % 2 == 0 else P.QING
		var d := PackedVector2Array([at + Vector2(0, -20), at + Vector2(15, 0), at + Vector2(0, 26), at + Vector2(-15, 0)])
		c.draw_colored_polygon(d, Color(col, 0.92))
		d.append(d[0])
		c.draw_polyline(d, P.INK, 2.0)
		c.draw_line(at + Vector2(0, -20), at + Vector2(0, 26), P.INK, 1.2)
		var tail := PackedVector2Array()
		for k in 8:
			tail.append(at + Vector2(sin(t * 3.0 - k * 0.7) * 6.0, 26 + k * 7.0))
		c.draw_polyline(tail, P.INK, 1.4)
		c.draw_line(at + Vector2(0, 6), at + Vector2(-60, 170), Color(P.INK, 0.5), 1.0)
	# 鸽子：歇在笼子上，隔一会儿整群起飞，绕楼顶几圈再回来
	var home := pts("pigeon")
	if home.is_empty():
		return
	var hub: Dictionary = pts("pigeon_home")[0] if not pts("pigeon_home").is_empty() else home[0]
	var center := Vector2(hub.x, hub.y + 40)
	for i in home.size():
		var p: Dictionary = home[i]
		var rest := Vector2(p.x, p.y)
		if _flying:
			var k := clampf(_flock_t / 1.2, 0.0, 1.0) * clampf((9.0 - _flock_t) / 1.2, 0.0, 1.0)
			var a := _flock_t * 1.1 + i * 0.5
			var orbit := center + Vector2(cos(a) * (240.0 + i * 10.0), sin(a) * 90.0 - 40.0)
			_pigeon(c, rest.lerp(orbit, k), t * 14.0 + i, k > 0.2)
		else:
			_pigeon(c, rest, t + i, false)


func _pigeon(c: CanvasItem, at: Vector2, phase: float, flying: bool) -> void:
	if flying:
		var flap := sin(phase) * 7.0
		c.draw_line(at, at + Vector2(-11, -4 - flap), P.INK, 2.4)
		c.draw_line(at, at + Vector2(11, -4 - flap), P.INK, 2.4)
		c.draw_circle(at, 3.2, P.PAPER)
		c.draw_arc(at, 3.2, 0, TAU, 10, P.INK, 1.4)
	else:
		var bob := sin(phase * 2.0) * 1.0
		c.draw_circle(at + Vector2(0, bob), 6.0, P.PAPER)
		c.draw_arc(at + Vector2(0, bob), 6.0, 0, TAU, 14, P.INK, 1.8)
		c.draw_circle(at + Vector2(5, -5 + bob), 3.4, P.INK)
		c.draw_line(at + Vector2(-5, 2 + bob), at + Vector2(-10, 4 + bob), P.INK, 2.0)


func _cat(c: CanvasItem, at: Vector2, t: float) -> void:
	c.draw_set_transform(at, 0.0, Vector2(1.0, 0.7))
	c.draw_circle(Vector2.ZERO, 13.0, Color(P.INK, 0.85))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	c.draw_circle(at + Vector2(11, -4), 7.0, Color(P.INK, 0.85))
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(7, -9), at + Vector2(9, -16), at + Vector2(12, -10)]), Color(P.INK, 0.85))
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(13, -10), at + Vector2(17, -15), at + Vector2(17, -7)]), Color(P.INK, 0.85))
	var tail := PackedVector2Array()
	for k in 7:
		tail.append(at + Vector2(-12 - k * 3.0, 4 + sin(t * 1.5 + k * 0.5) * k * 0.8))
	c.draw_polyline(tail, Color(P.INK, 0.85), 3.0)


class _Layer extends Node2D:
	var art: Node
	var sky := false

	func _init(p_art: Node, p_sky: bool) -> void:
		art = p_art
		sky = p_sky

	func _draw() -> void:
		if sky:
			art.draw_sky(self)
		else:
			art.draw_fx(self)
