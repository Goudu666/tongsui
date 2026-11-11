extends Node2D
## 一张横图的画，从后往前五层（都在这张图自己的坐标里，x 0~width、y TOP~BOTTOM）：
##   天   shaders/sky.gdshader：网点的天，太阳、晚霞、星星月亮、会走的云（不占贴图）
##   远景 res://art/layers/far_<年代>.png：远处的城，随人生阶段长高；视差 FAR_PARALLAX
##   中景 res://art/layers/mid_<年代>.png：隔一两条街的屋顶；视差 MID_PARALLAX
##   底图 res://art/scenes/<图>_<k>.png：tools/art/scenes.py 印的切片，天的地方是透明的
##   树   res://art/layers/tree_<种>_<季>.png：anchors.json 里每棵树的位置，按季节换、随风晃
## 远景、中景夜里自己点灯（far_layer.gdshader），所以夜版在天上只印一层薄的（scene_mask 告诉夜版哪儿是天）。
## 没有切片的图（还没画的），按 content/maps/<图>.yaml 的地点和地面画一张墨线草图。
## 只画眼前这一张图（换图时 show_scene），别的图不占显存。

const P := preload("res://scripts/ui/palette.gd")
const SKY_SHADER := preload("res://shaders/sky.gdshader")
const LAYER_SHADER := preload("res://shaders/far_layer.gdshader")
const SWAY_SHADER := preload("res://shaders/sway.gdshader")
const FORE_SHADER := preload("res://shaders/fore_dof.gdshader")
const SLICE := 1024.0   ## 每片多宽（世界像素）
const TOP := -200.0     ## 切片从这张图的 y = TOP 画起（楼顶上头还有一截天）
const BOTTOM := 1000.0
const ART_SCALE := 1.25
const MASK_STEP := 4.0  ## scene_mask 一格 = 4 世界像素
const FAR_PARALLAX := 0.1
const MID_PARALLAX := 0.32
const FAR_SCALE := 0.62   ## 远景条缩小了贴：远处的楼小
const MID_SCALE := 0.9
const FORE_PARALLAX := 1.55 ## 前景：比人走得快（贴着镜头）
const FORE_SCALE := 1.8     ## 前景放大贴：离镜头近，东西大、虚（fore_dof.gdshader）
const FORE := {"street": "street", "river": "river", "park": "green", "newhome": "green", "primary": "school",
	"middle": "school", "across": "street", "away": "street", "market": "market", "seaside": "sea", "village": "field"}
const ERAS := {"childhood": "child", "teen": "teen", "young": "young", "middle": "middle", "old": "old"}
## 树：画布多大（世界像素）、画的是多高的树（anchors 里的 h 按它缩放），和 tools/art/layers.py 的 TREES 一致
const TREES := {"huai": [620, 700, 620], "willow": [640, 680, 580], "young": [300, 380, 320]}
const TREE_SCALE := 1.25
## 每张图的远景、中景放在哪（楼脚的 y，这张图自己的坐标）；null = 这张图不要这一层
## 没写的图用 anchors 里记的地平线：远景楼脚在地平线，中景楼脚压在地面线上头一点（反正被近处的楼挡着）
## far_kind：远景不用城里那几条（按年代长高的楼），换成 far_<kind>.png（海边的岬角和货轮、乡下的杨树行和水塔），不随年代变；
## far_scale / far_haze：这一层贴多大、多淡
const LAYOUT := {
	"building": {"far": 300.0, "mid": 330.0},
	"street": {"far": 420.0, "mid": 640.0},
	"river": {"far": 560.0, "mid": 590.0, "mid_haze": 0.42},
	"primary": {"far": 560.0, "mid": 680.0},
	"middle": {"far": 520.0, "mid": 660.0},
	"across": {"far": 480.0, "mid": 640.0},
	"away": {"far": 520.0, "mid": 650.0},
	"rental": {"far": 300.0, "mid": null},
	"newhome": {"far": 500.0, "mid": 620.0},
	"park": {"far": 560.0, "mid": 640.0, "mid_haze": 0.35},
	"hospital": {"far": 300.0, "mid": null},
	"market": {"far": 400.0, "mid": 470.0},
	"seaside": {"far": 610.0, "mid": null, "far_kind": "sea", "far_scale": 0.8, "far_haze": 0.34},
	"village": {"far": 570.0, "mid": null, "far_kind": "village", "far_scale": 0.8, "far_haze": 0.32},
}

