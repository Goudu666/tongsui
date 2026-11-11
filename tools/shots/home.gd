extends SceneTree
## 家里的东西（client/scripts/world/home_life.gd）对比图：同一年清贫家和殷实家、同一户人家童年和少年。
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path client --rendering-driver opengl3 --resolution 1920x1080 \
##     -s res://../tools/shots/home.gd -- --out=/tmp/home [--only=a_poor,a_rich]
## 不联网：走 main 的「先逛逛」，往 life 里塞两户人家和年代（main._home_wealth / Era 照常读），WORLD.homes 直接喂给 world_view。
## 每一镜拍两张：青家和梅家（镜头跟着青走，被图边卡住，正好是一整间屋）。

var out_dir := "user://home_shots"
var only: Array = []
var main: Node

## [名字, 青家投哪户, 梅家投哪户, 年代名, look, 人生阶段, 钟点, 青家有的, 梅家有的]
## 年份对着 content/home.yaml 摆（八十年代中生：8 岁是九十年代初，16 岁是千禧年头上）
const SHOTS := [
	# 同一年、对门两家：江家（四口挤一间，清贫）和董家（厂长家，殷实）
	["a", "jiang", "dong", "九十年代", "childhood", "childhood", 1000,
		["radio", "tv"],
		["radio", "tv", "books", "milk", "fridge", "phone", "console"]],
	# 同一户人家（青家：陈家，小康）八岁和十六岁；对门是金家（老城里搬来的，穷了，书还在）
	["b_child", "chen", "jin", "九十年代", "childhood", "childhood", 1000,
		["radio", "tv", "fridge", "books"],
		["radio", "books"]],
	["b_teen", "chen", "jin", "千禧年头上", "teen", "teen", 1000,
		["tv", "fridge", "books", "milk", "phone", "console", "tape"],
		["books", "tv", "fridge", "tape"]],
	# 殷实人家到了一〇年代：彩电换成薄的，电脑也薄了；清贫人家这时候才有电脑
	["c_later", "jiang", "dong", "一〇年代", "young", "young", 1000,
		["tv", "fridge", "phone", "pc"],
		["tv", "books", "milk", "fridge", "phone", "tape", "pc"]],
	# 晚上：灯下
	["a_night", "jiang", "dong", "九十年代", "childhood", "childhood", 1230,
		["radio", "tv"],
		["radio", "tv", "books", "milk", "fridge", "phone", "console"]],
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
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(0.8)
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	var w: Node = main.world
	for r in ["qing", "mei"]:
		w.actors[r].display_name = main.names[r]
	await _wait(2.0)
	main.hud.visible = false
	for n in ["toast", "action_btn", "slot_btn", "goal_panel", "menu_box", "fill_btn"]:
		var c = main.get(n)
		if c is CanvasItem:
			c.visible = false
	for s in SHOTS:
		if not only.is_empty() and not str(s[0]) in only:
			continue
		main.life["persons"] = {"qing": {"familyId": s[1], "flags": []}, "mei": {"familyId": s[2], "flags": []}}
		main.life["era"] = {"decade": s[3], "look": s[4]}
		w.set_stage(str(s[5]))
		w.set_look(str(s[4]))
		w.set_season("autumn", 0)
		w.set_home_look(main._home_wealth(), str(s[3]))
		w.homes = {"qing": s[7], "mei": s[8]}
		w.home.set_items(w.homes)
		# 两个孩子都在这一家：去对门看电视、翻书，就是这么回事。镜头跟着青走，所以拍梅家时青也在梅家
		for side in [["qing", 830.0, 745.0], ["mei", 2370.0, 2455.0]]:
			var me: Node2D = w.me()
			var y := float(w.scenes.building.floors[1])
			me.position = Vector2(float(side[1]), y)
			me.walk_target = me.position
			var other: Node2D = w.actors.mei
			other.visible = true
			other.position = Vector2(float(side[2]), y)
			other.net_target = other.position
			other.walk_target = other.position
			main._preview_minute = float(s[6])
			await _wait(0.5)
			me.walk_target = me.position + Vector2(-12.0, 0.0)
			await _wait(1.2)
			main._preview_minute = float(s[6])
			main.hud.visible = false
			main.toast.visible = false
			await _wait(0.3)
			await _snap("%s_%s" % [s[0], side[0]])
	quit()
