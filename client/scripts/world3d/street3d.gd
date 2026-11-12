extends Node3D
## 楼下这条街（content/maps/street.yaml，宽 40 米）的实时 3D：照着 2D 那张图的布局一样一样搭真的东西。
## 从左到右：去小学的街口、早点铺（红白条雨棚、蒸笼、煎饼鏊子、折叠桌）、小卖部（橱窗里一格格货、冰柜、邮筒）、
## 胡同口（往里走是早市）、3 号楼（红砖三层、单元门、告示栏、石头棋桌、大槐树）、去公园的口子、
## 修车铺（铁皮棚、挂着的车胎、倒扣着修的二八车）、河畔茶社（木格窗、红灯笼、小戏台）、街尾去海河边。
## 前头是马路，后头是一排排的居民楼（远了有雾）。电线杆一根根，电线垂着。
##
## 搭法：大部分是盒子和圆柱，按材质并成一张网格（几十个 draw call）；材质全在 surface.gdshader 里现算（砖缝、方砖缝、木纹）。
## 窗户是墙上真挖的洞：玻璃缩进去、窗台凸出来，太阳一斜就有影子。
## 坐标：米。X = 2D 的 x / 100，地面 Y = 0，人走的那条线 Z = 0，店面在 FZ（人身后一米多），马路在前头。
## 年代：set_look 换店招（小卖部→便利店）、加防盗窗（少年起）、空调外机（青年起）。

const Kit := preload("res://scripts/world3d/kit3d.gd")
const SURF := preload("res://shaders/3d/surface.gdshader")
const FOLIAGE := preload("res://shaders/3d/foliage.gdshader")
const P := preload("res://scripts/ui/palette.gd")

const FZ := -1.25     ## 店面那堵墙的前脸
const CURB := 1.45    ## 马路牙子
const FLOOR_H := 3.1  ## 一层多高
const WIDTH := 40.0

## 材质：名字 → [花纹, 主色, 第二色, 一块多大, 粗糙, 起伏, 脏, 颜色差, 金属]
const MATS := {
	"brick": [1, "#93402f", "#b3a693", Vector2(0.24, 0.065), 0.88, 1.0, 0.55, 0.16, 0.0],
	"brick_dark": [1, "#7a3427", "#a1958a", Vector2(0.24, 0.065), 0.9, 1.0, 0.6, 0.14, 0.0],
	"brick_grey": [1, "#6f6a64", "#a39c90", Vector2(0.24, 0.065), 0.9, 1.0, 0.5, 0.12, 0.0],
	"plaster": [6, "#d6c8ab", "#000000", Vector2.ONE, 0.92, 0.7, 0.6, 0.1, 0.0],
	"plaster_grey": [6, "#aaa498", "#000000", Vector2.ONE, 0.92, 0.7, 0.55, 0.1, 0.0],
	"plaster_green": [6, "#5f806f", "#000000", Vector2.ONE, 0.85, 0.6, 0.5, 0.1, 0.0],
	"plaster_far": [6, "#b9b2a4", "#000000", Vector2.ONE, 0.95, 0.3, 0.4, 0.1, 0.0],
	"concrete": [6, "#a29d93", "#000000", Vector2.ONE, 0.9, 0.5, 0.4, 0.1, 0.0],
	"pavers": [2, "#aaa294", "#6f6961", Vector2(0.5, 0.5), 0.9, 1.0, 0.4, 0.12, 0.0],
	"curb": [2, "#8d8880", "#5f5a55", Vector2(1.0, 0.25), 0.85, 1.0, 0.3, 0.08, 0.0],
	"asphalt": [3, "#3f3e42", "#000000", Vector2.ONE, 0.92, 0.6, 0.0, 0.1, 0.0],
	"paint": [0, "#e1dccd", "#000000", Vector2.ONE, 0.8, 0.0, 0.0, 0.0, 0.0],
	"wood": [4, "#5d3e2b", "#3a2619", Vector2(0.12, 1.0), 0.75, 1.0, 0.3, 0.12, 0.0],
	"wood_green": [4, "#3f6c5b", "#2c4a3f", Vector2(0.14, 1.0), 0.6, 1.0, 0.55, 0.06, 0.0],
	"wood_red": [4, "#8a3029", "#5e211c", Vector2(0.14, 1.0), 0.6, 1.0, 0.45, 0.06, 0.0],
	"wood_light": [10, "#a9875f", "#7a5f42", Vector2(0.1, 1.0), 0.8, 1.0, 0.2, 0.15, 0.0],
	"bamboo": [10, "#c7a56d", "#9a7d4f", Vector2(0.03, 1.0), 0.75, 0.8, 0.1, 0.1, 0.0],
	"metal": [0, "#2f3236", "#000000", Vector2.ONE, 0.45, 0.2, 0.0, 0.0, 0.7],
	"metal_green": [0, "#2c5f50", "#000000", Vector2.ONE, 0.45, 0.2, 0.0, 0.0, 0.4],
	"metal_white": [0, "#d8d6cf", "#000000", Vector2.ONE, 0.35, 0.1, 0.0, 0.0, 0.2],
	"chrome": [0, "#c7c9cc", "#000000", Vector2.ONE, 0.2, 0.0, 0.0, 0.0, 0.95],
	"iron": [5, "#7d8186", "#000000", Vector2(0.09, 1.0), 0.6, 1.2, 0.8, 0.1, 0.5],
	"glass": [8, "#26313d", "#000000", Vector2(1.0, 1.0), 0.08, 0.0, 0.0, 0.0, 0.0],
	"glass_far": [8, "#2f3a46", "#000000", Vector2(1.0, 1.0), 0.15, 0.0, 0.0, 0.0, 0.0],
	"shopglass": [0, "#9fb4bf", "#000000", Vector2.ONE, 0.05, 0.0, 0.0, 0.0, 0.0],
	"awning": [7, "#c33d36", "#efe5d3", Vector2(0.5, 1.0), 0.9, 0.5, 0.3, 0.0, 0.0],
	"tar": [9, "#4b4643", "#000000", Vector2(1.0, 0.9), 0.95, 1.0, 0.2, 0.1, 0.0],
	"tiles": [11, "#55524e", "#000000", Vector2(0.2, 0.28), 0.8, 1.2, 0.3, 0.1, 0.0],
	"sign_green": [0, "#2c6b56", "#000000", Vector2.ONE, 0.5, 0.0, 0.0, 0.0, 0.0],
	"sign_red": [0, "#b53a30", "#000000", Vector2.ONE, 0.5, 0.0, 0.0, 0.0, 0.0],
	"sign_ink": [0, "#2b2a33", "#000000", Vector2.ONE, 0.5, 0.0, 0.0, 0.0, 0.0],
	"paper": [0, "#eee5d0", "#000000", Vector2.ONE, 0.95, 0.0, 0.0, 0.0, 0.0],
	"goods": [0, "#ffffff", "#000000", Vector2.ONE, 0.6, 0.0, 0.0, 0.0, 0.0],
	"stone": [6, "#8f8b84", "#000000", Vector2.ONE, 0.85, 1.0, 0.3, 0.1, 0.0],
	"rubber": [0, "#1f1f22", "#000000", Vector2.ONE, 0.7, 0.0, 0.0, 0.0, 0.0],
	"trunk": [4, "#4b3c2f", "#2f251c", Vector2(0.05, 1.0), 0.95, 1.4, 0.0, 0.2, 0.0],
	"lamp": [0, "#fff2cf", "#000000", Vector2.ONE, 0.4, 0.0, 0.0, 0.0, 0.0],
	"lantern": [0, "#c8302a", "#000000", Vector2.ONE, 0.6, 0.0, 0.0, 0.0, 0.0],
	"water": [0, "#4a5f63", "#000000", Vector2.ONE, 0.05, 0.0, 0.0, 0.0, 0.3],
}
## 夜里自己发光的几样：[材质名, 强度, 颜色]
const GLOW := {"lamp": [4.0, "#ffd9a0"], "lantern": [1.6, "#ff6a40"]}

