extends "res://scripts/world3d/set3d.gd"
## 海河边（content/maps/river.yaml，宽 36 米）的实时 3D：一段河堤步道，右头接一座铁桥。
## 从左到右：回楼下的石阶（往左上去）、晨跑的那段、长椅（放风筝）、地上粉笔画的跳房子、烤山芋的炉子（小时候）、
## 栏杆（13 米那一段漆色跟着年代换）、救生圈、钓鱼的台阶口（栏杆断开、石阶往下通到水边、马扎水桶钓竿）、
## 桥头石墩和灯、铁桥（桥面就在人走的高度，钢桁架立在人身后，前头只一道矮护栏，桥上值班的小岗亭）。
## 人身后：石头柱子 + 铸铁栏杆，柳树歪着身子探到水上；再往后是河水（自己的 river_water 水面），六十米外是对岸：
## 河堤、一溜树、一排路灯，后头是楼群（小时候、少年：老厂房锯齿顶、烟囱、水塔、红砖楼、码头吊车；
## 青年：厂子拆了大半，起了一排板楼、塔吊；中年、老年：玻璃高楼，夜里一格格亮窗、楼顶红灯和灯带）。
## 人前头：路牙、矮矮一溜花池和地灯，再往前草坡往下。
##
## 对岸的楼是「缩小了摆远」的（微缩模型的老办法）：镜头只比人高两米多、平着看，真尺寸的楼一过天边就出画了，
## 所以楼按大概四成的尺寸搭，摆在一百到两百米外，雾一吃，看着就是很远的一整片城。
## 水里的倒影是假的（兼容渲染器没有屏幕空间反射）：水面按菲涅尔叠天色，贴着对岸压一道暗；
## 灯的倒影是平铺在水面上、朝镜头拉长的一条条光（river_glint），天黑才亮。
## 年代：栏杆那段的漆、路灯样式（老式球灯 → 新式）、对岸的楼群、烤山芋的。季节：夏天有人游泳，冬天河面冻上、有人拉冰车，
## 春天天上一只风筝；不是冬天河上有船。雨雪由 stage3d 的全局参数管（水面结冰见 river_water）。

const WATER := preload("res://shaders/3d/river_water.gdshader")
const GLINT := preload("res://shaders/3d/river_glint.gdshader")

const W := 36.0
const B0 := 26.3      ## 桥从这儿起
const RZ := -1.05     ## 栏杆中线
const WY := -2.3      ## 水面
const FAR := -62.0    ## 对岸河堤的前脸
const TZ := -1.65     ## 桥后头那片桁架
const FISH := 20.0    ## 钓鱼的台阶口
const RAIL := 13.1    ## 跟着年代换漆的那段栏杆
## 栏杆石柱（18.95 和 21.05 之间断开，是下到水边的台阶）
const PIERS := [0.7, 2.9, 5.1, 7.3, 9.5, 11.9, 14.3, 16.6, 18.95, 21.05, 23.2, 25.4]
const LAMPS := [0.7, 5.1, 9.5, 14.3, 18.95, 23.2]           ## 柱子上立路灯的那几根
const WILLOWS := [2.2, 10.9, 16.0, 23.7]         ## 柳树
const BRIDGE_LAMPS := [28.9, 31.5, 34.1, 36.7]   ## 桁架竖杆上挑出来的桥灯（出了画面的那盏只有灯头、不点）
const FILLS := [4.0, 13.0, 22.0, 31.0]           ## 坡底下小路的路灯（看不见，只往上映一点光）
const MAX_LAMPS := 8                             ## 兼容渲染器一个东西最多吃八盏灯：只开离镜头最近的八盏

var _water_mat: ShaderMaterial
var _season_nodes: Array = []   ## [节点, 哪几个季节有]


func build(sc: Dictionary, p_look: String, season: String) -> void:
	_rng.seed = 20261118
	look = p_look
	_materials()
	_begin()
	_promenade()
	_stairs_up()
	_railing()
	_spots()
	_bridge()
	_commit(self)
	_era_lamps()
	_rail_paint()
	_yam_cart()
	_willows()
	_planter_shrubs()
	_far_bank()
	_skylines()
	_water()
	_glints()
	_seasonal()
	set_look(look)
	set_season(season)


func _materials() -> void:
	extra_mats = {
		"slab": [2, "#bab2a4", "#847c71", Vector2(0.6, 0.4), 0.88, 1.0, 0.35, 0.1, 0.0],
		"slab_dark": [2, "#8f887e", "#605a53", Vector2(0.42, 0.42), 0.9, 1.0, 0.4, 0.1, 0.0],
		"granite": [6, "#b2aa9e", "#000000", Vector2.ONE, 0.82, 0.8, 0.45, 0.1, 0.0],
		"embank": [1, "#8d877c", "#5c5750", Vector2(0.62, 0.3), 0.92, 1.0, 0.65, 0.14, 0.0],
		"soil": [6, "#4b3d2f", "#000000", Vector2.ONE, 1.0, 1.0, 0.0, 0.2, 0.0],
		"grass": [6, "#2c3d1f", "#000000", Vector2.ONE, 1.0, 1.4, 0.0, 0.35, 0.0],
		"reed": [0, "#8c7c4c", "#000000", Vector2.ONE, 0.9, 0.0, 0.0, 0.0, 0.0],
		"rail_iron": [0, "#2b3431", "#000000", Vector2.ONE, 0.5, 0.0, 0.0, 0.0, 0.5],
		"rail_old": [6, "#5b8a77", "#000000", Vector2.ONE, 0.6, 0.4, 0.45, 0.12, 0.3],
		"rail_mid": [6, "#6c5446", "#000000", Vector2.ONE, 0.78, 0.7, 0.6, 0.2, 0.3],
		"rail_new": [0, "#2b7c84", "#000000", Vector2.ONE, 0.3, 0.0, 0.0, 0.0, 0.35],
		"steel": [6, "#56685f", "#000000", Vector2.ONE, 0.62, 0.35, 0.55, 0.12, 0.35],
		"deck": [2, "#74685a", "#3a332c", Vector2(0.18, 3.0), 0.85, 1.0, 0.3, 0.14, 0.0],
		"ember": [0, "#6a2610", "#000000", Vector2.ONE, 0.9, 0.0, 0.0, 0.0, 0.0],
		"bulb": [0, "#fff0c8", "#000000", Vector2.ONE, 0.4, 0.0, 0.0, 0.0, 0.0],
		# 对岸：远了不要砖缝（会闪），用抹灰的斑驳就够
		"embank_far": [6, "#7a756c", "#000000", Vector2.ONE, 0.95, 0.4, 0.5, 0.12, 0.0],
		"far_stone": [6, "#9b968c", "#000000", Vector2.ONE, 0.95, 0.3, 0.3, 0.1, 0.0],
		"far_red": [6, "#8b5243", "#000000", Vector2.ONE, 0.95, 0.3, 0.35, 0.14, 0.0],
		"far_grey": [6, "#8e8c86", "#000000", Vector2.ONE, 0.95, 0.3, 0.35, 0.12, 0.0],
		"far_white": [6, "#c8c4ba", "#000000", Vector2.ONE, 0.92, 0.3, 0.3, 0.1, 0.0],
		"far_dark": [6, "#58585b", "#000000", Vector2.ONE, 0.9, 0.3, 0.2, 0.1, 0.0],
		"far_steel": [0, "#7b4334", "#000000", Vector2.ONE, 0.7, 0.0, 0.0, 0.0, 0.3],
		"crane_y": [0, "#c49a35", "#000000", Vector2.ONE, 0.6, 0.0, 0.0, 0.0, 0.2],
		"win_far": [8, "#2a333c", "#000000", Vector2(0.7, 1.15), 0.2, 0.0, 0.0, 0.0, 0.0],
		"win_mid": [8, "#2e3943", "#000000", Vector2(0.6, 1.0), 0.18, 0.0, 0.0, 0.0, 0.0],
		"glass_tower": [8, "#3d5468", "#000000", Vector2(0.75, 0.9), 0.08, 0.0, 0.0, 0.0, 0.25],
		"glass_tower2": [8, "#283a4e", "#000000", Vector2(0.9, 0.9), 0.08, 0.0, 0.0, 0.0, 0.25],
		"lamp_far": [0, "#fff0d0", "#000000", Vector2.ONE, 0.4, 0.0, 0.0, 0.0, 0.0],
		"beacon": [0, "#c83a2a", "#000000", Vector2.ONE, 0.5, 0.0, 0.0, 0.0, 0.0],
		"led": [0, "#d8ecf5", "#000000", Vector2.ONE, 0.5, 0.0, 0.0, 0.0, 0.0],
	}
	extra_glow = {
		"bulb": [5.0, "#ffd08a"], "lamp_far": [7.0, "#ffd29a"], "beacon": [6.0, "#ff3a20"],
		"led": [2.6, "#9fd4ff"], "ember": [3.0, "#ff6a2a"],
	}


