extends RefCounted
## 关口选路卡上「拉一把」的几句话（规则在 server/src/pull.ts，这里只把服务器给的 pulls 换成字）。
## pulls[role][optionId] = { by, gap, unit, reach }：role 走这条差 gap，by 拉得动，这一回最多拉 reach。


## 差几分的那个看到的：这条路不灰了，写着要谁一起走
static func mine(p: Dictionary, their_name: String) -> String:
	return "差 %d %s · 和%s一起走这条，TA 拉你过去" % [int(p.get("gap", 0)), _unit(p), their_name]


## 拉得动的那个看到的：自己走得了的这条路下面，写着对门差多少
static func theirs(p: Dictionary, their_name: String) -> String:
	if str(p.get("unit", "分")) == "块":
		return "%s差 %d 块 · 你也走这条，替 TA 垫上" % [their_name, int(p.get("gap", 0))]
	return "%s差 %d 分 · 你也走这条，就能拉 TA 过去" % [their_name, int(p.get("gap", 0))]


## 卡片正文下面那一行：这一关谁能拉谁、为什么拉得动（默契管分，亲近管钱）
static func headline(my: Dictionary, theirs_: Dictionary, their_name: String) -> String:
	var p: Dictionary = _first(my) if not my.is_empty() else _first(theirs_)
	var money := str(p.get("unit", "分")) == "块"
	var why := "亲近够，最多垫得了 %d 块" % int(p.get("reach", 0)) if money else "默契够，最多拉得动 %d 分" % int(p.get("reach", 0))
	if not my.is_empty():
		return "%s多出来的够匀给你。%s。两个人要走同一条。" % [their_name, why]
	return "%s差一点，你多出来的够匀给 TA。%s。" % [their_name, why]


static func _first(d: Dictionary) -> Dictionary:
	for k in d:
		if d[k] is Dictionary:
			return d[k]
	return {}


static func _unit(p: Dictionary) -> String:
	return str(p.get("unit", "分"))
