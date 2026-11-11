extends SceneTree
## 关口上拉一把的界面（不需要服务器）：godot --headless --path client -s res://tests/unit_pull.gd
## 规则在 server/src/pull.ts（server/test/pull.test.mjs）；这里查选路卡上的字、揭晓卡对门那截算不算过线。
## 画面靠 tools/shots/pull.gd 出图。

const Pull := preload("res://scripts/duet/pull_text.gd")
const Reveal := preload("res://scripts/ui/reveal.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


func _initialize() -> void:
	var score := {"by": "mei", "gap": 3, "unit": "分", "reach": 6}
	var money := {"by": "mei", "gap": 28, "unit": "块", "reach": 40}
	check(Pull.mine(score, "阿蘅") == "差 3 分 · 和阿蘅一起走这条，TA 拉你过去", "差分的那个：" + Pull.mine(score, "阿蘅"))
	check(Pull.theirs(score, "小满").begins_with("小满差 3 分"), "拉人的那个看到对门差多少")
	check(Pull.theirs(money, "小满").contains("垫上"), "钱是垫上")
	check(Pull.headline({"far": score}, {}, "阿蘅").contains("默契够，最多拉得动 6 分"), "差分的那个看到为什么拉得动（默契）")
	check(Pull.headline({}, {"buy": money}, "小满").contains("亲近够，最多垫得了 40 块"), "拉人的那个看到为什么垫得了（亲近）")
	check(Pull.headline({}, {"x": "坏数据", "far": score}, "小满").contains("6 分"), "pulls 里混了别的形状也不出错")

	check(Pull.goal_mine(score, "阿蘅") == "阿蘅能拉你 3 分", "目标条：我差的那条写谁能拉、差多少")
	check(Pull.goal_mine(money, "阿蘅") == "阿蘅能垫你 28 块", "目标条：钱是垫")
	check(Pull.goal_theirs(score, "小满") == "你能拉小满 3 分", "目标条：对门那头")
	var GP := preload("res://scripts/ui/goal_panel.gd")
	var g := {"id": "m_senior", "lines": [{"id": "far", "have": 73, "need": 76, "pull": score}]}
	check(GP.their_line(g, "far").get("pull") is Dictionary, "their_line 找得到那条线")
	check(GP.their_line(null, "far").is_empty() and GP.their_line(g, "near").is_empty(), "找不到给空的")

	var r := Reveal.new()
	r.score = 73
	r.line = 76
	check(not r.passed(), "73 不过 76")
	r.pull = 3
	check(r.passed(), "对门拉了 3 分就过")
	r.pull = 2
	check(not r.passed(), "拉 2 分还差 1 分")
	r.free()

	if fails == 0:
		print("✓ 拉一把：选路卡上的字（分、钱、默契亲近）/ 揭晓时对门那截算进过线")
	quit(1 if fails > 0 else 0)