var lamps: Array = []         ## [OmniLight3D, 亮度系数]（stage3d 按钟点开关）
var _mats: Dictionary = {}
var _st: Dictionary = {}      ## 当前批次：材质名 → SurfaceTool
var _era_nodes: Array = []    ## [节点, 从哪个年代起有, 到哪个年代止]
var _foliage: Array = []      ## 树冠（季节换颜色）
var _rng := RandomNumberGenerator.new()
var _labels: Dictionary = {}  ## 店招 → Label3D
var look := "childhood"
const LOOKS := ["childhood", "teen", "young", "middle", "old"]


func build(sc: Dictionary, p_look: String, season: String) -> void:
	_rng.seed = 20251112
	look = p_look
	_begin()
	_ground()
	_corner(-6.0, 2.1)
	_breakfast(2.1, 8.3)
	_shop(8.3, 13.2)
	_alley(13.2, 24.3)
	_bikeshop(24.3, 30.6)
	_teahouse(30.6, 38.2)
	_street_end(38.2, 48.0)
	_poles()
	_background()
	_commit(self)
	_era_bits()
	set_look(look)
	set_season(season)


# ======================================================================
# 批次：同一种材质的东西并成一张网格
# ======================================================================

func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var d: Array = MATS[key]
	var m := ShaderMaterial.new()
	m.shader = SURF
	m.set_shader_parameter("pattern", int(d[0]))
	m.set_shader_parameter("col_a", Color(str(d[1])))
	m.set_shader_parameter("col_b", Color(str(d[2])))
	m.set_shader_parameter("cell", d[3])
	m.set_shader_parameter("rough", float(d[4]))
	m.set_shader_parameter("relief", float(d[5]))
	m.set_shader_parameter("grime", float(d[6]))
	m.set_shader_parameter("vary", float(d[7]))
	m.set_shader_parameter("metal", float(d[8]))
	if GLOW.has(key):
		m.set_shader_parameter("emit", float(GLOW[key][0]))
		m.set_shader_parameter("emit_col", Color(str(GLOW[key][1])))
	_mats[key] = m
	return m


func _begin() -> void:
	_st = {}


func _tool(key: String) -> SurfaceTool:
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
	return _st[key]


