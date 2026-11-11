extends SceneTree
## 孩子那张小牌和「孩子 心智 +3」的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_kid.gd
## 查的是：没孩子不占地方；有孩子时小牌在「我」的牌底下、不压三张牌和纸带；数是百分制往下取整；
## did 带 k 才飘、飘的是孩子、飞向孩子那张牌、落下之前牌上的数不拨。
## 画得好不好看靠 tools/shots/family.gd 出图。

const Hud := preload("res://scripts/ui/hud.gd")
const Juice := preload("res://scripts/ui/juice.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


class FakeMain extends Node:
	var my_role := "qing"
	var modal: Control = null
	var fx = null
	var world = null
	var hud = null
	var ui: Control = null
	var life: Dictionary = {"turn": 0}
	var stat_strip = null
	var events_by_id := {}


func _kid(mind: float) -> Dictionary:
	return {"name": "石头", "age": 7, "stats": {"body": 3.48, "mind": mind, "charm": 2.9}, "shared": true}


func _world(kid: Dictionary, did: Dictionary = {}) -> Dictionary:
	var me := {"act": null}
	if not kid.is_empty():
		me["kid"] = kid
	if not did.is_empty():
		me["did"] = did
	return {"stats": {"qing": {"body": 5.0, "mind": 5.0, "charm": 5.0}, "mei": {"body": 5.0, "mind": 5.0, "charm": 5.0}},
		"money": {"qing": 20, "mei": 20}, "bond": {"close": 40, "sync": 20}, "actors": {"qing": me, "mei": {"act": null}}}


func _tags(j: Node) -> Array:
	var out: Array = []
	for c in j.get_children():
		if c is Juice.Tag:
			out.append(c)
	return out


func _initialize() -> void:
	# 版面：各种屏宽、有无刘海
	for size in [Vector2(1920, 1080), Vector2(2400, 1080), Vector2(1920, 1440)]:
		for notch in [0.0, 110.0]:
			var hud := Hud.new()
			hud.size = size
			hud.inset = Vector2(notch, notch)
			hud.needs = {"hunger": 50}
			hud.partner = {"name": "TA"}
			check(hud.kid_rect() == Rect2(), "没孩子不占地方")
			hud.kid = _kid(4.0)
			var k := hud.kid_rect()
			var tag := "%s 刘海 %d" % [size, int(notch)]
			check(k.position.y >= hud.me_rect().end.y + 8.0, "%s：孩子的小牌压住了我的牌" % tag)
			check(is_equal_approx(k.position.x, hud.me_rect().position.x) and k.size.x <= Hud.ME_W, "%s：孩子的小牌要和我的牌左边对齐、不比它宽" % tag)
			check(not k.intersects(hud.strip_rect()) and not k.intersects(hud.them_rect()), "%s：孩子的小牌压住了纸带或对门的牌" % tag)
			check(k.position.x >= notch, "%s：孩子的小牌要让开刘海" % tag)
			hud.free()
	check(Hud.kid_points({"body": 3.48, "mind": 5.79, "charm": 6.0}) == [["体魄", 34], ["心智", 57], ["魅力", 60]], "孩子的三项百分制往下取整")
	check(Hud.kid_age_text(0) == "不到一岁" and Hud.kid_age_text(7) == "7 岁", "几岁的写法")

	# k 折成飘字：用前后两帧的差；对不上就用 k；没涨的、不到 1 分的不飘
	var was := Juice.kid_points({"body": 3.0, "mind": 4.0, "charm": 3.0})
	var now := Juice.kid_points({"body": 3.0, "mind": 4.35, "charm": 3.0})
	check(Juice.kid_items({"mind": 0.35}, was, now) == [["孩子 心智", 3, "kid_mind"]], "孩子 心智 +3（实际 %s）" % [Juice.kid_items({"mind": 0.35}, was, now)])
	check(Juice.kid_items({"mind": 0.42}, {}, now) == [["孩子 心智", 4, "kid_mind"]], "前一帧没有孩子的数就用 k")
	check(Juice.kid_items({"body": 0.04}, was, now).is_empty(), "不到 1 分不飘")
	check(Juice.kid_items({}, was, now).is_empty(), "没有 k 不飘孩子")

	# 接起来：WORLD 里 did 带 k，飘一张「孩子 心智」，飞向孩子那张牌；落下之前牌上的数不拨
	var m := FakeMain.new()
	m.ui = Control.new()
	m.ui.size = Vector2(1920, 1080)
	m.modal = Control.new()
	m.modal.visible = false
	var hud := Hud.new()
	hud.size = Vector2(1920, 1080)
	hud.needs = {"hunger": 50}
	m.hud = hud
	root.add_child(m)
	m.add_child(hud)
	var j := Juice.new()
	j.main = m
	root.add_child(j)
	j.on_world(_world(_kid(4.0)))
	hud.kid = _kid(4.0)
	check(_tags(j).is_empty(), "头一帧不飘")
	j.on_world(_world(_kid(4.3)))
	check(_tags(j).is_empty(), "孩子自己长（没有 did.k）不飘")
	hud.kid = _kid(4.3)
	j.on_world(_world(_kid(4.6), {"n": 3, "a": "kid_homework", "l": "陪孩子写作业", "k": {"mind": 0.3}}))
	var tags := _tags(j)
	check(tags.size() == 1 and tags[0].text_small == "孩子 心智" and tags[0].text_big == "+3", "带孩子的事飘一张「孩子 心智 +3」（实际 %d 张）" % tags.size())
	check(j._target("kid_mind") == hud.kid_rect().get_center() + hud.global_position, "「孩子 心智」飞向孩子那张牌")
	hud.kid = _kid(4.6)
	check(not hud._kid_held.is_empty() and is_equal_approx(float(hud._kid_held.mind), 4.3), "飘字落下之前孩子牌上还是旧数")
	hud.kid_land("mind")
	check(hud._kid_held.is_empty(), "落下来就拨上去")
	j.on_world(_world(_kid(4.6), {"n": 3, "a": "kid_homework", "l": "陪孩子写作业", "k": {"mind": 0.3}}))
	check(_tags(j).size() == 1, "同一个 did 不重复飘")

	if fails == 0:
		print("✓ unit_kid：孩子的小牌不压三张牌、百分制、带孩子的事飘向孩子那张牌")
	quit(1 if fails > 0 else 0)
