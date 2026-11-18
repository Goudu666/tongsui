extends "res://scripts/world3d/set3d.gd"
## 小学（content/maps/primary.yaml，宽 28 米）的实时 3D：照着 2D 那张图的布局一样一样搭真的东西。
## 从左到右：校门外的街口（柏油、路灯、「注意儿童」牌）、传达室（小窗户朝外，窗台上搪瓷缸、报纸）、
## 校门（两根砖门柱、铁栅门，门柱上竖着「育红小学」）、围墙和光荣榜、放学接孩子停车的地方（车随年代换）、
## 两层红砖教学楼（一层教室剖开：后墙黑板、讲台、一排排课桌、日光灯、窗户、黑板报；二层正常外立面）、
## 操场（煤渣跑道、单杠、跳房子的粉笔格、水泥乒乓球台、篮球架、旗杆），后头围墙、杨树、远处楼群。
## 前景一溜矮冬青、花坛边。
##
## 坐标：米。X = 2D 的 x / 100，地面 Y = 0，人走的那条线 Z = 0。教学楼前脸（剖切面）在 ZF，人站在剖切面外头看进去。
## 年代：少年起换电动伸缩门、白板和投影、蓝色单人课桌、红色塑胶跑道；青年起操场铺假草；老年黑板换电子屏。
##   校门口接孩子的：童年自行车、少年电动车 + 自行车、青年/中年轿车、老年一排老人。
## 夜里：学校黑着（教室的灯 tick 里按天黑关掉），只传达室一盏灯、街口路灯、操场墙上一盏。


const ZF := -0.45     ## 教学楼前脸（一层剖开的那个面）
const ZB := -2.85     ## 教室后墙里皮
const ZW := -2.4      ## 校门、围墙的前脸
const Y0 := 0.14      ## 教室地面比外头高一点（剖开看得见楼板厚）
const WIDTH := 28.0

var _class_lamps: Array = []   ## 教室的日光灯（白天开着，天黑了关）
var _bulletin: Array = []      ## 黑板报的 Label3D：[报头, 正文]


func build(sc: Dictionary, p_look: String, season: String) -> void:
	_rng.seed = 20261118
	look = p_look
	extra_mats = {
		"terrazzo": [6, "#b9b1a1", "#000000", Vector2.ONE, 0.55, 0.3, 0.25, 0.07, 0.0],
		"wall_white": [6, "#e6dfcf", "#000000", Vector2.ONE, 0.92, 0.4, 0.35, 0.05, 0.0],
		"board": [6, "#2b3a33", "#000000", Vector2.ONE, 0.9, 0.25, 0.25, 0.08, 0.0],
		"cinder": [6, "#5d514b", "#000000", Vector2.ONE, 0.98, 1.5, 0.0, 0.2, 0.0],
		"track_red": [6, "#a3483b", "#000000", Vector2.ONE, 0.9, 0.7, 0.0, 0.06, 0.0],
		"dirt": [6, "#a08e72", "#000000", Vector2.ONE, 0.96, 1.1, 0.1, 0.16, 0.0],
		"soil": [6, "#5a4636", "#000000", Vector2.ONE, 0.98, 1.4, 0.0, 0.18, 0.0],
		"turf": [6, "#557f48", "#000000", Vector2.ONE, 0.97, 1.3, 0.0, 0.1, 0.0],
		"chalk": [0, "#ebe7dc", "#000000", Vector2.ONE, 0.98, 0.0, 0.0, 0.0, 0.0],
		"desk_blue": [0, "#3f72a6", "#000000", Vector2.ONE, 0.45, 0.0, 0.0, 0.0, 0.0],
		"tube_lamp": [0, "#f3f5f0", "#000000", Vector2.ONE, 0.3, 0.0, 0.0, 0.0, 0.0],
		"warm_win": [0, "#2c3540", "#000000", Vector2.ONE, 0.15, 0.0, 0.0, 0.0, 0.0],
		"carpaint": [0, "#ffffff", "#000000", Vector2.ONE, 0.28, 0.0, 0.0, 0.0, 0.25],
		"display": [0, "#dfe8ee", "#000000", Vector2.ONE, 0.2, 0.0, 0.0, 0.0, 0.0],
		"whiteboard": [0, "#f1f2ef", "#000000", Vector2.ONE, 0.18, 0.0, 0.0, 0.0, 0.0],
		"matte": [0, "#ffffff", "#000000", Vector2.ONE, 0.8, 0.0, 0.0, 0.0, 0.0],
		"shiny": [0, "#ffffff", "#000000", Vector2.ONE, 0.4, 0.0, 0.0, 0.0, 0.55],
	}
	extra_glow = {"warm_win": [2.4, "#ffc983"]}
	_begin()
	_ground()
	_street_mouth()
	_gatehouse()
	_gate_wall()
	_school_building()
	_classroom()
	_yard()
	_front_bed()
	_background()
	_commit(self)
	_era_parts()
	_quiet_shadows(self)
	set_look(look)
	set_season(season)