## 把这一批并好挂到 parent 下（每种材质一个 MeshInstance3D）
func _commit(parent: Node3D, shadows := true) -> void:
	for key in _st:
		var st: SurfaceTool = _st[key]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mat(key)
		mi.name = key
		if not shadows or key in ["glass", "glass_far", "lamp", "paper"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	_st = {}


## 盒子：按范围给（x0..x1, y0..y1, z0..z1）
func bx(key: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, color := Color.WHITE) -> void:
	var size := Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))
	if size.x < 0.0005 or size.y < 0.0005 or size.z < 0.0005:
		return
	Kit.box_into(_tool(key), size, Transform3D(Basis(), Vector3((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0)), color)


## 盒子：按中心、大小，可绕 Y 转、绕 X 斜
func bc(key: String, c: Vector3, size: Vector3, yaw := 0.0, pitch := 0.0, color := Color.WHITE) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	Kit.box_into(_tool(key), size, Transform3D(b, c), color)


func cyl(key: String, base: Vector3, r0: float, r1: float, h: float, seg := 10, color := Color.WHITE) -> void:
	Kit.cyl_into(_tool(key), base, r0, r1, h, seg, color)


func tube(key: String, pts: PackedVector3Array, r: float, seg := 6, r_end := -1.0) -> void:
	Kit.tube_into(_tool(key), pts, r, seg, r_end)


## 一堵有窗洞的墙：墙面在 z（前脸），往里厚 thick；holes 是 Rect2(x, y, w, h)。
## 按窗洞的边把墙切成格子，不在洞里的格子各出一块（同一行连着的并成一块）
func wall(key: String, x0: float, x1: float, y0: float, y1: float, z: float, thick: float, holes: Array) -> void:
	var xs: Array = [x0, x1]
	var ys: Array = [y0, y1]
	for h in holes:
		var r: Rect2 = h
		xs.append_array([clampf(r.position.x, x0, x1), clampf(r.end.x, x0, x1)])
		ys.append_array([clampf(r.position.y, y0, y1), clampf(r.end.y, y0, y1)])
	xs.sort()
	ys.sort()
	for yi in ys.size() - 1:
		var ya: float = ys[yi]
		var yb: float = ys[yi + 1]
		if yb - ya < 0.001:
			continue
		var run_start := -1.0
		for xi in xs.size() - 1:
			var xa: float = xs[xi]
			var xb: float = xs[xi + 1]
			if xb - xa < 0.001:
				continue
			var mid := Vector2((xa + xb) / 2.0, (ya + yb) / 2.0)
			var inside := false
			for h in holes:
				if (h as Rect2).has_point(mid):
					inside = true
					break
			if inside:
				if run_start >= 0.0:
					bx(key, run_start, xa, ya, yb, z - thick, z)
					run_start = -1.0
			elif run_start < 0.0:
				run_start = xa
		if run_start >= 0.0:
			bx(key, run_start, x1, ya, yb, z - thick, z)


## 一扇窗：玻璃缩进去、白漆窗框十字棂、水泥窗台凸出来。lit 夜里亮不亮的随机数
func window(x: float, y: float, w: float, h: float, z: float, frame := "paint", sill := true) -> void:
	var rz := z - 0.16
	bx("glass", x, x + w, y, y + h, rz - 0.02, rz, Color(_rng.randf(), _rng.randf(), _rng.randf()))
	var t := 0.045
	bx(frame, x, x + w, y, y + t, rz, rz + 0.05)
	bx(frame, x, x + w, y + h - t, y + h, rz, rz + 0.05)
	bx(frame, x, x + t, y, y + h, rz, rz + 0.05)
	bx(frame, x + w - t, x + w, y, y + h, rz, rz + 0.05)
	bx(frame, x + w / 2.0 - t / 2.0, x + w / 2.0 + t / 2.0, y, y + h, rz, rz + 0.04)
	bx(frame, x, x + w, y + h * 0.68, y + h * 0.68 + t * 0.8, rz, rz + 0.04)
	if sill:
		bx("concrete", x - 0.06, x + w + 0.06, y - 0.07, y, z - 0.05, z + 0.1)


## 一栋楼的上半截：floors 层（从 y0 起），每层一排窗；前脸 z，往后到 back
func upper_floors(key: String, x0: float, x1: float, y0: float, floors: int, z: float, back: float, win_w := 1.1, pitch := 1.9, parapet := 0.55) -> void:
	var holes: Array = []
	var top := y0 + floors * FLOOR_H
	for f in floors:
		var fy := y0 + f * FLOOR_H
		var n := int(floor((x1 - x0 - 0.6) / pitch))
		var span := n * pitch
		var start := x0 + (x1 - x0 - span) / 2.0 + (pitch - win_w) / 2.0
		for i in n:
			var wx := start + i * pitch
			var r := Rect2(wx, fy + 0.9, win_w, 1.45)
			holes.append(r)
			window(wx, fy + 0.9, win_w, 1.45, z)
			_rng.randf()
		# 楼层之间一道水泥腰线
		if f > 0:
			bx("concrete", x0, x1, fy - 0.08, fy + 0.08, z, z + 0.06)
	wall(key, x0, x1, y0, top + parapet, z, 0.3, holes)
	# 女儿墙压顶、楼身往后
	bx("concrete", x0 - 0.05, x1 + 0.05, top + parapet, top + parapet + 0.1, z - 0.32, z + 0.06)
	bx(key, x0, x1, 0.0, top, back, z - 0.3)
	bx("tar", x0, x1, top - 0.05, top + 0.02, back, z - 0.3)


# ======================================================================
# 地面：人行道方砖、马路牙子、柏油马路、车道线、井盖
# ======================================================================

func _ground() -> void:
	bx("pavers", -12.0, 52.0, -0.2, 0.0, FZ - 0.4, CURB)
	bx("curb", -12.0, 52.0, -0.2, 0.0, CURB, CURB + 0.28)
	bx("asphalt", -12.0, 52.0, -0.4, -0.16, CURB + 0.28, 26.0)
	# 车道线：一段一段的虚线
	var x := -11.0
	while x < 52.0:
		bx("paint", x, x + 2.2, -0.16, -0.155, 6.6, 6.75)
		x += 4.5
	# 路边一条白实线
	bx("paint", -12.0, 52.0, -0.16, -0.155, CURB + 0.5, CURB + 0.6)
	# 井盖、雨水箅子
	for wx in [5.5, 19.0, 33.5]:
		cyl("metal", Vector3(wx, -0.163, 3.6), 0.33, 0.33, 0.012, 16)
	for wx in [9.4, 26.8]:
		bx("metal", wx, wx + 0.8, -0.165, -0.15, CURB + 0.3, CURB + 0.65)


# ======================================================================
# 一段一段的街
# ======================================================================

## 街口：往小学去的一条小路，路边矮墙、冬青、路牌
func _corner(x0: float, x1: float) -> void:
	# 侧街：柏油往后延伸
	bx("asphalt", x0, x1 - 0.3, -0.2, -0.01, -40.0, FZ - 0.4)
	bx("curb", x1 - 0.3, x1, -0.2, 0.06, -40.0, FZ - 0.4)
	# 左边一栋楼的山墙（远一点）
	upper_floors("brick_grey", x0 - 6.0, x0 + 1.5, 0.0, 3, FZ - 2.0, FZ - 12.0)
	# 矮墙 + 冬青（学校那边）
	bx("brick_grey", x0 + 1.6, x0 + 4.4, 0.0, 0.85, -6.0, -5.7)
	_hedge(Vector3(x0 + 3.0, 0.85, -5.9), 2.6, 0.5)
	# 路牌：蓝底白字，指向小学
	cyl("metal", Vector3(1.4, 0, -0.2), 0.035, 0.035, 2.6, 8)
	bx("sign_green", 0.5, 1.4, 2.2, 2.5, -0.23, -0.19)
	_label("育红小学 ←", Vector3(0.95, 2.35, -0.185), 0.0065, Color("#f4eee1"))
	_tree(Vector3(-1.0, 0, -1.6), 1.0, "huai")


func _breakfast(x0: float, x1: float) -> void:
	var z := FZ
	# 楼：一层抹灰刷绿墙裙，二层红砖
	upper_floors("brick", x0, x1, FLOOR_H, 1, z, z - 9.0, 1.1, 1.9)
	# 一层：整面敞开的铺面，里头是后厨
	var open0 := x0 + 0.35
	var open1 := x1 - 0.35
	wall("plaster", x0, x1, 0.0, FLOOR_H, z, 0.3, [Rect2(open0, 0.0, open1 - open0, 2.55)])
	bx("plaster_green", x0, open0, 0.0, 1.0, z, z + 0.02)
	bx("plaster_green", open1, x1, 0.0, 1.0, z, z + 0.02)
	_room(open0, open1, 0.0, 2.55, z, 3.2, "plaster", "concrete")
	# 店里：后墙一排架子、灶台冒着热气的大锅、案板
	bx("wood", open0 + 0.2, open1 - 0.2, 0.0, 0.9, z - 3.0, z - 2.5)
	for i in 6:
		var sx := open0 + 0.6 + i * 0.85
		cyl("metal_white", Vector3(sx, 0.9, z - 2.75), 0.24, 0.26, 0.28, 14)
	bx("paper", open0 + 1.0, open0 + 3.0, 1.5, 2.2, z - 3.15, z - 3.1)
	_label("煎饼果子  豆浆\n油条  馄饨  锅巴菜", Vector3(open0 + 2.0, 1.85, z - 3.08), 0.0042, Color("#2b2a33"))
	# 门口的摊：不锈钢台子上一摞蒸笼、一口煎饼鏊子
	var sx0 := 4.35
	bx("metal_white", sx0, sx0 + 2.0, 0.0, 0.88, -0.95, -0.35)
	bx("chrome", sx0 - 0.02, sx0 + 2.02, 0.88, 0.92, -0.97, -0.33)
	for k in 5:
		cyl("bamboo", Vector3(sx0 + 0.45, 0.92 + k * 0.13, -0.65), 0.27, 0.27, 0.12, 18)
	cyl("bamboo", Vector3(sx0 + 0.45, 0.92 + 5 * 0.13, -0.65), 0.27, 0.06, 0.12, 18)
	cyl("metal", Vector3(sx0 + 1.45, 0.92, -0.65), 0.32, 0.32, 0.05, 20)
	cyl("chrome", Vector3(sx0 + 1.45, 0.97, -0.65), 0.3, 0.3, 0.01, 20)
	# 门前两张折叠桌、小马扎
	for tx in [6.85, 7.75]:
		_folding_table(Vector3(tx, 0, -0.75))
	# 红白条的雨棚：从墙上斜着伸出来
	var aw := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(16.0)), Vector3((x0 + x1) / 2.0, 2.68, z + 0.75))
	Kit.box_into(_tool("awning"), Vector3(x1 - x0 - 0.2, 0.03, 1.6), aw)
	bx("awning", x0 + 0.1, x1 - 0.1, 2.28, 2.5, z + 1.53, z + 1.56)
	# 招牌：红底白字
	bx("sign_red", x0 + 1.8, x0 + 4.6, 2.85, 3.05 + 0.4, z + 0.01, z + 0.08)
	_label("早点", Vector3(x0 + 3.2, 3.15, z + 0.085), 0.012, Color("#f8f1e2"))
	# 汽车站牌（坐车去外地）：路边一根杆、一块牌
	cyl("metal", Vector3(3.3, 0, CURB - 0.15), 0.04, 0.04, 2.5, 8)
	bx("metal_white", 3.0, 3.6, 1.9, 2.5, CURB - 0.19, CURB - 0.11)
	_label("长途\n汽车站", Vector3(3.3, 2.2, CURB - 0.105), 0.0048, Color("#2c6b56"))
	_shop_light(Vector3((x0 + x1) / 2.0, 2.2, z - 1.0), 1.0)


