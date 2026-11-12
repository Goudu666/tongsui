extends CanvasLayer
## 实时 3D 的舞台：把一张横版图换成真的 3D 场景，人换成 3D 小人，其余（互动点、名字牌、气泡、HUD、雨雪）还是 2D 画在上头。
##
## 怎么和 2D 对上：2D 的世界坐标 1 像素 = 1 厘米。3D 里 X = x / 100，Y = (这张图最下一层地面 − y) / 100，人走的那条线是 Z = 0。
## 镜头是「移轴镜头」：相机抬高 LIFT 米、镜头平着朝 -Z 看，再把取景框往下平移（frustum_offset），
## 于是 Z = 0 这个面上的东西和 2D 镜头（Camera2D）看到的世界矩形逐像素重合——2D 的点位、名字牌、气泡照旧对得上人；
## 同时人眼比街面高，看得见人行道的进深、桌面、地上的影子，前面的东西大、后面的楼小，是真透视。
##
## 画面：SubViewport 里实时渲染（真阴影、天光、雾、夜里路灯和亮窗），再缩一张四分之一的糊图，
## 最后 post3d.gdshader 合成：移轴虚化（只有人站的那一条清楚）、灯晕、调色、暗角、颗粒。
## 兼容渲染器（手机上最稳的那个）没有景深，所以虚化是自己做的；这也是为什么装在 CanvasLayer -1：在世界 2D 层底下。
##
## 哪张图有 3D：BUILDERS（现在只有楼下这条街，street3d.gd）。别的图照旧走 2D（scene_art.gd），一张一张往这里加。

const Figure := preload("res://scripts/world3d/figure3d.gd")
const Street3D := preload("res://scripts/world3d/street3d.gd")
const Kit := preload("res://scripts/world3d/kit3d.gd")
const BLUR := preload("res://shaders/3d/blur_down.gdshader")
const POST := preload("res://shaders/3d/post3d.gdshader")

const BUILDERS := {"street": Street3D}
const DIST := 15.0    ## 相机离人走的那条线多远（米）
const LIFT := 2.6     ## 相机比取景框中心高多少（米）：看得见地面的进深
const NEAR := 0.5
const FIG_SCALE := 1.2  ## 人比房子放大一点（微缩模型里人偶总是偏大，脸才看得清；2D 精灵放大 1.5）
## 总开关：关掉就全走 2D（单测、性能探针、对比截图用）
static var enabled := true
## 玩家在菜单里选的画面：auto 自动（开头几秒测帧时间，太卡就退回 2D）/ on 实时 3D / off 2D；"" 还没读设置
static var mode := ""
## 自动模式下测出来太卡、退回了 2D；记在设置里，下次打开也是 2D，菜单里再选一次「自动」或「实时 3D」就重试
static var auto_off := false
const VIDEO_CFG := "user://video.cfg"
const SLOW_MS := 45.0       ## 平均一帧超过这么久（不到 22 帧）算太卡
const WATCH_SKIP := 1.5     ## 刚搭好的头一秒半不算（编译 shader、建阴影图会卡一下）
const WATCH_LEN := 4.0      ## 量多久

signal fell_back            ## 自动模式测出太卡，刚退回 2D（world_view 换回 2D、提示一句）

var _watch_t := 0.0
var _watch_sum := 0.0
var _watch_n := 0
var _watched := false

var world: Node = null          ## world_view
var vp: SubViewport             ## 实时 3D
var soft_vp: SubViewport        ## 四分之一糊图
var out: TextureRect            ## 合成到屏幕
var post: ShaderMaterial
var root3d: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D    ## 只照人的补光（从镜头这边来，不投影）：夜里、逆光时脸不黑
const FIG_LAYER := 2            ## 人身上多一层渲染层，补光只照这一层
var env: Environment
var sky: ProceduralSkyMaterial
var set3d: Node3D = null        ## 眼前这张图的 3D（builder 搭出来的）
var scene_id := ""
var ground_y := 760.0           ## 这张图最下一层地面（世界 y）
var figures: Dictionary = {}    ## role -> Figure
var folk_figs: Dictionary = {}  ## 街坊、路人的 2D 节点 -> Figure
var minute := 480.0
var night := 0.0
var season := "spring"
var weather := ""
var look := "childhood"
var _ball: MeshInstance3D       ## 两人对踢的那个球
var _render_scale := 1.0
var _lamps: Array = []          ## [OmniLight3D, 在不在镜头附近]
var _lamp_on := 0.0             ## 路灯这会儿亮几成（天黑、阴雨）


