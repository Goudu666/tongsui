extends RefCounted
## 「接话」的界面：三种结算（共鸣 / 搭上了 / 错位）、回话、结局多出来的几句。（猜 TA 2026-11 砍了）
## 规则都在服务端（server/src/duet.ts），文案在 content/duet.yaml，这里只管画。设计见 docs/DUET.md。
## 用的都是 kit.gd 的部件；两个圆是 ui/resonance.gd。
##
## main.gd 在这几处调进来：
##   _show_mirror_result   mirror 结算 → show_result
##   _on_log_entries       回话的结算（solo 且带 duet.echo）→ show_echo
##   _on_snapshot          进了世界以后 → on_snapshot（有欠着的话就问）
##   _close_modal          弹窗关了 → check_owed（下一句）
##   _show_ending          → ending_lines

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const Resonance := preload("res://scripts/ui/resonance.gd")

const HEADLINE := {"res": "共鸣", "catch": "搭上了", "miss": "错位"}

var m: Node  ## main.gd
## 「先不说」：这一天不再问，下一个日子再说
var _quiet := false


func _init(main: Node) -> void:
	m = main


func _texts(section: String) -> Dictionary:
	var d: Variant = m.content.get("duet")
	if d is Dictionary and d.get(section) is Dictionary:
		return d[section]
	return {}


func _fill(tpl: String, vars: Dictionary) -> String:
	var out := tpl
	for k in vars:
		out = out.replace("{%s}" % k, str(vars[k]))
	return out


func _name(role: String) -> String:
	return str(m.names.get(role, P.ROLE_NAME.get(role, "TA")))


