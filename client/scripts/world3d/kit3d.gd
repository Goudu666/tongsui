extends RefCounted
## 实时 3D 的网格工具：放样（人身子、胳膊腿、裙子、鞋）、椭球（头）、发壳（头发）、管子（电线、树枝）。
## 都在代码里现搭，不带模型文件：改一个数，整个人、整条街一起变（同岁美术一向是程序化的，见 tools/art/README.md）。
## 单位是米；人朝 +Z（对着镜头），+Y 朝上。

const TAU_ := TAU


## 放样：沿 Y 轴一圈一圈的椭圆连起来。rings = [[y, 半宽 rx, 半厚 rz, 中心 x 偏, 中心 z 偏], ...]（后两个可省）
## 两头可以封口（顶上、底下各收成一个点）。seg = 一圈几段
static func loft(rings: Array, seg := 16, cap_bottom := true, cap_top := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rings.size()
	var pts: Array = []
	for r in rings:
		var row := PackedVector3Array()
		var cx: float = r[3] if r.size() > 3 else 0.0
		var cz: float = r[4] if r.size() > 4 else 0.0
		for i in seg:
			var a := TAU_ * float(i) / float(seg)
			row.append(Vector3(cx + sin(a) * float(r[1]), float(r[0]), cz + cos(a) * float(r[2])))
		pts.append(row)
	for k in n - 1:
		var v0: float = float(k) / float(n - 1)
		var v1: float = float(k + 1) / float(n - 1)
		for i in seg:
			var j := (i + 1) % seg
			var u0 := float(i) / float(seg)
			var u1 := float(i + 1) / float(seg)
			_quad(st, pts[k][i], pts[k][j], pts[k + 1][j], pts[k + 1][i], Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1))
	if cap_bottom:
		var c := Vector3(rings[0][3] if rings[0].size() > 3 else 0.0, float(rings[0][0]), rings[0][4] if rings[0].size() > 4 else 0.0)
		for i in seg:
			_tri(st, c, pts[0][i], pts[0][(i + 1) % seg])
	if cap_top:
		var r: Array = rings[n - 1]
		var c := Vector3(r[3] if r.size() > 3 else 0.0, float(r[0]), r[4] if r.size() > 4 else 0.0)
		for i in seg:
			_tri(st, c, pts[n - 1][(i + 1) % seg], pts[n - 1][i])
	st.generate_normals()
	return st.commit()


## 两头圆的一截（胳膊、腿）：从 0 往 -Y 长 len，上粗 r0、下细 r1，两头半个球收口
static func limb(length: float, r0: float, r1: float, seg := 12, flat := 1.0) -> ArrayMesh:
	var rings: Array = []
	var k := 4
	for i in range(k, 0, -1):  # 上头半球
		var a := PI / 2.0 * float(i) / float(k)
		rings.append([sin(a) * r0, cos(a) * r0, cos(a) * r0 * flat])
	var steps := 5
	for i in steps + 1:
		var t := float(i) / float(steps)
		var r := lerpf(r0, r1, t)
		# 中间略鼓一点（肌肉），不是直筒
		r *= 1.0 + 0.06 * sin(t * PI)
		rings.append([-t * length, r, r * flat])
	for i in range(1, k + 1):  # 下头半球
		var a := PI / 2.0 * float(i) / float(k)
		rings.append([-length - sin(a) * r1, cos(a) * r1, cos(a) * r1 * flat])
	rings.reverse()
	return loft(rings, seg, false, false)


## 椭球（头、手、球）
static func ellipsoid(r: Vector3, seg := 24, rings := 16) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rings:
		var t0 := PI * float(j) / float(rings)
		var t1 := PI * float(j + 1) / float(rings)
		for i in seg:
			var p0 := TAU_ * float(i) / float(seg)
			var p1 := TAU_ * float(i + 1) / float(seg)
			var a := _sph(t0, p0, r)
			var b := _sph(t0, p1, r)
			var c := _sph(t1, p1, r)
			var d := _sph(t1, p0, r)
			_quad_n(st, a, b, c, d, r)
	return st.commit()


static func _sph(theta: float, phi: float, r: Vector3) -> Vector3:
	return Vector3(sin(theta) * sin(phi) * r.x, cos(theta) * r.y, sin(theta) * cos(phi) * r.z)


