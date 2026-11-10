extends SceneTree
## 住户本和「街坊记住了」的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_ledger.gd
## 用真的主场景 + 假联机层：结局页盖的章 / 入口什么时候有 / 目录和每一页 / 服务器那一页来了以后 / 更早的几世 / 横竖两种排法。

const Op := preload("res://scripts/net/protocol.gd")


class FakeNet extends "res://scripts/net/lifeline_client.gd":
	var asked := []
	func _send(_op: int, _body: Dictionary) -> void:
		pass
	func fetch_past(life_no: int) -> void:
		asked.append(life_no)


var fails := 0
var main: Node
var net: FakeNet


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
	for s in node.find_children("*", "Control", true, false):
		if s.get("text") is String and not s is Label and not s is Button:
			out.append(s.text)  # 章上的字是画出来的
	return "\n".join(out)


func ledger() -> Control:
	return main.ui.get_node_or_null("Ledger") as Control


func tab(id: String) -> Button:
	return ledger().find_child("Tab_%s" % id, true, false) as Button


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	net = FakeNet.new()
	main.net = net
	net.server_protocol = Op.VERSION
	var C: Dictionary = main.content
	var rem: Array = C.get("remembered", [])
	var hs: Array = C.heirlooms
	var fams: Array = C.families
	var tals: Array = C.talents
	var pair: Dictionary = C.endings.pair[0]
	var lives_end: Dictionary = C.endings.lives[0]
	check(rem.size() >= 10 and rem.all(func(a): return a.has("title") and a.has("desc")), "内容里带着街坊记住的事")

	var past1 := {"life": 1, "pair": pair.id, "close": 71, "memories": ["墙上的名字", "一口气到桥头"], "noted": [rem[0].id],
		"persons": {"qing": {"name": "小满", "familyId": fams[0].id, "talentId": tals[1].id, "diedAtAge": 79, "ending": lives_end.id, "job": "job_teach", "heirloom": hs[0].id},
			"mei": {"name": "阿蘅", "familyId": fams[1].id, "talentId": tals[0].id, "diedAtAge": 81, "ending": lives_end.id, "job": "job_craft", "heirloom": hs[1].id}}}
	var past2: Dictionary = past1.duplicate(true)
	past2.life = 2
	past2.noted = [rem[1].id, "r_gone"]
	past2.persons.qing.name = "立冬"
	var legacy := {"lives": 2, "families": {}, "heirlooms": [hs[0].id, hs[1].id, "h_gone"], "past": [past1, past2],
		"remembered": {rem[0].id: 1, rem[1].id: 2, "r_gone": 2}, "traces": [], "marks": [], "jobs": ["job_teach", "job_craft"]}
	var ended := {"names": {"qing": "立冬", "mei": "阿蘅"}, "you": "qing", "online": {"qing": true, "mei": true}, "protocols": {"qing": Op.VERSION, "mei": Op.VERSION},
		"life": {"phase": "ended", "turn": 200, "life": 2, "log": [{"kind": "end", "text": "两个人前后脚走了。"}], "memories": [],
			"left": {"qing": hs[0].id, "mei": hs[1].id}, "noted": [rem[1].id, "r_gone"], "legacy": legacy}}

	# ---- 头一世还没走完过：没有入口；走完的结局页没记住什么就不画那一栏 ----
	var first: Dictionary = ended.duplicate(true)
	first.life.life = 1
	first.life.noted = []
	first.life.legacy = {"lives": 0, "families": {}, "heirlooms": [], "past": []}
	main._on_snapshot(first)
	check(main.body.find_child("OpenLedger", true, false) == null, "一世都没走完过，不该有住户本")
	check(main.body.find_child("Noted", true, false) == null and not texts(main.body).contains("街坊"), "没记住什么就不提街坊：\n" + texts(main.body))

	# ---- 结局页：这一世街坊新记住的事盖一枚章；内容里没有的那条不画 ----
	main._on_snapshot(ended)
	var t := texts(main.body)
	check(t.contains("街坊记住了") and t.contains(rem[1].title) and t.contains(rem[1].desc), "结局页的章：\n" + t)
	check(not t.contains(rem[0].title) and not t.contains("r_gone"), "只盖这一世新记住的：\n" + t)
	check(not t.contains("/") and not t.contains("还差"), "不写进度")
	var open := main.body.find_child("OpenLedger", true, false) as Button
	check(open != null and open.text == "翻翻住户本", "结局页有住户本的入口")
	# 票变了那一栏重画，章和入口还在
	main.legacy.on_again({"again": {"qing": true, "mei": false}})
	check(main.body.find_child("Noted", true, false) != null and main.body.find_child("OpenLedger", true, false) != null, "票变了以后章还在")

	# ---- 翻开：先翻到最近的一世，照着小传画；同时去服务器取那一页 ----
	(main.body.find_child("OpenLedger", true, false) as Button).pressed.emit()
	await process_frame
	var lg := ledger()
	check(lg != null, "住户本盖在页面上")
	if lg == null:
		quit(1)
		return
	main.legacy.open_ledger()
	check(main.ui.find_children("Ledger*", "Control", false, false).size() == 1, "再点一次不会翻开两本")
	check(lg.tab == "life:2" and net.asked == [2], "先翻到最近的一世，并去取那一页：%s %s" % [lg.tab, net.asked])
	check(tab("life_2") != null and tab("life_1") != null and tab("remembered") != null and tab("kept") != null, "目录：两世、记住的事、老物件")
	t = texts(lg)
	check(t.contains("第 2 世") and t.contains(pair.title) and t.contains("立冬") and t.contains("阿蘅"), "这一世的页头和两个人：\n" + t)
	check(t.contains("活到 79 岁") and t.contains("活到 81 岁") and t.contains(fams[0].name) and t.contains(tals[1].name), "活到多少岁、生在哪家：\n" + t)
	check(t.contains("教书") and t.contains("手艺") and t.contains(lives_end.title), "营生和一生：\n" + t)
	check(t.contains(hs[0].name) and t.contains(hs[1].name), "留下的老物件")
	check(t.contains("墙上的名字") and t.contains("这一世，街坊记住了") and t.contains(rem[1].title) and not t.contains(rem[0].title), "回忆和这一世的章：\n" + t)

	# 服务器那一页到了：回忆带上岁数，多一行默契；带来的老物件也有了
	var page := {"life": 2, "ending": {"pair": pair.id, "lives": {"qing": lives_end.id, "mei": lives_end.id}}, "close": 71,
		"persons": {"qing": {"name": "立冬", "familyId": fams[0].id, "talentId": tals[1].id, "diedAtAge": 79, "job": "job_teach", "heirloomId": hs[2].id},
			"mei": {"name": "阿蘅", "familyId": fams[1].id, "talentId": tals[0].id, "diedAtAge": 81, "job": "job_craft", "heirloomId": null}},
		"memories": [{"title": "墙上的名字", "age": 7, "vivid": 2}, {"title": "一口气到桥头", "age": 45, "vivid": 0}, {"title": "递过去的暖壶", "age": 46, "vivid": 1}],
		"left": {"qing": hs[0].id, "mei": hs[1].id}, "noted": [rem[1].id], "stats": {"mirrors": 20, "rate": 62, "together": 31}}
	net.past_life.emit(2, page)
	t = texts(lg)
	check(t.contains("7 岁 墙上的名字") and t.contains("46 岁 递过去的暖壶"), "回忆带上岁数：\n" + t)
	check(t.contains("十回有六回想到了一起"), "默契那一行：\n" + t)
	var Ledger := load("res://scripts/ui/ledger_ui.gd")
	check(Ledger.rate_line(100) == "遇到的事，回回都想到了一起" and Ledger.rate_line(3) == "遇到的事，没有一回想到一起" and Ledger.rate_line(74) == "遇到的事，十回有七回想到了一起", "默契率两头的写法")
	check(t.contains("带来") and t.contains(hs[2].name), "带来的老物件")
	for bad in ["rng", "seed", "flags", "null", "<null>"]:
		check(not t.contains(bad), "页面上不该出现 %s" % bad)

	# ---- 换一世：小传里有的马上画，再去取 ----
	tab("life_1").pressed.emit()
	t = texts(lg)
	check(lg.tab == "life:1" and net.asked == [2, 1] and t.contains("第 1 世") and t.contains("小满") and t.contains(rem[0].title), "翻到第 1 世：\n" + t)
	tab("life_2").pressed.emit()
	check(net.asked == [2, 1] and texts(lg).contains("7 岁 墙上的名字"), "取过的那一页不再取")

	# ---- 记住的事：只列记住了的，写上第几世；没记住的一个字不提 ----
	tab("remembered").pressed.emit()
	t = texts(lg)
	check(t.contains(rem[0].title) and t.contains(rem[1].title) and t.contains("第 1 世") and t.contains("第 2 世"), "记住的事：\n" + t)
	var untold := 0
	for a in rem.slice(2):
		if t.contains(str(a.desc)):
			untold += 1
	check(untold == 0 and not t.contains("/") and not t.contains("还差") and not t.contains("？"), "没记住的不显示、不占位、不数数：\n" + t)

	# ---- 老物件：攒下的都列着，内容里没有的不列 ----
	tab("kept").pressed.emit()
	t = texts(lg)
	check(t.contains(hs[0].name) and t.contains(hs[0].desc) and t.contains(hs[1].name) and not t.contains("h_gone") and not t.contains("+"), "留着的老物件（不写加成）：\n" + t)

	# ---- 更早的几世：小传里没有，只能等服务器；取不到就说没留下来 ----
	var many: Dictionary = ended.duplicate(true)
	many.life.life = 9
	many.life.legacy.lives = 9
	main.life = many.life
	lg.close()
	await process_frame
	check(ledger() == null, "合上")
	net.asked.clear()
	main.legacy.open_ledger()
	lg = ledger()
	check(lg.tab == "life:9" and tab("life_9") != null and tab("life_3") != null, "九世都在目录里")
	check(texts(lg).contains("正在翻……"), "小传里没有的先等着：\n" + texts(lg))
	net.past_life.emit(9, null)
	check(texts(lg).contains("这一页没有留下来。"), "取不到：\n" + texts(lg))
	net.past_life.emit(9, page)
	check(texts(lg).contains("7 岁 墙上的名字"), "后来取到了就画上")

	# ---- 横着拿、竖着拿 ----
	lg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lg.size = Vector2(2400, 1080)
	await process_frame
	var nav := lg.find_child("Nav", true, false)
	check(lg._wide and nav is VBoxContainer and lg.find_child("Person_qing", true, false).get_parent() is HBoxContainer, "横屏：目录在左边一栏，两个人并排")
	check(lg.find_child("Close", true, false) != null, "横屏有合上")
	lg.size = Vector2(1080, 1920)
	await process_frame
	nav = lg.find_child("Nav", true, false)
	check(not lg._wide and nav is HBoxContainer and lg.find_child("Person_qing", true, false).get_parent() is VBoxContainer, "竖屏：目录是顶上一排，两个人上下")
	(lg.find_child("Close", true, false) as Button).pressed.emit()
	await process_frame
	check(ledger() == null, "点合上就回去")

	# ---- 投胎页：第二世起有入口，头一世没有 ----
	main._on_snapshot({"names": {"qing": "小满", "mei": "阿蘅"}, "you": "qing", "online": {"qing": true, "mei": true},
		"life": {"phase": "roll", "turn": 0, "life": 3, "legacy": legacy, "rolls": {
			"qing": {"familyId": fams[0].id, "talentId": tals[0].id, "stats": {"body": 5, "mind": 5, "charm": 4, "luck": 4}, "confirmed": false, "rerollsLeft": 3, "house": 0, "offer": [], "heirloomId": null},
			"mei": {"familyId": fams[1].id, "talentId": tals[0].id, "stats": {"body": 5, "mind": 5, "charm": 4, "luck": 4}, "confirmed": false, "rerollsLeft": 3, "house": 0, "offer": [], "heirloomId": null}}}})
	check(main.body.find_child("OpenLedger", true, false) != null, "第三世的投胎页能翻住户本")

	if fails == 0:
		print("✓ 住户本：结局页盖章 / 入口 / 目录和每一页 / 服务器那一页 / 更早的几世 / 记住的事只列记住了的 / 横竖两种排法")
	quit(1 if fails > 0 else 0)
