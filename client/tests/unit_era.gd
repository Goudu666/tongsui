extends SceneTree
## 年代大事层的客户端单测（不需要服务器）：godot --headless --path client -s res://tests/unit_era.gd
## 查的是：年代卡怎么排字（几条连着来、我这一句用我的颜色）、HUD 日历牌上的字、街景按 era.look 还是按人生阶段、
## 投胎页的两行、长卷上的「年代 · 标题」、老服务器什么都不发时一切照旧、不认得的日志不崩。

const Era := preload("res://scripts/ui/era.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fx := preload("res://scripts/ui/fx.gd")
const P := preload("res://scripts/ui/palette.gd")
const LifeScroll := preload("res://scripts/ui/life_scroll.gd")
const WorldView := preload("res://scripts/world/world_view.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


func _era(id: String, title: String, text: String, hits := {}, turn := 20) -> Dictionary:
	return {"kind": "era", "turn": turn, "age": 8, "label": "8 岁 · 立春", "text": title + "。" + text,
		"era": {"id": id, "title": title, "text": text, "hits": hits}}


func _texts(specs: Array) -> Array:
	var out: Array = []
	for s in specs:
		out.append(str(s[0]))
	return out


func _initialize() -> void:
	# ---- 年代名、look ----
	var world := {"era": {"decade": "九十年代", "look": "teen"}}
	var life := {"era": {"decade": "八十年代", "look": "childhood"}, "cohort": {"id": "c85", "name": "八十年代中生", "note": "赶上了分配的尾巴。"}}
	check(Era.decade(Era.era_of(world, life)) == "九十年代", "WORLD 的年代比 life view 的新，先用它")
	check(Era.decade(Era.era_of({}, life)) == "八十年代", "WORLD 没带就看 life view")
	check(Era.era_of({}, {}).is_empty() and Era.decade(null) == "", "老服务器：没有年代")
	check(Era.era_of({"era": null}, {"era": "坏的"}).is_empty(), "半截、坏的字段当没有")
	check(Era.look_for("young", {"look": "childhood"}) == "childhood", "有 look 用 look 代替人生阶段")
	check(Era.look_for("young", {}) == "young", "没 look 照人生阶段")
	check(Era.look_for("young", {"look": "1990s"}) == "young", "不认得的 look 不用")
	check(Era.look_for("", {"look": 3}) == "", "look 不是字也不用")

	# ---- HUD ----
	check(Era.hud_label("8 岁 · 立春", {"decade": "九十年代"}) == "8 岁 · 立春 · 九十年代", "HUD：岁数后面跟年代名")
	check(Era.hud_label("8 岁 · 立春", {}) == "8 岁 · 立春", "HUD：没有年代就原样")
	check(Era.hud_label("", {"decade": "九十年代"}) == "", "HUD：还没有岁数就什么都不写")
	check(Hud.band_text("8 岁 · 立春 · 九十年代", "childhood") == "立春 · 九十年代", "日历牌色条：节气 · 年代")
	check(Hud.band_text("8 岁 · 立春", "childhood", "上学") == "立春 · 上学", "日历牌色条：老样子")
	check(Hud.band_text("20 岁 · 千禧年头上", "young") == "青年 · 千禧年头上", "青年往后只有岁数：人生阶段 · 年代")
	check(Hud.band_text("20 岁", "young") == "青年", "青年往后没有年代：老样子")
	check(Hud.band_text("13 岁 · 上学期 · 九十年代", "teen", "上学") == "上学期 · 九十年代 · 上学", "学期 · 年代 · 上学")

	# ---- 投胎页 ----
	check(Era.cohort_lines(life.cohort) == ["八十年代中生", "赶上了分配的尾巴。"], "投胎页：名字一行、小字一行")
	check(Era.cohort_lines({"id": "c92", "name": "九十年代初生"}) == ["九十年代初生"], "没有 note 只写名字")
	check(Era.cohort_lines(null).is_empty() and Era.cohort_lines({"id": "c92"}).is_empty(), "没有 cohort 不写")

	# ---- 年代卡 ----
	var xiahai := _era("era_xiahai", "下海", "街口的布告栏上，招工的条子一天比一天多。", {"qing": "爸爸辞了厂里的活，出去跑买卖。"})
	var bp := _era("era_bp", "大哥大", "楼下有人拿着砖头一样的电话说话。", {"mei": "妈妈说，家里也该装部电话了。"})
	var odd := {"kind": "era", "turn": 20, "era": {"id": "era_x"}}  # 只有 id：没字可写，不弹
	var entries: Array = [{"kind": "day", "turn": 19, "text": ""}, xiahai, "坏的", bp, odd, {"kind": "新东西", "text": "？"}]
	check(Era.pick(entries).size() == 3, "一批日志里挑出年代大事，别的不管")
	check(Era.pick(null).is_empty(), "没有日志不崩")

	var pages := Era.pages(entries, "qing", "九十年代")
	check(pages.size() == 1 and (pages[0] as Array).size() == 2, "连着两件排在一张卡上，没字的不算")
	var b0: Dictionary = pages[0][0]
	check(str(b0.kicker) == "九十年代" and str(b0.title) == "下海" and str(b0.hit) == "爸爸辞了厂里的活，出去跑买卖。", "一段：年代名、标题、正文、我这一句")
	check(str(pages[0][1].hit) == "", "落在 TA 头上的那一句我看不到")
	check(Color(b0.color) == P.QING, "我这一句是我的颜色")
	var mei_pages := Era.pages(entries, "mei", "")
	check(str(mei_pages[0][0].kicker) == "8 岁 · 立春", "没有年代名就写这条日志的 label")
	check(str(mei_pages[0][1].hit) == "妈妈说，家里也该装部电话了。" and Color(mei_pages[0][1].color) == P.MEI, "梅那一边看梅的那一句")

	var specs := Era.specs(pages[0])
	var texts := _texts(specs)
	check(texts.count("九十年代") == 1, "同一个年代，年代名只写一回：" + str(texts))
	check(texts.has("@rule") and texts.find("@rule") > texts.find("下海") and texts.find("@rule") < texts.find("大哥大"), "两件中间一道细线")
	check(texts.find("九十年代") < texts.find("下海") and texts.find("下海") < texts.find("街口的布告栏上，招工的条子一天比一天多。"), "从上到下：年代名、标题、正文")
	var hit_spec: Array = specs[texts.find("爸爸辞了厂里的活，出去跑买卖。")]
	check(Color(hit_spec[2]).is_equal_approx(P.QING.lightened(0.22)), "我这一句用自己的颜色（墨底上提亮一点）")
	var one := Era.specs([b0])
	var title_fs := 0
	for s in one:
		if str(s[0]) == "下海":
			title_fs = int(s[1])
	var two_fs := int(specs[texts.find("下海")][1])
	check(title_fs > two_fs and two_fs >= 60, "一件大事字最大，两件排一张就收一收（%d / %d）" % [title_fs, two_fs])
	check(Era.specs([]).is_empty(), "空卡没有字")

	var many: Array = []
	for i in 7:
		many.append(_era("era_%d" % i, "第%d件" % i, "一段话。"))
	var mp := Era.pages(many, "qing", "")
	check(mp.size() == 3 and mp[0].size() == Era.PER_CARD and mp[2].size() == 1, "七件分三张卡，一张最多三件")
	var col := Fx.era_column(Era.specs(mp[0]), 1000.0, 2)
	var labels := 0
	var last_text := ""
	for c in col.get_children():
		if c is Label:
			labels += 1
			last_text = c.text
	check(labels == 3 * 2 + 1 + 1, "卡上一栏：三件各两行、头上年代名、底下一行小字（%d）" % labels)
	check(last_text == "点一下，还有 2 张", "后面还有几张，小字说一声")
	check(Fx.era_column(Era.specs([b0]), 1000.0).get_child(-1).text == "点一下接着过", "最后一张：点一下接着过")
	col.free()

	# ---- 长卷 ----
	check(Era.log_line(xiahai) == "年代 · 下海", "日志里写成「年代 · 标题」")
	check(Era.log_line({"kind": "era", "text": "下海"}) == "年代 · 下海", "没有 era 字段用 text")
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	var m: Dictionary = LifeScroll.build({"log": [xiahai, bp, {"kind": "新东西", "turn": 3}, {"turn": 4}], "memories": []}, content)
	check(m.eras.size() == 2 and str(m.eras[0].line) == "年代 · 下海" and int(m.eras[0].turn) == 20, "长卷里记下年代大事")
	check(m.stations.is_empty() and m.counts.days == 0, "不认得的 kind、没有 kind 的条目不算进别的")

	# ---- 街景按 look ----
	var wv: Node2D = WorldView.new()
	wv.set_stage("young")
	check(wv.scene_look() == "young", "没年代：街景照人生阶段")
	wv.set_look(Era.look_for("", {"look": "childhood"}))
	check(wv.scene_look() == "childhood", "有 era.look：街景按年代")
	wv.set_stage("middle")
	check(wv.scene_look() == "childhood", "长大了，年代没变，街景不变")
	wv.set_look(Era.look_for("", {}))
	check(wv.scene_look() == "middle", "年代没了（老服务器），回到人生阶段")
	wv.free()

	if fails == 0:
		print("✓ 年代：卡上排字 / HUD 日历牌 / 投胎页 / 长卷「年代 · 标题」/ 街景按 look / 老服务器照旧")
	quit(1 if fails > 0 else 0)