## 合批（照楼里的办法）：没有花纹、只差底色的素料并成两种，底色（线性）乘进顶点色。
## 兼容渲染器每盏灯每个网格多画一遍，少几个网格夜里 draw call 就少一大截
const MERGE := {
	"paper": "matte", "sign_ink": "matte", "sign_red": "matte", "rubber": "matte", "chalk": "matte", "goods": "matte",
	"tube_lamp": "matte", "paint": "matte", "display": "matte", "whiteboard": "matte", "desk_blue": "matte",
	"metal": "shiny", "metal_green": "shiny", "chrome": "shiny", "metal_white": "shiny", "carpaint": "shiny",
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


## 小东西、贴地的、贴墙的薄片不投影（阴影那一遍少画很多）
const NO_SHADOW := ["matte", "shiny", "wood_light", "bamboo", "iron", "tiles", "wood_green", "wood_red", "goods", "paper", "chalk", "paint", "glass", "glass_far", "lamp", "rubber", "chrome", "dirt", "soil",
	"cinder", "track_red", "turf", "terrazzo", "asphalt", "pavers", "curb", "tube_lamp", "warm_win", "display", "whiteboard",
	"sign_red", "sign_ink", "board"]


func _quiet_shadows(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and str(c.name) in NO_SHADOW:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif c.get_child_count() > 0:
			_quiet_shadows(c)


## 一个随年代开关的节点（下面的东西 _commit 进去）
func _era_node(from: int, to: int) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	_era_nodes.append([n, from, to])
	return n


func _era_label(n: Node3D, text: String, at: Vector3, px: float, col: Color) -> Label3D:
	var l := _label(text, at, px, col)
	remove_child(l)
	n.add_child(l)
	return l


# ======================================================================
# 地面：街口柏油、校门口方砖、教学楼台基、操场（跑道、场地按年代在 _era_parts）
# ======================================================================

func _ground() -> void:
	# 校门口、教学楼前：方砖
	bx("pavers", 0.5, 7.8, -0.2, 0.0, ZW, 2.0)
	bx("pavers", 7.8, 18.6, -0.2, 0.0, ZF, 2.0)
	# 校门里头：水泥地，一直到后墙
	bx("concrete", 0.5, 18.6, -0.25, -0.01, -10.5, ZW)
	# 前头花坛外边：方砖接着往前铺
	bx("pavers", -14.0, 40.0, -0.22, -0.02, 3.3, 9.0)
	# 远处后墙外：一溜土地
	bx("dirt", -14.0, 40.0, -0.3, -0.02, -40.0, -10.5)


## 左头：校门外的街。柏油往后延伸、马路牙子、路灯、「注意儿童」的三角牌
func _street_mouth() -> void:
	bx("asphalt", -14.0, 0.25, -0.4, -0.15, -40.0, 9.0)
	bx("curb", 0.25, 0.5, -0.2, 0.0, -40.0, 3.3)
	# 斑马线：横穿侧街（离镜头近的一段）
	for k in 6:
		bx("paint", -4.2, -0.4, -0.15, -0.145, 2.6 + k * 0.5, 2.85 + k * 0.5)
	# 街对面一栋旧楼的山墙（远一点）
	upper_floors("brick_grey", -13.0, -4.5, 0.0, 3, -4.0, -14.0, 1.1, 1.9)
	_tree(Vector3(-1.4, -0.15, -3.5), 1.0, "huai")
	# 「注意儿童」：黄底黑边三角牌
	cyl("metal", Vector3(0.38, 0, -2.0), 0.03, 0.03, 2.3, 8)
	var c := Vector3(0.38, 2.05, -1.96)
	for i in 3:
		var a := TAU * float(i) / 3.0 + PI / 2.0
		var b2 := TAU * float(i + 1) / 3.0 + PI / 2.0
		var p0 := c + Vector3(cos(a), sin(a), 0) * 0.32
		var p1 := c + Vector3(cos(b2), sin(b2), 0) * 0.32
		tube("sign_ink", PackedVector3Array([p0, p1]), 0.022, 4)
	Kit.box_into(_tool("goods"), Vector3(0.36, 0.3, 0.012), Transform3D(Basis(), c + Vector3(0, -0.03, -0.01)), Color("#e8bf3a"))
	bc("goods", c + Vector3(-0.04, -0.02, 0.0), Vector3(0.05, 0.14, 0.01), 0.0, 0.0, Color("#26262b"))
	bc("goods", c + Vector3(0.06, -0.05, 0.0), Vector3(0.04, 0.1, 0.01), 0.0, 0.0, Color("#26262b"))
	_street_lamp(Vector3(0.38, 0, -0.95))


# ======================================================================
# 传达室：小屋，抹灰刷白、灰勒脚，小窗户朝外，窗台上搪瓷缸、报纸；侧面绿门；房檐下一盏灯
# ======================================================================

func _gatehouse() -> void:
	var x0 := 0.7
	var x1 := 2.5
	var zf := -0.75
	var zb := ZW - 0.3
	var h := 2.65
	var win := Rect2(1.3, 0.95, 0.9, 0.8)
	wall("plaster", x0, x1, 0.0, h, zf, 0.25, [win])
	bx("plaster", x0, x0 + 0.25, 0.0, h, zb, zf - 0.25)
	bx("plaster", x1 - 0.25, x1, 0.0, h, zb, zf - 0.25)
	bx("plaster_grey", x0 - 0.02, x1 + 0.02, 0.0, 0.45, zb, zf + 0.02)
	# 平顶：水泥板挑出来一圈
	bx("concrete", x0 - 0.15, x1 + 0.15, h, h + 0.12, zb - 0.05, zf + 0.18)
	bx("tar", x0 - 0.1, x1 + 0.1, h + 0.12, h + 0.15, zb, zf + 0.12)
	# 小窗：推拉的两扇，里头一点暖光（夜里亮）
	bx("warm_win", win.position.x, win.end.x, win.position.y, win.end.y, zf - 0.17, zf - 0.15)
	var t := 0.04
	for fx in [win.position.x, win.position.x + win.size.x / 2.0 - t / 2.0, win.end.x - t]:
		bx("paint", fx, fx + t, win.position.y, win.end.y, zf - 0.15, zf - 0.1)
	bx("paint", win.position.x, win.end.x, win.end.y - t, win.end.y, zf - 0.15, zf - 0.1)
	bx("concrete", win.position.x - 0.08, win.end.x + 0.08, win.position.y - 0.07, win.position.y, zf - 0.2, zf + 0.12)
	# 窗台上：搪瓷缸（白身子红口）、叠着的报纸
	var mx := 1.55
	cyl("metal_white", Vector3(mx, win.position.y, zf + 0.0), 0.045, 0.045, 0.1, 10)
	cyl("sign_red", Vector3(mx, win.position.y + 0.1, zf + 0.0), 0.047, 0.047, 0.012, 10)
	tube("metal_white", PackedVector3Array([Vector3(mx + 0.045, win.position.y + 0.08, zf), Vector3(mx + 0.08, win.position.y + 0.06, zf), Vector3(mx + 0.045, win.position.y + 0.025, zf)]), 0.008, 4)
	bc("paper", Vector3(1.88, win.position.y + 0.012, zf + 0.0), Vector3(0.3, 0.02, 0.2), 0.12)
	bc("paper", Vector3(1.9, win.position.y + 0.03, zf - 0.01), Vector3(0.28, 0.015, 0.18), -0.08)
	# 门头小牌「传达室」
	bx("metal_white", 1.42, 2.08, 1.92, 2.12, zf, zf + 0.025)
	_label("传达室", Vector3(1.75, 2.02, zf + 0.03), 0.0034, Color("#2b2a33"))
	# 侧面一扇绿漆木门（朝校门那边）
	bx("wood_green", x1, x1 + 0.03, 0.0, 2.05, -1.95, -1.05)
	bx("chrome", x1 + 0.03, x1 + 0.05, 0.98, 1.02, -1.15, -1.1)
	# 冬天生炉子的铁皮烟筒：从侧墙伸出来往上拐
	tube("iron", PackedVector3Array([Vector3(x0 + 0.1, 2.1, -1.6), Vector3(x0 - 0.25, 2.1, -1.6), Vector3(x0 - 0.25, 3.05, -1.6)]), 0.055, 8)
	cyl("iron", Vector3(x0 - 0.25, 3.05, -1.6), 0.1, 0.03, 0.1, 8)
	# 门口一把旧藤椅（大爷坐的）、一个暖壶
	bx("bamboo", 0.82, 1.22, 0.38, 0.42, -0.72, -0.42)
	bx("bamboo", 0.82, 1.22, 0.42, 0.82, -0.76, -0.72)
	for lx in [0.84, 1.2]:
		for lz in [-0.72, -0.44]:
			bx("bamboo", lx - 0.015, lx + 0.015, 0.0, 0.38, lz - 0.015, lz + 0.015)
	cyl("goods", Vector3(1.32, 0, -0.62), 0.065, 0.06, 0.32, 10, Color("#c9483c"))
	cyl("chrome", Vector3(1.32, 0.32, -0.62), 0.03, 0.03, 0.04, 8)
	# 房檐下一盏灯：夜里整个学校就这儿亮着
	_lamp_wall(Vector3(1.75, 2.45, zf + 0.1))


# ======================================================================
# 校门、围墙、光荣榜
# ======================================================================

func _gate_wall() -> void:
	# 两根门柱：红砖、水泥帽子
	for p in [[2.5, 2.95], [4.65, 5.1]]:
		var a: float = p[0]
		var b: float = p[1]
		bx("brick", a, b, 0.0, 2.5, ZW - 0.45, ZW)
		bx("concrete", a - 0.06, b + 0.06, 2.5, 2.62, ZW - 0.51, ZW + 0.06)
		bc("concrete", Vector3((a + b) / 2.0, 2.7, ZW - 0.225), Vector3(0.3, 0.16, 0.3))
		bx("concrete", a - 0.03, b + 0.03, 0.0, 0.25, ZW - 0.48, ZW + 0.03)
	# 校牌：右门柱上竖着一块白牌、黑字
	bx("metal_white", 4.72, 5.03, 0.75, 2.3, ZW + 0.0, ZW + 0.03)
	_label("育\n红\n小\n学", Vector3(4.875, 1.52, ZW + 0.035), 0.0062, Color("#24232a"))
	# 门槛下的轨道（伸缩门走的槽，老年代也一直在）
	bx("metal", 2.95, 4.65, 0.0, 0.012, ZW - 0.26, ZW - 0.2)
	# 围墙：门右边到教学楼。下半截砖、上头一排铁栏杆带尖
	var w0 := 5.1
	var w1 := 7.8
	bx("brick", w0, w1, 0.0, 0.85, ZW - 0.3, ZW)
	bx("concrete", w0, w1, 0.85, 0.93, ZW - 0.33, ZW + 0.03)
	var x := w0 + 0.1
	while x < w1 - 0.05:
		cyl("metal_green", Vector3(x, 0.93, ZW - 0.15), 0.012, 0.012, 1.05, 5)
		cyl("metal_green", Vector3(x, 1.98, ZW - 0.15), 0.025, 0.0, 0.08, 5)
		x += 0.13
	for gy in [1.1, 1.85]:
		bx("metal_green", w0, w1, gy, gy + 0.03, ZW - 0.17, ZW - 0.13)
	# 传达室和左门柱之间、传达室左边：一段砖墙接上
	bx("brick", 0.5, 0.7, 0.0, 2.0, ZW - 0.3, ZW)
	# 校门里头：一条水泥道往后、自行车棚（老师的车）、一棵槐树
	bx("pavers", 2.95, 4.65, -0.2, -0.005, -9.5, ZW - 0.3)
	var sz0 := -7.6
	var sz1 := -5.6
	for px in [0.9, 3.0, 5.6, 7.4]:
		cyl("metal", Vector3(px, 0, sz1), 0.035, 0.035, 2.05, 6)
		cyl("metal", Vector3(px, 0, sz0), 0.035, 0.035, 2.25, 6)
	Kit.box_into(_tool("iron"), Vector3(7.0, 0.025, 2.3), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-6.0)), Vector3(4.15, 2.2, (sz0 + sz1) / 2.0)))
	bx("brick_grey", 0.6, 7.7, 0.0, 1.2, sz0 - 0.2, sz0)
	_tree(Vector3(1.6, 0, -4.2), 0.9, "huai")


