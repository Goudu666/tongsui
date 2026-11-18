extends "res://scripts/world3d/set3d.gd"
## 中学（content/maps/middle.yaml，宽 28 米）的实时 3D：初中、高中、职专共用一个院。
## 从左到右：校门外一家小文具店（门口挂着本子、贴纸）、校门（贴瓷砖的大门柱、竖着的白底校牌、推拉铁门 / 后来的电动伸缩门）、
## 传达室（墙上一块光荣榜）、三层教学楼（一层剖开是教室：课桌、讲台、黑板、黑板报、日光灯；门边挂值日表）、
## 楼头接出来的一间小屋是广播站（话筒、调音台、录音机、磁带架，屋顶一个大喇叭朝着操场）、
## 操场（红色塑胶跑道、篮球架、小球门、主席台和旗杆，后头围墙和大杨树）、车棚（石棉瓦顶、铁架、一排排自行车，最里头一辆落灰的）。
##
## 镜头竖着只看得到地面以上约 4.9 米，所以细节都堆在一层；二三层只是外立面，楼顶的东西看不见，大喇叭放在广播站小屋顶上。
## 年代：老的推拉铁门 → 中年以后电动伸缩门、楼外贴新瓷砖；青年以后教室里有投影、车棚里电动车多起来。
## 夜里：傍晚到九点教室日光灯亮着（晚自习），车棚一盏灯，校门一盏灯。


const GZ := -1.3      ## 校门、文具店、传达室的前脸
const BZ := -0.45     ## 教学楼前脸（一层剖开，二三层的墙在这儿）
const BACK := -5.2    ## 教室后墙
const CURB := 2.9     ## 马路牙子
const B0 := 6.6       ## 教学楼左头
const B1 := 15.3      ## 教学楼右头（往右是广播站小屋）
const R1 := 18.2      ## 广播站小屋右头

var _facade_node: Node3D
var _class_lamps: Array = []


func build(sc: Dictionary, p_look: String, season: String) -> void:
	_rng.seed = 20261118
	look = p_look
	extra_mats = {
		"tile_white": [2, "#e3e0d6", "#b4afa4", Vector2(0.24, 0.12), 0.5, 0.5, 0.3, 0.05, 0.0],
		"school_plaster": [6, "#ddd6c4", "#000000", Vector2.ONE, 0.92, 0.6, 0.6, 0.08, 0.0],
		"tile_gate": [2, "#cbc3b2", "#8d8579", Vector2(0.15, 0.15), 0.45, 0.6, 0.3, 0.08, 0.0],
		"frame_blue": [0, "#3d6b94", "#000000", Vector2.ONE, 0.45, 0.0, 0.2, 0.0, 0.1],
		"wall_white": [6, "#ebe3cf", "#000000", Vector2.ONE, 0.93, 0.45, 0.35, 0.05, 0.0],
		"wall_pink": [6, "#d9bcaa", "#000000", Vector2.ONE, 0.92, 0.5, 0.35, 0.06, 0.0],
		"wain": [0, "#5f8a78", "#000000", Vector2.ONE, 0.42, 0.0, 0.3, 0.0, 0.0],
		"terrazzo": [2, "#a9a798", "#86847a", Vector2(0.6, 0.6), 0.45, 0.3, 0.3, 0.12, 0.0],
		"board": [6, "#2e4a3e", "#000000", Vector2.ONE, 0.9, 0.3, 0.55, 0.05, 0.0],
		"desk": [10, "#c39d6a", "#9c784c", Vector2(0.09, 1.0), 0.5, 0.6, 0.25, 0.1, 0.0],
		"track": [6, "#a4483b", "#000000", Vector2.ONE, 0.95, 1.3, 0.25, 0.08, 0.0],
		"turf": [6, "#5f7f45", "#000000", Vector2.ONE, 0.95, 1.5, 0.3, 0.16, 0.0],
		"asbestos": [5, "#b3aea1", "#000000", Vector2(0.11, 1.0), 0.95, 1.3, 0.85, 0.12, 0.0],
		"foam": [2, "#6d6860", "#4c4842", Vector2(0.09, 0.09), 0.98, 1.4, 0.0, 0.1, 0.0],
		"ftube": [0, "#f3f6f4", "#000000", Vector2.ONE, 0.3, 0.0, 0.0, 0.0, 0.0],
		"flag": [0, "#c3302a", "#000000", Vector2.ONE, 0.85, 0.0, 0.0, 0.0, 0.0],
		"dusty": [0, "#8a8377", "#000000", Vector2.ONE, 0.98, 0.0, 0.9, 0.1, 0.0],
	}
	extra_glow = {"ftube": [3.5, "#eef4ff"]}
	_begin()
	_ground()
	_stationery(-2.6, 1.6)
	_gate()
	_booth(4.6, 6.55)
	_classroom()
	_radio_room()
	_field()
	_shed(23.3, 28.6)
	_background()
	_commit(self)
	_facade()
	_trees()
	_era_bits()
	set_look(look)
	set_season(season)


# ======================================================================
# 地面：门口人行道方砖、马路牙子、马路；院里水泥地
# ======================================================================

func _ground() -> void:
	bx("pavers", -12.0, 40.0, -0.2, 0.0, GZ, CURB)
	bx("curb", -12.0, 40.0, -0.2, 0.0, CURB, CURB + 0.25)
	bx("asphalt", -12.0, 40.0, -0.4, -0.16, CURB + 0.25, 24.0)
	bx("paint", -12.0, 40.0, -0.16, -0.155, CURB + 0.6, CURB + 0.7)
	# 院里的水泥地（门里、楼后头）
	bx("concrete", -1.0, 30.0, -0.21, -0.01, -18.0, GZ)
	# 雨水箅子
	for wx in [5.4, 13.0]:
		bx("metal", wx, wx + 0.7, -0.005, 0.004, CURB - 0.45, CURB - 0.15)
	# 校门口的斑马线、三根矮隔离桩（上学放学车别往门口冲）
	for k in 6:
		bx("paint", 2.05 + k * 0.4, 2.3 + k * 0.4, -0.16, -0.152, CURB + 0.45, CURB + 4.8)
	for bxp in [2.4, 3.1, 3.8]:
		cyl("metal_white", Vector3(bxp, 0.0, 2.5), 0.065, 0.06, 0.5, 10)
		cyl("sign_red", Vector3(bxp, 0.36, 2.5), 0.068, 0.066, 0.07, 10)
	# 楼前一溜矮花池（不高过 0.6 米，别挡人）
	for p in [[8.2, 11.0], [12.0, 14.8]]:
		var a: float = p[0]
		var b: float = p[1]
		bx("concrete", a, b, 0.0, 0.32, 2.15, 2.6)
		bx("stone", a + 0.05, b - 0.05, 0.3, 0.34, 2.2, 2.55)
		_hedge(Vector3((a + b) / 2.0, 0.28, 2.37), b - a - 0.2, 0.2)


# ======================================================================
# 校门外的文具店：两层老楼，一层整面敞开，门口挂着本子、贴纸
# ======================================================================