func _shop(x0: float, x1: float) -> void:
	var z := FZ
	upper_floors("brick", x0, x1, FLOOR_H, 1, z, z - 9.0, 1.1, 1.75)
	# 一层：两边大橱窗、中间门
	var door0 := 9.9
	var door1 := 10.95
	var win_l := Rect2(x0 + 0.35, 0.55, door0 - x0 - 0.55, 1.95)
	var win_r := Rect2(door1 + 0.2, 0.55, x1 - door1 - 0.55, 1.95)
	wall("plaster_grey", x0, x1, 0.0, FLOOR_H, z, 0.3, [win_l, Rect2(door0, 0.0, door1 - door0, 2.35), win_r])
	_room(x0 + 0.3, x1 - 0.3, 0.0, 2.6, z, 3.4, "plaster", "pavers")
	# 店里：一排排货架，一格格五颜六色的货
	var goods := [Color("#c9473c"), Color("#e2b33c"), Color("#3f7d68"), Color("#e9e1cf"), Color("#4a6aa0"), Color("#d77a3a"), Color("#8b3c6b"), Color("#f0d070")]
	for row in [[z - 0.5, x0 + 0.5, door0 - 0.15], [z - 0.5, door1 + 0.25, x1 - 0.5], [z - 3.0, x0 + 0.5, x1 - 0.5]]:
		var rz: float = row[0]
		bx("wood", row[1], row[2], 0.0, 0.05, rz - 0.4, rz)
		for shelf in 4:
			var sy := 0.35 + shelf * 0.5
			bx("wood", row[1], row[2], sy, sy + 0.03, rz - 0.4, rz)
			var gx: float = row[1] + 0.04
			while gx < float(row[2]) - 0.08:
				var gw := _rng.randf_range(0.07, 0.18)
				var gh := _rng.randf_range(0.12, 0.32)
				bx("goods", gx, gx + gw, sy + 0.03, sy + 0.03 + gh, rz - 0.32, rz - 0.06, goods[_rng.randi() % goods.size()])
				gx += gw + 0.015
	# 橱窗玻璃（亮面）和门：绿漆木门、上半截玻璃
	for r in [win_l, win_r]:
		var rr: Rect2 = r
		bx("shopglass", rr.position.x, rr.end.x, rr.position.y, rr.end.y, z - 0.2, z - 0.19)
		bx("wood_green", rr.position.x - 0.05, rr.end.x + 0.05, rr.position.y - 0.08, rr.position.y, z - 0.25, z + 0.04)
	bx("wood_green", door0 + 0.05, door1 - 0.05, 0.0, 2.3, z - 0.2, z - 0.15)
	bx("glass", door0 + 0.15, door1 - 0.15, 1.1, 2.15, z - 0.155, z - 0.14)
	# 招牌：绿底白字
	bx("sign_green", x0 + 0.6, x1 - 0.6, 2.62, 3.05, z + 0.01, z + 0.09)
	_labels["shop"] = _label("小卖部", Vector3((x0 + x1) / 2.0, 2.84, z + 0.095), 0.011, Color("#f4eee1"))
	# 门口：冰柜（白的，印个「冰」）、邮筒（绿）
	bx("metal_white", 11.2, 12.15, 0.0, 0.85, -0.95, -0.35)
	bx("chrome", 11.2, 12.15, 0.85, 0.88, -0.95, -0.35)
	_label("冰 糕", Vector3(11.675, 0.5, -0.345), 0.006, Color("#3b7ea8"))
	cyl("metal_green", Vector3(12.55, 0, -0.55), 0.24, 0.24, 1.12, 16)
	cyl("metal_green", Vector3(12.55, 1.12, -0.55), 0.27, 0.1, 0.16, 16)
	bx("metal", 12.38, 12.72, 0.92, 0.95, -0.32, -0.3)
	_label("邮", Vector3(12.55, 0.65, -0.305), 0.007, Color("#f4eee1"))
	_shop_light(Vector3((x0 + x1) / 2.0, 2.2, z - 1.5), 0.9)


func _alley(x0: float, x1: float) -> void:
	var z := FZ
	var lane0 := 13.45
	var lane1 := 14.65
	var b0 := lane1
	var b1 := 22.3
	# 胡同口左边那一小段（接小卖部）
	upper_floors("brick_dark", x0, lane0, 0.0, 2, z, z - 9.0, 0.0, 9.0)
	# 胡同：两边是墙，地上铺砖，往里走一盏灯
	bx("pavers", lane0, lane1, -0.2, 0.0, -24.0, FZ - 0.4)
	bx("brick_dark", lane0 - 0.25, lane0, 0.0, 6.0, -24.0, z - 0.3)
	bx("brick", lane1, lane1 + 0.25, 0.0, 9.6, -24.0, z - 0.3)
	# 过街楼：胡同口上头还是楼，下面一个门洞
	bx("brick_dark", lane0, lane1, 2.6, 6.75, z - 0.3, z)
	bx("concrete", lane0 - 0.05, lane1 + 0.05, 2.5, 2.62, z - 0.35, z + 0.05)
	bx("wood_light", lane0 + 0.2, lane1 - 0.2, 2.9, 3.2, z + 0.0, z + 0.06)
	_label("早市", Vector3((lane0 + lane1) / 2.0, 3.05, z + 0.065), 0.0055, Color("#2b2a33"))
	_lamp_wall(Vector3((lane0 + lane1) / 2.0, 2.4, -9.0))
	# 胡同深处：尽头一面墙、晾着的衣服
	bx("plaster", lane0, lane1, 0.0, 4.0, -24.2, -24.0)
	tube("metal", PackedVector3Array([Vector3(lane0, 2.3, -14.0), Vector3(lane1, 2.25, -14.0)]), 0.008, 4)
	for k in 3:
		bx("goods", lane0 + 0.2 + k * 0.35, lane0 + 0.45 + k * 0.35, 1.7, 2.25, -14.02, -13.98, [Color("#d9485f"), Color("#e8e2d4"), Color("#4a6aa0")][k])
	# 3 号楼：三层红砖，一层也是住家的窗，中间单元门
	upper_floors("brick", b0, b1, 0.0, 3, z, z - 11.0, 1.15, 1.85)
	# 单元门：门洞、门头雨搭、台阶、门牌
	var dx := 17.0
	bx("metal_green", dx - 0.6, dx + 0.6, 0.0, 2.3, z - 0.32, z - 0.28)
	bx("metal", dx - 0.6, dx + 0.6, 0.0, 2.3, z - 0.28, z - 0.27)
	bx("concrete", dx - 0.95, dx + 0.95, 2.45, 2.57, z, z + 0.75)
	bx("concrete", dx - 0.8, dx + 0.8, 0.0, 0.14, z, z + 0.35)
	bx("sign_green", dx + 0.75, dx + 1.25, 1.7, 2.05, z + 0.01, z + 0.05)
	_label("3号楼", Vector3(dx + 1.0, 1.875, z + 0.055), 0.0034, Color("#f4eee1"))
	# 竖着的地名牌「河畔里」
	bx("sign_green", 21.9, 22.25, 1.2, 2.6, z + 0.01, z + 0.06)
	_label("河\n畔\n里", Vector3(22.075, 1.9, z + 0.065), 0.0055, Color("#f4eee1"))
	# 告示栏：两条腿、一块板、贴着几张纸
	var nx := 15.3
	for lx in [nx - 0.62, nx + 0.62]:
		bx("metal", lx - 0.03, lx + 0.03, 0.0, 1.95, -0.85, -0.79)
	bx("wood_red", nx - 0.72, nx + 0.72, 0.95, 1.95, -0.86, -0.8)
	bx("sign_red", nx - 0.78, nx + 0.78, 1.95, 2.1, -0.9, -0.74)
	_label("告  示", Vector3(nx, 2.025, -0.735), 0.004, Color("#f8f1e2"))
	for k in 4:
		bx("paper", nx - 0.6 + k * 0.31, nx - 0.6 + k * 0.31 + _rng.randf_range(0.2, 0.27), 1.1 + _rng.randf() * 0.3, 1.5 + _rng.randf() * 0.35, -0.8, -0.795)
	# 石头棋桌、两个石墩
	var cx := 20.1
	cyl("stone", Vector3(cx, 0, -0.65), 0.16, 0.2, 0.66, 12)
	cyl("stone", Vector3(cx, 0.66, -0.65), 0.42, 0.42, 0.06, 20)
	bx("paper", cx - 0.2, cx + 0.2, 0.721, 0.723, -0.85, -0.45)
	for sx in [cx - 0.7, cx + 0.7]:
		cyl("stone", Vector3(sx, 0, -0.65), 0.17, 0.15, 0.4, 12)
	# 夜市的小摊（灯下一张桌子、一筐水果）
	_folding_table(Vector3(22.75, 0, -0.85), false)
	cyl("bamboo", Vector3(22.75, 0.72, -0.85), 0.22, 0.26, 0.16, 12)
	for k in 7:
		var fx := 22.62 + (k % 4) * 0.08
		Kit.box_into(_tool("goods"), Vector3(0.07, 0.07, 0.07), Transform3D(Basis(), Vector3(fx, 0.9, -0.9 + (k / 4) * 0.08)), Color("#e07a2f"))
	_lamp_post(Vector3(23.0, 0, -0.95), 2.0, 0.8)
	# 门前的大槐树
	_tree(Vector3(18.65, 0, -0.95), 0.95, "huai")
	# 去公园的口子：两栋楼中间，后头一片绿
	bx("pavers", b1, x1, -0.2, 0.0, -18.0, FZ - 0.4)
	bx("brick_grey", b1 + 0.2, b1 + 0.45, 0.0, 1.9, -1.0, -0.9)
	bx("brick_grey", x1 - 0.45, x1 - 0.2, 0.0, 1.9, -1.0, -0.9)
	bx("metal_green", b1 + 0.45, x1 - 0.45, 1.65, 1.9, -0.99, -0.92)
	_label("河畔公园", Vector3((b1 + x1) / 2.0, 1.775, -0.915), 0.0042, Color("#f4eee1"))
	for k in 4:
		_tree(Vector3(b1 + 0.4 + k * 0.6, 0, -6.0 - k * 2.7), 0.8 + _rng.randf() * 0.4, "huai")
	_hedge(Vector3((b1 + x1) / 2.0, 0.0, -3.0), x1 - b1 - 0.4, 0.6)