# ======================================================================
# 河堤步道：石板、压边、路牙、花池、草坡；桥头的石砌桥台
# ======================================================================

func _promenade() -> void:
	var x1 := B0 - 0.6
	# 步道：浅色花岗岩石板；靠栏杆一溜深色压边（台阶口那儿断开）
	bx("slab", -6.0, x1, -0.3, 0.0, RZ + 0.17, 1.7)
	for seg in [[-6.0, 19.15], [20.85, x1]]:
		bx("slab_dark", float(seg[0]), float(seg[1]), -0.3, 0.004, RZ - 0.3, RZ + 0.42)
	bx("slab_dark", 19.15, 20.85, -0.3, 0.004, RZ + 0.17, RZ + 0.42)
	# 前沿：一道路牙、矮矮的石砌花池（里头的灌木另一批）、地灯
	# （花池、草坡一直接到桥台的端面为止，桥那头底下是空的、看得见桥下的水）
	bx("granite", -6.0, B0, -0.3, 0.1, 1.7, 1.92)
	bx("embank", -6.0, B0, -0.7, 0.3, 1.92, 2.9)
	bx("granite", -6.0, B0 + 0.04, 0.3, 0.36, 1.9, 1.98)
	bx("granite", -6.0, B0 + 0.04, 0.3, 0.36, 2.84, 2.92)
	bx("granite", B0 - 0.08, B0 + 0.04, 0.3, 0.36, 1.98, 2.84)
	bx("soil", -6.0, B0 - 0.08, 0.3, 0.33, 1.98, 2.84)
	var bxl := 1.8
	while bxl < B0 - 1.0:
		cyl("metal", Vector3(bxl, 0.1, 1.81), 0.07, 0.07, 0.36, 10)
		cyl("lamp", Vector3(bxl, 0.46, 1.81), 0.06, 0.06, 0.06, 10)
		cyl("metal", Vector3(bxl, 0.52, 1.81), 0.08, 0.05, 0.04, 10)
		bxl += 3.6
	# 草坡往下（画面最底下）
	var top := Vector2(2.9, -0.1)
	var bot := Vector2(7.6, -2.9)
	var ln := top.distance_to(bot)
	var ang := atan2(top.y - bot.y, bot.x - top.x)
	bc("grass", Vector3((-6.0 + B0) / 2.0, (top.y + bot.y) / 2.0 - 0.12, (top.x + bot.x) / 2.0), Vector3(B0 + 6.0, 0.25, ln), 0.0, ang)
	# 坡上靠花池那一溜：一丛丛芦苇（2D 那张图底下也有）
	var rx := -5.0
	while rx < B0 - 1.5:
		var rz := _rng.randf_range(3.1, 3.6)
		var ry := -0.1 - (rz - 2.9) * 0.6
		for k in _rng.randi_range(3, 6):
			var b := Vector3(rx + _rng.randf_range(-0.2, 0.2), ry, rz + _rng.randf_range(-0.1, 0.1))
			var tip := b + Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf_range(0.55, 0.95), _rng.randf_range(-0.05, 0.05))
			tube("reed", PackedVector3Array([b, b.lerp(tip, 0.6) + Vector3(0.02, 0, 0), tip]), 0.008, 3, 0.003)
			if _rng.randf() < 0.5:
				var hd := b.lerp(tip, 0.78)
				cyl("trunk", hd, 0.018, 0.018, 0.1, 5)
		rx += _rng.randf_range(0.6, 1.8)
	# 栏杆底下的河堤（往下到水，镜头这边看不见正脸，挡住缝）
	for seg in [[-6.0, FISH - 1.0], [FISH + 1.0, B0]]:
		bx("embank", float(seg[0]), float(seg[1]), WY - 0.6, -0.3, RZ - 0.35, RZ + 0.3)
	# 桥台：石块砌的一大块，顶面接着步道，朝右的那面下到水里
	bx("embank", B0 - 0.9, B0, WY - 0.6, 0.0, RZ - 1.6, 1.7)
	bx("granite", B0 - 0.9, B0 + 0.05, -0.08, 0.0, RZ - 1.6, 1.7)
	bx("embank", B0 - 0.6, B0, -3.2, -0.7, 1.7, 3.0)


## 回楼下：左头一段石阶往左上去（街比河堤高一截），外侧石墙压一道斜的扶手；路口一根指路牌
func _stairs_up() -> void:
	var x0 := 0.45
	for i in 11:
		bx("granite", -6.0, x0 - i * 0.3, 0.0, (i + 1) * 0.15, RZ + 0.17, 1.5)
		bx("slab_dark", -6.0, x0 - i * 0.3, (i + 1) * 0.15 - 0.01, (i + 1) * 0.15 + 0.004, 1.42, 1.5)
	# 外侧：一级一级的石墙，顶上斜着压一条花岗岩
	for i in 11:
		bx("embank", -6.0, x0 + 0.2 - i * 0.3, -0.3, (i + 1) * 0.15 + 0.5, 1.5, 1.85)
	var a := atan2(0.15, 0.3)
	var c := Vector3(x0 + 0.2 - 1.8, 0.62 + 1.8 * 0.5 + 0.07, 1.675)
	Kit.box_into(_tool("granite"), Vector3(3.9, 0.1, 0.45), Transform3D(Basis(Vector3.BACK, -a), c))
	# 里侧（靠河）一道高一点的石墙，接着河边栏杆
	bx("embank", -6.0, x0 + 0.05, 0.0, 2.3, RZ - 0.3, RZ + 0.17)
	bx("granite", -6.0, x0 + 0.1, 2.3, 2.4, RZ - 0.34, RZ + 0.21)
	# 指路牌
	cyl("metal", Vector3(1.3, 0, -0.75), 0.035, 0.035, 2.45, 8)
	bx("sign_green", 0.82, 1.78, 2.02, 2.32, -0.79, -0.75)
	_label("← 河畔里", Vector3(1.3, 2.17, -0.745), 0.0058, Color("#f4eee1"))


# ======================================================================
# 栏杆：石柱子 + 铸铁栏杆（中间一排铁圈），柱子上隔几根立一盏路灯
# ======================================================================

func _railing() -> void:
	for i in PIERS.size():
		var px: float = PIERS[i]
		bx("granite", px - 0.17, px + 0.17, 0.0, 1.0, RZ - 0.17, RZ + 0.17)
		bx("granite", px - 0.21, px + 0.21, 1.0, 1.08, RZ - 0.21, RZ + 0.21)
		bx("granite", px - 0.13, px + 0.13, 1.08, 1.14, RZ - 0.13, RZ + 0.13)
		if not LAMPS.has(px):
			cyl("granite", Vector3(px, 1.14, RZ), 0.09, 0.02, 0.12, 8)
		if i == PIERS.size() - 1:
			break
		var a := px + 0.17
		var b: float = float(PIERS[i + 1]) - 0.17
		if a > FISH - 1.2 and b < FISH + 1.2:
			continue   # 台阶口
		bx("granite", a, b, 0.0, 0.22, RZ - 0.14, RZ + 0.14)
		if a < RAIL and b > RAIL:
			continue   # 这一段的铁栏杆单独一批（跟着年代换漆）
		_panel("rail_iron", a, b)


## 一格铸铁栏杆：上下横杆、一根根竖条、中间一排铁圈
func _panel(key: String, a: float, b: float) -> void:
	bx(key, a, b, 0.93, 0.98, RZ - 0.035, RZ + 0.035)
	bx(key, a, b, 0.22, 0.27, RZ - 0.025, RZ + 0.025)
	bx(key, a, b, 0.66, 0.69, RZ - 0.02, RZ + 0.02)
	var n := int((b - a) / 0.14)
	for k in n + 1:
		var x := a + (b - a) * float(k) / float(n)
		bx(key, x - 0.011, x + 0.011, 0.27, 0.93, RZ - 0.011, RZ + 0.011)
	var m := int((b - a) / 0.42)
	for k in m:
		var cx := a + (b - a) * (float(k) + 0.5) / float(m)
		_hoop(key, Vector3(cx, 0.465, RZ), 0.15, 0.011)