func _stationery(x0: float, x1: float) -> void:
	var z := GZ
	var o0 := x0 + 0.5
	var o1 := x1 - 0.55
	wall("brick", x0, x1, 0.0, FLOOR_H, z, 0.3, [Rect2(o0, 0.0, o1 - o0, 2.45)])
	bx("plaster_grey", x0, x1, 0.0, 0.5, z, z + 0.02)
	_room(o0, o1, 0.0, 2.45, z, 3.0, "plaster", "concrete")
	_house_front("brick", x0, x1, FLOOR_H, 1, z, z - 9.0, "paint", 1.8, 1.05)
	# 卷帘门收在门头上
	bx("metal", o0 - 0.05, o1 + 0.05, 2.45, 2.72, z - 0.05, z + 0.12)
	for k in 4:
		bx("iron", o0, o1, 2.47 + k * 0.06, 2.5 + k * 0.06, z + 0.12, z + 0.13)
	# 店里：后墙一排木架子，一格格本子、文具盒；左边玻璃柜台
	var goods := [Color("#c9473c"), Color("#e2b33c"), Color("#3f7d68"), Color("#ece4cf"), Color("#4a6aa0"), Color("#d77a3a"), Color("#8b3c6b"), Color("#7fa6c9")]
	var rz := z - 2.6
	bx("wood", o0 + 0.15, o1 - 0.15, 0.0, 0.05, rz - 0.38, rz)
	for shelf in 4:
		var sy := 0.4 + shelf * 0.45
		bx("wood", o0 + 0.15, o1 - 0.15, sy, sy + 0.03, rz - 0.38, rz)
		var gx := o0 + 0.2
		while gx < o1 - 0.25:
			var gw := _rng.randf_range(0.03, 0.12)
			var gh := _rng.randf_range(0.18, 0.3)
			bx("goods", gx, gx + gw, sy + 0.03, sy + 0.03 + gh, rz - 0.3, rz - 0.06, goods[_rng.randi() % goods.size()])
			gx += gw + 0.012
	for sx in [o0 + 0.15, o1 - 0.15]:
		bx("wood", sx - 0.03, sx + 0.03, 0.0, 2.2, rz - 0.38, rz)
	# 玻璃柜台：里头一排排笔
	bx("wood", o0 + 0.3, o0 + 2.1, 0.0, 0.45, z - 1.9, z - 1.4)
	bx("shopglass", o0 + 0.3, o0 + 2.1, 0.45, 0.95, z - 1.42, z - 1.4)
	bx("chrome", o0 + 0.28, o0 + 2.12, 0.95, 0.98, z - 1.92, z - 1.38)
	for k in 14:
		bx("goods", o0 + 0.38 + k * 0.12, o0 + 0.42 + k * 0.12, 0.62, 0.78, z - 1.6, z - 1.48, goods[k % goods.size()])
	# 门口一张摊桌：文具盒、一摞练习本、笔筒
	var tx0 := -0.15
	var tx1 := 0.95
	bx("wood_light", tx0, tx1, 0.72, 0.76, -1.05, -0.6)
	for lx in [tx0 + 0.05, tx1 - 0.08]:
		for lz in [-1.0, -0.66]:
			bx("metal", lx, lx + 0.03, 0.0, 0.72, lz, lz + 0.03)
	var bxx := tx0 + 0.08
	while bxx < tx1 - 0.2:
		var h := _rng.randf_range(0.03, 0.12)
		bx("goods", bxx, bxx + 0.2, 0.76, 0.76 + h, -0.98 + _rng.randf() * 0.05, -0.7, goods[_rng.randi() % goods.size()])
		bx("paper", bxx + 0.01, bxx + 0.19, 0.76 + h, 0.765 + h, -0.96, -0.72)
		bxx += 0.24
	cyl("metal", Vector3(tx1 - 0.1, 0.76, -0.82), 0.05, 0.05, 0.13, 8)
	for k in 5:
		tube("goods", PackedVector3Array([Vector3(tx1 - 0.12 + k * 0.01, 0.8, -0.82), Vector3(tx1 - 0.14 + k * 0.02, 0.98, -0.83 + k * 0.01)]), 0.006, 4)
	# 门头上拉一根铁丝，夹子夹着本子、贴纸、明信片往下垂
	tube("metal", PackedVector3Array([Vector3(o0, 2.32, z + 0.16), Vector3(o1, 2.32, z + 0.16)]), 0.006, 4)
	var hx := o0 + 0.15
	while hx < o1 - 0.2:
		var w := _rng.randf_range(0.14, 0.22)
		var hh := _rng.randf_range(0.22, 0.34)
		bx("metal", hx + w / 2.0 - 0.015, hx + w / 2.0 + 0.015, 2.27, 2.34, z + 0.15, z + 0.18)
		bx("goods", hx, hx + w, 2.28 - hh, 2.28, z + 0.15, z + 0.16, goods[_rng.randi() % goods.size()])
		if _rng.randf() < 0.5:
			bx("paper", hx + 0.02, hx + w - 0.02, 2.28 - hh * 0.7, 2.28 - hh * 0.4, z + 0.16, z + 0.165)
		hx += w + 0.05
	# 招牌
	bx("sign_red", o0 + 0.6, o1 - 0.6, 2.8, 3.06, z + 0.0, z + 0.07)
	_label("文 具", Vector3((o0 + o1) / 2.0, 2.93, z + 0.075), 0.009, Color("#f8f1e2"))
	_shop_light(Vector3(-0.4, 2.2, z - 1.4), 0.8)


## 楼的上半截外立面（不像 upper_floors 那样把一层也填实，一层留给剖开的屋子）
func _house_front(key: String, x0: float, x1: float, y0: float, floors: int, z: float, back: float, frame: String, pitch: float, win_w: float) -> void:
	var holes: Array = []
	var top := y0 + floors * FLOOR_H
	for f in floors:
		var fy := y0 + f * FLOOR_H
		var n := int(floor((x1 - x0 - 0.5) / pitch))
		var start := x0 + (x1 - x0 - n * pitch) / 2.0 + (pitch - win_w) / 2.0
		for i in n:
			var wx := start + i * pitch
			holes.append(Rect2(wx, fy + 0.85, win_w, 1.5))
			window(wx, fy + 0.85, win_w, 1.5, z, frame)
		bx("concrete", x0, x1, fy - 0.07, fy + 0.07, z, z + 0.05)
	wall(key, x0, x1, y0, top + 0.6, z, 0.3, holes)
	bx("concrete", x0 - 0.05, x1 + 0.05, top + 0.6, top + 0.7, z - 0.32, z + 0.06)
	bx(key, x0, x1, y0, top, back, z - 0.3)
	bx("tar", x0, x1, top - 0.05, top + 0.02, back, z - 0.3)


# ======================================================================
# 校门：两根贴瓷砖的大门柱，竖着的白底黑字校牌；门里一条水泥路往院里去
# ======================================================================