func _bikeshop(x0: float, x1: float) -> void:
	var z := FZ
	# 后面一栋两层的楼（往后退一点），前面是铁皮棚
	upper_floors("brick_grey", x0, x1, 0.0, 2, z - 3.2, z - 12.0, 1.1, 1.9)
	# 去中学的路口：棚子左边一条窄路
	bx("asphalt", x0, x0 + 1.9, -0.2, -0.01, -30.0, FZ - 0.4)
	var s0 := x0 + 1.9
	# 棚：三根铁柱、斜的波纹铁皮顶、后墙是砖
	bx("brick_grey", s0, x1, 0.0, 2.6, z - 3.0, z - 2.75)
	bx("brick_grey", s0, s0 + 0.24, 0.0, 2.75, z - 3.0, z)
	bx("brick_grey", x1 - 0.24, x1, 0.0, 2.75, z - 3.0, z)
	var roof := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(10.0)), Vector3((s0 + x1) / 2.0, 2.85, z - 1.2))
	Kit.box_into(_tool("iron"), Vector3(x1 - s0 + 0.3, 0.025, 3.9), roof)
	for px in [s0 + 0.1, (s0 + x1) / 2.0, x1 - 0.1]:
		cyl("metal", Vector3(px, 0, z + 0.55), 0.04, 0.04, 2.55, 8)
	bx("metal", s0, x1, 2.5, 2.58, z + 0.5, z + 0.6)
	# 招牌「修车」：黑底白字，挂在棚檐上
	bx("sign_ink", s0 + 0.6, s0 + 2.3, 2.6, 3.05, z + 0.62, z + 0.68)
	_label("修车", Vector3(s0 + 1.45, 2.825, z + 0.685), 0.0095, Color("#f4eee1"))
	# 后墙上挂着一圈圈车胎、工具板
	for k in 5:
		var tx := s0 + 0.7 + k * 0.62
		_ring("rubber", Vector3(tx, 1.75 + (k % 2) * 0.12, z - 2.7), 0.33, 0.028)
	bx("wood_light", x1 - 1.8, x1 - 0.5, 1.0, 2.0, z - 2.74, z - 2.7)
	for k in 6:
		bx("metal", x1 - 1.7 + k * 0.2, x1 - 1.66 + k * 0.2, 1.2, 1.75, z - 2.7, z - 2.66)
	# 长条凳、工具箱、打气筒
	bx("wood", 27.6, 28.6, 0.42, 0.47, -0.8, -0.5)
	for lx in [27.7, 28.5]:
		bx("wood", lx - 0.03, lx + 0.03, 0.0, 0.42, -0.78, -0.52)
	bx("sign_red", 28.75, 29.2, 0.0, 0.28, -0.85, -0.55)
	cyl("metal", Vector3(26.3, 0, -0.75), 0.03, 0.03, 0.62, 8)
	# 倒扣着修的那辆二八车（车把车座着地）和停着的几辆
	_bike(Vector3(27.1, 0, -0.55), 0.0, true, "metal")
	_bike(Vector3(29.25, 0, -0.95), 0.12, false, "metal_green")
	_bike(Vector3(29.95, 0, -1.05), -0.08, false, "metal")
	_bike(Vector3(25.0, 0, -1.6), 0.0, false, "sign_red")
	_shop_light(Vector3((s0 + x1) / 2.0, 2.3, z - 1.2), 0.8)


