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
	_p.color = Color.WHITE
	_p.angle_min = 0.0
	_p.angle_max = 0.0
	_p.angular_velocity_min = 0.0
	_p.angular_velocity_max = 0.0
	_p.scale_amount_min = 1.0
	_p.scale_amount_max = 1.0
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
			_p.color = Color(1, 1, 1, 0.55)
		"snow":
			_p.amount = 180
			_p.lifetime = 9.0
			_p.gravity = Vector2(0, 14)
			_p.direction = Vector2(0.15, 1.0)
			_p.spread = 25.0
			_p.initial_velocity_min = 50.0
			_p.initial_velocity_max = 90.0
			_p.scale_amount_min = 0.5
			_p.scale_amount_max = 1.25
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
			_p.scale_amount_min = 0.6
			_p.scale_amount_max = 1.1
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
			_p.scale_amount_min = 0.7
			_p.scale_amount_max = 1.2
			_p.tangential_accel_min = -20.0
			_p.tangential_accel_max = 20.0
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


## 粒子的样子：现画一张小图（孔版的颜色）
func _texture(k: String) -> Texture2D:
	if _tex.has(k):
		return _tex[k]
	var img: Image
	match k:
		"rain":
			img = Image.create(3, 34, false, Image.FORMAT_RGBA8)
			for y in 34:
				var a := 0.25 + 0.75 * float(y) / 33.0
				img.set_pixel(1, y, Color(P.QING.darkened(0.1), a))
				img.set_pixel(0, y, Color(P.QING, a * 0.3))
		"snow":
			img = _disc(9, P.PAPER, Color(P.INK, 0.55))
		"catkin":
			img = _disc(7, Color(P.PAPER, 0.95), Color(P.INK_SOFT, 0.45), true)
		"leaf":
			img = Image.create(14, 9, false, Image.FORMAT_RGBA8)
			for y in 9:
				for x in 14:
					var u := (float(x) - 6.5) / 6.5
					var v := (float(y) - 4.0) / (4.0 * (1.0 - u * u) + 0.01)
					if absf(v) <= 1.0:
						img.set_pixel(x, y, P.MEI if (x + y) % 5 != 0 else P.QING)
	_tex[k] = ImageTexture.create_from_image(img)
	return _tex[k]


func _disc(r: int, fill: Color, rim: Color, fuzzy := false) -> Image:
	var n := r * 2 + 1
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - r, y - r).length() / float(r)
			if fuzzy:
				d += 0.25 * sin(atan2(y - r, x - r) * 7.0)
			if d <= 0.72:
				img.set_pixel(x, y, fill)
			elif d <= 1.0:
				img.set_pixel(x, y, rim)
	return img
