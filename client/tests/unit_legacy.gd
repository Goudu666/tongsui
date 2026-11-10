extends SceneTree
## 传承界面的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_legacy.gd
## 用真的主场景 + 一个只记账的假联机层，把 投胎页挑老物件 / 结局页留下了什么 / 再来一世 / 新旧版本混搭 各走一遍。

const Op := preload("res://scripts/net/protocol.gd")


class FakeNet extends "res://scripts/net/lifeline_client.gd":
	var sent := []
	func _send(op: int, body: Dictionary) -> void:
		sent.append([op, body])


var fails := 0
var main: Node
var net: FakeNet


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


func _init() -> void:
	_run()


func texts() -> String:
	var out := []
	for l in main.body.find_children("*", "Label", true, false):
		out.append(l.text)
	return "\n".join(out)


func buttons() -> Array:
	return main.body.find_children("*", "Button", true, false)


func button(text: String) -> Button:
	for b in buttons():
		if b.text == text:
			return b
	return null


func tag(id: String) -> Button:
	return main.body.find_child("Heirloom_%s" % id, true, false) as Button


func roll(family: String, more := {}) -> Dictionary:
	var r := {"familyId": family, "talentId": main.content.talents[0].id, "stats": {"body": 5, "mind": 5, "charm": 4, "luck": 4},
		"confirmed": false, "rerollsLeft": 3, "house": 0, "offer": [], "heirloomId": null}
	r.merge(more, true)
	return r


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	net = FakeNet.new()
	main.net = net
	net.server_protocol = Op.VERSION
	net.again_state.connect(main.legacy.on_again)
	var fams: Array = main.content.families
	var hs: Array = main.content.get("heirlooms", [])
	check(hs.size() >= 10 and hs.all(func(h): return h.has("name") and h.has("desc")), "内容里带着老物件")
	check(Op.AGAIN == 31 and Op.LEGACY_SINCE == 3, "协议常量")
	var a := str(hs[0].id)
	var b := str(hs[1].id)
	var c := str(hs[2].id)

	# ---- 头一世：投胎页和以前一样 ----
	main._on_snapshot({"names": {"qing": "小满", "mei": "阿蘅"}, "you": "qing", "online": {"qing": true, "mei": true},
		"life": {"phase": "roll", "turn": 0, "life": 1, "rolls": {"qing": roll(fams[0].id), "mei": roll(fams[1].id)}}})
	check(texts().contains("你出生在……") and not texts().contains("世") and not texts().contains("老物件"), "头一世不提第几世、不摆东西：\n" + texts())

	# ---- 第二世：页头、小传、家业、各自面前的老物件 ----
	var pair: Dictionary = main.content.endings.pair[0]
	var legacy := {"lives": 1, "families": {}, "heirlooms": [a, b, c], "past": [{"life": 1, "pair": pair.id, "close": 60, "memories": [],
		"persons": {"qing": {"name": "小满", "diedAtAge": 79}, "mei": {"name": "阿蘅", "diedAtAge": 81}}}]}
	var snap := {"names": {"qing": "小满", "mei": "阿蘅"}, "you": "qing", "online": {"qing": true, "mei": true}, "protocols": {"qing": 3, "mei": 3},
		"life": {"phase": "roll", "turn": 0, "life": 2, "legacy": legacy,
			"rolls": {"qing": roll(fams[0].id, {"offer": [a, b], "house": 2}), "mei": roll(fams[1].id, {"offer": [c, "h_gone"]})}}}
	main._on_snapshot(snap)
	var t := texts()
	check(t.contains("第 2 世") and t.contains("上一世「%s」 · 小满 79 岁 · 阿蘅 81 岁" % pair.title), "页头和上一世的小传：\n" + t)
	var per := int(main.content.rules.legacy.houseMoney)
	check(per > 0 and t.contains("家里的营生传了 2 代，家底多 %d 块" % (per * 2)), "家业那一行：\n" + t)
	check(t.contains(hs[0].name) and t.contains(hs[0].desc) and t.contains(hs[1].name), "我面前的两件")
	check(t.contains("TA 面前摆着：" + str(hs[2].name)) and not t.contains("h_gone"), "对门面前的看得见；内容里没有的不摆：\n" + t)
	check(tag(a) != null and tag(b) != null and tag(c) == null, "只有自己面前的能点")
	check(main.legacy.effect_text({"bonus": {"mind": 0.5}, "money": 10, "close": 6}) == "心智 +5　零花钱 +10 块　亲近 +6", "加成的写法")

	# 点一件：发给服务器；服务器回了以后原地改，不整页重画
	tag(a).pressed.emit()
	check(net.sent == [[Op.ROLL, {"heirloom": a}]], "挑一件：%s" % [net.sent])
	net.sent.clear()
	var body_was: Node = main.body
	var rolls: Dictionary = snap.life.rolls.duplicate(true)
	rolls.qing.heirloomId = a
	main._on_roll_state({"rolls": rolls})
	check(main.body == body_was, "只换了手里的东西，页面不重画")
	check(texts().contains("带上") and tag(a) != null, "挑中的盖上「带上」")
	tag(a).pressed.emit()
	check(net.sent == [[Op.ROLL, {"heirloom": null}]], "再点一下是放下：%s" % [net.sent])
	net.sent.clear()
	tag(b).pressed.emit()
	check(net.sent == [[Op.ROLL, {"heirloom": b}]], "换一件直接点另一件")
	net.sent.clear()
	# 对门挑了：我这边看得见
	rolls = rolls.duplicate(true)
	rolls.mei.heirloomId = c
	main._on_roll_state({"rolls": rolls})
	check(main.body == body_was and texts().contains("带上了"), "对门带上了哪件看得见：\n" + texts())
	# 重抽了：整页重画（出生证换了）
	rolls = rolls.duplicate(true)
	rolls.qing.familyId = fams[2].id
	rolls.qing.rerollsLeft = 2
	main._on_roll_state({"rolls": rolls})
	check(main.body != body_was, "换了人家要重画")
	# 确认以后：定了，不能再点
	rolls = rolls.duplicate(true)
	rolls.qing.confirmed = true
	main._on_roll_state({"rolls": rolls})
	check(tag(a) == null and tag(b) == null and texts().contains("带着「%s」出生。" % hs[0].name), "确认以后定下来：\n" + texts())

	# ---- 结局页：留下了什么、再来一世 ----
	var ended := {"names": {"qing": "小满", "mei": "阿蘅"}, "you": "qing", "online": {"qing": true, "mei": true}, "protocols": {"qing": 3, "mei": 3},
		"life": {"phase": "ended", "turn": 200, "life": 2, "log": [{"kind": "end", "text": "两个人前后脚走了。"}], "memories": [],
			"left": {"qing": a, "mei": c}}}
	main._on_snapshot(ended)
	t = texts()
	check(t.contains("留给河畔里") and t.contains(hs[0].name) and t.contains(hs[2].desc), "留下了什么：\n" + t)
	check(button("再来一世") != null and not button("再来一世").disabled and button("回到标题") != null, "再来一世的按钮")
	button("再来一世").pressed.emit()
	check(net.sent == [[Op.AGAIN, {"yes": true}]], "点头：%s" % [net.sent])
	net.sent.clear()
	body_was = main.body
	net.again_state.emit({"again": {"qing": true, "mei": false}})
	check(main.body == body_was, "票变了只改那一栏")
	check(texts().contains("你点了头。等 TA 也点头……") and button("再来一世") == null and button("再想想") != null, "点了以后等 TA：\n" + texts())
	button("再想想").pressed.emit()
	check(net.sent == [[Op.AGAIN, {"yes": false}]], "收回：%s" % [net.sent])
	net.sent.clear()
	net.again_state.emit({"again": {"qing": false, "mei": true}})
	check(texts().contains("阿蘅 想再来一世。") and button("再来一世") != null, "TA 先点了：\n" + texts())
	# TA 下线了
	net.again_state.emit({"again": {"qing": true, "mei": false}})
	main._on_presence({"online": {"qing": true, "mei": false}, "protocols": {"qing": 3, "mei": 0}})
	check(texts().contains("TA 不在。等 TA 回来点头。"), "TA 不在线：\n" + texts())
	# TA 用旧安装包上来了：说清楚，按钮按不了
	net.again_state.emit({"again": {"qing": false, "mei": false}})
	main._on_presence({"online": {"qing": true, "mei": true}, "protocols": {"qing": 3, "mei": 2}})
	check(texts().contains("TA 的安装包还是旧的") and button("再来一世").disabled, "TA 的安装包旧：\n" + texts())
	# 连着旧服务器：没有再来一世，回到标题还是主按钮
	net.server_protocol = 2
	var old_server: Dictionary = ended.duplicate(true)
	old_server.erase("protocols")
	old_server.life.erase("left")
	main._on_snapshot(old_server)
	check(button("再来一世") == null and button("回到标题") != null and not texts().contains("留给河畔里"), "旧服务器：结局页和以前一样：\n" + texts())
	net.server_protocol = Op.VERSION

	# 两个人都点了：服务器发来新一世的快照，直接到投胎页
	var third: Dictionary = snap.duplicate(true)
	third.life.life = 3
	main.last_world = {"stats": {"qing": {"body": 9}}}
	main._on_snapshot(third)
	check(texts().contains("第 3 世") and main.last_world.is_empty(), "新的一世：到投胎页，上一世的属性不留着")

	# ---- 大厅：第几世 ----
	check(main.legacy.life_text({"life": 1}) == "" and main.legacy.life_text({}) == "" and main.legacy.life_text({"life": 4}) == "第 4 世 · ", "大厅里的第几世")

	if fails == 0:
		print("✓ 传承界面：头一世照旧 / 第二世的页头、小传、家业、两边的老物件 / 挑、放下、换、确认 / 留给河畔里 / 再来一世的四种状态 / 旧服务器、旧安装包 / 大厅")
	quit(1 if fails > 0 else 0)