func _init() -> void:
	layer = -1
	_render_scale = 0.8 if OS.has_feature("mobile") else 1.0
	_build_viewports()
	_build_world()
	visible = false
	set_process(false)


func _ready() -> void:
	_resize()
	get_viewport().size_changed.connect(_resize)


func _build_viewports() -> void:
	soft_vp = SubViewport.new()
	soft_vp.disable_3d = true
	soft_vp.transparent_bg = false
	soft_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(soft_vp)
	# 3D 的那个挂在糊图下面：子视口先画，糊图这一帧就拿得到新画面（不会拖一帧的影）
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X if OS.has_feature("mobile") else Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.positional_shadow_atlas_size = 1024
	soft_vp.add_child(vp)
	var down := TextureRect.new()
	down.texture = vp.get_texture()
	down.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	down.stretch_mode = TextureRect.STRETCH_SCALE
	down.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bm := ShaderMaterial.new()
	bm.shader = BLUR
	bm.set_shader_parameter("src", vp.get_texture())
	down.material = bm
	soft_vp.add_child(down)
	out = TextureRect.new()
	out.texture = vp.get_texture()
	out.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	out.stretch_mode = TextureRect.STRETCH_SCALE
	out.set_anchors_preset(Control.PRESET_FULL_RECT)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = ShaderMaterial.new()
	post.shader = POST
	post.set_shader_parameter("sharp", vp.get_texture())
	post.set_shader_parameter("soft", soft_vp.get_texture())
	out.material = post
	add_child(out)


func _resize() -> void:
	var px: Vector2 = Vector2(get_tree().root.size) if is_inside_tree() else Vector2(1920, 1080)
	if px.x < 16.0:
		px = Vector2(1920, 1080)
	var size := Vector2i((px * _render_scale).round())
	vp.size = size
	soft_vp.size = Vector2i(maxi(4, size.x / 4), maxi(4, size.y / 4))
	var bm: ShaderMaterial = (soft_vp.get_child(1) as TextureRect).material
	bm.set_shader_parameter("src_px", Vector2(1.0 / size.x, 1.0 / size.y))
	post.set_shader_parameter("soft_px", Vector2(1.0 / soft_vp.size.x, 1.0 / soft_vp.size.y))


func _build_world() -> void:
	# 全局参数 g_wet / g_snow / g_night 在 project.godot 的 [shader_globals] 里声明（运行时加会拖慢）
	root3d = Node3D.new()
	vp.add_child(root3d)
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	sky = ProceduralSkyMaterial.new()
	sky.sun_angle_max = 8.0
	sky.sun_curve = 0.08
	var sk := Sky.new()
	sk.sky_material = sky
	sk.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sk
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.003
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.12
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 42.0
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	root3d.add_child(sun)
	fill = DirectionalLight3D.new()
	fill.shadow_enabled = false
	fill.light_cull_mask = FIG_LAYER
	fill.light_specular = 0.2
	fill.rotation = Vector3(-0.35, 0.25, 0.0)  # 从镜头左上方一点照过来
	root3d.add_child(fill)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_FRUSTUM
	cam.near = NEAR
	cam.far = 260.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	root3d.add_child(cam)
	cam.current = true
	_ball = MeshInstance3D.new()
	_ball.mesh = Kit.ellipsoid(Vector3.ONE * 0.1, 16, 10)
	_ball.material_override = Kit.mat(Color("#F6F3EC"), 0.35)
	_ball.visible = false
	root3d.add_child(_ball)
	RenderingServer.directional_shadow_atlas_set_size(2048 if OS.has_feature("mobile") else 4096, true)


## 这张图有没有 3D
static func supports(id: String) -> bool:
	return want_3d() and BUILDERS.has(id)


## 照设置该不该开 3D
static func want_3d() -> bool:
	_load_mode()
	return enabled and (mode == "on" or (mode == "auto" and not auto_off))


