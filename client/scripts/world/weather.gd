extends Node2D
## 天气：春天飘柳絮、夏天有的日子下雨、秋天落叶、冬天有的日子下雪。只是画面，不进结算。
## 粒子在世界坐标里落（人往前走，雪片留在原地），发射口跟着镜头顶上走。
## 屋里为主的图（楼里的剖面、出租屋、医院）不下：剖面图上雨会落进屋里。
## 下雨下雪的日子天是阴的（scene_art.set_overcast）。

const P := preload("res://scripts/ui/palette.gd")
const INDOOR := ["building", "rental", "hospital"]

var art = null            ## scene_art：阴天要告诉它
var light = null          ## print_light：雨雪天灯晕大一点、地面湿（atmos 读 light.wet 画倒影）
var season := "spring"
var day := 0              ## 第几个回合：同一个季节，有的日子下、有的不下
var kind := ""            ## 现在下的是什么：catkin / rain / leaf / snow / ""
var _scene := ""
var _p: CPUParticles2D
var _tex := {}
var restarts := 0         ## 粒子重撒过几回（单测看：同一天反复设不该重撒）


func _ready() -> void:
	z_index = 60
	_p = CPUParticles2D.new()
	_p.local_coords = false
	_p.emitting = false
	_p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	add_child(_p)
	_apply()  # 进树之前就设过季节和图的，这会儿补上


## 换图、换季节、换回合都可能每秒被调好几次（WORLD 5Hz 刷 HUD），没变就不动
func set_scene(id: String) -> void:
	if id == _scene:
		return
	_scene = id
	_apply()


func set_season(s: String, p_day := -1) -> void:
	if s == season and (p_day < 0 or p_day == day):
		return
	season = s
	if p_day >= 0:
		day = p_day
	_apply()


## 今天外面下的是什么（不管现在是哪张图）：声音用，人在屋里也听得见窗外的雨
func today() -> String:
	return _pick()


## 这一天下不下：按回合撒一个数，一季里大概三分之一的日子下雨、一多半的冬天下雪
func _pick() -> String:
	var h := fmod(sin(float(day) * 12.9898 + 4.1) * 43758.5453, 1.0)
	h = absf(h)
	match season:
		"spring":
			return "catkin"
		"summer":
			return "rain" if h < 0.35 else ""
		"autumn":
			return "leaf"
		"winter":
			return "snow" if h < 0.65 else ""
	return ""