## 头发壳：贴着头的一层，按发际线收边，表面一缕一缕起伏。
## r 头的半径（椭球），hairline(phi) 给出每个方位（phi=0 正脸，±PI 后脑）头发往下盖到多远（弧度，从头顶量起）。
## lift 头发离头皮多厚，clump 一缕缕的起伏多大，strands 一圈多少缕
static func hair_shell(r: Vector3, hairline: Callable, lift := 0.08, clump := 0.035, strands := 9.0, seg := 40, rows := 14) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for i in seg + 1:
		var phi := -PI + TAU_ * float(i) / float(seg)
		var tmax: float = hairline.call(phi)
		var col := PackedVector3Array()
		for j in rows + 1:
			var t := float(j) / float(rows)
			var theta := t * tmax
			# 一缕一缕：沿方位起伏，越往发梢越明显；发梢往里收一点（贴回头皮）
			var bump := clump * sin(phi * strands + sin(theta * 3.0) * 0.8) * smoothstep(0.1, 0.7, t)
			var tuck := 0.55 * smoothstep(0.82, 1.0, t)
			var k := 1.0 + lift * (1.0 - tuck) + bump * (1.0 - tuck)
			# 头顶蓬一点
			k += 0.03 * (1.0 - t)
			col.append(_sph(theta, phi, r * k))
		grid.append(col)
	for i in seg:
		for j in rows:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var c: Vector3 = grid[i + 1][j + 1]
			var d: Vector3 = grid[i][j + 1]
			var uv := Vector2(float(i) / seg, float(j) / rows)
			var uv2 := Vector2(float(i + 1) / seg, float(j + 1) / rows)
			_quad(st, a, d, c, b, uv, Vector2(uv.x, uv2.y), uv2, Vector2(uv2.x, uv.y))
	st.generate_normals()
	return st.commit()


## 一根管子沿着几个点走（电线、树枝、鱼竿）
static func tube(points: PackedVector3Array, radius: float, seg := 6, r_end := -1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	tube_into(st, points, radius, seg, r_end)
	return st.commit()


## 管子加进一个批次：每个顶点都带颜色、法线、UV（和 box_into、cyl_into 同一种格式，能并在一张网格里）
static func tube_into(st: SurfaceTool, points: PackedVector3Array, radius: float, seg := 6, r_end := -1.0, color := Color.WHITE) -> void:
	if r_end < 0.0:
		r_end = radius
	var n := points.size()
	var rings: Array = []
	var norms: Array = []
	for k in n:
		var dir: Vector3
		if k == 0:
			dir = points[1] - points[0]
		elif k == n - 1:
			dir = points[k] - points[k - 1]
		else:
			dir = points[k + 1] - points[k - 1]
		dir = dir.normalized()
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var s := dir.cross(up).normalized()
		var t := s.cross(dir).normalized()
		var r := lerpf(radius, r_end, float(k) / float(max(1, n - 1)))
		var ring := PackedVector3Array()
		var nr := PackedVector3Array()
		for i in seg:
			var a := TAU_ * float(i) / float(seg)
			var d := s * cos(a) + t * sin(a)
			ring.append(points[k] + d * r)
			nr.append(d)
		rings.append(ring)
		norms.append(nr)
	for k in n - 1:
		for i in seg:
			var j := (i + 1) % seg
			# 从外面看：a = 这一圈第 i 个、b = 下一圈第 i 个、c = 下一圈第 j 个、d = 这一圈第 j 个
			var idx := [[k, i], [k + 1, j], [k + 1, i], [k, i], [k, j], [k + 1, j]]
			for q in idx:
				st.set_color(color)
				st.set_normal(norms[q[0]][q[1]])
				st.set_uv(Vector2.ZERO)
				st.add_vertex(rings[q[0]][q[1]])


## 往一个 SurfaceTool 里加一个盒子（街景大量的方块：墙、窗框、货架、招牌），可带变换
static func box_into(st: SurfaceTool, size: Vector3, xf := Transform3D.IDENTITY, color := Color.WHITE) -> void:
	var h := size / 2.0
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[4, 5, 6, 7, Vector3.BACK], [1, 0, 3, 2, Vector3.FORWARD], [5, 1, 2, 6, Vector3.RIGHT],
		[0, 4, 7, 3, Vector3.LEFT], [7, 6, 2, 3, Vector3.UP], [0, 1, 5, 4, Vector3.DOWN]]
	var b := xf.basis
	for f in faces:
		var nrm: Vector3 = (b * (f[4] as Vector3)).normalized()
		var p := [xf * (c[f[0]] as Vector3), xf * (c[f[1]] as Vector3), xf * (c[f[2]] as Vector3), xf * (c[f[3]] as Vector3)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_color(color)
			st.set_normal(nrm)
			st.set_uv(Vector2(0, 0))
			st.add_vertex(p[idx])


## 往 SurfaceTool 里加一根竖着的圆柱（电线杆、桌腿、蒸笼）：底面中心 base，半径 r0（底）r1（顶）
static func cyl_into(st: SurfaceTool, base: Vector3, r0: float, r1: float, h: float, seg := 10, color := Color.WHITE, caps := true) -> void:
	for i in seg:
		var a0 := TAU_ * float(i) / float(seg)
		var a1 := TAU_ * float(i + 1) / float(seg)
		var d0 := Vector3(sin(a0), 0, cos(a0))
		var d1 := Vector3(sin(a1), 0, cos(a1))
		var p00 := base + d0 * r0
		var p01 := base + d1 * r0
		var p10 := base + d0 * r1 + Vector3(0, h, 0)
		var p11 := base + d1 * r1 + Vector3(0, h, 0)
		for v in [[p00, d0], [p11, d1], [p01, d1], [p00, d0], [p10, d0], [p11, d1]]:
			st.set_color(color)
			st.set_normal(v[1])
			st.set_uv(Vector2.ZERO)
			st.add_vertex(v[0])
		if caps:
			var top := base + Vector3(0, h, 0)
			for v in [top, p11, p10]:
				st.set_color(color)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2.ZERO)
				st.add_vertex(v)