static func _load_mode() -> void:
	if mode != "":
		return
	mode = "auto"
	var cf := ConfigFile.new()
	if cf.load(VIDEO_CFG) == OK:
		mode = str(cf.get_value("video", "mode", "auto"))
		auto_off = bool(cf.get_value("video", "auto_off", false))
	if not mode in ["auto", "on", "off"]:
		mode = "auto"


## 菜单里换画面（重新选一次就清掉「测出太卡」的记录，再给 3D 一次机会）；save = false 出图工具用，不写设置
static func set_mode(m: String, save := true) -> void:
	_load_mode()
	mode = m if m in ["auto", "on", "off"] else "auto"
	auto_off = false
	if save:
		_save_mode()


static func _save_mode() -> void:
	var cf := ConfigFile.new()
	cf.set_value("video", "mode", mode)
	cf.set_value("video", "auto_off", auto_off)
	cf.save(VIDEO_CFG)


## 自动模式：3D 开着的头几秒量平均帧时间，太卡就记下来、退回 2D（一次运行只量一回）
func _watch(delta: float) -> void:
	if _watched or mode != "auto" or auto_off:
		return
	_watch_t += delta
	if _watch_t < WATCH_SKIP:
		return
	_watch_sum += delta
	_watch_n += 1
	if _watch_t < WATCH_SKIP + WATCH_LEN:
		return
	_watched = true
	var avg := _watch_sum / maxf(1.0, float(_watch_n)) * 1000.0
	print("[3d] 开头 %.1f 秒平均一帧 %.1f ms" % [WATCH_LEN, avg])
	if avg > SLOW_MS:
		auto_off = true
		_save_mode()
		fell_back.emit()


## 换图：有 3D 的搭起来（同一张图不重搭），没有的整层藏起来、2D 接手
func show_scene(sc: Dictionary) -> void:
	var id := str(sc.get("id", ""))
	if not supports(id):
		_clear()
		visible = false
		set_process(false)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		soft_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	visible = true
	set_process(true)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	soft_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var floors: Array = sc.get("floors", [760])
	ground_y = float(floors[-1])
	if id == scene_id and set3d != null:
		return
	_clear()
	scene_id = id
	set3d = BUILDERS[id].new()
	root3d.add_child(set3d)
	set3d.build(sc, look, season)
	_lamps = set3d.lamps if "lamps" in set3d else []
	_apply_time()
	_apply_season()


func _clear() -> void:
	if set3d != null:
		set3d.queue_free()
		set3d = null
	scene_id = ""
	for f in folk_figs.values():
		f.queue_free()
	folk_figs.clear()


## 年代（街上的店招、空调、防盗窗）
func set_look(p_look: String) -> void:
	look = p_look
	if set3d != null and set3d.has_method("set_look"):
		set3d.set_look(look)


func set_season(p_season: String, p_weather: String) -> void:
	season = p_season
	weather = p_weather
	_apply_season()


func _apply_season() -> void:
	RenderingServer.global_shader_parameter_set("g_wet", 1.0 if weather == "rain" else 0.0)
	RenderingServer.global_shader_parameter_set("g_snow", 1.0 if weather == "snow" else (0.35 if season == "winter" else 0.0))
	if set3d != null and set3d.has_method("set_season"):
		set3d.set_season(season)
	_apply_time()


## 时钟：太阳从左边（东）升起、右边落下；傍晚暖、夜里月光冷，路灯、亮窗、店里的灯一盏盏亮
func set_time(p_minute: float, p_night: float) -> void:
	minute = p_minute
	night = p_night
	_apply_time()


