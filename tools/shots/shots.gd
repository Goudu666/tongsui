extends SceneTree
## 截图脚本：把游戏开到各个界面，各存一张 PNG。用来做画面改动的前后对比。
##   bash tools/shots/run.sh <输出目录>
## 不联网：直接往 main.gd 里喂假数据（和服务器发来的结构一致）。

var out_dir := "user://shots"
var main: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
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
	await _wait(1.6)
	await _snap("01_title")

	# 抽卡
	var fams: Array = main.content.families
	var tals: Array = main.content.talents
	main.names = {"qing": "小满", "mei": "阿蘅"}
	main.my_role = "qing"
	main.life = {"phase": "roll", "turn": 0, "rolls": {
		"qing": {"familyId": fams[0].id, "talentId": tals[0].id, "stats": {"body": 6, "mind": 8, "charm": 4, "luck": 7}, "confirmed": false, "rerollsLeft": 2},
		"mei": {"familyId": fams[1].id, "talentId": tals[1].id, "stats": {"body": 5, "mind": 5, "charm": 9, "luck": 3}, "confirmed": true, "rerollsLeft": 0},
	}}
	main._show_roll()
	await _wait(1.8)
	await _snap("02_roll")

	main._on_net_created("482913", "demo")
	await _wait(1.5)
	await _snap("16_code")

	if main.has_method("_show_server_settings"):
		main._show_server_settings()
		await _wait(1.5)
		await _snap("18_server")

	# 河畔里：清早 / 傍晚 / 夜里
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	if main.world != null:
		for r in ["qing", "mei"]:
			main.world.actors[r].display_name = main.names[r]
	await _wait(0.28)
	await _snap("15_print_in")
	await _wait(2.5)
	await _snap("03_world_morning")
	await _walk(Vector2(1180, 1010), 3.0)
	main._preview_minute = 1095.0
	await _wait(1.2)
	await _snap("04_world_dusk")
	main._preview_minute = 1290.0
	await _wait(1.2)
	await _snap("05_world_night")
	await _walk(Vector2(2090, 720), 5.0)
	main._preview_minute = 1100.0
	await _wait(1.0)
	await _snap("06_river_dusk")

	# 事件弹窗（默契时刻）
	var ev: Dictionary = {}
	for e in main.content.events:
		if e.get("options", []).size() >= 3:
			ev = e
			break
	main.offline_preview = false
	main._on_event_started({"event": {"roles": ["qing", "mei"], "eventId": ev.id, "kind": "mirror"}})
	await _wait(1.5)
	await _snap("07_event")
	main._show_mirror_result({"label": "7 岁 · 立夏", "events": {"qing": ev.id, "mei": ev.id},
		"choices": {"qing": ev.options[0].id, "mei": ev.options[0].id}, "shadow": [], "resonance": true,
		"text": "两个人谁也没看谁，手却伸向了同一边。"})
	await _wait(1.5)
	await _snap("08_resonance")
	main._show_mirror_result({"label": "7 岁 · 立夏", "events": {"qing": ev.id, "mei": ev.id},
		"choices": {"qing": ev.options[0].id, "mei": ev.options[1].id}, "shadow": ["mei"], "resonance": false,
		"text": "一个人在楼顶等了很久，另一个人已经在楼下了。"})
	await _wait(1.9)
	await _snap("17_dissonance")
	main._on_log_entries({"entries": [{"kind": "day", "label": "7 岁 · 立夏", "text": "这一天，楼顶的鸽子飞了三圈才回来。"}]})
	await _wait(1.5)
	await _snap("09_day_end")
	main._close_modal()

	# 长大：过场卡（旧版本没有，就直接换阶段）
	main.offline_preview = true
	main.life = {"turn": 50}
	main._preview_minute = 600.0
	if main.has_method("_grow_up"):
		main._refresh_hud()
		main._grow_up(main.LifeTime.at(50))
		await _wait(1.3)
		await _snap("12_grow_up")
		await _wait(2.6)
	elif main.world != null:
		main.world.set_stage("young")
		await _wait(1.5)
	main._preview_minute = 600.0
	await _wait(0.3)
	await _snap("10_world_young")
	if main.world != null:
		main.world.set_stage("old")
	main.life = {"turn": 72}
	if main.has_method("_refresh_hud"):
		main._refresh_hud()
	main._toast("TA 上线了")
	await _walk(Vector2(2090, 420), 2.5)
	main._preview_minute = 1000.0
	await _wait(1.0)
	await _snap("13_world_old")

	# 联机时的 HUD：四个圆表、零花钱、两个圆（假装服务器发来了状态）
	main.offline_preview = false
	main.life = {"turn": 17}
	main.last_world = {"minute": 462.0, "schoolDay": true, "needs": {"qing": {"hunger": 22, "energy": 81, "mood": 64, "clean": 47}},
		"money": {"qing": 12}, "bond": {"sync": 14, "close": 46}}
	if main.has_method("_grow_up"):
		main._stage_shown = "childhood"
	if main.world != null:
		main.world.set_stage("childhood")
		main.world.set_minute(462.0)
	main._refresh_hud()
	await _walk(Vector2(1630, 500), 3.2)
	await _snap("14_hud_online")
	main._close_modal()

	# 一生
	main.life = {"phase": "ended", "turn": 200, "log": [{"kind": "end", "text": "七十九岁那年冬天，两个人前后脚走了。楼下的槐树还在。"}],
		"memories": [{"age": 6, "title": "楼顶的鸽子", "vivid": 2}, {"age": 9, "title": "一毛钱的冰棍", "vivid": 1},
			{"age": 15, "title": "铁桥上的晚自习", "vivid": 0}, {"age": 23, "title": "搬家那天", "vivid": 1}, {"age": 61, "title": "又回到早点铺", "vivid": 3}]}
	main._show_ending()
	await _wait(1.8)
	await _snap("11_ending")
	quit()


## 让自己走到某处（走寻路），等一会儿
func _walk(to: Vector2, sec: float) -> void:
	var w: Node = main.world
	if w == null:
		return
	var a: Node2D = w.me()
	if w.nav.ready():
		a.set_path(w.nav.path(a.position, w.nav.snap(to)))
	else:
		a.walk_target = to
	await _wait(sec)