static func box(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	box_into(st, size)
	return st.commit()


## 平铺的一片（地面、路面），朝 +Y
static func plane(size: Vector2) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = size
	return p


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_uv(Vector2.ZERO)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## 四边形：从外面看 a 左下、b 右下、c 右上、d 左上（逆时针）。Godot 的正面是顺时针，所以按 a,c,b / a,d,c 出
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ub); st.add_vertex(b)
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(ud); st.add_vertex(d)
	st.set_uv(uc); st.add_vertex(c)


## 椭球用：法线按椭球解析算（比 generate_normals 光滑）
static func _quad_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, r: Vector3) -> void:
	for p in [a, b, c, a, c, d]:
		var v: Vector3 = p
		st.set_normal(Vector3(v.x / (r.x * r.x), v.y / (r.y * r.y), v.z / (r.z * r.z)).normalized())
		st.add_vertex(v)


## 一块不受光的软影子（脚底、桌底的接触阴影：没有 SSAO，靠它把东西「放」在地上）
static func blob_shadow(w: float, d: float, strength := 0.45) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, d)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/3d/blob.gdshader")
	m.set_shader_parameter("strength", strength)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.004
	return mi


## 常用的实色材质（布、塑料、漆）：粗糙度、要不要一点边缘光（布的绒感）
static func mat(c: Color, rough := 0.75, metal := 0.0, rim := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.6
	return m


## 日漫的头：上半个球，下半往下巴收（腮帮子收窄、下巴略往前、略尖），jaw 0 就是椭球
static func anime_head(r: Vector3, jaw := 1.0, seg := 32, rings := 22) -> ArrayMesh:
	# 日漫的头（手办那种）：上半是圆圆的后脑勺和额头（就是 r 这个椭球，发壳贴着它，不动）；
	# 下半：脸颊鼓一点，从颧骨往下顺顺地收到一个小而圆的下巴，下巴略往前、往下；后面下颌往脖子收。
	# 脸的正面稍平一点（眼睛画在一个面上，侧过去也不显小）。jaw：0 小孩（圆、下巴宽、脸颊肉）… 1 大人（脸长一点、下颌清楚）。
	# 网格比参数给的细一点：轮廓是曲线不是折线（手办的脸边要圆润）。
	seg = maxi(seg, 56)
	rings = maxi(rings, 40)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	var kid := 1.0 - clampf(jaw, 0.0, 1.0)
	for j in rings + 1:
		var theta := PI * float(j) / float(rings)
		var row := PackedVector3Array()
		for i in seg + 1:
			var phi := TAU_ * float(i) / float(seg)
			var d := Vector3(sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi))
			var c := cos(phi)                                # 1 正脸 … 0 两侧 … -1 后脑
			var front := clampf(c, 0.0, 1.0)
			var back := clampf(-c, 0.0, 1.0)
			var t := clampf(-d.y, 0.0, 1.0)                  # 0 眼睛那一圈 … 1 下巴底下
			var up := clampf(d.y, 0.0, 1.0)
			var p := Vector3(d.x * r.x, d.y * r.y, d.z * r.z)
			# 脸正面略平：额头到嘴这一块往里收一点点（只收正中，两侧不动）
			var mid := (1.0 - smoothstep(0.35, 0.85, up)) * (1.0 - smoothstep(0.55, 0.95, t))
			p.z -= r.z * 0.045 * pow(front, 3.0) * mid
			# 下半张脸往里收：颧骨下面才开始，越往下越窄，到下巴是一个小圆
			var taper := pow(smoothstep(0.12, 1.0, t), 1.25)
			var narrow := lerpf(0.12, 0.29, jaw) * taper
			# 正面比两侧略多收一点：下颌线从耳朵下面斜着走向下巴；但到下巴尖又放回来一点（圆下巴，不是尖锥）
			narrow += lerpf(0.0, 0.06, jaw) * taper * front * (1.0 - smoothstep(0.75, 1.0, t))
			p.x *= 1.0 - narrow
			# 脸颊：眼睛下面、偏外的那一块鼓一点（小孩更肉）
			var cheek := exp(-pow((t - 0.32) / 0.2, 2.0)) * exp(-pow((absf(sin(phi)) - 0.62) / 0.3, 2.0)) * front
			p += Vector3(d.x * r.x, 0.0, d.z * r.z * 0.6) * cheek * lerpf(0.022, 0.065, kid)
			# 下巴往前、往下一点（大人多一点，脸显得长、下巴尖而不锐）
			var fw := smoothstep(-0.1, 0.75, c)                # 前半边一大片一起动（不只正中一条），下巴才是圆的
			p.z += r.z * lerpf(0.08, 0.16, jaw) * pow(t, 2.2) * fw
			p.y -= r.y * lerpf(0.0, 0.035, jaw) * pow(t, 3.0) * fw
			# 后面、下面往脖子收：下颌底下斜着往后上走
			p.z *= 1.0 - 0.32 * pow(t, 1.4) * back
			p.y *= 1.0 - 0.1 * pow(t, 2.0) * back
			row.append(p)
		grid.append(row)
	for j in rings:
		for i in seg:
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j][i + 1]
			var c: Vector3 = grid[j + 1][i + 1]
			var d: Vector3 = grid[j + 1][i]
			for p in [a, b, c, a, c, d]:
				st.set_uv(Vector2.ZERO)
				st.add_vertex(p)
	st.index()
	st.generate_normals()
	return st.commit()