func _teahouse(x0: float, x1: float) -> void:
	var z := FZ
	# 两层木楼：一层敞开（戏台、茶座），二层木格窗，坡瓦檐
	_room(x0 + 0.3, x1 - 0.3, 0.0, 2.75, z, 4.0, "wood", "wood_light")
	bx("wood_red", x0, x0 + 0.3, 0.0, 6.2, z - 0.3, z + 0.05)
	bx("wood_red", x1 - 0.3, x1, 0.0, 6.2, z - 0.3, z + 0.05)
	for px in [x0 + 2.6, x0 + 5.1]:
		cyl("wood_red", Vector3(px, 0, z - 0.1), 0.11, 0.11, 2.75, 10)
		bx("stone", px - 0.16, px + 0.16, 0.0, 0.15, z - 0.26, z + 0.06)
	bx("wood", x0, x1, 2.75, 3.15, z - 0.3, z + 0.05)
	# 二层：一排木格窗
	var holes: Array = []
	var n := 4
	for i in n:
		var wx := x0 + 0.6 + i * (x1 - x0 - 1.2) / n + 0.15
		var ww := (x1 - x0 - 1.2) / n - 0.3
		holes.append(Rect2(wx, 3.7, ww, 1.6))
		bx("glass", wx, wx + ww, 3.7, 5.3, z - 0.22, z - 0.2, Color(_rng.randf(), _rng.randf(), 0.0))
		# 木格子
		var k := 0.0
		while k <= ww + 0.001:
			bx("wood_red", wx + k - 0.015, wx + k + 0.015, 3.7, 5.3, z - 0.2, z - 0.16)
			k += ww / 6.0
		for gy in [3.7, 4.23, 4.77, 5.28]:
			bx("wood_red", wx, wx + ww, gy, gy + 0.03, z - 0.2, z - 0.16)
	wall("wood", x0 + 0.3, x1 - 0.3, 3.15, 6.2, z, 0.3, holes)
	bx("wood", x0, x1, 0.0, 6.2, z - 9.0, z - 0.3)
	# 坡瓦檐：一层顶上、二层顶上各一道
	for ey in [3.25, 6.3]:
		var eave := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(28.0)), Vector3((x0 + x1) / 2.0, ey, z + 0.35))
		Kit.box_into(_tool("tiles"), Vector3(x1 - x0 + 0.6, 0.06, 1.25), eave)
	bx("tiles", x0 - 0.3, x1 + 0.3, 6.55, 7.3, z - 9.0, z - 0.25)
	# 招牌：黑底金字的横匾
	bx("sign_ink", x0 + 1.9, x1 - 1.9, 3.35, 3.65, z + 0.06, z + 0.12)
	_label("河 畔 茶 社", Vector3((x0 + x1) / 2.0, 3.5, z + 0.125), 0.0058, Color("#e7c56a"))
	# 一串红灯笼
	for lx in [x0 + 1.0, x0 + 3.85, x1 - 1.0]:
		tube("metal", PackedVector3Array([Vector3(lx, 3.0, z + 0.55), Vector3(lx, 2.75, z + 0.55)]), 0.006, 4)
		_lantern(Vector3(lx, 2.55, z + 0.55))
	# 戏台：一层里头抬高一截、红幕
	var st0 := 32.5
	bx("wood_light", st0, st0 + 1.6, 0.0, 0.32, z - 3.6, z - 0.4)
	bx("lantern", st0 + 0.05, st0 + 1.55, 0.32, 2.6, z - 3.7, z - 3.62)
	for cx in [st0 + 0.05, st0 + 1.5]:
		bx("lantern", cx, cx + 0.06, 0.32, 2.6, z - 3.6, z - 0.6)
	# 茶座：方桌、长凳、盖碗
	for tx in [35.8, 37.55]:
		bx("wood", tx - 0.42, tx + 0.42, 0.74, 0.79, -1.1, -0.45)
		for lx in [tx - 0.38, tx + 0.38]:
			for lz in [-1.06, -0.49]:
				bx("wood", lx - 0.03, lx + 0.03, 0.0, 0.74, lz - 0.03, lz + 0.03)
		bx("wood", tx - 0.5, tx + 0.5, 0.42, 0.46, -1.4, -1.2)
		for k in 2:
			cyl("metal_white", Vector3(tx - 0.15 + k * 0.3, 0.79, -0.75), 0.05, 0.065, 0.06, 10)
	# 公交站（坐车去医院）
	cyl("metal", Vector3(31.5, 0, CURB - 0.15), 0.04, 0.04, 2.5, 8)
	bx("metal_white", 31.2, 31.8, 1.9, 2.5, CURB - 0.19, CURB - 0.11)
	_label("公交\n医院方向", Vector3(31.5, 2.2, CURB - 0.105), 0.0042, Color("#b53a30"))
	_shop_light(Vector3(x0 + 2.0, 2.3, z - 1.5), 1.0)
	_shop_light(Vector3(x1 - 2.0, 2.3, z - 1.5), 0.9)


## 街尾：护栏、台阶下去是海河边，几棵柳树
func _street_end(x0: float, x1: float) -> void:
	bx("concrete", x0, x1, -0.2, 0.0, -20.0, FZ - 0.4)
	bx("stone", x0 + 0.6, x1, 0.0, 0.5, -4.2, -4.0)
	for k in 12:
		var px := x0 + 0.8 + k * 0.85
		cyl("metal", Vector3(px, 0.5, -4.1), 0.025, 0.025, 0.65, 6)
	tube("metal", PackedVector3Array([Vector3(x0 + 0.8, 1.15, -4.1), Vector3(x1, 1.15, -4.1)]), 0.025, 6)
	bx("water", x0 - 2.0, x1 + 10.0, -1.5, -1.4, -60.0, -4.3)
	for k in 3:
		_tree(Vector3(x0 + 1.2 + k * 2.8, 0, -3.2), 1.0, "willow")
	bx("sign_green", 39.0, 39.8, 2.2, 2.5, -0.2, -0.16)
	cyl("metal", Vector3(39.4, 0, -0.18), 0.035, 0.035, 2.2, 8)
	_label("海河 →", Vector3(39.4, 2.35, -0.155), 0.0055, Color("#f4eee1"))


## 电线杆 + 垂着的电线、路灯
func _poles() -> void:
	var xs := [-3.0, 9.2, 21.0, 33.2, 45.0]
	for px in xs:
		cyl("concrete", Vector3(px, 0, CURB - 0.2), 0.11, 0.075, 7.6, 10)
		bx("metal", px - 0.75, px + 0.75, 7.0, 7.08, CURB - 0.24, CURB - 0.16)
		for k in 3:
			cyl("metal_white", Vector3(px - 0.6 + k * 0.6, 7.08, CURB - 0.2), 0.03, 0.03, 0.08, 6)
		bx("metal", px - 0.2, px + 0.2, 5.6, 6.0, CURB - 0.35, CURB - 0.06)
	for i in xs.size() - 1:
		for k in 3:
			var a := Vector3(float(xs[i]) - 0.6 + k * 0.6, 7.15, CURB - 0.2)
			var b := Vector3(float(xs[i + 1]) - 0.6 + k * 0.6, 7.15, CURB - 0.2)
			_wire(a, b, 0.55 + k * 0.08)
		_wire(Vector3(float(xs[i]), 5.8, CURB - 0.2), Vector3(float(xs[i + 1]), 5.8, CURB - 0.2), 0.4)
	# 从杆子上往楼里拉的入户线
	for px in [9.2, 21.0]:
		_wire(Vector3(px, 5.8, CURB - 0.2), Vector3(px - 1.5, 5.2, FZ), 0.15)
	# 路灯：弯臂伸到人行道上头
	for lx in [3.9, 16.0, 28.2, 37.0]:
		_street_lamp(Vector3(lx, 0, CURB - 0.25))