## 一圈细铁（立着，在 XY 面上）：段数少一点，省三角形
func _hoop(key: String, c: Vector3, r: float, t: float, n := 12, col := Color.WHITE) -> void:
	var pts := PackedVector3Array()
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector3(cos(a) * r, sin(a) * r, 0))
	Kit.tube_into(_tool(key), pts, t, 4, -1.0, col)


## 平躺在水面上的一圈（游泳的人身边的水花）
func _hoop_flat(key: String, c: Vector3, r: float, t: float, col := Color.WHITE) -> void:
	var pts := PackedVector3Array()
	for i in 13:
		var a := TAU * float(i) / 12.0
		pts.append(c + Vector3(cos(a) * r, 0, sin(a) * r * 0.8))
	Kit.tube_into(_tool(key), pts, t, 4, -1.0, col)


## 带颜色的细管子：季节、年代的小东西都并进 goods 一批（省 draw call）
func _tc(pts: PackedVector3Array, r: float, col: Color) -> void:
	Kit.tube_into(_tool("goods"), pts, r, 3, -1.0, col)


## 一个球（灯罩、人头）：三节圆台叠起来，能和盒子并在一批里
func _globe(key: String, c: Vector3, r: float, seg := 10, col := Color.WHITE) -> void:
	cyl(key, c + Vector3(0, -r, 0), r * 0.35, r * 0.92, r * 0.55, seg, col)
	cyl(key, c + Vector3(0, -r * 0.45, 0), r * 0.92, r * 0.92, r * 0.9, seg, col)
	cyl(key, c + Vector3(0, r * 0.45, 0), r * 0.92, r * 0.3, r * 0.55, seg, col)


## 这段栏杆的漆：小时候、少年刷着青漆；青年、中年掉了漆、锈红；老年刷了新漆
func _rail_paint() -> void:
	var a := 11.9 + 0.17
	var b := 14.3 - 0.17
	for e in [["rail_old", 0, 1], ["rail_mid", 2, 3], ["rail_new", 4, 4]]:
		_begin()
		_panel(str(e[0]), a, b)
		var n := Node3D.new()
		add_child(n)
		_commit(n)
		_era_nodes.append([n, int(e[1]), int(e[2])])


## 路灯：老式（铸铁杆顶一个白球）→ 新式（细方杆、挑出来一个扁灯头）。灯光两种共用
func _era_lamps() -> void:
	for p in LAMPS:
		var x: float = p
		_add_lamp(Vector3(x, 3.2, RZ + 0.7), Color(1.0, 0.76, 0.48), 10.5, 1.9)
	_add_lamp(Vector3(B0 - 0.45, 2.7, TZ + 0.9), Color(1.0, 0.76, 0.48), 7.0, 1.3)
	# 坡底下还有一条沿河的小路，那边的路灯照不进画面，只把花池前脸、草坡、人脸前头映亮一点（不然夜里画面底下一整条黑）
	for fx in FILLS:
		_add_lamp(Vector3(float(fx), 1.1, 4.6), Color(1.0, 0.84, 0.62), 7.5, 0.55)
	_begin()
	for p in LAMPS:
		var x: float = p
		var base := Vector3(x, 1.14, RZ)
		cyl("metal", base, 0.07, 0.05, 0.35, 8)
		cyl("metal", base + Vector3(0, 0.35, 0), 0.04, 0.035, 2.0, 8)
		cyl("metal", base + Vector3(0, 0.9, 0), 0.055, 0.055, 0.08, 8)
		cyl("metal", base + Vector3(0, 2.35, 0), 0.06, 0.08, 0.1, 8)
		_globe("lamp", base + Vector3(0, 2.66, 0), 0.22, 12)
		cyl("metal", base + Vector3(0, 2.86, 0), 0.06, 0.02, 0.08, 8)
	var old := Node3D.new()
	add_child(old)
	_commit(old)
	_era_nodes.append([old, 0, 1])
	_begin()
	for p in LAMPS:
		var x: float = p
		var base := Vector3(x, 1.14, RZ)
		bx("far_dark", x - 0.1, x + 0.1, 1.14, 1.4, RZ - 0.1, RZ + 0.1)
		cyl("far_dark", base, 0.055, 0.04, 2.45, 10)
		cyl("far_dark", base + Vector3(0, 2.45, 0), 0.08, 0.12, 0.08, 12)
		cyl("lamp", base + Vector3(0, 2.53, 0), 0.12, 0.12, 0.42, 12)
		for k in 4:
			var aa := TAU * float(k) / 4.0 + PI / 4.0
			bx("far_dark", x + cos(aa) * 0.12 - 0.012, x + cos(aa) * 0.12 + 0.012, 3.67, 4.09, RZ + sin(aa) * 0.12 - 0.012, RZ + sin(aa) * 0.12 + 0.012)
		cyl("far_dark", base + Vector3(0, 2.95, 0), 0.16, 0.03, 0.14, 12)
	var neu := Node3D.new()
	add_child(neu)
	_commit(neu)
	_era_nodes.append([neu, 2, 4])


# ======================================================================
# 点位上的东西
# ======================================================================

func _spots() -> void:
	# 河边（5.6）：一张铸铁腿、青漆木条的长椅，背靠着河
	var bx0 := 5.6
	for sx in [-0.72, 0.72]:
		var lx: float = bx0 + sx
		bx("metal", lx - 0.03, lx + 0.03, 0.0, 0.4, -0.88, -0.5)
		bx("metal", lx - 0.03, lx + 0.03, 0.4, 0.86, -0.9, -0.85)
		bx("metal", lx - 0.03, lx + 0.03, 0.55, 0.59, -0.86, -0.52)
	for k in 4:
		bx("wood_green", bx0 - 0.88, bx0 + 0.88, 0.4, 0.43, -0.84 + k * 0.085, -0.77 + k * 0.085)
	for k in 3:
		bx("wood_green", bx0 - 0.88, bx0 + 0.88, 0.5 + k * 0.12, 0.58 + k * 0.12, -0.885, -0.86)
	# 小孩跑的地方（8.2）：地上粉笔画的跳房子
	var cells := [[7.35, 7.75, 1], [7.75, 8.15, 1], [8.15, 8.55, 2], [8.55, 8.95, 1], [8.95, 9.35, 2]]
	for c in cells:
		var x0: float = c[0]
		var x1: float = c[1]
		var z0 := -0.32
		var z1 := 0.28
		for zz in [z0, z1]:
			bx("paint", x0, x1, 0.0, 0.003, zz - 0.012, zz + 0.012)
		for xx in [x0, x1]:
			bx("paint", xx - 0.012, xx + 0.012, 0.0, 0.003, z0, z1)
		if int(c[2]) == 2:
			bx("paint", x0, x1, 0.0, 0.003, -0.032, -0.008)
	bx("goods", 8.68, 8.74, 0.0, 0.015, -0.12, -0.06, Color("#c9473c"))
	# 救生圈：一根杆、一圈红白
	cyl("metal", Vector3(18.3, 0, -0.84), 0.03, 0.03, 1.5, 8)
	bx("metal", 18.24, 18.36, 1.38, 1.44, -0.86, -0.74)
	_hoop("sign_red", Vector3(18.3, 1.1, -0.76), 0.24, 0.05, 16)
	for k in 4:
		var aa := TAU * float(k) / 4.0 + PI / 4.0
		var pc := Vector3(18.3 + cos(aa) * 0.24, 1.1 + sin(aa) * 0.24, -0.76)
		bc("paint", pc, Vector3(0.08, 0.08, 0.11), 0.0, 0.0)
	_fishing()


