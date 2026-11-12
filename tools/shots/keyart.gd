extends SceneTree
## 主视觉的底片：在游戏里摆好图、钟点、年纪、季节和两个人，收起界面，镜头推近一点，拍成干净的 PNG。
## tools/art/keyart.py 拿这些底片排字，出标题页的底图、七章的章首小画、商店宣传图。
##   godot --path client --rendering-driver opengl3 --resolution 2400x1080 --script res://../tools/shots/keyart.gd -- --out=DIR [--only=a,b]
## 都是游戏里真的画面（同一套底图、光与空气、人），不另画。

var out_dir := "user://keyart"
var only: Array = []
var main: Node

## 名字, 图, 我在哪（x）, 对门离我多远, 几点（分钟）, 人生阶段, 季节, 回合（挑天气）, 镜头推近几倍, 镜头偏移 (x, y)
const SHOTS := [
	# 标题页：傍晚的河边，两个半大孩子靠着栏杆，铁桥和对岸的楼
	["title", "river", 2450, 110, 1098, "teen", "summer", 0, 1.35, Vector2(-230, 10)],
	# 七章，一章一张（章首卡上裁成横条，人在中间偏下）
	["ch1", "building", 1560, 110, 445, "childhood", "spring", 0, 1.7, Vector2(40, 120)],
	["ch2", "primary", 1250, 100, 760, "childhood", "autumn", 0, 1.7, Vector2(60, 90)],
	["ch3", "river", 2950, 100, 1105, "teen", "summer", 0, 1.6, Vector2(40, 40)],
	["ch4", "away", 1500, 300, 1080, "young", "winter", 0, 1.6, Vector2(150, 80)],
	["ch5", "newhome", 1300, 110, 1085, "middle", "spring", 0, 1.7, Vector2(40, 90)],
	["ch6", "street", 2600, 110, 1240, "middle", "summer", 2, 1.6, Vector2(40, 80)],
	["ch7", "river", 2200, 90, 1100, "old", "autumn", 0, 1.6, Vector2(0, 40)],
	# 商店宣传图的底片
	["store_street", "street", 1700, 130, 1100, "teen", "autumn", 0, 1.15, Vector2(0, 40)],
	["store_rain", "street", 2400, 120, 1250, "young", "summer", 2, 1.2, Vector2(0, 50)],
	["store_park", "park", 2400, 100, 660, "old", "autumn", 0, 1.2, Vector2(0, 40)],
]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name, " ", img.get_size())


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(0.8)
	main._start_preview()
	main.names = {"qing": "", "mei": ""}
	var w: Node = main.world
	# 脚下的名牌是 actor 自己的 overlay 画的（z 71，不在界面层里），只改 main.names 收不掉
	for r in ["qing", "mei"]:
		var ov = w.actors[r].get("_over")
		if ov is CanvasItem:
			ov.visible = false
	await _wait(2.2)
	main.hud.visible = false
	for n in ["toast", "action_btn", "slot_btn", "goal_panel", "banner", "guide", "juice", "stat_strip"]:
		var c = main.get(n)
		if c is CanvasItem:
			c.visible = false
		elif c is CanvasLayer:
			c.visible = false
	# 界面层（HUD、音量按钮、爽感层……）都在 layer ≥ 1 的 CanvasLayer 里：一起收起来
	for n in root.find_children("*", "CanvasLayer", true, false):
		if (n as CanvasLayer).layer >= 1:
			n.visible = false
	for s in SHOTS:
		if not only.is_empty() and not str(s[0]) in only:
			continue
		var sc: Dictionary = w.scenes.get(str(s[1]), {})
		if sc.is_empty():
			continue
		var y := float(sc.floors[-1])
		var me: Node2D = w.me()
		me.position = Vector2(float(s[2]), y)
		me.walk_target = me.position
		var other: Node2D = w.actors.mei
		other.visible = true
		other.position = Vector2(float(s[2]) + float(s[3]), y)
		other.net_target = other.position
		other.walk_target = other.position
		w.set_stage(str(s[5]))
		w.set_season(str(s[6]), int(s[7]))
		main._preview_minute = float(s[4])
		await _wait(0.4)
		# 我往对门那边走一小步，再站住：两个人脸朝着一个方向
		me.walk_target = me.position + Vector2(40.0, 0.0)
		await _wait(0.9)
		w.camera.zoom = w.camera.zoom * float(s[8])
		w.camera.offset = s[9]
		w.camera.reset_smoothing()
		# 名字签、头顶的字是界面，不进画：人自己画的那层透明掉（精灵是子节点，不受影响）
		for a in w.actors.values():
			a.self_modulate.a = 0.0
		if w.get("_marks") is CanvasItem:
			w._marks.visible = false
		main._preview_minute = float(s[4])
		await _wait(0.5)
		await _snap(str(s[0]))
		w.camera.zoom = w.camera.zoom / float(s[8])
		w.camera.offset = Vector2.ZERO
	quit()
