extends "res://scripts/world3d/set3d.gd"
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


const FZ := -1.25     ## 店面那堵墙的前脸
const CURB := 1.45    ## 马路牙子
const WIDTH := 40.0

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
	super.set_look(p_look)
	var i := maxi(0, LOOKS.find(look))
	if _labels.has("shop"):
		(_labels.shop as Label3D).text = "便利店" if i >= 3 else "小卖部"  # 和内容、2D 一致：一直是小卖部，到中年才换便利店
