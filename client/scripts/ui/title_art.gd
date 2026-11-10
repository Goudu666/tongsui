extends Control
## 标题页的画面（横屏；按钮由 main.gd 摆在 buttons_rect() 里）：
##   左边是标志：青、梅两个圆从两边滑进来、叠住，"同""岁"反白在圆里；下面一句话，再下面是按钮
##   右边是一扇"窗"：楼下那条老街（侧视横版的底图）在里面慢慢横移，天会黑、灯会亮
##   窗的四角有裁切线，下面一排色标：这是一张还没裁的印刷打样

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const SceneArt := preload("res://scripts/world/scene_art.gd")
const ContentStore := preload("res://scripts/net/content_store.gd")
const PrintLight := preload("res://scripts/world/print_light.gd")

const LEFT := 96.0       ## 左栏离屏幕左边
const COL_W := 620.0     ## 左栏（标志、按钮）的宽
const LOGO_Y := 292.0
const LOGO_R := 150.0
const WIN_TOP := 190.0
const WIN_H := 640.0
const VIEW_SCALE := 0.62
const VIEW_TOP := 0.0  ## 窗里从这张图的哪一行看起（图自己的坐标）
const SCENE := "street"
const DAY := 70.0  ## 窗里的一整天（秒）

var _t := 0.0
var _inset := Vector2.ZERO
var _window: Control
var _frame: Control
var _holder: Node2D
var _art: SceneArt
var _width := 2400.0
var _light: PrintLight


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inset = Kit.safe_sides(self)
	_window = Control.new()
	_window.clip_contents = true
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_window)
	_holder = Node2D.new()
	_holder.scale = Vector2.ONE * VIEW_SCALE
	_window.add_child(_holder)
	_art = SceneArt.new()
	_holder.add_child(_art)
	var map: Dictionary = ContentStore.load_bundled().get("map", {})
	for sc in map.get("scenes", []):
		if str(sc.id) == SCENE:
			_art.show_scene(sc, map.get("zones", []), map.get("exits", []))
			_width = float(sc.width)
	_art.position = Vector2.ZERO  # 窗里只放这一张，不按世界坐标摆
	if _art.has_art:
		_light = PrintLight.new()
		_holder.add_child(_light)
		_light.setup(Vector2(_width, SceneArt.BOTTOM - SceneArt.TOP), SceneArt.anchors_for(SCENE))
		_light.position = Vector2(0, SceneArt.TOP)
	else:
		_window.visible = false
	_frame = _Frame.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = _window.visible
	add_child(_frame)
	_place()


## 屏幕比 16:9 高（平板）时，整个版面往下挪，上下居中
func _drop() -> float:
	return maxf(0.0, (size.y - Kit.BASE.y) * 0.5)


func _left() -> float:
	return LEFT + _inset.x


## 那扇窗：左栏右边剩下的地方都给它，手机越长窗越宽
func window_rect() -> Rect2:
	var x := _left() + COL_W + 110.0
	return Rect2(x, WIN_TOP + _drop(), maxf(480.0, size.x - x - 110.0 - _inset.y), WIN_H)


## 按钮列放哪儿（main.gd 用）
func buttons_rect() -> Rect2:
	return Rect2(_left(), 600.0 + _drop(), COL_W, 0.0)


func _place() -> void:
	var win := window_rect()
	_window.position = win.position
	_window.size = win.size
	_frame.position = win.position
	_frame.size = win.size


func _process(delta: float) -> void:
	_t += delta
	_place()
	if _window.visible:
		# 镜头：沿着老街来回走一趟
		var span := maxf(0.0, _width - _window.size.x / VIEW_SCALE)
		var k := 0.5 - 0.5 * cos(_t / 95.0 * TAU)
		_holder.position = Vector2(-span * k * VIEW_SCALE, -VIEW_TOP * VIEW_SCALE)
		# 时钟：清早 → 夜里 → 再倒回清早（倒着看的晚霞就是朝霞）
		var d := fmod(_t + 8.0, DAY * 2.0) / DAY
		var day := d if d < 1.0 else 2.0 - d
		var m := lerpf(420.0, 1300.0, smoothstep(0.08, 0.92, day))
		if _light != null:
			_light.set_minute(m)
	queue_redraw()


func _draw() -> void:
	var f := P.font()
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


## 窗框：墨线、裁切线、套准十字、色标、图注
class _Frame extends Control:
	const P := preload("res://scripts/ui/palette.gd")

	func _draw() -> void:
		var f := P.font()
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, P.INK, false, 4.0)
		# 四角裁切线
		for corner in [r.position, Vector2(r.end.x, 0), Vector2(0, r.end.y), r.end]:
			var sx := -1.0 if corner.x < 1.0 else 1.0
			var sy := -1.0 if corner.y < 1.0 else 1.0
			draw_line(corner + Vector2(sx * 14, 0), corner + Vector2(sx * 40, 0), P.INK, 2.0)
			draw_line(corner + Vector2(0, sy * 14), corner + Vector2(0, sy * 40), P.INK, 2.0)
		# 套准十字
		var reg := Vector2(size.x / 2.0, -26)
		draw_arc(reg, 9.0, 0, TAU, 20, P.INK, 1.6, true)
		draw_line(reg + Vector2(-16, 0), reg + Vector2(16, 0), P.INK, 1.6)
		draw_line(reg + Vector2(0, -16), reg + Vector2(0, 16), P.INK, 1.6)
		# 图注 + 色标（墨、青、梅、叠印）
		draw_string(f, Vector2(22, size.y + 62), "天津 · 河畔里", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, P.INK_SOFT)
		var x := size.x - 4 * 44.0 - 14.0
		for col in [P.INK, P.QING, P.MEI, P.OVERLAP]:
			draw_rect(Rect2(x, size.y + 34, 36, 30), col)
			x += 44.0