## 钓鱼的台阶口：两根柱子中间断开，石阶往下通到水边一个小平台；边上马扎、水桶、竿子
func _fishing() -> void:
	var z := RZ + 0.17
	for i in 12:
		var top := -float(i + 1) * 0.18
		bx("granite", FISH - 0.85, FISH + 0.85, WY - 0.4, top, z - (i + 1) * 0.3, z - i * 0.3)
	var zb := z - 12 * 0.3
	bx("granite", FISH - 1.6, FISH + 1.6, WY - 0.6, WY + 0.12, zb - 1.4, zb)
	# 两边的石头挡墙，跟着台阶往下
	for sx in [FISH - 1.0, FISH + 0.85]:
		for i in 12:
			var top2 := 0.22 - float(i) * 0.18
			bx("embank", sx, sx + 0.15, WY - 0.4, top2, z - (i + 1) * 0.3, z - i * 0.3)
	# 两道铁扶手顺着台阶往下：台阶本身从步道上看不见，扶手弯下去的那一截让人看得出「这儿能下到水边」
	for hx in [FISH - 0.74, FISH + 0.74]:
		var hp := PackedVector3Array([Vector3(hx, 0.0, z - 0.06), Vector3(hx, 0.92, z - 0.06), Vector3(hx, 0.95, z - 0.3)])
		for i in [2, 6, 10, 12]:
			hp.append(Vector3(hx, 0.95 - float(i) * 0.18, z - float(i) * 0.3))
		tube("rail_iron", hp, 0.024, 6)
		for i in [4, 8]:
			var pz := z - float(i) * 0.3 - 0.15
			cyl("rail_iron", Vector3(hx, -float(i + 1) * 0.18, pz), 0.02, 0.02, 0.95, 6)
	# 马扎（帆布面）、蓝水桶、一根竿子搭在叉子上伸到水上
	var mx := FISH + 0.55
	for s in [-1.0, 1.0]:
		bc("metal", Vector3(mx, 0.17, -0.6), Vector3(0.02, 0.4, 0.02), 0.0, s * 0.6)
	bx("goods", mx - 0.14, mx + 0.14, 0.32, 0.34, -0.72, -0.48, Color("#3f5f7a"))
	cyl("goods", Vector3(FISH - 0.55, 0, -0.62), 0.12, 0.15, 0.26, 12, Color("#3b6ea8"))
	cyl("goods", Vector3(FISH - 0.55, 0.26, -0.62), 0.155, 0.155, 0.02, 12, Color("#2c5583"))
	tube("metal", PackedVector3Array([Vector3(FISH - 0.65, 0.27, -0.62), Vector3(FISH - 0.55, 0.42, -0.62), Vector3(FISH - 0.45, 0.27, -0.62)]), 0.006, 4)
	cyl("metal", Vector3(FISH + 0.2, 0, -0.62), 0.012, 0.012, 0.5, 5)
	tube("metal", PackedVector3Array([Vector3(FISH + 0.2, 0.5, -0.62), Vector3(FISH + 0.14, 0.58, -0.62)]), 0.008, 4)
	tube("metal", PackedVector3Array([Vector3(FISH + 0.2, 0.5, -0.62), Vector3(FISH + 0.26, 0.58, -0.62)]), 0.008, 4)
	var butt := Vector3(FISH - 0.1, 0.1, -0.45)
	var tip := Vector3(FISH + 1.25, 2.55, -4.6)
	tube("rail_iron", PackedVector3Array([butt, butt.lerp(tip, 0.5) + Vector3(0, 0.08, 0), tip]), 0.016, 5, 0.005)
	var bob := Vector3(FISH + 1.5, WY + 0.02, -7.6)
	var line := PackedVector3Array()
	for i in 9:
		var t := float(i) / 8.0
		var p := tip.lerp(bob, t)
		p.y -= 0.35 * 4.0 * t * (1.0 - t)
		line.append(p)
	tube("paint", line, 0.004, 3)
	cyl("sign_red", bob, 0.025, 0.01, 0.12, 6)
	# 另一根竿子靠在柱子上
	tube("trunk", PackedVector3Array([Vector3(FISH + 1.12, 0.0, -0.78), Vector3(FISH + 0.98, 2.3, -0.98)]), 0.014, 5, 0.006)


# ======================================================================
# 铁桥
# ======================================================================

## 一根钢构件：从 a 到 b（X、Y），立在 z 那个面上；w 宽、d 厚
func _member(key: String, a: Vector2, b: Vector2, z: float, w: float, d: float) -> void:
	var c := Vector3((a.x + b.x) / 2.0, (a.y + b.y) / 2.0, z)
	var ang := atan2(b.y - a.y, b.x - a.x)
	Kit.box_into(_tool(key), Vector3(a.distance_to(b), w, d), Transform3D(Basis(Vector3.BACK, ang), c))
	# 槽钢的两道边：前脸再贴两条，接得住光
	var n := Vector2(-sin(ang), cos(ang)) * (w / 2.0 - 0.02)
	for s in [-1.0, 1.0]:
		var off := Vector3(n.x * s, n.y * s, d / 2.0 + 0.012)
		Kit.box_into(_tool(key), Vector3(a.distance_to(b), 0.04, 0.025), Transform3D(Basis(Vector3.BACK, ang), c + off))


func _bridge() -> void:
	var x1 := 52.0
	# 桥面：横铺的木板，钢边
	bx("deck", B0, x1, -0.12, 0.0, TZ + 0.2, 1.15)
	bx("steel", B0, x1, -0.12, 0.05, 1.08, 1.18)
	# 前脸的钢板梁：一道道加劲板、两排铆钉、下翼缘
	bx("steel", B0, x1, -0.95, -0.12, 0.9, 1.15)
	bx("steel", B0, x1, -1.0, -0.92, 0.85, 1.25)
	var x := B0 + 0.4
	while x < x1:
		bx("steel", x - 0.03, x + 0.03, -0.92, -0.12, 1.15, 1.2)
		x += 0.85
	x = B0 + 0.1
	while x < x1:
		for ry in [-0.2, -0.84]:
			bx("metal", x - 0.012, x + 0.012, float(ry) - 0.012, float(ry) + 0.012, 1.15, 1.17)
		x += 0.17
	# 前头一道矮护栏（不挡人）
	bx("steel", B0, x1, 0.55, 0.6, 1.0, 1.08)
	bx("steel", B0, x1, 0.28, 0.31, 1.02, 1.06)
	x = B0 + 0.3
	while x < x1:
		bx("steel", x - 0.025, x + 0.025, 0.0, 0.55, 1.01, 1.07)
		x += 1.3
	# 后头的桁架：下弦、上弦、斜的端柱、竖杆、斜撑，节点上一块块连接板
	bx("steel", B0 + 0.1, x1, -0.95, 0.4, TZ - 0.2, TZ + 0.2)
	var pw := 2.6
	var h := 4.25
	_member("steel", Vector2(B0 + 0.35, 0.3), Vector2(B0 + pw, h), TZ, 0.3, 0.3)
	bx("steel", B0 + pw - 0.1, x1, h - 0.15, h + 0.18, TZ - 0.18, TZ + 0.18)
	var xs: Array = []
	x = B0 + pw
	while x < x1:
		xs.append(x)
		x += pw
	for i in xs.size():
		var xv: float = xs[i]
		_member("steel", Vector2(xv, 0.35), Vector2(xv, h - 0.1), TZ, 0.2, 0.22)
		if i + 1 < xs.size():
			var xn: float = xs[i + 1]
			if i % 2 == 0:
				_member("steel", Vector2(xv, h - 0.1), Vector2(xn, 0.4), TZ, 0.18, 0.2)
			else:
				_member("steel", Vector2(xv, 0.4), Vector2(xn, h - 0.1), TZ, 0.18, 0.2)
		for gy in [0.25, h - 0.05]:
			bx("steel", xv - 0.38, xv + 0.38, float(gy) - 0.32, float(gy) + 0.32, TZ + 0.12, TZ + 0.15)
			for rx in [-0.25, 0.0, 0.25]:
				for ry in [-0.2, 0.2]:
					bx("metal", xv + float(rx) - 0.015, xv + float(rx) + 0.015, float(gy) + float(ry) - 0.015, float(gy) + float(ry) + 0.015, TZ + 0.15, TZ + 0.17)
	# 桥上一串灯：竖杆顶上垂下来的一溜小灯泡
	for i in xs.size() - 1:
		var a := Vector3(float(xs[i]), h - 0.3, TZ + 0.2)
		var b := Vector3(float(xs[i + 1]), h - 0.3, TZ + 0.2)
		var pts := PackedVector3Array()
		for k in 9:
			var t := float(k) / 8.0
			var p := a.lerp(b, t)
			p.y -= 0.45 * 4.0 * t * (1.0 - t)
			pts.append(p)
			if k > 0 and k < 8:
				bx("bulb", p.x - 0.035, p.x + 0.035, p.y - 0.09, p.y - 0.02, p.z - 0.035, p.z + 0.035)
		tube("metal", pts, 0.008, 3)
	# 河上的桥夜里都勾一道轮廓灯：上弦、端柱、前脸钢梁的下沿一溜小灯头（白天看就是一颗颗灯座）
	var lx0 := B0 + 0.3
	while lx0 < x1:
		bx("bulb", lx0 - 0.03, lx0 + 0.03, -1.06, -1.0, 1.22, 1.28)
		if lx0 > B0 + pw:
			bx("bulb", lx0 - 0.03, lx0 + 0.03, h + 0.18, h + 0.23, TZ + 0.14, TZ + 0.2)
		lx0 += 0.5
	for k in 8:
		var ep := Vector2(B0 + 0.35, 0.3).lerp(Vector2(B0 + pw, h), (float(k) + 0.5) / 8.0)
		bx("bulb", ep.x - 0.17, ep.x - 0.11, ep.y - 0.03, ep.y + 0.03, TZ + 0.15, TZ + 0.21)
	# 桥灯：竖杆上挑出来
	for p in BRIDGE_LAMPS:
		var lx: float = p
		tube("steel", PackedVector3Array([Vector3(lx, 3.0, TZ + 0.12), Vector3(lx, 3.2, TZ + 0.5), Vector3(lx, 3.2, TZ + 0.85)]), 0.035, 6)
		bx("metal", lx - 0.16, lx + 0.16, 3.12, 3.22, TZ + 0.68, TZ + 1.02)
		bx("lamp", lx - 0.13, lx + 0.13, 3.08, 3.12, TZ + 0.71, TZ + 0.99)
		if lx < W:
			_add_lamp(Vector3(lx, 2.8, TZ + 1.0), Color(1.0, 0.8, 0.55), 7.5, 1.5)
	# 桥头石墩：后头一根高的顶一盏灯，前头一块矮的
	var px := B0 - 0.45
	bx("granite", px - 0.36, px + 0.36, 0.0, 2.0, TZ - 0.36, TZ + 0.36)
	bx("granite", px - 0.42, px + 0.42, 2.0, 2.12, TZ - 0.42, TZ + 0.42)
	bx("embank", px - 0.37, px + 0.37, 0.15, 0.25, TZ - 0.37, TZ + 0.37)
	cyl("metal", Vector3(px, 2.12, TZ), 0.06, 0.04, 0.35, 8)
	_globe("lamp", Vector3(px, 2.68, TZ), 0.22, 12)
	bx("granite", px - 0.34, px + 0.34, 0.0, 0.55, 1.2, 1.75)
	bx("granite", px - 0.38, px + 0.38, 0.55, 0.62, 1.16, 1.79)
	# 桥墩：水里一个石头墩子，两头削尖分水
	var mx := 33.4
	bx("embank", mx - 0.7, mx + 0.7, WY - 0.5, -1.0, TZ - 0.6, 1.9)
	for zz in [TZ - 0.6, 1.9]:
		bc("embank", Vector3(mx, (WY - 0.5 - 1.0) / 2.0, float(zz)), Vector3(0.99, WY * -1.0 - 0.5, 0.99), PI / 4.0)
	bx("granite", mx - 0.78, mx + 0.78, -1.05, -0.95, TZ - 0.7, 2.0)
	# 桥上值班的小岗亭（29.4）：白铁皮、绿顶、一扇窗夜里亮着
	var gx := 29.4
	bx("metal_white", gx - 0.45, gx + 0.45, 0.0, 2.1, TZ + 0.25, -0.6)
	bx("metal_green", gx - 0.55, gx + 0.55, 2.1, 2.2, TZ + 0.15, -0.5)
	bx("metal_green", gx - 0.47, gx + 0.47, 0.0, 0.12, TZ + 0.23, -0.58)
	bx("glass", gx - 0.3, gx + 0.3, 1.1, 1.75, -0.61, -0.59, Color(0.95, 0.3, 0.6))
	bx("metal_green", gx - 0.33, gx + 0.33, 1.07, 1.1, -0.62, -0.57)
	bx("metal_green", gx - 0.33, gx + 0.33, 1.75, 1.78, -0.62, -0.57)


