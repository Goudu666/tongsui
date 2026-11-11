extends SceneTree
## 「人物活起来」演示：两个人在几张图上做各自的事（专属动作、表情、头顶气泡）、搭伴面对面、做完击掌、碰面招手，街坊各干各的。
##   godot --path client --rendering-driver opengl3 --resolution 1920x1080 --script res://../tools/shots/life.gd -- --out=DIR [--movie]
## 不带 --movie：每一段拍一张 PNG；带 --movie（配合 --write-movie x.avi --fixed-fps 30）：整段录下来。

var main: Node
var out := "/tmp/life"
var movie := false
var zoom := 1.0   ## 镜头再推近几倍（--zoom=1.7 看细节；1 = 游戏里的取景）

## [图, 阶段, 几点, 季节, 青 [x, 行动, 点位], 梅 [x, 行动, 点位], 一起, 秒, 名字]
const CUTS := [
	["street", "childhood", 440, "spring", [500, "eat_out", "breakfast_stall"], [560, "eat_out", "breakfast_stall"], true, 4.0, "c01_eat_together"],
	["street", "childhood", 900, "summer", [1500, "play_alley", "alley_rope"], [1560, "play_alley", "alley_rope"], true, 3.4, "c02_hop"],
	["building", "childhood", 1150, "autumn", [520, "study", "desk_qing"], [600, "picture_book", "desk_qing"], false, 3.4, "c03_homework"],
	["river", "teen", 1000, "summer", [2700, "fish", "river_fish"], [2860, "play_river", "river_bank"], false, 3.6, "c04_fish_kite"],
	["middle", "teen", 800, "autumn", [1300, "ball", "middle_yard"], [1500, "broadcast", "radio_mic"], false, 3.4, "c05_ball"],
	["street", "young", 1200, "winter", [2240, "night_market", "alley_night"], [2330, "chat", "alley_night"], false, 3.4, "c06_night_market"],
	["street", "young", 700, "spring", [2680, "work", "bike_bench"], [2010, "chess", "chess_table"], false, 3.4, "c07_fix_chess"],
	["across", "middle", 1250, "autumn", [4000, "overtime", "office_desk"], [4100, "overtime", "office_desk"], true, 3.4, "c08_overtime"],
	["park", "old", 600, "spring", [2800, "ground_write", "square_ground"], [1960, "choir", "pavilion_choir"], false, 3.6, "c09_old_park"],
	["street", "old", 900, "summer", [1990, "chess", "chess_table"], [2040, "chess", "chess_table"], true, 3.6, "c10_old_chess"],
]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--movie":
			movie = true
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	if movie:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("✓ ", name)


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.3)
	main = current_scene
	await _wait(0.5)
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	var w: Node = main.world
	for r in ["qing", "mei"]:
		w.actors[r].display_name = main.names[r]
	await _wait(0.2)
	main.hud.visible = false
	if main.toast is CanvasItem:
		main.toast.visible = false
	if main.get("guide") is Node:
		main.guide.process_mode = Node.PROCESS_MODE_DISABLED
		if main.guide is CanvasItem:
			main.guide.visible = false
	for c in CUTS:
		var sc: Dictionary = w.scenes.get(str(c[0]), {})
		var y := float(sc.floors[-1])
		w.set_stage(str(c[1]))
		w.set_season(str(c[3]))
		main._preview_minute = float(c[2])
		var cfg := {"qing": c[4], "mei": c[5]}
		for r in ["qing", "mei"]:
			var a: Node2D = w.actors[r]
			var row: Array = cfg[r]
			var yy := y
			if str(c[0]) == "building":
				yy = float(sc.floors[0]) if r == "qing" and false else float(sc.floors[-1])
			a.visible = true
			var x := float(row[0])
			if bool(c[6]):
				var gap: float = w.FACE_GAP if w._act_loop(str(row[1]), str(row[2])) in a.FACE_LOOPS else w.PAIR_GAP
				x = float(c[4][0]) + (-gap if r == "qing" else gap)
			a.position = Vector2(x, yy)
			a.walk_target = a.position
			a.net_target = a.position
			a.snap_remote = true
			a.doing = str(row[1])
			a.at_spot = str(row[2])
			a.action_label = w._doing_label(r, str(row[1]))
			a.together = bool(c[6])
			a.face_to = 0
		w._pair_faces(bool(c[6]))
		_frame(w, (w.actors.qing.position + w.actors.mei.position) / 2.0)
		await _wait(float(c[7]) * 0.55)
		await _shot(str(c[8]))
		await _wait(float(c[7]) * 0.45)
		# 做完一回：放下手里的事，按 did 反应（一起的击掌）
		for r in ["qing", "mei"]:
			var a: Node2D = w.actors[r]
			var f := {"tg": bool(c[6]), "did": {"tg": bool(c[6]), "nd": {"mood": 6 if r == "qing" else -4}, "s": {"mind": 1.2}}}
			a.doing = ""
			a.action_label = ""
			a.together = false
			w._react(r, a, f)
		await _wait(0.5)
		await _shot(str(c[8]) + "_after")
		await _wait(0.9)
	await _meet(w)
	quit()


## 镜头：推近、对准两个人中间（游戏里镜头跟着自己横着走；这里只为看清楚）
func _frame(w: Node, at: Vector2) -> void:
	if zoom <= 1.0:
		return
	w._enter_scene(w.scene_at(at.y))
	await process_frame
	var cam: Camera2D = w.camera
	var base: float = get_root().get_visible_rect().size.y / float(cam.limit_bottom - cam.limit_top)
	cam.zoom = Vector2.ONE * base * zoom
	cam.position = Vector2(at.x, at.y - 120.0)
	cam.reset_smoothing()
	w.set_process(false)  # 别让 world_view 把镜头拽回自己身上


## 收尾：两个人从街两头走过来，碰上了招手；路过的街坊搭一句
func _meet(w: Node) -> void:
	w.set_process(true)
	var sc: Dictionary = w.scenes.street
	var y := float(sc.floors[-1])
	w.set_stage("teen")
	w.set_season("autumn")
	main._preview_minute = 600.0
	var me: Node2D = w.me()
	var other: Node2D = w.actors.mei
	for a in [me, other]:
		a.doing = ""
		a.action_label = ""
		a.together = false
		a.face_to = 0
	me.position = Vector2(1100, y)
	me.walk_target = me.position
	other.position = Vector2(2400, y)
	other.net_target = other.position
	other.snap_remote = true
	w._apart = true
	await _wait(0.3)
	me.walk_target = Vector2(1650, y)
	var t := 0.0
	while t < 4.0:
		await process_frame
		t += 1.0 / 30.0
		other.net_target.x = maxf(1760.0, other.net_target.x - 260.0 / 30.0)
		w._pair_faces(false)
		if zoom > 1.0:
			w.set_process(false)
			w.camera.position = Vector2((me.position.x + other.position.x) / 2.0, y - 120.0)
			w.camera.zoom = Vector2.ONE * get_root().get_visible_rect().size.y / float(w.camera.limit_bottom - w.camera.limit_top) * zoom
		if absf(t - 2.6) < 0.02:
			await _shot("c11_meet")
	await _wait(1.0)
	await _shot("c12_meet_after")
	await _wait(1.5)
