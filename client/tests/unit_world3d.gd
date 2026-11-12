extends SceneTree
## 实时 3D（world3d/）：小人五个岁数、两个人都搭得起来，二十一套动作和情绪都演得动；
## 楼下这条街搭得起来、年代季节换得动；3D 相机和 2D 镜头在人走的那条线上对得上。

const Figure := preload("res://scripts/world3d/figure3d.gd")
const Street3D := preload("res://scripts/world3d/street3d.gd")
const Stage3D := preload("res://scripts/world3d/stage3d.gd")
const Actor := preload("res://scripts/world/actor.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		printerr("✗ ", what)


func _initialize() -> void:
	# 小人：每个人每个岁数都有完整的关节；身高照 actor.gd 的 HEIGHT（梅矮 6 厘米）
	for r in ["qing", "mei"]:
		for st in Actor.STAGES:
			var f := Figure.new()
			root.add_child(f)
			f.build(r, st)
			for jn in ["root", "hips", "spine", "neck", "head", "sh_l", "el_l", "hand_r", "th_l", "kn_r", "an_l"]:
				check(f.j.has(jn), "%s %s 少了关节 %s" % [r, st, jn])
			var want: float = Actor.HEIGHT[st] / 100.0 - (0.06 if r == "mei" else 0.0)
			check(absf(f.height - want) < 0.001, "%s %s 身高 %.2f ≠ %.2f" % [r, st, f.height, want])
			# 每套动作演一会儿：关节角度都是有限数，不会转飞
			var loops: Array = Actor.ACT_LOOP.duplicate()
			loops.append_array(["sit", "wave", "busy"])
			for lp in loops:
				f.loop = lp
				for i in 12:
					f.animate(0.05)
				for jn in f.j:
					var rot: Vector3 = (f.j[jn] as Node3D).rotation
					check(rot.is_finite(), "%s %s %s 关节 %s 角度不是数" % [r, st, lp, jn])
			f.loop = ""
			for e in Actor.EMOTE_CELL:
				f.emote = e
				f.animate(0.1)
			f.emote = ""
			f.walking = true
			for i in 20:
				f.phase = fmod(f.phase + 0.05, 1.0)
				f.animate(0.033)
			check(absf(f._yaw) > deg_to_rad(40.0), "%s %s 走路时没侧过身" % [r, st])
			f.queue_free()
	# 街：搭得起来，有灯、有树，年代换得动（便利店的店招在中年以后）
	var s := Street3D.new()
	root.add_child(s)
	s.build({"id": "street", "width": 4000, "floors": [760]}, "childhood", "summer")
	check(s.get_child_count() > 20, "街上的东西太少：%d" % s.get_child_count())
	check(s.lamps.size() >= 6, "路灯、店里的灯太少：%d" % s.lamps.size())
	check(not s._foliage.is_empty(), "街上没有树")
	s.set_look("middle")
	check((s._labels.shop as Label3D).text == "便利店", "中年以后小卖部该是便利店")
	s.set_look("childhood")
	check((s._labels.shop as Label3D).text == "小卖部", "小时候是小卖部")
	s.set_season("winter")
	var bare := true
	for f in s._foliage:
		if f[2] != "hedge" and (f[0] as Node3D).visible:
			bare = false
	check(bare, "冬天树冠该藏起来只剩枝子")
	s.queue_free()
	# 只有有 3D 的图走 3D
	check(Stage3D.supports("street"), "楼下这条街该有 3D")
	check(not Stage3D.supports("building"), "楼里还没有 3D，该走 2D")
	Stage3D.enabled = false
	check(not Stage3D.supports("street"), "关掉 3D 后都走 2D")
	Stage3D.enabled = true
	# 相机：Z = 0 面上的点投到屏幕上，和 2D 镜头算的一样（取景框 1920×1080、地面 760、镜头中心 (1500, 600)、竖着看 900 像素）
	var st3 := Stage3D.new()
	st3.ground_y = 760.0
	var center := Vector2(1500, 600)
	var view := Vector2(1600, 900)
	var cam := st3.cam
	var h := view.y / 100.0
	cam.position = Vector3(center.x / 100.0, (760.0 - center.y) / 100.0 + Stage3D.LIFT, Stage3D.DIST)
	cam.size = h * Stage3D.NEAR / Stage3D.DIST
	cam.frustum_offset = Vector2(0.0, -Stage3D.LIFT * Stage3D.NEAR / Stage3D.DIST)
	for p: Vector2 in [Vector2(1500, 760), Vector2(1100, 400), Vector2(2200, 1000)]:
		var w3: Vector3 = st3.to3d(p)
		# 手算投影：平移镜头的透视，Z = 0 面上像素 = (世界 − 中心) × 屏高 / 看到的高
		var rel := w3 - cam.position
		var k: float = Stage3D.DIST / -rel.z
		var sy := (rel.y * k + Stage3D.LIFT) / h
		var sx := rel.x * k / h
		var want := (p - center) / view.y
		check(absf(sx - want.x) < 0.001 and absf(-sy - want.y) < 0.001, "3D 相机和 2D 镜头没对上：%s" % p)
	st3.free()
	if fails == 0:
		print("✓ unit_world3d：两个人五个岁数、二十四套动作、街道 3D、年代季节、相机对齐")
	quit(1 if fails > 0 else 0)