# ======================================================================
# 树：柳树歪着探到水上（垂下来的一绺绺枝条），花池里的矮灌木
# ======================================================================

func _willows() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_begin()
	for p in WILLOWS:
		var x: float = p
		var base := Vector3(x, 0.0, -0.62)
		var lean := _rng.randf_range(-0.25, 0.25)
		var top := base + Vector3(lean, 3.2, -0.75)
		tube("trunk", PackedVector3Array([base, base + Vector3(lean * 0.2, 1.3, -0.08), base + Vector3(lean * 0.6, 2.4, -0.42), top]), 0.16, 8, 0.09)
		# 树坑：一块铸铁箅子
		bx("metal", x - 0.42, x + 0.42, 0.0, 0.012, -0.86, -0.4)
		for k in 6:
			var a := TAU * float(k) / 6.0 + _rng.randf() * 0.4
			var tip := top + Vector3(cos(a) * 1.5, _rng.randf_range(0.4, 0.9), sin(a) * 1.15 - 0.55)
			var mid := top.lerp(tip, 0.5) + Vector3(0, 0.35, 0)
			tube("trunk", PackedVector3Array([top, mid, tip]), 0.06, 5, 0.02)
			# 枝头往下垂一绺绺：越在水上越长；步道上头的收短，别垂到人脸前
			# 一团团往下垂的（模型树的海绵团拉长了），挨着挤成一挂帘子；中间夹几绺细的
			for j in 7:
				var t := 0.3 + 0.7 * float(j) / 6.0
				var q: Vector3 = top.lerp(mid, t * 2.0) if t < 0.5 else mid.lerp(tip, (t - 0.5) * 2.0)
				q += Vector3(_rng.randf_range(-0.2, 0.2), 0.1, _rng.randf_range(-0.2, 0.2))
				var thin := j % 3 == 2
				var ln := _rng.randf_range(1.1, 2.4) if not thin else _rng.randf_range(1.6, 2.8)
				if q.z > -0.9:
					ln = minf(ln, maxf(0.5, q.y - 2.6))
				var r := Vector3(0.3, ln / 2.0, 0.26) * _rng.randf_range(0.8, 1.1) if not thin else Vector3(0.1, ln / 2.0, 0.09)
				r.y = ln / 2.0
				var e := Kit.ellipsoid(r, 7 if not thin else 5, 7)
				var tilt := Basis(Vector3.BACK, _rng.randf_range(-0.12, 0.12)) * Basis(Vector3.UP, _rng.randf() * TAU)
				st.append_from(e, 0, Transform3D(tilt, q - Vector3(0, ln / 2.0 - 0.15, 0)))
		for k in 9:
			var a2 := TAU * float(k) / 9.0 + _rng.randf() * 0.5
			var rr := _rng.randf_range(0.4, 1.1)
			var c := top + Vector3(cos(a2) * rr, 0.45 + _rng.randf() * 0.45, sin(a2) * rr * 0.8 - 0.35)
			st.append_from(Kit.ellipsoid(Vector3(0.42, 0.3, 0.38) * _rng.randf_range(0.8, 1.2), 8, 6), 0, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), c))
	_commit(self)
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	_foliage.append([mi, mat, "willow"])


func _planter_shrubs() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := -5.5
	while x < B0 - 1.4:
		var r := Vector3(_rng.randf_range(0.38, 0.52), _rng.randf_range(0.18, 0.26), 0.36)
		st.append_from(Kit.ellipsoid(r, 9, 6), 0, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(x, 0.33, 2.41)))
		x += _rng.randf_range(0.55, 0.8)
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE
	mat.set_shader_parameter("sway", 0.15)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	_foliage.append([mi, mat, "hedge"])



# ======================================================================
# 对岸：河堤、步道栏杆、一溜树、路灯；后头的楼群按年代三套
# ======================================================================