## 后头一排排的居民楼：五到七层，远了被雾吃掉一点；夜里一格格窗亮着
func _background() -> void:
	var rows := [[-16.0, 1.0, 0.0], [-30.0, 1.25, 7.0], [-48.0, 1.6, 3.0]]
	for row in rows:
		var bz: float = row[0]
		var x := -24.0 + float(row[2])
		while x < 66.0:
			var w := _rng.randf_range(10.0, 18.0)
			var floors := _rng.randi_range(4, 7) + (1 if bz < -20.0 else 0)
			var h := floors * 2.9
			var key: String = ["plaster_far", "brick_grey", "plaster_far", "brick"][_rng.randi() % 4]
			bx(key, x, x + w, 0.0, h, bz - 10.0, bz)
			bx("concrete", x - 0.05, x + w + 0.05, h, h + 0.4, bz - 10.0, bz + 0.05)
			# 一格格窗（不挖洞，贴一层就行，远了看不出）
			for f in floors:
				var wx := x + 0.7
				while wx < x + w - 1.4:
					bx("glass_far", wx, wx + 1.0, f * 2.9 + 0.9, f * 2.9 + 2.2, bz, bz + 0.03, Color(_rng.randf(), _rng.randf(), _rng.randf()))
					wx += 1.75
			# 楼顶的水箱、天线
			if _rng.randf() < 0.6:
				bx("concrete", x + w * 0.3, x + w * 0.3 + 2.0, h + 0.4, h + 1.8, bz - 6.0, bz - 4.0)
			if _rng.randf() < 0.5:
				cyl("metal", Vector3(x + w * 0.7, h + 0.4, bz - 3.0), 0.03, 0.02, 2.4, 5)
			x += w + _rng.randf_range(0.5, 4.0)


# ======================================================================
# 小零件
# ======================================================================

## 一间敞着的屋子（铺面里头）：后墙、两侧、天花、地面
func _room(x0: float, x1: float, y0: float, y1: float, z: float, depth: float, wall_key: String, floor_key: String) -> void:
	bx(wall_key, x0, x1, y0, y1, z - depth - 0.1, z - depth)
	bx(wall_key, x0 - 0.1, x0, y0, y1, z - depth, z - 0.3)
	bx(wall_key, x1, x1 + 0.1, y0, y1, z - depth, z - 0.3)
	bx(wall_key, x0, x1, y1, y1 + 0.1, z - depth, z - 0.3)
	bx(floor_key, x0, x1, y0 - 0.02, y0 + 0.005, z - depth, z)


func _folding_table(at: Vector3, stools := true) -> void:
	bx("metal_white", at.x - 0.38, at.x + 0.38, 0.68, 0.71, at.z - 0.3, at.z + 0.3)
	for dx in [-0.33, 0.33]:
		for dz in [-0.25, 0.25]:
			bx("metal", at.x + dx - 0.015, at.x + dx + 0.015, 0.0, 0.68, at.z + dz - 0.015, at.z + dz + 0.015)
	if stools:
		for sx in [at.x - 0.55, at.x + 0.55]:
			bx("sign_red", sx - 0.14, sx + 0.14, 0.3, 0.33, at.z - 0.12, at.z + 0.12)
			for dx in [-0.11, 0.11]:
				bx("metal", sx + dx - 0.012, sx + dx + 0.012, 0.0, 0.3, at.z - 0.1, at.z + 0.1)


## 二八自行车：两个大轮子、三角大梁、车把、车座、后架。upside = 倒扣着修
func _bike(at: Vector3, yaw: float, upside: bool, frame_key: String) -> void:
	var r := 0.33
	var wb := 1.1
	var b := Basis(Vector3.UP, yaw)
	if upside:
		b = b * Basis(Vector3.FORWARD, PI)
	var lift := 0.0 if not upside else 1.02
	var o := at + Vector3(0, lift, 0)
	var rear := o + b * Vector3(-wb / 2.0, r, 0)
	var front := o + b * Vector3(wb / 2.0, r, 0)
	_ring_b("rubber", rear, r, 0.022, b)
	_ring_b("rubber", front, r, 0.022, b)
	_ring_b("chrome", rear, r * 0.92, 0.008, b)
	_ring_b("chrome", front, r * 0.92, 0.008, b)
	var seat := o + b * Vector3(-0.2, 0.95, 0)
	var head := o + b * Vector3(0.38, 0.98, 0)
	var crank := o + b * Vector3(-0.05, 0.3, 0)
	for seg in [[rear, crank], [crank, seat], [seat, head], [crank, head], [head, front], [rear, seat]]:
		tube(frame_key, PackedVector3Array([seg[0], seg[1]]), 0.018, 5)
	tube("chrome", PackedVector3Array([head, head + b * Vector3(-0.05, 0.12, 0.28)]), 0.012, 5)
	tube("chrome", PackedVector3Array([head, head + b * Vector3(-0.05, 0.12, -0.28)]), 0.012, 5)
	Kit.box_into(_tool("rubber"), Vector3(0.24, 0.05, 0.11), Transform3D(b, seat + b * Vector3(0, 0.04, 0)))
	Kit.box_into(_tool(frame_key), Vector3(0.36, 0.02, 0.12), Transform3D(b, o + b * Vector3(-0.55, 0.78, 0)))


func _ring(key: String, c: Vector3, r: float, t: float) -> void:
	_ring_b(key, c, r, t, Basis())


## 一圈管子（车轮、轮胎）：在 b 的 XY 面上
func _ring_b(key: String, c: Vector3, r: float, t: float, b: Basis) -> void:
	var pts := PackedVector3Array()
	for i in 21:
		var a := TAU * float(i) / 20.0
		pts.append(c + b * Vector3(cos(a) * r, sin(a) * r, 0))
	tube(key, pts, t, 6)


func _wire(a: Vector3, b: Vector3, sag: float) -> void:
	var pts := PackedVector3Array()
	for i in 13:
		var t := float(i) / 12.0
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	tube("metal", pts, 0.009, 4)


func _street_lamp(at: Vector3) -> void:
	cyl("metal", at, 0.07, 0.05, 4.8, 8)
	var top := at + Vector3(0, 4.8, 0)
	# 灯臂伸到马路上（朝镜头这边），灯照着人行道和人，不贴着墙打出一块亮斑
	var arm := PackedVector3Array([top, top + Vector3(0, 0.25, 0.3), top + Vector3(0, 0.3, 1.1), top + Vector3(0, 0.22, 1.5)])
	tube("metal", arm, 0.03, 6)
	var head := top + Vector3(0, 0.12, 1.5)
	bx("metal", head.x - 0.18, head.x + 0.18, head.y, head.y + 0.1, head.z - 0.28, head.z + 0.28)
	bx("lamp", head.x - 0.15, head.x + 0.15, head.y - 0.03, head.y, head.z - 0.24, head.z + 0.24)
	_add_lamp(head + Vector3(0, -0.3, 0), Color(1.0, 0.72, 0.42), 10.0, 1.8)


func _lamp_post(at: Vector3, h: float, k: float) -> void:
	cyl("metal", at, 0.025, 0.02, h, 6)
	bx("lamp", at.x - 0.08, at.x + 0.08, at.y + h - 0.12, at.y + h, at.z - 0.08, at.z + 0.08)
	_add_lamp(at + Vector3(0, h - 0.2, 0.2), Color(1.0, 0.8, 0.55), 4.0, 1.4 * k)


func _lamp_wall(at: Vector3) -> void:
	bx("metal", at.x - 0.1, at.x + 0.1, at.y, at.y + 0.08, at.z - 0.1, at.z + 0.1)
	bx("lamp", at.x - 0.08, at.x + 0.08, at.y - 0.03, at.y, at.z - 0.08, at.z + 0.08)
	_add_lamp(at + Vector3(0, -0.2, 0), Color(1.0, 0.78, 0.5), 6.0, 1.3)


func _shop_light(at: Vector3, k: float) -> void:
	_add_lamp(at, Color(1.0, 0.82, 0.58), 5.5, 1.5 * k, 0.35)


