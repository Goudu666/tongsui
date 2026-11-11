extends Control
## 标题页的画面（横屏；按钮由 main.gd 摆在 buttons_rect() 里）：
##   整屏铺一张主视觉 res://art/keyart/title.jpg：傍晚的河边，两个半大孩子背着书包往铁桥走
##   （tools/shots/keyart.gd 在游戏里摆拍，tools/art/keyart.py 出图，和商店图是同一张底片）
##   左边一层纸色慢慢盖上来，标志、一句话、按钮印在纸上；画从右边透出来
##   画面慢慢推拉，夕阳那边飘着光里的尘；四角裁切线、一排色标：这是一张还没裁的印刷打样
## 没有这张图时退回纯纸色。

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")

const ART := "res://art/keyart/title.jpg"
const LEFT := 96.0       ## 左栏离屏幕左边
const COL_W := 620.0     ## 左栏（标志、按钮）的宽
const LOGO_Y := 292.0
const LOGO_R := 150.0
const FADE_SOLID := 0.62  ## 纸色从左往右：这一段几乎盖满（相对左栏右边）
const DRIFT := 46.0      ## 一来一回推拉一次（秒）
const MOTES := 34

var _t := 0.0
var _inset := Vector2.ZERO
var _tex: Texture2D
var _fade: GradientTexture2D
var _motes: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inset = Kit.safe_sides(self)
	if ResourceLoader.exists(ART):
		_tex = load(ART)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, FADE_SOLID, 1.0])
	g.colors = PackedColorArray([Color(P.PAPER, 0.95), Color(P.PAPER, 0.86), Color(P.PAPER, 0.0)])
	_fade = GradientTexture2D.new()
	_fade.gradient = g
	_fade.width = 256
	_fade.height = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in MOTES:
		_motes.append(Vector4(rng.randf(), rng.randf(), rng.randf_range(1.6, 4.2), rng.randf() * TAU))


## 屏幕比 16:9 高（平板）时，整个版面往下挪，上下居中
func _drop() -> float:
	return maxf(0.0, (size.y - Kit.BASE.y) * 0.5)


func _left() -> float:
	return LEFT + _inset.x


## 按钮列放哪儿（main.gd 用）
func buttons_rect() -> Rect2:
	return Rect2(_left(), 600.0 + _drop(), COL_W, 0.0)


## 画铺在哪儿：盖满屏幕，右边对齐（两个人在画的右三分之二处），慢慢推拉
func art_rect() -> Rect2:
	if _tex == null:
		return Rect2(Vector2.ZERO, size)
	var ts := Vector2(_tex.get_size())
	var k := 0.5 - 0.5 * cos(_t / DRIFT * TAU)
	var s := maxf(size.x / ts.x, size.y / ts.y) * lerpf(1.0, 1.045, k)
	var sz := ts * s
	# 宽出来的部分大多裁左边（左边反正盖着纸）
	var x := (size.x - sz.x) * lerpf(0.86, 0.94, k)
	var y := (size.y - sz.y) * 0.62
	return Rect2(Vector2(x, y), sz)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var f := P.font()
	var a := clampf(_t / 0.9, 0.0, 1.0)
	if _tex != null:
		var r := art_rect()
		draw_texture_rect(_tex, r, false, Color(1, 1, 1, a))
		_draw_motes(r, a)
		# 左边铺纸：标志和按钮印在纸上
		var fw := _left() + COL_W + 420.0
		draw_texture_rect(_fade, Rect2(0, 0, fw, size.y), false)
		_draw_marks()
	var cx := _left() + COL_W / 2.0
	# 两个圆：开场时从两边滑进来（没套准），慢慢对上，之后轻轻呼吸
	var settle := 1.0 - pow(1.0 - clampf(_t / 1.4, 0.0, 1.0), 3.0)
	var gap := lerpf(LOGO_R * 3.4, LOGO_R * 1.36, settle) + sin(_t * 0.9) * 4.0 * settle
	var c := Vector2(cx, LOGO_Y + _drop())
	Kit.draw_pair(self, c, LOGO_R, gap, 1.0, 3.0)
	var fs := 148
	for i in 2:
		var ch := "同" if i == 0 else "岁"
		var at := c + Vector2((-0.5 if i == 0 else 0.5) * gap + (-13.0 if i == 0 else 13.0), 0.0)
		var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, at + Vector2(-w / 2.0, fs * 0.35), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, P.PAPER)
	var line := "同一栋楼，同一年出生，同一生。"
	var lw := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
	draw_string(f, Vector2(cx - lw / 2.0, LOGO_Y + LOGO_R + 86.0 + _drop()), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color(P.INK, clampf(_t - 0.9, 0.0, 1.0)))


## 光里的尘：夕阳那边（画的右上）慢慢往上飘，一闪一闪
func _draw_motes(r: Rect2, a: float) -> void:
	for m in _motes:
		var u := fmod(m.x + _t * 0.006 * m.z, 1.0)
		var v := 1.0 - fmod(m.y + _t * 0.011 * m.z, 1.0)
		var p := r.position + r.size * Vector2(0.42 + u * 0.56, 0.08 + v * 0.62)
		p.x += sin(_t * 0.7 + m.w) * 10.0
		var tw := 0.5 + 0.5 * sin(_t * 1.3 + m.w * 3.0)
		draw_circle(p, m.z, Color(1.0, 0.93, 0.78, 0.5 * tw * a))


## 四角裁切线、右下的色标和图注：一张还没裁的打样
func _draw_marks() -> void:
	var f := P.font()
	var m := 34.0
	var r := Rect2(Vector2(m + _inset.x, m), size - Vector2(m * 2.0 + _inset.x + _inset.y, m * 2.0))
	for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := -1.0 if corner.x < size.x / 2.0 else 1.0
		var sy := -1.0 if corner.y < size.y / 2.0 else 1.0
		draw_line(corner + Vector2(-sx * 6, 0), corner + Vector2(-sx * 30, 0), Color(P.INK, 0.7), 2.0)
		draw_line(corner + Vector2(0, -sy * 6), corner + Vector2(0, -sy * 30), Color(P.INK, 0.7), 2.0)
	var x := r.end.x - 4 * 34.0 - 10.0
	var y := r.end.y - 44.0
	var cap := "天津 · 河畔里"
	var cw := f.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	draw_rect(Rect2(x - cw - 34.0, y - 4.0, cw + 20.0, 34.0), Color(P.PAPER, 0.9))
	draw_string(f, Vector2(x - cw - 24.0, y + 22.0), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, P.INK_SOFT)
	for col in [P.INK, P.QING, P.MEI, P.OVERLAP]:
		draw_rect(Rect2(x, y, 26, 26), col)
		x += 34.0
