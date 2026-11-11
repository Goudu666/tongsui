extends SceneTree
## 爽感层的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_juice.gd
## 查的是「数对不对、该不该飘」：分数按百分制往下取整（和关口纸带一个口径）、开着弹窗不飘、
## 成长账按日子记点、换了一世从头记、长大时成绩单讲的是刚过完的那一段、揭晓的过线判定、成长账那条的数等飘字落下才拨。
## 画得好不好看、手感对不对靠 tools/shots/juice.gd 出图录屏。

const Juice := preload("res://scripts/ui/juice.gd")
const StatStrip := preload("res://scripts/ui/stat_strip.gd")
const Reveal := preload("res://scripts/ui/reveal.gd")
const Report := preload("res://scripts/ui/stage_report.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


## 只有 juice.gd 读的那几样
class FakeMain extends Node:
	var my_role := "qing"
	var modal: Control = null
	var fx = null
	var world = null
	var hud = null
	var ui: Control = null
	var life: Dictionary = {"turn": 0}
	var stat_strip = null
	var events_by_id := {"m_junior": {"title": "小升初", "grades": [{"min": 8.6, "label": "考进年级前十"}, {"min": 0, "label": ""}], "options": [{"id": "key", "text": "去重点班", "min": 7.4}, {"id": "normal", "text": "普通班"}]},
		"m_school": {"title": "上小学", "options": [{"id": "go", "text": "背上书包"}]}}


func _world(stats: Dictionary, money := 10, close := 40) -> Dictionary:
	return {"stats": stats, "money": {"qing": money, "mei": 5}, "bond": {"close": close, "sync": 20}, "actors": {"qing": {"act": null}, "mei": {"act": null}}}


func _tags(j: Node) -> int:
	var n := 0
	for c in j.get_children():
		if c is Juice.Tag:
			n += 1
	return n


func _initialize() -> void:
	check(Juice.points(5.79) == 57 and Juice.points(5.8) == 58 and Juice.points(6.0) == 60, "百分制往下取整（57.9 不能显示成 58）")

	var m := FakeMain.new()
	m.ui = Control.new()
	m.ui.size = Vector2(1920, 1080)
	m.modal = Control.new()
	m.modal.visible = false
	root.add_child(m)
	var j := Juice.new()
	j.main = m
	root.add_child(j)

	# 飘字：头一帧只记底数；涨了才飘；只涨了 0.04（不到 1 分）不飘；开着弹窗不飘
	j.on_world(_world({"qing": {"body": 4.0, "mind": 5.0, "charm": 3.0}, "mei": {"body": 4.0, "mind": 4.0, "charm": 4.0}}))
	check(_tags(j) == 0, "头一帧不飘")
	j.on_world(_world({"qing": {"body": 4.04, "mind": 5.0, "charm": 3.0}, "mei": {"body": 4.0, "mind": 4.0, "charm": 4.0}}))
	check(_tags(j) == 0, "不到 1 分不飘")
	j.on_world(_world({"qing": {"body": 4.04, "mind": 5.35, "charm": 3.0}, "mei": {"body": 4.0, "mind": 4.0, "charm": 4.0}}, 18, 42))
	check(_tags(j) == 3, "心智 +3、钱 +8、亲近 +2 各一张（实际 %d）" % _tags(j))
	m.modal.visible = true
	var before := _tags(j)
	j.on_world(_world({"qing": {"body": 4.5, "mind": 5.35, "charm": 3.0}, "mei": {"body": 4.0, "mind": 4.0, "charm": 4.0}}, 18, 42))
	check(_tags(j) == before, "开着弹窗不飘（关口、当天小结里另有交代）")
	m.modal.visible = false
	j.on_world(_world({"qing": {"body": 4.5, "mind": 5.35, "charm": 3.0}, "mei": {"body": 4.0, "mind": 4.0, "charm": 4.0}}, 18, 42))
	check(_tags(j) == before, "弹窗关了也不补飘（底数跟着走了）")

	# 成长账：一个日子一个点，同一天只改不加；回到更早的日子（再来一世）从头记
	j.journal = {"pts": [], "stages": {}}
	for turn in [0, 0, 1, 2, 35, 36]:
		m.life = {"turn": turn}
		j._record(turn, {"qing": {"body": 3.0 + turn * 0.05, "mind": 3.0, "charm": 3.0}, "mei": {"body": 3.0, "mind": 3.0, "charm": 3.0}})
	check(j.journal.pts.size() == 5, "同一天只留一个点（实际 %d）" % j.journal.pts.size())
	check(str(j.journal.pts[-1][2]) == "teen" and str(j.journal.pts[-2][2]) == "childhood", "36 回合是少年、35 还是童年")
	var rep: Control = j.stage_report()
	check(rep != null and rep.stage == "childhood", "长大那一刻讲的是刚过完的童年")
	if rep != null:
		var fl: Array = rep._first_last()
		check(int(fl[1][3]) == Juice.points(3.0 + 36 * 0.05), "童年的「到」是长大那一刻的数")
		rep.free()
	j.on_log([{"kind": "together", "age": 8}, {"kind": "together", "age": 8}, {"kind": "mirror", "age": 9, "resonance": true}, {"kind": "mirror", "age": 9, "resonance": false},
		{"kind": "milestone", "age": 12, "results": {"qing": {}}}, {"kind": "milestone", "age": 12, "results": {"mei": {}}}])
	check(j.journal.stages.get("childhood", {}).get("tg", 0) == 2 and j.journal.stages.childhood.get("res", 0) == 1, "搭伴两回、想到一块儿一回")
	check(j.journal.stages.get("teen", {}).get("ms", 0) == 1, "12 岁的关算进少年；对门一个人过的关不算我的")
	# 成绩单上的关口总账：走了哪条路、过没过线、离没走成的那条差几分；只有一条路的关不记
	j.on_log([{"kind": "milestone", "age": 12, "events": {"qing": "m_junior"}, "results": {"qing": {"score": 72, "scored": true, "unit": "分", "option": "normal", "grade": null,
		"near": {"option": "key", "need": 74, "have": 72, "unit": "分", "label": "心智"}}}},
		{"kind": "milestone", "age": 13, "events": {"qing": "m_junior"}, "results": {"qing": {"score": 80, "scored": true, "unit": "分", "option": "key", "line": 74, "grade": "考进年级前十"}}},
		{"kind": "milestone", "age": 6, "events": {"qing": "m_school"}, "results": {"qing": {"score": 0, "scored": false, "option": "go"}}}])
	var rows: Array = j.journal.stages.get("teen", {}).get("list", [])
	check(rows.size() == 2, "两道有路可挑的关进了总账，上小学不进（实际 %d）" % rows.size())
	if rows.size() == 2:
		check(rows[0].o == "普通班" and not rows[0].has("ok") and int(rows[0].gap) == 2 and rows[0].mt == "去重点班", "普通班没有线不盖印，差 2 分没够上「去重点班」：%s" % str(rows[0]))
		check(rows[1].ok and rows[1].g == "考进年级前十" and not rows[1].has("gap"), "够着了：盖名次档")
		check(Juice.rank_of({"grades": [{"min": 9.3, "label": "考进全市前一百"}, {"min": 6.8, "label": "过了本科线"}, {"min": 0, "label": "没过线"}]}, "没过线") == "" and Juice.rank_of({"grades": [{"min": 9.3, "label": "考进全市前一百"}, {"min": 0, "label": "没过线"}]}, "考进全市前一百") == "考进全市前一百", "兜底那档不算名次")
		check(Report.ledger_height(j.journal.stages.teen) > 0.0 and Report.ledger_height({}) == 0.0, "有总账才多占地方")
	check(int(j.journal.stages.get("childhood", {}).get("ms", 0)) == 1 and not j.journal.stages.childhood.has("list"), "只有一条路的关只算个数")
	j._record(3, {"qing": {"body": 3.0, "mind": 3.0, "charm": 3.0}})
	check(j.journal.pts.size() == 1 and j.journal.stages.is_empty(), "回到更早的日子：换了一世，从头记")
	check(j.stage_report() == null, "只有一个点：没有成绩单")

	# 成长账那条：飘字在路上的时候数不动，落下来才拨上去
	var s := StatStrip.new()
	root.add_child(s)
	s.stats = {"body": 4.0, "mind": 5.0, "charm": 3.0}
	s._process(0.016)
	s.stats = {"body": 4.0, "mind": 5.4, "charm": 3.0}
	s.hold("mind", 1.0)
	for i in 30:
		s._process(0.016)
	check(int(round(s._shown.mind)) == 50, "飘字还在路上：心智还是 50")
	s.land("mind", 4)
	for i in 60:
		s._process(0.016)
	check(int(round(s._shown.mind)) == 54, "落下来以后拨到 54（实际 %s）" % str(s._shown.mind))
	check(s.cell_rect("mind").position.x > s.cell_rect("body").position.x, "三格从左到右：体魄、心智、魅力")

	# 揭晓：过线看走的这条路的线
	var r := Reveal.new()
	r.score = 70
	r.line = 68
	check(r.passed(), "70 分过 68 的线")
	r.line = 74
	check(not r.passed(), "70 分不过 74")
	r.line = -1
	check(not r.passed(), "不看分的路不盖「过线」")
	r.free()
	check(Report.has_stage([[0, 3, "childhood", 1, 1, 1, 1, 1, 1]], "childhood") and not Report.has_stage([], "teen"), "成长账里有没有这一段")

	if fails == 0:
		print("✓ 爽感层：百分制取整 / 不到 1 分不飘 / 开着弹窗不飘 / 成长账一天一点、换一世从头记 / 成绩单讲刚过完的那段 / 搭伴和关口计数 / 数等飘字落下才拨 / 过线判定")
	quit(1 if fails > 0 else 0)
