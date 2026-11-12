extends SceneTree
## 楼下这条街的实时 3D 巡拍：几个钟点、年纪、季节、天气，两个人在不同的点上做不同的事。
##   xvfb-run -a godot --path client --rendering-driver opengl3 --resolution 1920x1080 -s ../tools/shots/street3d.gd -- --out=/tmp/s3d [--only=a,b] [--hud]
## 不加 --hud 时收起 HUD 和提示条，只看画。帧按「过了几帧」等（软件渲染一帧要半秒多，按秒等会不够）。
var out := "/tmp/s3d"
var only: Array = []
var hud := false
const Stage3D := preload("res://scripts/world3d/stage3d.gd")
var main: Node

## [名字, 青站的 x, 几点（分钟）, 人生阶段, 季节, 回合（挑雨雪天）, 梅离青多远, 青在做的事, 梅在做的事]
const SHOTS := [
	["s01_morning_breakfast", 560, 430, "childhood", "spring", 0, 120, "eat_out", "eat_out"],
	["s02_noon_shop", 1150, 720, "childhood", "summer", 0, 150, "", ""],
	["s03_alley_chess", 1960, 800, "teen", "summer", 0, 110, "chess", "chess"],
	["s04_bike_fix", 2700, 900, "young", "autumn", 0, -160, "work", ""],
	["s05_dusk_tea", 3500, 1100, "young", "autumn", 0, 160, "", "chat"],
	["s06_night_alley", 1750, 1290, "middle", "winter", 0, 140, "", ""],
	["s07_rain_night", 2300, 1240, "teen", "summer", 2, 130, "", ""],
	["s08_kick", 2200, 980, "childhood", "summer", 0, 170, "ball", "ball"],
	["s09_old_morning", 1500, 450, "old", "spring", 0, 130, "", "morning_walk"],
]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
		elif a.begins_with("--only="): only = a.trim_prefix("--only=").split(",")
		elif a == "--hud": hud = true
	DirAccess.make_dir_recursive_absolute(out)
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	Stage3D.set_mode("on", false)  # 出图：软件渲染很慢，别让自动模式退回 2D
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(3)
	main = current_scene
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	var w: Node = main.world
	for r in ["qing", "mei"]:
		w.actors[r].display_name = main.names[r]
	await _frames(2)
	for s in SHOTS:
		if not only.is_empty() and not str(s[0]) in only:
			continue
		var sc: Dictionary = w.scenes.street
		var y := float(sc.floors[0])
		var me: Node2D = w.me()
		var other: Node2D = w.actors.mei
		me.position = Vector2(float(s[1]), y)
		me.walk_target = me.position
		other.visible = true
		other.position = Vector2(float(s[1]) + float(s[6]), y)
		other.net_target = other.position
		other.walk_target = other.position
		w.set_stage(str(s[3]))
		w.set_season(str(s[4]), int(s[5]))
		main._preview_minute = float(s[2])
		for pair in [[me, str(s[7])], [other, str(s[8])]]:
			var a: Node2D = pair[0]
			var act: String = pair[1]
			a.doing = act
			a.action_label = "" if act == "" else str(w.actions.get(act, {}).get("label", act))
			a.together = act != "" and str(s[7]) == str(s[8])
		w._pair_faces(str(s[7]) != "" and s[7] == s[8])
		if not hud:
			main.hud.visible = false
			for n in ["toast", "action_btn", "slot_btn", "goal_panel", "fill_btn", "menu_box"]:
				var c = main.get(n)
				if c is CanvasItem:
					c.visible = false
		w.camera.reset_smoothing()
		await _frames(4)
		main._preview_minute = float(s[2])
		await _frames(2)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png("%s/%s.png" % [out, s[0]])
		print("shot ", s[0])
	quit()