func _apply_time() -> void:
	if sun == null:
		return
	var t := clampf((minute - 330.0) / (1170.0 - 330.0), 0.0, 1.0)  # 5:30 日出 ~ 19:30 日落
	var elev := sin(t * PI)
	var warm := 1.0 - smoothstep(0.0, 0.32, elev)  # 太阳低：暖
	var rain := 1.0 if weather == "rain" else 0.0
	var snow := 1.0 if weather == "snow" else 0.0
	var overcast := maxf(rain * 0.8, snow * 0.6)
	# 白天的太阳：从左前方到右前方划过去；夜里换成冷的月光，从右上方来
	var day_dir := Vector3(-cos(t * PI) * 0.9, -maxf(0.12, elev * 0.95), -0.55).normalized()
	var moon_dir := Vector3(0.45, -0.8, -0.4).normalized()
	var dir := day_dir.lerp(moon_dir, night).normalized()
	sun.look_at_from_position(Vector3.ZERO, dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.BACK)
	var day_col := Color(1.0, 0.96, 0.9).lerp(Color(1.0, 0.62, 0.36), warm)
	sun.light_color = day_col.lerp(Color(0.55, 0.65, 0.95), night)
	sun.light_energy = lerpf(lerpf(2.3, 1.3, warm) * (1.0 - overcast * 0.7), 0.18, night)
	sun.shadow_opacity = lerpf(1.0, 0.55, maxf(overcast, night))
	fill.light_color = Color(1.0, 0.93, 0.85).lerp(Color(1.0, 0.8, 0.62), night)  # 夜里像路灯、窗里透出来的暖光
	fill.light_energy = lerpf(0.18, 0.55, maxf(night, overcast * 0.6))
	# 天：白天蓝、傍晚橙紫、夜里深蓝；阴雨天灰
	var top := Color(0.32, 0.52, 0.82).lerp(Color(0.36, 0.38, 0.62), warm).lerp(Color(0.04, 0.06, 0.14), night)
	var hor := Color(0.78, 0.84, 0.9).lerp(Color(0.98, 0.62, 0.42), warm).lerp(Color(0.12, 0.13, 0.24), night)
	var grey := Color(0.56, 0.58, 0.62).lerp(Color(0.1, 0.11, 0.15), night)
	top = top.lerp(grey, overcast)
	hor = hor.lerp(grey.lightened(0.1), overcast)
	sky.sky_top_color = top
	sky.sky_horizon_color = hor
	sky.ground_horizon_color = hor.darkened(0.2)
	sky.ground_bottom_color = hor.darkened(0.6)
	sky.sun_angle_max = 8.0 if night < 0.5 else 2.0
	sky.sky_energy_multiplier = lerpf(1.0, 0.5, night)
	env.ambient_light_energy = lerpf(lerpf(0.5, 0.42, warm), 0.3, night) * (1.0 + overcast * 0.5)
	env.fog_light_color = hor.lerp(Color(0.1, 0.11, 0.18), night * 0.5)
	env.fog_density = 0.003 + overcast * 0.01
	env.tonemap_exposure = lerpf(0.95, 1.2, night)
	RenderingServer.global_shader_parameter_set("g_night", clampf(night * 1.15 + warm * 0.25 * (1.0 - night) + overcast * 0.2, 0.0, 1.0))
	_lamp_on = clampf((night - 0.15) / 0.45 + overcast * 0.4, 0.0, 1.0)
	_apply_lamps()
	if post != null:
		post.set_shader_parameter("gain", Color(1.0, 0.98, 0.95).lerp(Color(1.05, 0.95, 0.85), warm * (1.0 - night)).lerp(Color(0.9, 0.95, 1.08), night))
		post.set_shader_parameter("lift", Color(0.006, 0.004, 0.01).lerp(Color(0.0, 0.01, 0.03), night))
		post.set_shader_parameter("saturation", lerpf(1.06, 0.92, night) * (1.0 - overcast * 0.2))
		post.set_shader_parameter("bloom", lerpf(0.1, 0.45, night))
		post.set_shader_parameter("bloom_cut", lerpf(0.92, 0.6, night))


func _process(delta: float) -> void:
	if world == null or set3d == null:
		return
	_watch(delta)
	if set3d == null:  # 刚测出太卡、退回了 2D（fell_back 里已经把 3D 拆了）
		return
	_sync_camera()
	_sync_actors(delta)
	_sync_folks()
	if set3d.has_method("tick"):
		set3d.tick(delta, cam.global_position.x)
	_apply_lamps()


func _apply_lamps() -> void:
	for l in _lamps:
		var light: Light3D = l[0]
		var on := maxf(_lamp_on, float(light.get_meta("day", 0.0))) * float(l[1])
		light.visible = on > 0.02
		light.light_energy = on * float(light.get_meta("energy", 1.6))


