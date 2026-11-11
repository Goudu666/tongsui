extends SceneTree
## 图鉴和「差一点」的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_atlas.gd
## 结局页：头一回走到的、图鉴攒到多少、差一点那一栏在「再来一世」上面 / 住户本的图鉴页：见过的、谜面、藏着的 /
## 会变的老物件底下那一句 / 投胎页提一句上一世差一点 / 旧服务器（没有 seen 和 near）照旧画、不报错。

const Op := preload("res://scripts/net/protocol.gd")


class FakeNet extends "res://scripts/net/lifeline_client.gd":
	func _send(_op: int, _body: Dictionary) -> void:
		pass
	func fetch_past(_life_no: int) -> void:
		pass


var fails := 0
var main: Node


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


func _init() -> void:
	_run()


func texts(node: Node) -> String:
	var out := []
	for l in node.find_children("*", "Label", true, false):
		out.append(l.text)
	return "\n".join(out)


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var net := FakeNet.new()
	main.net = net
	net.server_protocol = Op.VERSION
	var C: Dictionary = main.content
	var A: Dictionary = C.get("atlas", {})
	check(A.get("riddles") is Dictionary and A.get("hidden") is Array, "内容里带着图鉴（谜面、藏着的）")
	var pairs: Array = C.endings.pair
	var lives_list: Array = C.endings.lives
	var plain: Array = pairs.filter(func(e): return not A.hidden.has(e.id))
	var shy: Array = pairs.filter(func(e): return A.hidden.has(e.id))
	var got: Dictionary = plain[1]
	var old_one: Dictionary = plain[2]
	var fams: Array = C.families
	var tals: Array = C.talents

	var past := {"life": 2, "pair": got.id, "close": 60, "memories": [], "noted": [], "near": ["差一点就是「%s」：亲近 40 分，要 45 分。" % plain[0].title],
		"persons": {"qing": {"name": "立冬", "familyId": fams[0].id, "talentId": tals[0].id, "diedAtAge": 80, "ending": lives_list[-1].id, "job": null, "heirloom": "h_photo"},
			"mei": {"name": "阿蘅", "familyId": fams[1].id, "talentId": tals[0].id, "diedAtAge": 81, "ending": lives_list[-2].id, "job": null, "heirloom": "h_books"}}}
	var legacy := {"lives": 2, "families": {}, "heirlooms": ["h_photo", "h_books", "h_noted_books"], "past": [past], "remembered": {}, "traces": [], "marks": [],
		"seen": {"pair": {old_one.id: 1, got.id: 2}, "lives": {lives_list[-1].id: 1, lives_list[-2].id: 2}}}
	var near := [
		{"kind": "milestone", "id": "m_senior", "role": "mei", "text": "15 岁中考，阿蘅心智差 3 分，没够上「过桥去念重点高中」。"},
		{"kind": "pair", "id": plain[0].id, "text": "差一点就是「%s」：亲近 40 分，要 45 分。" % plain[0].title},
	]
	var ended := {"names": {"qing": "立冬", "mei": "阿蘅"}, "you": "qing", "online": {"qing": true, "mei": true}, "protocols": {"qing": Op.VERSION, "mei": Op.VERSION},
		"life": {"phase": "ended", "turn": 200, "life": 2, "log": [{"kind": "end", "text": "两个人前后脚走了。"}], "memories": [],
			"left": {"qing": "h_photo", "mei": "h_books"}, "noted": [], "near": near, "legacy": legacy}}

	# ---- 结局页：头一回走到、攒到多少、差一点在再来一世上面 ----
	main._on_snapshot(ended)
	var t := texts(main.body)
	check(t.contains("头一回走到「%s」" % got.title) and t.contains(lives_list[-2].title) and not t.contains("「%s」「" % old_one.title), "头一回走到的只写这一世新见的：\n" + t)
	check(t.contains("结局图鉴 2 / %d" % pairs.size()) and t.contains("一生 2 / %d" % lives_list.size()), "图鉴攒到多少：\n" + t)
	check(t.contains("差一点") and t.contains("阿蘅心智差 3 分") and t.contains(plain[0].title), "差一点那一栏：\n" + t)
	var card: Node = main.body.find_child("Near", true, false)
	var again_btn: Button = null
	for b in main.body.find_children("*", "Button", true, false):
		if (b as Button).text == "再来一世":
			again_btn = b
	check(card != null and again_btn != null and card.get_parent() == again_btn.get_parent() and card.get_index() < again_btn.get_index(), "差一点放在「再来一世」正上方")

	# ---- 住户本的图鉴：见过的写全、没见过的一句谜面、藏着的只有「藏」 ----
	main.legacy.open_ledger()
	var lg: Control = main.ui.get_node_or_null("Ledger")
	check(lg != null, "翻开住户本")
	if lg == null:
		quit(1)
		return
	var nav_btn := lg.find_child("Tab_atlas", true, false) as Button
	check(nav_btn != null and nav_btn.text.contains("2 / %d" % pairs.size()), "目录里有图鉴，写着见过几个：%s" % (nav_btn.text if nav_btn else "（没有）"))
	nav_btn.pressed.emit()
	t = texts(lg)
	check(lg.find_child("Got_%s" % got.id, true, false) != null and t.contains(str(got.text)) and t.contains("第 2 世") and t.contains("第 1 世"), "见过的写全、写第几世：\n" + t)
	var r0 := str(A.riddles.get(plain[0].id, ""))
	check(r0 != "" and lg.find_child("Riddle_%s" % plain[0].id, true, false) != null and t.contains(r0) and not t.contains(str(plain[0].text)), "没见过的只有谜面")
	for e in shy:
		check(lg.find_child("Hidden_%s" % e.id, true, false) != null and not t.contains(str(e.title)) and not t.contains(str(e.text)), "藏着的不露名字：" + str(e.id))
	check(not t.contains("{name}") and not t.contains("null"), "没有漏出来的占位")
	var cells := 0
	for part in ["pair", "lives"]:
		var grid: Node = lg.find_child("Atlas_%s" % part, true, false)
		cells += grid.get_child_count() if grid != null else 0
	check(cells == pairs.size() + lives_list.size(), "每个结局一格：%d" % cells)

	# ---- 老物件：会变的写一句怎么变；变过的写变成了什么 ----
	(lg.find_child("Tab_kept", true, false) as Button).pressed.emit()
	t = texts(lg)
	check(lg.find_child("Changed_h_books", true, false) != null and t.contains("变成过「批注过的书」"), "一箱书已经变过：\n" + t)
	check(lg.find_child("Next_h_photo", true, false) != null and t.contains("这件东西还会变：") and t.contains("拉一回钩"), "合影还会变：\n" + t)
	check(lg.find_child("Next_h_noted_books", true, false) != null, "批注过的书还会变")
	lg.close()
	await process_frame

	# ---- 投胎页：上一世差一点 ----
	main._on_snapshot({"names": {"qing": "小满", "mei": "阿蘅"}, "you": "qing", "online": {"qing": true, "mei": true},
		"life": {"phase": "roll", "turn": 0, "life": 3, "legacy": legacy, "rolls": {
			"qing": {"familyId": fams[0].id, "talentId": tals[0].id, "stats": {"body": 5, "mind": 5, "charm": 4, "luck": 4}, "confirmed": false, "rerollsLeft": 3, "house": 0, "offer": [], "heirloomId": null},
			"mei": {"familyId": fams[1].id, "talentId": tals[0].id, "stats": {"body": 5, "mind": 5, "charm": 4, "luck": 4}, "confirmed": false, "rerollsLeft": 3, "house": 0, "offer": [], "heirloomId": null}}}})
	var pn := main.body.find_child("PastNear", true, false) as Label
	check(pn != null and pn.text == "上一世差一点：「%s」：亲近 40 分，要 45 分。" % plain[0].title, "投胎页提一句上一世差一点：%s" % (pn.text if pn else "（没有）"))

	# ---- 旧服务器：没有 seen、没有 near，照旧画，不报错 ----
	var bare: Dictionary = ended.duplicate(true)
	bare.life.erase("near")
	bare.life.legacy.erase("seen")
	bare.life.legacy.past[0].erase("near")
	main._on_snapshot(bare)
	await process_frame
	t = texts(main.body)
	check(main.body.find_child("Near", true, false) == null and main.body.find_child("Fresh", true, false) == null and t.contains("两个人都点头"), "旧服务器不画差一点和图鉴：\n" + t)
	main.legacy.open_ledger()
	lg = main.ui.get_node_or_null("Ledger")
	(lg.find_child("Tab_atlas", true, false) as Button).pressed.emit()
	check(lg.find_child("Got_%s" % got.id, true, false) != null, "旧服务器的图鉴从小传里凑")

	if fails == 0:
		print("✓ 图鉴：结局页头一回走到 / 攒到多少 / 差一点在再来一世上面 / 图鉴页见过、谜面、藏着的 / 老物件会变 / 投胎页提一句 / 旧服务器照旧")
	quit(1 if fails > 0 else 0)
