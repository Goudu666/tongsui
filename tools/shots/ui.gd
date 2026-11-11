extends SceneTree
## 界面截图（重做界面线程用的子集）：把游戏开到各个界面，各存一张 PNG。用来做画面改动的前后对比。
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
	var cfg := ConfigFile.new()
	for k in ["walk", "story", "slot", "wait", "together", "gate", "need", "night", "day", "goal"]:
		cfg.set_value("tips", k, true)
	cfg.save("user://guide.cfg")
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(1.2)
	await _snap("01_title")
	main.guide.process_mode = Node.PROCESS_MODE_DISABLED
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	if main.world != null:
		for r in ["qing", "mei"]:
			main.world.actors[r].display_name = main.names[r]
	await _wait(2.5)
	await _snap("03_world_morning")
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
	# 联机时的 HUD：四个圆表、零花钱、两个圆（假装服务器发来了状态）
	main.offline_preview = false
	main.life = {"turn": 17}
	var junior := {"id": "m_junior", "title": "小升初", "age": 12, "turns": 14, "lines": [
		{"id": "key", "text": "去重点班", "by": "心智", "unit": "分", "have": 58, "need": 64, "ok": false}]}
	var junior_mei: Dictionary = junior.duplicate(true)
	junior_mei.lines[0].have = 66
	junior_mei.lines[0].ok = true
	var duty := {"label": "上学", "spot": "school_gate", "arrive": [420, 540], "until": 930, "done": false, "open": true}
	main.last_world = {"minute": 390.0, "slot": 0, "ready": {"qing": false, "mei": true}, "playing": false, "rest": false, "needs": {"qing": {"hunger": 22, "energy": 81, "mood": 64, "clean": 47}},
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
		await _many_paths()
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


func _many_paths() -> void:
	for id in ["m_job", "m_school"]:
		var ev: Dictionary = main.events_by_id.get(id, {})
		if ev.get("options", []).size() < 4:
			continue
		var locks: Dictionary = {}
		for o in ev.options:
			if o.has("min") and locks.is_empty():
				locks[o.id] = "心智 58 分，线是 64 分"
		main._close_modal()
		main.my_role = "qing"
		main._on_event_started({"event": {"roles": ["qing", "mei"], "eventId": id, "kind": "milestone", "choices": {}, "swing": {"qing": -0.2, "mei": 0.1}, "steady": {"qing": 0.3}},
			"locks": {"qing": locks, "mei": {}}})
		await _wait(1.5)
		await _snap("37_paths_%d" % ev.options.size())
	main._close_modal()