## 2D 镜头看到的世界矩形 → 3D 相机（Z = 0 的面上逐像素重合）
func _sync_camera() -> void:
	var c2: Camera2D = world.camera
	if c2 == null:
		return
	var center: Vector2 = c2.get_screen_center_position()
	var view: Vector2 = world.get_viewport_rect().size / c2.zoom
	var h := view.y / 100.0
	var cx := center.x / 100.0
	var cy := (ground_y - center.y) / 100.0
	cam.position = Vector3(cx, cy + LIFT, DIST)
	cam.rotation = Vector3.ZERO
	cam.size = h * NEAR / DIST
	cam.frustum_offset = Vector2(0.0, -LIFT * NEAR / DIST)
	post.set_shader_parameter("focus_y", focus_line(ground_y, center.y, view.y))


## 移轴对准的那条线在屏幕上的高度（0 顶 1 底）：人身子的正中（地面往上半个大人），人比身后的墙清楚
static func focus_line(ground: float, center_y: float, view_y: float) -> float:
	var feet := (ground - center_y) / view_y + 0.5
	var body := 75.0 * FIG_SCALE / view_y
	return clampf(feet - body, 0.2, 0.9)


## 世界坐标（2D 像素）→ 3D
func to3d(p: Vector2, z := 0.0) -> Vector3:
	return Vector3(p.x / 100.0, (ground_y - p.y) / 100.0, z)


func _sync_actors(_delta: float) -> void:
	for r in world.actors:
		var a = world.actors[r]
		var f: Node3D = figures.get(r)
		if f == null or f.stage != a.stage:
			if f != null:
				f.queue_free()
			f = Figure.new()
			root3d.add_child(f)
			f.scale = Vector3.ONE * FIG_SCALE
			f.build(r, a.stage)
			figures[r] = f
		f.visible = a.visible
		f.position = to3d(a.position, 0.0 if r == world.my_role else -0.08)
		f.walking = a.walking
		f.phase = fmod(a._phase / 8.0, 1.0)
		f.dir = -1 if a._dir == 3 else 1
		f.face_to = 0 if a.face_to == 0 else (1 if a.face_to == 2 else -1)
		var lp: String = a._loop
		if f.loop != lp:
			f.loop_t = 0.0
		f.loop = lp
		if f.emote != a._emote:
			f.emote_t = 0.0
		f.emote = a._emote
		f.asleep = a.asleep
		if lp == "pass":
			f.pass_phase = a._pass_phase()
	_sync_ball()


## 两人对踢：球从出脚的人脚边滚到另一个人脚边（和 actor._draw_pass 一个算法）
func _sync_ball() -> void:
	var lead = null
	for a in world.actors.values():
		if a.pass_lead and a._loop == "pass" and a.pass_with != null and a.visible:
			lead = a
	_ball.visible = lead != null
	if lead == null:
		return
	var other = lead.pass_with
	var u := fmod(lead.pass_clock / lead.PASS_PERIOD, 1.0)
	var f := fmod(u * 2.0, 1.0)
	var mine := u < 0.5
	var h: float = lead._height() / 100.0
	var reach := h * 0.2
	var s := signf(other.position.x - lead.position.x)
	var a3 := to3d(lead.position) + Vector3(s * reach, 0, 0.12)
	var b3 := to3d(other.position) + Vector3(-s * reach, 0, 0.12)
	var from := a3 if mine else b3
	var to := b3 if mine else a3
	var e := 1.0 - pow(1.0 - f, 1.7)
	var p := from.lerp(to, e)
	var r := 0.085 * h / 1.7 + 0.015
	p.y += r + absf(sin(f * PI * 2.0)) * (1.0 - f) * h * 0.09
	_ball.position = p
	_ball.scale = Vector3.ONE * (r / 0.1)
	_ball.rotation.z = -(p.x - from.x) / r