var scene: Dictionary = {}
var zones: Array = []     ## 这张图上的地点（content.map.zones 里 scene 是它的）
var exits: Array = []
var has_art := false
var stage := "childhood"
var season := "spring"
var _slices: Array = []
var _trees: Array = []
var _sky: Sprite2D
var _far: Sprite2D
var _mid: Sprite2D
var _fore: Sprite2D
var _sky_mat: ShaderMaterial
var _far_mat: ShaderMaterial
var _mid_mat: ShaderMaterial
var _fore_mat: ShaderMaterial
var _horizon := 760.0
var _time := Vector3.ZERO  ## night, dusk, dawn
var _day_t := 0.3
var overcast := 0.0
static var _anchors: Dictionary = {}  ## anchors.json 里每张图的灯、树、地平线（只读一回）
const LIGHT_KINDS := ["street_lamp", "stall_light", "window_light", "hall_lamp", "far_light"]


func _ready() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	_sky = _quad(_sky_mat)
	_sky.z_index = -3
	add_child(_sky)
	_far_mat = _layer_mat(0.0)
	_far = _strip(_far_mat, -2)
	_far_mat.set_shader_parameter("blur", 1.1)
	_mid_mat = _layer_mat(7.0)
	_mid_mat.set_shader_parameter("blur", 0.5)
	_mid = _strip(_mid_mat, -1)
	_fore_mat = ShaderMaterial.new()
	_fore_mat.shader = FORE_SHADER
	_fore = _strip(_fore_mat, 0)
	_fore.z_as_relative = false
	_fore.z_index = 69  ## 在光与空气（atmos 68）上面：不进倒影、不被调色压两遍；夜色自己在 fore_dof 里压


func _quad(mat: ShaderMaterial) -> Sprite2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var s := Sprite2D.new()
	s.texture = ImageTexture.create_from_image(img)
	s.centered = false
	s.material = mat
	return s


