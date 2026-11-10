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
		if a.begins_with("--notch=") and float(a.trim_prefix("--notch=")) > 0.0:
			# 假装左右都有刘海 / 圆角，看 HUD 和菜单页让没让开
			var n := float(a.trim_prefix("--notch="))
			load("res://scripts/ui/kit.gd").safe_override = Vector2(n, n)
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
	var junior := {"id": "m_junior", "title": "小升初", "age": 12, "turns": 14, "lines": [
		{"id": "key", "text": "去重点班", "by": "心智", "unit": "分", "have": 58, "need": 64, "ok": false}]}
	var junior_mei: Dictionary = junior.duplicate(true)
	junior_mei.lines[0].have = 66
	junior_mei.lines[0].ok = true
	var duty := {"label": "上学", "spot": "school_gate", "arrive": [420, 540], "until": 930, "done": false, "open": true}
	main.last_world = {"minute": 462.0, "rest": false, "needs": {"qing": {"hunger": 22, "energy": 81, "mood": 64, "clean": 47}},
		"money": {"qing": 12}, "bond": {"sync": 14, "close": 46},
		"goals": {"qing": junior, "mei": junior_mei},
		"stats": {"qing": {"body": 6.2, "mind": 5.8, "charm": 4.1, "luck": 5.0}, "mei": {"body": 4.4, "mind": 6.6, "charm": 6.9, "luck": 3.0}},
		"eff": {"qing": 1.1, "mei": 0.9},
		"tracks": {"qing": {"id": "primary", "label": "上小学", "duty": duty}, "mei": {"id": "primary", "label": "上小学", "duty": duty}}}
	if main.world != null:
		main.world.duties = {"qing": duty, "mei": duty}
	if main.has_method("_grow_up"):
		main._stage_shown = "childhood"
	if main.world != null:
		main.world.set_stage("childhood")
		main.world.set_minute(462.0)
	main._refresh_hud()
	# 对门在线，正在自己家写作业（HUD 右上那张牌）
	main._partner_online = true
	if main.world != null:
		var mei: Node2D = main.world.actors.mei
		mei.doing = "study"
		mei.action_label = "写作业"
	await _walk(Vector2(1630, 500), 3.2)
	await _snap("14_hud_online")
	# 走到河边：对门出了画面，屏幕边上一个箭头指着 TA
	if main.world != null:
		var far: Node2D = main.world.actors.mei
		far.position = Vector2(330, 1210)
		far.walk_target = far.position
		far.net_target = far.position
		far.doing = "duty"
		far.action_label = "上学"
	await _walk(Vector2(2140, 840), 4.0)
	await _snap("28_partner_pointer")
	await _walk(Vector2(1630, 500), 3.6)
	main._toast("同框 · 「俩鸡蛋，多放葱花。」你们说的是同一句。")
	main.banner.visible = true
	await _wait(0.8)
	await _snap("36_toast_banner")
	main.banner.visible = false
	main._close_modal()

	# 核心玩法：目标纸带点开、人生关口（有一条路够不着）、揭晓（同路 / 各走各的）、带成长的日结
	if main.has_method("_show_goal_detail"):
		main._show_goal_detail()
		await _wait(1.5)
		await _snap("21_goal_detail")
		main._close_modal()
		var job := {"id": "m_job", "title": "找个正经事由", "age": 22, "turns": 3, "lines": [
			{"id": "desk", "text": "考进机关坐办公室", "by": "心智", "unit": "分", "have": 74, "need": 82, "ok": false},
			{"id": "teach", "text": "回学校教书", "by": "心智和魅力", "unit": "分", "have": 66, "need": 68, "ok": false},
			{"id": "trade", "text": "自己支个摊", "by": "魅力和运气", "unit": "分", "have": 52, "need": 60, "ok": false},
			{"id": "craft", "text": "学门手艺", "by": "体魄和心智", "unit": "分", "have": 69, "need": 64, "ok": true},
			{"id": "labor", "text": "去码头上工", "by": "体魄", "unit": "分", "have": 64, "need": 60, "ok": true}]}
		var job_mei: Dictionary = job.duplicate(true)
		for i in 5:
			job_mei.lines[i].have = [70, 71, 66, 55, 44][i]
		main.last_world.goals = {"qing": job, "mei": job_mei}
		main.life = {"turn": 49}
		main._refresh_hud()
		main._show_goal_detail()
		await _wait(1.5)
		await _snap("22_goal_job")
		main._close_modal()
		main.life = {"turn": 36}
		main._on_event_started({"event": {"roles": ["qing", "mei"], "eventId": "m_junior", "kind": "milestone", "choices": {}, "swing": {"qing": 0.2, "mei": -0.1}},
			"locks": {"qing": {"key": "心智 60 分，线是 64 分"}, "mei": {}}})
		await _wait(1.5)
		await _snap("23_milestone_locked")
		main._close_modal()
		main.my_role = "mei"
		main._on_event_started({"event": {"roles": ["qing", "mei"], "eventId": "m_junior", "kind": "milestone", "choices": {}, "swing": {"qing": 0.2, "mei": -0.1}},
			"locks": {"qing": {"key": "心智 60 分，线是 64 分"}, "mei": {}}})
		await _wait(1.5)
		await _snap("24_milestone_choice")
		main.my_role = "qing"
		main._on_log_entries({"entries": [{"kind": "milestone", "label": "12 岁 · 上学期", "events": {"qing": "m_junior", "mei": "m_junior"},
			"choices": {"qing": "normal", "mei": "normal"}, "shadow": [], "resonance": true, "text": "三点半，校门口，还是你们俩。",
			"results": {"qing": {"score": 60, "unit": "分", "grade": null, "option": "normal", "track": "junior"}, "mei": {"score": 65, "unit": "分", "grade": null, "option": "normal", "track": "junior"}}}]})
		await _wait(1.9)
		await _snap("25_milestone_same")
		main._on_log_entries({"entries": [{"kind": "milestone", "label": "12 岁 · 上学期", "events": {"qing": "m_junior", "mei": "m_junior"},
			"choices": {"qing": "normal", "mei": "key"}, "shadow": [], "resonance": false, "text": "一个三点半放学，一个要上到五点。先出来的那个，在校门口的台阶上多坐了一会儿。",
			"results": {"qing": {"score": 60, "unit": "分", "grade": null, "option": "normal", "track": "junior"}, "mei": {"score": 65, "unit": "分", "grade": null, "option": "key", "track": "junior_key"}}}]})
		await _wait(1.9)
		await _snap("26_milestone_apart")
		main._on_log_entries({"entries": [{"kind": "day", "label": "11 岁 · 立秋", "text": "这一天，你们在一张桌上写完了作业。",
			"gains": {"qing": {"mind": 0.21, "body": 0.04}, "mei": {"mind": 0.16}}}]})
		await _wait(1.5)
		await _snap("27_day_gains")
		main._close_modal()
		main.life = {"turn": 17}

	# 搭伴小游戏：放风筝（试玩，不联网）
	if main.get("games") != null and main.world != null:
		main.games.my_role = "qing"
		main.games.names = main.names
		main.games.start_practice(true)
		await _wait(5.5)
		await _snap("29_kite")
		main.games.close()
		await _wait(0.3)

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