# ======================================================================
# 教学楼：两层红砖，一层教室剖开；二层窗户、窗台、腰线、雨水管，坡瓦顶
# ======================================================================

func _school_building() -> void:
	var x0 := 7.8
	var x1 := 18.6
	var zb := ZB - 0.3
	var top := FLOOR_H * 2.0 + 0.25
	# 台基：教室地面比外头高一截，剖开看得见水泥楼板厚、上头一层水磨石
	bx("concrete", x0, x1, -0.2, Y0 - 0.02, zb, ZF)
	bx("terrazzo", x0 + 0.3, x1 - 0.3, Y0 - 0.02, Y0, ZB, ZF)
	bx("concrete", x0, x1, Y0 - 0.06, Y0, ZF - 0.04, ZF + 0.02)
	# 两头的山墙：一层剖到 ZF，砖的厚度露在剖面上
	bx("brick", x0, x0 + 0.3, 0.0, top, zb, ZF)
	bx("brick", x1 - 0.3, x1, 0.0, top, zb, ZF)
	# 二楼楼板：剖面上一道水泥、底下刷白的天花
	bx("concrete", x0, x1, FLOOR_H, FLOOR_H + 0.28, zb, ZF + 0.04)
	bx("wall_white", x0 + 0.3, x1 - 0.3, FLOOR_H - 0.02, FLOOR_H, ZB, ZF)
	# 二层：一排窗，砖墙挖洞
	var holes: Array = []
	var n := 5
	var pitch := (x1 - x0) / float(n)
	for i in n:
		var wx := x0 + i * pitch + (pitch - 1.25) / 2.0
		var r := Rect2(wx, FLOOR_H + 0.95, 1.25, 1.5)
		holes.append(r)
		_dark_window(wx, FLOOR_H + 0.95, 1.25, 1.5, ZF)
	wall("brick", x0, x1, FLOOR_H + 0.28, top, ZF, 0.3, holes)
	bx("brick", x0, x1, FLOOR_H + 0.28, top, zb, ZF - 0.3)
	# 檐口、坡瓦顶（镜头一般拍不到全，拍到一角就够）
	bx("concrete", x0 - 0.12, x1 + 0.12, top, top + 0.16, zb - 0.12, ZF + 0.14)
	var eave := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-26.0)), Vector3((x0 + x1) / 2.0, top + 0.75, ZF - 1.0))
	Kit.box_into(_tool("tiles"), Vector3(x1 - x0 + 0.5, 0.08, 3.4), eave)
	# 雨水管：右边山墙前脸，从檐口一直下到地
	var px := x1 - 0.12
	tube("metal_white", PackedVector3Array([Vector3(px, top, ZF + 0.12), Vector3(px, top - 0.3, ZF + 0.07), Vector3(px, 0.25, ZF + 0.07), Vector3(px, 0.05, ZF + 0.18)]), 0.045, 6)
	bx("metal_white", px - 0.08, px + 0.08, top - 0.08, top + 0.06, ZF + 0.02, ZF + 0.2)
	# 操场那边墙上一盏灯（夜里照着跑道一角）
	_lamp_wall(Vector3(x1 + 0.12, 2.75, -1.1))
	# 楼后头：两棵杨树（从教室窗户看得见）
	_tree(Vector3(12.2, 0, -5.4), 1.15, "huai")
	_tree(Vector3(16.9, 0, -6.2), 1.05, "huai")


# ======================================================================
# 教室：后墙（窗朝后院）、绿墙裙、黑板 + 讲台、课程表、标语、钟、奖状、黑板报、图书角、日光灯
# 课桌椅、黑板这些随年代换的在 _era_parts
# ======================================================================