func _layer_mat(seed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LAYER_SHADER
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("haze_col", Color(0.90, 0.92, 0.88))
	return m


func _strip(mat: ShaderMaterial, z: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.region_enabled = true
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.material = mat
	s.z_index = z
	add_child(s)
	return s


func show_scene(sc: Dictionary, all_zones: Array, all_exits: Array) -> void:
	scene = sc
	zones = all_zones.filter(func(z): return str(z.scene) == str(sc.id))
	exits = all_exits.filter(func(e): return str(e.scene) == str(sc.id))
	position = Vector2(0, float(sc.top))
	for s in _slices:
		s.queue_free()
	_slices.clear()
	has_art = false
	var k := 0
	while true:
		var path := "res://art/scenes/%s_%d.png" % [sc.id, k]
		if not ResourceLoader.exists(path):
			break
		var spr := Sprite2D.new()
		spr.texture = load(path)
		spr.centered = false
		spr.scale = Vector2.ONE / ART_SCALE
		spr.position = Vector2(k * SLICE, TOP)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(spr)
		_slices.append(spr)
		has_art = true
		k += 1
	var w := float(sc.get("width", 1920))
	var layer: Dictionary = _raw(str(sc.id)).get("layer", {})
	_horizon = float(layer.get("horizon", float(sc.floors[0]) - float(sc.top)))
	_sky.position = Vector2(-200, TOP)
	_sky.scale = Vector2(w + 400, BOTTOM - TOP)
	_sky_mat.set_shader_parameter("size", _sky.scale)
	_sky_mat.set_shader_parameter("horizon", _horizon - TOP)
	_sky.visible = has_art
	_set_layers()
	_plant_trees()
	_set_fore()
	queue_redraw()


func _set_fore() -> void:
	var kind := str(FORE.get(str(scene.get("id", "")), ""))
	var path := "res://art/layers/fore_%s.png" % kind
	if kind == "" or not has_art or not ResourceLoader.exists(path):
		_fore.visible = false
		return
	_fore.visible = true
	_fore.texture = load(path)
	var floors: Array = scene.floors
	var h := _fore.texture.get_height()
	var fs := FORE_SCALE * (0.75 if kind == "river" else 1.0)  ## 河边的栏杆放太大像一根横梁
	_fore.scale = Vector2.ONE * fs
	_fore_mat.set_shader_parameter("tex_px", _fore.texture.get_size())
	# 底边压在镜头下沿再往下一点：东西只露出上半截
	_fore.position.y = float(floors[-1]) - float(scene.top) + (390.0 if kind == "river" else 300.0) - h * fs
	_fore.set_meta("h", h)


## 这张图上的灯（路灯、窗、楼道灯、摊子、远处）：坐标换成夜版自己的（从 TOP 那一行算起）
static func anchors_for(id: String) -> Dictionary:
	var out := {}
	var src: Dictionary = _raw(id)
	for kind in src:
		if not kind in LIGHT_KINDS:
			continue
		var pts: Array = []
		for p in src[kind]:
			pts.append(Vector2(float(p[0]), float(p[1]) - TOP))
		out[kind] = pts
	return out


static func _raw(id: String) -> Dictionary:
	if _anchors.is_empty():
		var f := FileAccess.open("res://art/scenes/anchors.json", FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_anchors = d.get("scenes", {})
	return _anchors.get(id, {})


## 哪儿是天（夜版用）：底图切片的透明度缩成 1/4，一张灰度图，白 = 实的
static func scene_mask(id: String) -> Texture2D:
	var path := "res://art/scenes/%s_mask.png" % id
	return load(path) if ResourceLoader.exists(path) else null


## 这张图在世界坐标里能看见的那一截
func band() -> Rect2:
	return Rect2(0, float(scene.get("top", 0)) + TOP, float(scene.get("width", 1920)), BOTTOM - TOP)


func set_stage(p_stage: String) -> void:
	if p_stage == stage and _far.texture != null:
		return
	stage = p_stage
	_set_layers()


func set_season(p_season: String) -> void:
	if p_season == season:
		return
	season = p_season
	_plant_trees()


## 钟点：夜、晚霞、清早各多深（print_light 算好的），白天走到哪儿了
func set_time(night: float, dusk: float, dawn: float, minute: float) -> void:
	_time = Vector3(night, dusk, dawn)
	_day_t = clampf((minute - 390.0) / (1110.0 - 390.0), 0.0, 1.0)
	_fore_mat.set_shader_parameter("night", night)
	for m in [_far_mat, _mid_mat]:
		m.set_shader_parameter("night", night)
		m.set_shader_parameter("dusk", dusk)
		m.set_shader_parameter("dawn", dawn)
	_sky_mat.set_shader_parameter("night", night)
	_sky_mat.set_shader_parameter("dusk", dusk)
	_sky_mat.set_shader_parameter("dawn", dawn)
	_sky_mat.set_shader_parameter("day_t", _day_t)
	# 远处的楼傍晚发暖、夜里发蓝：空气透视的颜色跟着天走
	var hz := Color(0.90, 0.92, 0.88).lerp(Color(0.97, 0.80, 0.66), dusk * 0.8).lerp(Color(0.80, 0.83, 0.90), night * 0.6)
	_far_mat.set_shader_parameter("haze_col", hz)
	_mid_mat.set_shader_parameter("haze_col", hz)


## 太阳在世界里的位置（和 sky.gdshader 里算的一样）：光与空气那一层（atmos.gd）从这儿打光柱
func sun_world() -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Vector2.ZERO
	var center := cam.get_screen_center_position() - position
	var view := get_viewport_rect().size / cam.zoom
	var top := center.y - view.y * 0.5
	var sx := center.x + view.x * lerpf(-0.34, 0.34, _day_t)
	var sy := lerpf(top + view.y * 0.12, _horizon - 40.0, pow(absf(_day_t - 0.5) * 2.0, 1.6))
	sy = lerpf(sy, _horizon - 70.0, _time.y)
	return position + Vector2(sx, sy)


## 远景楼脚（地平线）在世界里的 y
func horizon_world() -> float:
	return position.y + _horizon


func set_overcast(v: float) -> void:
	overcast = v
	_sky_mat.set_shader_parameter("overcast", v)


func _set_layers() -> void:
	if scene.is_empty():
		return
	var era := str(ERAS.get(stage, "child"))
	var lay: Dictionary = LAYOUT.get(str(scene.id), {})
	for pair in [[_far, _far_mat, "far", 0.42, FAR_SCALE], [_mid, _mid_mat, "mid", 0.12, MID_SCALE]]:
		var spr: Sprite2D = pair[0]
		var mat: ShaderMaterial = pair[1]
		var kind: String = pair[2]
		var suffix := str(lay.get(kind + "_kind", era))
		var path := "res://art/layers/%s_%s.png" % [kind, suffix]
		var base: Variant = lay.get(kind, _horizon if kind == "far" else _horizon + 60.0)
		if base == null or not has_art or not ResourceLoader.exists(path):
			spr.visible = false
			continue
		spr.visible = true
		spr.texture = load(path)
		var lit := "res://art/layers/%s_%s_lit.png" % [kind, suffix]
		if ResourceLoader.exists(lit):
			mat.set_shader_parameter("lit_tex", load(lit))
		var tsize := spr.texture.get_size()
		mat.set_shader_parameter("tex_size", tsize)
		mat.set_shader_parameter("haze", float(lay.get(kind + "_haze", pair[3])))
		var sc: float = float(lay.get(kind + "_scale", pair[4]))
		spr.scale = Vector2(sc, sc)
		spr.position.y = float(base) - tsize.y * sc
		spr.set_meta("h", tsize.y)


func _plant_trees() -> void:
	for t in _trees:
		t.queue_free()
	_trees.clear()
	if scene.is_empty() or not has_art:
		return
	var i := 0
	for a in _raw(str(scene.id)).get("trees", []):
		var kind := str(a[4])
		if not TREES.has(kind):
			continue
		var path := "res://art/layers/tree_%s_%s.png" % [kind, season]
		if not ResourceLoader.exists(path):
			continue
		var spec: Array = TREES[kind]
		var s := Sprite2D.new()
		s.texture = load(path)
		s.centered = false
		var k := float(a[2]) / float(spec[2])
		s.scale = Vector2.ONE * k / TREE_SCALE
		s.position = Vector2(float(a[0]) - float(spec[0]) * k * 0.5, float(a[1]) - float(spec[1]) * k)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var m := ShaderMaterial.new()
		m.shader = SWAY_SHADER
		m.set_shader_parameter("phase", float(a[0]) * 0.013 + i * 1.7)
		m.set_shader_parameter("amp", 7.0 if kind != "young" else 4.0)
		m.set_shader_parameter("strands", 1.0 if kind == "willow" else 0.0)
		m.set_shader_parameter("tex_px", s.texture.get_size())
		s.material = m
		s.z_index = 1
		add_child(s)
		_trees.append(s)
		i += 1


func _process(_delta: float) -> void:
	if scene.is_empty() or not has_art:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var center := cam.get_screen_center_position() - position
	var view := get_viewport_rect().size / cam.zoom
	_sky_mat.set_shader_parameter("cam", center - Vector2(-200, TOP))
	_sky_mat.set_shader_parameter("view", view)
	var left := center.x - view.x * 0.5
	for pair in [[_far, FAR_PARALLAX], [_mid, MID_PARALLAX], [_fore, FORE_PARALLAX]]:
		var spr: Sprite2D = pair[0]
		if not spr.visible or spr.texture == null:
			continue
		# 视差：镜头挪 1，这一层只挪 f；平铺够盖满镜头就行
		var f: float = pair[1]
		var tw := spr.texture.get_width() * spr.scale.x  ## 一张贴图在世界里多宽
		var start := left * f
		spr.position.x = left - start + floorf(start / tw) * tw - 64.0
		var need := (view.x + tw + 128.0) / spr.scale.x
		spr.region_rect = Rect2(0, 0, need, float(spr.get_meta("h", spr.texture.get_height())))


func _draw() -> void:
	if scene.is_empty() or has_art:
		return
	var f := P.font()
	var w := float(scene.width)
	var floors: Array = scene.floors
	var top := float(scene.top)
	# 纸、远处一抹天际线
	draw_rect(Rect2(0, TOP, w, BOTTOM - TOP), P.PAPER)
	var x := 0.0
	var i := 0
	while x < w:
		var h := 120.0 + fmod(i * 73.0, 160.0)
		draw_rect(Rect2(x, float(floors[0]) - top - 380.0 - h * 0.4, 90.0 + fmod(i * 41.0, 80.0), h), Color(P.QING, 0.08))
		x += 150.0 + fmod(i * 29.0, 70.0)
		i += 1
	for fy in floors:
		var y := float(fy) - top
		draw_rect(Rect2(0, y, w, 26.0), Color(P.INK, 0.10))
		draw_line(Vector2(0, y), Vector2(w, y), P.INK, 4.0)
	for z in zones:
		var y := float(floors[int(z.floor)]) - top
		var r := Rect2(float(z.span[0]), y - 360.0, float(z.span[1]) - float(z.span[0]), 360.0)
		if z.has("owner"):
			draw_rect(r, Color(P.role_color(str(z.owner)), 0.07))
		var e := 10.0
		draw_line(Vector2(r.position.x, r.position.y - e), Vector2(r.position.x, r.end.y), Color(P.INK, 0.7), 3.0)
		draw_line(Vector2(r.end.x, r.position.y - e), Vector2(r.end.x, r.end.y), Color(P.INK, 0.7), 3.0)
		draw_line(Vector2(r.position.x - e, r.position.y), Vector2(r.end.x + e, r.position.y), Color(P.INK, 0.7), 3.0)
		draw_string(f, r.position + Vector2(24, 52), str(z.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 38, P.INK_SOFT)
	for ex in exits:
		var at := Vector2(float(ex.at[0]), float(ex.at[1]) - top)
		draw_rect(Rect2(at + Vector2(-46, -200), Vector2(92, 200)), Color(P.INK, 0.12))
		draw_rect(Rect2(at + Vector2(-46, -200), Vector2(92, 200)), P.INK, false, 3.0)
