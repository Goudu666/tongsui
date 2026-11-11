extends Node2D
## 光与空气：画印好了，最后在镜头前面罩一层（shaders/grade.gdshader）。
## 孔版的四块版管「印什么」，这一层管「那天的光和空气」：分色调、亮处的晕、太阳那边的光柱和光里的尘、
## 清早和雨天的地气、四边压角。跟着镜头走，盖在夜版（z 65）上面、互动点（z 70）下面。
## 只是画面，不进结算。enabled = false 整层收起来（省一次全屏读屏幕）。

const SHADER := preload("res://shaders/grade.gdshader")
const INDOOR := ["building", "rental", "hospital"]
## 地面线往下是马路的图：下雨时映出倒影（河边是堤岸、公园是草，不映）
const ROAD := ["street", "across", "away", "newhome", "primary", "middle"]

var art = null    ## scene_art：太阳在哪、地平线、阴天
var light = null  ## print_light：夜、晚霞、清早
var subject: Node2D = null  ## 我（world_view.me()）：压角围着人
var enabled := true
var _mat: ShaderMaterial
var _quad: Sprite2D
var _indoor := 0.0
var _road := 0.0
var _ground := 760.0  ## 这张图最下一层地面（世界 y）


func _ready() -> void:
	z_index = 68
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_quad = Sprite2D.new()
	_quad.texture = ImageTexture.create_from_image(img)
	_quad.centered = false
	_quad.material = _mat
	add_child(_quad)


func set_scene(sc: Dictionary) -> void:
	_indoor = 1.0 if str(sc.get("id", "")) in INDOOR else 0.0
	var floors: Array = sc.get("floors", [760])
	_ground = float(floors[-1])
	_mat.set_shader_parameter("indoor", _indoor)
	_road = 1.0 if str(sc.get("id", "")) in ROAD else 0.0


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	_quad.visible = enabled and cam != null and art != null and art.has_art
	if not _quad.visible:
		return
	var center := cam.get_screen_center_position()
	var view := get_viewport_rect().size / cam.zoom
	var tl := center - view * 0.5
	# 多盖一圈：镜头平滑移动时边上不漏
	_quad.position = tl - Vector2(8, 8)
	_quad.scale = view + Vector2(16, 16)
	var to_uv := func(p: Vector2) -> Vector2: return (p - tl) / view
	_mat.set_shader_parameter("cam", center)
	_mat.set_shader_parameter("view_h", view.y)
	_mat.set_shader_parameter("sun", to_uv.call(art.sun_world()))
	_mat.set_shader_parameter("ground", to_uv.call(Vector2(0, _ground)).y)
	_mat.set_shader_parameter("horizon", to_uv.call(Vector2(0, art.horizon_world())).y)
	_mat.set_shader_parameter("overcast", art.overcast)
	if subject != null and is_instance_valid(subject):
		var f: Vector2 = to_uv.call(subject.position + Vector2(0, -90))
		_mat.set_shader_parameter("focus", f.clamp(Vector2(0.15, 0.2), Vector2(0.85, 0.85)))
	if light != null:
		_mat.set_shader_parameter("night", light.night)
		_mat.set_shader_parameter("dusk", light.dusk())
		_mat.set_shader_parameter("dawn", light.dawn())
		_mat.set_shader_parameter("wet", light.wet * _road)