func _classroom() -> void:
	var x0 := 8.1
	var x1 := 18.3
	var win_a := Rect2(13.05, 1.2, 1.45, 1.45)
	var win_b := Rect2(15.15, 1.2, 1.45, 1.45)
	# 后墙：里皮刷白、外皮红砖，窗洞
	wall("wall_white", x0, x1, Y0, FLOOR_H, ZB, 0.27, [win_a, win_b])
	wall("brick", x0 - 0.3, x1 + 0.3, 0.0, FLOOR_H + 0.28, ZB - 0.27, 0.03, [win_a, win_b])
	# 两侧墙里皮
	bx("wall_white", x0, x0 + 0.015, Y0, FLOOR_H, ZB, ZF)
	bx("wall_white", x1 - 0.015, x1, Y0, FLOOR_H, ZB, ZF)
	# 绿墙裙：一圈到窗台下，上沿一道深绿线
	bx("plaster_green", x0, x1, Y0, 1.12, ZB, ZB + 0.012)
	bx("plaster_green", x0, x0 + 0.02, Y0, 1.12, ZB, ZF)
	bx("plaster_green", x1 - 0.02, x1, Y0, 1.12, ZB, ZF)
	bx("wood_green", x0, x1, 1.1, 1.14, ZB, ZB + 0.02)
	# 窗：木框刷白、玻璃不装（看得见后院的树），水泥窗台
	for r in [win_a, win_b]:
		var w: Rect2 = r
		var t := 0.05
		var fz := ZB - 0.14
		bx("paint", w.position.x, w.end.x, w.position.y, w.position.y + t, fz, fz + 0.05)
		bx("paint", w.position.x, w.end.x, w.end.y - t, w.end.y, fz, fz + 0.05)
		bx("paint", w.position.x, w.position.x + t, w.position.y, w.end.y, fz, fz + 0.05)
		bx("paint", w.end.x - t, w.end.x, w.position.y, w.end.y, fz, fz + 0.05)
		bx("paint", w.position.x + w.size.x / 2.0 - 0.02, w.position.x + w.size.x / 2.0 + 0.02, w.position.y, w.end.y, fz, fz + 0.04)
		bx("paint", w.position.x, w.end.x, w.position.y + 1.0, w.position.y + 1.04, fz, fz + 0.04)
		bx("concrete", w.position.x - 0.05, w.end.x + 0.05, w.position.y - 0.05, w.position.y, ZB - 0.27, ZB + 0.1)
		# 窗台上一盆花（吊兰）
		cyl("goods", Vector3(w.position.x + 0.3, w.position.y, ZB - 0.05), 0.07, 0.055, 0.12, 8, Color("#a5563a"))
	for k in 5:
		var a := TAU * float(k) / 5.0
		tube("plaster_green", PackedVector3Array([Vector3(13.35, 1.32, -2.9), Vector3(13.35 + cos(a) * 0.16, 1.4, -2.9 + sin(a) * 0.1), Vector3(13.35 + cos(a) * 0.22, 1.25, -2.9 + sin(a) * 0.14)]), 0.012, 4)
	# 讲台：沿后墙一溜木台子，比地面高一步
	bx("wood", 8.35, 12.95, Y0, Y0 + 0.18, ZB, ZB + 0.95)
	bx("wood_light", 8.35, 12.95, Y0 + 0.16, Y0 + 0.18, ZB + 0.9, ZB + 0.96)
	# 讲桌：木头的，桌上粉笔盒、黑板擦、教鞭、一摞作业本
	var lx := 10.9
	var lz := ZB + 0.6
	var ly := Y0 + 0.18
	bx("wood", lx - 0.45, lx + 0.45, ly, ly + 0.92, lz - 0.25, lz + 0.25)
	bx("wood_light", lx - 0.5, lx + 0.5, ly + 0.92, ly + 0.96, lz - 0.29, lz + 0.29)
	bx("wood_light", lx - 0.43, lx + 0.43, ly + 0.08, ly + 0.84, lz + 0.25, lz + 0.26)
	var tt := ly + 0.96
	bx("goods", lx - 0.38, lx - 0.22, tt, tt + 0.07, lz - 0.1, lz + 0.02, Color("#e9e4d8"))
	bx("goods", lx - 0.15, lx + 0.05, tt, tt + 0.05, lz + 0.02, lz + 0.1, Color("#7a5a3a"))
	bc("goods", Vector3(lx + 0.15, tt + 0.01, lz + 0.05), Vector3(0.9, 0.018, 0.018), 0.25, 0.0, Color("#b38a52"))
	for k in 5:
		bx("goods", lx + 0.18, lx + 0.42, tt + k * 0.018, tt + k * 0.018 + 0.016, lz - 0.2, lz - 0.04, [Color("#e6dfcf"), Color("#c4d3c4"), Color("#e6dfcf"), Color("#d6c9a8"), Color("#e6dfcf")][k])
	# 课程表：黑板左边一张纸、画着格子
	var sx0 := 8.35
	var sx1 := 9.15
	bx("paper", sx0, sx1, 1.45, 2.3, ZB, ZB + 0.012)
	for k in 6:
		bx("sign_ink", sx0 + 0.04, sx1 - 0.04, 1.55 + k * 0.13, 1.556 + k * 0.13, ZB + 0.012, ZB + 0.016)
	for k in 4:
		bx("sign_ink", sx0 + 0.12 + k * 0.16, sx0 + 0.126 + k * 0.16, 1.52, 2.22, ZB + 0.012, ZB + 0.016)
	_label("课程表", Vector3((sx0 + sx1) / 2.0, 2.24, ZB + 0.02), 0.0022, Color("#2b2a33"))
	# 标语：黑板上方一溜红字
	bx("paper", 9.5, 12.3, 2.45, 2.72, ZB, ZB + 0.012)
	_label("好好学习  天天向上", Vector3(10.9, 2.585, ZB + 0.018), 0.0042, Color("#b53a30"))
	# 两扇窗之间：圆钟
	var cc := Vector3(14.82, 2.42, ZB + 0.03)
	_ring_b("metal", cc, 0.15, 0.018, Basis())
	bx("paper", cc.x - 0.11, cc.x + 0.11, cc.y - 0.11, cc.y + 0.11, ZB + 0.005, ZB + 0.02)
	bc("sign_ink", cc + Vector3(0.0, 0.04, 0.0), Vector3(0.012, 0.09, 0.006))
	bc("sign_ink", cc + Vector3(0.04, 0.0, 0.0), Vector3(0.1, 0.01, 0.006), 0.0, 0.0)
	# 奖状：第一扇窗上头两张（白纸红边）
	for k in 2:
		var ax := 13.1 + k * 0.72
		bx("sign_red", ax, ax + 0.6, 2.7, 3.02, ZB, ZB + 0.01)
		bx("paper", ax + 0.03, ax + 0.57, 2.73, 2.99, ZB + 0.01, ZB + 0.014)
		bx("goods", ax + 0.24, ax + 0.36, 2.92, 2.96, ZB + 0.014, ZB + 0.018, Color("#c9a13c"))
	# 教室后头：黑板报（墙上一块黑板，粉笔字只红黄白）
	var bb0 := 16.85
	var bb1 := 18.15
	bx("wood", bb0 - 0.05, bb1 + 0.03, 1.15, 2.6, ZB, ZB + 0.025)
	bx("board", bb0, bb1, 1.2, 2.55, ZB + 0.025, ZB + 0.035)
	var head := _label("学习园地", Vector3(bb0 + 0.42, 2.38, ZB + 0.04), 0.0036, Color("#e48a76"))
	var body := _label("", Vector3(bb0 + 0.62, 1.82, ZB + 0.04), 0.0021, Color("#ece7da"))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_bulletin = [head, body]
	# 报头旁边画的花边、一朵粉笔太阳（黄）
	for k in 9:
		bx("goods", bb0 + 0.05 + k * 0.14, bb0 + 0.12 + k * 0.14, 1.26, 1.29, ZB + 0.036, ZB + 0.04, Color("#e8d27a") if k % 2 == 0 else Color("#e48a76"))
	_ring_b("goods", Vector3(bb1 - 0.22, 2.32, ZB + 0.038), 0.09, 0.008, Basis())
	# 图书角：黑板报底下一个矮柜，几排书；墙角扫帚、簸箕、铁皮水桶
	bx("wood_light", 16.9, 18.2, Y0, Y0 + 0.75, ZB, ZB + 0.38)
	bx("wood", 16.9, 18.2, Y0 + 0.36, Y0 + 0.38, ZB, ZB + 0.38)
	var bcol := [Color("#b84a3a"), Color("#3d6a8f"), Color("#e2c46a"), Color("#e6dfcf"), Color("#4f7d5c"), Color("#8b5a7b")]
	for shelf in [Y0 + 0.38, Y0 + 0.75]:
		var gx := 16.95
		while gx < 18.1:
			var gw := _rng.randf_range(0.03, 0.06)
			bx("goods", gx, gx + gw, shelf, shelf + _rng.randf_range(0.18, 0.26), ZB + 0.06, ZB + 0.3, bcol[_rng.randi() % bcol.size()])
			gx += gw + 0.008
	tube("bamboo", PackedVector3Array([Vector3(18.12, Y0, -1.4), Vector3(18.2, Y0 + 1.15, -1.48)]), 0.015, 5)
	bc("goods", Vector3(18.1, Y0 + 0.12, -1.38), Vector3(0.06, 0.24, 0.22), 0.0, 0.0, Color("#7f6a45"))
	cyl("iron", Vector3(18.0, Y0, -1.05), 0.14, 0.12, 0.3, 12)
	bx("goods", 17.88, 18.12, Y0, Y0 + 0.03, -0.72, -0.55, Color("#3d6a8f"))
	# 日光灯：三排，两根吊杆、白铁灯罩、灯管
	for fx in [10.3, 13.4, 16.4]:
		for fz in [-1.15, -2.05]:
			for dz in [-0.45, 0.45]:
				tube("metal", PackedVector3Array([Vector3(fx, FLOOR_H, fz + dz), Vector3(fx, 2.78, fz + dz)]), 0.006, 3)
			bx("metal_white", fx - 0.07, fx + 0.07, 2.76, 2.8, fz - 0.6, fz + 0.6)
			bx("tube_lamp", fx - 0.025, fx + 0.025, 2.72, 2.76, fz - 0.58, fz + 0.58)
	# 白天开着的两盏大灯（教室里一两盏大范围的灯就够；天黑了 tick 里关）
	for p in [Vector3(13.2, 2.6, -1.0)]:
		_add_lamp(p, Color(0.92, 0.97, 1.0), 7.0, 2.0, 0.42)
		_class_lamps.append(lamps[-1])


# ======================================================================
# 操场：单杠、跳房子的粉笔格、水泥乒乓球台、篮球架、旗杆；后头围墙、杨树；右头铁栏杆
# 跑道、场地随年代换（_era_parts）
# ======================================================================

