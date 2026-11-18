extends RefCounted
## 实时 3D 的网格工具：放样（人身子、胳膊腿、裙子、鞋）、椭球（头）、发壳（头发）、管子（电线、树枝）。
## 都在代码里现搭，不带模型文件：改一个数，整个人、整条街一起变（同岁美术一向是程序化的，见 tools/art/README.md）。
## 单位是米；人朝 +Z（对着镜头），+Y 朝上。

const TAU_ := TAU


## 放样：沿 Y 轴一圈一圈的椭圆连起来。rings = [[y, 半宽 rx, 半厚 rz, 中心 x 偏, 中心 z 偏, 明暗, 褶], ...]（后面的可省）
## 明暗：1 不变、小于 1 往暗压（顶点色，关节、领口底下、裙褶里的「窝」，toon 用 COLOR.r 压暗）；
## 褶：这一圈按 pleats 个褶往外鼓多少（半径的几分之几：裙摆的百褶）。两头可以封口（收成一个点）。seg = 一圈几段
static func loft(rings: Array, seg := 16, cap_bottom := true, cap_top := true, pleats := 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	loft_into(st, rings, seg, cap_bottom, cap_top, Transform3D.IDENTITY, pleats)
	st.generate_normals()
	return st.commit()


## 放样加进一个批次（几段并成一张网格：手掌 + 大拇指、鞋），xf 把整段挪 / 转过去
static func loft_into(st: SurfaceTool, rings: Array, seg := 16, cap_bottom := true, cap_top := true, xf := Transform3D.IDENTITY, pleats := 0) -> void:
	var n := rings.size()
	var pts: Array = []
	var shd: Array = []
	for r in rings:
		var row := PackedVector3Array()
		var cx: float = r[3] if r.size() > 3 else 0.0
		var cz: float = r[4] if r.size() > 4 else 0.0
		var pl: float = r[6] if r.size() > 6 else 0.0
		for i in seg:
			var a := TAU_ * float(i) / float(seg)
			var k := 1.0
			if pleats > 0 and pl != 0.0:
				# 褶：圆的一半是鼓出来的面，一半是折进去的窝（不是正弦波，像压过的褶）
				var w := absf(sin(a * float(pleats) * 0.5))
				k += pl * (pow(w, 0.6) - 0.6)
			row.append(xf * Vector3(cx + sin(a) * float(r[1]) * k, float(r[0]), cz + cos(a) * float(r[2]) * k))
		pts.append(row)
		shd.append(float(r[5]) if r.size() > 5 else 1.0)
	for k in n - 1:
		var v0: float = float(k) / float(n - 1)
		var v1: float = float(k + 1) / float(n - 1)
		var c0 := Color(shd[k], shd[k], shd[k])
		var c1 := Color(shd[k + 1], shd[k + 1], shd[k + 1])
		for i in seg:
			var j := (i + 1) % seg
			var u0 := float(i) / float(seg)
			var u1 := float(i + 1) / float(seg)
			var a: Vector3 = pts[k][i]
			var b: Vector3 = pts[k][j]
			var c: Vector3 = pts[k + 1][j]
			var d: Vector3 = pts[k + 1][i]
			for v in [[a, c0, Vector2(u0, v0)], [c, c1, Vector2(u1, v1)], [b, c0, Vector2(u1, v0)], [a, c0, Vector2(u0, v0)], [d, c1, Vector2(u0, v1)], [c, c1, Vector2(u1, v1)]]:
				st.set_color(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
	if cap_bottom:
		var r0: Array = rings[0]
		var c := xf * Vector3(r0[3] if r0.size() > 3 else 0.0, float(r0[0]), r0[4] if r0.size() > 4 else 0.0)
		var cc := Color(shd[0], shd[0], shd[0])
		for i in seg:
			for v in [c, pts[0][i], pts[0][(i + 1) % seg]]:
				st.set_color(cc)
				st.set_uv(Vector2.ZERO)
				st.add_vertex(v)
	if cap_top:
		var r: Array = rings[n - 1]
		var c := xf * Vector3(r[3] if r.size() > 3 else 0.0, float(r[0]), r[4] if r.size() > 4 else 0.0)
		var cc := Color(shd[n - 1], shd[n - 1], shd[n - 1])
		for i in seg:
			for v in [c, pts[n - 1][(i + 1) % seg], pts[n - 1][i]]:
				st.set_color(cc)
				st.set_uv(Vector2.ZERO)
				st.add_vertex(v)


## 两头圆的一截（胳膊、腿）：从 0 往 -Y 长 len，上粗 r0、下细 r1，两头半个球收口。
## bulge 肌肉鼓多少、peak 鼓在哪（0 上头 … 1 下头）：大腿、上臂鼓在上三分之一，小腿肚鼓在上头，往手腕 / 脚踝收细。
## 两头的半球压暗一点（关节的窝）
static func limb(length: float, r0: float, r1: float, seg := 12, flat := 1.0, bulge := 0.06, peak := 0.5, end_shade := 0.86) -> ArrayMesh:
	var rings: Array = []
	var k := 4
	for i in range(k, 0, -1):  # 上头半球
		var a := PI / 2.0 * float(i) / float(k)
		rings.append([sin(a) * r0, cos(a) * r0, cos(a) * r0 * flat, 0.0, 0.0, lerpf(1.0, end_shade, float(i) / float(k))])
	var steps := 8
	for i in steps + 1:
		var t := float(i) / float(steps)
		var r := lerpf(r0, r1, t)
		# 中间鼓一点（肌肉），鼓的地方靠上，往下收得快：胳膊腿有个形，不是直筒
		var u := t / peak if t < peak else 1.0 - (t - peak) / (1.0 - peak)
		r *= 1.0 + bulge * sin(clampf(u, 0.0, 1.0) * PI * 0.5)
		rings.append([-t * length, r, r * flat])
	for i in range(1, k + 1):  # 下头半球
		var a := PI / 2.0 * float(i) / float(k)
		rings.append([-length - sin(a) * r1, cos(a) * r1, cos(a) * r1 * flat, 0.0, 0.0, lerpf(1.0, end_shade, float(i) / float(k))])
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


## 头发壳：贴着头的一层，按发际线收边，表面是光滑的（手办上漆那样），一缕一缕的起伏交给上面的发束。
## r 头的半径（椭球），hairline(phi) 给出每个方位（phi=0 正脸，±PI 后脑）头发往下盖到多远（弧度，从头顶量起）。
## lift 头发离头皮多厚；clump、strands 留着兼容（clump 0 就是光的）。
## 顶点色 = 发丝方向（从头顶往下）+ 从根到梢，UV.x = 方位（头发材质靠它画天使环、根深梢浅）
static func hair_shell(r: Vector3, hairline: Callable, lift := 0.08, clump := 0.0, strands := 9.0, seg := 40, rows := 14) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	var tans: Array = []
	for i in seg + 1:
		var phi := -PI + TAU_ * float(i) / float(seg)
		var tmax: float = hairline.call(phi)
		var col := PackedVector3Array()
		var tcol := PackedVector3Array()
		for j in rows + 1:
			var t := float(j) / float(rows)
			var theta := t * tmax
			var bump := clump * sin(phi * strands + sin(theta * 3.0) * 0.8) * smoothstep(0.1, 0.7, t)
			# 发际线那一圈往里收（贴回头皮），头顶蓬一点、后脑勺鼓一点
			var tuck := 0.6 * smoothstep(0.8, 1.0, t)
			var k := 1.0 + lift * (1.0 - tuck) + bump * (1.0 - tuck)
			k += 0.035 * (1.0 - t) * (1.0 - t)
			k += 0.02 * smoothstep(0.6, -0.9, cos(phi)) * sin(theta) * (1.0 - tuck)
			col.append(_sph(theta, phi, r * k))
			tcol.append(Vector3(cos(theta) * sin(phi) * r.x, -sin(theta) * r.y, cos(theta) * cos(phi) * r.z).normalized())
		grid.append(col)
		tans.append(tcol)
	for i in seg:
		for j in rows:
			var u0 := float(i) / seg
			var u1 := float(i + 1) / seg
			var v0 := float(j) / rows
			var v1 := float(j + 1) / rows
			var q := [[grid[i][j], tans[i][j], u0, v0], [grid[i + 1][j + 1], tans[i + 1][j + 1], u1, v1], [grid[i][j + 1], tans[i][j + 1], u0, v1],
				[grid[i][j], tans[i][j], u0, v0], [grid[i + 1][j], tans[i + 1][j], u1, v0], [grid[i + 1][j + 1], tans[i + 1][j + 1], u1, v1]]
			for e in q:
				# 法线按椭球解析算：头顶那个点（所有方位挤在一起）也不会出黑点
				var pv: Vector3 = e[0]
				st.set_normal(Vector3(pv.x / (r.x * r.x), pv.y / (r.y * r.y), pv.z / (r.z * r.z)).normalized())
				_hair_v(st, pv, e[1], e[3], e[2])
	st.index()
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


## 一缕头发：沿 path 走的扁管子。截面上面鼓、底下平（像手办雕出来的一片），宽的一边横着贴头皮，鼓的一边朝 outs（往外）；
## 根上略窄、三分之一处最宽、到发梢收成尖。几缕可以加进同一个 SurfaceTool 并成一张网格。
## 顶点色带发丝方向和根→梢（头发材质画天使环用），UV.x 是这一缕的编号（sid < 0 就按位置随机一个）
static func lock_into(st: SurfaceTool, path: PackedVector3Array, outs: PackedVector3Array, w0: float, t0: float, seg := 8, tip := 0.0, sid := -1.0, wide := 0.3) -> void:
	var n := path.size()
	if sid < 0.0:
		sid = fposmod(sin(path[0].dot(Vector3(12.9898, 78.233, 37.719)) * 91.7) * 43758.5453, 1.0)
	var rings: Array = []
	var tans: Array = []
	for k in n:
		var tg: Vector3 = (path[mini(k + 1, n - 1)] - path[maxi(k - 1, 0)]).normalized()
		var o: Vector3 = outs[k] - tg * outs[k].dot(tg)
		if o.length() < 1e-5:
			o = Vector3.UP.cross(tg)
		o = o.normalized()
		var side := tg.cross(o).normalized()
		var t := float(k) / float(n - 1)
		# wide：最宽的地方在哪（0.3 = 三分之一处；长发往后挪，宽着垂下来再收尖）
		var f := lerpf(0.72, 1.0, t / wide) if t < wide else pow(maxf(0.0, 1.0 - (t - wide) / (1.0 - wide)), 0.85)
		f = maxf(f, tip * (1.0 - pow(t, 6.0) * 0.3))  # tip > 0：齐的发梢（剪平的刘海）
		var row := PackedVector3Array()
		for i in seg:
			var a := TAU_ * float(i) / float(seg)
			var sa := sin(a)
			var th := sa if sa > 0.0 else sa * 0.45
			row.append(path[k] + side * cos(a) * w0 * f + o * th * t0 * maxf(f, 0.0))
		rings.append(row)
		tans.append(tg)
	for k in n - 1:
		var t0k := float(k) / float(n - 1)
		var t1k := float(k + 1) / float(n - 1)
		for i in seg:
			var i2 := (i + 1) % seg
			_hair_v(st, rings[k][i2], tans[k], t0k, sid)
			_hair_v(st, rings[k + 1][i], tans[k + 1], t1k, sid)
			_hair_v(st, rings[k][i], tans[k], t0k, sid)
			_hair_v(st, rings[k][i2], tans[k], t0k, sid)
			_hair_v(st, rings[k + 1][i2], tans[k + 1], t1k, sid)
			_hair_v(st, rings[k + 1][i], tans[k + 1], t1k, sid)


## 头发的一个顶点：顶点色 = 发丝方向（×0.5+0.5）+ 根→梢，UV.x = 哪一缕
static func _hair_v(st: SurfaceTool, p: Vector3, tg: Vector3, t: float, sid: float) -> void:
	st.set_color(Color(tg.x * 0.5 + 0.5, tg.y * 0.5 + 0.5, tg.z * 0.5 + 0.5, clampf(t, 0.0, 0.995)))
	st.set_uv(Vector2(sid, t))
	st.add_vertex(p)


## 发髻：一团（椭球芯）外面绕几缕，从贴头那圈往外拧到顶上，像盘起来的。
## at 发髻中心，out 往外的方向，rad 半径；加进 st（和别的发束并成一张网格）
static func bun_into(st: SurfaceTool, at: Vector3, out: Vector3, rad: Vector3, n := 7) -> void:
	var d := out.normalized()
	var u := d.cross(Vector3.UP)
	if u.length() < 1e-4:
		u = Vector3.RIGHT
	u = u.normalized()
	var v := d.cross(u).normalized()
	# 芯：一个椭球（方向顺着绕的那圈）
	var R := 10
	var S := 14
	for jj in R:
		for ii in S:
			var q := []
			for e in [[jj, ii], [jj + 1, ii + 1], [jj + 1, ii], [jj, ii], [jj, ii + 1], [jj + 1, ii + 1]]:
				var th := PI * float(e[0]) / float(R)
				var ph := TAU_ * float(e[1]) / float(S)
				var p := at + (u * cos(ph) * sin(th) * rad.x + v * sin(ph) * sin(th) * rad.y + d * cos(th) * rad.z) * 0.92
				var tg := (-u * sin(ph) + v * cos(ph)).normalized()
				q.append([p, tg])
			for e in q:
				_hair_v(st, e[0], e[1], 0.55, 0.37)
	# 外面拧着的几缕
	for k in n:
		var a0 := TAU_ * float(k) / float(n)
		var path := PackedVector3Array()
		var outs := PackedVector3Array()
		for i in 9:
			var t := float(i) / 8.0
			var th := lerpf(PI * 0.62, 0.12, t)
			var ph := a0 + t * 1.6
			var dir := u * cos(ph) * sin(th) + v * sin(ph) * sin(th) + d * cos(th)
			var p := at + Vector3(dir.x * rad.x, dir.y * rad.y, dir.z * rad.z).length() * dir * 1.02
			path.append(p)
			outs.append(dir)
		lock_into(st, path, outs, rad.x * 0.42, rad.x * 0.2, 6, 0.0, fposmod(float(k) * 0.137 + 0.21, 1.0))



## 手：手掌是扁的（掌心朝里贴着腿、手背朝外），往指尖收；大拇指在前面斜着下来。sz = 手的半长
static func hand(sz: float, slim := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := slim
	loft_into(st, [
		[-sz * 1.72, sz * 0.12 * w, sz * 0.2, 0.0, sz * 0.06],
		[-sz * 1.6, sz * 0.2 * w, sz * 0.4, 0.0, sz * 0.05],
		[-sz * 1.3, sz * 0.24 * w, sz * 0.52, 0.0, sz * 0.02],
		[-sz * 0.95, sz * 0.27 * w, sz * 0.58, 0.0, 0.0, 0.96],
		[-sz * 0.55, sz * 0.3 * w, sz * 0.56],
		[-sz * 0.2, sz * 0.3 * w, sz * 0.44],
		[sz * 0.05, sz * 0.32 * w, sz * 0.38, 0.0, 0.0, 0.9],
		[sz * 0.2, sz * 0.2 * w, sz * 0.24, 0.0, 0.0, 0.85],
	], 12)
	# 大拇指：从掌根前面斜着往前下
	loft_into(st, [
		[-sz * 1.05, sz * 0.07, sz * 0.08, sz * 0.02, sz * 0.66],
		[-sz * 0.95, sz * 0.12, sz * 0.12, sz * 0.03, sz * 0.62],
		[-sz * 0.6, sz * 0.15, sz * 0.15, sz * 0.03, sz * 0.5],
		[-sz * 0.3, sz * 0.15, sz * 0.15, sz * 0.02, sz * 0.32, 0.92],
	], 8)
	st.generate_normals()
	return st.commit()


## 鞋：顺着脚往前放样（后跟圆、脚背斜下去、鞋头圆而微翘），底是平的贴地。原点 = 鞋底后跟正下方的地面往前 0.28 鞋长。
## fl 鞋长、fw 半宽、fh 后跟多高；sole 只要一片鞋底（另一个颜色）：薄、宽一点
static func shoe(fl: float, fw: float, fh: float, sole := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 放样沿 Y 走，转一下让它沿 +Z（往前）；圈的「z」就成了往下（所以中心高度取负）
	var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	# [往前多远, 半宽, 半高, 中心高]
	var prof := [
		[-0.3, 0.45, 0.4, 0.5], [-0.27, 0.78, 0.86, 0.5], [-0.18, 0.9, 0.98, 0.5], [0.0, 0.94, 0.88, 0.44],
		[0.18, 1.0, 0.62, 0.31], [0.38, 1.04, 0.42, 0.21], [0.55, 0.96, 0.36, 0.19], [0.66, 0.78, 0.3, 0.17],
		[0.72, 0.5, 0.22, 0.15], [0.745, 0.2, 0.1, 0.12]]
	var rings: Array = []
	for p in prof:
		if sole:
			var hs := 0.075 * fh / fl
			rings.append([float(p[0]) * fl * 1.02 + 0.004, float(p[1]) * fw * 1.06, hs * fl, 0.0, -hs * fl, 1.0])
		else:
			var hh := float(p[2]) * fh * 0.5
			var yc := float(p[3]) * fh
			rings.append([float(p[0]) * fl, float(p[1]) * fw, hh, 0.0, -maxf(yc, hh), lerpf(0.9, 1.0, clampf(float(p[0]) + 0.3, 0.0, 1.0))])
	loft_into(st, rings, 14, true, true, xf)
	st.generate_normals()
	return st.commit()


## 裙子：腰往下撑开，裙摆按 pleats 个褶起伏（越往下褶越深），裙摆里面一圈压暗（裙子里的影）
static func skirt(waist_y: float, length: float, waist: Vector2, hem: Vector2, pleats := 14, depth := 0.12, seg := 56) -> ArrayMesh:
	var rings: Array = []
	var steps := 6
	for i in steps + 1:
		var t := float(i) / float(steps)
		var e := 1.0 - pow(1.0 - t, 2.2)  # 上头贴腰、过了胯往下撑开
		var r := waist.lerp(hem, e)
		rings.append([waist_y - t * length, r.x, r.y, 0.0, 0.0, lerpf(1.0, 0.94, t), depth * smoothstep(0.0, 0.6, t)])
	# 裙摆往里折一点（布有厚度）
	rings.append([waist_y - length - 0.004, hem.x * 0.97, hem.y * 0.97, 0.0, 0.0, 0.75, depth])
	rings.reverse()
	return loft(rings, seg, false, false, pleats)
