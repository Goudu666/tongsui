extends SceneTree
## 爽感层的截图和录屏：做完一件事的飘字和搭伴印、关口揭晓、长大的阶段成绩单、成长账。
##   godot --path client --rendering-driver opengl3 --resolution 1920x1080 --script res://../tools/shots/juice.gd -- --out=<目录>
##   录屏：再加 --write-movie <x.avi> --fixed-fps 30 -- --out=<目录> --movie（不截图，只按时间轴演一遍）
## 不联网：往 main.gd 里喂和服务器一样结构的 WORLD / LOG / SNAPSHOT。

var out_dir := "user://shots_juice"
var movie := false
var main: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a == "--movie":
			movie = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _snap(name: String) -> void:
	if movie:
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name)


var _stats := {"qing": {"body": 4.6, "mind": 5.2, "charm": 4.1, "luck": 5.0}, "mei": {"body": 5.0, "mind": 4.8, "charm": 5.6, "luck": 4.0}}
var _money := {"qing": 12, "mei": 9}
var _bond := {"close": 46, "sync": 31}
var _tick := 0


func _world(acts: Dictionary, tg := false, did: Dictionary = {}) -> void:
	_tick += 2
	var actors := {}
	for r in ["qing", "mei"]:
		var a: Node2D = main.world.actors[r]
		actors[r] = {"x": a.position.x, "y": a.position.y, "act": acts.get(r), "spot": null, "sleep": false, "seq": 0, "tg": tg and acts.get(r) != null, "fr": 1, "rd": 0}
	if not did.is_empty():
		actors["qing"]["did"] = did
	main._on_world_state({"tick": _tick, "minute": 600, "slot": 1, "ready": {}, "playing": false, "wait": 0, "rest": true,
		"actors": actors, "needs": {"qing": {"hunger": 70, "energy": 64, "mood": 80, "clean": 70}, "mei": {"hunger": 60, "energy": 70, "mood": 75, "clean": 66}},
		"money": _money.duplicate(), "event": null, "bond": _bond.duplicate(), "hints": [], "stats": _stats.duplicate(true), "eff": {"qing": 1.0, "mei": 1.0},
		"goals": {"qing": _goal("qing"), "mei": _goal("mei")}, "tracks": {}})