func _yard() -> void:
	# 单杠：两高一低
	var bz := -2.25
	for p in [[19.3, 1.95], [20.45, 1.95], [21.35, 1.45]]:
		cyl("metal", Vector3(float(p[0]), 0, bz), 0.035, 0.035, float(p[1]), 8)
	tube("chrome", PackedVector3Array([Vector3(19.3, 1.85, bz), Vector3(20.45, 1.85, bz)]), 0.018, 6)
	tube("chrome", PackedVector3Array([Vector3(20.45, 1.35, bz), Vector3(21.35, 1.35, bz)]), 0.018, 6)
	# 单杠底下一块沙坑（垫着）
	bx("goods", 19.0, 21.65, -0.03, 0.015, bz - 0.55, bz + 0.5, Color("#c9b48c"))
	# 跳房子：粉笔格子（单、双、单、双……顶上一个半圆）
	var hz := -1.95
	var cell := 0.42
	var hx := 21.95
	var pat := [1, 1, 2, 1, 2, 1, 1]
	for i in pat.size():
		var cx := hx + i * cell
		if int(pat[i]) == 1:
			_chalk_rect(cx, cx + cell, hz - cell / 2.0, hz + cell / 2.0)
		else:
			_chalk_rect(cx, cx + cell, hz - cell, hz)
			_chalk_rect(cx, cx + cell, hz, hz + cell)
	var ex := hx + pat.size() * cell
	var arc := PackedVector3Array()
	for k in 9:
		var a := -PI / 2.0 + PI * float(k) / 8.0
		arc.append(Vector3(ex + cos(a) * cell * 0.6, 0.006, hz + sin(a) * cell * 0.6))
	tube("chalk", arc, 0.012, 3)
	# 格子里一块瓦片
	bc("goods", Vector3(hx + 2.5 * cell, 0.012, hz + 0.05), Vector3(0.09, 0.02, 0.07), 0.6, 0.0, Color("#8a4a3a"))
	# 水泥乒乓球台：一块板、两个墩子、中间一排砖当网
	var tx := 21.1
	var tz := -4.8
	bx("concrete", tx - 1.1, tx + 1.1, 0.68, 0.76, tz - 0.6, tz + 0.6)
	for lx in [tx - 0.7, tx + 0.7]:
		bx("concrete", lx - 0.12, lx + 0.12, 0.0, 0.68, tz - 0.4, tz + 0.4)
	bx("brick_dark", tx - 0.05, tx + 0.05, 0.76, 0.92, tz - 0.6, tz + 0.6)
	bx("paint", tx - 1.1, tx + 1.1, 0.76, 0.765, tz - 0.01, tz + 0.01)
	# 篮球架：铁杆、白边木篮板、红铁圈、网
	var hx2 := 25.7
	var pz := -4.7
	cyl("metal", Vector3(hx2, 0, pz), 0.07, 0.06, 3.3, 10)
	tube("metal", PackedVector3Array([Vector3(hx2, 3.1, pz), Vector3(hx2, 3.25, pz + 0.5), Vector3(hx2, 3.25, pz + 0.75)]), 0.04, 6)
	tube("metal", PackedVector3Array([Vector3(hx2, 2.4, pz), Vector3(hx2, 2.9, pz + 0.72)]), 0.03, 6)
	var bdz := pz + 0.78
	bx("metal_white", hx2 - 0.62, hx2 + 0.62, 2.55, 3.38, bdz, bdz + 0.04)
	bx("sign_red", hx2 - 0.2, hx2 + 0.2, 2.75, 2.78, bdz + 0.04, bdz + 0.045)
	bx("sign_red", hx2 - 0.2, hx2 + 0.2, 3.03, 3.06, bdz + 0.04, bdz + 0.045)
	bx("sign_red", hx2 - 0.2, hx2 - 0.17, 2.75, 3.06, bdz + 0.04, bdz + 0.045)
	bx("sign_red", hx2 + 0.17, hx2 + 0.2, 2.75, 3.06, bdz + 0.04, bdz + 0.045)
	var rim := PackedVector3Array()
	for k in 13:
		var a := TAU * float(k) / 12.0
		rim.append(Vector3(hx2 + cos(a) * 0.22, 2.78, bdz + 0.27 + sin(a) * 0.22))
	tube("sign_red", rim, 0.012, 4)
	for k in 6:
		var a := TAU * float(k) / 6.0
		tube("chalk", PackedVector3Array([Vector3(hx2 + cos(a) * 0.22, 2.78, bdz + 0.27 + sin(a) * 0.22), Vector3(hx2 + cos(a) * 0.13, 2.45, bdz + 0.27 + sin(a) * 0.13)]), 0.005, 3)
	# 罚球区的线
	_chalk_rect(hx2 - 0.9, hx2 + 0.9, bdz, bdz + 2.2)
	# 旗杆：两级水泥旗台、不锈钢杆、一面红旗
	var fx := 27.1
	var fz := -6.0
	bx("concrete", fx - 0.9, fx + 0.9, 0.0, 0.18, fz - 0.9, fz + 0.9)
	bx("concrete", fx - 0.6, fx + 0.6, 0.18, 0.36, fz - 0.6, fz + 0.6)
	cyl("chrome", Vector3(fx, 0.36, fz), 0.06, 0.04, 5.1, 10)
	cyl("chrome", Vector3(fx, 5.46, fz), 0.06, 0.06, 0.08, 8)
	tube("metal_white", PackedVector3Array([Vector3(fx + 0.06, 5.4, fz), Vector3(fx + 0.06, 1.0, fz)]), 0.004, 3)
	var flag := PackedVector3Array()
	for k in 7:
		var u := float(k) / 6.0
		flag.append(Vector3(fx + 0.04 + u * 1.05, 5.0, fz + sin(u * 4.0) * 0.08))
	for k in 6:
		var u := (float(k) + 0.5) / 6.0
		bc("sign_red", Vector3(fx + 0.04 + u * 1.05, 4.67, fz + sin(u * 4.0) * 0.08), Vector3(1.05 / 6.0 + 0.01, 0.66, 0.012), -cos(u * 4.0) * 0.32 * 0.9)
	# 后围墙：砖墙、水泥压顶；墙里头一排杨树
	bx("brick", -0.5, 30.0, 0.0, 2.2, -10.8, -10.5)
	bx("concrete", -0.55, 30.05, 2.2, 2.3, -10.85, -10.45)
	for k in 7:
		var px := 1.0 + k * 4.4
		bx("brick", px - 0.2, px + 0.2, 0.0, 2.45, -10.85, -10.42)
	for p in [[19.6, -8.8, 1.2], [23.4, -9.3, 1.1], [29.6, -8.6, 1.25], [8.8, -9.0, 1.15]]:
		_tree(Vector3(float(p[0]), 0, float(p[1])), float(p[2]), "huai")
	# 右头：铁栏杆围墙（砖墩、铁条带尖）
	var rx := 28.6
	bx("brick", rx, rx + 0.3, 0.0, 0.5, -10.5, 2.0)
	bx("concrete", rx - 0.03, rx + 0.33, 0.5, 0.56, -10.5, 2.0)
	var z := 1.9
	while z > -10.4:
		cyl("metal_green", Vector3(rx + 0.15, 0.56, z), 0.012, 0.012, 1.2, 5)
		cyl("metal_green", Vector3(rx + 0.15, 1.76, z), 0.024, 0.0, 0.08, 5)
		z -= 0.16
	for gy in [0.8, 1.66]:
		bx("metal_green", rx + 0.12, rx + 0.18, gy, gy + 0.03, -10.5, 2.0)
	for pz2 in [1.9, -2.2, -6.3, -10.4]:
		bx("brick", rx - 0.05, rx + 0.35, 0.0, 1.95, pz2 - 0.18, pz2 + 0.18)
		bx("concrete", rx - 0.08, rx + 0.38, 1.95, 2.03, pz2 - 0.21, pz2 + 0.21)
	# 栏杆外头：街边的地
	bx("pavers", rx + 0.3, 40.0, -0.21, -0.01, -10.5, 3.3)


## 和 window() 一样，只是玻璃夜里不亮（放了学楼里没人）
func _dark_window(x: float, y: float, w: float, h: float, z: float) -> void:
	var rz := z - 0.16
	bx("glass", x, x + w, y, y + h, rz - 0.02, rz, Color(0.0, _rng.randf(), _rng.randf()))
	var t := 0.045
	bx("paint", x, x + w, y, y + t, rz, rz + 0.05)
	bx("paint", x, x + w, y + h - t, y + h, rz, rz + 0.05)
	bx("paint", x, x + t, y, y + h, rz, rz + 0.05)
	bx("paint", x + w - t, x + w, y, y + h, rz, rz + 0.05)
	bx("paint", x + w / 2.0 - t / 2.0, x + w / 2.0 + t / 2.0, y, y + h, rz, rz + 0.04)
	bx("paint", x, x + w, y + h * 0.68, y + h * 0.68 + t * 0.8, rz, rz + 0.04)
	bx("concrete", x - 0.06, x + w + 0.06, y - 0.07, y, z - 0.05, z + 0.1)


func _chalk_rect(x0: float, x1: float, z0: float, z1: float) -> void:
	var t := 0.025
	bx("chalk", x0, x1, 0.0, 0.006, z0, z0 + t)
	bx("chalk", x0, x1, 0.0, 0.006, z1 - t, z1)
	bx("chalk", x0, x0 + t, 0.0, 0.006, z0, z1)
	bx("chalk", x1 - t, x1, 0.0, 0.006, z0, z1)


# ======================================================================
# 前景：马路牙子、花坛（土、一溜矮冬青、几朵月季），都不高过 0.5 米
# ======================================================================

func _front_bed() -> void:
	bx("curb", -0.0, 28.6, -0.2, 0.12, 2.0, 2.2)
	bx("curb", -0.0, 28.6, -0.2, 0.12, 3.15, 3.3)
	bx("soil", 0.0, 28.6, -0.2, 0.06, 2.2, 3.15)
	for p in [[3.0, 5.0], [10.6, 5.6], [17.8, 5.0], [25.0, 5.4]]:
		_hedge(Vector3(float(p[0]), 0.02, 2.68), float(p[1]), 0.42)
	# 冬青缝里几朵月季
	var cols := [Color("#c8344a"), Color("#e4a0a8"), Color("#e9dfa8")]
	for k in 14:
		var fx := _rng.randf_range(0.5, 28.0)
		Kit.box_into(_tool("goods"), Vector3(0.07, 0.06, 0.07), Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(fx, 0.42 + _rng.randf() * 0.06, 2.35 + _rng.randf() * 0.15)), cols[_rng.randi() % cols.size()])