func _gate() -> void:
	var z := GZ
	for p in [[1.65, 2.2], [4.0, 4.55]]:
		var a: float = p[0]
		var b: float = p[1]
		bx("stone", a - 0.05, b + 0.05, 0.0, 0.28, z - 0.4, z + 0.35)
		bx("tile_gate", a, b, 0.28, 2.95, z - 0.35, z + 0.3)
		bx("concrete", a - 0.08, b + 0.08, 2.95, 3.08, z - 0.43, z + 0.38)
		bx("concrete", a + 0.04, b - 0.04, 3.08, 3.2, z - 0.35, z + 0.3)
	# 校牌：白底，挂在左边门柱上
	bx("metal_white", 1.74, 2.11, 0.7, 2.7, z + 0.3, z + 0.33)
	bx("metal", 1.72, 2.13, 0.68, 0.7, z + 0.3, z + 0.34)
	_label("河\n畔\n中\n学", Vector3(1.925, 1.7, z + 0.335), 0.0085, Color("#25242a"))
	# 地上的门轨
	bx("metal", 2.2, 4.0, 0.0, 0.012, z - 0.06, z + 0.06)
	# 门里：水泥路往后去，两边冬青
	bx("concrete", 2.2, 4.0, -0.2, 0.002, -16.0, z - 0.35)
	for hx in [2.4, 3.8]:
		_hedge(Vector3(hx, 0.0, -6.0), 0.5, 0.55)
	# 门里远处一排矮平房（实验楼），把门洞里填上
	bx("school_plaster", -1.0, 6.6, 0.0, 3.4, -18.0, -14.0)
	bx("concrete", -1.05, 6.65, 3.4, 3.55, -18.05, -13.95)
	for k in 4:
		var wx := -0.4 + k * 1.75
		bx("glass", wx, wx + 1.1, 1.0, 2.5, -13.99, -13.97, Color(_rng.randf(), _rng.randf(), _rng.randf()))
		bx("frame_blue", wx - 0.05, wx + 1.15, 0.95, 1.0, -13.98, -13.92)
	_lamp_wall(Vector3(4.27, 2.65, z + 0.45))


## 传达室：一间小平房，推拉窗，墙上一块光荣榜（红榜）
func _booth(x0: float, x1: float) -> void:
	var z := GZ + 0.1
	var win := Rect2(x0 + 0.12, 1.0, 0.58, 0.85)
	wall("wall_white", x0, x1, 0.0, 2.75, z, 0.25, [win])
	bx("wain", x0, x1, 0.0, 0.9, z, z + 0.015)
	bx("wall_white", x0, x1, 0.0, 2.75, -4.2, z - 0.25)
	bx("concrete", x0 - 0.08, x1 + 0.12, 2.75, 2.9, -4.25, z + 0.15)
	bx("glass", win.position.x, win.end.x, win.position.y, win.end.y, z - 0.12, z - 0.1, Color(0.2, 0.3, 0.9))
	for fx in [win.position.x, win.position.x + win.size.x / 2.0 - 0.02, win.end.x - 0.04]:
		bx("frame_blue", fx, fx + 0.04, win.position.y, win.end.y, z - 0.1, z - 0.06)
	bx("frame_blue", win.position.x, win.end.x, win.position.y - 0.04, win.position.y, z - 0.1, z - 0.06)
	bx("frame_blue", win.position.x, win.end.x, win.end.y, win.end.y + 0.04, z - 0.1, z - 0.06)
	bx("concrete", win.position.x - 0.05, win.end.x + 0.05, 0.93, 1.0, z - 0.1, z + 0.12)
	bx("metal_white", x0 + 0.16, x0 + 0.66, 2.08, 2.26, z, z + 0.02)
	_label("传达室", Vector3(x0 + 0.41, 2.17, z + 0.025), 0.0026, Color("#2b2a33"))
	# 光荣榜：红底，一行行黄纸名字
	var rx := 6.0
	bx("wood_red", rx - 0.42, rx + 0.42, 0.95, 1.85, z, z + 0.04)
	bx("metal", rx - 0.45, rx + 0.45, 1.85, 1.9, z, z + 0.06)
	_label("光荣榜", Vector3(rx, 1.76, z + 0.045), 0.0028, Color("#f2d27a"))
	for row in 5:
		for col in 2:
			bx("paper", rx - 0.36 + col * 0.37, rx - 0.04 + col * 0.37, 1.05 + row * 0.12, 1.12 + row * 0.12, z + 0.04, z + 0.045)


# ======================================================================
# 教学楼一层：左头楼门（门边挂值日表），剖开的教室
# ======================================================================