## 一盏灯：夜里 stage3d 按钟点开；day 白天也留一点（店里开着灯）
func _add_lamp(at: Vector3, col: Color, rng: float, energy: float, day := 0.0) -> void:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = col
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.light_energy = energy
	l.set_meta("energy", energy)
	l.set_meta("day", day)
	l.shadow_enabled = false
	l.visible = false
	add_child(l)
	lamps.append([l, 1.0])


func _lantern(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.ellipsoid(Vector3(0.16, 0.19, 0.16), 14, 10)
	mi.material_override = _mat("lantern")
	mi.position = at
	add_child(mi)
	bx("sign_ink", at.x - 0.08, at.x + 0.08, at.y + 0.17, at.y + 0.22, at.z - 0.08, at.z + 0.08)
	bx("sign_ink", at.x - 0.08, at.x + 0.08, at.y - 0.22, at.y - 0.17, at.z - 0.08, at.z + 0.08)


func _label(text: String, at: Vector3, px: float, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = P.font()
	l.font_size = 96
	l.pixel_size = px * 0.45
	l.modulate = col
	l.outline_size = 0
	l.position = at
	l.double_sided = false
	l.shaded = true
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.line_spacing = -8.0
	add_child(l)
	return l


## 树：主干分几杈往上，杈子顶上一团团树冠（季节换颜色，冬天只剩枝子）
func _tree(at: Vector3, s: float, kind: String) -> void:
	var trunk_h := 2.6 * s
	tube("trunk", PackedVector3Array([at, at + Vector3(0.05, trunk_h * 0.5, 0.02), at + Vector3(-0.05, trunk_h, 0.0)]), 0.16 * s, 8, 0.11 * s)
	var crown := at + Vector3(0, trunk_h, 0)
	var tips: Array = []
	for i in 5:
		var a := TAU * float(i) / 5.0 + _rng.randf() * 0.5
		var tip := crown + Vector3(cos(a) * 1.3 * s, (1.2 + _rng.randf() * 1.1) * s, sin(a) * 0.9 * s)
		tube("trunk", PackedVector3Array([crown, crown.lerp(tip, 0.5) + Vector3(0, 0.25 * s, 0), tip]), 0.08 * s, 6, 0.025 * s)
		tips.append(tip)
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE
	var holder := Node3D.new()
	holder.position = at
	add_child(holder)
	# 树冠：枝头一团团（模型树的海绵团），中间再填几团，外圈的小、里头的大
	var clumps: Array = []
	for t in tips:
		clumps.append([(t as Vector3), 0.75])
		clumps.append([(t as Vector3).lerp(crown, 0.35) + Vector3(0, 0.35 * s, 0), 0.65])
	for i in 7:
		var a2 := TAU * float(i) / 7.0 + 0.3
		var rr := _rng.randf_range(0.4, 1.3) * s
		clumps.append([crown + Vector3(cos(a2) * rr, (1.5 + _rng.randf() * 1.3) * s, sin(a2) * rr * 0.7), 0.6])
	clumps.append([crown + Vector3(0, 2.7 * s, 0), 0.7])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in clumps:
		var r: float = (float(c[1]) + _rng.randf() * 0.2) * s * (0.85 if kind == "willow" else 1.0)
		var e := Kit.ellipsoid(Vector3(r * 1.1, r * (1.35 if kind == "willow" else 0.82), r), 12, 8)
		var off: Vector3 = (c[0] as Vector3) - at + (Vector3(0, -0.6 * s, 0) if kind == "willow" else Vector3.ZERO)
		st.append_from(e, 0, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), off))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	holder.add_child(mi)
	_foliage.append([holder, mat, kind])


func _hedge(at: Vector3, w: float, h: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE
	mat.set_shader_parameter("sway", 0.2)
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.ellipsoid(Vector3(w / 2.0, h, 0.4), 18, 8)
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	_foliage.append([mi, mat, "hedge"])


# ======================================================================
# 年代、季节
# ======================================================================

## 年代上的小东西：防盗窗（少年起家家装）、空调外机（青年起）。各自一批，整批开关
func _era_bits() -> void:
	var z := FZ
	_begin()
	for wx in [3.1, 5.0, 15.3, 17.15, 19.0, 20.85]:
		var y := FLOOR_H + 0.9 if wx < 10.0 else FLOOR_H * 2.0 + 0.9
		var w := 1.25
		var d := 0.42
		for k in 7:
			bx("metal", wx - 0.07 + k * (w / 6.0), wx - 0.05 + k * (w / 6.0), y - 0.05, y + 1.5, z + d - 0.02, z + d)
		for gy in [y - 0.05, y + 0.7, y + 1.5]:
			bx("metal", wx - 0.07, wx + w - 0.05, gy, gy + 0.025, z, z + d)
		bx("metal", wx - 0.07, wx + w - 0.05, y + 1.5, y + 1.53, z, z + d)
	var cages := Node3D.new()
	add_child(cages)
	_commit(cages)
	_era_nodes.append([cages, 1, 4])
	_begin()
	for p in [[6.4, FLOOR_H + 0.45], [12.0, FLOOR_H + 0.5], [18.2, FLOOR_H * 2.0 + 0.4], [21.0, FLOOR_H + 0.4], [16.1, 0.45 + FLOOR_H * 2.0]]:
		var ax: float = p[0]
		var ay: float = p[1]
		bx("metal_white", ax, ax + 0.8, ay, ay + 0.55, z + 0.02, z + 0.3)
		cyl("metal", Vector3(ax + 0.3, ay + 0.28, z + 0.31), 0.18, 0.18, 0.01, 14)
		bx("metal", ax - 0.02, ax + 0.82, ay - 0.04, ay, z, z + 0.32)
	var acs := Node3D.new()
	add_child(acs)
	_commit(acs)
	_era_nodes.append([acs, 2, 4])


func set_look(p_look: String) -> void:
	look = p_look
	var i := LOOKS.find(look)
	if i < 0:
		i = 0
	for e in _era_nodes:
		(e[0] as Node3D).visible = i >= int(e[1]) and i <= int(e[2])
	if _labels.has("shop"):
		(_labels.shop as Label3D).text = "便利店" if i >= 3 else ("超  市" if i == 2 else "小卖部")


func set_season(season: String) -> void:
	var cols := {
		"spring": [Color("#7fa55a"), Color("#b5c97a")],
		"summer": [Color("#3f6b33"), Color("#6f8f3e")],
		"autumn": [Color("#b7782f"), Color("#d9a63e")],
		"winter": [Color("#6b6a4e"), Color("#8a8763")],
	}
	var c: Array = cols.get(season, cols.summer)
	for f in _foliage:
		var mat: ShaderMaterial = f[1]
		var kind: String = f[2]
		var a: Color = c[0]
		var b: Color = c[1]
		if kind == "willow" and season != "autumn":
			a = a.lightened(0.12)
			b = b.lightened(0.15)
		if kind == "hedge":
			a = Color("#365e34")
			b = Color("#4f7a3e")
		mat.set_shader_parameter("leaf", a)
		mat.set_shader_parameter("leaf2", b)
		(f[0] as Node3D).visible = season != "winter" or kind == "hedge"


## 每帧：只开镜头附近的灯（兼容渲染器一个东西最多吃八盏灯）
func tick(_delta: float, cam_x: float) -> void:
	for l in lamps:
		var light: OmniLight3D = l[0]
		l[1] = 1.0 if absf(light.position.x - cam_x) < 13.0 else 0.0
