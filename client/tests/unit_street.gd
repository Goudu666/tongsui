extends SceneTree
## 街景的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_street.gd
## 查的是数据和引擎对得上：每个年代街上都有人、公告栏一次只有一块、茶社台上有人上台时原来的人让开。

const StreetLife := preload("res://scripts/world/street_life.gd")
const STAGES := ["childhood", "teen", "young", "middle", "old"]

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


func _on(life: Node, id: String) -> bool:
	for th in life._things:
		if str(th.def.id) == id:
			return th.on
	return false


func _count(life: Node, prefix: String) -> int:
	var n := 0
	for th in life._things:
		if th.on and str(th.def.id).begins_with(prefix):
			n += 1
	return n


func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/street.json"))
	var sprites: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/street/sprites.json")).sprites
	for part in ["npcs", "props", "traffic"]:
		for d in data[part]:
			check(sprites.has(d.sprite), "%s 的精灵 %s 在图集里" % [d.id, d.sprite])
	for st in STAGES:
		check(str(data.eras.get(st, {}).get("name", "")) != "", "%s 有年代名" % st)

	var view := Node2D.new()
	root.add_child(view)
	var life := StreetLife.new()
	view.add_child(life)
	life.setup(view)
	check(life.ready_ok, "街景加载成功")
	check(life._things.size() == data.npcs.size() + data.props.size(), "街坊和道具都摆上了")

	for st in STAGES:
		life.set_stage(st)
		life.set_minute(900.0)  # 下午三点
		check(life.era_name() == str(data.eras[st].name), "%s 的年代名" % st)
		check(_count(life, "notice_") == 1, "%s：公告栏只有一块" % st)
		check(_count(life, "far_") == 1, "%s：对岸只有一种天际线" % st)
		check(_on(life, "bike_ye") != _on(life, "bike_tu"), "%s：修车铺只有一个人看摊" % st)
		check(_on(life, "gu_ye") != _on(life, "gu_xiao"), "%s：茶社台上只有一位" % st)
		check(_on(life, "fisher"), "%s：钓鱼的大爷一直都在" % st)
		var traffic := 0
		for tr in life._traffic:
			if st in tr.def.get("eras", STAGES):
				traffic += 1
		check(traffic >= 1, "%s：街上有车过" % st)

	# 钟点：深夜街上没有人；早上早点铺有人
	life.set_stage("childhood")
	life.set_minute(1380.0)
	check(not _on(life, "gu_ye") and not _on(life, "fisher"), "夜里十一点，都回家了")
	life.set_minute(420.0)
	check(_on(life, "zhou_shen"), "早上七点，周婶出摊了")
	# 主角上台，台上的人让开
	life.set_minute(900.0)
	check(_on(life, "gu_ye"), "下午顾爷爷在台上")
	life.set_busy(["perform"])
	check(not _on(life, "gu_ye"), "主角上台时顾爷爷让开")
	life.set_busy([])
	check(_on(life, "gu_ye"), "主角下来，顾爷爷回到台上")

	if fails == 0:
		print("✓ 街景：%d 个街坊和道具、%d 种车 / 五个年代各自对得上 / 钟点 / 上台让位" % [life._things.size(), life._traffic.size()])
	quit(1 if fails > 0 else 0)