func _far_bank() -> void:
	var far := Node3D.new()
	far.name = "far"
	add_child(far)
	_begin()
	bx("embank_far", -70.0, 150.0, WY - 0.5, 0.25, FAR - 1.5, FAR)
	bx("far_stone", -70.0, 150.0, 0.18, 0.28, FAR - 1.6, FAR + 0.08)
	bx("far_stone", -70.0, 150.0, 0.0, 0.22, FAR - 14.0, FAR - 1.5)
	# 河堤脸上：贴着水一道泡湿的深色、隔一段一道往下淌的水渍；两处顺着堤脸斜下去的石阶（码头上下船的）
	bx("far_dark", -70.0, 150.0, WY - 0.1, WY + 0.38, FAR, FAR + 0.03)
	var sx := -66.0
	while sx < 148.0:
		var sw := _rng.randf_range(0.15, 0.4)
		bx("far_dark", sx, sx + sw, _rng.randf_range(-1.4, -0.6), 0.12, FAR, FAR + 0.02)
		sx += _rng.randf_range(2.5, 6.5)
	for s0 in [-14.0, 37.0]:
		var x0: float = s0
		for i in 13:
			bx("far_stone", x0 + i * 0.32, x0 + (i + 1) * 0.32, WY - 0.5, 0.25 - (i + 1) * 0.18, FAR, FAR + 1.3)
		bx("embank_far", x0 - 0.3, x0 + 13 * 0.32 + 0.6, WY - 0.5, WY + 0.25, FAR, FAR + 1.4)
		var a := atan2(-0.18, 0.32)
		Kit.box_into(_tool("far_stone"), Vector3(13 * 0.37, 0.12, 0.14), Transform3D(Basis(Vector3.BACK, a), Vector3(x0 + 13 * 0.16, 0.25 - 13 * 0.09 + 0.75, FAR + 1.28)))
	bx("metal", -70.0, 150.0, 1.0, 1.06, FAR - 0.3, FAR - 0.24)
	var x := -68.0
	while x < 150.0:
		bx("metal", x - 0.04, x + 0.04, 0.28, 1.0, FAR - 0.3, FAR - 0.24)
		x += 2.5
	x = -63.0
	while x < 150.0:
		cyl("metal", Vector3(x, 0.28, FAR - 0.6), 0.06, 0.05, 3.3, 5)
		bx("lamp_far", x - 0.14, x + 0.14, 3.5, 3.8, FAR - 0.74, FAR - 0.46)
		x += 7.0
	# 树干
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	x = -66.0
	while x < 150.0:
		var tz := FAR - _rng.randf_range(3.0, 6.0)
		var hh := _rng.randf_range(2.0, 2.6)
		cyl("trunk", Vector3(x, 0.2, tz), 0.12, 0.08, hh + 0.4, 5)
		for k in 3:
			var c := Vector3(x + _rng.randf_range(-0.8, 0.8), hh + _rng.randf_range(0.0, 0.9), tz + _rng.randf_range(-0.6, 0.6))
			st.append_from(Kit.ellipsoid(Vector3(1.3, 1.0, 1.2) * _rng.randf_range(0.8, 1.15), 8, 6), 0, Transform3D(Basis(), c))
		x += _rng.randf_range(3.0, 4.6)
	_commit(far, false)
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE
	mat.set_shader_parameter("sway", 0.3)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.add_child(mi)
	_foliage.append([mi, mat, "far"])


## 一栋远处的楼：一块楼身、每层一条窗带（贴着，不挖洞）、窗间墙一条条压在窗带前头、女儿墙
func _block(key: String, win: String, x: float, w: float, floors: int, fh: float, z: float, d := 8.0, cols := 0.7) -> void:
	var hh := floors * fh
	bx(key, x, x + w, 0.0, hh, z - d, z)
	for f in floors:
		var fy := f * fh
		bx(win, x + 0.25, x + w - 0.25, fy + fh * 0.3, fy + fh * 0.78, z, z + 0.03)
	var cx := x + 0.25 + cols
	while cx < x + w - 0.4:
		bx(key, cx - 0.09, cx + 0.09, 0.0, hh, z + 0.03, z + 0.06)
		cx += cols
	bx("far_dark", x - 0.06, x + w + 0.06, hh, hh + 0.22, z - d, z + 0.08)


## 锯齿顶的老厂房：一排齿朝一边，天窗那面是玻璃
func _factory(key: String, x: float, w: float, z: float, d: float, wall_h: float) -> void:
	bx(key, x, x + w, 0.0, wall_h, z - d, z)
	var tw := 2.2
	var n := int(w / tw)
	for i in n:
		var tx := x + i * tw
		var a := atan2(1.1, tw)
		var ln := sqrt(tw * tw + 1.1 * 1.1)
		Kit.box_into(_tool("far_dark"), Vector3(ln, 0.08, d), Transform3D(Basis(Vector3.BACK, a), Vector3(tx + tw / 2.0, wall_h + 0.55, z - d / 2.0)))
		bx("win_far", tx + tw - 0.06, tx + tw, wall_h, wall_h + 1.1, z - d, z)
	bx("win_far", x + 0.4, x + w - 0.4, wall_h * 0.45, wall_h * 0.8, z, z + 0.03)


func _chimney(x: float, z: float, h: float, banded: bool) -> void:
	cyl("far_red", Vector3(x, 0, z), 0.75, 0.42, h, 10)
	if banded:
		for k in 2:
			cyl("far_white", Vector3(x, h - 0.9 - k * 1.6, z), 0.47 + k * 0.05, 0.46 + k * 0.05, 0.6, 10)
	cyl("far_dark", Vector3(x, h, z), 0.46, 0.46, 0.18, 10)


## 远处的东西要在画面上冒到多高：p 是投影到人那条线上离地多少米（镜头高 4.1、画面顶 4.9），返回真要搭多高
func _hp(z: float, p: float) -> float:
	return 4.1 + (p - 4.1) * (15.0 - z) / 15.0


func _skylines() -> void:
	# 小时候、少年：老厂房、烟囱、水塔、红砖楼、码头吊车
	var a := Node3D.new()
	a.name = "sky_old"
	add_child(a)
	_begin()
	var x := -66.0
	while x < 130.0:
		var w := _rng.randf_range(9.0, 16.0)
		var fz := -76.0 - _rng.randf_range(0.0, 6.0)
		_factory(["far_red", "far_grey"][_rng.randi() % 2], x, w, fz, 12.0, _hp(fz, _rng.randf_range(4.2, 4.32)) - 1.1)
		x += w + _rng.randf_range(2.0, 7.0)
	x = -80.0
	while x < 140.0:
		var w2 := _rng.randf_range(8.0, 14.0)
		var z2 := -98.0 - _rng.randf_range(0.0, 20.0)
		_block(["far_red", "far_grey", "far_red"][_rng.randi() % 3], "win_far", x, w2, maxi(3, int(_hp(z2, _rng.randf_range(4.28, 4.48)) / 1.15)), 1.15, z2)
		x += w2 + _rng.randf_range(1.0, 6.0)
	x = -100.0
	while x < 160.0:
		var w3 := _rng.randf_range(12.0, 20.0)
		var z3 := -150.0 - _rng.randf_range(0.0, 30.0)
		_block(["far_white", "far_grey"][_rng.randi() % 2], "win_far", x, w3, int(_hp(z3, _rng.randf_range(4.38, 4.6)) / 1.15), 1.15, z3, 10.0, 1.0)
		x += w3 + _rng.randf_range(2.0, 8.0)
	_chimney(8.0, -92.0, _hp(-92.0, 4.72), false)
	_chimney(13.5, -112.0, _hp(-112.0, 4.82), true)
	_chimney(-18.0, -125.0, _hp(-125.0, 4.7), false)
	_chimney(46.0, -135.0, _hp(-135.0, 4.8), true)
	# 水塔：四条腿顶一个圆罐
	var wt := Vector3(24.0, 0, -90.0)
	var wh := _hp(wt.z, 4.55) - 2.1
	for dx in [-0.8, 0.8]:
		for dz in [-0.8, 0.8]:
			bx("far_grey", wt.x + dx - 0.12, wt.x + dx + 0.12, 0.0, wh, wt.z + dz - 0.12, wt.z + dz + 0.12)
	cyl("far_white", wt + Vector3(0, wh, 0), 1.3, 1.3, 1.6, 12)
	cyl("far_dark", wt + Vector3(0, wh + 1.6, 0), 1.35, 0.2, 0.5, 12)
	# 码头的门式吊车（对岸河边）
	var cx := -4.0
	for dx2 in [-1.2, 1.2]:
		_member("far_steel", Vector2(cx + dx2 * 1.4, 0.3), Vector2(cx + dx2 * 0.5, 5.6), FAR - 3.0, 0.22, 0.22)
	bx("far_steel", cx - 6.0, cx + 4.0, 5.6, 6.0, FAR - 3.2, FAR - 2.8)
	bx("far_steel", cx - 0.8, cx + 0.8, 6.0, 6.9, FAR - 3.4, FAR - 2.6)
	_commit(a, false)
	_era_nodes.append([a, 0, 1])

	# 青年：厂子拆了大半，起了一排板楼，还有塔吊在盖
	var b := Node3D.new()
	b.name = "sky_mid"
	add_child(b)
	_begin()
	x = -70.0
	while x < 140.0:
		var w4 := _rng.randf_range(10.0, 18.0)
		var z4 := -88.0 - _rng.randf_range(0.0, 14.0)
		_block(["far_white", "far_grey", "far_white"][_rng.randi() % 3], "win_mid", x, w4, int(_hp(z4, _rng.randf_range(4.35, 4.6))), 1.0, z4, 9.0, 0.6)
		x += w4 + _rng.randf_range(3.0, 9.0)
	x = -110.0
	while x < 170.0:
		var w5 := _rng.randf_range(12.0, 22.0)
		var z5 := -150.0 - _rng.randf_range(0.0, 35.0)
		_block(["far_white", "far_grey"][_rng.randi() % 2], "win_mid", x, w5, int(_hp(z5, _rng.randf_range(4.45, 4.7))), 1.0, z5, 10.0, 0.9)
		x += w5 + _rng.randf_range(2.0, 7.0)
	_factory("far_red", 2.0, 14.0, -76.0, 12.0, _hp(-76.0, 4.25) - 1.1)
	_chimney(13.5, -112.0, _hp(-112.0, 4.82), true)
	_tower_crane(30.0, -96.0, _hp(-96.0, 4.78))
	_tower_crane(-24.0, -118.0, _hp(-118.0, 4.8))
	_commit(b, false)
	_era_nodes.append([b, 2, 2])

	# 中年、老年：玻璃高楼一片，夜里一格格亮、楼顶红灯、楼边的灯带；老烟囱留着
	var c := Node3D.new()
	c.name = "sky_new"
	add_child(c)
	_begin()
	x = -70.0
	while x < 140.0:
		var w6 := _rng.randf_range(10.0, 16.0)
		var z6 := -80.0 - _rng.randf_range(0.0, 8.0)
		_block(["far_white", "far_grey"][_rng.randi() % 2], "win_mid", x, w6, int(_hp(z6, _rng.randf_range(4.2, 4.38))), 1.0, z6, 9.0, 0.6)
		x += w6 + _rng.randf_range(4.0, 12.0)
	x = -110.0
	while x < 170.0:
		var w7 := _rng.randf_range(7.0, 13.0)
		var z := -110.0 - _rng.randf_range(0.0, 70.0)
		var hh := _hp(z, _rng.randf_range(4.45, 4.82) if _rng.randf() < 0.85 else 5.6)
		var key: String = ["glass_tower", "glass_tower2"][_rng.randi() % 2]
		bx(key, x, x + w7, 0.0, hh, z - 9.0, z)
		# 横的楼板线、竖的灯带
		var fy := 3.6
		while fy < hh:
			bx("far_grey", x - 0.03, x + w7 + 0.03, fy, fy + 0.12, z - 9.0, z + 0.04)
			fy += 3.6
		if _rng.randf() < 0.6:
			for ex in [x + 0.05, x + w7 - 0.05]:
				bx("led", float(ex) - 0.05, float(ex) + 0.05, 0.0, hh, z - 0.05, z + 0.06)
		bx("led", x, x + w7, hh - 0.25, hh - 0.1, z, z + 0.08)
		bx("beacon", x + w7 / 2.0 - 0.15, x + w7 / 2.0 + 0.15, hh, hh + 0.3, z - 4.6, z - 4.3)
		x += w7 + _rng.randf_range(2.0, 9.0)
	_chimney(13.5, -112.0, _hp(-112.0, 4.72), true)
	_commit(c, false)
	_era_nodes.append([c, 3, 4])
	(_mat("glass_tower") as ShaderMaterial).set_shader_parameter("lit_chance", 0.45)
	(_mat("glass_tower2") as ShaderMaterial).set_shader_parameter("lit_chance", 0.35)
	(_mat("glass_tower2") as ShaderMaterial).set_shader_parameter("lit_col", Color(0.85, 0.9, 1.0))
	(_mat("win_mid") as ShaderMaterial).set_shader_parameter("lit_chance", 0.5)