# ======================================================================
# 随年代换的：校门、黑板、课桌椅、跑道、场地、光荣榜、校门口接孩子的
# ======================================================================

func _era_parts() -> void:
	# --- 校门：童年两扇铁栅门（敞着往里开）；少年起电动伸缩门
	_begin()
	_iron_leaf(Vector3(2.95, 0, ZW - 0.22), deg_to_rad(72.0))
	_iron_leaf(Vector3(4.65, 0, ZW - 0.22), deg_to_rad(108.0))
	_commit(_era_node(0, 0))
	_begin()
	_slide_gate(2.95, 3.75)
	_commit(_era_node(1, 4))
	# --- 黑板：童年墨绿黑板 + 粉笔字
	var n0 := _era_node(0, 0)
	_begin()
	_board_frame(9.35, 12.45, "board")
	_commit(n0)
	_era_label(n0, "25 × 4 = 100\n125 × 8 = 1000\n36 ÷ 6 =", Vector3(10.0, 1.62, ZB + 0.05), 0.0034, Color("#ece7da"))
	_era_label(n0, "十一月十八日  星期三", Vector3(10.0, 2.12, ZB + 0.05), 0.0022, Color("#ece7da"))
	_era_label(n0, "值日生", Vector3(12.05, 2.12, ZB + 0.05), 0.0022, Color("#e8d27a"))
	_begin()
	# 黑板右边粉笔画的一个正方形、一个三角
	var sq := Rect2(11.55, 1.2, 0.5, 0.5)
	for e in [[sq.position.x, sq.end.x, sq.position.y, sq.position.y + 0.012], [sq.position.x, sq.end.x, sq.end.y - 0.012, sq.end.y],
			[sq.position.x, sq.position.x + 0.012, sq.position.y, sq.end.y], [sq.end.x - 0.012, sq.end.x, sq.position.y, sq.end.y]]:
		bx("chalk", float(e[0]), float(e[1]), float(e[2]), float(e[3]), ZB + 0.044, ZB + 0.047)
	tube("goods", PackedVector3Array([Vector3(12.12, 1.2, ZB + 0.046), Vector3(12.38, 1.2, ZB + 0.046), Vector3(12.25, 1.5, ZB + 0.046), Vector3(12.12, 1.2, ZB + 0.046)]), 0.006, 3)
	_commit(n0)
	# 少年到中年：白板（蓝字），上头卷着投影幕；屋顶吊一台投影仪
	var n1 := _era_node(1, 3)
	_begin()
	_board_frame(9.35, 12.45, "whiteboard")
	bx("metal_white", 9.6, 12.2, 2.32, 2.42, ZB + 0.02, ZB + 0.14)
	bx("whiteboard", 9.7, 12.1, 1.75, 2.32, ZB + 0.11, ZB + 0.12)
	bx("metal", 9.7, 12.1, 1.73, 1.76, ZB + 0.1, ZB + 0.13)
	bx("metal_white", 10.75, 11.05, 2.62, 2.78, -1.45, -1.05)
	tube("metal", PackedVector3Array([Vector3(10.9, FLOOR_H, -1.25), Vector3(10.9, 2.78, -1.25)]), 0.015, 4)
	_commit(n1)
	_era_label(n1, "第 三 课", Vector3(10.9, 2.06, ZB + 0.125), 0.003, Color("#3a5f9a"))
	_era_label(n1, "复习：分数的加减", Vector3(10.2, 1.4, ZB + 0.05), 0.0022, Color("#2f4f86"))
	# 老年：一整块电子屏（黑边框、亮着的课件）
	var n2 := _era_node(4, 4)
	_begin()
	bx("metal", 9.25, 12.55, 0.95, 2.3, ZB, ZB + 0.06)
	bx("display", 9.33, 12.47, 1.03, 2.22, ZB + 0.06, ZB + 0.065)
	bx("goods", 9.5, 10.6, 1.3, 1.9, ZB + 0.066, ZB + 0.07, Color("#9fc0d4"))
	bx("goods", 9.5, 10.6, 1.3, 1.36, ZB + 0.07, ZB + 0.072, Color("#5a7f63"))
	_commit(n2)
	_era_label(n2, "认识二十四节气", Vector3(11.5, 1.95, ZB + 0.07), 0.0024, Color("#2b3a4a"))
	_era_label(n2, "立春  雨水  惊蛰\n春分  清明  谷雨", Vector3(11.5, 1.5, ZB + 0.07), 0.0018, Color("#3d5566"))
	# --- 课桌椅：童年双人木课桌、铁腿；少年起蓝色塑料面单人桌
	_begin()
	for cx in [13.6, 15.3, 17.0]:
		for cz in [-1.15, -2.2]:
			_desk_pair(cx, cz)
	_commit(_era_node(0, 0))
	_begin()
	for cx in [13.3, 13.95, 15.0, 15.65, 16.7, 17.35]:
		for cz in [-1.15, -2.2]:
			_desk_single(cx, cz)
	_commit(_era_node(1, 4))
	# --- 跑道：童年、少年头两年煤渣（这儿简化成童年）；少年起红色塑胶
	_begin()
	bx("cinder", 18.6, 28.6, -0.2, 0.0, -1.35, 2.0)
	for lz in [-1.3, -0.35, 0.6, 1.55]:
		bx("chalk", 18.6, 28.6, 0.0, 0.004, lz, lz + 0.05)
	bx("dirt", 18.6, 28.6, -0.22, -0.005, -10.5, -1.35)
	_commit(_era_node(0, 0))
	_begin()
	bx("track_red", 18.6, 28.6, -0.2, 0.0, -1.35, 2.0)
	for lz in [-1.3, -0.35, 0.6, 1.55]:
		bx("paint", 18.6, 28.6, 0.0, 0.004, lz, lz + 0.05)
	# 起跑线、号码
	bx("paint", 19.0, 19.06, 0.0, 0.004, -1.3, 1.6)
	_commit(_era_node(1, 4))
	_begin()
	bx("dirt", 18.6, 28.6, -0.22, -0.005, -10.5, -1.35)
	_commit(_era_node(1, 1))
	_begin()
	bx("turf", 18.6, 28.6, -0.22, -0.005, -10.5, -1.35)
	_commit(_era_node(2, 4))
	# --- 光荣榜（童年）：两条腿的玻璃橱窗，红纸一排排
	var hb := _era_node(0, 0)
	_begin()
	var hx := 6.65
	for lx in [hx - 0.62, hx + 0.62]:
		bx("metal", lx - 0.025, lx + 0.025, 0.0, 2.05, ZW + 0.04, ZW + 0.09)
	bx("wood_red", hx - 0.7, hx + 0.7, 1.0, 2.05, ZW + 0.04, ZW + 0.16)
	bx("paper", hx - 0.64, hx + 0.64, 1.05, 1.86, ZW + 0.16, ZW + 0.165)
	for k in 7:
		bx("sign_red", hx - 0.6 + k * 0.175, hx - 0.47 + k * 0.175, 1.1, 1.62, ZW + 0.165, ZW + 0.17)
		bx("goods", hx - 0.58 + k * 0.175, hx - 0.49 + k * 0.175, 1.45, 1.58, ZW + 0.17, ZW + 0.173, Color("#d8cdb6"))
	bx("sign_red", hx - 0.72, hx + 0.72, 2.05, 2.2, ZW + 0.02, ZW + 0.18)
	_commit(hb)
	_era_label(hb, "光 荣 榜", Vector3(hx, 1.95, ZW + 0.175), 0.0036, Color("#e8c96a"))
	# --- 校门口接孩子的
	_begin()
	_bike(Vector3(5.85, 0, -1.0), 0.06, false, "metal")
	_bike(Vector3(6.65, 0, -1.6), -0.05, false, "metal_green")
	bx("bamboo", 6.0, 6.32, 0.8, 1.05, -1.78, -1.42)
	_bike(Vector3(7.1, 0, -2.05), 0.1, false, "sign_red")
	_commit(_era_node(0, 0))
	_begin()
	_ebike(Vector3(5.6, 0, -1.05), Color("#e8e6e0"))
	_ebike(Vector3(6.75, 0, -1.7), Color("#3f6c9a"))
	_bike(Vector3(7.0, 0, -2.15), 0.06, false, "metal")
	_commit(_era_node(1, 1))
	_begin()
	_car(4.3, 7.65, -1.45, Color("#6e2a2a"))
	_commit(_era_node(2, 2))
	_begin()
	_car(4.3, 7.65, -1.45, Color("#d8d8d4"))
	_commit(_era_node(3, 3))
	_begin()
	_oldie(4.55, -1.55, 1.68, Color("#3f4a5a"), Color("#2f2f33"), Color("#c9c6c0"), true)
	_oldie(5.35, -1.85, 1.62, Color("#8a3b3b"), Color("#3a3634"), Color("#d9d6d0"), false)
	_oldie(6.25, -1.5, 1.72, Color("#5b6b4e"), Color("#2b2b2e"), Color("#b9b6b0"), false)
	_oldie(7.15, -1.9, 1.6, Color("#7a6a8a"), Color("#3a3634"), Color("#e2dfd8"), true)
	# 一辆老年代步车
	_ebike(Vector3(6.7, 0, -2.25), Color("#c8b48a"))
	_commit(_era_node(4, 4))


