extends SceneTree
## 任意一张有实时 3D 的图的巡拍 / 性能探针（street3d.gd 那套的通用版）。
##   xvfb-run -a godot --path client --rendering-driver opengl3 --resolution 1920x1080 -s ../tools/shots/scene3d.gd -- \
##     --scene=building --out=/tmp/b3d [--shots=shots.json] [--only=a,b] [--hud] [--perf] [--2d]
## shots.json：[{"name":"b01", "x":520, "floor":1, "minute":480, "stage":"childhood", "season":"spring", "turn":0,
##               "gap":120, "other_floor":1, "me":"study", "other":"", "wealth":[1,2], "items":["tv","books"], "decade":"八十年代"}]
##   没给 --shots 就按这张图的宽度从左到右均匀拍五张（白天、傍晚、夜里轮着）。
##   wealth / items / decade 只在楼里有用：两家的家境、两家各有什么（同一份给两家）、年代名。
## --perf：每张多量 60 帧，3D 和 2D 各一遍，打 PERF 行（llvmpipe 只看相对值、draw call）。--2d：拍 2D 版对照。
var out := "/tmp/s3d"
var scene_id := "street"
var shots_path := ""
var only: Array = []
var hud := false
var perf := false
var flat := false
const Stage3D := preload("res://scripts/world3d/stage3d.gd")
var main: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
		elif a.begins_with("--scene="): scene_id = a.trim_prefix("--scene=")
		elif a.begins_with("--shots="): shots_path = a.trim_prefix("--shots=")
		elif a.begins_with("--only="): only = a.trim_prefix("--only=").split(",")
		elif a == "--hud": hud = true
		elif a == "--perf": perf = true
		elif a == "--2d": flat = true
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _default_shots(sc: Dictionary) -> Array:
	var w := float(sc.width)
	var floors: Array = sc.floors
	var res: Array = []
	var mins := [480, 1080, 1290, 720, 430]
	var stages := ["childhood", "teen", "young", "middle", "old"]
	for i in 5:
		res.append({"name": "%s_%d" % [scene_id, i + 1], "x": w * (0.1 + 0.2 * i), "floor": floors.size() - 1,
			"minute": mins[i], "stage": stages[i], "season": ["spring", "summer", "autumn", "winter", "spring"][i], "gap": 130})
	return res


func _run() -> void:
	Stage3D.set_mode("off" if flat else "on", false)  # 出图：软件渲染很慢，别让自动模式退回 2D
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(3)
	main = current_scene
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	var w: Node = main.world
	for r in ["qing", "mei"]:
		w.actors[r].display_name = main.names[r]
	await _frames(2)
	var sc: Dictionary = w.scenes.get(scene_id, {})
	if sc.is_empty():
		push_error("没有这张图：" + scene_id)
		quit(1)
		return
	var shots: Array = _default_shots(sc)
	if shots_path != "":
		shots = JSON.parse_string(FileAccess.get_file_as_string(shots_path))
	for s in shots:
		if not only.is_empty() and not str(s.name) in only:
			continue
		var floors: Array = sc.floors
		var y := float(floors[int(s.get("floor", floors.size() - 1))])
		var oy := float(floors[int(s.get("other_floor", s.get("floor", floors.size() - 1)))])
		var me: Node2D = w.me()
		var other: Node2D = w.actors.mei
		me.position = Vector2(float(s.x), y)
		me.walk_target = me.position
		other.visible = s.get("gap", 130) != null
		other.position = Vector2(float(s.x) + float(s.get("gap", 130)), oy)
		other.net_target = other.position
		other.walk_target = other.position
		w._enter_scene(sc)
		w.set_stage(str(s.get("stage", "childhood")))
		w.set_season(str(s.get("season", "spring")), int(s.get("turn", 0)))
		if s.has("wealth") or s.has("items") or s.has("decade"):
			var wl: Array = s.get("wealth", [1, 1])
			var items: Array = s.get("items", [])
			w.home.set_look({"qing": int(wl[0]), "mei": int(wl[1])}, str(s.get("decade", "")), w.scene_look())
			w.home.set_items({"qing": items, "mei": items})
		main._preview_minute = float(s.get("minute", 600))
		var a_me := str(s.get("me", ""))
		var a_ot := str(s.get("other", ""))
		for pair in [[me, a_me], [other, a_ot]]:
			var a: Node2D = pair[0]
			var act: String = pair[1]
			a.doing = act
			a.action_label = "" if act == "" else str(w.actions.get(act, {}).get("label", act))
			a.together = act != "" and a_me == a_ot
		w._pair_faces(a_me != "" and a_me == a_ot)
		if s.get("asleep", false):
			me.asleep = true
			other.asleep = true
		if not hud:
			main.hud.visible = false
			for n in ["toast", "action_btn", "slot_btn", "goal_panel", "fill_btn", "menu_box"]:
				var c = main.get(n)
				if c is CanvasItem:
					c.visible = false
		w.camera.reset_smoothing()
		await _frames(4)
		main._preview_minute = float(s.get("minute", 600))
		await _frames(2)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png("%s/%s.png" % [out, s.name])
		print("shot ", s.name, " 3d=", w.stage3d.active())
		if perf:
			for on in [true, false]:
				Stage3D.set_mode("on" if on else "off", false)
				w.reapply_3d()
				await _frames(8)
				var dc_sum := 0.0
				var n := 0
				var t0 := Time.get_ticks_usec()
				for i in 40:
					main._preview_minute = float(s.get("minute", 600))
					await process_frame
					dc_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
					n += 1
				var dt := (Time.get_ticks_usec() - t0) / 1000.0 / n
				print("PERF %s %s frame_ms=%.1f draw_calls=%.0f prims=%.0f vram_MB=%.1f" % ["3D" if on else "2D", s.name, dt, dc_sum / n,
					Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
			Stage3D.set_mode("off" if flat else "on", false)
			w.reapply_3d()
	quit()