func _classroom() -> void:
	var x0 := 8.0
	var x1 := B1 - 0.25
	# 地面、后墙、隔墙、天花
	bx("terrazzo", B0, R1, -0.02, 0.006, BACK, BZ + 0.05)
	bx("wall_white", x0, x1, 0.0, 3.0, BACK - 0.25, BACK)
	bx("wain", x0, x1, 0.0, 1.05, BACK, BACK + 0.015)
	bx("wall_white", x0 - 0.2, x0, 0.0, 3.0, BACK, BZ - 0.1)
	bx("wain", x0, x0 + 0.015, 0.0, 1.05, BACK, BZ - 0.1)
	bx("concrete", B0, B1, 2.98, 3.12, -10.0, BZ - 0.1)
	# 楼门那段：实墙、门洞里是楼梯间（暗）、门口三级台阶
	bx("wall_white", B0, x0, 0.0, 3.0, -10.0, BZ - 0.3)
	bx("sign_ink", 6.98, 7.78, 0.0, 2.35, BZ - 0.31, BZ - 0.29)
	for k in 6:
		bx("concrete", 7.0, 7.76, 0.18 + k * 0.17, 0.2 + k * 0.17, BZ - 1.0 - k * 0.25, BZ - 0.31)
	for k in 2:
		bx("concrete", 6.9, 7.86, 0.0, 0.15 - k * 0.07, BZ - 0.3, BZ + 0.05 + (1 - k) * 0.25)
	# 值日表：走廊墙上一张格子表，旁边一个班牌
	bx("wood_light", 6.66, 6.96, 1.15, 1.75, BZ - 0.3, BZ - 0.27)
	bx("paper", 6.68, 6.94, 1.17, 1.73, BZ - 0.27, BZ - 0.265)
	for r in 6:
		bx("sign_ink", 6.69, 6.93, 1.25 + r * 0.08, 1.256 + r * 0.08, BZ - 0.265, BZ - 0.262)
	bx("sign_ink", 6.79, 6.795, 1.19, 1.66, BZ - 0.265, BZ - 0.262)
	_label("值日", Vector3(6.81, 1.69, BZ - 0.26), 0.0016, Color("#b53a30"))
	# 后墙：讲台、黑板、粉笔槽；右边黑板报；墙上一个钟、一个广播小喇叭
	bx("wood", 8.3, 12.3, 0.0, 0.2, BACK, BACK + 1.0)
	bx("board", 8.7, 11.9, 0.95, 2.2, BACK, BACK + 0.03)
	for fx in [[8.65, 8.7], [11.9, 11.95]]:
		bx("chrome", fx[0], fx[1], 0.95, 2.2, BACK, BACK + 0.04)
	bx("chrome", 8.65, 11.95, 2.2, 2.24, BACK, BACK + 0.04)
	bx("chrome", 8.65, 11.95, 0.9, 0.95, BACK, BACK + 0.09)
	# 黑板上没擦干净的粉笔字（几道白道）、右上角一行值日生
	for k in 4:
		var lx := 8.95 + _rng.randf() * 0.3
		bx("paper", lx, lx + _rng.randf_range(0.9, 1.8), 1.85 - k * 0.2, 1.865 - k * 0.2, BACK + 0.03, BACK + 0.033)
	bx("paper", 11.35, 11.75, 1.95, 1.96, BACK + 0.03, BACK + 0.033)
	bx("paper", 11.35, 11.65, 1.88, 1.89, BACK + 0.03, BACK + 0.033)
	# 讲桌
	bx("desk", 9.8, 10.8, 0.2, 1.02, BACK + 0.35, BACK + 0.85)
	bx("desk", 9.75, 10.85, 1.02, 1.05, BACK + 0.3, BACK + 0.9)
	bx("goods", 10.0, 10.3, 1.05, 1.1, BACK + 0.45, BACK + 0.7, Color("#c9473c"))
	cyl("metal_white", Vector3(10.55, 1.05, BACK + 0.6), 0.04, 0.045, 0.12, 8)
	# 黑板报：深色底子，贴着几块彩纸、画着花边
	bx("board", 12.5, 14.8, 0.95, 2.25, BACK, BACK + 0.03)
	var bcols := [Color("#d9485f"), Color("#e8c84a"), Color("#6fa3c9"), Color("#e8e2d4"), Color("#7fb07a")]
	for k in 5:
		var px := 12.62 + k * 0.43
		var py := 1.05 + (k % 2) * 0.55
		bx("goods", px, px + 0.36, py, py + _rng.randf_range(0.38, 0.5), BACK + 0.03, BACK + 0.034, bcols[k])
	for k in 12:
		bx("goods", 12.55 + k * 0.19, 12.65 + k * 0.19, 2.12, 2.2, BACK + 0.03, BACK + 0.034, bcols[k % 5])
	tube("metal_white", PackedVector3Array([Vector3(10.3, 2.48, BACK), Vector3(10.3, 2.48, BACK + 0.05)]), 0.15, 16)
	bx("sign_ink", 10.29, 10.31, 2.42, 2.56, BACK + 0.05, BACK + 0.055)
	bx("wood", 13.4, 13.9, 2.38, 2.75, BACK, BACK + 0.15)
	bx("rubber", 13.44, 13.86, 2.42, 2.71, BACK + 0.15, BACK + 0.155)
	# 课桌：三排四列，两人一张，椅子在朝镜头这边（学生面朝黑板）
	var cols := [9.0, 10.9, 12.8, 14.45]
	var rows := [-1.0, -2.05, -3.1]
	var bag := [Color("#3b5d8a"), Color("#a33a33"), Color("#2e2e33"), Color("#4f7a5a"), Color("#c7883a")]
	for rz in rows:
		for cx in cols:
			var j := _rng.randf_range(-0.05, 0.05)
			_desk(Vector3(cx + j, 0.0, rz), bag[_rng.randi() % bag.size()])
	# 天花上的日光灯：三排
	for lz in [-1.6, -3.0, -4.3]:
		for lx in [9.3, 11.6, 13.9]:
			bx("metal_white", lx - 0.65, lx + 0.65, 2.9, 2.98, lz - 0.07, lz + 0.07)
			bx("ftube", lx - 0.6, lx + 0.6, 2.87, 2.9, lz - 0.025, lz + 0.025)
	# 墙角值日的家什：笤帚、簸箕、铁皮水桶
	tube("bamboo", PackedVector3Array([Vector3(14.92, 0.05, -4.7), Vector3(14.98, 1.25, -4.95)]), 0.012, 5)
	bc("bamboo", Vector3(14.9, 0.18, -4.68), Vector3(0.24, 0.32, 0.06), 0.0, 0.08)
	bc("metal_green", Vector3(14.6, 0.04, -4.8), Vector3(0.3, 0.06, 0.26), 0.3)
	cyl("chrome", Vector3(14.35, 0.0, -4.55), 0.13, 0.15, 0.3, 12)
	# 吊扇
	for fx in [10.4, 13.0]:
		cyl("metal_white", Vector3(fx, 2.55, -2.4), 0.012, 0.012, 0.45, 5)
		cyl("metal_white", Vector3(fx, 2.5, -2.4), 0.09, 0.09, 0.08, 10)
		for a in 3:
			bc("metal_white", Vector3(fx, 2.54, -2.4) + Vector3(cos(a * TAU / 3.0), 0, sin(a * TAU / 3.0)) * 0.42, Vector3(0.7, 0.01, 0.1), -a * TAU / 3.0)
	for lx in [9.6, 13.4]:
		var l := _class_lamp(Vector3(lx, 2.6, -2.0))
		_class_lamps.append(l)


## 一张两人课桌 + 两把椅子，at 是桌子中心（地面）
func _desk(at: Vector3, bag_col: Color) -> void:
	var w := 1.1
	var d := 0.45
	bx("desk", at.x - w / 2.0, at.x + w / 2.0, 0.7, 0.73, at.z - d / 2.0, at.z + d / 2.0)
	bx("desk", at.x - w / 2.0 + 0.02, at.x + w / 2.0 - 0.02, 0.56, 0.58, at.z - d / 2.0 + 0.02, at.z + d / 2.0 - 0.05)
	for dx in [-w / 2.0 + 0.03, w / 2.0 - 0.06]:
		for dz in [-d / 2.0 + 0.02, d / 2.0 - 0.05]:
			bx("frame_blue", at.x + dx, at.x + dx + 0.03, 0.0, 0.7, at.z + dz, at.z + dz + 0.03)
	# 桌上的书、文具盒
	bx("goods", at.x - 0.42, at.x - 0.12, 0.73, 0.76 + _rng.randf() * 0.05, at.z - 0.12, at.z + 0.1, Color("#e8e2d4"))
	bx("goods", at.x + 0.1, at.x + 0.32, 0.73, 0.75, at.z - 0.05, at.z + 0.12, [Color("#4a6aa0"), Color("#c9473c"), Color("#e2b33c")][_rng.randi() % 3])
	# 椅子：朝镜头那边
	for sx in [at.x - 0.27, at.x + 0.27]:
		var cz := at.z + d / 2.0 + 0.2
		bx("desk", sx - 0.19, sx + 0.19, 0.42, 0.45, cz - 0.17, cz + 0.17)
		bx("desk", sx - 0.19, sx + 0.19, 0.62, 0.82, cz + 0.15, cz + 0.17)
		for dx in [-0.17, 0.15]:
			for dz in [-0.15, 0.13]:
				bx("frame_blue", sx + dx, sx + dx + 0.025, 0.0, 0.42 if dz < 0.0 else 0.82, cz + dz, cz + dz + 0.025)
	# 一个书包挂在桌边
	bc("goods", Vector3(at.x + w / 2.0 + 0.04, 0.5, at.z), Vector3(0.1, 0.32, 0.26), 0.0, 0.0, bag_col)