func _apply() -> void:
	if _p == null:
		return
	var k := "" if _scene in INDOOR else _pick()
	if art != null:
		art.set_overcast(1.0 if k in ["rain", "snow"] else 0.0)
	if light != null:
		light.wet = 1.0 if k == "rain" else (0.5 if k == "snow" else 0.0)
	# 下的东西没变（比如冬天两天都下雪），接着下，不重撒
	if k == kind and (k == "" or _p.emitting):
		return
	kind = k
	_p.emitting = kind != ""
	if kind == "":
		return
	_p.texture = _texture(kind)
	_p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_p.color = Color.WHITE
	_p.color_initial_ramp = null
	_p.angle_min = 0.0
	_p.angle_max = 0.0
	_p.angular_velocity_min = 0.0
	_p.angular_velocity_max = 0.0
	_p.scale_amount_min = 1.0 / SS
	_p.scale_amount_max = 1.0 / SS
	_p.orbit_velocity_min = 0.0
	_p.orbit_velocity_max = 0.0
	_p.tangential_accel_min = 0.0
	_p.tangential_accel_max = 0.0
	match kind:
		"rain":
			_p.amount = 260
			_p.lifetime = 1.1
			_p.gravity = Vector2(0, 0)
			_p.direction = Vector2(-0.22, 1.0)
			_p.spread = 2.0
			_p.initial_velocity_min = 1100.0
			_p.initial_velocity_max = 1300.0
			_p.angle_min = -12.4
			_p.angle_max = -12.4
			_p.color = Color(1, 1, 1, 0.6)
			_p.scale_amount_min = 0.8 / SS   # 远近不一：细的、粗的雨丝
			_p.scale_amount_max = 1.2 / SS
		"snow":
			_p.amount = 180
			_p.lifetime = 9.0
			_p.gravity = Vector2(0, 14)
			_p.direction = Vector2(0.15, 1.0)
			_p.spread = 25.0
			_p.initial_velocity_min = 50.0
			_p.initial_velocity_max = 90.0
			_p.scale_amount_min = 0.45 / SS
			_p.scale_amount_max = 1.25 / SS
			_p.tangential_accel_min = -8.0
			_p.tangential_accel_max = 8.0
		"catkin":
			_p.amount = 36
			_p.lifetime = 14.0
			_p.gravity = Vector2(6, 4)
			_p.direction = Vector2(1.0, 0.3)
			_p.spread = 60.0
			_p.initial_velocity_min = 20.0
			_p.initial_velocity_max = 45.0
			_p.scale_amount_min = 0.6 / SS
			_p.scale_amount_max = 1.1 / SS
			_p.tangential_accel_min = -12.0
			_p.tangential_accel_max = 12.0
		"leaf":
			_p.amount = 22
			_p.lifetime = 10.0
			_p.gravity = Vector2(10, 30)
			_p.direction = Vector2(0.4, 1.0)
			_p.spread = 30.0
			_p.initial_velocity_min = 30.0
			_p.initial_velocity_max = 70.0
			_p.angular_velocity_min = -160.0
			_p.angular_velocity_max = 160.0
			_p.angle_min = 0.0
			_p.angle_max = 360.0
			_p.scale_amount_min = 0.7 / SS
			_p.scale_amount_max = 1.2 / SS
			_p.tangential_accel_min = -20.0
			_p.tangential_accel_max = 20.0
			# 每片叶子颜色不一样：柿子橙、杏黄、梅红、一点点还没黄透的青
			var ramp := Gradient.new()
			ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
			ramp.colors = PackedColorArray([Color(0.93, 0.56, 0.24), Color(0.96, 0.76, 0.32), P.MEI.lightened(0.1), P.QING.lightened(0.15)])
			_p.color_initial_ramp = ramp
	# 先空跑一整轮再开始，第一次进图就是满屏的
	_p.preprocess = _p.lifetime
	_p.restart()
	restarts += 1


func _process(_delta: float) -> void:
	if kind == "":
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var c := cam.get_screen_center_position()
	var view := get_viewport_rect().size / cam.zoom
	# 发射口：镜头顶上一条，比镜头宽一截（风把东西往一边吹）
	_p.position = Vector2(c.x, c.y - view.y * 0.5 - 40.0)
	_p.emission_rect_extents = Vector2(view.x * 0.75, 30.0)
	if kind == "catkin" or kind == "leaf":
		# 柳絮和落叶是满屏飘的，不只从顶上来
		_p.emission_rect_extents = Vector2(view.x * 0.75, view.y * 0.5)
		_p.position.y = c.y - 60.0


## 粒子的样子：现画一张小图。微缩模型里的雨雪是软的、有一点体积：
##   雨：一道细细的、两头虚的水痕（中间一条亮线像被灯照着），落得快，拖成一条
##   雪：一颗柔边的小棉球，左上被照亮、右下一层淡淡的蓝灰，边缘虚掉
##   柳絮：一团更虚的绒毛，几乎不分明暗
##   落叶：一片带叶脉的小叶子，一边亮一边暗（像微微卷起来），颜色每片不同（color_initial_ramp）
## 图按 SS 倍画、粒子再按 1/SS 缩回去，带 mipmap，镜头怎么缩边都是平滑的
const SS := 2.0


func _texture(k: String) -> Texture2D:
	if _tex.has(k):
		return _tex[k]
	var img: Image
	match k:
		"rain":
			img = _streak(4, 40)
		"snow":
			img = _ball(8, Color(0.97, 0.98, 1.0), Color(0.74, 0.80, 0.92), 0.0)
		"catkin":
			img = _ball(7, Color(1.0, 0.99, 0.95), Color(0.90, 0.88, 0.82), 0.55)
		"leaf":
			img = _leaf(9, 6)
	img.generate_mipmaps()
	_tex[k] = ImageTexture.create_from_image(img)
	return _tex[k]


