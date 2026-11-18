extends "res://scripts/world3d/set3d.gd"
## 楼里（content/maps/building.yaml，宽 32 米）的实时 3D：红砖楼三楼像玩具屋一样把正面墙拿掉，看进屋里。
## 从左到右：青家（0~12 m：床、屋角的五斗柜 / 书柜 / 琴、书桌、饭桌、电视柜、脸盆架、冰箱）、
## 楼道（12~20 m：两扇对门、春联、奶箱、暖气片、堆东西的那一角、小板凳、往下的楼梯、电表箱、拉线灯、上楼顶的铁梯子）、
## 梅家（20~32 m：和青家左右镜像，整户是同一套搭法、x 翻过来）。
## 头顶是楼顶的楼板（剖开露厚度），楼板上头是楼顶：女儿墙、鸽子棚、晾衣绳和床单、楼梯间小屋、水箱、天线（后来是太阳能）。
## 脚底下是三楼的楼板剖面和二楼的红砖外墙（窗户上半截），楼梯那一段二楼也剖开，看得见楼梯一跑一跑往下走。
## 后墙真挖了窗洞，窗外是后院的大槐树和后头一排排的楼（夜里亮窗）。
##
## 坐标：Y = 0 是三楼屋里的地面，楼顶楼板顶面 Y = 4.6；人走在 Z = 0，后墙前脸 ZB，正面剖到 ZF。
## 家里的东西（HomeLife.pick 的键单）每样一个节点，tick 里每 0.3 秒对一遍两家的单子，新进门的从 0.85 倍长到 1。
## 梅家：先按青家的坐标搭，节点 x 翻过来（scale.x = -1、挪到 32 米）——家具、灯、东西都一样镜像。
## 年代：楼道门（木门→防盗门）、堆的东西、小广告、楼顶的天线 / 太阳能 / 鸽子棚、小孩的课桌。

const HomeLife := preload("res://scripts/world/home_life.gd")
const W := 32.0       ## 图宽；梅家 x = W − 青家 x
const ZB := -2.6      ## 后墙前脸
const ZF := 1.0       ## 正面剖切线（楼板前沿）
const CEIL := 4.4     ## 屋顶板底面
const ROOF := 4.6     ## 楼顶板顶面（楼顶那一层地面）
const DOWN := -6.6    ## 街面（三楼往下两层多）
const ACC := {"qing": Color("#3f7d68"), "mei": Color("#b54a3e")}
const HOLE := Rect2(14.95, -2.6, 2.05, 1.5)   ## 楼梯口（x, z 的范围）：x 14.95~17.0，z -2.6~-1.1
const HATCH := Rect2(16.95, -2.6, 0.9, 0.75)  ## 屋顶板上的检修口（铁梯子上去）

var _items: Dictionary = {}     ## "role/键@样子" -> Node3D
var _shown: Dictionary = {}     ## role -> 现在摆着的键单（含样子）
var _grow: Array = []           ## [节点, 已经长了几秒, x 方向（梅家 -1）]
var _home_t := 0.0
var _home_sig := ""
var _fills: Array = []         ## [OmniLight3D, 亮度]：白天屋里的天光（自己按钟点调）
var _pane_mat: StandardMaterial3D


func build(sc: Dictionary, p_look: String, season: String) -> void:
	_rng.seed = 20261118
	look = p_look
	extra_mats = {
		"wall_white": [6, "#efe2c4", "#000000", Vector2.ONE, 0.93, 0.45, 0.35, 0.05, 0.0],
		"wall_hall": [6, "#d3c9b3", "#000000", Vector2.ONE, 0.95, 0.6, 0.75, 0.08, 0.0],
		"wain": [0, "#6f9886", "#000000", Vector2.ONE, 0.42, 0.0, 0.25, 0.0, 0.0],
		"wain_hall": [0, "#5f8682", "#000000", Vector2.ONE, 0.5, 0.0, 0.55, 0.0, 0.0],
		"floor_home": [6, "#968a78", "#000000", Vector2.ONE, 0.62, 0.5, 0.35, 0.08, 0.0],
		"floor_hall": [6, "#7d786f", "#000000", Vector2.ONE, 0.85, 0.8, 0.6, 0.1, 0.0],
		"lino": [2, "#9b5a3a", "#7a412a", Vector2(0.32, 0.32), 0.45, 0.3, 0.1, 0.1, 0.0],
		"roof_tile": [2, "#9d978a", "#6c675e", Vector2(0.5, 0.5), 0.9, 1.0, 0.5, 0.12, 0.0],
		"furn": [4, "#6a3923", "#47220f", Vector2(0.1, 1.0), 0.38, 0.6, 0.15, 0.08, 0.0],
		"furn_light": [10, "#b08a5c", "#8a6a44", Vector2(0.09, 1.0), 0.55, 0.6, 0.15, 0.1, 0.0],
		"tint": [0, "#ffffff", "#000000", Vector2.ONE, 0.6, 0.0, 0.0, 0.0, 0.0],
		"enamel": [0, "#ffffff", "#000000", Vector2.ONE, 0.22, 0.0, 0.0, 0.0, 0.0],
		"cloth": [0, "#ffffff", "#000000", Vector2.ONE, 0.97, 0.0, 0.0, 0.0, 0.0],
		"lacquer": [0, "#121214", "#000000", Vector2.ONE, 0.16, 0.0, 0.0, 0.0, 0.0],
		"silver": [0, "#b4b7b6", "#000000", Vector2.ONE, 0.5, 0.0, 0.2, 0.0, 0.55],
		"brass": [0, "#b48c40", "#000000", Vector2.ONE, 0.3, 0.0, 0.0, 0.0, 0.85],
		"screen": [0, "#1d2422", "#000000", Vector2.ONE, 0.12, 0.0, 0.0, 0.0, 0.0],
		"coal": [0, "#2a2725", "#000000", Vector2.ONE, 0.95, 0.0, 0.0, 0.0, 0.0],
		"bulb": [0, "#fff4d8", "#000000", Vector2.ONE, 0.3, 0.0, 0.0, 0.0, 0.0],
		# 合批用的三种素料（见 _commit）：底色乘进顶点色
		"matte": [0, "#ffffff", "#000000", Vector2.ONE, 0.82, 0.0, 0.0, 0.0, 0.0],
		"gloss": [0, "#ffffff", "#000000", Vector2.ONE, 0.2, 0.0, 0.0, 0.0, 0.0],
		"shiny": [0, "#ffffff", "#000000", Vector2.ONE, 0.35, 0.0, 0.0, 0.0, 0.8],
	}
	extra_glow = {"bulb": [3.0, "#ffd9a0"]}
	_pane_mat = StandardMaterial3D.new()
	_pane_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pane_mat.albedo_color = Color(0.78, 0.86, 0.9, 0.1)
	_pane_mat.roughness = 0.04
	_pane_mat.metallic_specular = 0.9
	_pane_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["pane"] = _pane_mat
	# 按地方分几批：compatibility 渲染器里每盏点光要把它够得着的网格再画一遍，
	# 一整张图并成一批的话，哪盏灯一亮全图都得重画；分成楼壳 / 楼道 / 楼顶 / 远景，灯只碰身边那几批
	_begin()
	_shell()
	_downstairs()
	_commit(_part("shell"))
	_begin()
	_stairs()
	_hallway()
	_commit(_part("hall"))
	_begin()
	_roof()
	_commit(_part("roof"))
	_begin()
	_bg()
	_tree(Vector3(5.6, DOWN, -10.0), 2.35, "huai")
	_tree(Vector3(27.0, DOWN, -11.0), 2.2, "huai")
	_commit(_part("far"))
	for role in ["qing", "mei"]:
		_home(role)
	_hall_doors()
	_hall_era()
	_roof_era()
	(_mat("glass_far") as ShaderMaterial).set_shader_parameter("lit_chance", 0.38)
	# 白天屋里的天光：后窗进来的散光，夜里灯一亮就收
	for role in ["qing", "mei"]:
		var fx := 6.6 if role == "qing" else W - 6.6
		_fill(Vector3(fx, 2.8, -0.6), Color(1.0, 0.88, 0.72), 7.0, 2.4)
	_fill(Vector3(16.0, 2.6, -0.8), Color(0.97, 0.96, 0.98), 3.9, 1.2)
	_update_home(false)
	_fix_shadows(self)
	set_look(look)
	set_season(season)


## 不投影的料：小东西、贴墙的薄片、地面、远景。太阳从后窗进来，影子靠墙、楼板、大件家具、窗帘投就够了，
## 小物件都投影的话阴影那一遍要多画一百多次
const NO_SHADOW := ["pane", "bulb", "cloth_thin", "tint", "paper", "enamel", "sign_ink", "sign_red", "brass", "chrome",
	"silver", "rubber", "bamboo", "water", "lacquer", "screen", "metal", "glass", "gloss", "shiny", "glass_far", "lamp", "floor_home",
	"floor_hall", "lino", "wain", "wain_hall", "asphalt", "stone", "coal"]


