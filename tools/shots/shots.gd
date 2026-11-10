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

	# 联机大厅和找回码（假联机，不连服务器）
	if main.has_method("_show_recovery"):
		var fake: Node = load((get_script() as Script).resource_path.get_base_dir().path_join("fake_net.gd")).new()
		main.add_child(fake)
		fake.lifelines.connect(main._on_lifelines)
		main.net = fake
		main._show_online()
		await _wait(1.6)
		await _snap("19_lobby")
		main._show_recovery()
		await _wait(1.6)
		await _snap("20_recovery")
		main.net = null
		fake.queue_free()

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
	await _duet_cards()
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


## 「接话」的几张卡：猜 TA、搭上了、都猜中的共鸣、影子替选的错位、回来被问到、回话的结算（见 docs/DUET.md）
func _duet_cards() -> void:
	if not main.events_by_id.has("d_kite_tree") or main.get("duet") == null:
		return
	var ev: Dictionary = main.events_by_id["d_kite_tree"]
	var roles := {"qing": "d_kite_tree", "mei": "d_kite_tree"}
	main._on_event_started({"event": {"roles": ["qing", "mei"], "eventId": "d_kite_tree", "kind": "mirror"}})
	main.duet.ask_guess("d_kite_tree", "climb", str(ev.options[0].text))
	await _wait(1.2)
	await _snap("30_duet_guess")
	main._show_mirror_result({"label": "8 岁 · 春", "events": roles, "choices": {"qing": "climb", "mei": "hold"}, "shadow": [],
		"resonance": true, "text": ev.catches[0].text,
		"duet": {"outcome": "catch", "knew": {"qing": true, "mei": false}, "line": "小满猜着了阿蘅，阿蘅没猜着小满。"}})
	await _wait(2.2)
	await _snap("31_duet_catch")
	main._show_mirror_result({"label": "8 岁 · 春", "events": roles, "choices": {"qing": "wait", "mei": "wait"}, "shadow": [],
		"resonance": true, "text": ev.resonance.wait.text,
		"duet": {"outcome": "res", "knew": {"qing": true, "mei": true}, "line": "而且谁也不意外。"}})
	await _wait(2.4)
	await _snap("32_duet_res")
	main._show_mirror_result({"label": "8 岁 · 春", "events": roles, "choices": {"qing": "climb", "mei": "wait"}, "shadow": ["mei"],
		"resonance": false, "text": ev.dissonance.text, "duet": {"outcome": "miss", "knew": {"qing": false, "mei": null}, "line": null, "owed": "mei"}})
	await _wait(2.2)
	await _snap("33_duet_miss_shadow")
	main._close_modal()
	# 换成阿蘅这边：她回来了
	var life_was: Dictionary = main.life
	main.my_role = "mei"
	main.life = {"phase": "life", "turn": 12, "duet": {"keep": 8, "epitaph": [], "owed": {"qing": [], "mei": [
		{"turn": 9, "age": 8, "label": "8 岁 · 春", "eventId": "d_kite_tree", "shadow": "wait", "partner": "climb", "outcome": "miss"}]}}}
	main.duet.on_snapshot()
	await _wait(1.2)
	await _snap("34_duet_owed")
	main.life.duet.owed.mei = []
	main._on_log_entries({"entries": [{"turn": 12, "age": 8, "label": "8 岁 · 夏", "kind": "solo", "shadow": [], "resonance": null,
		"events": {"qing": null, "mei": "d_kite_tree"}, "choices": {"qing": null, "mei": "hold"}, "text": ev.catches[0].text,
		"duet": {"echo": true, "role": "mei", "outcome": "catch", "was": "miss", "like": false, "shadow": "wait", "partner": "climb",
			"partnerKnew": true, "turn": 9, "label": "8 岁 · 春",
			"lines": ["隔了三个日子，还是搭上了。", "影子替你选的是「等风把它吹下来」。它还得学。", "小满当时猜的就是这个。小满比影子懂你。"]}}]})
	await _wait(2.2)
	await _snap("35_duet_echo")
	main._close_modal()
	main.my_role = "qing"
	main.life = life_was