func _tower_crane(x: float, z: float, h: float) -> void:
	bx("crane_y", x - 0.35, x + 0.35, 0.0, h, z - 0.35, z + 0.35)
	bx("crane_y", x - 9.0, x + 4.0, h, h + 0.4, z - 0.25, z + 0.25)
	bx("far_dark", x + 2.6, x + 4.0, h - 0.6, h, z - 0.6, z + 0.6)
	bx("crane_y", x - 0.5, x + 0.5, h + 0.4, h + 0.9, z - 0.5, z + 0.5)
	bx("beacon", x - 0.1, x + 0.1, h + 0.9, h + 1.1, z - 0.1, z + 0.1)
	tube("metal", PackedVector3Array([Vector3(x - 6.0, h, z), Vector3(x - 6.0, h - 3.5, z)]), 0.03, 3)


# ======================================================================
# 水面、水里灯的倒影
# ======================================================================

func _water() -> void:
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = WATER
	_water_mat.set_shader_parameter("far_z", FAR)
	var pm := PlaneMesh.new()
	pm.size = Vector2(300.0, FAR * -1.0 + 20.0)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = _water_mat
	mi.position = Vector3(20.0, WY, (FAR + 20.0) / 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "water"
	add_child(mi)


## 一条倒影：灯脚在 z0（远），朝镜头拉到 z1
func _streak(st: SurfaceTool, x: float, z0: float, z1: float, w: float, col: Color) -> void:
	var y := WY + 0.015
	var seed := _rng.randf()
	var c := Color(col.r, col.g, col.b, seed)
	var p := [Vector3(x - w / 2.0, y, z0), Vector3(x + w / 2.0, y, z0), Vector3(x + w / 2.0, y, z1), Vector3(x - w / 2.0, y, z1)]
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(c)
		st.set_uv(uv[i])
		st.set_normal(Vector3.UP)
		st.add_vertex(p[i])


func _glint_node(st: SurfaceTool, parent: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = GLINT
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _glints() -> void:
	var warm := Color(1.0, 0.68, 0.36)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 对岸一排路灯：长长的倒影一直拉到河当中
	var x := -63.0
	while x < 150.0:
		_streak(st, x, FAR + 0.3, FAR + 30.0, 1.1, warm)
		x += 7.0
	# 桥灯、桥上那串灯：桥底下、桥后头的水里
	for p in BRIDGE_LAMPS:
		_streak(st, float(p), -16.0, 4.0, 0.7, Color(1.0, 0.75, 0.45))
	for p in LAMPS:
		_streak(st, float(p), -24.0, -9.0, 0.9, warm * 0.55)
	_streak(st, B0 - 0.45, -22.0, -6.0, 0.7, warm * 0.6)
	_glint_node(st, self)
	# 中年以后：对岸高楼的灯在水里一点点
	var n := Node3D.new()
	add_child(n)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	x = -60.0
	while x < 140.0:
		var col: Color = [Color(1.0, 0.8, 0.5), Color(0.6, 0.8, 1.0), Color(1.0, 0.95, 0.85), Color(1.0, 0.35, 0.25)][_rng.randi() % 4]
		_streak(st2, x, FAR + 0.3, FAR + _rng.randf_range(8.0, 18.0), _rng.randf_range(0.4, 0.9), col * 0.5)
		x += _rng.randf_range(1.5, 4.0)
	_glint_node(st2, n)
	_era_nodes.append([n, 3, 4])


# ======================================================================
# 年代、季节上的小东西
# ======================================================================

## 烤山芋的（小时候、少年）：一辆平板三轮上架个汽油桶改的炉子，炉口一圈红
func _yam_cart() -> void:
	_begin()
	var x := 9.98
	var z := -0.66
	# 除了炉口那圈红，都并进 goods 一批（顶点色上色）
	var wood_c := Color("#5d3e2b")
	var rub_c := Color("#1f1f22")
	var iron_c := Color("#55575a")
	bx("goods", x - 0.38, x + 0.38, 0.32, 0.36, z - 0.2, z + 0.2, wood_c)
	for wx in [x - 0.3, x + 0.3]:
		_hoop("goods", Vector3(float(wx), 0.17, z + 0.2), 0.16, 0.02, 12, rub_c)
		_hoop("goods", Vector3(float(wx), 0.17, z - 0.2), 0.16, 0.02, 12, rub_c)
	cyl("goods", Vector3(x, 0.36, z), 0.2, 0.2, 0.62, 12, Color("#5e3a2a"))
	cyl("ember", Vector3(x, 0.98, z), 0.17, 0.17, 0.01, 12)
	cyl("goods", Vector3(x, 0.98, z), 0.21, 0.21, 0.03, 12, iron_c)
	cyl("goods", Vector3(x + 0.12, 0.98, z - 0.08), 0.035, 0.035, 0.5, 6, iron_c)
	for k in 5:
		var a := TAU * float(k) / 5.0
		bc("goods", Vector3(x + cos(a) * 0.12, 1.02, z + sin(a) * 0.1), Vector3(0.12, 0.05, 0.06), a, 0.0, Color("#7a4a2c"))
	bx("goods", x - 0.36, x - 0.12, 0.36, 0.5, z - 0.12, z + 0.12, Color("#c8b48a"))
	var n := Node3D.new()
	add_child(n)
	_commit(n)
	_era_nodes.append([n, 0, 1])


func _seasonal() -> void:
	# 季节的小东西都用 goods 一批、顶点色上色（一个节点一两个 draw call）
	var skin := Color("#d6a487")
	var red := Color("#b53a30")
	var white := Color("#e4e9ec")
	var iron := Color("#55575a")
	# 夏天：河里游泳的，红白泳帽，身边一圈水花
	var sw := Node3D.new()
	add_child(sw)
	_begin()
	for p in [[6.5, -24.0], [7.6, -26.0], [14.8, -28.0], [21.5, -25.0], [-2.0, -30.0]]:
		var c := Vector3(float(p[0]), WY + 0.06, float(p[1]))
		_globe("goods", c, 0.12, 8, skin)
		_globe("goods", c + Vector3(0, 0.04, 0), 0.115, 8, red if _rng.randf() < 0.5 else white)
		bc("goods", c + Vector3(0.22, 0.02, 0.05), Vector3(0.32, 0.05, 0.07), 0.3, 0.0, skin)
		_hoop_flat("goods", c + Vector3(0, -0.04, 0), 0.32, 0.025, white)
		_hoop_flat("goods", c + Vector3(0.1, -0.05, 0), 0.6, 0.015, white)
	_commit(sw, false)
	_season_nodes.append([sw, ["summer"]])
	# 冬天：冰上拉冰车的，裹得圆滚滚
	var ice := Node3D.new()
	add_child(ice)
	_begin()
	for p in [[7.0, -22.0, 0], [8.1, -22.6, 1], [17.5, -30.0, 0], [18.3, -29.6, 1], [27.0, -20.0, 0]]:
		var b := Vector3(float(p[0]), WY, float(p[1]))
		var col: Color = [Color("#a8392f"), Color("#2f4f78"), Color("#3c6b4f"), Color("#d9a33a")][_rng.randi() % 4]
		if int(p[2]) == 1:
			# 坐在冰车上的小孩
			bx("goods", b.x - 0.3, b.x + 0.3, b.y + 0.06, b.y + 0.12, b.z - 0.22, b.z + 0.22, Color("#5d3e2b"))
			for rz in [-0.18, 0.18]:
				bx("goods", b.x - 0.34, b.x + 0.3, b.y, b.y + 0.06, b.z + float(rz) - 0.015, b.z + float(rz) + 0.015, iron)
			cyl("goods", b + Vector3(0, 0.12, 0), 0.17, 0.13, 0.42, 8, col)
			_globe("goods", b + Vector3(0, 0.66, 0), 0.11, 8, skin)
			_globe("goods", b + Vector3(0, 0.71, 0), 0.105, 8, Color.WHITE)
			_tc(PackedVector3Array([b + Vector3(0.1, 0.4, 0.15), b + Vector3(0.45, 0.0, 0.25)]), 0.012, iron)
		else:
			cyl("goods", b, 0.18, 0.2, 0.55, 8, Color("#2b2d33"))
			cyl("goods", b + Vector3(0, 0.55, 0), 0.22, 0.17, 0.55, 8, col)
			_globe("goods", b + Vector3(0, 1.25, 0), 0.12, 8, skin)
			_globe("goods", b + Vector3(0, 1.3, 0), 0.115, 8, Color.WHITE)
			_tc(PackedVector3Array([b + Vector3(0.15, 0.95, 0), b + Vector3(0.6, 0.55, 0.05), b + Vector3(0.75, 0.15, 0.05)]), 0.01, Color.WHITE)
	_commit(ice, false)
	_season_nodes.append([ice, ["winter"]])
	# 不是冬天：河上一条小船、远一点一条驳船（船舱的窗单独一批，夜里亮）
	var boat := Node3D.new()
	add_child(boat)
	_begin()
	var hull := Color("#33414b")
	var cream := Color("#e1dccd")
	var bz := -34.0
	bx("goods", 14.6, 18.2, WY - 0.2, WY + 0.45, bz - 0.7, bz + 0.7, hull)
	bc("goods", Vector3(18.2, WY + 0.12, bz), Vector3(0.99, 0.65, 0.99), PI / 4.0, 0.0, hull)
	bx("goods", 14.5, 18.4, WY + 0.42, WY + 0.5, bz - 0.75, bz + 0.75, cream)
	bx("goods", 15.0, 16.7, WY + 0.5, WY + 1.35, bz - 0.55, bz + 0.55, cream)
	bx("glass", 15.15, 16.55, WY + 0.9, WY + 1.2, bz + 0.55, bz + 0.57, Color(0.9, 0.2, 0.4))
	bx("goods", 14.9, 16.8, WY + 1.35, WY + 1.45, bz - 0.65, bz + 0.65, red)
	cyl("goods", Vector3(16.2, WY + 1.45, bz), 0.03, 0.02, 1.0, 5, iron)
	_hoop_flat("goods", Vector3(18.6, WY + 0.01, bz), 0.5, 0.03, white)
	var gz := -47.0
	bx("goods", 34.0, 46.0, WY - 0.2, WY + 0.6, gz - 1.6, gz + 1.6, Color("#2c3338"))
	bx("goods", 34.5, 36.5, WY + 0.6, WY + 1.8, gz - 1.2, gz + 1.2, Color("#58585b"))
	for k in 3:
		cyl("goods", Vector3(38.5 + k * 2.4, WY + 0.6, gz), 1.2, 0.3, 0.9, 8, Color("#8e8c86"))
	_commit(boat, false)
	_season_nodes.append([boat, ["spring", "summer", "autumn"]])
	# 春天：天上一只风筝，线拴在长椅扶手上
	var kite := Node3D.new()
	add_child(kite)
	_begin()
	var kc := Vector3(7.4, 4.5, -7.5)
	Kit.box_into(_tool("goods"), Vector3(0.42, 0.42, 0.015), Transform3D(Basis(Vector3.BACK, PI / 4.0), kc), red)
	Kit.box_into(_tool("goods"), Vector3(0.2, 0.2, 0.02), Transform3D(Basis(Vector3.BACK, PI / 4.0), kc), cream)
	var tail := PackedVector3Array()
	for i in 8:
		tail.append(kc + Vector3(-0.08 * i, -0.3 - 0.13 * i, 0.02 * sin(i)))
	_tc(tail, 0.01, red)
	var ln := PackedVector3Array()
	var a := Vector3(6.32, 0.58, -0.7)
	for i in 11:
		var t := float(i) / 10.0
		var p := a.lerp(kc, t)
		p.y -= 0.6 * 4.0 * t * (1.0 - t)
		ln.append(p)
	_tc(ln, 0.004, cream)
	_commit(kite, false)
	_season_nodes.append([kite, ["spring"]])


func set_season(season: String) -> void:
	super.set_season(season)
	for s in _season_nodes:
		(s[0] as Node3D).visible = (s[1] as Array).has(season)
	var g := {"spring": "#36442a", "summer": "#2d3a21", "autumn": "#4a4428", "winter": "#4a4536"}
	(_mat("grass") as ShaderMaterial).set_shader_parameter("col_a", Color(str(g.get(season, "#5f7a3c"))))


## 每帧：水面跟着天色走（stage3d 的天：白天蓝、傍晚橙紫、夜里深蓝）
func tick(delta: float, cam_x: float) -> void:
	super.tick(delta, cam_x)
	# set3d 按 13 米裁过一遍；这张图灯密（栏杆灯、桥灯、坡下映光），再按远近只留八盏
	var near: Array = []
	for l in lamps:
		if float(l[1]) > 0.0:
			near.append(l)
	if near.size() > MAX_LAMPS:
		near.sort_custom(func(a: Array, b: Array) -> bool:
			return absf((a[0] as Node3D).position.x - cam_x) < absf((b[0] as Node3D).position.x - cam_x))
		for i in range(MAX_LAMPS, near.size()):
			near[i][1] = 0.0
	if stage == null or _water_mat == null:
		return
	var sk: ProceduralSkyMaterial = stage.sky
	if sk == null:
		return
	_water_mat.set_shader_parameter("sky_hor", sk.sky_horizon_color)
	_water_mat.set_shader_parameter("sky_top", sk.sky_top_color)