func _fix_shadows(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and str(c.name) in NO_SHADOW:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif c.get_child_count() > 0:
			_fix_shadows(c)


## 合批：没有花纹、只差底色和粗糙度的素料（纸、布、油墨、搪瓷、电镀件……）并成三种，
## 每样东西少出好几个网格（每个网格每盏灯都得多画一遍）。底色（线性）乘进顶点色，看着和原来一样
const MERGE := {
	"paper": "matte", "cloth": "matte", "sign_ink": "matte", "sign_red": "matte", "rubber": "matte", "tint": "matte",
	"lacquer": "gloss", "screen": "gloss", "enamel": "gloss",
	"chrome": "shiny", "brass": "shiny", "silver": "shiny", "metal": "shiny",
}


func _commit(parent: Node3D, shadows := true) -> void:
	var groups := {}
	for key in _st.keys():
		var g: String = MERGE.get(key, "")
		if g == "":
			continue
		var arr: Array = (_st[key] as SurfaceTool).commit_to_arrays()
		var d: Array = extra_mats[key] if extra_mats.has(key) else MATS[key]
		var base := Color(str(d[1])).srgb_to_linear()
		var n := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		if cols.size() != n:
			cols.resize(n)
			cols.fill(Color.WHITE)
		for i in n:
			var c := cols[i]
			cols[i] = Color(c.r * base.r, c.g * base.g, c.b * base.b, c.a)
		arr[Mesh.ARRAY_COLOR] = cols
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		if not groups.has(g):
			var nt := SurfaceTool.new()
			nt.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[g] = nt
		(groups[g] as SurfaceTool).append_from(m, 0, Transform3D.IDENTITY)
		_st.erase(key)
	for g in groups:
		_st[g] = groups[g]
	super._commit(parent, shadows)


func _part(nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	add_child(n)
	return n


## 一个小椭球（鸽子、白菜、钟面、灯泡）：经纬网格直接往批次里写
func _ell(key: String, c: Vector3, r: Vector3, color := Color.WHITE, seg := 10, rings := 6) -> void:
	var st := _tool(key)
	for j in rings:
		var t0 := PI * float(j) / float(rings)
		var t1 := PI * float(j + 1) / float(rings)
		for i in seg:
			var p0 := TAU * float(i) / float(seg)
			var p1 := TAU * float(i + 1) / float(seg)
			var q := [Vector3(sin(t0) * cos(p0), cos(t0), sin(t0) * sin(p0)), Vector3(sin(t0) * cos(p1), cos(t0), sin(t0) * sin(p1)),
				Vector3(sin(t1) * cos(p1), cos(t1), sin(t1) * sin(p1)), Vector3(sin(t1) * cos(p0), cos(t1), sin(t1) * sin(p0))]
			for idx in [0, 1, 2, 0, 2, 3]:
				var u: Vector3 = q[idx]
				st.set_color(color)
				st.set_normal(Vector3(u.x / r.x, u.y / r.y, u.z / r.z).normalized())
				st.set_uv(Vector2.ZERO)
				st.add_vertex(c + u * r)


## 绕 Z 转的盒子（钟的指针、斜靠的东西）
func _roll(key: String, c: Vector3, size: Vector3, a: float, color := Color.WHITE) -> void:
	Kit.box_into(_tool(key), size, Transform3D(Basis(Vector3.BACK, a), c), color)


## 灯（家里的灯按青家坐标给，梅家翻过来）
func _lamp_at(role: String, at: Vector3, col: Color, rng: float, energy: float, day := 0.0) -> void:
	var p := at
	if role == "mei":
		p.x = W - p.x
	_add_lamp(p, col, rng, energy, day)


# ======================================================================
# 楼的壳子：楼板、外墙剖面、隔墙、后墙
# ======================================================================

func _shell() -> void:
	# 三楼楼板（剖面露厚度），楼梯口挖空
	var h0 := HOLE.position.x
	var h1 := HOLE.end.x
	bx("concrete", -0.36, h0, -0.27, -0.02, ZB - 0.3, ZF)
	bx("concrete", h1, W + 0.36, -0.27, -0.02, ZB - 0.3, ZF)
	bx("concrete", h0, h1, -0.27, -0.02, HOLE.end.y, ZF)
	bx("floor_home", 0.0, 11.88, -0.02, 0.0, ZB, ZF)
	bx("floor_home", 20.12, W, -0.02, 0.0, ZB, ZF)
	bx("floor_hall", 11.88, h0, -0.02, 0.0, ZB, ZF)
	bx("floor_hall", h1, 20.12, -0.02, 0.0, ZB, ZF)
	bx("floor_hall", h0, h1, -0.02, 0.0, HOLE.end.y, ZF)
	# 楼梯口的边：水泥包边
	bx("concrete", h0 - 0.04, h1 + 0.04, -0.02, 0.025, HOLE.end.y, HOLE.end.y + 0.05)
	# 屋顶板：底面 4.4，顶面 4.6；铁梯子那儿一个检修口
	var a0 := HATCH.position.x
	var a1 := HATCH.end.x
	bx("concrete", -0.36, a0, CEIL, ROOF - 0.02, ZB - 0.3, ZF)
	bx("concrete", a1, W + 0.36, CEIL, ROOF - 0.02, ZB - 0.3, ZF)
	bx("concrete", a0, a1, CEIL, ROOF - 0.02, HATCH.end.y, ZF)
	bx("concrete", a0, a1, CEIL, ROOF - 0.02, ZB - 0.3, ZB)
	# 屋顶板前沿一道深色的缝（剖切线，像模型的切口）
	bx("asphalt", -0.36, W + 0.36, CEIL - 0.012, CEIL, ZF - 0.02, ZF + 0.003)
	bx("asphalt", -0.36, W + 0.36, -0.02, 0.0, ZF - 0.02, ZF + 0.004)
	# 两头的外墙：剖到的红砖，里面一层白灰
	for xx in [[-0.36, 0.0], [W, W + 0.36]]:
		bx("brick", float(xx[0]), float(xx[1]), -2.6, ROOF + 0.9, ZB - 0.3, ZF)
		bx("concrete", float(xx[0]) - 0.03, float(xx[1]) + 0.03, ROOF + 0.9, ROOF + 1.0, ZB - 0.33, ZF + 0.03)
	# 楼道的天花、后墙
	bx("wall_hall", 12.12, 19.88, CEIL - 0.02, CEIL, ZB, ZF)
	# 楼道后墙：一扇小窗（堆东西那儿），两个门洞，楼梯口那一段往下通到二楼
	var holes := [Rect2(13.95, 1.25, 0.8, 1.2), Rect2(12.6, 0.0, 0.8, 2.1), Rect2(18.6, 0.0, 0.8, 2.1)]
	wall("wall_hall", 12.12, 19.88, 0.0, CEIL, ZB, 0.3, holes)
	bx("wall_hall", h0 - 0.3, h1 + 0.4, -2.6, 0.0, ZB, ZB - 0.3)
	bx("wain_hall", 12.12, 19.88, 0.0, 1.2, ZB, ZB + 0.012)
	bx("wain_hall", h0 - 0.3, h1 + 0.4, -2.6, 0.0, ZB, ZB + 0.012)
	bx("sign_ink", 12.12, 19.88, 1.2, 1.225, ZB, ZB + 0.016)
	_win_frame(13.95, 1.25, 0.8, 1.2, ZB, false)
	bx("concrete", 13.9, 14.8, 1.19, 1.25, ZB, ZB + 0.09)


## 二楼：只露出上半截。红砖外墙、窗户上沿、水泥腰线；楼梯那一段剖开
func _downstairs() -> void:
	var cut0 := 14.55
	var cut1 := 17.45
	var holes: Array = []
	for wx in [1.2, 4.6, 8.3, 22.3, 26.0, 29.4]:
		var r := Rect2(float(wx), -2.25, 1.4, 1.5)
		holes.append(r)
		window(float(wx), -2.25, 1.4, 1.5, ZF)
	holes.append(Rect2(cut0, -3.2, cut1 - cut0, 2.93))
	wall("brick", -0.36, W + 0.36, -3.2, -0.27, ZF, 0.3, holes)
	# 窗上的水泥过梁
	for wx in [1.2, 4.6, 8.3, 22.3, 26.0, 29.4]:
		bx("concrete", float(wx) - 0.08, float(wx) + 1.48, -0.75, -0.6, ZF - 0.02, ZF + 0.02)
	# 楼梯间剖开的两侧墙、里头的白墙
	for x in [cut0, cut1]:
		bx("brick", x - 0.12, x + 0.12, -3.2, -0.27, ZB - 0.3, ZF)
	bx("wall_hall", cut0 + 0.12, cut1 - 0.12, -3.2, -0.27, ZB - 0.32, ZB - 0.3)
	bx("wall_hall", cut0 + 0.12, cut1 - 0.12, -0.3, -0.27, ZB, ZF)
	# 二楼窗外：一户的晾衣架、一户的花盆（楼下也住着人）
	tube("metal", PackedVector3Array([Vector3(4.5, -0.85, ZF + 0.02), Vector3(4.5, -0.85, ZF + 0.5), Vector3(6.1, -0.85, ZF + 0.5), Vector3(6.1, -0.85, ZF + 0.02)]), 0.012, 4)
	for k in 4:
		bx("cloth", 4.65 + k * 0.38, 4.95 + k * 0.38, -1.4 + (k % 2) * 0.12, -0.86, ZF + 0.49, ZF + 0.51, [Color("#d9d2c2"), Color("#6d7fa0"), Color("#c26b5a"), Color("#e8e1cf")][k])
	bx("concrete", 26.0, 27.4, -0.88, -0.82, ZF, ZF + 0.25)
	for k in 3:
		cyl("wood_red", Vector3(26.25 + k * 0.45, -0.82, ZF + 0.12), 0.09, 0.11, 0.16, 8)
		_ell("tint", Vector3(26.25 + k * 0.45, -0.58, ZF + 0.12), Vector3(0.14, 0.12, 0.12), Color("#4d7a3e"))


## 往下的楼梯：头一跑靠后墙往右下，缓台，第二跑贴着前头往左下；水泥台阶、铁栏杆木扶手
func _stairs() -> void:
	var x0 := HOLE.position.x
	var rise := 0.172
	var run := 0.255
	var z0 := HOLE.end.y - 0.03
	var zb := ZB + 0.02
	for i in 9:
		var top := -rise * float(i + 1)
		var sx := x0 + run * float(i)
		bx("concrete", sx, sx + run, top - 0.16, top, zb, z0)
		bx("stone", sx - 0.01, sx + run, top - 0.006, top + 0.004, zb, z0 + 0.01)
	# 斜的梯板
	var slab := Transform3D(Basis(Vector3.BACK, -atan2(rise, run)), Vector3(x0 + run * 4.5 + 0.06, -rise * 5.0 - 0.32, (zb + z0) / 2.0))
	Kit.box_into(_tool("concrete"), Vector3(9.0 * run / cos(atan2(rise, run)) + 0.1, 0.14, z0 - zb), slab)
	# 缓台
	var lx := x0 + run * 9.0
	var ly := -rise * 9.0
	bx("concrete", lx, lx + 0.5, ly - 0.2, ly, zb, ZF - 0.32)
	# 第二跑：往左下，贴着前头
	for i in 9:
		var top := ly - rise * float(i + 1)
		var sx := lx - run * float(i + 1)
		bx("concrete", sx, sx + run, top - 0.16, top, z0 + 0.06, ZF - 0.32)
		bx("stone", sx, sx + run + 0.01, top - 0.006, top + 0.004, z0 + 0.06, ZF - 0.31)
	# 楼梯口一圈栏杆：铁条、木扶手（前沿、左边）
	var rz := HOLE.end.y + 0.04
	var x := x0 + 0.02
	while x < HOLE.end.x - 0.02:
		bx("metal", x - 0.009, x + 0.009, 0.0, 0.9, rz - 0.009, rz + 0.009)
		x += 0.13
	bx("metal", x0, HOLE.end.x, 0.1, 0.12, rz - 0.012, rz + 0.012)
	bx("wood_red", x0 - 0.03, HOLE.end.x + 0.03, 0.9, 0.95, rz - 0.035, rz + 0.035)
	var z := rz - 0.13
	while z > ZB + 0.05:
		bx("metal", x0 - 0.009, x0 + 0.009, 0.0, 0.9, z - 0.009, z + 0.009)
		z -= 0.13
	bx("wood_red", x0 - 0.035, x0 + 0.035, 0.9, 0.95, ZB, rz)
	bx("wood_red", x0 - 0.04, x0 + 0.04, 0.0, 1.02, rz - 0.04, rz + 0.04)
	# 往下那一跑的斜扶手
	tube("wood_red", PackedVector3Array([Vector3(x0, 0.92, rz), Vector3(lx, ly + 0.92, rz)]), 0.025, 5)
	for k in 7:
		var t := float(k + 1) / 8.0
		var p := Vector3(lerpf(x0, lx, t), lerpf(0.0, ly, t), rz)
		bx("metal", p.x - 0.009, p.x + 0.009, p.y, p.y + 0.92, rz - 0.009, rz + 0.009)


func _win_frame(x: float, y: float, w: float, h: float, z: float, mullion := true) -> void:
	var rz := z - 0.14
	var t := 0.05
	bx("paint", x, x + w, y, y + t, rz - 0.04, rz + 0.04)
	bx("paint", x, x + w, y + h - t, y + h, rz - 0.04, rz + 0.04)
	bx("paint", x, x + t, y, y + h, rz - 0.04, rz + 0.04)
	bx("paint", x + w - t, x + w, y, y + h, rz - 0.04, rz + 0.04)
	if mullion:
		for k in [1, 2]:
			var mx := x + w * float(k) / 3.0
			bx("paint", mx - 0.025, mx + 0.025, y, y + h, rz - 0.035, rz + 0.035)
	bx("paint", x, x + w, y + h * 0.7, y + h * 0.7 + 0.04, rz - 0.035, rz + 0.035)
	bx("pane", x + t, x + w - t, y + t, y + h - t, rz - 0.005, rz + 0.005)


# ======================================================================
# 一户人家（按青家坐标搭；梅家整户镜像）
# ======================================================================

func _home(role: String) -> void:
	var root := Node3D.new()
	root.name = "home_" + role
	add_child(root)
	if role == "mei":
		root.position = Vector3(W, 0, 0)
		root.scale = Vector3(-1, 1, 1)
	var acc: Color = ACC[role]
	var other: Color = ACC["mei" if role == "qing" else "qing"]
	_begin()
	# 后墙：上白下绿，两扇窗真挖洞
	var wins := [Rect2(4.1, 1.5, 2.2, 1.75), Rect2(6.9, 1.5, 2.2, 1.75)]
	wall("wall_white", 0.0, 11.88, 0.0, CEIL, ZB, 0.3, wins)
	bx("wain", 0.0, 11.88, 0.0, 1.3, ZB, ZB + 0.012)
	bx("sign_ink", 0.0, 11.88, 1.3, 1.325, ZB, ZB + 0.018)
	bx("furn", 0.0, 11.88, 0.0, 0.11, ZB, ZB + 0.02)
	bx("furn_light", 0.0, 11.88, 3.85, 3.88, ZB, ZB + 0.03)  # 挂镜线
	bx("wall_white", 0.0, 11.88, CEIL - 0.02, CEIL, ZB, ZF)
	# 左边外墙里皮、右边和楼道之间的隔墙（前头留出走道，上头一道过梁）
	bx("wall_white", 0.0, 0.015, 0.0, CEIL, ZB, ZF)
	bx("wain", 0.0, 0.02, 0.0, 1.3, ZB, ZF)
	bx("brick", 11.9, 12.1, 0.0, CEIL, ZB, -0.55)
	bx("brick", 11.9, 12.1, 2.45, CEIL, -0.55, ZF)
	bx("wall_white", 11.88, 11.9, 0.0, CEIL, ZB, -0.55)
	bx("wain", 11.87, 11.9, 0.0, 1.3, ZB, -0.55)
	bx("wall_white", 11.88, 11.9, 2.45, CEIL, -0.55, ZF)
	bx("wall_hall", 12.1, 12.12, 0.0, CEIL, ZB, -0.55)
	bx("wain_hall", 12.1, 12.125, 0.0, 1.2, ZB, -0.55)
	bx("wall_hall", 12.1, 12.12, 2.45, CEIL, -0.55, ZF)
	bx("concrete", 11.86, 12.14, 2.41, 2.47, -0.6, ZF)
	for r in wins:
		var rr: Rect2 = r
		_win_frame(rr.position.x, rr.position.y, rr.size.x, rr.size.y, ZB)
		# 窗台板、窗帘杆、两片窗帘（褶子一道道）
		bx("furn_light", rr.position.x - 0.08, rr.end.x + 0.08, rr.position.y - 0.03, rr.position.y + 0.01, ZB, ZB + 0.14)
		bx("chrome", rr.position.x - 0.25, rr.end.x + 0.25, 3.4, 3.42, ZB + 0.06, ZB + 0.08)
		for side in [0, 1]:
			var cx0: float = rr.position.x - 0.22 if side == 0 else rr.end.x - 0.32
			for k in 5:
				var fz := ZB + 0.05 + (0.025 if k % 2 == 0 else 0.0)
				bx("cloth", cx0 + k * 0.108, cx0 + k * 0.108 + 0.11, 1.38, 3.4, fz, fz + 0.02, acc.lerp(Color("#e8e0cc"), 0.35 + 0.08 * (k % 2)))
		# 窗下的暖气片（银粉的铸铁片）
		var rx := rr.get_center().x
		for k in 11:
			var fx := rx - 0.5 + k * 0.095
			bx("silver", fx, fx + 0.07, 0.14, 0.72, ZB + 0.05, ZB + 0.19)
		bx("silver", rx - 0.52, rx + 0.5, 0.18, 0.21, ZB + 0.08, ZB + 0.16)
		bx("silver", rx - 0.52, rx + 0.5, 0.64, 0.67, ZB + 0.08, ZB + 0.16)
	# 窗台上：一盆花、一个罐头瓶
	cyl("wood_red", Vector3(4.5, 1.51, ZB + 0.08), 0.06, 0.08, 0.12, 8)
	_ell("tint", Vector3(4.5, 1.7, ZB + 0.08), Vector3(0.12, 0.1, 0.07), Color("#4f7d3c"))
	cyl("pane", Vector3(8.7, 1.51, ZB + 0.08), 0.05, 0.05, 0.14, 8)
	_bed(acc, other)
	_desk(acc)
	_table(other)
	_basin(acc)
	_wall_bits(acc)
	_commit(root)
	_fix_shadows(root)
	# 灯：饭桌上头的吊灯、后墙上的日光灯、书桌上的台灯
	_lamp_at(role, Vector3(8.0, 3.2, -0.95), Color(1.0, 0.86, 0.66), 6.5, 1.8)
	_lamp_at(role, Vector3(3.2, 3.55, -1.9), Color(1.0, 0.95, 0.86), 6.5, 1.0)
	_lamp_at(role, Vector3(4.55, 1.0, -0.85), Color(1.0, 0.8, 0.55), 2.6, 0.9)
	# 小孩的课桌（青年起：两个人自己的孩子在这儿写作业）
	_begin()
	var kx := 6.6
	bx("furn_light", kx - 0.32, kx + 0.32, 0.55, 0.58, -1.02, -0.6)
	for lx in [kx - 0.28, kx + 0.28]:
		for lz in [-0.98, -0.64]:
			bx("metal", lx - 0.012, lx + 0.012, 0.0, 0.55, lz - 0.012, lz + 0.012)
	bx("furn_light", kx - 0.3, kx + 0.3, 0.42, 0.44, -0.98, -0.64)
	bx("tint", kx - 0.2, kx - 0.02, 0.58, 0.6, -0.9, -0.72, Color("#3c6aa8"))
	bx("paper", kx + 0.02, kx + 0.24, 0.58, 0.585, -0.9, -0.74, Color("#f2ecdc"))
	bx("tint", kx + 0.1, kx + 0.28, 0.585, 0.6, -1.0, -0.94, Color("#d9a63e"))
	var kd := Node3D.new()
	root.add_child(kd)
	_commit(kd)
	_era_nodes.append([kd, 2, 4])


## 床：靠左墙，床头板、床尾板、褥子床单、叠好的被子枕头；床后头一口樟木箱，墙上奖状
func _bed(acc: Color, other: Color) -> void:
	var z0 := -1.68
	var z1 := 0.04   ## 床沿伸到走道线上一点：打盹的人（figure3d 的 asleep 是坐着歪头）正好坐在床沿上
	bx("furn", 0.05, 0.12, 0.0, 1.05, z0, z1)
	bx("furn", 0.03, 0.14, 1.05, 1.1, z0 - 0.02, z1 + 0.02)
	bx("furn", 2.18, 2.25, 0.0, 0.68, z0, z1)
	bx("furn", 2.16, 2.27, 0.68, 0.72, z0 - 0.02, z1 + 0.02)
	bx("furn", 0.12, 2.18, 0.22, 0.32, z0, z0 + 0.04)
	bx("furn", 0.12, 2.18, 0.22, 0.32, z1 - 0.04, z1)
	bx("cloth", 0.12, 2.18, 0.32, 0.42, z0 + 0.02, z1 - 0.02, Color("#e9e3d4"))
	# 床单：耷拉过前沿一截
	var sheet := acc.lerp(Color("#efe6d2"), 0.55)
	bx("cloth", 0.12, 2.18, 0.42, 0.445, z0 + 0.01, z1 + 0.01, sheet)
	bx("cloth", 0.12, 2.18, 0.27, 0.445, z1 + 0.01, z1 + 0.025, sheet.darkened(0.06))
	for k in 6:
		bx("cloth", 0.25 + k * 0.33, 0.33 + k * 0.33, 0.43, 0.447, z0 + 0.1, z1 - 0.05, acc.lerp(Color.WHITE, 0.2))
	# 叠成豆腐块的被子、枕头、枕巾
	bx("cloth", 0.2, 0.78, 0.445, 0.72, z0 + 0.12, z0 + 0.95, other.lerp(Color("#f0d9a8"), 0.35))
	bx("cloth", 0.18, 0.8, 0.6, 0.62, z0 + 0.1, z0 + 0.97, other.lerp(Color("#f0d9a8"), 0.15))
	bx("cloth", 0.2, 0.62, 0.445, 0.58, z0 + 1.05, z1 - 0.12, Color("#ece6d8"))
	bx("cloth", 0.18, 0.64, 0.58, 0.59, z0 + 1.03, z1 - 0.1, Color("#f3efe4"))
	# 床前地上一块碎布编的圆垫子
	cyl("cloth", Vector3(1.25, 0.0, 0.42), 0.36, 0.36, 0.012, 20, Color("#8a5a4a"))
	cyl("cloth", Vector3(1.25, 0.012, 0.42), 0.27, 0.27, 0.004, 18, Color("#c9a77a"))
	cyl("cloth", Vector3(1.25, 0.016, 0.42), 0.15, 0.15, 0.003, 14, acc.lerp(Color("#d8cbb0"), 0.4))
	# 樟木箱、箱上一摞衣裳
	bx("wood_red", 0.3, 1.45, 0.0, 0.55, ZB + 0.02, ZB + 0.6)
	bx("brass", 0.28, 0.36, 0.42, 0.55, ZB + 0.58, ZB + 0.62)
	bx("brass", 1.39, 1.47, 0.42, 0.55, ZB + 0.58, ZB + 0.62)
	bx("brass", 0.84, 0.92, 0.4, 0.5, ZB + 0.6, ZB + 0.62)
	bx("cloth", 0.45, 1.0, 0.55, 0.68, ZB + 0.1, ZB + 0.5, Color("#5f6f8a"))
	bx("cloth", 0.48, 0.98, 0.68, 0.74, ZB + 0.12, ZB + 0.48, Color("#c9b48a"))
	# 墙上：两张奖状、一张合影
	for k in 2:
		var ax := 0.45 + k * 0.78
		bx("paper", ax, ax + 0.62, 2.0, 2.45, ZB, ZB + 0.008, Color("#f1e7cc"))
		bx("paper", ax + 0.03, ax + 0.59, 2.03, 2.42, ZB + 0.008, ZB + 0.01, Color("#c8483a"))
		bx("paper", ax + 0.06, ax + 0.56, 2.06, 2.39, ZB + 0.01, ZB + 0.012, Color("#f6eed8"))
		bx("paper", ax + 0.2, ax + 0.42, 2.3, 2.35, ZB + 0.012, ZB + 0.014, Color("#b8402f"))
	bx("furn", 0.75, 1.3, 2.7, 3.15, ZB, ZB + 0.03)
	bx("paper", 0.8, 1.25, 2.75, 3.1, ZB + 0.03, ZB + 0.035, Color("#8d8a80"))


## 书桌：抽屉、玻璃板、台灯、书、搪瓷缸；一把推进去的椅子
func _desk(acc: Color) -> void:
	var x0 := 4.2
	var x1 := 6.2
	var z0 := -1.3
	var z1 := -0.62
	bx("furn", x0, x1, 0.72, 0.76, z0, z1)
	bx("pane", x0 + 0.02, x1 - 0.02, 0.76, 0.766, z0 + 0.02, z1 - 0.02)
	bx("furn", x0, x0 + 0.48, 0.0, 0.72, z0 + 0.02, z1 - 0.02)
	for k in 3:
		var dy := 0.08 + k * 0.21
		bx("furn_light", x0 + 0.03, x0 + 0.45, dy, dy + 0.18, z1 - 0.025, z1 - 0.01)
		bx("brass", x0 + 0.2, x0 + 0.28, dy + 0.08, dy + 0.1, z1 - 0.01, z1 + 0.005)
	bx("furn_light", x0 + 0.5, x1 - 0.05, 0.6, 0.7, z1 - 0.025, z1 - 0.01)
	for lx in [x1 - 0.04]:
		for lz in [z0 + 0.04, z1 - 0.04]:
			bx("furn", lx - 0.025, lx + 0.025, 0.0, 0.72, lz - 0.025, lz + 0.025)
	# 玻璃板底下压着的照片、课程表
	bx("paper", x0 + 0.6, x0 + 0.85, 0.761, 0.763, z0 + 0.1, z0 + 0.28, Color("#d9c8a8"))
	bx("paper", x0 + 1.25, x0 + 1.55, 0.761, 0.763, z0 + 0.06, z0 + 0.26, Color("#e8e4d8"))
	# 台灯：铁座、弯杆、绿灯罩
	var lp := Vector3(4.5, 0.766, -1.12)
	cyl("metal", lp, 0.09, 0.08, 0.03, 10)
	tube("chrome", PackedVector3Array([lp + Vector3(0, 0.03, 0), lp + Vector3(0.02, 0.33, 0.0), lp + Vector3(0.08, 0.42, 0.12)]), 0.01, 5)
	cyl("enamel", lp + Vector3(0.08, 0.27, 0.13), 0.14, 0.035, 0.15, 12, acc.darkened(0.15))
	_ell("bulb", lp + Vector3(0.08, 0.3, 0.13), Vector3(0.04, 0.04, 0.04))
	# 一摞书、摊开的本子、搪瓷缸、笔筒
	var bcols := [Color("#a8452f"), Color("#e2d5b5"), Color("#3f5f86"), Color("#d6a446"), Color("#5d7a54")]
	var by := 0.766
	for k in 5:
		var th := 0.03 + _rng.randf() * 0.025
		bx("tint", 5.65 + _rng.randf() * 0.04, 6.0 - _rng.randf() * 0.04, by, by + th, -1.25, -1.0, bcols[k])
		by += th
	bx("paper", 4.95, 5.4, 0.766, 0.772, -0.98, -0.72, Color("#f3eedf"))
	bx("sign_ink", 5.17, 5.18, 0.772, 0.774, -0.97, -0.73)
	cyl("enamel", Vector3(5.6, 0.766, -0.82), 0.045, 0.045, 0.1, 10, Color("#f0ebe0"))
	cyl("enamel", Vector3(5.6, 0.856, -0.82), 0.047, 0.047, 0.012, 10, Color("#b8342c"))
	cyl("bamboo", Vector3(4.82, 0.766, -1.2), 0.04, 0.04, 0.12, 8)
	for k in 3:
		tube("tint", PackedVector3Array([Vector3(4.81 + k * 0.012, 0.8, -1.2), Vector3(4.8 + k * 0.025, 0.95, -1.21 + k * 0.01)]), 0.005, 4)
	# 椅子：推进桌底下，靠背朝外
	var cx := 5.75
	var cz := -0.9
	bx("furn", cx - 0.2, cx + 0.2, 0.43, 0.46, cz - 0.2, cz + 0.18)
	for lx in [cx - 0.17, cx + 0.17]:
		for lz in [cz - 0.17, cz + 0.15]:
			bx("furn", lx - 0.017, lx + 0.017, 0.0, 0.43, lz - 0.017, lz + 0.017)
		bx("furn", lx - 0.018, lx + 0.018, 0.46, 0.92, cz + 0.13, cz + 0.17)
	bx("furn", cx - 0.19, cx + 0.19, 0.78, 0.9, cz + 0.135, cz + 0.165)
	bx("furn", cx - 0.19, cx + 0.19, 0.6, 0.63, cz + 0.14, cz + 0.16)


## 饭桌：折叠圆桌铺着桌布、两只方凳塞在底下；桌上碗、盘子扣着纱罩、茶壶
func _table(other: Color) -> void:
	var c := Vector3(8.0, 0.0, -1.0)
	for a in [0.5, -0.5]:
		tube("metal", PackedVector3Array([c + Vector3(-0.32, 0, a * 0.5), c + Vector3(0.32, 0.68, -a * 0.5)]), 0.014, 5)
		tube("metal", PackedVector3Array([c + Vector3(0.32, 0, a * 0.5), c + Vector3(-0.32, 0.68, -a * 0.5)]), 0.014, 5)
	cyl("furn", c + Vector3(0, 0.69, 0), 0.5, 0.5, 0.03, 24)
	cyl("cloth", c + Vector3(0, 0.6, 0), 0.53, 0.53, 0.125, 24, other.lerp(Color("#f1ead8"), 0.62))
	for k in 12:
		var a := TAU * float(k) / 12.0
		bx("cloth", c.x + cos(a) * 0.5 - 0.03, c.x + cos(a) * 0.5 + 0.03, 0.722, 0.726, c.z + sin(a) * 0.5 - 0.03, c.z + sin(a) * 0.5 + 0.03, other.lerp(Color.WHITE, 0.3))
	var top := 0.725
	# 碗、盘子、纱罩、茶壶
	for p in [Vector3(-0.2, 0, 0.18), Vector3(0.18, 0, 0.2)]:
		cyl("enamel", c + p + Vector3(0, top, 0), 0.04, 0.075, 0.06, 12, Color("#f2efe8"))
		cyl("enamel", c + p + Vector3(0, top + 0.06, 0), 0.076, 0.076, 0.006, 12, Color("#3b5f9a"))
		bx("bamboo", c.x + p.x - 0.01, c.x + p.x + 0.11, top + 0.065, top + 0.07, c.z + p.z - 0.006, c.z + p.z + 0.006)
	cyl("enamel", c + Vector3(0.0, top, -0.15), 0.13, 0.15, 0.015, 14, Color("#f0ece2"))
	_ell("cloth", c + Vector3(0.0, top + 0.015, -0.15), Vector3(0.17, 0.12, 0.17), Color("#9fb7a8"), 12, 6)
	_ell("enamel", c + Vector3(0.28, top + 0.08, -0.12), Vector3(0.08, 0.075, 0.08), Color("#ece4cf"))
	tube("enamel", PackedVector3Array([c + Vector3(0.35, top + 0.08, -0.12), c + Vector3(0.43, top + 0.15, -0.12)]), 0.012, 5)
	# 两只方凳塞在桌底下
	for sx in [-0.32, 0.32]:
		var s := c + Vector3(sx, 0, -0.08)
		bx("furn_light", s.x - 0.15, s.x + 0.15, 0.4, 0.43, s.z - 0.15, s.z + 0.15)
		for dx in [-0.12, 0.12]:
			for dz in [-0.12, 0.12]:
				bx("furn_light", s.x + dx - 0.016, s.x + dx + 0.016, 0.0, 0.4, s.z + dz - 0.016, s.z + dz + 0.016)
	# 吊灯：花线、搪瓷灯罩
	tube("rubber", PackedVector3Array([Vector3(8.0, CEIL, -0.95), Vector3(8.0, 3.55, -0.95)]), 0.007, 4)
	cyl("enamel", Vector3(8.0, 3.38, -0.95), 0.26, 0.05, 0.17, 16, Color("#e7e3d6"))
	cyl("metal", Vector3(8.0, 3.53, -0.95), 0.03, 0.03, 0.04, 8)
	_ell("bulb", Vector3(8.0, 3.36, -0.95), Vector3(0.05, 0.06, 0.05))
	bx("concrete", 7.9, 8.1, CEIL - 0.02, CEIL, -1.05, -0.85)


## 脸盆架：三条腿的木架子、搪瓷盆、毛巾、小镜子；脚边两只暖瓶
func _basin(acc: Color) -> void:
	var c := Vector3(10.7, 0.0, -0.82)
	for k in 3:
		var a := TAU * float(k) / 3.0 + 0.5
		var foot := c + Vector3(cos(a) * 0.24, 0, sin(a) * 0.2)
		var top := c + Vector3(cos(a) * 0.19, 0.74, sin(a) * 0.16)
		tube("furn", PackedVector3Array([foot, top]), 0.018, 5)
	cyl("furn", c + Vector3(0, 0.72, 0), 0.21, 0.21, 0.025, 14)
	cyl("enamel", c + Vector3(0, 0.745, 0), 0.15, 0.22, 0.09, 16, Color("#efece4"))
	cyl("enamel", c + Vector3(0, 0.83, 0), 0.225, 0.225, 0.01, 16, acc)
	cyl("water", c + Vector3(0, 0.8, 0), 0.19, 0.19, 0.005, 16)
	# 后头两根立柱、横杆上搭着毛巾、顶上小镜子
	for dx in [-0.17, 0.17]:
		tube("furn", PackedVector3Array([c + Vector3(dx, 0.72, -0.17), c + Vector3(dx, 1.55, -0.2)]), 0.016, 5)
	tube("furn", PackedVector3Array([c + Vector3(-0.19, 1.3, -0.2), c + Vector3(0.19, 1.3, -0.2)]), 0.012, 5)
	bx("cloth", c.x - 0.13, c.x + 0.13, 0.98, 1.31, c.z - 0.215, c.z - 0.19, Color("#f1ede2"))
	bx("cloth", c.x - 0.13, c.x + 0.13, 1.06, 1.1, c.z - 0.19, c.z - 0.185, acc)
	bx("furn", c.x - 0.15, c.x + 0.15, 1.42, 1.66, c.z - 0.22, c.z - 0.2)
	bx("chrome", c.x - 0.13, c.x + 0.13, 1.44, 1.64, c.z - 0.2, c.z - 0.195)
	# 暖瓶：竹壳的、铁皮印花的
	cyl("bamboo", Vector3(10.2, 0, -1.05), 0.07, 0.07, 0.36, 10)
	cyl("enamel", Vector3(10.2, 0.36, -1.05), 0.05, 0.035, 0.06, 10, Color("#cfc9b8"))
	cyl("furn_light", Vector3(10.2, 0.42, -1.05), 0.03, 0.028, 0.035, 8)
	cyl("enamel", Vector3(11.2, 0, -1.1), 0.07, 0.07, 0.36, 10, Color("#b8483a"))
	cyl("enamel", Vector3(11.2, 0.36, -1.1), 0.05, 0.035, 0.06, 10, Color("#d9c99a"))
	cyl("furn_light", Vector3(11.2, 0.42, -1.1), 0.03, 0.028, 0.035, 8)
	# 墙根一个搪瓷盆、一个漱口缸（地上）
	cyl("enamel", Vector3(10.15, 0, -1.6), 0.2, 0.26, 0.08, 14, Color("#e9e4d6"))
	cyl("enamel", Vector3(10.15, 0.08, -1.6), 0.262, 0.262, 0.008, 14, Color("#3b5f9a"))


func _wall_bits(acc: Color) -> void:
	# 挂历：两扇窗中间
	var cx := 6.6
	bx("paper", cx - 0.21, cx + 0.21, 2.15, 3.05, ZB, ZB + 0.01, Color("#efe8d8"))
	bx("paper", cx - 0.19, cx + 0.19, 2.55, 3.0, ZB + 0.01, ZB + 0.012, Color("#7f9fb6"))
	bx("paper", cx - 0.19, cx + 0.19, 2.55, 2.72, ZB + 0.012, ZB + 0.014, Color("#5d7f55"))
	bx("paper", cx - 0.03, cx + 0.15, 2.82, 2.96, ZB + 0.012, ZB + 0.014, Color("#d27a5a"))
	for r in 4:
		bx("sign_ink", cx - 0.17, cx + 0.17, 2.24 + r * 0.075, 2.25 + r * 0.075, ZB + 0.012, ZB + 0.014)
	bx("sign_red", cx - 0.17, cx + 0.17, 2.47, 2.52, ZB + 0.012, ZB + 0.014)
	# 日光灯：铁皮灯架、灯管、拉线开关
	bx("metal_white", 2.55, 3.85, 3.62, 3.68, ZB, ZB + 0.08)
	Kit.box_into(_tool("bulb"), Vector3(1.2, 0.035, 0.035), Transform3D(Basis(), Vector3(3.2, 3.6, ZB + 0.1)))
	tube("metal_white", PackedVector3Array([Vector3(3.9, 3.66, ZB + 0.02), Vector3(3.9, CEIL, ZB + 0.02)]), 0.008, 4)
	# 电线：沿墙走的明线、开关盒
	bx("metal_white", 11.6, 11.68, 1.35, 1.47, ZB, ZB + 0.03)
	bx("metal_white", 11.62, 11.65, 1.47, CEIL, ZB, ZB + 0.015)
	# 门边挂的书包
	bx("tint", 11.55, 11.8, 1.0, 1.3, ZB + 0.02, ZB + 0.12, acc.darkened(0.25))
	tube("tint", PackedVector3Array([Vector3(11.6, 1.3, ZB + 0.06), Vector3(11.67, 1.55, ZB + 0.03), Vector3(11.75, 1.3, ZB + 0.06)]), 0.008, 4)


# ======================================================================
# 楼道：门、春联、奶箱、暖气片、电表箱、拉线灯、小板凳、上楼顶的铁梯子
# ======================================================================

func _hallway() -> void:
	# 暖气片（青家门边）
	for k in 5:
		var fx := 13.47 + k * 0.085
		bx("silver", fx, fx + 0.065, 0.14, 0.7, ZB + 0.05, ZB + 0.18)
	tube("silver", PackedVector3Array([Vector3(13.5, 0.75, ZB + 0.1), Vector3(13.5, CEIL, ZB + 0.1)]), 0.016, 6)
	# 电表箱：铁皮箱、玻璃窗里三块表，线往上走
	var ex := 15.9
	bx("metal_green", ex - 0.55, ex + 0.55, 2.85, 3.6, ZB, ZB + 0.16)
	bx("pane", ex - 0.45, ex + 0.45, 3.0, 3.45, ZB + 0.16, ZB + 0.165)
	for k in 3:
		bx("metal_white", ex - 0.4 + k * 0.28, ex - 0.18 + k * 0.28, 3.05, 3.4, ZB + 0.08, ZB + 0.14)
		bx("sign_ink", ex - 0.36 + k * 0.28, ex - 0.22 + k * 0.28, 3.25, 3.3, ZB + 0.14, ZB + 0.145)
	for k in 4:
		tube("rubber", PackedVector3Array([Vector3(ex - 0.3 + k * 0.2, 3.6, ZB + 0.08), Vector3(ex - 0.3 + k * 0.2, CEIL, ZB + 0.06)]), 0.008, 4)
	_wire(Vector3(ex + 0.55, 3.3, ZB + 0.08), Vector3(19.4, 2.5, ZB + 0.03), 0.2)
	_wire(Vector3(ex - 0.55, 3.3, ZB + 0.08), Vector3(12.6, 2.45, ZB + 0.03), 0.25)
	# 拉线灯：花线吊着灯头、灯泡，一根拉线垂下来
	var bp := Vector3(16.3, 3.55, -1.5)
	tube("rubber", PackedVector3Array([Vector3(bp.x, CEIL, bp.z), bp + Vector3(0, 0.08, 0)]), 0.006, 4)
	cyl("rubber", bp + Vector3(0, 0.0, 0), 0.025, 0.025, 0.08, 8)
	_ell("bulb", bp + Vector3(0, -0.05, 0), Vector3(0.04, 0.055, 0.04))
	tube("paper", PackedVector3Array([bp + Vector3(0.02, 0.05, 0), bp + Vector3(0.03, -1.45, 0.01)]), 0.003, 3)
	_ell("tint", bp + Vector3(0.03, -1.47, 0.01), Vector3(0.015, 0.02, 0.015), Color("#c8b48a"))
	_add_lamp(bp + Vector3(0, -0.25, 0.3), Color(1.0, 0.76, 0.46), 5.8, 1.5, 0.22)
	# 小板凳
	var sx := 14.8
	bx("wood_green", sx - 0.18, sx + 0.18, 0.26, 0.29, -0.72, -0.5)
	for dx in [-0.15, 0.15]:
		bx("wood_green", sx + dx - 0.015, sx + dx + 0.015, 0.0, 0.26, -0.7, -0.52)
	# 上楼顶的铁梯子：贴着后墙一直通到屋顶板的检修口
	var lx := 17.4
	for dx in [-0.22, 0.22]:
		tube("iron", PackedVector3Array([Vector3(lx + dx, 0.0, ZB + 0.24), Vector3(lx + dx, ROOF + 0.9, ZB + 0.24)]), 0.02, 6)
		bx("metal", lx + dx - 0.02, lx + dx + 0.02, 1.0, 1.04, ZB, ZB + 0.24)
		bx("metal", lx + dx - 0.02, lx + dx + 0.02, 3.2, 3.24, ZB, ZB + 0.24)
	var ry := 0.25
	while ry < ROOF + 0.6:
		tube("iron", PackedVector3Array([Vector3(lx - 0.22, ry, ZB + 0.24), Vector3(lx + 0.22, ry, ZB + 0.24)]), 0.011, 5)
		ry += 0.3
	# 检修口的铁框
	bx("metal", HATCH.position.x - 0.04, HATCH.end.x + 0.04, CEIL - 0.05, CEIL, HATCH.end.y, HATCH.end.y + 0.05)
	# 往下的箭头那儿：墙上刷的楼层号
	_label("3", Vector3(14.6, 2.75, ZB + 0.01), 0.008, Color("#b53a30"))


## 楼道的门：小时候、少年是刷漆的木门（青家绿、梅家红），青年起换防盗门。春联、福字、门牌一直在
func _hall_doors() -> void:
	for spec in [["qing", 13.0, "301"], ["mei", 19.0, "302"]]:
		var role: String = spec[0]
		var dx: float = spec[1]
		var acc: Color = ACC[role]
		var keep := Node3D.new()
		add_child(keep)
		_begin()
		# 门框、门洞里头黑黢黢的门厅（门关着看不见，留一圈门框）
		bx("furn_light", dx - 0.46, dx + 0.46, 2.1, 2.18, ZB - 0.05, ZB + 0.04)
		bx("furn_light", dx - 0.46, dx - 0.4, 0.0, 2.18, ZB - 0.05, ZB + 0.04)
		bx("furn_light", dx + 0.4, dx + 0.46, 0.0, 2.18, ZB - 0.05, ZB + 0.04)
		# 春联、横批、门牌
		bx("paper", dx - 0.62, dx - 0.5, 0.55, 2.0, ZB, ZB + 0.006, Color("#c8352c"))
		bx("paper", dx + 0.5, dx + 0.62, 0.55, 2.0, ZB, ZB + 0.006, Color("#c8352c"))
		bx("paper", dx - 0.4, dx + 0.4, 2.22, 2.36, ZB, ZB + 0.006, Color("#c8352c"))
		bx("metal_white", dx - 0.14, dx + 0.14, 2.42, 2.56, ZB, ZB + 0.012)
		_commit(keep)
		var plate := _label(str(spec[2]), Vector3(dx, 2.49, ZB + 0.014), 0.0026, acc.darkened(0.2))
		plate.reparent(keep, false)
		var lines := ["一帆风顺年年好", "万事如意步步高"] if role == "qing" else ["春回大地千山秀", "福满人间万户欢"]
		for k in 2:
			var cx := dx - 0.56 if k == 0 else dx + 0.56
			var l := _label(_vert(str(lines[k])), Vector3(cx, 1.28, ZB + 0.008), 0.0026, Color("#1d1a18"))
			l.line_spacing = 0.0
			l.reparent(keep, false)
		var hp := _label("吉祥如意" if role == "qing" else "四季平安", Vector3(dx, 2.29, ZB + 0.008), 0.0025, Color("#1d1a18"))
		hp.reparent(keep, false)
		# 木门：刷漆、上下两块门芯板、把手；门上倒贴一个福
		var old := Node3D.new()
		add_child(old)
		_begin()
		var key := "wood_green" if role == "qing" else "wood_red"
		bx(key, dx - 0.4, dx + 0.4, 0.0, 2.1, ZB - 0.06, ZB - 0.02)
		bx(key, dx - 0.32, dx + 0.32, 1.15, 1.95, ZB - 0.02, ZB - 0.005)
		bx(key, dx - 0.32, dx + 0.32, 0.15, 1.0, ZB - 0.02, ZB - 0.005)
		bx("brass", dx + 0.27, dx + 0.31, 0.98, 1.08, ZB - 0.005, ZB + 0.03)
		bx("metal", dx - 0.05, dx + 0.05, 1.55, 1.58, ZB - 0.005, ZB + 0.002)
		Kit.box_into(_tool("paper"), Vector3(0.3, 0.3, 0.006), Transform3D(Basis(Vector3.BACK, PI / 4.0), Vector3(dx, 1.55, ZB - 0.0)), Color("#c8352c"))
		_commit(old)
		var fu := _label("福", Vector3(dx, 1.55, ZB + 0.005), 0.0052, Color("#1d1a18"))
		fu.rotation = Vector3(0, 0, PI)
		fu.reparent(old, false)
		_era_nodes.append([old, 0, 1])
		# 防盗门：铁的、压出来的花、猫眼、不锈钢把手
		var steel := Node3D.new()
		add_child(steel)
		_begin()
		var sc := Color("#6a5348") if role == "qing" else Color("#5a5a5e")
		bx("enamel", dx - 0.41, dx + 0.41, 0.0, 2.1, ZB - 0.07, ZB - 0.02, sc)
		for gy in [0.2, 0.75, 1.3]:
			bx("enamel", dx - 0.3, dx + 0.3, gy, gy + 0.45, ZB - 0.02, ZB - 0.008, sc.lightened(0.08))
		bx("chrome", dx + 0.24, dx + 0.34, 0.98, 1.03, ZB - 0.008, ZB + 0.04)
		bx("chrome", dx + 0.27, dx + 0.31, 0.85, 1.2, ZB - 0.008, ZB + 0.004)
		cyl("chrome", Vector3(dx, 1.5, ZB - 0.01), 0.012, 0.012, 0.0, 6)
		Kit.box_into(_tool("paper"), Vector3(0.3, 0.3, 0.006), Transform3D(Basis(Vector3.BACK, PI / 4.0), Vector3(dx, 1.62, ZB - 0.005)), Color("#c8352c"))
		_commit(steel)
		var fu2 := _label("福", Vector3(dx, 1.62, ZB + 0.0), 0.0052, Color("#1d1a18"))
		fu2.rotation = Vector3(0, 0, PI)
		fu2.reparent(steel, false)
		_era_nodes.append([steel, 2, 4])


## 楼道里一个年代一换的：堆的东西（hall_pile 14.0）和墙上的小广告
func _hall_era() -> void:
	var px := 14.35
	# 小时候：蜂窝煤码到窗台，上头两棵白菜；一辆二八车
	var n := Node3D.new()
	add_child(n)
	_begin()
	bx("coal", 13.92, 14.78, 0.0, 1.18, ZB + 0.02, ZB + 0.4)
	for r in 13:
		for c in 7:
			cyl("coal", Vector3(13.98 + c * 0.12, 0.05 + r * 0.088, ZB + 0.4), 0.058, 0.058, 0.0, 8)
			_ell("rubber", Vector3(13.98 + c * 0.12, 0.05 + r * 0.088, ZB + 0.402), Vector3(0.01, 0.01, 0.003), Color.WHITE, 5, 3)
	_ell("tint", Vector3(14.15, 1.3, ZB + 0.2), Vector3(0.12, 0.13, 0.22), Color("#c9d6a4"), 10, 6)
	_ell("tint", Vector3(14.48, 1.28, ZB + 0.22), Vector3(0.11, 0.12, 0.21), Color("#b9cc8e"), 10, 6)
	_bike(Vector3(px - 0.1, 0, -1.55), 0.05, false, "metal")
	bx("tint", px - 0.38, px - 0.16, 0.98, 1.03, -1.6, -1.48, Color("#3c6aa8"))
	_commit(n)
	_era_nodes.append([n, 0, 0])
	# 少年：山地车锁在暖气管上，几个纸箱「别扔」
	n = Node3D.new()
	add_child(n)
	_begin()
	_bike(Vector3(px + 0.05, 0, -1.6), -0.05, false, "sign_red")
	for k in 3:
		var bw := 0.42 - k * 0.06
		var by := k * 0.3
		bx("tint", 14.0 + k * 0.04, 14.0 + k * 0.04 + bw, by, by + 0.3, ZB + 0.05, ZB + 0.45, Color("#b08a5c").darkened(k * 0.05))
	var l := _label("别扔", Vector3(14.21, 0.15, ZB + 0.452), 0.003, Color("#2b2a33"))
	l.reparent(n, false)
	_commit(n)
	_era_nodes.append([n, 1, 1])
	# 青年：电动车，充电线从门缝里拉出来
	n = Node3D.new()
	add_child(n)
	_begin()
	_ebike(Vector3(px, 0, -1.55))
	tube("rubber", PackedVector3Array([Vector3(13.4, 0.9, ZB), Vector3(13.6, 0.02, -1.6), Vector3(14.0, 0.02, -1.6), Vector3(14.2, 0.55, -1.55)]), 0.006, 4)
	_commit(n)
	_era_nodes.append([n, 2, 2])
	# 中年：快递盒子、婴儿车、一把折起来的轮椅
	n = Node3D.new()
	add_child(n)
	_begin()
	for k in 5:
		var w := _rng.randf_range(0.25, 0.45)
		var h := _rng.randf_range(0.12, 0.3)
		var ox := 13.62 + (k % 3) * 0.3
		var oy := 0.0 if k < 3 else 0.3
		bc("tint", Vector3(ox + w / 2.0, oy + h / 2.0, ZB + 0.3), Vector3(w, h, 0.35), _rng.randf_range(-0.2, 0.2), 0.0, Color("#b89466").darkened(_rng.randf() * 0.15))
		bx("paper", ox + 0.05, ox + 0.15, oy + h * 0.3, oy + h * 0.7, ZB + 0.476, ZB + 0.48, Color("#f2f0ea"))
	# 婴儿车：车架、篷、四个小轮
	var bp := Vector3(14.55, 0, -1.45)
	for dx in [-0.22, 0.22]:
		for dz in [-0.2, 0.2]:
			cyl("rubber", bp + Vector3(dx, 0.0, dz), 0.06, 0.06, 0.03, 8)
	bx("tint", bp.x - 0.28, bp.x + 0.28, 0.3, 0.55, bp.z - 0.2, bp.z + 0.2, Color("#5b6f8f"))
	_ell("tint", bp + Vector3(-0.15, 0.62, 0), Vector3(0.2, 0.22, 0.22), Color("#4a5c78"), 10, 6)
	tube("chrome", PackedVector3Array([bp + Vector3(-0.22, 0.06, 0.2), bp + Vector3(0.3, 0.55, 0.2), bp + Vector3(0.42, 0.95, 0.2)]), 0.012, 5)
	tube("chrome", PackedVector3Array([bp + Vector3(-0.22, 0.06, -0.2), bp + Vector3(0.3, 0.55, -0.2), bp + Vector3(0.42, 0.95, -0.2)]), 0.012, 5)
	tube("rubber", PackedVector3Array([bp + Vector3(0.42, 0.95, 0.2), bp + Vector3(0.42, 0.95, -0.2)]), 0.018, 5)
	# 轮椅折着靠墙
	var wp := Vector3(13.4, 0, ZB + 0.45)
	_ring_b("rubber", wp + Vector3(0, 0.3, 0), 0.3, 0.02, Basis(Vector3.UP, 0.2))
	_ring_b("chrome", wp + Vector3(0, 0.3, 0), 0.26, 0.008, Basis(Vector3.UP, 0.2))
	tube("chrome", PackedVector3Array([wp + Vector3(-0.2, 0.05, 0.05), wp + Vector3(-0.2, 0.95, 0.05), wp + Vector3(-0.1, 0.98, 0.05)]), 0.012, 5)
	tube("chrome", PackedVector3Array([wp + Vector3(0.2, 0.05, 0.1), wp + Vector3(0.2, 0.95, 0.1)]), 0.012, 5)
	_commit(n)
	_era_nodes.append([n, 3, 3])
	# 老了：空了，地上拖过的印子
	n = Node3D.new()
	add_child(n)
	_begin()
	for k in 3:
		_roll("coal", Vector3(14.1 + k * 0.25, 0.002, -1.6), Vector3(0.9, 0.003, 0.04), 0.0, Color.WHITE)
	bx("floor_hall", 13.9, 14.8, 0.0, 0.004, ZB + 0.02, ZB + 0.42)
	_commit(n)
	for c in n.get_children():
		(c as MeshInstance3D).transparency = 0.5
	_era_nodes.append([n, 4, 4])
	# 小广告：年代越后越多；开锁、通下水
	var counts := [1, 3, 9, 14, 7]
	for e in 5:
		n = Node3D.new()
		add_child(n)
		_begin()
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + e
		for k in int(counts[e]):
			var ax := rng.randf_range(12.3, 19.6)
			if absf(ax - 13.0) < 0.55 or absf(ax - 19.0) < 0.55 or (ax > 13.85 and ax < 14.85):
				ax += 1.1
			var ay := rng.randf_range(0.5, 2.2)
			var aw := rng.randf_range(0.1, 0.22)
			var col: Color = [Color("#f1ece0"), Color("#efe6a8"), Color("#f2c9b8"), Color("#dfe6ee")][rng.randi() % 4]
			if e == 4:
				col = col.darkened(0.15)
			bx("paper", ax, ax + aw, ay, ay + aw * 1.3, ZB, ZB + 0.004 + k * 0.0002, col)
			bx("sign_ink", ax + 0.02, ax + aw - 0.02, ay + aw * 0.9, ay + aw * 0.98, ZB + 0.005, ZB + 0.006 + k * 0.0002)
		_commit(n)
		if e == 2 or e == 3:
			var t1 := _label("开锁", Vector3(18.0, 1.9, ZB + 0.006), 0.003, Color("#c03a2e"))
			t1.reparent(n, false)
			var t2 := _label("通下水", Vector3(15.7, 1.35, ZB + 0.006), 0.0034, Color("#2b2a33"))
			t2.reparent(n, false)
		if e == 0:
			var t0 := _label("通  知", Vector3(16.0, 2.1, ZB + 0.008), 0.0034, Color("#2b2a33"))
			t0.reparent(n, false)
			bx("paper", 15.75, 16.25, 1.75, 2.2, ZB, ZB + 0.005, Color("#f3eedf"))
			var nn := Node3D.new()
			n.add_child(nn)
			_commit(nn)
		_era_nodes.append([n, e, e])


## 竖排的字（春联）：一个字一行
func _vert(t: String) -> String:
	var out := ""
	for i in t.length():
		out += t[i] + ("\n" if i < t.length() - 1 else "")
	return out


func _ebike(at: Vector3) -> void:
	var r := 0.22
	_ring_b("rubber", at + Vector3(-0.55, r, 0), r, 0.035, Basis())
	_ring_b("rubber", at + Vector3(0.55, r, 0), r, 0.035, Basis())
	_ell("enamel", at + Vector3(-0.55, r, 0), Vector3(0.1, 0.1, 0.03), Color("#9aa0a6"), 8, 4)
	_ell("enamel", at + Vector3(0.55, r, 0), Vector3(0.1, 0.1, 0.03), Color("#9aa0a6"), 8, 4)
	bc("enamel", at + Vector3(-0.05, 0.36, 0), Vector3(0.75, 0.14, 0.24), 0.0, 0.0, Color("#e8e6e0"))
	_roll("enamel", at + Vector3(0.4, 0.6, 0), Vector3(0.12, 0.6, 0.26), -0.35, Color("#e8e6e0"))
	bc("rubber", at + Vector3(-0.25, 0.62, 0), Vector3(0.5, 0.1, 0.26), 0.0, 0.0)
	tube("metal", PackedVector3Array([at + Vector3(0.5, 0.88, -0.3), at + Vector3(0.5, 0.92, 0.3)]), 0.015, 5)
	bc("tint", at + Vector3(0.58, 0.82, 0), Vector3(0.08, 0.1, 0.16), 0.0, 0.0, Color("#2b2a33"))
	bc("tint", at + Vector3(-0.62, 0.62, 0), Vector3(0.3, 0.22, 0.3), 0.0, 0.0, Color("#2b2a33"))


# ======================================================================
# 楼顶：女儿墙、鸽子棚、晾衣绳、楼梯间小屋、水箱、天线、花盆凉席
# ======================================================================

func _roof() -> void:
	# 楼顶面：中间平台铺隔热砖，两头油毡
	bx("roof_tile", 9.75, 22.25, ROOF - 0.02, ROOF, ZB - 0.28, ZF - 0.24)
	bx("tar", -0.36, 9.75, ROOF - 0.02, ROOF + 0.005, ZB - 0.28, ZF - 0.24)
	bx("tar", 22.25, W + 0.36, ROOF - 0.02, ROOF + 0.005, ZB - 0.28, ZF - 0.24)
	# 女儿墙：后头一米高，前头矮（平台那段只到小腿）
	bx("brick", -0.36, W + 0.36, ROOF, ROOF + 0.95, ZB - 0.3, ZB - 0.06)
	bx("concrete", -0.4, W + 0.4, ROOF + 0.95, ROOF + 1.03, ZB - 0.34, ZB - 0.02)
	bx("brick", -0.36, 9.75, ROOF, ROOF + 0.72, ZF - 0.24, ZF)
	bx("brick", 22.25, W + 0.36, ROOF, ROOF + 0.72, ZF - 0.24, ZF)
	bx("concrete", -0.4, 9.75, ROOF + 0.72, ROOF + 0.8, ZF - 0.28, ZF + 0.04)
	bx("concrete", 22.25, W + 0.4, ROOF + 0.72, ROOF + 0.8, ZF - 0.28, ZF + 0.04)
	bx("brick", 9.75, 22.25, ROOF, ROOF + 0.1, ZF - 0.24, ZF)
	bx("concrete", 9.7, 22.3, ROOF + 0.1, ROOF + 0.15, ZF - 0.28, ZF + 0.04)
	# 平台两头的铁栏杆
	for x in [9.7, 22.3]:
		for k in 6:
			var z := ZB + 0.1 + k * 0.62
			cyl("iron", Vector3(x, ROOF, z), 0.018, 0.018, 0.95, 6)
		tube("iron", PackedVector3Array([Vector3(x, ROOF + 0.95, ZB - 0.05), Vector3(x, ROOF + 0.95, ZF - 0.25)]), 0.022, 6)
		tube("iron", PackedVector3Array([Vector3(x, ROOF + 0.5, ZB - 0.05), Vector3(x, ROOF + 0.5, ZF - 0.25)]), 0.014, 6)
	# 楼梯间小屋：红砖、平顶、一扇半开的铁皮门，门头一盏灯
	var hx0 := 16.5
	var hx1 := 18.4
	var hz0 := ZB - 0.3
	var hz1 := -0.7
	var top := ROOF + 2.45
	wall("brick", hx0, hx1, ROOF, top, hz1, 0.24, [Rect2(16.97, ROOF, 0.86, 2.05)])
	bx("brick", hx0, hx0 + 0.24, ROOF, top, hz0, hz1 - 0.24)
	bx("brick", hx1 - 0.24, hx1, ROOF, top, hz0, hz1 - 0.24)
	bx("concrete", hx0 - 0.12, hx1 + 0.12, top, top + 0.14, hz0 - 0.1, hz1 + 0.12)
	bx("tar", hx0 - 0.1, hx1 + 0.1, top + 0.14, top + 0.16, hz0 - 0.08, hz1 + 0.1)
	bx("coal", hx0 + 0.24, hx1 - 0.24, ROOF, top, hz0, hz0 + 0.05)
	bx("concrete", 16.9, 17.9, ROOF + 2.05, ROOF + 2.13, hz1 - 0.24, hz1 + 0.04)
	Kit.box_into(_tool("iron"), Vector3(0.84, 2.0, 0.035), Transform3D(Basis(Vector3.UP, -1.1), Vector3(16.97 + 0.42 * cos(1.1) - 0.02, ROOF + 1.02, hz1 + 0.42 * sin(1.1) - 0.02)))
	bx("metal", 17.35, 17.45, ROOF + 2.2, ROOF + 2.28, hz1, hz1 + 0.15)
	_ell("bulb", Vector3(17.4, ROOF + 2.17, hz1 + 0.12), Vector3(0.04, 0.05, 0.04))
	_add_lamp(Vector3(17.4, ROOF + 1.9, hz1 + 0.6), Color(1.0, 0.78, 0.5), 5.5, 1.0)
	# 晾衣绳：两根铁杆，一根绳，床单、被单、毛巾（小屋门前留空）
	var l0 := 13.95
	var l1 := 21.7
	var lz := -0.55
	for x in [l0, l1]:
		cyl("metal", Vector3(x, ROOF, lz), 0.025, 0.022, 2.05, 6)
		bx("metal", x - 0.02, x + 0.02, ROOF + 1.95, ROOF + 1.99, lz - 0.2, lz + 0.2)
	var pts := PackedVector3Array()
	for i in 17:
		var t := float(i) / 16.0
		pts.append(Vector3(lerpf(l0, l1, t), ROOF + 1.97 - 0.2 * 4.0 * t * (1.0 - t), lz))
	tube("rubber", pts, 0.006, 3)
	var sheets := [[14.2, 15.3, Color("#ece7da"), 1.25], [15.45, 16.35, Color("#d9e0d0"), 1.05], [18.05, 19.25, Color("#e9d7c8"), 1.3],
		[19.4, 19.75, Color("#b5463c"), 0.55], [19.9, 21.2, Color("#dfe6ee"), 1.2]]
	for s in sheets:
		var sx0: float = s[0]
		var sx1: float = s[1]
		var t0 := (sx0 - l0) / (l1 - l0)
		var t1 := (sx1 - l0) / (l1 - l0)
		var y0 := ROOF + 1.97 - 0.2 * 4.0 * t0 * (1.0 - t0)
		var y1 := ROOF + 1.97 - 0.2 * 4.0 * t1 * (1.0 - t1)
		var yt := minf(y0, y1)
		var col: Color = s[2]
		var hh: float = s[3]
		# 一块布：几道竖褶，前后错一点
		var nk := int(ceil((sx1 - sx0) / 0.14))
		for k in nk:
			var fx0 := sx0 + (sx1 - sx0) * float(k) / float(nk)
			var fx1 := sx0 + (sx1 - sx0) * float(k + 1) / float(nk)
			var fz := lz + (0.018 if k % 2 == 0 else -0.012)
			bx("cloth", fx0, fx1 + 0.003, yt - hh + 0.04 * sin(float(k)), yt, fz - 0.006, fz + 0.006, col.darkened(0.04 * float(k % 2)))
		if col.r > 0.85 and col.g > 0.85:
			bx("cloth", sx0, sx1, yt - hh * 0.55, yt - hh * 0.48, lz - 0.02, lz + 0.026, Color("#7d98b6"))
		for x in [sx0 + 0.03, sx1 - 0.03]:
			bx("wood_light", x - 0.012, x + 0.012, yt - 0.04, yt + 0.03, lz - 0.015, lz + 0.015)
	# 水箱（平台外头）：铁架子上一个大铁皮箱
	for dx in [23.15, 24.65]:
		for dz in [-2.45, -1.55]:
			bx("metal", dx - 0.03, dx + 0.03, ROOF, ROOF + 0.5, dz - 0.03, dz + 0.03)
	bx("iron", 23.05, 24.75, ROOF + 0.5, ROOF + 1.55, -2.55, -1.45)
	cyl("metal", Vector3(23.4, ROOF + 1.55, -2.0), 0.15, 0.15, 0.08, 10)
	tube("metal", PackedVector3Array([Vector3(24.75, ROOF + 0.8, -2.0), Vector3(25.2, ROOF + 0.8, -2.0), Vector3(25.2, ROOF, -2.0)]), 0.03, 6)
	# 平台左头：卷着的凉席、几个花盆（葱、月季）
	for k in 2:
		var fx := 10.85 + k * 0.42
		cyl("bamboo", Vector3(fx, ROOF, -1.0 - k * 0.1), 0.11, 0.11, 0.95, 10)
	for p in [[10.3, -2.1, 0.13], [10.65, -2.25, 0.1], [21.6, -2.15, 0.12], [21.25, -2.3, 0.09]]:
		var pc := Vector3(float(p[0]), ROOF, float(p[1]))
		var pr: float = p[2]
		cyl("wood_red", pc, pr * 0.8, pr, pr * 1.6, 10)
		_ell("tint", pc + Vector3(0, pr * 1.6 + pr * 0.6, 0), Vector3(pr * 1.4, pr * 1.2, pr * 1.3), Color("#4f7d3c").lerp(Color("#6f9a46"), _rng.randf()))
	# 鸽子棚（小时候到青年）在 _roof_era


## 楼顶上一个年代一换的：鸽子棚（小时候到青年），电视天线（小时候、少年），太阳能热水器（青年起）
func _roof_era() -> void:
	var n := Node3D.new()
	add_child(n)
	_begin()
	var cx := 12.5
	var x0 := cx - 1.15
	var x1 := cx + 1.15
	var z0 := ZB - 0.05
	var z1 := -0.8
	var base := ROOF
	var h := 1.45
	# 木框、铁丝网格子、底下一层木板、屋顶油毡坡顶
	bx("furn_light", x0, x1, base, base + 0.35, z0, z1)
	bx("wood", x0, x1, base + 0.35, base + 0.4, z0, z1)
	for k in 5:
		var fx := x0 + (x1 - x0) * float(k) / 4.0
		bx("wood", fx - 0.035, fx + 0.035, base, base + h, z1 - 0.07, z1)
	bx("wood", x0, x1, base + h - 0.05, base + h, z1 - 0.07, z1)
	bx("wood", x0, x1, base + 0.88, base + 0.92, z1 - 0.06, z1)
	var gx := x0
	while gx < x1:
		bx("metal", gx - 0.004, gx + 0.004, base + 0.4, base + h - 0.05, z1 - 0.04, z1 - 0.03)
		gx += 0.07
	var gy := base + 0.4
	while gy < base + h - 0.05:
		bx("metal", x0, x1, gy - 0.004, gy + 0.004, z1 - 0.04, z1 - 0.03)
		gy += 0.07
	bx("coal", x0 + 0.05, x1 - 0.05, base + 0.4, base + h, z0, z0 + 0.04)
	for side in [-1.0, 1.0]:
		var rf := Transform3D(Basis(Vector3.RIGHT, side * 0.42), Vector3(cx, base + h + 0.22, (z0 + z1) / 2.0 + side * 0.5))
		Kit.box_into(_tool("tar"), Vector3(x1 - x0 + 0.3, 0.04, 1.15), rf)
	bx("wood", x0, x0 + 0.06, base, base + h + 0.4, z0 + 0.6, z0 + 0.7)
	bx("wood", x1 - 0.06, x1, base, base + h + 0.4, z0 + 0.6, z0 + 0.7)
	# 鸽子：几只在棚顶、几只在里头
	var doves := [Vector3(cx - 0.5, base + h + 0.5, (z0 + z1) / 2.0 + 0.05), Vector3(cx + 0.1, base + h + 0.52, (z0 + z1) / 2.0), Vector3(cx + 0.65, base + h + 0.46, (z0 + z1) / 2.0 + 0.1),
		Vector3(cx - 0.6, base + 0.98, z1 - 0.25), Vector3(cx + 0.4, base + 0.47, z1 - 0.3)]
	for d in doves:
		var dc: Color = [Color("#8f949c"), Color("#d8d6d0"), Color("#6e737b")][_rng.randi() % 3]
		_ell("tint", d, Vector3(0.1, 0.07, 0.065), dc, 8, 5)
		_ell("tint", d + Vector3(0.08, 0.06, 0), Vector3(0.04, 0.04, 0.04), dc.darkened(0.1), 6, 4)
		_roll("tint", d + Vector3(-0.12, 0.0, 0), Vector3(0.1, 0.02, 0.06), 0.3, dc.darkened(0.25))
	_commit(n)
	_era_nodes.append([n, 0, 2])
	# 鸽子棚拆了以后：地上一块颜色浅的印子、一个空的笼子
	n = Node3D.new()
	add_child(n)
	_begin()
	bx("concrete", x0, x1, ROOF, ROOF + 0.006, z0, z1)
	bx("metal", cx + 0.3, cx + 0.8, ROOF, ROOF + 0.35, -2.2, -1.8)
	_commit(n)
	_era_nodes.append([n, 3, 4])
	# 电视天线：铁杆上一排横杆（鱼骨），拉线
	n = Node3D.new()
	add_child(n)
	_begin()
	for ax in [6.2, 28.6]:
		var b := Vector3(float(ax), ROOF, -2.2)
		cyl("metal", b, 0.025, 0.018, 2.6, 6)
		for k in 6:
			var yy := 1.6 + k * 0.17
			var hw := 0.5 - k * 0.06
			bx("metal", b.x - hw, b.x + hw, b.y + yy, b.y + yy + 0.015, b.z - 0.01, b.z + 0.01)
		tube("metal", PackedVector3Array([b + Vector3(0, 2.2, 0), b + Vector3(-0.9, 0, 0.5)]), 0.004, 3)
		tube("metal", PackedVector3Array([b + Vector3(0, 2.2, 0), b + Vector3(0.9, 0, -0.3)]), 0.004, 3)
	_commit(n)
	_era_nodes.append([n, 0, 1])
	# 太阳能热水器：斜着的一排真空管、上头一根水箱
	n = Node3D.new()
	add_child(n)
	_begin()
	for sx in [3.0, 26.4]:
		var b := Vector3(float(sx), ROOF, -2.4)
		for k in 14:
			var tx := b.x + k * 0.12
			tube("pane", PackedVector3Array([Vector3(tx, b.y + 0.25, b.z + 1.3), Vector3(tx, b.y + 1.15, b.z + 0.1)]), 0.04, 6)
			tube("screen", PackedVector3Array([Vector3(tx, b.y + 0.25, b.z + 1.3), Vector3(tx, b.y + 1.15, b.z + 0.1)]), 0.025, 5)
		var tank := PackedVector3Array([Vector3(b.x - 0.1, b.y + 1.25, b.z + 0.05), Vector3(b.x + 1.75, b.y + 1.25, b.z + 0.05)])
		tube("metal_white", tank, 0.16, 10)
		for fx in [b.x, b.x + 1.6]:
			tube("chrome", PackedVector3Array([Vector3(fx, b.y, b.z + 1.35), Vector3(fx, b.y + 0.25, b.z + 1.3), Vector3(fx, b.y + 1.2, b.z + 0.05), Vector3(fx, b.y, b.z + 0.05)]), 0.015, 4)
	_commit(n)
	_fix_shadows(n)
	_era_nodes.append([n, 2, 4])


## 后头一排排的楼：底在街面（三楼往下两层），夜里一格格窗亮着
func _bg() -> void:
	# 街面（远处、看不见也得有）
	bx("concrete", -30.0, 62.0, DOWN - 0.2, DOWN, -60.0, ZF + 6.0)
	var rows := [[-16.0, 0.0, 3, 5], [-31.0, 6.0, 4, 6], [-52.0, 2.0, 6, 9]]
	for row in rows:
		var bz: float = row[0]
		var x := -22.0 + float(row[1])
		while x < 56.0:
			var w := _rng.randf_range(9.0, 15.0)
			var floors := _rng.randi_range(int(row[2]), int(row[3]))
			var h := floors * 2.9
			var key: String = ["plaster_far", "brick_grey", "plaster_far", "brick"][_rng.randi() % 4]
			bx(key, x, x + w, DOWN, DOWN + h, bz - 10.0, bz)
			bx("concrete", x - 0.05, x + w + 0.05, DOWN + h, DOWN + h + 0.4, bz - 10.0, bz + 0.05)
			for f in floors:
				var wx := x + 0.7
				while wx < x + w - 1.4:
					bx("glass_far", wx, wx + 1.0, DOWN + f * 2.9 + 0.9, DOWN + f * 2.9 + 2.2, bz, bz + 0.03, Color(_rng.randf(), _rng.randf(), _rng.randf()))
					if f > 0 and _rng.randf() < 0.3:
						bx("metal", wx - 0.05, wx + 1.05, DOWN + f * 2.9 + 0.85, DOWN + f * 2.9 + 0.9, bz, bz + 0.35)
					wx += 1.75
			if _rng.randf() < 0.6:
				bx("concrete", x + w * 0.3, x + w * 0.3 + 2.0, DOWN + h + 0.4, DOWN + h + 1.8, bz - 6.0, bz - 4.0)
			if _rng.randf() < 0.5:
				cyl("metal", Vector3(x + w * 0.7, DOWN + h + 0.4, bz - 3.0), 0.03, 0.02, 2.4, 5)
			x += w + _rng.randf_range(1.5, 7.0)
	# 后院：一溜平房的灰瓦顶、院墙
	bx("brick_grey", -4.0, 36.0, DOWN, DOWN + 2.2, -8.5, -8.2)
	bx("tiles", -4.0, 36.0, DOWN + 2.6, DOWN + 3.0, -11.0, -8.5)


# ======================================================================
# 家里的东西：HomeLife.pick 的键单，每样一个节点
# ======================================================================

## 两家现在该摆什么：{role: [键@样子…]}；stage 没有（单测里）就按年代摆个小康的底子
func _wanted() -> Dictionary:
	var wealth := {"qing": 1, "mei": 1}
	var items := {"qing": [], "mei": []}
	var dec: int = int(HomeLife.LOOK_DECADE.get(look, 3))
	if stage != null and "world" in stage and stage.world != null:
		var hm: Variant = stage.world.get("home")
		if hm != null and is_instance_valid(hm):
			wealth = hm.wealth
			items = hm.items
			dec = int(hm.decade)
	var out := {}
	for role in ["qing", "mei"]:
		var w := clampi(int(wealth.get(role, 1)), 0, 2)
		var have: Array = items.get(role, []) if items.get(role) is Array else []
		var keys: Array = HomeLife.pick(w, have, dec)
		var books := have.has("books")
		var l: Array = []
		for k in keys:
			var key := str(k)
			if key.begins_with("radio"):
				key += "@" + ("piano" if w == 2 else ("case" if books else "chest"))
			elif key == "bookcase":
				key += "@" + ("bed" if w == 2 else "corner")
			l.append(key)
		# 家境陈设：屋角平时是五斗柜，殷实人家是一架琴（书柜挪到床后头）
		if w == 2:
			l.append("piano")
		elif not books:
			l.append("chest")
		out[role] = l
	return out


func _update_home(animate: bool) -> void:
	var want := _wanted()
	for role in ["qing", "mei"]:
		var now: Array = want[role]
		var before: Array = _shown.get(role, [])
		for key in before:
			if not now.has(key):
				var nd: Node3D = _items.get(role + "/" + str(key))
				if nd != null:
					nd.visible = false
		for key in now:
			var id: String = role + "/" + str(key)
			var nd: Node3D = _items.get(id)
			if nd == null:
				nd = _make_item(role, str(key))
				_items[id] = nd
			if nd.visible and before.has(key):
				continue
			nd.visible = true
			var m := -1.0 if role == "mei" else 1.0
			if animate and not before.has(key) and _is_thing(str(key)):
				nd.scale = Vector3(0.85 * m, 0.85, 0.85)
				_grow.append([nd, 0.0, m])
			else:
				nd.scale = Vector3(m, 1, 1)
		_shown[role] = now


static func _is_thing(key: String) -> bool:
	return HomeLife._is_item(key.get_slice("@", 0))


## 搭一样东西：按青家坐标画，节点原点挪到东西的底座中心（长出来的时候按这儿缩放），梅家翻过来
func _make_item(role: String, key: String) -> Node3D:
	var acc: Color = ACC[role]
	var nd := Node3D.new()
	nd.name = role + "_" + key.replace("@", "_")
	add_child(nd)
	_begin()
	var pivot := _draw_item(key, acc)
	_commit(nd)
	_fix_shadows(nd)
	for c in nd.get_children():
		(c as Node3D).position = -pivot
	var p := pivot
	if role == "mei":
		p.x = W - p.x
	nd.position = p
	return nd


## 画一样东西，回它的底座中心（青家坐标）
func _draw_item(key: String, acc: Color) -> Vector3:
	var k := key.get_slice("@", 0)
	var how := key.get_slice("@", 1) if key.contains("@") else ""
	if k.begins_with("tv_"):
		var parts := k.split("_")
		return _tv(parts[1], int(parts[2]))
	if k.begins_with("cab_"):
		return _cab(int(k.get_slice("_", 1)))
	if k.begins_with("console_"):
		return _console(int(k.get_slice("_", 1)))
	if k.begins_with("radio"):
		return _radio(how)
	match k:
		"floor_rich":
			bx("lino", 0.02, 11.86, 0.0, 0.006, ZB, 0.86)
			bx("furn", 0.02, 11.86, 0.0, 0.012, 0.84, 0.88)
			return Vector3(6.0, 0, -1.0)
		"curtain":
			return _curtain(acc)
		"sewing":
			return _sewing()
		"sofa":
			return _sofa()
		"clock_round":
			return _clock_round()
		"clock_pendulum":
			return _clock_pendulum()
		"bookcase":
			return _bookcase(how == "bed")
		"chest":
			return _chest(acc)
		"piano":
			return _piano()
		"boxes":
			return _boxes()
		"fridge":
			return _fridge()
		"pc_crt", "pc_lcd":
			return _pc(k == "pc_lcd", acc)
		"tape":
			return _tape()
		"phone":
			return _phone()
		"milk":
			return _milk()
	return Vector3.ZERO


const CAB_TOP := {0: 0.5, 1: 0.62, 2: 0.6}
const TV_X := {0: 9.4, 1: 9.52, 2: 9.52}


func _cab(w: int) -> Vector3:
	var cx := 9.45 if w == 0 else 9.52
	var t: float = CAB_TOP[w]
	if w == 0:
		# 木箱子：一块块木板钉的，侧面印着字
		bx("furn_light", cx - 0.42, cx + 0.42, 0.0, t, ZB + 0.04, ZB + 0.62)
		for k in 4:
			bx("wood", cx - 0.425, cx + 0.425, 0.03 + k * 0.125, 0.04 + k * 0.125, ZB + 0.62, ZB + 0.625)
		bx("sign_ink", cx - 0.2, cx + 0.12, 0.2, 0.3, ZB + 0.62, ZB + 0.626)
		bx("cloth", cx - 0.45, cx + 0.45, t, t + 0.012, ZB + 0.03, ZB + 0.65, Color("#e9e2cf"))
	elif w == 1:
		bx("furn", cx - 0.55, cx + 0.55, 0.06, t, ZB + 0.03, ZB + 0.66)
		for dx in [-0.5, 0.5]:
			bx("furn", cx + dx - 0.03, cx + dx + 0.03, 0.0, 0.06, ZB + 0.6, ZB + 0.66)
		for dx in [-0.27, 0.27]:
			bx("furn", cx + dx - 0.25, cx + dx + 0.25, 0.12, t - 0.06, ZB + 0.66, ZB + 0.675)
			bx("brass", cx + dx * 0.15 - 0.015, cx + dx * 0.15 + 0.015, 0.3, 0.42, ZB + 0.675, ZB + 0.69)
		bx("cloth", cx - 0.56, cx + 0.56, t, t + 0.01, ZB + 0.02, ZB + 0.68, Color("#efe9dc"))
	else:
		# 玻璃门柜：细腿、两扇推拉玻璃、里头摆着杯子、酒瓶
		bx("furn", cx - 0.6, cx + 0.6, 0.12, t, ZB + 0.03, ZB + 0.6)
		for dx in [-0.55, 0.55]:
			cyl("furn", Vector3(cx + dx, 0.0, ZB + 0.55), 0.025, 0.02, 0.12, 6)
		bx("tint", cx - 0.55, cx + 0.55, 0.17, t - 0.04, ZB + 0.58, ZB + 0.6, Color("#2a1a12"))
		for k in 5:
			cyl("pane", Vector3(cx - 0.42 + k * 0.2, 0.18, ZB + 0.45), 0.035, 0.035, 0.16 + (k % 2) * 0.12, 8)
			cyl("tint", Vector3(cx - 0.32 + k * 0.2, 0.18, ZB + 0.4), 0.03, 0.025, 0.08, 8, Color("#e8e2d0"))
		bx("pane", cx - 0.56, cx + 0.56, 0.16, t - 0.03, ZB + 0.605, ZB + 0.61)
		bx("chrome", cx - 0.56, cx + 0.56, 0.16, 0.17, ZB + 0.6, ZB + 0.615)
	return Vector3(cx, 0, ZB + 0.35)


func _tv(kind: String, w: int) -> Vector3:
	var cx: float = TV_X[w]
	var y: float = float(CAB_TOP[w]) + 0.012
	var z := ZB + 0.33
	if kind == "bw":
		# 黑白小方盒：奶白壳、深灰屏、右边一竖排旋钮、兔耳朵天线
		bx("enamel", cx - 0.24, cx + 0.24, y, y + 0.38, z - 0.2, z + 0.18, Color("#cfc8b4"))
		bx("screen", cx - 0.21, cx + 0.09, y + 0.06, y + 0.33, z + 0.18, z + 0.19)
		bx("tint", cx + 0.11, cx + 0.22, y + 0.04, y + 0.34, z + 0.18, z + 0.185, Color("#8c877a"))
		for k in 3:
			cyl("rubber", Vector3(cx + 0.165, y + 0.26 - k * 0.09, z + 0.185), 0.025, 0.025, 0.0, 8)
			_ell("rubber", Vector3(cx + 0.165, y + 0.26 - k * 0.09, z + 0.19), Vector3(0.025, 0.025, 0.015), Color.WHITE, 8, 4)
		tube("chrome", PackedVector3Array([Vector3(cx, y + 0.38, z), Vector3(cx - 0.25, y + 0.85, z - 0.05)]), 0.005, 3)
		tube("chrome", PackedVector3Array([Vector3(cx, y + 0.38, z), Vector3(cx + 0.22, y + 0.88, z + 0.02)]), 0.005, 3)
		cyl("rubber", Vector3(cx, y + 0.38, z), 0.03, 0.03, 0.025, 8)
	elif kind == "color":
		# 大脑袋彩电：黑壳、后头鼓出来，顶上苫一块钩花白巾
		bx("lacquer", cx - 0.34, cx + 0.34, y, y + 0.52, z - 0.18, z + 0.22)
		bx("lacquer", cx - 0.24, cx + 0.24, y + 0.06, y + 0.44, z - 0.32, z - 0.18)
		bx("screen", cx - 0.29, cx + 0.2, y + 0.1, y + 0.46, z + 0.22, z + 0.235)
		bx("tint", cx + 0.22, cx + 0.31, y + 0.08, y + 0.46, z + 0.22, z + 0.226, Color("#2c2c30"))
		for k in 4:
			bx("silver", cx + 0.24, cx + 0.29, y + 0.36 - k * 0.06, y + 0.38 - k * 0.06, z + 0.226, z + 0.235)
		bx("cloth", cx - 0.36, cx + 0.36, y + 0.52, y + 0.53, z - 0.2, z + 0.24, Color("#f3efe4"))
		for k in 7:
			var fx := cx - 0.33 + k * 0.11
			bx("cloth", fx, fx + 0.07, y + 0.43, y + 0.53, z + 0.235, z + 0.245, Color("#f3efe4"))
	else:
		# 薄电视：黑框、矮座
		bx("lacquer", cx - 0.12, cx + 0.12, y, y + 0.02, z - 0.1, z + 0.08)
		bx("lacquer", cx - 0.03, cx + 0.03, y, y + 0.12, z - 0.02, z + 0.02)
		bx("lacquer", cx - 0.5, cx + 0.5, y + 0.1, y + 0.68, z - 0.02, z + 0.03)
		bx("screen", cx - 0.48, cx + 0.48, y + 0.12, y + 0.66, z + 0.03, z + 0.035)
	return Vector3(cx, y, z)


func _console(w: int) -> Vector3:
	var cx: float = TV_X[w] - 0.28
	var y: float = float(CAB_TOP[w]) + 0.012
	var z := ZB + 0.6
	bx("tint", cx - 0.12, cx + 0.12, y, y + 0.05, z - 0.08, z + 0.03, Color("#d8d2c0"))
	bx("tint", cx - 0.05, cx + 0.05, y + 0.05, y + 0.11, z - 0.06, z - 0.03, Color("#d0a63a"))
	# 两个手柄，线耷拉下来
	for k in 2:
		var hx := cx - 0.08 + k * 0.32
		bx("tint", hx - 0.065, hx + 0.065, y, y + 0.02, z - 0.0, z + 0.05, Color("#3a3a3e"))
		tube("rubber", PackedVector3Array([Vector3(cx, y + 0.02, z - 0.04), Vector3(hx, y + 0.01, z + 0.02)]), 0.004, 3)
	tube("rubber", PackedVector3Array([Vector3(cx + 0.24, y + 0.01, z + 0.05), Vector3(cx + 0.3, y - 0.2, z + 0.07), Vector3(cx + 0.36, 0.01, z + 0.15)]), 0.004, 3)
	return Vector3(cx, y, z)


func _radio(how: String) -> Vector3:
	var cx := 3.82
	var y := 1.17
	if how == "piano":
		cx = 3.75
		y = 1.27
	elif how == "case":
		y = 2.02
	var z := ZB + 0.25
	# 木壳收音机：前脸布网、刻度窗、两个旋钮
	bx("furn", cx - 0.2, cx + 0.2, y, y + 0.24, z - 0.09, z + 0.09)
	bx("cloth", cx - 0.17, cx + 0.04, y + 0.03, y + 0.21, z + 0.09, z + 0.095, Color("#c9b88e"))
	bx("paper", cx + 0.06, cx + 0.17, y + 0.14, y + 0.2, z + 0.09, z + 0.096, Color("#efe2b6"))
	for k in 2:
		cyl("tint", Vector3(cx + 0.08 + k * 0.07, y + 0.07, z + 0.09), 0.022, 0.022, 0.0, 8, Color("#e8e2d0"))
		_ell("tint", Vector3(cx + 0.08 + k * 0.07, y + 0.07, z + 0.1), Vector3(0.022, 0.022, 0.014), Color("#e8e2d0"), 8, 4)
	tube("chrome", PackedVector3Array([Vector3(cx + 0.15, y + 0.24, z - 0.05), Vector3(cx + 0.35, y + 0.6, z - 0.08)]), 0.004, 3)
	return Vector3(cx, y, z)


func _chest(acc: Color) -> Vector3:
	# 五斗柜：枣红漆、一格格抽屉、铜把手；顶上镜子、相框、花瓶
	var x0 := 2.95
	var x1 := 4.12
	var z0 := ZB + 0.02
	var z1 := ZB + 0.52
	bx("furn", x0, x1, 0.08, 1.15, z0, z1)
	bx("furn", x0 - 0.02, x1 + 0.02, 1.13, 1.17, z0, z1 + 0.02)
	for dx in [x0 + 0.04, x1 - 0.04]:
		bx("furn", dx - 0.03, dx + 0.03, 0.0, 0.08, z1 - 0.06, z1)
	for r in 4:
		var dy := 0.14 + r * 0.24
		if r == 3:
			for c in 2:
				var ax := x0 + 0.05 + c * 0.55
				bx("furn", ax, ax + 0.52, dy, dy + 0.2, z1, z1 + 0.015)
				bx("brass", ax + 0.22, ax + 0.3, dy + 0.09, dy + 0.11, z1 + 0.015, z1 + 0.03)
		else:
			bx("furn", x0 + 0.05, x1 - 0.05, dy, dy + 0.2, z1, z1 + 0.015)
			for c in [0.3, 0.75]:
				var hx: float = x0 + (x1 - x0) * c
				bx("brass", hx - 0.04, hx + 0.04, dy + 0.09, dy + 0.11, z1 + 0.015, z1 + 0.03)
	bx("cloth", x0 + 0.05, x1 - 0.05, 1.17, 1.175, z0 + 0.02, z1 - 0.02, Color("#f2ede0"))
	bx("furn", x0 + 0.1, x0 + 0.42, 1.175, 1.5, z0 + 0.15, z0 + 0.18)
	bx("paper", x0 + 0.13, x0 + 0.39, 1.2, 1.47, z0 + 0.18, z0 + 0.185, Color("#9a9184"))
	cyl("enamel", Vector3(x0 + 0.6, 1.175, z0 + 0.25), 0.05, 0.035, 0.22, 10, acc.lerp(Color.WHITE, 0.2))
	_ell("tint", Vector3(x0 + 0.6, 1.47, z0 + 0.25), Vector3(0.09, 0.07, 0.07), Color("#c95a4a"))
	return Vector3((x0 + x1) / 2.0, 0, (z0 + z1) / 2.0)


func _bookcase(by_bed: bool) -> Vector3:
	var x0 := 0.35 if by_bed else 2.92
	var x1 := x0 + 1.15
	var z0 := ZB + 0.02
	var z1 := ZB + 0.42
	var top := 2.0
	bx("furn", x0, x1, 0.0, top, z0, z1)
	bx("furn", x0 - 0.02, x1 + 0.02, top, top + 0.04, z0, z1 + 0.02)
	# 上头玻璃门里一层层书，下头两扇木门
	var cols := [Color("#a8452f"), Color("#e2d5b5"), Color("#3f5f86"), Color("#d6a446"), Color("#5d7a54"), Color("#7b5a8c"), Color("#c9c3b2"), Color("#2f3b4c")]
	for s in 3:
		var sy := 0.8 + s * 0.38
		bx("furn_light", x0 + 0.04, x1 - 0.04, sy, sy + 0.02, z0 + 0.02, z1 - 0.01)
		var bxp := x0 + 0.06
		while bxp < x1 - 0.1:
			var bw := _rng.randf_range(0.025, 0.06)
			var bh := _rng.randf_range(0.2, 0.32)
			bx("tint", bxp, bxp + bw, sy + 0.02, sy + 0.02 + bh, z0 + 0.08, z1 - 0.06, cols[_rng.randi() % cols.size()])
			bxp += bw + 0.004
	bx("tint", x0 + 0.04, x1 - 0.04, 0.78, top - 0.04, z0 + 0.01, z0 + 0.02, Color("#3a2216"))
	for c in 2:
		var dx0 := x0 + 0.03 + c * (x1 - x0 - 0.06) / 2.0
		var dx1 := dx0 + (x1 - x0 - 0.06) / 2.0
		bx("furn", dx0, dx0 + 0.03, 0.78, top - 0.03, z1, z1 + 0.02)
		bx("furn", dx1 - 0.03, dx1, 0.78, top - 0.03, z1, z1 + 0.02)
		bx("furn", dx0, dx1, top - 0.06, top - 0.03, z1, z1 + 0.02)
		bx("furn", dx0, dx1, 0.78, 0.81, z1, z1 + 0.02)
		bx("pane", dx0 + 0.03, dx1 - 0.03, 0.81, top - 0.06, z1 + 0.005, z1 + 0.01)
		bx("furn", dx0 + 0.01, dx1 - 0.01, 0.06, 0.74, z1, z1 + 0.018)
		bx("brass", dx1 - 0.06, dx1 - 0.04, 0.45, 0.55, z1 + 0.018, z1 + 0.03)
	# 顶上一个相框
	bx("furn", x0 + 0.35, x0 + 0.7, top + 0.04, top + 0.34, z0 + 0.15, z0 + 0.18)
	bx("paper", x0 + 0.38, x0 + 0.67, top + 0.07, top + 0.31, z0 + 0.18, z0 + 0.185, Color("#a39a8a"))
	return Vector3((x0 + x1) / 2.0, 0, (z0 + z1) / 2.0)


func _piano() -> Vector3:
	# 立式钢琴：黑漆、键盘、谱架、两只铜烛台；琴凳塞在底下
	var x0 := 2.7
	var x1 := 4.12
	var z0 := ZB + 0.02
	var z1 := ZB + 0.6
	bx("lacquer", x0, x1, 0.0, 1.25, z0, z1)
	bx("lacquer", x0 - 0.02, x1 + 0.02, 1.25, 1.29, z0 - 0.01, z1 + 0.02)
	bx("lacquer", x0, x0 + 0.06, 0.0, 0.75, z1, z1 + 0.22)
	bx("lacquer", x1 - 0.06, x1, 0.0, 0.75, z1, z1 + 0.22)
	bx("lacquer", x0 + 0.06, x1 - 0.06, 0.62, 0.7, z1, z1 + 0.2)
	bx("enamel", x0 + 0.08, x1 - 0.08, 0.7, 0.74, z1 + 0.02, z1 + 0.2, Color("#f3efe4"))
	var kx := x0 + 0.1
	var n := 0
	while kx < x1 - 0.12:
		if n % 7 != 2 and n % 7 != 6:
			bx("lacquer", kx + 0.012, kx + 0.03, 0.74, 0.76, z1 + 0.09, z1 + 0.2)
		kx += 0.0365
		n += 1
	bx("lacquer", x0 + 0.06, x1 - 0.06, 0.76, 0.82, z1 + 0.02, z1 + 0.04)
	bx("paper", x0 + 0.45, x1 - 0.45, 0.88, 1.12, z1 + 0.01, z1 + 0.02, Color("#f1ead8"))
	bx("lacquer", x0 + 0.06, x1 - 0.06, 0.0, 0.08, z1, z1 + 0.04)
	for cx in [x0 + 0.12, x1 - 0.12]:
		bx("brass", cx - 0.03, cx + 0.03, 1.0, 1.02, z1, z1 + 0.08)
		cyl("enamel", Vector3(cx, 1.02, z1 + 0.05), 0.012, 0.012, 0.08, 6, Color("#f2eee2"))
	# 琴盖上一块绒布、一个相框
	bx("cloth", x0 + 0.1, x1 - 0.1, 1.29, 1.3, z0 + 0.05, z1 - 0.05, Color("#8c2f2a"))
	bx("brass", x0 + 0.25, x0 + 0.55, 1.3, 1.55, z0 + 0.2, z0 + 0.22)
	bx("paper", x0 + 0.27, x0 + 0.53, 1.32, 1.53, z0 + 0.22, z0 + 0.225, Color("#9a9184"))
	var bc0 := Vector3((x0 + x1) / 2.0, 0, z1 + 0.25)
	bx("lacquer", bc0.x - 0.35, bc0.x + 0.35, 0.44, 0.5, bc0.z - 0.15, bc0.z + 0.15)
	for dx in [-0.31, 0.31]:
		for dz in [-0.11, 0.11]:
			bx("lacquer", bc0.x + dx - 0.02, bc0.x + dx + 0.02, 0.0, 0.44, bc0.z + dz - 0.02, bc0.z + dz + 0.02)
	return Vector3((x0 + x1) / 2.0, 0, (z0 + z1) / 2.0)


func _curtain(acc: Color) -> Vector3:
	# 屋当间一道布帘子（从后墙拉到快到走道），帘子后头一张折叠床
	var x := 6.95
	tube("metal", PackedVector3Array([Vector3(x, 2.65, ZB), Vector3(x, 2.65, -1.2)]), 0.012, 4)
	var col := acc.lerp(Color("#e3d9c2"), 0.7)
	var z := ZB + 0.05
	var k := 0
	while z < -1.7:
		var fw := 0.1
		var fx := x + (0.025 if k % 2 == 0 else -0.02)
		bx("cloth", fx - 0.008, fx + 0.008, 0.25, 2.64, z, z + fw, col.darkened(0.05 * float(k % 2)))
		z += fw * 0.9
		k += 1
	for r in 1:
		bx("cloth", x - 0.03, x + 0.03, 0.25 + r * 0.38, 0.31 + r * 0.38, ZB + 0.05, z, col.lightened(0.15))
	# 折叠床：收起来立在墙边
	var b := Vector3(7.35, 0, ZB + 0.12)
	_roll("metal", b + Vector3(0, 0.5, 0), Vector3(0.04, 1.0, 0.06), 0.12)
	_roll("metal", b + Vector3(0.62, 0.5, 0), Vector3(0.04, 1.0, 0.06), 0.12)
	_roll("cloth", b + Vector3(0.31, 0.5, 0.0), Vector3(0.6, 0.95, 0.03), 0.12, Color("#6e7f5a"))
	return Vector3(x, 0, -1.6)


func _sewing() -> Vector3:
	# 缝纫机：木台面、铸铁花腿、踏板、黑机头带金字、手轮
	var c := Vector3(6.66, 0, ZB + 0.35)
	bx("furn", c.x - 0.4, c.x + 0.4, 0.72, 0.76, c.z - 0.24, c.z + 0.24)
	bx("furn", c.x - 0.38, c.x - 0.06, 0.52, 0.72, c.z - 0.22, c.z + 0.22)
	for k in 3:
		bx("furn_light", c.x - 0.36, c.x - 0.08, 0.54 + k * 0.06, 0.58 + k * 0.06, c.z + 0.22, c.z + 0.23)
	for dx in [-0.34, 0.34]:
		bx("lacquer", c.x + dx - 0.02, c.x + dx + 0.02, 0.0, 0.72, c.z - 0.2, c.z + 0.2)
		_roll("lacquer", Vector3(c.x + dx, 0.4, c.z), Vector3(0.025, 0.55, 0.025), 0.5)
		_roll("lacquer", Vector3(c.x + dx, 0.4, c.z), Vector3(0.025, 0.55, 0.025), -0.5)
	bx("lacquer", c.x - 0.3, c.x + 0.3, 0.05, 0.08, c.z - 0.12, c.z + 0.18)
	_ring_b("lacquer", Vector3(c.x + 0.3, 0.32, c.z), 0.22, 0.015, Basis(Vector3.UP, PI / 2.0))
	# 机头
	bx("lacquer", c.x - 0.28, c.x + 0.24, 0.76, 0.8, c.z - 0.1, c.z + 0.1)
	bx("lacquer", c.x + 0.12, c.x + 0.24, 0.8, 1.04, c.z - 0.07, c.z + 0.07)
	bx("lacquer", c.x - 0.28, c.x + 0.24, 0.96, 1.06, c.z - 0.06, c.z + 0.06)
	bx("lacquer", c.x - 0.3, c.x - 0.2, 0.84, 1.06, c.z - 0.05, c.z + 0.05)
	bx("chrome", c.x - 0.27, c.x - 0.25, 0.8, 0.86, c.z - 0.01, c.z + 0.01)
	bx("brass", c.x - 0.1, c.x + 0.1, 1.0, 1.02, c.z + 0.06, c.z + 0.062)
	_ring_b("silver", Vector3(c.x + 0.27, 0.96, c.z), 0.07, 0.015, Basis(Vector3.UP, PI / 2.0))
	# 搭着一块花布
	bx("cloth", c.x - 0.38, c.x - 0.05, 0.76, 0.77, c.z - 0.2, c.z + 0.26, Color("#c98a5a"))
	bx("cloth", c.x - 0.38, c.x - 0.05, 0.62, 0.77, c.z + 0.25, c.z + 0.26, Color("#c98a5a"))
	return c


func _sofa() -> Vector3:
	# 单人沙发：咖啡色布面、扶手，靠背和扶手上苫着白钩花巾
	var c := Vector3(6.66, 0, ZB + 0.45)
	var col := Color("#7a4a3a")
	bx("furn", c.x - 0.4, c.x + 0.4, 0.0, 0.12, c.z - 0.35, c.z + 0.35)
	bx("cloth", c.x - 0.4, c.x + 0.4, 0.12, 0.4, c.z - 0.35, c.z + 0.35, col)
	bx("cloth", c.x - 0.3, c.x + 0.3, 0.4, 0.5, c.z - 0.18, c.z + 0.33, col.lightened(0.06))
	bx("cloth", c.x - 0.4, c.x + 0.4, 0.4, 0.95, c.z - 0.35, c.z - 0.15, col)
	for dx in [-0.35, 0.35]:
		bx("cloth", c.x + dx - 0.06, c.x + dx + 0.06, 0.4, 0.62, c.z - 0.33, c.z + 0.35, col.darkened(0.05))
		bx("cloth", c.x + dx - 0.065, c.x + dx + 0.065, 0.62, 0.63, c.z - 0.05, c.z + 0.3, Color("#f3efe4"))
	bx("cloth", c.x - 0.28, c.x + 0.28, 0.95, 0.96, c.z - 0.36, c.z - 0.14, Color("#f3efe4"))
	bx("cloth", c.x - 0.28, c.x + 0.28, 0.75, 0.96, c.z - 0.14, c.z - 0.13, Color("#f3efe4"))
	return c


func _clock_round() -> Vector3:
	var c := Vector3(9.52, 3.3, ZB + 0.03)
	_ell("enamel", c, Vector3(0.17, 0.17, 0.03), Color("#3b4f6a"), 16, 6)
	_ell("enamel", c + Vector3(0, 0, 0.012), Vector3(0.145, 0.145, 0.025), Color("#f4f0e4"), 16, 6)
	_roll("sign_ink", c + Vector3(0.0, 0.045, 0.04), Vector3(0.012, 0.09, 0.004), 0.4)
	_roll("sign_ink", c + Vector3(0.04, 0.0, 0.041), Vector3(0.11, 0.008, 0.004), -0.3)
	for k in 12:
		var a := TAU * float(k) / 12.0
		bx("sign_ink", c.x + sin(a) * 0.12 - 0.006, c.x + sin(a) * 0.12 + 0.006, c.y + cos(a) * 0.12 - 0.006, c.y + cos(a) * 0.12 + 0.006, c.z + 0.035, c.z + 0.037)
	return c


func _clock_pendulum() -> Vector3:
	var c := Vector3(9.52, 2.65, ZB + 0.08)
	bx("furn", c.x - 0.2, c.x + 0.2, c.y, c.y + 1.15, c.z - 0.07, c.z + 0.07)
	bx("furn", c.x - 0.24, c.x + 0.24, c.y + 1.15, c.y + 1.22, c.z - 0.08, c.z + 0.08)
	bx("furn", c.x - 0.22, c.x + 0.22, c.y - 0.04, c.y, c.z - 0.08, c.z + 0.08)
	bx("tint", c.x - 0.16, c.x + 0.16, c.y + 0.08, c.y + 0.75, c.z + 0.07, c.z + 0.072, Color("#2a1810"))
	_ell("brass", Vector3(c.x, c.y + 0.22, c.z + 0.075), Vector3(0.07, 0.07, 0.01), Color.WHITE, 12, 4)
	bx("brass", c.x - 0.006, c.x + 0.006, c.y + 0.22, c.y + 0.7, c.z + 0.073, c.z + 0.076)
	bx("pane", c.x - 0.16, c.x + 0.16, c.y + 0.08, c.y + 0.75, c.z + 0.08, c.z + 0.085)
	_ell("enamel", Vector3(c.x, c.y + 0.95, c.z + 0.07), Vector3(0.14, 0.14, 0.02), Color("#f4f0e4"), 14, 5)
	_roll("sign_ink", Vector3(c.x, c.y + 0.98, c.z + 0.09), Vector3(0.01, 0.08, 0.004), 0.5)
	_roll("sign_ink", Vector3(c.x + 0.03, c.y + 0.95, c.z + 0.091), Vector3(0.1, 0.008, 0.004), -0.2)
	return Vector3(c.x, c.y, c.z)


func _boxes() -> Vector3:
	# 清贫人家糊纸盒的活儿：一摞摞压扁的纸盒、糨糊盆、几个糊好的
	for k in 4:
		var bxp := 7.9 + k * 0.42
		var h := 0.25 + _rng.randf() * 0.35
		bc("tint", Vector3(bxp, h / 2.0, -1.95), Vector3(0.36, h, 0.28), _rng.randf_range(-0.08, 0.08), 0.0, Color("#c9a978").darkened(_rng.randf() * 0.12))
		for s in int(h / 0.04):
			bx("paper", bxp - 0.18, bxp + 0.18, s * 0.04, s * 0.04 + 0.004, -1.81, -1.805, Color("#8a6f4c"))
	for k in 3:
		bc("tint", Vector3(8.0 + k * 0.22, 0.9, -1.0), Vector3(0.12, 0.08, 0.16), 0.3 * k, 0.0, Color("#e6d6b0"))
	cyl("enamel", Vector3(9.45, 0.0, -1.7), 0.11, 0.13, 0.1, 12, Color("#e9e4d6"))
	return Vector3(8.6, 0, -1.9)


func _fridge() -> Vector3:
	# 双门冰箱：白、镀铬把手、上头苫一块白巾放个果盘
	var x0 := 11.2
	var x1 := 11.82
	var z0 := ZB + 0.05
	var z1 := ZB + 0.66
	bx("enamel", x0, x1, 0.04, 1.48, z0, z1, Color("#ecebe6"))
	bx("rubber", x0 + 0.02, x1 - 0.02, 0.0, 0.05, z0 + 0.02, z1 - 0.02)
	bx("sign_ink", x0, x1, 1.0, 1.012, z1, z1 + 0.004)
	bx("chrome", x0 + 0.04, x0 + 0.065, 1.1, 1.4, z1, z1 + 0.035)
	bx("chrome", x0 + 0.04, x0 + 0.065, 0.55, 0.95, z1, z1 + 0.035)
	bx("tint", x0 + 0.38, x1 - 0.06, 1.38, 1.42, z1, z1 + 0.004, Color("#3b5f9a"))
	bx("cloth", x0 - 0.02, x1 + 0.02, 1.48, 1.49, z0, z1 + 0.02, Color("#f3efe4"))
	bx("cloth", x0 - 0.02, x1 + 0.02, 1.32, 1.49, z1 + 0.02, z1 + 0.025, Color("#f3efe4"))
	cyl("enamel", Vector3(11.5, 1.49, z0 + 0.3), 0.12, 0.14, 0.05, 12, Color("#c9483a"))
	for k in 3:
		_ell("tint", Vector3(11.45 + k * 0.05, 1.57, z0 + 0.28 + (k % 2) * 0.05), Vector3(0.045, 0.045, 0.045), Color("#e07a2f"))
	return Vector3((x0 + x1) / 2.0, 0, (z0 + z1) / 2.0)


func _pc(lcd: bool, acc: Color) -> Vector3:
	# 电脑桌（在屋角那件家具跟前）：大脑袋显示器罩着一块布 / 后来是液晶
	var x0 := 3.0
	var x1 := 4.08
	var z0 := -1.55
	var z1 := -0.98
	bx("furn_light", x0, x1, 0.72, 0.75, z0, z1)
	for dx in [x0 + 0.03, x1 - 0.03]:
		bx("furn_light", dx - 0.02, dx + 0.02, 0.0, 0.72, z0, z1)
	bx("furn_light", x0 + 0.05, x1 - 0.05, 0.62, 0.64, z0 + 0.05, z1 - 0.05)
	var case_col := Color("#d8d2c0") if not lcd else Color("#26272a")
	bx("enamel", x1 - 0.3, x1 - 0.1, 0.0, 0.42, z0 + 0.05, z0 + 0.48, case_col)
	bx("enamel", x0 + 0.2, x0 + 0.62, 0.645, 0.67, z1 - 0.18, z1 - 0.05, case_col)
	var mx := (x0 + x1) / 2.0 - 0.05
	if not lcd:
		bx("enamel", mx - 0.21, mx + 0.21, 0.75, 1.13, z0 + 0.06, z0 + 0.42, case_col)
		bx("enamel", mx - 0.15, mx + 0.15, 0.8, 1.06, z0 + 0.0, z0 + 0.06, case_col.darkened(0.1))
		bx("screen", mx - 0.17, mx + 0.17, 0.8, 1.08, z0 + 0.42, z0 + 0.425)
		# 防尘的罩布：苫在显示器上头、前头垂一截
		bx("cloth", mx - 0.23, mx + 0.23, 1.13, 1.145, z0 + 0.04, z0 + 0.45, acc.lerp(Color("#efe6d2"), 0.5))
		bx("cloth", mx - 0.23, mx + 0.23, 0.96, 1.145, z0 + 0.44, z0 + 0.455, acc.lerp(Color("#efe6d2"), 0.5))
	else:
		bx("enamel", mx - 0.06, mx + 0.06, 0.75, 0.77, z0 + 0.1, z0 + 0.25, case_col)
		bx("enamel", mx - 0.02, mx + 0.02, 0.77, 0.9, z0 + 0.15, z0 + 0.19, case_col)
		bx("enamel", mx - 0.27, mx + 0.27, 0.86, 1.2, z0 + 0.18, z0 + 0.21, case_col)
		bx("screen", mx - 0.25, mx + 0.25, 0.88, 1.18, z0 + 0.21, z0 + 0.212)
	bx("enamel", mx + 0.25, mx + 0.31, 0.75, 0.77, z0 + 0.4, z0 + 0.48, case_col)
	return Vector3((x0 + x1) / 2.0, 0, (z0 + z1) / 2.0)


func _tape() -> Vector3:
	# 复读机：塑料壳、磁带仓、一副耳机
	var c := Vector3(6.0, 0.766, -0.85)
	bx("enamel", c.x - 0.13, c.x + 0.13, c.y, c.y + 0.06, c.z - 0.09, c.z + 0.09, Color("#3f5f7a"))
	bx("screen", c.x - 0.09, c.x + 0.03, c.y + 0.06, c.y + 0.062, c.z - 0.06, c.z + 0.04)
	for k in 5:
		bx("silver", c.x + 0.05 + (k % 3) * 0.025, c.x + 0.07 + (k % 3) * 0.025, c.y + 0.06, c.y + 0.066, c.z - 0.06 + floorf(k / 3.0) * 0.04, c.z - 0.04 + floorf(k / 3.0) * 0.04)
	tube("rubber", PackedVector3Array([Vector3(c.x + 0.13, c.y + 0.03, c.z), Vector3(c.x + 0.2, c.y + 0.005, c.z + 0.05), Vector3(c.x + 0.12, c.y + 0.005, c.z + 0.1)]), 0.003, 3)
	_ell("rubber", Vector3(c.x + 0.1, c.y + 0.012, c.z + 0.1), Vector3(0.02, 0.012, 0.02))
	return Vector3(c.x, c.y, c.z)


func _phone() -> Vector3:
	# 电话：红色按键电话，听筒搁着，线卷着
	var c := Vector3(4.92, 0.766, -0.86)
	bx("enamel", c.x - 0.1, c.x + 0.1, c.y, c.y + 0.06, c.z - 0.11, c.z + 0.09, Color("#b8342c"))
	Kit.box_into(_tool("enamel"), Vector3(0.18, 0.03, 0.12), Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(c.x, c.y + 0.07, c.z + 0.02)), Color("#b8342c"))
	bx("enamel", c.x - 0.11, c.x + 0.11, c.y + 0.06, c.y + 0.1, c.z - 0.1, c.z - 0.04, Color("#b8342c"))
	for k in 6:
		bx("tint", c.x - 0.05 + (k % 3) * 0.035, c.x - 0.03 + (k % 3) * 0.035, c.y + 0.085, c.y + 0.092, c.z + floorf(k / 3.0) * 0.035, c.z + 0.02 + floorf(k / 3.0) * 0.035, Color("#f2eee2"))
	tube("rubber", PackedVector3Array([Vector3(c.x - 0.1, c.y + 0.08, c.z - 0.07), Vector3(c.x - 0.16, c.y + 0.01, c.z - 0.02), Vector3(c.x - 0.12, c.y + 0.005, c.z + 0.08)]), 0.006, 4)
	return Vector3(c.x, c.y, c.z)


func _milk() -> Vector3:
	# 门口挂的奶箱：木头的、刷绿漆、斜顶、前头一道投奶口
	var x0 := 13.55
	var x1 := 13.82
	var y0 := 1.45
	bx("wood_green", x0, x1, y0, y0 + 0.3, ZB, ZB + 0.16)
	Kit.box_into(_tool("wood_green"), Vector3(x1 - x0 + 0.04, 0.02, 0.21), Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3((x0 + x1) / 2.0, y0 + 0.32, ZB + 0.09)))
	bx("rubber", x0 + 0.05, x1 - 0.05, y0 + 0.22, y0 + 0.235, ZB + 0.16, ZB + 0.165)
	bx("metal", (x0 + x1) / 2.0 - 0.015, (x0 + x1) / 2.0 + 0.015, y0 + 0.06, y0 + 0.1, ZB + 0.16, ZB + 0.17)
	return Vector3((x0 + x1) / 2.0, y0, ZB + 0.08)


