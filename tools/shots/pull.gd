extends SceneTree
## 关口上拉一把（server/src/pull.ts）的截图：差几分的那个看到的选路卡、拉得动的那个看到的选路卡、揭晓时对门那截接上去、重逢那一句。
##   godot --path client --rendering-driver opengl3 --resolution 1920x1080 --script res://../tools/shots/pull.gd -- --out=<目录>
## 不联网：往 main.gd 里喂和服务器一样结构的 EVENT / LOG。

var out_dir := "user://shots_pull"
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
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name)


func _pe() -> Dictionary:
	return {"eventId": "m_senior", "kind": "milestone", "roles": ["qing", "mei"], "choices": {}, "shadow": [], "swing": {"qing": 0, "mei": 0.1}, "steady": {}}


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(0.8)
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	await _wait(1.6)
	main.offline_preview = false
	main.guide.process_mode = Node.PROCESS_MODE_DISABLED
	main.life = {"phase": "life", "turn": 40}
	while main.fx.is_busy():
		await _wait(0.2)
	await _wait(0.4)
	var locks := {"qing": {"far": "心智 73 分，线是 76 分"}, "mei": {}}
	var pulls := {"qing": {"far": {"by": "mei", "gap": 3, "unit": "分", "reach": 4}}}

	# 1. 差 3 分的那个（小满）：外地那条不灰了，写着要和阿蘅一起走
	main.my_role = "qing"
	main._on_event_started({"event": _pe(), "locks": locks, "pulls": pulls})
	await _wait(0.9)
	await _snap("p01_pulled_choose")
	main._close_modal()
	await _wait(0.4)

	# 2. 拉得动的那个（阿蘅）：外地那条下面写着小满差 3 分
	main.my_role = "mei"
	main._on_event_started({"event": _pe(), "locks": locks, "pulls": pulls})
	await _wait(0.9)
	await _snap("p02_puller_choose")
	main._close_modal()
	await _wait(0.4)

	# 3. 揭晓：小满自己数到 73，阿蘅的颜色接上 3 分，过线盖印；底下一句谁拉的、一句重逢
	main.my_role = "qing"
	main._on_log_entries({"entries": [{"kind": "milestone", "label": "15 岁", "age": 15, "events": {"qing": "m_senior", "mei": "m_senior"},
		"choices": {"qing": "far", "mei": "far"}, "shadow": [], "resonance": true,
		"text": "两张录取通知书是同一天到的。",
		"gate": {"pull": {"qing": {"by": "mei", "gap": 3, "unit": "分"}}, "reunion": 3, "lines": [
			{"text": "小满差 3 分。阿蘅把自己那份往这边推了推，两个人一块儿过去了。", "role": "mei"},
			{"text": "各走各的三年，到这儿又走到一条路上了。"}]},
		"results": {
			"qing": {"score": 73, "scored": true, "unit": "分", "grade": null, "option": "far", "track": "hs_far", "line": 76},
			"mei": {"score": 82, "scored": true, "unit": "分", "grade": null, "option": "far", "track": "hs_far", "line": 76, "luck": 1}}}]})
	await _wait(1.3)
	await _snap("p03_reveal_counting")
	await _wait(1.0)
	await _snap("p04_reveal_pulled")
	await _wait(1.8)
	await _snap("p05_reveal_done")
	main._close_modal()
	await _wait(0.4)

	# 4. 安家：差 28 块，阿蘅塞过去
	main._on_log_entries({"entries": [{"kind": "milestone", "label": "30 岁", "age": 30, "events": {"qing": "m_settle", "mei": "m_settle"},
		"choices": {"qing": "buy", "mei": "buy"}, "shadow": [], "resonance": true, "text": "",
		"gate": {"pull": {"qing": {"by": "mei", "gap": 15, "unit": "块"}}, "lines": [{"text": "小满差 15 块。阿蘅没吭声，把钱塞进了小满的兜里。", "role": "mei"}]},
		"results": {
			"qing": {"score": 185, "scored": true, "unit": "块", "grade": null, "option": "buy", "track": "", "line": 200},
			"mei": {"score": 260, "scored": true, "unit": "块", "grade": null, "option": "buy", "track": "", "line": 200}}}]})
	await _wait(3.6)
	await _snap("p06_money")
	quit(0)
