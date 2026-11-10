extends SceneTree
## 人生长卷的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_scroll.gd
## 查的是从 life 整理出来的东西对不对：哪几关同路、哪几关各走各的、线在哪并在哪分、谁先走了。画得好不好看靠 tools/shots/scroll.gd 出图。

const LifeScroll := preload("res://scripts/ui/life_scroll.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


func _gate(turn: int, age: int, id: String, q: Variant, m: Variant, shadow: Array = []) -> Dictionary:
	var results := {}
	if q != null:
		results["qing"] = {"score": 72, "unit": "分", "grade": null, "option": q, "track": ""}
	if m != null:
		results["mei"] = {"score": 0, "scored": false, "unit": "分", "grade": "过了本科线", "option": m, "track": ""}
	return {"turn": turn, "age": age, "kind": "milestone", "minute": 630, "events": {"qing": id if q != null else null, "mei": id if m != null else null},
		"choices": {"qing": q, "mei": m}, "shadow": shadow, "resonance": q != null and q == m, "text": "", "results": results}


func _initialize() -> void:
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	var log: Array = []
	for t in 74:
		log.append({"turn": t, "age": 3, "kind": "day", "minute": null, "text": ""})
	for t in [0, 1, 1, 5, 40]:
		log.append({"turn": t, "age": 3, "kind": "together", "minute": 700, "text": ""})
	log.append(_gate(12, 6, "m_school", "study", "study"))
	log.append(_gate(36, 12, "m_junior", "key", "normal", ["mei"]))
	log.append(_gate(48, 18, "m_gaokao", "away", null))
	log.append({"turn": 71, "age": 66, "kind": "death", "minute": 910, "text": "阿蘅 在 66 岁那年离开了。"})
	log.append(_gate(72, 70, "m_evening", "walk", null))
	var life := {
		"log": log, "bond": {"close": 50.0, "sync": 20.0},
		"memories": [
			{"title": "一个收一个发", "eventId": "m_school", "turn": 12, "age": 6, "vivid": 0},
			{"title": "第四十七颗星", "eventId": "c_summer_roof", "turn": 5, "age": 4, "vivid": 2},
		],
		"persons": {"qing": {"name": "小满", "alive": true}, "mei": {"name": "阿蘅", "alive": false, "diedAtAge": 66}},
		"ending": {"pair": str(content.endings.pair[0].id), "lives": {"qing": str(content.endings.lives[0].id), "mei": str(content.endings.lives[1].id)}},
	}
	var m: Dictionary = LifeScroll.build(life, content)
	check(m.stations.size() == 4, "四个关口四站")
	check(bool(m.stations[0].same) and str(m.stations[0].memory) == "一个收一个发" and not bool(m.stations[0].vivid), "同路的那一站带着这一关的回忆（褪了色也在）")
	check(not bool(m.stations[1].same) and bool(m.stations[1].both), "各走各的")
	check(bool(m.stations[1].roads.mei.shadow) and not bool(m.stations[1].roads.qing.shadow), "影子替选的记在那个人头上")
	check(not bool(m.stations[2].both) and not m.stations[2].roads.has("mei"), "只有一个人过的关")
	check(m.stations[0].roads.mei.score == null and int(m.stations[0].roads.qing.score) == 72, "不看分的路不画分数")
	check(str(m.stations[0].roads.qing.text) == "当学习委员", "路名只留头一句：" + str(m.stations[0].roads.qing.text))
	check(m.memories.size() == 1 and str(m.memories[0].title) == "第四十七颗星", "关口以外的回忆单独列")
	check(m.counts.same == 1 and m.counts.apart == 1 and m.counts.together == 5 and m.counts.days == 74 and m.counts.memories == 2, "题词里的数")
	check(m.deaths.has("mei") and int(m.deaths.mei.age) == 66 and int(m.deaths.mei.turn) == 71 and not m.deaths.has("qing"), "谁在哪一年走的")
	check(str(m.pair.title) != "" and str(m.lives.qing.text).find("{name}") < 0, "结局的字，名字填好了")

	var scroll: Control = LifeScroll.new()
	scroll.setup(life, content, {"qing": "小满", "mei": "阿蘅"})
	check(scroll.custom_minimum_size.y == LifeScroll.HEIGHT and scroll.custom_minimum_size.x > 1920.0, "比一屏宽，高度固定")
	var prev := -1.0
	var rising := true
	for t in 76:
		var x: float = scroll.x_of(float(t))
		rising = rising and x >= prev
		prev = x
	check(rising, "日子往右走，不回头")
	var x0: float = scroll.x_of(12.0)
	var x1: float = scroll.x_of(36.0)
	check(absf(scroll.sep_at(x0) - LifeScroll.SEP_SAME) < 0.01, "同路的那一站两条线并在一起")
	check(absf(scroll.sep_at(x0 + 60.0) - LifeScroll.SEP_SAME) < 0.01, "出了站还并着走一段")
	check(absf(scroll.sep_at(x1) - LifeScroll.SEP_APART) < 0.01, "各走各的那一站分开了")
	check(scroll.sep_at(LifeScroll.LEFT) == LifeScroll.SEP_START, "开头是两扇对着的门")
	# 对门走了以后，剩下的那条线回到正中间
	var far: float = float(scroll._anchors[-1].x)
	check(absf(scroll._lane("qing", far) - LifeScroll.MID) < 0.5, "一个人走完的那一段在纸的正中间")
	check(scroll._end_x("mei") < scroll._end_x("qing"), "先走的那条线先停")
	scroll.free()

	# 空的人生（刚开局就看）也不报错
	var empty: Dictionary = LifeScroll.build({}, content)
	check(empty.stations.is_empty() and empty.deaths.is_empty(), "空的也画得出来")

	if fails == 0:
		print("✓ 人生长卷：同路 / 各走各的 / 一个人过的关 / 影子 / 回忆 / 先走的人 / 题词 / 线的并和分")
	quit(1 if fails > 0 else 0)
