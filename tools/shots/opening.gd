extends SceneTree
## 开局一小时的截图：章首卡、头几天的小纸条、主线路标、长大和进新一章并成的那张卡。
##   node tools/shots/opening_dump.mjs <json>   先从真服务器取几帧状态
##   godot --path client --rendering-driver opengl3 --resolution 1920x1080 --script res://../tools/shots/opening.gd -- --out=<目录> --frames=<json>
##   加 --movie（配合 Godot 的 --write-movie x.avi --fixed-fps 30）录一段约 50 秒的开局：标题、投胎、章首卡、小纸条、第一件主线、路标、长大
## 不联网：把取来的 SNAPSHOT / WORLD 原样喂给 main.gd。

var out_dir := "user://shots"
var frames_path := ""
var main: Node
var frames: Dictionary = {}
var _feed: Dictionary = {}
var movie := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a == "--movie":
			movie = true
		if a.begins_with("--frames="):
			frames_path = a.trim_prefix("--frames=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.remove_absolute("user://guide.cfg")  # 小纸条从头出
	frames = JSON.parse_string(FileAccess.get_file_as_string(frames_path))
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name, " ", img.get_size())


## 服务器一秒发五回 WORLD：这里也一直喂着，guide 和 HUD 才会动
func _pump() -> void:
	while true:
		await create_timer(0.2).timeout
		if not _feed.is_empty() and main.world != null:
			var w: Dictionary = _feed.duplicate(true)
			main._on_world_state(w)


func _frame(name: String) -> void:
	var f: Dictionary = frames[name]
	main._on_snapshot(f.snapshot)
	_feed = f.world


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(1.0)
	_pump()
	if movie:
		await _movie()
		quit()
		return
	# 头一天：一进来是第一章的章首卡
	_frame("day0_morning")
	await _wait(1.3)
	await _snap("o01_chapter1")
	await _wait(3.6)
	await _snap("o02_tip_walk")
	main.guide._hide_tip()
	await _wait(2.8)
	await _snap("o03_tip_story")
	main.guide._hide_tip()
	await _wait(2.8)
	await _snap("o04_tip_slot")
	main.guide._hide_tip()
	# 下了楼：主线在楼道里，路标指着「上楼」
	_frame("day0_street")
	await _wait(1.6)
	await _snap("o05_route")
	# 6 岁：第二章（没赶上长大，单放一张章首卡）
	_frame("day12")
	await _wait(1.5)
	await _snap("o06_chapter2")
	await _wait(4.5)
	# 12 岁：长大成少年那张卡上也写着第三章
	_frame("day36")
	await _wait(1.6)
	await _snap("o07_stage_chapter3")
	await _wait(4.0)
	await _snap("o08_teen")
	quit()


func _movie() -> void:
	await _wait(1.5)  # 标题
	var fams: Array = main.content.families
	var tals: Array = main.content.talents
	main.names = {"qing": "小满", "mei": "阿蘅"}
	main._set_role("qing")
	main.life = {"phase": "roll", "turn": 0, "rolls": {
		"qing": {"familyId": fams[11].id, "talentId": tals[0].id, "stats": {"body": 6, "mind": 7, "charm": 4, "luck": 5}, "confirmed": false, "rerollsLeft": 2},
		"mei": {"familyId": fams[4].id, "talentId": tals[3].id, "stats": {"body": 4, "mind": 5, "charm": 8, "luck": 5}, "confirmed": true, "rerollsLeft": 1},
	}}
	main._show_roll()
	await _wait(3.5)
	_frame("day0_morning")
	await _wait(9.0)  # 章首卡揭开，第一张纸条
	main.guide._hide_tip()
	await _wait(4.0)  # 主线小签那张
	main.guide._hide_tip()
	await _wait(3.5)
	main.guide._hide_tip()
	# 第一件主线：上午，楼道里，隔着门敲三下
	var ev: Dictionary = {}
	for e in main.content.story.events:
		if int(e.chapter) == 1 and int(e.beat) == 1:
			ev = e
			break
	main._on_event_started({"event": {"roles": ["qing", "mei"], "eventId": ev.id, "kind": "mirror"}})
	await _wait(4.5)
	main._show_mirror_result({"label": "3 岁 · 立春", "events": {"qing": ev.id, "mei": ev.id},
		"choices": {"qing": ev.options[0].id, "mei": ev.options[0].id}, "shadow": [], "resonance": true,
		"text": _resonance_text(ev)})
	await _wait(4.0)
	main._close_modal()
	_frame("day0_street")
	await _wait(4.0)  # 路标：主线在楼里，指着「上楼」
	_frame("day12")
	await _wait(6.0)
	_frame("day36")
	await _wait(7.5)



## 共鸣那句：剧本里按选项写（{选项: {text…}}），取两个人都选了的第一个选项那句
func _resonance_text(ev: Dictionary) -> String:
	var r = ev.get("resonance", null)
	if r is Dictionary:
		var one = r.get(str(ev.options[0].id), null)
		if one is Dictionary and one.has("text"):
			return str(one.text)
	if r is String:
		return r
	return "隔着一扇门，两个人敲的是同一个拍子。"