## 街坊、路人：2D 那边照旧管谁在、干活还是歇着、往哪边让；这里只换成 3D 小人
func _sync_folks() -> void:
	var street = world.street
	if street == null:
		return
	var live := {}
	var nodes: Array = []
	nodes.append_array(street._people)
	nodes.append_array(street._walkers)
	for n in nodes:
		if not is_instance_valid(n):
			continue
		live[n] = true
		var f: Node3D = folk_figs.get(n)
		if f == null:
			f = Figure.new()
			root3d.add_child(f)
			f.scale = Vector3.ONE * FIG_SCALE
			var lk := _folk_look(n)
			var st := "young"
			if "speed" in n:
				var kinds: Array = street._index.get("walkers", [])
				var kind := str(kinds[n._row]) if n._row < kinds.size() else ""
				if kind == "kid":
					st = "childhood"
					lk["height"] = 1.15
					lk["head"] = 0.15
				elif kind.contains("old") or bool(lk.get("old", false)):
					st = "old"
					lk["hair"] = "boy_old" if not lk.girl else "bun_grey"
					lk.erase("hair_col")
			if st == "young" and bool(lk.get("old", false)):
				st = "old"  # 摆摊、坐着的老街坊：脸也是老人的（眼睛细、眼尾有纹）
			f.build("folk", st, lk)
			f.set_meta("work", "busy")
			folk_figs[n] = f
		var x: float = n.position.x
		var walker: bool = "speed" in n
		var walking := false
		var dir := 1
		var z := -0.4
		if "_sprite" in n and n._sprite != null and not walker:
			x += n._sprite.position.x
		if walker:
			walking = float(n._pause) <= 0.0
			dir = 1 if float(n.speed) > 0.0 else -1
			f.phase = fmod(float(n._phase) / 8.0, 1.0)
			# 后道的从人身后过，前道的从人跟前过
			z = -0.75 if n.position.y < ground_y else 0.75
		elif "_flip" in n:
			dir = -1 if n._flip else 1
		f.position = to3d(Vector2(x, ground_y), z)
		f.walking = walking
		f.dir = dir
		var working: bool = bool(n.get("_working")) if "_working" in n else false
		var want := str(f.get_meta("work", "busy")) if working else ""
		if f.loop != want:
			f.loop_t = 0.0
		f.loop = want
		f.visible = n.visible
	for n in folk_figs.keys():
		if not live.has(n):
			folk_figs[n].queue_free()
			folk_figs.erase(n)


## 街坊长什么样：按 id 挑一套（衣服颜色、身高、胖瘦、发型）；行当决定手上干什么
func _folk_look(n: Node) -> Dictionary:
	var id := str(n.get("id")) if "id" in n else str(n.get_instance_id())
	var h := hash(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var tops := ["#5A6B7D", "#8C5A44", "#3F5E52", "#B9A27A", "#6E4E66", "#2F3E55", "#C8B79A", "#7A7F5A", "#4B4A55"]
	var bottoms := ["#2F3340", "#4A4038", "#3C4A5C", "#5A5248", "#262A33"]
	var girl := rng.randf() < 0.45
	var old := rng.randf() < 0.3
	var lk := {
		"top": tops[rng.randi() % tops.size()], "bottom": bottoms[rng.randi() % bottoms.size()],
		"sleeve": 1.0 if rng.randf() < 0.7 else 0.5, "legs": 1.0,
		"shoes": ["#2B2724", "#4A3328", "#5B5E63"][rng.randi() % 3], "shoe2": "#1E1B19",
		"height": rng.randf_range(1.55, 1.78) - (0.08 if girl else 0.0) - (0.05 if old else 0.0),
		"head": 0.132, "build": rng.randf_range(0.95, 1.12), "girl": girl, "old": old,
		"hair": (["bun_grey", "bob"] if old else ["bob", "bun", "ponytail"])[rng.randi() % 2] if girl else (["boy_old", "boy_short"][0 if old else 1]),
		# 日漫的肤色：浅、偏暖，人和人之间差一点
		"skin": Color(1.0, 0.88, 0.8).lerp(Color(0.93, 0.76, 0.64), rng.randf()).to_html(),
	}
	if old and not girl:
		lk["hair"] = "boy_old"
	if not old:
		# 头发：黑、深棕、栗色几种
		var hairs := ["#2A2328", "#3B2A26", "#4A3428", "#24232E", "#5A3B2C"]
		lk["hair_col"] = hairs[rng.randi() % hairs.size()]
	return lk


## 截图、对比用：画面里有没有 3D
func active() -> bool:
	return visible and set3d != null
