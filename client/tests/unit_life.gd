extends SceneTree
## 「人物活起来」的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_life.gd
## 查的是对不上号的地方：每个行动都有动作（专属一套、坐着、招手，或者通用的"在忙"里登记过）、
## 动作表的顺序和 tools/art/actor_acts.py 一致、上学上班的点位真有、每位街坊都画了长相、图集行数够、
## 演完一回的反应和搭伴面对面不出错。好不好看靠 tools/shots/life.gd 出图录屏。

const Actor := preload("res://scripts/world/actor.gd")
const Folks := preload("res://scripts/world/folks.gd")

## 没有专属动作、用通用"在忙"姿势也说得过去的行动（新加的行动要么配一套，要么登记在这儿）
const GENERIC_OK := ["sleep", "duty"]

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


func _json(path: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _initialize() -> void:
	var content := _json("res://data/content.json")
	var map: Dictionary = content.get("map", {})
	# 1. 每个行动都演得出来
	for a in map.get("actions", []):
		var id := str(a.id)
		var ok: bool = Actor.ACTION_LOOP.has(id) or id in Actor.SIT_ACTIONS or id in Actor.WAVE_ACTIONS or id in GENERIC_OK
		check(ok, "行动 %s 没有动作：在 actor.gd 的 ACTION_LOOP 里配一套" % id)
	for id in Actor.ACTION_LOOP:
		check(str(Actor.ACTION_LOOP[id]) in Actor.ACT_LOOP, "ACTION_LOOP[%s] = %s 不在 ACT_LOOP 里" % [id, Actor.ACTION_LOOP[id]])
	for sp in Actor.DUTY_LOOP:
		check(map.get("spots", []).any(func(s): return str(s.id) == sp), "DUTY_LOOP 的点位 %s 在地图上没有" % sp)
		check(str(Actor.DUTY_LOOP[sp]) in Actor.ACT_LOOP, "DUTY_LOOP[%s] 不在 ACT_LOOP 里" % sp)
	for lp in Actor.FACE_LOOPS:
		check(lp in Actor.ACT_LOOP, "FACE_LOOPS 里的 %s 不在 ACT_LOOP 里" % lp)
	# 2. 动作表的顺序和画图那边一致（tools/art/actor_acts.py 的 ACTS）
	var py_path := ProjectSettings.globalize_path("res://").path_join("../tools/art/actor_acts.py")
	if FileAccess.file_exists(py_path):
		var src := FileAccess.get_file_as_string(py_path)
		var body := src.substr(src.find("ACTS = ["))
		body = body.substr(0, body.find("]\n"))
		var re := RegEx.create_from_string("\\(\"(\\w+)\", act_")
		var names: Array = []
		for m in re.search_all(body):
			names.append(m.get_string(1))
		check(names == Actor.ACT_LOOP, "actor_acts.py 的 ACTS 顺序 %s 和 actor.gd 的 ACT_LOOP 不一样" % str(names))
	check(Actor.ACT_LOOP.size() <= Actor.ACT_ROWS * 2, "ACT_LOOP 比动作表装得下的多")
	# 3. 每个年纪的两张表都在，尺寸对
	for role in ["qing", "mei"]:
		for st in Actor.STAGE_FILE.values():
			var base: Texture2D = load("res://art/actors/%s_%s.png" % [role, st])
			var act: Texture2D = load("res://art/actors/%s_%s_act.png" % [role, st])
			check(base != null and base.get_height() == int(Actor.CELL.y * Actor.ART_SCALE) * Actor.ROWS, "%s_%s.png 行数不对" % [role, st])
			check(act != null and act.get_height() == int(Actor.CELL.y * Actor.ACT_ART_SCALE) * Actor.ACT_ROWS, "%s_%s_act.png 行数不对" % [role, st])
			check(act != null and act.get_width() <= 4096 and act.get_height() <= 4096, "%s_%s_act.png 超过手机贴图上限 4096" % [role, st])
	# 4. 街坊：每位都画了，图集行数够
	var folks := _json("res://data/folks.json")
	var index := _json("res://art/folks/index.json")
	for sid in folks:
		var tex: Texture2D = load("res://art/folks/%s.png" % sid)
		check(tex != null, "街坊图集 %s.png 没有" % sid)
		var rows := 0 if tex == null else tex.get_height() / int(float(index.cell[1]) * float(index.scale))
		for n in folks[sid]:
			var info: Variant = index.get("folks", {}).get(str(n.id))
			check(info != null, "街坊 %s 没画长相：在 tools/art/folks.py 的 FOLKS 里加，再跑一遍" % n.id)
			if info != null:
				check(str(info.scene) == sid and int(info.row) < rows, "街坊 %s 的图集行不对（重跑 tools/art/folks.py）" % n.id)
	check(load("res://art/folks/walkers.png") != null, "路人图集 walkers.png 没有")
	# 5. 演一下：做事换表、演完反应、情绪动作不卡在半截
	var a: Node2D = Actor.new()
	root.add_child(a)
	a.setup("qing", "小满", true, Vector2(100, 760))
	a.set_stage("teen")
	a.doing = "study"
	a.action_label = "写作业"
	a._process(0.1)
	check(a.loop_name() == "write" and a._on_act, "写作业应该换到专属动作表的 write")
	a.doing = "duty"
	a.at_spot = "office_desk"
	check(a.loop_name() == "type", "坐办公桌上班应该敲电脑")
	a.doing = ""
	a.action_label = ""
	a._process(0.1)
	check(not a._on_act, "不做事了应该换回基础表")
	a.react({"nd": {"mood": 8}, "s": {}})
	check(a._emote == "joy" and not a._bubbles.is_empty(), "心情涨了应该高兴一下、冒个泡")
	for i in 30:
		a._process(0.1)
	check(a._emote == "", "情绪动作演完要停")
	a.react({"nd": {"mood": -6}})
	check(a._emote == "sad", "心情掉了应该泄气")
	a.react({"tg": true})
	check(a._bubbles.any(func(b): return str(b.kind) == "pair"), "搭伴做完一回冒两个圆")
	a.quiet_label = true
	var n0: int = a._bubbles.size()
	a.bubble("pair")
	check(a._bubbles.size() == n0, "挨着的两个人只让一个冒两个圆")
	a.queue_free()
	if fails == 0:
		print("✓ unit_life：%d 个行动都有动作，%d 位街坊都画了" % [map.get("actions", []).size(), index.get("folks", {}).size()])
	quit(1 if fails > 0 else 0)
