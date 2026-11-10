extends RefCounted
## 「接话」的界面：猜 TA、三种结算（共鸣 / 搭上了 / 错位）、回话、结局多出来的几句。
## 规则都在服务端（server/src/duet.ts），文案在 content/duet.yaml，这里只管画。设计见 docs/DUET.md。
##
## main.gd 在这几处调进来：
##   _pick            默契事件里选完自己的 → ask_guess
##   _on_log_entries  mirror 结算 → show_result；回话的结算（solo 且带 duet.echo）→ show_echo
##   _on_snapshot     进了世界以后 → on_snapshot（有欠着的话就问）
##   _close_modal     弹窗关了 → check_owed（下一句）
##   _show_ending     → ending_lines

const P := preload("res://scripts/ui/palette.gd")
const Seal := preload("res://scripts/duet/seal.gd")

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


# ----------------------------------------------------------------------
# 猜 TA
# ----------------------------------------------------------------------

## 选完自己的，再猜对门选了哪个。猜不猜都行；猜了才和自己的选择一起发出去
func ask_guess(event_id: String, option_id: String, option_text: String) -> void:
	var ev: Dictionary = m.events_by_id.get(event_id, {})
	var box: VBoxContainer = m.modal_body
	m._clear(box)
	m._label(box, "你选了", 32, P.INK_SOFT)
	m._label(box, option_text, 48, P.role_color(m.my_role))
	m._gap(box, 12)
	var other: String = m._other()
	m._label(box, "猜猜 %s 选了哪个？" % m._role_text(other), 40, P.role_color(other))
	for o in ev.get("options", []):
		m._button(box, str(o.text), m._pick_send.bind(option_id, option_text, str(o.id)))
	_quiet_button(box, "不猜", m._pick_send.bind(option_id, option_text, ""))


## 不抢戏的按钮：没有边框，字是淡的
func _quiet_button(box: Container, text: String, on_press: Callable) -> Button:
	var b: Button = m._button(box, text, on_press)
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 34)
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(c, P.INK_SOFT)
	return b


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
	var box: VBoxContainer = m.modal_body
	m._open_modal()
	m._label(box, str(e.label), 30, P.INK_SOFT)
	m._label(box, str(ev.get("title", "")), 64)
	box.add_child(Seal.new(outcome, d.get("knew")))
	for r in ["qing", "mei"]:
		var mark := "（影子）" if e.shadow.has(r) else ""
		m._label(box, "%s %s%s" % [m._role_text(r), m._option_text(e.events[r], e.choices[r]), mark], 38, P.role_color(r))
	m._label(box, "%s · %s" % [HEADLINE[outcome], str(e.text)], 44, P.INK_SOFT if outcome == "miss" else P.OVERLAP)
	if d.get("line") is String:
		m._label(box, str(d.line), 34, P.INK_SOFT)
	var owed: Variant = d.get("owed")
	if owed is String and owed != m.my_role and _texts("echo").has("kept"):
		m._label(box, _fill(str(_texts("echo").kept), {"b": m.names.get(owed, "TA")}), 32, P.role_color(owed))
	m._button(box, "嗯", m._close_modal)


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
	m._open_modal()
	m._label(box, "你不在的那天 · %s" % str(o.label), 30, P.role_color(m.my_role))
	m._label(box, str(ev.get("title", "")), 64)
	m._label(box, str(ev.get("text", "")), 38)
	m._label(box, str(_texts("echo").get("ask", "换了你，你会？")), 36, P.INK_SOFT)
	for opt in ev.get("options", []):
		m._button(box, str(opt.text), _answer.bind(turn, str(opt.id), str(opt.text)))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	_quiet_button(row, "先不说", _later)
	_quiet_button(row, "不提了", _drop.bind(turn))


func _forget(turn: int) -> void:
	var d: Variant = m.life.get("duet")
	if d is Dictionary and d.get("owed") is Dictionary:
		d.owed[m.my_role] = d.owed.get(m.my_role, []).filter(func(o): return int(o.turn) != turn)


func _answer(turn: int, option_id: String, option_text: String) -> void:
	m.net.echo(turn, option_id)
	_forget(turn)
	var box: VBoxContainer = m.modal_body
	m._clear(box)
	m._label(box, "你说", 32, P.INK_SOFT)
	m._label(box, option_text, 48, P.role_color(m.my_role))
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
		var told := _fill(str(_texts("echo").get("told", "{b}回了「{o}」那天的话。")), {"b": m.names.get(role, "TA"), "o": ev.get("title", "")})
		m._toast(told + (HEADLINE[outcome] + "。" if mended else ""))
		return
	var other := "mei" if role == "qing" else "qing"
	var box: VBoxContainer = m.modal_body
	m._open_modal()
	m._label(box, "回话 · %s" % str(d.get("label", "")), 30, P.role_color(role))
	m._label(box, str(ev.get("title", "")), 64)
	box.add_child(Seal.new(outcome, null, 0.72))
	m._label(box, "%s %s" % [m._role_text(role), m._option_text(ev.get("id"), e.choices[role])], 38, P.role_color(role))
	m._label(box, "%s %s" % [m._role_text(other), m._option_text(ev.get("id"), d.get("partner"))], 38, P.role_color(other))
	m._label(box, "%s · %s" % [HEADLINE[outcome], str(e.text)], 44, P.INK_SOFT if outcome == "miss" else P.OVERLAP)
	var lines: Array = d.get("lines", [])
	if not lines.is_empty():
		m._label(box, "\n".join(lines.map(func(l): return str(l))), 32, P.INK_SOFT)
	m._button(box, "嗯", m._close_modal)


# ----------------------------------------------------------------------
# 一生结束时多出来的几句
# ----------------------------------------------------------------------

func ending_lines() -> Array:
	var d: Variant = m.life.get("duet")
	if d is Dictionary and d.get("epitaph") is Array:
		return d.epitaph
	return []