## 一缕头发：沿 path 走的扁管子。截面是椭圆，宽的一边横着贴头皮，薄的一边朝 outs（往外）；
## 根上略窄、三分之一处最宽、到发梢收成尖。几缕可以加进同一个 SurfaceTool 并成一张网格。
static func lock_into(st: SurfaceTool, path: PackedVector3Array, outs: PackedVector3Array, w0: float, t0: float, seg := 8, tip := 0.0) -> void:
	var n := path.size()
	var rings: Array = []
	for k in n:
		var tg: Vector3 = (path[mini(k + 1, n - 1)] - path[maxi(k - 1, 0)]).normalized()
		var o: Vector3 = outs[k] - tg * outs[k].dot(tg)
		if o.length() < 1e-5:
			o = Vector3.UP.cross(tg)
		o = o.normalized()
		var side := tg.cross(o).normalized()
		var t := float(k) / float(n - 1)
		var f := lerpf(0.72, 1.0, t / 0.3) if t < 0.3 else pow(maxf(0.0, 1.0 - (t - 0.3) / 0.7), 0.85)
		f = maxf(f, tip * (1.0 - pow(t, 6.0) * 0.3))  # tip > 0：齐的发梢（剪平的刘海）
		var row := PackedVector3Array()
		for i in seg:
			var a := TAU_ * float(i) / float(seg)
			row.append(path[k] + side * cos(a) * w0 * f + o * sin(a) * t0 * maxf(f, 0.0))
		rings.append(row)
	for k in n - 1:
		for i in seg:
			var i2 := (i + 1) % seg
			_quad(st, rings[k][i2], rings[k][i], rings[k + 1][i], rings[k + 1][i2], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
