extends RefCounted
## 一封信：分在外地和河畔里的两个人写的（规则在 server/src/post.ts，文字在 content/letters.yaml）。
## 「这一天过去了」那条日志带着 post（到了的信）：收信的人在撕下来的那页日历底下看到它。
##
## 样子：一张信纸，写信人颜色的横格线，一行字一格；右上角一个邮戳（外地 / 河畔里 + 写信那天）；末尾落款。

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")


## 这条日志里寄给我的信（老服务器没有 post 字段就是空的）
static func mine(entry: Dictionary, my_role: String) -> Array:
	var out := []
	var post: Variant = entry.get("post")
	if not post is Array:
		return out
	for l in post:
		if l is Dictionary and str(l.get("to", "")) == my_role and l.get("lines") is Array:
			out.append(l)
	return out


## 收信人看到的那几行：信的正文 + 落款
static func text_of(letter: Dictionary, names: Dictionary) -> Array:
	var out: Array = []
	for t in letter.get("lines", []):
		out.append(str(t))
	out.append("—— " + str(names.get(str(letter.get("from", "")), P.ROLE_NAME.get(str(letter.get("from", "")), "TA"))))
	return out


static func build(parent: Container, letter: Dictionary, names: Dictionary) -> Control:
	var from := str(letter.get("from", "qing"))
	var color := P.role_color(from)
	var card := Kit.card(Color(color, 0.18), 40.0, false, 8.0)
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	box.add_child(head)
	var who := str(names.get(from, P.ROLE_NAME.get(from, "TA")))
	Kit.chip(head, "%s的信" % who, color, 28)
	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(filler)
	var mark := _Postmark.new()
	mark.color = color
	mark.place = "外地" if str(letter.get("side", "")) == "away" else "河畔里"
	mark.day = str(letter.get("label", ""))
	mark.custom_minimum_size = Vector2(124, 124)
	head.add_child(mark)
	var lines := text_of(letter, names)
	for i in lines.size():
		var last := i == lines.size() - 1
		var row := _Ruled.new()
		row.color = Color(color, 0.45)
		row.add_theme_constant_override("margin_top", 18)
		row.add_theme_constant_override("margin_bottom", 10)
		box.add_child(row)
		var l := Kit.label(row, str(lines[i]), 38, P.INK, HORIZONTAL_ALIGNMENT_RIGHT if last else HORIZONTAL_ALIGNMENT_LEFT)
		if last:
			l.add_theme_color_override("font_color", color)
	return card


## 一格信纸：字底下一条横线；字长了折成两行，格子跟着高
class _Ruled extends MarginContainer:
	var color := Color.BLACK

	func _draw() -> void:
		draw_line(Vector2(0, size.y - 3), Vector2(size.x, size.y - 3), color, 2.0)


## 邮戳：两道圈，上面地名，下面日子，斜着盖
class _Postmark extends Control:
	var color := Color.BLACK
	var place := ""
	var day := ""

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 6.0
		draw_set_transform(c, -0.18, Vector2.ONE)
		draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(color, 0.8), 3.0, true)
		draw_arc(Vector2.ZERO, r - 9.0, 0, TAU, 48, Color(color, 0.5), 1.5, true)
		var f := get_theme_font("font", "Label")
		var fs := 22
		var w := f.get_string_size(place, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(-w / 2.0, -4), place, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color, 0.85))
		var d := day.split(" · ")[0]
		var w2 := f.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(f, Vector2(-w2 / 2.0, 24), d, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(color, 0.7))
		draw_line(Vector2(-r + 12, 6), Vector2(r - 12, 6), Color(color, 0.5), 1.5)