## 雨丝：宽 w、长 h（世界像素）。横着是高斯一样的软边，竖着上淡下浓、末端收尖
func _streak(w: int, h: int) -> Image:
	var W := int(w * SS)
	var H := int(h * SS)
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var body := Color(0.80, 0.88, 0.96)
	var hi := Color(1.0, 1.0, 1.0)
	for y in H:
		var v := (float(y) + 0.5) / float(H)
		var along := smoothstep(0.0, 0.75, v) * (1.0 - smoothstep(0.9, 1.0, v))
		for x in W:
			var u := ((float(x) + 0.5) / float(W) - 0.5) * 2.0
			var across := exp(-u * u * 4.0)
			var c := body.lerp(hi, exp(-u * u * 18.0) * 0.8)
			img.set_pixel(x, y, Color(c, across * along))
	return img


## 小球：半径 r（世界像素）。lit 被照亮的一面，shade 背光的一面；fuzz > 0 边更虚、带一点绒毛的起伏
func _ball(r: int, lit: Color, shade: Color, fuzz: float) -> Image:
	var R := r * SS
	var n := int(ceil(R)) * 2 + 2
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(lit, 0.0))  # 透明处也填上本色：线性过滤、mipmap 时边上不起黑圈
	var c0 := Vector2(n, n) * 0.5
	var sun := Vector3(-0.5, -0.6, 0.62).normalized()  # 光从左上前方来（和渲染底图的太阳同一边）
	for y in n:
		for x in n:
			var q := (Vector2(x + 0.5, y + 0.5) - c0) / R
			var d := q.length()
			if fuzz > 0.0:
				d *= 1.0 + fuzz * 0.12 * sin(atan2(q.y, q.x) * 9.0 + d * 6.0)
			var a := 1.0 - smoothstep(0.55 - fuzz * 0.25, 1.0, d)
			if a <= 0.001:
				continue
			var dz := sqrt(maxf(0.0, 1.0 - minf(d, 1.0) * minf(d, 1.0)))
			var nrm := Vector3(q.x, q.y, dz).normalized()
			var k := clampf(nrm.dot(sun) * 0.5 + 0.5, 0.0, 1.0)
			k = lerpf(k, 0.75, fuzz)
			var col := shade.lerp(lit, k)
			# 一小点高光（棉球、冰晶反光），绒毛没有
			var spec := pow(maxf(0.0, nrm.dot(sun)), 12.0) * (1.0 - fuzz)
			col = col.lerp(Color.WHITE, spec * 0.6)
			img.set_pixel(x, y, Color(col, a * (1.0 - fuzz * 0.25)))
	return img


## 叶子：半长 hl、半宽 hw（世界像素），白色打底（颜色由 color_initial_ramp 染），一边亮一边暗、一条叶脉
func _leaf(hl: int, hw: int) -> Image:
	var L := hl * SS
	var Wd := hw * SS
	var nx := int(L * 2.0) + 2
	var ny := int(Wd * 2.0) + 2
	var img := Image.create(nx, ny, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.85, 0.85, 0.85, 0.0))
	for y in ny:
		for x in nx:
			var u := (float(x) + 0.5 - nx * 0.5) / L            # -1 ~ 1，叶柄到叶尖
			var v := (float(y) + 0.5 - ny * 0.5) / Wd
			var half := (1.0 - u * u) * (1.0 - 0.25 * u)         # 叶子这一处有多宽（靠叶柄胖一点）
			if half <= 0.0:
				continue
			var e := absf(v) / half
			var a := 1.0 - smoothstep(0.82, 1.0, e)
			if a <= 0.001:
				continue
			var lightk := 0.82 + 0.18 * (-v / maxf(half, 0.05))  # 上半片亮、下半片暗（卷起来）
			lightk *= 1.0 - 0.18 * smoothstep(0.6, 1.0, e)       # 边上暗一点，有厚度
			var vein := 1.0 - (1.0 - smoothstep(0.0, 0.09, absf(v))) * 0.22 * (1.0 - smoothstep(0.7, 1.0, u))
			var g := clampf(lightk * vein, 0.0, 1.0)
			img.set_pixel(x, y, Color(g, g, g, a))
	return img
