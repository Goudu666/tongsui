extends Node2D
## 夜色：昼夜不靠"整屏调暗"，而是像把模型桌上的顶灯关掉、只留模型里的小灯（shaders/night_plate.gdshader 压蓝紫、
## 灯下留出暖黄的光池；shaders/lamp_glow.gdshader 往上加灯晕）。
## 这里负责三件事：
##   1. 把 anchors.json 里的灯（路灯、楼道灯、窗、摊子、对岸）烘成一张低分辨率灯光图
##   2. 按时钟算出 晚霞 / 夜 / 清早 三块版各印多深
##   3. 把两个人的位置喂给着色器，夜里各带一小圈光
## 盖在叠印层和鸽子上面（z 65）、互动点标记下面（z 70）。

const P := preload("res://scripts/ui/palette.gd")
const SHADER := preload("res://shaders/night_plate.gdshader")
const GLOW := preload("res://shaders/lamp_glow.gdshader")
const BAKE_STEP := 8.0  ## 灯光图一格 = 8 世界像素
## 每种灯：照多远（世界像素）、多亮
const LAMPS := {
	"street_lamp": [250.0, 1.0],
	"stall_light": [190.0, 0.95],
	"window_light": [170.0, 0.9],
	"hall_lamp": [150.0, 0.85],
	"far_light": [34.0, 0.9],
}
## 人生阶段 → 纸有多旧
const STAGE_AGE := {"childhood": 0.0, "teen": 0.12, "young": 0.26, "middle": 0.5, "old": 0.85}

var map_size := Vector2(2400, 1600)
var actors: Array = []  ## 最多两个 Node2D
var minute := 390.0
var night := 0.0
var _mat: ShaderMaterial
var _quad: Sprite2D
var _glow: Sprite2D        ## 灯晕：同一张灯光图往上加暖光（夜版只能压暗）
var _glow_mat: ShaderMaterial
var wet := 0.0             ## 雨雪天：晕大一点（weather 设）
var _dusk := 0.0
var _dawn := 0.0
var _age := 0.0
var _age_target := 0.0


func setup(size: Vector2, anchors: Dictionary) -> void:
	map_size = size
	z_index = 65
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("map_size", map_size)
	_mat.set_shader_parameter("light_map", _bake(anchors))
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_quad = Sprite2D.new()
	_quad.texture = ImageTexture.create_from_image(img)
	_quad.centered = false
	_quad.scale = map_size
	_quad.material = _mat
	add_child(_quad)
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = GLOW
	_glow = Sprite2D.new()
	_glow.texture = _quad.texture
	_glow.centered = false
	_glow.scale = map_size
	_glow.material = _glow_mat
	add_child(_glow)
	_glow_mat.set_shader_parameter("light_map", _mat.get_shader_parameter("light_map"))
	_glow_mat.set_shader_parameter("map_size", map_size)
	set_minute(minute)


## 换一张图：纸的大小和灯都换成那张图的（横版一张图一套灯）。mask：哪儿是天（scene_art.scene_mask），没有就整张都印
func relight(size: Vector2, anchors: Dictionary, mask: Texture2D = null) -> void:
	map_size = size
	_mat.set_shader_parameter("map_size", map_size)
	var lm := _bake(anchors)
	_mat.set_shader_parameter("light_map", lm)
	_glow_mat.set_shader_parameter("light_map", lm)
	_glow_mat.set_shader_parameter("map_size", map_size)
	_glow.scale = map_size
	_mat.set_shader_parameter("scene_mask", mask)
	_mat.set_shader_parameter("use_mask", mask != null)
	_quad.scale = map_size


## 晚霞、清早各印多深（scene_art 的天和远景跟着它变）
func dusk() -> float:
	return _dusk


func dawn() -> float:
	return _dawn


## 把所有灯烘成一张灰度图：每盏灯只画自己照得到的那一小块，叠加用"滤色"
func _bake(anchors: Dictionary) -> ImageTexture:
	var w := int(ceil(map_size.x / BAKE_STEP))
	var h := int(ceil(map_size.y / BAKE_STEP))
	var data := PackedFloat32Array()
	data.resize(w * h)
	for kind in LAMPS:
		var radius: float = LAMPS[kind][0] / BAKE_STEP
		var power: float = LAMPS[kind][1]
		for p in anchors.get(kind, []):
			var cx := float(p.x) / BAKE_STEP
			var cy := float(p.y) / BAKE_STEP
			for y in range(maxi(0, int(cy - radius)), mini(h, int(cy + radius) + 1)):
				for x in range(maxi(0, int(cx - radius)), mini(w, int(cx + radius) + 1)):
					var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length() / radius
					if d >= 1.0:
						continue
					var v := power * (1.0 - smoothstep(0.0, 1.0, d))
					var i := y * w + x
					data[i] = 1.0 - (1.0 - data[i]) * (1.0 - v)
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for i in w * h:
		bytes[i] = int(clampf(data[i], 0.0, 1.0) * 255.0)
	return ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_L8, bytes))


## 时钟（分钟）→ 三块版的深浅
func set_minute(m: float) -> void:
	minute = m
	night = smoothstep(1090.0, 1200.0, m) if m >= 390.0 else 1.0
	_dusk = smoothstep(990.0, 1105.0, m) * (1.0 - smoothstep(1130.0, 1210.0, m))
	_dawn = 1.0 - smoothstep(390.0, 500.0, m) if m >= 390.0 else 0.0
	if _glow_mat != null:
		_glow_mat.set_shader_parameter("night", night)
		_glow_mat.set_shader_parameter("wet", wet)
	if _mat != null:
		_mat.set_shader_parameter("night", night)
		_mat.set_shader_parameter("dusk", _dusk)
		_mat.set_shader_parameter("dawn", _dawn)


func set_stage(stage: String, instant := false) -> void:
	_age_target = float(STAGE_AGE.get(stage, 0.0))
	if instant:
		_age = _age_target
		_mat.set_shader_parameter("age", _age)


func _process(delta: float) -> void:
	if _mat == null:
		return
	# 大白天、纸也是新的：什么都不用印，整块版收起来，省一次全屏绘制
	_glow.visible = night > 0.001
	_quad.visible = night > 0.001 or _dusk > 0.001 or _dawn > 0.001 or _age > 0.001 or _age_target > 0.001
	if not is_equal_approx(_age, _age_target):
		_age = move_toward(_age, _age_target, delta * 0.25)
		_mat.set_shader_parameter("age", _age)
	var keys := ["actor_a", "actor_b"]
	for i in 2:
		var v := Vector4.ZERO
		if i < actors.size() and is_instance_valid(actors[i]) and (actors[i] as Node2D).visible:
			var a: Node2D = actors[i]
			v = Vector4(a.position.x - position.x, a.position.y - position.y - 40.0, 150.0, 0.8)
		_mat.set_shader_parameter(keys[i], v)
