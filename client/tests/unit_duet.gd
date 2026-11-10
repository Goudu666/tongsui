extends SceneTree
## 「接话」界面的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_duet.gd
## 用真的主场景 + 一个只记账的假联机层，把 默契事件选项 / 三种结算 / 回话 / 结局闲话 各走一遍。

const Op := preload("res://scripts/net/protocol.gd")
const Resonance := preload("res://scripts/ui/resonance.gd")
const DuetUI := preload("res://scripts/duet/duet_ui.gd")


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


func buttons() -> Array:
	return main.modal_body.find_children("*", "Button", true, false)


func press(text: String) -> void:
	for b in buttons():
		if b.text == text:
			b.pressed.emit()
			return
	check(false, "没有「%s」这个按钮，只有 %s" % [text, buttons().map(func(b): return b.text)])


func texts() -> String:
	var out := []
	for l in main.modal_body.find_children("*", "Label", true, false):
		out.append(l.text)
	return "\n".join(out)


func seal() -> Variant:
	var found: Array = main.modal_body.find_children("*", "Control", true, false).filter(func(c): return c is Resonance)
	return found[0] if found.size() == 1 else null


func entry(event_id: String, a: String, b: String, more := {}) -> Dictionary:
	var e := {
		"turn": 12, "age": 8, "label": "8 岁 · 春", "kind": "mirror", "minute": 600,
		"events": {"qing": event_id, "mei": event_id}, "choices": {"qing": a, "mei": b},
		"shadow": [], "resonance": a == b, "text": "……",
	}
	e.merge(more, true)
	return e


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main._start_preview()  # 进世界（离线，不连服务器）
	net = FakeNet.new()
	main.net = net
	main.life = {"phase": "life", "turn": 12, "log": [], "memories": []}
	await process_frame
	var ev: Dictionary = main.events_by_id["d_kite_tree"]
	check(ev.get("catches", []).size() == 1, "内容里带着搭上了")
	check(main.content.duet.echo.has("ask") and not main.content.duet.has("lines"), "内容里带着接话的文案，没有猜 TA 的旁白")

	# ---- 默契事件：选了就发，不再猜 TA ----
	main._on_event_started({"event": {"eventId": "d_kite_tree", "kind": "mirror", "roles": ["qing", "mei"]}})
	check(buttons().size() == 3, "默契事件三个选项")
	press(ev.options[0].text)
	check(net.sent == [[Op.CHOOSE, {"optionId": "climb"}]], "选了就发，不带 guess：%s" % [net.sent])
	check(texts().contains("TA 还在想") and not texts().contains("猜猜"), "发完等 TA，没有猜 TA 那一步")
	net.sent.clear()
	# 各自的事
	var solo: Dictionary = main.content.events.filter(func(e): return e.kind == "solo")[0]
	main._on_event_started({"event": {"eventId": solo.id, "kind": "solo", "roles": ["qing"]}})
	press(solo.options[0].text)
	check(net.sent == [[Op.CHOOSE, {"optionId": solo.options[0].id}]], "各自的事直接发")
	net.sent.clear()

	# ---- 结算：共鸣 / 搭上了 / 错位 ----
	main._on_log_entries({"entries": [entry("d_kite_tree", "climb", "hold", {
		"resonance": true, "text": ev.catches[0].text,
		"duet": {"outcome": "catch"},
	})]})
	check(main.modal.visible and texts().contains("搭上了") and texts().contains("一个上树"), "搭上了的卡：\n" + texts())
	check(seal() != null and seal().outcome == "catch", "印：扣在一起")
	main._on_log_entries({"entries": [entry("d_kite_tree", "wait", "wait", {"duet": {"outcome": "res", "knew": {"qing": null, "mei": null}, "line": null}})]})
	check(texts().contains("共鸣") and seal().outcome == "res", "共鸣的卡")
	main._on_log_entries({"entries": [entry("d_kite_tree", "climb", "wait", {"shadow": ["mei"], "duet": {"outcome": "miss", "owed": "mei", "line": null}})]})
	check(texts().contains("错位") and seal().outcome == "miss" and texts().contains("（影子）"), "错位的卡")
	check(texts().contains("等本人回来接"), "影子替 TA 选的：告诉我话先悬着")
	# 老服务器的日志没有 duet：按 resonance 画
	main._on_log_entries({"entries": [entry("d_kite_tree", "hold", "hold")]})
	check(texts().contains("共鸣") and seal().outcome == "res", "没有 duet 字段也能画")
	check(DuetUI.outcome_of({"resonance": false}) == "miss", "没有 duet 字段的错位")

	# ---- 回话 ----
	main.life["duet"] = {"keep": 8, "epitaph": ["影子替梅去过 1 回，有 0 回选得跟本人一样。"], "owed": {"mei": [], "qing": [
		{"turn": 9, "age": 8, "label": "8 岁 · 春", "eventId": "d_kite_tree", "shadow": "wait", "partner": "hold", "outcome": "miss"},
		{"turn": 10, "age": 8, "label": "8 岁 · 春", "eventId": "d_broken_window", "shadow": "run", "partner": "own", "outcome": "miss"},
		{"turn": 2, "age": 6, "label": "6 岁 · 春", "eventId": "d_radio_show", "shadow": "fix", "partner": "pick", "outcome": "miss"},
		{"turn": 11, "age": 8, "label": "8 岁 · 夏", "eventId": "no_such_event", "shadow": "a", "partner": "b", "outcome": "miss"},
	]}}
	check(main.duet.owed_list().size() == 2, "过期的、事件已经不在的不问")
	press("嗯")  # 关掉上一张结算卡 → 接着问欠着的
	check(main.modal.visible and texts().contains("你不在的那天") and texts().contains(main.content.duet.echo.ask), "关了弹窗就问欠着的话：\n" + texts())
	check(texts().contains(ev.title) and not texts().contains("（影子）"), "盲答：不说影子和 TA 选了什么")
	check(buttons().size() == 5, "三个选项 + 先不说 + 不提了")
	press(ev.options[0].text)
	check(net.sent == [[Op.ECHO, {"turn": 9, "optionId": "climb"}]], "回话：%s" % [net.sent])
	check(main.duet.owed_list().size() == 1, "回过的不再问")
	net.sent.clear()
	var echo_entry := {
		"turn": 12, "age": 8, "label": "8 岁 · 夏", "kind": "solo", "minute": 600, "shadow": [], "resonance": null,
		"events": {"qing": "d_kite_tree", "mei": null}, "choices": {"qing": "climb", "mei": null}, "text": ev.catches[0].text,
		"duet": {"echo": true, "role": "qing", "outcome": "catch", "was": "miss", "like": false, "shadow": "wait", "partner": "hold",
			"partnerKnew": true, "turn": 9, "label": "8 岁 · 春", "lines": ["隔了三个日子，还是搭上了。", "影子替你选的是「等风把它吹下来」。它还得学。"]},
	}
	main._on_log_entries({"entries": [echo_entry]})
	check(texts().contains("回话 · 8 岁 · 春") and texts().contains("搭上了") and texts().contains("它还得学"), "回话的结算卡：\n" + texts())
	check(seal() != null and seal().outcome == "catch", "回话的印")
	press("嗯")
	check(texts().contains(main.events_by_id["d_broken_window"].title), "接着问下一句")
	press("不提了")
	check(net.sent == [[Op.ECHO, {"turn": 10, "optionId": null}]], "不提了：%s" % [net.sent])
	check(not main.modal.visible and main.duet.owed_list().is_empty(), "都问完了")
	# 先不说：这一天不再问，下一个日子的快照来了再问
	main.life.duet.owed.qing = [{"turn": 11, "age": 8, "label": "8 岁 · 夏", "eventId": "d_radio_show", "shadow": "fix", "partner": "pick", "outcome": "miss"}]
	main.duet.check_owed()
	check(main.modal.visible, "又欠了一句")
	press("先不说")
	check(not main.modal.visible, "先不说")
	main.duet.check_owed()
	check(not main.modal.visible, "这一天不再问")
	main.duet.on_snapshot()
	check(main.modal.visible, "下一个日子再问")
	main.duet._later()
	# 对门回话：补上了弹卡，没补上只提一句；我正在弹窗里时不打断
	var theirs := echo_entry.duplicate(true)
	theirs.events = {"qing": null, "mei": "d_kite_tree"}
	theirs.choices = {"qing": null, "mei": "climb"}
	theirs.duet.role = "mei"
	main._on_log_entries({"entries": [theirs]})
	check(main.modal.visible and texts().contains("回话 · "), "TA 把话接上了：我也看到")
	main._close_modal()
	theirs.duet.outcome = "miss"
	main._on_log_entries({"entries": [theirs]})
	check(not main.modal.visible and main.toast_label.text.contains("梅回了「%s」那天的话" % ev.title), "没补上只提一句：" + main.toast_label.text)

	# ---- 结局多出来的几句 ----
	check(main.duet.ending_lines() == ["影子替梅去过 1 回，有 0 回选得跟本人一样。"], "结局闲话")
	main.life.erase("duet")
	check(main.duet.ending_lines().is_empty() and main.duet.owed_list().is_empty(), "老服务器没有 duet 也不出错")

	if fails == 0:
		print("✓ 接话界面：默契事件选了就发 / 三种结算和印 / 回话（盲答、先不说、不提了、过期不问）/ 对门回话 / 结局闲话")
	main.queue_free()
	await process_frame
	quit(1 if fails > 0 else 0)