# ======================================================================
# 年代、每帧
# ======================================================================

func set_look(p_look: String) -> void:
	super.set_look(p_look)
	if not _shown.is_empty():
		_update_home(false)


func _fill(at: Vector3, col: Color, rng: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = col
	l.omni_range = rng
	l.omni_attenuation = 1.1
	l.light_energy = energy
	l.shadow_enabled = false
	add_child(l)
	_fills.append([l, energy])


func tick(delta: float, cam_x: float) -> void:
	super.tick(delta, cam_x)
	var nt := 0.0
	var oc := 0.0
	if stage != null and "night" in stage:
		nt = float(stage.night)
		oc = 1.0 if str(stage.weather) in ["rain", "snow"] else 0.0
	var day := clampf(1.0 - nt * 2.4, 0.0, 1.0) * (1.0 - oc * 0.35)
	for f in _fills:
		var l: OmniLight3D = f[0]
		l.visible = day > 0.02 and absf(l.position.x - cam_x) < 13.0
		l.light_energy = float(f[1]) * day
	_home_t += delta
	if _home_t >= 0.3:
		_home_t = 0.0
		var sig := str(_wanted())
		if sig != _home_sig:
			_home_sig = sig
			_update_home(true)
	var i := 0
	while i < _grow.size():
		var g: Array = _grow[i]
		var nd: Node3D = g[0]
		g[1] = float(g[1]) + delta
		var k := clampf(float(g[1]) / 0.9, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		var s := lerpf(0.85, 1.0, e)
		var m: float = g[2]
		if is_instance_valid(nd):
			nd.scale = Vector3(s * m, s, s)
		if k >= 1.0:
			_grow.remove_at(i)
		else:
			i += 1