## 一扇铁栅门：铰链在 hinge，朝 yaw 方向打开（门扇在 Basis(UP, yaw) 的 X 方向上）
func _iron_leaf(hinge: Vector3, yaw: float) -> void:
	var w := 0.85
	var h := 1.85
	var u := Vector3(cos(yaw), 0, -sin(yaw))
	for y in [0.12, 0.95, h - 0.06]:
		bc("metal_green", hinge + u * (w / 2.0) + Vector3(0, y, 0), Vector3(w, 0.045, 0.03), yaw)
	var k := 0.0
	while k <= w + 0.001:
		bc("metal_green", hinge + u * k + Vector3(0, h / 2.0 + 0.02, 0), Vector3(0.022, h - 0.04, 0.022), yaw)
		cyl("metal_green", hinge + u * k + Vector3(0, h, 0), 0.025, 0.0, 0.1, 4)
		k += w / 7.0
	# 中间一道铁皮，刷了块红漆写的校徽（就一块红）
	bc("metal_green", hinge + u * (w / 2.0) + Vector3(0, 0.55, 0), Vector3(w, 0.5, 0.012), yaw)


## 电动伸缩门：缩在左门柱边上（菱形的不锈钢格子）、门头一个控制箱
func _slide_gate(x0: float, x1: float) -> void:
	var z := ZW - 0.23
	var n := 9
	var h := 1.4
	for i in n + 1:
		var x := lerpf(x0, x1 - 0.22, float(i) / float(n))
		bx("chrome", x - 0.015, x + 0.015, 0.06, h, z - 0.015, z + 0.015)
		if i < n:
			var xn := lerpf(x0, x1 - 0.22, float(i + 1) / float(n))
			tube("chrome", PackedVector3Array([Vector3(x, 0.15, z), Vector3(xn, h - 0.08, z)]), 0.008, 3)
			tube("chrome", PackedVector3Array([Vector3(x, h - 0.08, z), Vector3(xn, 0.15, z)]), 0.008, 3)
	bx("chrome", x0, x1 - 0.22, h - 0.03, h, z - 0.03, z + 0.03)
	# 门头
	bx("metal_white", x1 - 0.25, x1, 0.04, 1.62, z - 0.14, z + 0.14)
	bx("goods", x1 - 0.23, x1 - 0.02, 1.4, 1.55, z + 0.14, z + 0.145, Color("#3a7fb8"))
	bx("goods", x1 - 0.2, x1 - 0.05, 0.9, 1.0, z + 0.14, z + 0.145, Color("#c84a3a"))
	for wx in [x0 + 0.05, x1 - 0.12]:
		cyl("rubber", Vector3(wx, 0.0, z), 0.04, 0.04, 0.06, 8)


func _board_frame(x0: float, x1: float, face: String) -> void:
	bx("wood", x0 - 0.06, x1 + 0.06, 0.92, 2.3, ZB, ZB + 0.03)
	bx(face, x0, x1, 0.97, 2.25, ZB + 0.03, ZB + 0.04)
	# 粉笔槽
	bx("wood_light", x0, x1, 0.92, 0.96, ZB + 0.03, ZB + 0.11)
	for k in 4:
		bx("chalk", x0 + 0.3 + k * 0.09, x0 + 0.37 + k * 0.09, 0.96, 0.975, ZB + 0.05, ZB + 0.065)
	bx("goods", x1 - 0.5, x1 - 0.32, 0.96, 0.99, ZB + 0.05, ZB + 0.1, Color("#6e5a3e"))


## 双人木课桌（桌斗、铁腿）+ 两把木椅子，朝后墙（-Z）
func _desk_pair(cx: float, cz: float) -> void:
	var y := Y0
	bx("wood_light", cx - 0.55, cx + 0.55, y + 0.68, y + 0.72, cz - 0.22, cz + 0.22)
	bx("wood_light", cx - 0.53, cx + 0.53, y + 0.5, y + 0.52, cz - 0.2, cz + 0.16)
	bx("wood_light", cx - 0.55, cx + 0.55, y + 0.5, y + 0.68, cz - 0.22, cz - 0.2)
	for dx in [-0.52, 0.52]:
		for dz in [-0.19, 0.19]:
			bx("metal", cx + dx - 0.015, cx + dx + 0.015, y, y + 0.68, cz + dz - 0.015, cz + dz + 0.015)
		bx("metal", cx + dx - 0.012, cx + dx + 0.012, y + 0.12, y + 0.14, cz - 0.19, cz + 0.19)
	# 桌上：书、铁皮文具盒
	for sx in [-0.27, 0.27]:
		var bxp: float = cx + float(sx)
		if _rng.randf() < 0.75:
			bc("goods", Vector3(bxp, y + 0.735, cz - 0.02), Vector3(0.26, 0.025, 0.19), _rng.randf_range(-0.2, 0.2), 0.0, [Color("#e6dfcf"), Color("#c9d6c0"), Color("#d8c39a")][_rng.randi() % 3])
		if _rng.randf() < 0.6:
			bc("goods", Vector3(bxp + 0.12, y + 0.735, cz - 0.15), Vector3(0.2, 0.025, 0.06), 0.0, 0.0, [Color("#3d6a8f"), Color("#b84a3a"), Color("#4f7d5c")][_rng.randi() % 3])
		_chair(bxp, cz + 0.47, "wood_light", "metal")


func _desk_single(cx: float, cz: float) -> void:
	var y := Y0
	bx("desk_blue", cx - 0.29, cx + 0.29, y + 0.7, y + 0.73, cz - 0.21, cz + 0.21)
	bx("metal_white", cx - 0.27, cx + 0.27, y + 0.5, y + 0.52, cz - 0.19, cz + 0.15)
	bx("metal_white", cx - 0.27, cx + 0.27, y + 0.52, y + 0.7, cz - 0.2, cz - 0.19)
	for dx in [-0.25, 0.25]:
		bx("metal", cx + dx - 0.016, cx + dx + 0.016, y, y + 0.7, cz - 0.016, cz + 0.016)
		bx("metal", cx + dx - 0.02, cx + dx + 0.02, y, y + 0.02, cz - 0.2, cz + 0.2)
	if _rng.randf() < 0.7:
		bc("goods", Vector3(cx, y + 0.745, cz), Vector3(0.24, 0.025, 0.18), _rng.randf_range(-0.2, 0.2), 0.0, [Color("#e6dfcf"), Color("#f0c94a"), Color("#d8c39a")][_rng.randi() % 3])
	_chair(cx, cz + 0.45, "desk_blue", "metal")


func _chair(cx: float, cz: float, seat: String, leg: String) -> void:
	var y := Y0
	bx(seat, cx - 0.17, cx + 0.17, y + 0.4, y + 0.43, cz - 0.15, cz + 0.15)
	bx(seat, cx - 0.17, cx + 0.17, y + 0.58, y + 0.78, cz + 0.13, cz + 0.155)
	for dx in [-0.15, 0.15]:
		for dz in [-0.13, 0.13]:
			bx(leg, cx + dx - 0.012, cx + dx + 0.012, y, y + 0.4, cz + dz - 0.012, cz + dz + 0.012)
		bx(leg, cx + dx - 0.012, cx + dx + 0.012, y + 0.4, y + 0.78, cz + 0.13, cz + 0.155)


