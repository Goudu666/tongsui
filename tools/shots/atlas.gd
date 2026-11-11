extends SceneTree
## 图鉴和「差一点」的截图（不连服务器）：
##   godot --path client --rendering-driver opengl3 --resolution 2400x1080 --script ../tools/shots/atlas.gd -- --out=<目录>
## 没有显示器的机器前面套一层 xvfb-run -a。数据是编的第三世，只为看版面；规则见 docs/LEGACY.md 第十三节。

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


func _scroll_to(node: Node, y: int) -> void:
	var sc := node.find_child("PageScroll", true, false) as ScrollContainer
	if sc != null:
		sc.scroll_vertical = y


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(1.0)
	var fake: Node = load((get_script() as Script).resource_path.get_base_dir().path_join("fake_net.gd")).new()
	main.add_child(fake)
	fake.server_protocol = 6
	main.net = fake
	fake.again_state.connect(main.legacy.on_again)
	var C: Dictionary = main.content
	var fams: Array = C.families
	var tals: Array = C.talents
	var one := func(id: String) -> String: return _id(C.endings.lives, id)
	var person := func(nm: String, fam: int, age: int, ending: String, left: String) -> Dictionary:
		return {"name": nm, "familyId": fams[fam].id, "talentId": tals[0].id, "diedAtAge": age, "ending": one.call(ending), "job": "job_teach", "heirloom": left}
	var near := [
		{"kind": "milestone", "id": "m_senior", "role": "mei", "text": "15 岁中考，白露心智差 2 分，没够上「过桥去念重点高中」。"},
		{"kind": "pair", "id": "e_white_hair", "text": "差一点就是「白头」：亲近 41 分，要 45 分。"},
		{"kind": "life", "id": "l_scholar", "role": "qing", "text": "谷雨差一点就是「读书人」：心智 86 分，要 90 分。"},
	]
	var past := [
		{"life": 1, "pair": "e_nod", "close": 22, "memories": ["楼顶的鸽子"], "noted": [], "near": ["9 岁三年级，小满魅力差 1 分，没够上「进少年宫的曲艺队」。"],
			"persons": {"qing": person.call("小满", 0, 79, "l_parent", "h_photo"), "mei": person.call("阿蘅", 1, 66, "l_early", "h_books")}},
		{"life": 2, "pair": "e_neighbors", "close": 58, "memories": ["墙上的名字"], "noted": ["r_homecoming"], "near": ["差一点就是「同岁」：就差跟对门成一家。"],
			"persons": {"qing": person.call("立冬", 4, 72, "l_wanderer", "h_photo_two"), "mei": person.call("小雪", 7, 88, "l_stayer", "h_noted_books")}},
		{"life": 3, "pair": "e_reunited", "close": 41, "memories": ["墙上的四个名字"], "noted": ["r_patched"], "near": [near[0].text, near[1].text],
			"persons": {"qing": person.call("谷雨", 2, 84, "l_parent", "h_letters"), "mei": person.call("白露", 9, 81, "l_heir_teacher", "h_chalk")}},
	]
	var seen := {"pair": {"e_nod": 1, "e_neighbors": 2, "e_reunited": 3}, "lives": {"l_parent": 1, "l_early": 1, "l_wanderer": 2, "l_stayer": 2, "l_heir_teacher": 3}}
	var legacy := {"lives": 3, "families": {}, "past": past, "traces": [], "marks": [], "seen": seen,
		"heirlooms": ["h_photo", "h_books", "h_photo_two", "h_noted_books", "h_letters", "h_chalk"],
		"remembered": {"r_homecoming": 2, "r_patched": 3}}
	main.names = {"qing": "谷雨", "mei": "白露"}
	main.my_role = "qing"
	main.life = {"phase": "ended", "turn": 200, "life": 3, "legacy": legacy, "noted": ["r_patched"], "near": near,
		"left": {"qing": "h_letters", "mei": "h_chalk"}, "again": {"qing": false, "mei": true},
		"log": [{"kind": "end", "text": "「重逢」走散过很多年。后来在海河边又碰上了，谁也没提那些年，只说了一句：「吃了吗您？」"}],
		"memories": [{"age": 7, "title": "墙上的四个名字", "vivid": 3}, {"age": 17, "title": "拉过的钩", "vivid": 2}, {"age": 52, "title": "海河边又碰上", "vivid": 3}]}
	main.legacy.on_protocols({"qing": 6, "mei": 6})
	main._show_ending()
	await _wait(1.6)
	var sc := main.body.get_parent().get_parent() as ScrollContainer
	if sc != null:
		sc.scroll_vertical = 100000
	await _wait(0.4)
	await _snap("60_ending_near")
	if sc != null:
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value * 0.45)
	await _wait(0.4)
	await _snap("59_ending_fresh")

	main.legacy.open_ledger()
	await _wait(0.5)
	var lg: Control = main.ui.get_node("Ledger")
	lg.show_tab("atlas")
	await _wait(0.5)
	await _snap("61_atlas_pair")
	_scroll_to(lg, 1500)
	await _wait(0.4)
	await _snap("62_atlas_lives")
	lg.show_tab("remembered")
	await _wait(0.4)
	await _snap("63_remembered_all")
	lg.show_tab("kept")
	await _wait(0.4)
	await _snap("64_kept_chain")
	lg.close()
	await _wait(0.3)

	# 第四世的投胎页：上一世差一点
	var roll := func(fam: int) -> Dictionary:
		return {"familyId": fams[fam].id, "talentId": tals[0].id, "stats": {"body": 5, "mind": 6, "charm": 4, "luck": 4}, "confirmed": false, "rerollsLeft": 3, "house": 0, "offer": [], "heirloomId": null}
	var r1: Dictionary = roll.call(3)
	r1.offer = ["h_photo_two", "h_noted_books", "h_letters"]
	var r2: Dictionary = roll.call(5)
	r2.offer = ["h_photo", "h_books", "h_chalk"]
	legacy.lives = 3
	main.life = {"phase": "roll", "turn": 0, "life": 4, "legacy": legacy, "rolls": {"qing": r1, "mei": r2}}
	main._show_roll()
	await _wait(1.2)
	await _snap("65_roll_past_near")
	quit()