func _class_lamp(at: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = Color(0.96, 0.98, 1.0)
	l.omni_range = 5.5
	l.omni_attenuation = 1.0
	l.light_energy = 1.05
	l.set_meta("energy", 1.05)
	l.set_meta("day", 0.35)
	l.shadow_enabled = false
	l.visible = false
	add_child(l)
	lamps.append([l, 1.0])
	return l


# ======================================================================
# 广播站：楼头接出来的一间小屋，桌上话筒、调音台、录音机，后墙磁带架；屋顶一个大喇叭
# ======================================================================

func _radio_room() -> void:
	var x0 := B1 + 0.05
	var x1 := R1 - 0.2
	var rb := -3.6
	var top := 3.15
	bx("wall_pink", x0, x1, 0.0, top, rb - 0.2, rb)
	bx("wall_pink", x0 - 0.3, x0, 0.0, top, rb, BZ - 0.1)
	bx("wall_pink", x1, x1 + 0.2, 0.0, top, rb - 0.2, BZ - 0.1)
	bx("wain", x0, x1, 0.0, 0.8, rb, rb + 0.015)
	# 屋顶：平顶、压顶、女儿墙
	bx("concrete", B1 - 0.1, R1, top, top + 0.18, rb - 0.2, BZ + 0.05)
	bx("school_plaster", B1 - 0.1, R1, top + 0.18, top + 0.55, BZ - 0.1, BZ + 0.05)
	bx("concrete", B1 - 0.15, R1 + 0.05, top + 0.55, top + 0.62, BZ - 0.12, BZ + 0.08)
	bx("school_plaster", R1 - 0.15, R1, top + 0.18, top + 0.55, rb - 0.2, BZ)
	# 门口两边的柱子
	for p in [[B1 - 0.05, B1 + 0.2], [R1 - 0.25, R1]]:
		bx("tile_gate", p[0], p[1], 0.0, top, BZ - 0.3, BZ + 0.02)
	# 后墙：隔音泡沫板、「广播站」红牌、磁带架
	bx("foam", x0 + 0.15, x0 + 1.4, 1.0, 2.4, rb, rb + 0.04)
	bx("sign_red", 16.2, 17.4, 2.55, 2.85, rb, rb + 0.04)
	_label("广播站", Vector3(16.8, 2.7, rb + 0.045), 0.0042, Color("#f8f1e2"))
	var sx0 := x1 - 1.05
	bx("wood", sx0, x1 - 0.1, 0.9, 2.3, rb, rb + 0.22)
	var tape := [Color("#2b2a33"), Color("#e8e2d4"), Color("#c9473c"), Color("#4a6aa0"), Color("#e2b33c")]
	for shelf in 4:
		var sy := 0.95 + shelf * 0.34
		bx("wood", sx0, x1 - 0.1, sy, sy + 0.025, rb + 0.0, rb + 0.24)
		var tx := sx0 + 0.04
		while tx < x1 - 0.16:
			bx("goods", tx, tx + 0.018, sy + 0.025, sy + 0.135, rb + 0.06, rb + 0.2, tape[_rng.randi() % tape.size()])
			tx += 0.024
	# 桌子：话筒、调音台、录音机、耳机
	var dx := 16.8
	var dz := -0.95
	bx("desk", dx - 0.7, dx + 0.7, 0.74, 0.77, dz - 0.35, dz + 0.32)
	bx("wood", dx - 0.68, dx + 0.68, 0.06, 0.74, dz - 0.33, dz - 0.3)
	for lx in [dx - 0.66, dx + 0.62]:
		bx("wood", lx, lx + 0.04, 0.0, 0.74, dz - 0.33, dz + 0.3)
	# 调音台：斜面，一排排推子、旋钮
	bc("metal", Vector3(dx + 0.2, 0.83, dz - 0.05), Vector3(0.5, 0.06, 0.34), 0.0, deg_to_rad(-10.0))
	for k in 8:
		bx("metal_white", dx - 0.03 + k * 0.055, dx - 0.015 + k * 0.055, 0.87, 0.885, dz - 0.12, dz + 0.02)
		bx("sign_red" if k % 3 == 0 else "chrome", dx - 0.03 + k * 0.055, dx - 0.01 + k * 0.055, 0.86, 0.9, dz - 0.18, dz - 0.16)
	# 录音机（双卡）
	bx("metal", dx - 0.6, dx - 0.12, 0.77, 0.95, dz - 0.25, dz - 0.05)
	bx("chrome", dx - 0.56, dx - 0.4, 0.8, 0.92, dz - 0.05, dz - 0.04)
	bx("chrome", dx - 0.32, dx - 0.16, 0.8, 0.92, dz - 0.05, dz - 0.04)
	bx("metal", dx - 0.45, dx - 0.27, 0.95, 0.97, dz - 0.2, dz - 0.1)
	# 话筒：小底座、鹅颈、话筒头裹着海绵
	cyl("metal", Vector3(dx - 0.05, 0.77, dz + 0.12), 0.07, 0.06, 0.03, 10)
	tube("chrome", PackedVector3Array([Vector3(dx - 0.05, 0.8, dz + 0.12), Vector3(dx - 0.05, 1.0, dz + 0.14), Vector3(dx - 0.08, 1.1, dz + 0.24)]), 0.008, 5)
	var mic := MeshInstance3D.new()
	mic.mesh = Kit.ellipsoid(Vector3(0.04, 0.045, 0.04), 10, 8)
	mic.material_override = _mat("rubber")
	mic.position = Vector3(dx - 0.085, 1.13, dz + 0.27)
	add_child(mic)
	# 椅子在桌子后头（播音员面朝外坐）
	bx("desk", dx - 0.2, dx + 0.2, 0.44, 0.47, dz - 0.85, dz - 0.5)
	bx("desk", dx - 0.2, dx + 0.2, 0.47, 0.9, dz - 0.88, dz - 0.85)
	for k in 4:
		bx("metal", dx - 0.18 + (k % 2) * 0.33, dx - 0.15 + (k % 2) * 0.33, 0.0, 0.44, dz - 0.84 + (k / 2) * 0.3, dz - 0.81 + (k / 2) * 0.3)
	# 墙上一盏小灯
	_add_lamp(Vector3(16.8, 2.6, -1.8), Color(1.0, 0.82, 0.6), 4.5, 1.1, 0.0)
	bx("lamp", 16.6, 17.0, 2.95, 3.0, -2.0, -1.6)
	# 屋顶：铁杆上一个大喇叭，朝着操场
	var hp := Vector3(17.45, top + 0.18 - 0.6, -1.4)
	cyl("metal", hp + Vector3(0, 0.6, 0), 0.035, 0.03, 0.9, 6)
	for a in [-0.4, 0.35]:
		var mouth := hp + Vector3(0.75, 1.45 + a * 0.3, a)
		tube("metal_white", PackedVector3Array([hp + Vector3(0.05, 1.35, 0), mouth]), 0.05, 12, 0.3)
		bx("metal", hp.x - 0.03, hp.x + 0.08, hp.y + 1.3, hp.y + 1.4, hp.z - 0.05 + a * 0.3, hp.z + 0.05 + a * 0.3)
	_wire(hp + Vector3(0, 1.2, 0), Vector3(B1 + 0.2, top + 0.6, -1.0), 0.15)


# ======================================================================
# 操场：红塑胶跑道、草皮、篮球架、小球门、主席台和旗杆，后头围墙
# ======================================================================

func _field() -> void:
	var x0 := R1
	var x1 := 23.3
	bx("track", x0, x1, -0.02, 0.012, -2.4, 1.25)
	for lz in [-1.6, -0.8, 0.4]:
		bx("paint", x0, x1, 0.012, 0.016, lz - 0.025, lz + 0.025)
	bx("paint", x0 + 0.9, x0 + 0.96, 0.012, 0.016, -2.4, 1.25)
	bx("curb", x0, x1, -0.02, 0.05, -2.55, -2.4)
	bx("metal_white", x0, x1, -0.02, 0.03, 1.25, 1.33)
	bx("metal_white", x1 - 0.06, x1, -0.02, 0.03, -2.4, 1.33)
	bx("turf", x0 - 0.5, 31.0, -0.02, 0.008, -16.5, -2.55)
	# 草皮上的白线：中线、禁区
	bx("paint", x0, 31.0, 0.008, 0.012, -9.05, -8.98)
	# 篮球架：靠楼这头，篮板朝镜头
	var bxp := 19.1
	bx("frame_blue", bxp - 0.08, bxp + 0.08, 0.0, 3.3, -3.3, -3.14)
	tube("frame_blue", PackedVector3Array([Vector3(bxp, 3.2, -3.2), Vector3(bxp, 3.25, -2.3)]), 0.05, 6)
	bx("metal_white", bxp - 0.6, bxp + 0.6, 2.85, 3.6, -2.32, -2.28)
	bx("sign_red", bxp - 0.2, bxp + 0.2, 3.0, 3.2, -2.28, -2.27)
	_hoop(Vector3(bxp, 3.05, -2.06), 0.22)
	# 小球门：白漆管子、网
	var gx0 := 20.4
	var gx1 := 23.0
	var gz := -7.5
	for gxx in [gx0, gx1]:
		cyl("metal_white", Vector3(gxx, 0, gz), 0.045, 0.045, 1.8, 8)
		tube("metal_white", PackedVector3Array([Vector3(gxx, 1.8, gz), Vector3(gxx, 1.5, gz - 0.9), Vector3(gxx, 0.0, gz - 1.1)]), 0.02, 5)
	tube("metal_white", PackedVector3Array([Vector3(gx0, 1.8, gz), Vector3(gx1, 1.8, gz)]), 0.045, 8)
	for k in 13:
		var nx := gx0 + k * (gx1 - gx0) / 12.0
		tube("paper", PackedVector3Array([Vector3(nx, 1.78, gz), Vector3(nx, 1.5, gz - 0.88), Vector3(nx, 0.0, gz - 1.08)]), 0.004, 3)
	for k in 6:
		var ny := 0.25 + k * 0.28
		tube("paper", PackedVector3Array([Vector3(gx0, ny, gz - 1.08 + ny * 0.12), Vector3(gx1, ny, gz - 1.08 + ny * 0.12)]), 0.004, 3)
	_ball(Vector3(21.3, 0.11, -3.6))
	# 主席台：水泥台子、台阶、后墙一块红底
	var tz := -13.0
	bx("concrete", 18.6, 23.6, 0.0, 1.0, tz - 2.0, tz)
	for k in 4:
		bx("concrete", 20.4, 21.8, 0.0, 0.25 * (k + 1), tz + 0.9 - k * 0.3, tz + 1.2 - k * 0.3)
	bx("school_plaster", 18.6, 23.6, 1.0, 3.2, tz - 2.2, tz - 1.9)
	bx("sign_red", 19.2, 23.0, 2.0, 2.9, tz - 1.9, tz - 1.87)
	bx("metal_white", 18.8, 23.4, 1.0, 1.95, tz - 0.05, tz)
	for k in 12:
		bx("metal", 18.8 + k * 0.4, 18.83 + k * 0.4, 1.0, 1.9, tz - 0.06, tz + 0.02)
	# 旗杆：台子前头，顶上一面红旗
	var fz := tz + 1.8
	var fpx := 22.4
	bx("stone", fpx - 0.4, fpx + 0.4, 0.0, 0.3, fz - 0.4, fz + 0.4)
	cyl("chrome", Vector3(fpx, 0.3, fz), 0.05, 0.03, 4.8, 10)
	cyl("chrome", Vector3(fpx, 5.1, fz), 0.05, 0.05, 0.08, 8)
	for k in 5:
		bc("flag", Vector3(fpx + 0.12 + k * 0.2, 4.72 + sin(k * 1.2) * 0.03, fz + sin(k * 0.9) * 0.05), Vector3(0.21, 0.62, 0.02), sin(k * 0.9 + 0.5) * 0.25)
	# 围墙：下半截砖、上头铁栏杆
	var wz := -16.5
	bx("brick", R1 - 0.5, 31.0, 0.0, 0.9, wz - 0.24, wz)
	bx("concrete", R1 - 0.55, 31.0, 0.9, 0.98, wz - 0.28, wz + 0.04)
	var px := R1 - 0.3
	while px < 31.0:
		bx("metal_green", px, px + 0.025, 0.98, 2.2, wz - 0.13, wz - 0.1)
		px += 0.16
	for gy in [1.2, 2.1]:
		bx("metal_green", R1 - 0.5, 31.0, gy, gy + 0.03, wz - 0.14, wz - 0.09)


func _hoop(c: Vector3, r: float) -> void:
	var pts := PackedVector3Array()
	for i in 17:
		var a := TAU * float(i) / 16.0
		pts.append(c + Vector3(cos(a) * r, 0, sin(a) * r))
	tube("sign_red", pts, 0.012, 5)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var top := c + Vector3(cos(a) * r, 0, sin(a) * r)
		tube("paper", PackedVector3Array([top, c + Vector3(cos(a) * r * 0.6, -0.4, sin(a) * r * 0.6)]), 0.004, 3)


func _ball(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.ellipsoid(Vector3(0.11, 0.11, 0.11), 12, 8)
	mi.material_override = _mat("metal_white")
	mi.position = at
	add_child(mi)


# ======================================================================
# 车棚：铁柱子、斜的石棉瓦顶（波纹），后墙是砖；看车棚阿姨的小桌和凳子
# ======================================================================

func _shed(x0: float, x1: float) -> void:
	var fz := -0.55
	var bz := -3.9
	bx("concrete", x0, x1 + 3.0, -0.2, 0.004, bz, GZ + 0.8)
	bx("curb", x0, x0 + 0.06, 0.0, 0.08, bz, -0.4)
	# 后墙、右头墙
	bx("brick", x0, x1, 0.0, 2.6, bz - 0.25, bz)
	bx("brick", x1, x1 + 0.25, 0.0, 2.9, bz - 0.25, fz + 0.3)
	bx("concrete", x0, x1 + 0.25, 2.6, 2.68, bz - 0.28, bz + 0.03)
	# 柱子：前一排、后一排
	var px := x0 + 0.2
	while px < x1 + 0.1:
		bx("metal_green", px - 0.04, px + 0.04, 0.0, 2.35, fz - 0.04, fz + 0.04)
		bx("metal_green", px - 0.04, px + 0.04, 0.0, 2.7, bz + 0.1, bz + 0.18)
		px += 2.6
	bx("metal_green", x0, x1, 2.3, 2.4, fz - 0.05, fz + 0.05)
	bx("metal_green", x0, x1, 2.65, 2.75, bz + 0.08, bz + 0.2)
	# 石棉瓦：斜着搭，前低后高，往前挑出一点
	var ang := atan2(0.4, fz - bz)
	var rlen := Vector2(bz - fz, 0.4).length() + 0.7
	var mid := Vector3((x0 + x1) / 2.0, 2.54, (fz + bz) / 2.0 + 0.3)
	bc("asbestos", mid, Vector3(x1 - x0 + 0.3, 0.03, rlen), 0.0, ang)
	# 前沿一排波峰（看得出是波纹瓦）
	var wx := x0 - 0.15
	while wx < x1 + 0.15:
		cyl("asbestos", Vector3(wx, 2.36, fz + 0.32), 0.03, 0.03, 0.02, 6)
		wx += 0.18
	bx("asbestos", x0 - 0.15, x1 + 0.15, 2.33, 2.38, fz + 0.3, fz + 0.36)
	# 自行车（年代那批另做），最里头一辆落灰的、瘪了胎
	_dusty_bike(Vector3(28.05, 0.0, -2.55))
	# 阿姨的小桌、凳子、打气筒、暖壶
	var ax := 25.5
	bx("wood", ax - 0.35, ax + 0.35, 0.62, 0.66, -1.35, -0.85)
	for lx in [ax - 0.32, ax + 0.29]:
		for lz in [-1.32, -0.9]:
			bx("wood", lx, lx + 0.03, 0.0, 0.62, lz, lz + 0.03)
	bx("paper", ax - 0.3, ax - 0.05, 0.66, 0.67, -1.25, -0.95)
	cyl("sign_red", Vector3(ax + 0.18, 0.66, -1.1), 0.06, 0.06, 0.3, 10)
	cyl("chrome", Vector3(ax + 0.18, 0.96, -1.1), 0.035, 0.03, 0.04, 8)
	bx("wood", ax + 0.5, ax + 0.8, 0.28, 0.31, -1.0, -0.72)
	for k in 4:
		bx("wood", ax + 0.52 + (k % 2) * 0.24, ax + 0.54 + (k % 2) * 0.24, 0.0, 0.28, -0.98 + (k / 2) * 0.22, -0.96 + (k / 2) * 0.22)
	cyl("metal_green", Vector3(ax - 0.62, 0.0, -1.0), 0.03, 0.03, 0.62, 6)
	bx("metal", ax - 0.75, ax - 0.49, 0.0, 0.02, -1.04, -0.96)
	tube("rubber", PackedVector3Array([Vector3(ax - 0.62, 0.5, -1.0), Vector3(ax - 0.75, 0.3, -0.95), Vector3(ax - 0.7, 0.05, -0.8)]), 0.008, 4)
	# 一盏灯泡吊在梁上
	cyl("metal", Vector3(ax, 2.1, -1.6), 0.005, 0.005, 0.38, 3)
	cyl("lamp", Vector3(ax, 2.02, -1.6), 0.045, 0.045, 0.09, 8)
	_add_lamp(Vector3(ax, 1.9, -1.4), Color(1.0, 0.8, 0.52), 5.5, 1.4)


func _dusty_bike(at: Vector3) -> void:
	_bike(at, PI / 2.0, false, "dusty")
	# 瘪胎：地上压扁的一截
	bx("rubber", at.x - 0.03, at.x + 0.03, 0.0, 0.03, at.z - 0.75, at.z - 0.4)
	bx("dusty", at.x - 0.15, at.x + 0.15, 0.97, 1.0, at.z - 0.3, at.z + 0.0)


# ======================================================================
# 外立面（单独一个节点，年代换料：抹灰 → 贴白瓷砖）
# ======================================================================

func _facade() -> void:
	_begin()
	_house_front("school_plaster", B0, B1, FLOOR_H, 2, BZ, -10.0, "frame_blue", 1.45, 1.15)
	# 一层：前面的梁、柱子（贴同样的料）
	bx("school_plaster", B0, B1, 2.75, FLOOR_H, BZ - 0.3, BZ)
	for p in [[B0, B0 + 0.3], [8.0 - 0.2, 8.05], [B1 - 0.25, B1]]:
		bx("school_plaster", p[0], p[1], 0.0, 2.75, BZ - 0.35, BZ)
	# 一层后半截（教室后墙以后）实心
	bx("school_plaster", B0, B1, 0.0, FLOOR_H, -10.0, BACK - 0.25)
	# 楼头山墙：往操场那边
	bx("school_plaster", B1, B1 + 0.05, FLOOR_H + 0.4, FLOOR_H * 3.0, -10.0, BZ - 0.3)
	# 班牌：教室门头上
	bx("metal_white", 8.25, 9.05, 2.83, 3.03, BZ, BZ + 0.03)
	_facade_node = Node3D.new()
	_facade_node.name = "facade"
	add_child(_facade_node)
	_commit(_facade_node)
	_label("初二（3）班", Vector3(8.65, 2.93, BZ + 0.035), 0.0026, Color("#2b2a33"))


func _trees() -> void:
	_begin()
	for p in [[18.9, -15.4, 0.9], [24.3, -15.6, 0.95], [27.6, -15.2, 0.88], [0.4, -12.5, 0.8], [5.7, -12.0, 0.75]]:
		_tree(Vector3(float(p[0]), 0, float(p[1])), float(p[2]), "poplar")
	_commit(self)


# ======================================================================
# 年代：校门（推拉铁门 → 电动伸缩门）、教室（电视 → 投影）、车棚（自行车 → 电动车）
# ======================================================================

func _era_bits() -> void:
	var z := GZ
	# 推拉铁门：半开着，拉到右边门柱后头
	_begin()
	var gx := 3.1
	while gx < 4.0:
		bx("metal_green", gx, gx + 0.025, 0.08, 1.95, z - 0.18, z - 0.15)
		bx("metal_green", gx + 0.0, gx + 0.025, 1.95, 2.05, z - 0.175, z - 0.155)
		gx += 0.11
	for gy in [0.08, 0.9, 1.75]:
		bx("metal_green", 3.05, 4.0, gy, gy + 0.05, z - 0.19, z - 0.14)
	_era_node(0, 2)
	# 电动伸缩门：折起来靠在左边门柱旁，前头一个机头
	_begin()
	for k in 7:
		var lx := 2.26 + k * 0.1
		bx("metal_white", lx, lx + 0.03, 0.12, 1.45, z - 0.2, z - 0.14)
		if k < 6:
			for s in [-1.0, 1.0]:
				Kit.box_into(_tool("metal_white"), Vector3(0.02, 0.62, 0.02), Transform3D(Basis(Vector3.BACK, s * 0.15), Vector3(lx + 0.06, 0.5, z - 0.17)))
				Kit.box_into(_tool("metal_white"), Vector3(0.02, 0.62, 0.02), Transform3D(Basis(Vector3.BACK, s * 0.15), Vector3(lx + 0.06, 1.08, z - 0.17)))
	bx("metal_white", 2.95, 3.3, 0.06, 1.55, z - 0.3, z - 0.04)
	bx("sign_ink", 2.98, 3.27, 1.25, 1.45, z - 0.04, z - 0.03)
	bx("rubber", 2.25, 3.3, 0.0, 0.07, z - 0.22, z - 0.12)
	_era_node(3, 4)
	# 教室：老的挂在墙角的电视
	_begin()
	bx("metal", 12.05, 12.35, 2.35, 2.4, BACK, BACK + 0.45)
	bx("metal", 11.95, 12.45, 2.4, 2.8, BACK + 0.05, BACK + 0.5)
	bx("glass", 12.0, 12.4, 2.45, 2.75, BACK + 0.5, BACK + 0.51, Color(0.1, 0.1, 0.1))
	_era_node(0, 1)
	# 投影：天花上吊着投影仪，黑板上头拉下来一块幕布
	_begin()
	bx("metal_white", 10.1, 10.5, 2.72, 2.85, -3.1, -2.75)
	cyl("metal", Vector3(10.3, 2.85, -2.92), 0.02, 0.02, 0.15, 5)
	bx("metal_white", 8.75, 11.85, 2.3, 2.4, BACK + 0.02, BACK + 0.14)
	bx("paper", 8.85, 11.75, 1.55, 2.3, BACK + 0.07, BACK + 0.08)
	bx("metal", 8.85, 11.75, 1.53, 1.56, BACK + 0.06, BACK + 0.1)
	_era_node(2, 4)
	# 车棚：少年以前一排排都是自行车
	var frames := ["metal", "metal", "metal_green", "frame_blue", "sign_red", "metal"]
	_begin()
	for k in 11:
		var bxx := 23.75 + k * 0.4
		if bxx < 27.8:
			_bike(Vector3(bxx, 0, -2.55), PI / 2.0 + _rng.randf_range(-0.08, 0.08), false, frames[_rng.randi() % frames.size()])
	for bxx in [23.7, 24.1, 24.5, 26.5, 26.9, 27.3, 27.7]:
		_bike(Vector3(bxx, 0, -1.3), PI / 2.0 + _rng.randf_range(-0.1, 0.1), false, frames[_rng.randi() % frames.size()])
	_era_node(0, 1)
	# 青年以后：自行车少了，电动车多了
	_begin()
	var ecols := [Color("#e9e6dc"), Color("#2f3a4a"), Color("#b93a3a"), Color("#6aa0b5"), Color("#e2b33c")]
	for k in 7:
		var ex := 23.8 + k * 0.6
		_ebike(Vector3(ex, 0, -2.6), ecols[k % ecols.size()])
	for bxx in [23.7, 24.15, 26.6, 27.4]:
		_bike(Vector3(bxx, 0, -1.3), PI / 2.0 + _rng.randf_range(-0.1, 0.1), false, frames[_rng.randi() % frames.size()])
	_era_node(2, 4)


func _part(nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	add_child(n)
	return n


## 合批（抄楼里的办法）：没有花纹的素料按光泽并成三种，底色（线性）乘进顶点色，看着一样、网格少一大半
const MERGE := {
	"paper": "matte", "sign_ink": "matte", "sign_red": "matte", "sign_green": "matte", "rubber": "matte", "goods": "matte",
	"wain": "matte", "flag": "matte", "dusty": "matte",
	"metal_white": "gloss", "metal_green": "gloss", "frame_blue": "gloss",
	"chrome": "shiny", "metal": "shiny",
}


func _commit(parent: Node3D, shadows := true) -> void:
	if extra_mats.has("wain") and not extra_mats.has("matte"):
		extra_mats["matte"] = [0, "#ffffff", "#000000", Vector2.ONE, 0.8, 0.0, 0.15, 0.0, 0.0]
		extra_mats["gloss"] = [0, "#ffffff", "#000000", Vector2.ONE, 0.38, 0.0, 0.1, 0.0, 0.25]
		extra_mats["shiny"] = [0, "#ffffff", "#000000", Vector2.ONE, 0.32, 0.0, 0.0, 0.0, 0.8]
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
	# 贴地的、零碎的不投影（每投一次影，平行光的几层阴影都得多画一遍）
	for c in parent.get_children():
		if c is MeshInstance3D and str(c.name) in NO_SHADOW:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


const NO_SHADOW := ["pavers", "curb", "asphalt", "paint", "terrazzo", "track", "turf", "goods", "paper", "matte", "foam",
	"ftube", "lamp", "glass", "glass_far", "wain", "board", "tar", "plaster_far", "brick_grey", "tile_gate", "stone", "bamboo"]


func _era_node(a: int, b: int) -> void:
	var n := Node3D.new()
	add_child(n)
	_commit(n)
	_era_nodes.append([n, a, b])


## 电动车：小轮子、包着塑料壳的车身、踏板、车筐，竖着停（车头朝外）
func _ebike(at: Vector3, col: Color) -> void:
	var b := Basis(Vector3.UP, PI / 2.0)
	for s in [-0.5, 0.5]:
		_ring_b("rubber", at + b * Vector3(s, 0.24, 0), 0.22, 0.045, b)
	Kit.box_into(_tool("goods"), Vector3(0.62, 0.32, 0.26), Transform3D(b, at + b * Vector3(-0.3, 0.55, 0)), col)
	Kit.box_into(_tool("goods"), Vector3(0.12, 0.62, 0.3), Transform3D(b * Basis(Vector3.BACK, -0.25), at + b * Vector3(0.38, 0.6, 0)), col)
	Kit.box_into(_tool("rubber"), Vector3(0.5, 0.06, 0.22), Transform3D(b, at + b * Vector3(-0.3, 0.74, 0)))
	Kit.box_into(_tool("rubber"), Vector3(0.4, 0.04, 0.2), Transform3D(b, at + b * Vector3(0.1, 0.3, 0)))
	tube("chrome", PackedVector3Array([at + b * Vector3(0.45, 0.95, -0.3), at + b * Vector3(0.45, 0.98, 0.3)]), 0.012, 5)
	Kit.box_into(_tool("metal"), Vector3(0.2, 0.18, 0.28), Transform3D(b, at + b * Vector3(0.58, 0.82, 0)))


# ======================================================================
# 年代、灯
# ======================================================================

func set_look(p_look: String) -> void:
	super.set_look(p_look)
	var i := maxi(0, LOOKS.find(look))
	if _facade_node != null:
		var mi := _facade_node.get_node_or_null("school_plaster") as MeshInstance3D
		if mi != null:
			mi.material_override = _mat("tile_white" if i >= 3 else "school_plaster")


## 教室的日光灯：白天开着一点，傍晚到九点（晚自习）全亮，九点以后关
func tick(delta: float, cam_x: float) -> void:
	super.tick(delta, cam_x)
	var m := 600.0
	if stage != null and "minute" in stage:
		m = float(stage.minute)
	for l in lamps:
		var light: OmniLight3D = l[0]
		if light in _class_lamps:
			light.set_meta("day", 1.0 if (m >= 1050.0 and m < 1260.0) else 0.0)
			if m >= 1260.0 or m < 360.0:
				l[1] = 0.0