## 纸带上的关口：小升初进重点班看心智（和服务器 lifeGoal 一样的形状）
func _goal(r: String) -> Dictionary:
	var have := int(floor(float(_stats[r].mind) * 10.0 + 0.001))
	return {"id": "m_junior", "title": "小升初", "age": 12, "turns": 9, "lines": [
		{"id": "key", "text": "去重点班", "by": "心智", "unit": "分", "have": have, "need": 74, "ok": have >= 74}]}


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(0.8)
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	for r in ["qing", "mei"]:
		main.world.actors[r].display_name = main.names[r]
	await _wait(1.6)
	main.offline_preview = false
	main._preview_minute = 600.0
	main.world.set_minute(600.0)
	main.life = {"phase": "life", "turn": 20}
	# 两个人站到一块儿
	var me: Node2D = main.world.actors.qing
	var them: Node2D = main.world.actors.mei
	them.position = me.position + Vector2(120, 0)
	them.net_target = them.position
	main.guide.process_mode = Node.PROCESS_MODE_DISABLED  # 开局引导的章首卡、小纸条不来凑热闹（长大那张卡上的章名照样有）
	await _juice_journal(36)
	_world({})
	await _wait(0.3)
	while main.fx.is_busy():  # 开局引导的章首卡先过去
		await _wait(0.2)
	await _wait(0.6)
	main.juice.on_snapshot({"lifelineId": "", "life": {"phase": "life", "turn": 20, "persons": {
		"qing": {"alive": true, "stats": _stats.qing, "money": 12}, "mei": {"alive": true, "stats": _stats.mei, "money": 9}}, "bond": _bond}})
	await _wait(0.4)
	await _snap("j00_hud")

	# 1. 搭伴写作业：开始（脚下一圈墨），做完（搭伴印 + 飘字飞进成长账）
	_world({"qing": "study", "mei": "study"}, true)
	await _wait(0.2)
	await _snap("j01_start")
	await _wait(1.0)
	_stats.qing.mind += 0.45
	_stats.qing.charm += 0.1
	_stats.mei.mind += 0.32
	_bond.close += 2
	_world({}, false, {"n": 7, "a": "study", "l": "写作业", "tg": true, "b": 1.6})
	await _wait(0.2 + main.juice.DID_LEAD)  # 有 did：先让钟拨过去、人把事做完
	await _snap("j02_stamp")
	await _wait(0.5)
	await _snap("j03_tags")
	await _wait(0.75)
	await _snap("j04_fly")
	await _wait(0.6)
	await _snap("j05_landed")
	await _wait(1.4)

	# 2. 一个人修车挣钱
	_world({"qing": "work"})
	await _wait(0.9)
	_stats.qing.body += 0.2
	_money.qing += 8
	_world({})
	await _wait(0.85)
	await _snap("j06_money")
	await _wait(1.8)

	# 3. 关口揭晓：高考，一个够着了外地，一个够着本市、差一点没够上外地
	main.life = {"phase": "life", "turn": 66}
	main._on_log_entries({"entries": [{"kind": "milestone", "label": "18 岁", "age": 18, "events": {"qing": "m_gaokao", "mei": "m_gaokao"},
		"choices": {"qing": "local", "mei": "away"}, "shadow": [], "resonance": false,
		"text": "一个留在本市，一个坐上了往南的车。车开以前，你们在站台上把那包瓜子分完了。",
		"results": {
			"qing": {"score": 81, "scored": true, "unit": "分", "grade": "过了本科线", "option": "local", "track": "uni_local", "line": 68, "luck": -3, "steady": 2, "near": {"option": "away", "need": 84, "have": 81, "unit": "分", "label": "心智"}},
			"mei": {"score": 86, "scored": true, "unit": "分", "grade": "过了本科线", "option": "away", "track": "uni_away", "line": 84, "luck": 2}}}]})
	await _wait(0.75)
	await _snap("j07_reveal_counting")
	await _wait(0.6)
	await _snap("j08_reveal_mid")
	await _wait(1.4)
	await _snap("j09_reveal_done")
	await _wait(1.6)
	main._close_modal()
	await _wait(0.6)

	# 4. 一个人的关：小升初，差 2 分没进重点班
	main._on_log_entries({"entries": [{"kind": "milestone", "label": "12 岁 · 上学期", "age": 12, "events": {"qing": "m_junior"},
		"choices": {"qing": "normal"}, "shadow": [], "resonance": null, "text": "",
		"results": {"qing": {"score": 72, "scored": true, "unit": "分", "grade": null, "option": "normal", "track": "junior", "luck": -2, "near": {"option": "key", "need": 74, "have": 72, "unit": "分", "label": "心智"}}}}]})
	await _wait(2.6)
	await _snap("j10_miss")
	await _wait(1.0)
	main._close_modal()
	await _wait(0.5)

	# 5. 长大：少年过完（18 岁）的墨卡上放成绩单，最上面是这一章两场冲刺的总账
	main.life = {"phase": "life", "turn": 48}
	main._stage_shown = "teen"
	await _juice_journal(48)  # 前面演飘字的时候记了几个点，换成一整段童年加少年
	main.juice._record(48, _stats)
	main._grow_up({"age": 18, "stage": "young"})
	await _wait(1.7)
	await _snap("j11_stage_report")
	await _wait(2.0)
	await _snap("j12_stage_report_done")
	await _wait(3.0)

	# 6. 成长账（点 HUD 左边那条）
	main._show_growth()
	await _wait(2.4)
	await _snap("j13_growth")
	await _wait(1.0)
	main._close_modal()
	await _wait(0.5)
	quit()


## 假的成长账：童年九年一年四个日子、少年一年两个，两个人一路长上来（读书的心智长得快，TA 魅力长得快）
func _juice_journal(turns: int) -> void:
	var LifeTime := load("res://scripts/ui/life_time.gd")
	var pts: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var q := [33.0, 36.0, 31.0]
	var m := [36.0, 33.0, 38.0]
	for turn in turns:
		var t: Dictionary = LifeTime.at(turn)
		pts.append([turn, int(t.age), str(t.stage), int(q[0]), int(q[1]), int(q[2]), int(m[0]), int(m[1]), int(m[2])])
		q[0] += rng.randf_range(0.1, 0.5)
		q[1] += rng.randf_range(0.3, 0.9)
		q[2] += rng.randf_range(0.0, 0.5)
		m[0] += rng.randf_range(0.2, 0.5)
		m[1] += rng.randf_range(0.1, 0.6)
		m[2] += rng.randf_range(0.3, 0.8)
	main.juice.journal = {"pts": pts, "stages": {"childhood": {"tg": 23, "res": 4, "ms": 2,
		"list": [{"a": 9, "t": "三年级", "o": "进数学小组", "ok": true}]},
		"teen": {"tg": 14, "res": 3, "ms": 2, "list": [
			{"a": 12, "t": "小升初", "o": "去普通班", "gap": 2, "u": "分", "mt": "去重点班"},
			{"a": 15, "t": "中考", "o": "过桥去念重点高中", "ok": true, "g": "考进全区前五十"}]}}}
	_stats.qing = {"body": q[0] / 10.0, "mind": q[1] / 10.0, "charm": q[2] / 10.0, "luck": 5.0}
	_stats.mei = {"body": m[0] / 10.0, "mind": m[1] / 10.0, "charm": m[2] / 10.0, "luck": 4.0}
