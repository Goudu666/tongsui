extends SceneTree
## 住户本和「街坊记住了」的截图（不连服务器）。横竖屏都能截：
##   godot --path client --rendering-driver opengl3 --resolution 1920x1080 --script tools/shots/ledger.gd -- --out=<目录>
## 没有显示器的机器前面套一层 xvfb-run -a。数据是编的三世，只为看版面；规则见 docs/LEGACY.md。

var out_dir := "shots"
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


func _id(list: Array, id: String) -> String:
	for it in list:
		if str(it.id) == id:
			return id
	return str(list[0].id)


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(1.0)
	var fake: Node = load((get_script() as Script).resource_path.get_base_dir().path_join("fake_net.gd")).new()
	main.add_child(fake)
	fake.server_protocol = 3
	main.net = fake
	fake.again_state.connect(main.legacy.on_again)
	var C: Dictionary = main.content
	var fams: Array = C.families
	var tals: Array = C.talents
	var pair := func(id: String) -> String: return _id(C.endings.pair, id)
	var one := func(id: String) -> String: return _id(C.endings.lives, id)
	var person := func(nm: String, fam: int, tal: String, age: int, ending: String, job: String, left: String) -> Dictionary:
		return {"name": nm, "familyId": fams[fam].id, "talentId": _id(tals, tal), "diedAtAge": age, "ending": one.call(ending), "job": job, "heirloom": left}
	var past := [
		{"life": 1, "pair": pair.call("e_neighbors"), "close": 58, "memories": ["楼顶的鸽子", "一毛钱的冰棍", "铁桥上的晚自习", "搬家那天"], "noted": ["r_homecoming", "r_same_trade"],
			"persons": {"qing": person.call("小满", 0, "none", 79, "l_heir_teacher", "job_teach", "h_chalk"), "mei": person.call("阿蘅", 1, "pigeon", 81, "l_heir_pigeon", "job_teach", "h_whistle")}},
		{"life": 2, "pair": pair.call("e_reunited"), "close": 66, "memories": ["墙上的名字", "没回的信", "又坐到一张桌上", "一口气到桥头"], "noted": ["r_patched"],
			"persons": {"qing": person.call("立冬", 4, "stubborn", 72, "l_wanderer", "job_labor", "h_towel"), "mei": person.call("小雪", 7, "kind", 88, "l_stayer", "job_trade", "h_scale")}},
		{"life": 3, "pair": pair.call("e_four_names"), "close": 83, "memories": ["墙上的四个名字", "河边的盒子", "拉过的钩", "一个柜子里的碗"], "noted": ["r_four_names", "r_one_door", "r_wordless"],
			"persons": {"qing": person.call("谷雨", 2, "late", 84, "l_just_right", "job_craft", "h_books"), "mei": person.call("白露", 9, "linked", 84, "l_parent", "job_desk", "h_photo")}},
	]
	var legacy := {"lives": 3, "families": {}, "past": past, "traces": [], "marks": [],
		"heirlooms": ["h_chalk", "h_whistle", "h_towel", "h_scale", "h_books", "h_photo"],
		"remembered": {"r_homecoming": 1, "r_same_trade": 1, "r_patched": 2, "r_four_names": 3, "r_one_door": 3, "r_wordless": 3}}
	main.names = {"qing": "谷雨", "mei": "白露"}
	main.my_role = "qing"
	main.life = {"phase": "ended", "turn": 200, "life": 3, "legacy": legacy, "noted": ["r_four_names", "r_one_door", "r_wordless"],
		"left": {"qing": "h_books", "mei": "h_photo"}, "again": {"qing": false, "mei": true},
		"log": [{"kind": "end", "text": "八十四岁那年秋天，两个人同一年走的。墙上的四个名字还在。"}],
		"memories": [{"age": 7, "title": "墙上的四个名字", "vivid": 3}, {"age": 9, "title": "河边的盒子", "vivid": 2}, {"age": 17, "title": "拉过的钩", "vivid": 2}, {"age": 70, "title": "一个柜子里的碗", "vivid": 3}]}
	main.legacy.on_protocols({"qing": 3, "mei": 3})
	main._show_ending()
	await _wait(1.6)
	var sc := main.body.get_parent().get_parent() as ScrollContainer
	if sc != null:
		sc.scroll_vertical = 100000
	await _wait(0.4)
	await _snap("50_ending_noted")

	main.legacy.open_ledger()
	await _wait(0.5)
	var lg: Control = main.ui.get_node("Ledger")
	fake.past_life.emit(3, {"life": 3, "ending": {"pair": pair.call("e_four_names"), "lives": {"qing": one.call("l_just_right"), "mei": one.call("l_parent")}}, "close": 83,
		"persons": {"qing": {"name": "谷雨", "familyId": fams[2].id, "talentId": _id(tals, "late"), "diedAtAge": 84, "job": "job_craft", "heirloomId": "h_whistle"},
			"mei": {"name": "白露", "familyId": fams[9].id, "talentId": _id(tals, "linked"), "diedAtAge": 84, "job": "job_desk", "heirloomId": "h_scale"}},
		"memories": [{"title": "墙上的四个名字", "age": 7, "vivid": 3}, {"title": "河边的盒子", "age": 9, "vivid": 2}, {"title": "借来的自行车", "age": 12, "vivid": 0},
			{"title": "铁桥上的晚自习", "age": 15, "vivid": 1}, {"title": "拉过的钩", "age": 17, "vivid": 2}, {"title": "站台上没说的话", "age": 22, "vivid": 0},
			{"title": "两块招牌", "age": 31, "vivid": 1}, {"title": "递过去的暖壶", "age": 45, "vivid": 2}, {"title": "两个徒弟", "age": 60, "vivid": 1}, {"title": "一个柜子里的碗", "age": 70, "vivid": 3}],
		"left": {"qing": "h_books", "mei": "h_photo"}, "noted": ["r_four_names", "r_one_door", "r_wordless"], "stats": {"mirrors": 34, "rate": 74, "together": 52}})
	await _wait(0.4)
	await _snap("51_ledger_life")
	lg.show_tab("life:1")
	await _wait(0.4)
	await _snap("52_ledger_older")
	lg.show_tab("remembered")
	await _wait(0.4)
	await _snap("53_ledger_remembered")
	lg.show_tab("kept")
	await _wait(0.4)
	await _snap("54_ledger_kept")
	quit()
