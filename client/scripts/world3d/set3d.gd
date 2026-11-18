extends Node3D
## 实时 3D 一张图的搭法底子（street3d、building3d、river3d、primary3d、middle3d 都从这儿派生）。
## 坐标：米。X = 2D 的 x / 100，这张图最下一层地面 Y = 0，人走的那条线 Z = 0，往后是 -Z，镜头在 +Z。
## 搭法：大部分是盒子和圆柱，按材质并成一张网格（一种材质一个 draw call）；材质全在 surface.gdshader 里现算（砖缝、方砖缝、木纹）。
##   _begin() → bx/bc/cyl/tube/wall/window… 往批次里加 → _commit(parent) 一种材质出一个 MeshInstance3D。
##   材质表 MATS 是大家共用的；派生的图要自己的材质就在 build() 开头往 extra_mats / extra_glow 里加（同样的格式），别改 MATS 的老条目。
## 灯：_add_lamp 加进 lamps，stage3d 按钟点开、tick 只开镜头附近的（兼容渲染器一个东西最多吃八盏灯）。
## 年代：_era_nodes 里 [节点, 从第几个年代起有, 到第几个止]，set_look 整批开关。季节：_foliage 里的树冠换颜色、冬天藏起来。
## stage：Stage3D（build 之前塞进来），要读世界的状态（屋里有什么、谁在哪）从 stage.world 拿。

const Kit := preload("res://scripts/world3d/kit3d.gd")
const SURF := preload("res://shaders/3d/surface.gdshader")
const FOLIAGE := preload("res://shaders/3d/foliage.gdshader")
const P := preload("res://scripts/ui/palette.gd")

const FLOOR_H := 3.1  ## 一层多高

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
## 派生的图自己加的材质、发光（格式同 MATS / GLOW），build() 开头填
var extra_mats: Dictionary = {}
var extra_glow: Dictionary = {}
var stage = null              ## Stage3D（build 之前塞进来）

var lamps: Array = []         ## [OmniLight3D, 亮度系数]（stage3d 按钟点开关）
var _mats: Dictionary = {}
var _st: Dictionary = {}      ## 当前批次：材质名 → SurfaceTool
var _era_nodes: Array = []    ## [节点, 从哪个年代起有, 到哪个年代止]
var _foliage: Array = []      ## 树冠（季节换颜色）
var _rng := RandomNumberGenerator.new()
var _labels: Dictionary = {}  ## 店招 → Label3D
var look := "childhood"
const LOOKS := ["childhood", "teen", "young", "middle", "old"]


## 派生的图覆盖：照着 2D 那张图（content/maps/<id>.yaml）搭出来
func build(_sc: Dictionary, p_look: String, season: String) -> void:
	look = p_look
	set_look(look)
	set_season(season)


# ======================================================================
# 批次：同一种材质的东西并成一张网格
# ======================================================================

func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var d: Array = extra_mats[key] if extra_mats.has(key) else MATS[key]
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
	var g: Array = extra_glow.get(key, GLOW.get(key, []))
	if not g.is_empty():
		m.set_shader_parameter("emit", float(g[0]))
		m.set_shader_parameter("emit_col", Color(str(g[1])))
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
# ======================================================================
# 年代、季节
# ======================================================================

## 年代：_era_nodes 整批开关（派生的图要换店招之类，覆盖了记得 super.set_look）
func set_look(p_look: String) -> void:
	look = p_look
	var i := LOOKS.find(look)
	if i < 0:
		i = 0
	for e in _era_nodes:
		(e[0] as Node3D).visible = i >= int(e[1]) and i <= int(e[2])



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