## 电动车：两个小轮、踏板、车身、车把、前筐、后头一个箱子
func _ebike(at: Vector3, col: Color) -> void:
	var r := 0.22
	_ring_b("rubber", at + Vector3(-0.55, r, 0), r, 0.04, Basis())
	_ring_b("rubber", at + Vector3(0.55, r, 0), r, 0.04, Basis())
	bc("chrome", at + Vector3(-0.55, r, 0), Vector3(0.12, 0.12, 0.06))
	bc("chrome", at + Vector3(0.55, r, 0), Vector3(0.12, 0.12, 0.06))
	bc("goods", at + Vector3(-0.05, 0.36, 0), Vector3(0.75, 0.14, 0.26), 0.0, 0.0, col)
	Kit.box_into(_tool("goods"), Vector3(0.12, 0.6, 0.26), Transform3D(Basis(Vector3.BACK, -0.35), at + Vector3(0.4, 0.62, 0)), col)
	Kit.box_into(_tool("goods"), Vector3(0.45, 0.22, 0.26), Transform3D(Basis(), at + Vector3(-0.32, 0.55, 0)), col)
	bc("rubber", at + Vector3(-0.28, 0.7, 0), Vector3(0.5, 0.08, 0.26))
	tube("metal", PackedVector3Array([at + Vector3(0.5, 0.92, -0.3), at + Vector3(0.5, 0.95, 0.3)]), 0.015, 5)
	bc("metal", at + Vector3(0.62, 0.82, 0), Vector3(0.18, 0.15, 0.24))
	bc("goods", at + Vector3(-0.66, 0.78, 0), Vector3(0.28, 0.22, 0.3), 0.0, 0.0, Color("#2b2a33"))


## 轿车：车身、车舱（玻璃）、车顶、四个轮子、前后灯
func _car(x0: float, x1: float, zc: float, col: Color) -> void:
	var w := 0.78
	bx("carpaint", x0 + 0.05, x1 - 0.05, 0.3, 0.78, zc - w, zc + w, col)
	bx("carpaint", x0, x1, 0.32, 0.62, zc - w + 0.02, zc + w - 0.02, col)
	# 车身腰线一道深色、门把手
	bx("rubber", x0 + 0.02, x1 - 0.02, 0.6, 0.625, zc - w - 0.005, zc + w + 0.005)
	# 车舱：玻璃，前后挡风斜着
	var c0 := x0 + 0.85
	var c1 := x1 - 1.15
	bx("glass", c0, c1, 0.78, 1.18, zc - w + 0.1, zc + w - 0.1, Color(0.0, 0.4, 0.6))
	Kit.box_into(_tool("glass"), Vector3(0.5, 0.04, w * 2.0 - 0.22), Transform3D(Basis(Vector3.BACK, deg_to_rad(-48.0)), Vector3(c1 + 0.18, 0.98, zc)), Color(0.0, 0.4, 0.6))
	Kit.box_into(_tool("glass"), Vector3(0.45, 0.04, w * 2.0 - 0.22), Transform3D(Basis(Vector3.BACK, deg_to_rad(52.0)), Vector3(c0 - 0.15, 0.98, zc)), Color(0.0, 0.4, 0.6))
	bx("carpaint", c0 - 0.05, c1 + 0.05, 1.18, 1.24, zc - w + 0.12, zc + w - 0.12, col)
	# 车门的柱子
	bx("carpaint", (c0 + c1) / 2.0 - 0.04, (c0 + c1) / 2.0 + 0.04, 0.78, 1.18, zc - w + 0.09, zc + w - 0.09, col)
	# 轮子
	for wx in [x0 + 0.65, x1 - 0.7]:
		for wz in [zc - w + 0.1, zc + w - 0.1]:
			_ring_b("rubber", Vector3(wx, 0.27, wz), 0.19, 0.085, Basis())
			bc("chrome", Vector3(wx, 0.27, wz + (0.06 if wz > zc else -0.06)), Vector3(0.2, 0.2, 0.02))
	# 前后灯、保险杠
	bx("paint", x1 - 0.02, x1 + 0.01, 0.55, 0.64, zc - w + 0.1, zc - w + 0.38)
	bx("paint", x1 - 0.02, x1 + 0.01, 0.55, 0.64, zc + w - 0.38, zc + w - 0.1)
	bx("sign_red", x0 - 0.01, x0 + 0.02, 0.58, 0.68, zc - w + 0.08, zc - w + 0.34)
	bx("sign_red", x0 - 0.01, x0 + 0.02, 0.58, 0.68, zc + w - 0.34, zc + w - 0.08)
	bx("rubber", x0 - 0.04, x0 + 0.1, 0.3, 0.42, zc - w + 0.02, zc + w - 0.02)
	bx("rubber", x1 - 0.1, x1 + 0.04, 0.3, 0.42, zc - w + 0.02, zc + w - 0.02)
	# 车牌（不写字）
	bx("goods", x1 + 0.03, x1 + 0.04, 0.42, 0.52, zc - 0.2, zc + 0.2, Color("#2f5a9a"))


## 一个等孙辈的老人（静物）：裤子、外套、胳膊背在后头、脑袋、帽子或白头发
func _oldie(x: float, z: float, h: float, coat: Color, pants: Color, hair: Color, cap: bool) -> void:
	var k := h / 1.7
	var skin := Color("#c99a78")
	for dx in [-0.075, 0.075]:
		bx("goods", x + dx - 0.06, x + dx + 0.06, 0.06 * k, 0.8 * k, z - 0.07, z + 0.07, pants)
		bx("goods", x + dx - 0.065, x + dx + 0.07, 0.0, 0.07 * k, z - 0.11, z + 0.08, Color("#2a2522"))
	cyl("goods", Vector3(x, 0.75 * k, z), 0.17 * k, 0.16 * k, 0.6 * k, 10, coat)
	cyl("goods", Vector3(x, 1.35 * k, z), 0.16 * k, 0.07 * k, 0.07 * k, 10, coat)
	for dx in [-0.19, 0.19]:
		Kit.box_into(_tool("goods"), Vector3(0.09, 0.55, 0.1) * k, Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(x + dx * k, 1.1 * k, z - 0.04)), coat)
	cyl("goods", Vector3(x, 1.4 * k, z), 0.045 * k, 0.045 * k, 0.07 * k, 8, skin)
	cyl("goods", Vector3(x, 1.46 * k, z), 0.085 * k, 0.1 * k, 0.12 * k, 10, skin)
	cyl("goods", Vector3(x, 1.58 * k, z), 0.1 * k, 0.07 * k, 0.1 * k, 10, skin)
	if cap:
		cyl("goods", Vector3(x, 1.6 * k, z), 0.11 * k, 0.1 * k, 0.08 * k, 10, Color("#3a3a3e"))
		bx("goods", x - 0.09 * k, x + 0.09 * k, 1.6 * k, 1.615 * k, z + 0.05, z + 0.17, Color("#3a3a3e"))
	else:
		cyl("goods", Vector3(x, 1.6 * k, z - 0.01), 0.105 * k, 0.06 * k, 0.09 * k, 10, hair)


# ======================================================================
# 年代、季节、每帧
# ======================================================================

## 黑板报每学期换一版（按季节：春、夏、秋、冬各一版）
func set_season(season: String) -> void:
	super.set_season(season)
	if _bulletin.size() < 2:
		return
	var heads := {"spring": "春天来了", "summer": "安全过暑假", "autumn": "新学期 新气象", "winter": "迎接新年"}
	var bodies := {
		"spring": "植树节\n我们班种了三棵树\n——二年级一班",
		"summer": "不到河边玩水\n过马路看红绿灯",
		"autumn": "开学第一天\n我的新同桌\n比我矮一点",
		"winter": "元旦联欢会\n每人出一个节目",
	}
	(_bulletin[0] as Label3D).text = str(heads.get(season, heads.autumn))
	(_bulletin[1] as Label3D).text = str(bodies.get(season, bodies.autumn))


## 每帧：镜头附近的灯；教室的灯白天开、天黑了关（夜里学校黑着）
func tick(delta: float, cam_x: float) -> void:
	super.tick(delta, cam_x)
	var dark := 0.0
	if stage != null:
		var v: Variant = stage.get("_lamp_on")
		if v != null:
			dark = clampf(float(v), 0.0, 1.0)
	for l in _class_lamps:
		l[1] = float(l[1]) * (1.0 - dark)