## 一行：名字的色签 + 他选的那一项
func _pick_row(box: Container, role: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	Kit.chip(row, _name(role), P.role_color(role), 30)
	var pick: Label = m._label(row, text, 38, P.INK)
	pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## 卡片最上面一行：结果的色签 + 哪一天、哪件事
func _head(box: Container, outcome: String, when: String) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	box.add_child(head)
	Kit.chip(head, HEADLINE[outcome], P.INK_SOFT if outcome == "miss" else P.OVERLAP)
	var l: Label = m._label(head, when, 30, P.INK_SOFT)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER


# ----------------------------------------------------------------------
# 结算：共鸣 / 搭上了 / 错位
# ----------------------------------------------------------------------

static func outcome_of(e: Dictionary) -> String:
	var d: Variant = e.get("duet")
	if d is Dictionary and HEADLINE.has(str(d.get("outcome", ""))):
		return str(d.outcome)
	return "res" if e.get("resonance") == true else "miss"


func show_result(e: Dictionary) -> void:
	var d: Dictionary = e.duet if e.get("duet") is Dictionary else {}
	var outcome := outcome_of(e)
	var ev: Dictionary = m.events_by_id.get(e.events.qing, {})
	# 横屏：两个圆在左，谁选了什么、那句话在右
	m._open_modal(m.MODAL_WIDE - 160.0)
	var cols: Array = m._columns(m.modal_body, 0.62, 1.0, 56)
	var emblem: VBoxContainer = cols[0]
	emblem.alignment = BoxContainer.ALIGNMENT_CENTER
	emblem.add_child(Resonance.new(outcome, d.get("knew")))
	var box: VBoxContainer = cols[1]
	box.add_theme_constant_override("separation", 20)
	_head(box, outcome, "%s · %s" % [str(e.label), str(ev.get("title", ""))])
	var checks: Dictionary = e.checks if e.get("checks") is Dictionary else {}
	for r in ["qing", "mei"]:
		var mark := "（影子）" if e.shadow.has(r) else ""
		_pick_row(box, r, m._option_text(e.events[r], e.choices[r]) + mark)
		# 这一项挂着检定（成长线的）：成没成，写在选择下面
		if checks.get(r) is Dictionary:
			m._label(box, "%s　%s" % [m._check_verdict(checks[r]), str(checks[r].get("text", ""))], 30, P.INK_SOFT)
	Kit.rule(box, Color(P.INK, 0.25))
	m._label(box, str(e.text), 44, P.INK if outcome == "miss" else P.OVERLAP)
	var notes := []
	if d.get("line") is String:
		notes.append(str(d.line))
	var owed: Variant = d.get("owed")
	if owed is String and owed != m.my_role and _texts("echo").has("kept"):
		notes.append(_fill(str(_texts("echo").kept), {"b": _name(owed)}))
	if not notes.is_empty():
		m._label(box, "\n".join(notes), 32, P.INK_SOFT)
	m._primary(box, "嗯", m._close_modal)
	m._gap(box, 4)


# ----------------------------------------------------------------------
# 回话：影子替我选过的，我回来补答
# ----------------------------------------------------------------------

func on_snapshot() -> void:
	_quiet = false
	check_owed()


## 还欠着、还接得上的话（最早的在前）
func owed_list() -> Array:
	var d: Variant = m.life.get("duet")
	if not d is Dictionary or not d.get("owed") is Dictionary:
		return []
	var keep := int(d.get("keep", 8))
	var out := []
	for o in d.owed.get(m.my_role, []):
		if int(m.life.get("turn", 0)) - int(o.turn) < keep and m.events_by_id.has(o.eventId):
			out.append(o)
	return out


## 没有别的弹窗挡着时，把欠着的下一句拿出来问
func check_owed() -> void:
	if _quiet or m.world == null or m.modal.visible or str(m.life.get("phase", "")) != "life":
		return
	var list := owed_list()
	if not list.is_empty():
		_show_owed(list[0])


func _show_owed(o: Dictionary) -> void:
	var ev: Dictionary = m.events_by_id.get(o.eventId, {})
	var turn := int(o.turn)
	var box: VBoxContainer = m.modal_body
	var opts: Array = ev.get("options", [])
	m._open_modal(m._options_width(opts.size()))
	Kit.chip(box, "你不在的那天 · %s" % str(o.label), P.role_color(m.my_role))
	m._label(box, str(ev.get("title", "")), 64)
	Kit.rule(box)
	m._label(box, str(ev.get("text", "")), 38)
	m._label(box, str(_texts("echo").get("ask", "换了你，你会？")), 34, P.INK_SOFT)
	var grid: Container = m._options(box, opts.size())
	for opt in opts:
		m._option(grid, str(opt.text), _answer.bind(turn, str(opt.id), str(opt.text)))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	m._quiet(row, "先不说", _later)
	m._quiet(row, "不提了", _drop.bind(turn))


func _forget(turn: int) -> void:
	var d: Variant = m.life.get("duet")
	if d is Dictionary and d.get("owed") is Dictionary:
		d.owed[m.my_role] = d.owed.get(m.my_role, []).filter(func(o): return int(o.turn) != turn)


func _answer(turn: int, option_id: String, option_text: String) -> void:
	m.net.echo(turn, option_id)
	_forget(turn)
	var box: VBoxContainer = m.modal_body
	m._clear(box)
	m.modal_card.custom_minimum_size.x = m.MODAL_WIDTH
	m._label(box, "你说", 32, P.INK_SOFT)
	m._label(box, option_text, 48, P.role_color(m.my_role))
	Kit.rule(box, Color(P.INK, 0.25))
	m._label(box, "话递过去了……", 36, P.INK_SOFT)


func _later() -> void:
	_quiet = true
	m._close_modal()


func _drop(turn: int) -> void:
	m.net.echo(turn)
	_forget(turn)
	m._close_modal()


## 回话的结算。回话的人看到整张卡；对门那边，补上了就弹卡，没补上只提一句
func show_echo(e: Dictionary) -> void:
	var d: Dictionary = e.duet
	var role := str(d.role)
	var mine: bool = role == m.my_role
	var outcome := outcome_of(e)
	var ev: Dictionary = m.events_by_id.get(e.events[role], {})
	var mended: bool = outcome != "miss" and str(d.get("was", "")) == "miss"
	if not mine and (m.modal.visible or not mended):
		var told := _fill(str(_texts("echo").get("told", "{b}回了「{o}」那天的话。")), {"b": _name(role), "o": ev.get("title", "")})
		m._toast(told + (HEADLINE[outcome] + "。" if mended else ""))
		return
	var other := "mei" if role == "qing" else "qing"
	m._open_modal(m.MODAL_WIDE - 160.0)
	var cols: Array = m._columns(m.modal_body, 0.62, 1.0, 56)
	var emblem: VBoxContainer = cols[0]
	emblem.alignment = BoxContainer.ALIGNMENT_CENTER
	emblem.add_child(Resonance.new(outcome, null, 0.78))
	var box: VBoxContainer = cols[1]
	box.add_theme_constant_override("separation", 20)
	_head(box, outcome, "回话 · %s · %s" % [str(d.get("label", "")), str(ev.get("title", ""))])
	_pick_row(box, role, m._option_text(ev.get("id"), e.choices[role]))
	_pick_row(box, other, m._option_text(ev.get("id"), d.get("partner")))
	Kit.rule(box, Color(P.INK, 0.25))
	m._label(box, str(e.text), 44, P.INK if outcome == "miss" else P.OVERLAP)
	var lines: Array = d.get("lines", [])
	if not lines.is_empty():
		m._label(box, "\n".join(lines.map(func(l): return str(l))), 32, P.INK_SOFT)
	m._primary(box, "嗯", m._close_modal)
	m._gap(box, 4)


# ----------------------------------------------------------------------
# 一生结束时多出来的几句
# ----------------------------------------------------------------------

func ending_lines() -> Array:
	var d: Variant = m.life.get("duet")
	if d is Dictionary and d.get("epitaph") is Array:
		return d.epitaph
	return []
