extends RefCounted
## 年代大事层的客户端（服务器 server/src/era.ts，接口见 eras/SPEC.md）。都是纯函数，单测 tests/unit_era.gd 查。
##   - life view / WORLD 可能带 era: { decade: "九十年代", look: "childhood" }；life view 还带 cohort: { id, name, note }
##   - 长卷 log 里的 kind "era"：{ kind, turn, age, label, text, era: { id, title, text, hits: { qing?, mei? } } }
## 都是可选的：老服务器不发，这里一律返回空，界面照老样子。

const P := preload("res://scripts/ui/palette.gd")

## look 的取值就是现有美术的五个阶段键（scene_art / street_life / soundscape 都认它）
const LOOKS := ["childhood", "teen", "young", "middle", "old"]
const PER_CARD := 3  ## 一张年代卡上最多排几件大事，再多就下一张


static func _d(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## 现在是什么年代：WORLD 的 era 新一点，先看它；没有就看 life view 的
static func era_of(world: Variant, life: Variant = null) -> Dictionary:
	var e := _d(_d(world).get("era"))
	if e.is_empty():
		e = _d(_d(life).get("era"))
	return e


static func decade(era: Variant) -> String:
	var v: Variant = _d(era).get("decade")
	return str(v) if v is String else ""


## 街景 / 远景 / 声景用哪一套：有 era.look（而且是认得的键）就用它，不然照人生阶段
static func look_for(stage: String, era: Variant) -> String:
	var look: Variant = _d(era).get("look")
	if look is String and look in LOOKS:
		return look
	return stage


## HUD 日历牌上的那一行：「8 岁 · 立春」→「8 岁 · 立春 · 九十年代」；没有年代就原样
static func hud_label(label: String, era: Variant) -> String:
	var dn := decade(era)
	if dn == "" or label == "":
		return label
	return "%s · %s" % [label, dn]


## 投胎页上两行：出生年代的名字、一句小字。没有 cohort 就是空的
static func cohort_lines(cohort: Variant) -> Array:
	var c := _d(cohort)
	var name: Variant = c.get("name")
	if not name is String or name == "":
		return []
	var out: Array = [str(name)]
	var note: Variant = c.get("note")
	if note is String and note != "":
		out.append(str(note))
	return out


## 一批日志里挑出年代大事
static func pick(entries: Variant) -> Array:
	var out: Array = []
	if not entries is Array:
		return out
	for e in entries:
		if e is Dictionary and str(e.get("kind", "")) == "era":
			out.append(e)
	return out


## 年代大事 → 年代卡上一段要写的东西：{ kicker 年代名, title, text, hit 我这一句, color 我的颜色 }
## decade_now：现在的年代名（WORLD 的 era.decade）；没有就用这条日志的 label
static func block(e: Dictionary, me: String, decade_now := "") -> Dictionary:
	var ev := _d(e.get("era"))
	var title := str(ev.get("title", "")) if ev.get("title") is String else ""
	var text := str(ev.get("text", "")) if ev.get("text") is String else ""
	if title == "" and text == "":
		text = str(e.get("text", "")) if e.get("text") is String else ""
	var hit: Variant = _d(ev.get("hits")).get(me)
	var kicker := decade_now if decade_now != "" else (str(e.label) if e.get("label") is String else "")
	return {"kicker": kicker, "title": title, "text": text, "hit": str(hit) if hit is String else "", "color": P.role_color(me)}


## 一批年代日志 → 一张张卡（每张最多 PER_CARD 段）
static func pages(entries: Array, me: String, decade_now := "") -> Array:
	var out: Array = []
	for e in pick(entries):
		var b := block(e, me, decade_now)
		if str(b.title) == "" and str(b.text) == "":
			continue
		if out.is_empty() or (out[-1] as Array).size() >= PER_CARD:
			out.append([])
		(out[-1] as Array).append(b)
	return out


## 一张卡上从上到下的字：[[字, 字号, 颜色], …]。年代名只在头上写一回（几段同一个年代）；
## 一件大事字最大，几件排在一起就收一收；我这一句用我的颜色（墨底上提亮一点，看得清）
static func specs(page: Array) -> Array:
	var out: Array = []
	if page.is_empty():
		return out
	var n := page.size()
	var title_fs := 132 if n == 1 else (88 if n == 2 else 68)
	var text_fs := 38 if n == 1 else 32
	var last_kicker := ""
	for i in n:
		var b: Dictionary = page[i]
		if i > 0:
			out.append(["@rule", 0, Color(P.PAPER, 0.3)])
		var k := str(b.get("kicker", ""))
		if k != "" and k != last_kicker:
			out.append([k, 36, Color(P.PAPER, 0.7)])
			last_kicker = k
		if str(b.get("title", "")) != "":
			out.append([str(b.title), title_fs, P.PAPER])
		if str(b.get("text", "")) != "":
			out.append([str(b.text), text_fs, Color(P.PAPER, 0.85)])
		if str(b.get("hit", "")) != "":
			var c: Color = b.get("color", P.QING)
			out.append([str(b.hit), text_fs + 4, c.lightened(0.22)])
	return out


## 长卷 / 日志列表里的一行：「年代 · 标题」
static func log_line(e: Dictionary) -> String:
	var ev := _d(e.get("era"))
	var title := str(ev.get("title", "")) if ev.get("title") is String else ""
	return "年代 · " + (title if title != "" else str(e.get("text", "")))
