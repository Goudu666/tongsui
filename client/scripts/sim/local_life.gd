extends RefCounted
## 本地「同屏双人」原型用的人生结算。
## 规则是 server/src/sim.ts 的 GDScript 版本，联机时以服务器结算为准。改规则时两边一起改。

const ROLES := ["qing", "mei"]
const SEASONS := ["spring", "summer", "autumn", "winter"]
const SEASON_LABEL := ["立春", "立夏", "立秋", "立冬"]
const FADE_EVERY := 8
## 时间的密度：越长大，一回合越长
const STAGES := [
	{"stage": "childhood", "from_age": 3, "tpy": 4.0, "years": 9},
	{"stage": "teen", "from_age": 12, "tpy": 2.0, "years": 6},
	{"stage": "young", "from_age": 18, "tpy": 1.0, "years": 12},
	{"stage": "middle", "from_age": 30, "tpy": 1.0 / 3.0, "years": 30},
	{"stage": "old", "from_age": 60, "tpy": 0.2, "years": 1000},
]

var events: Array = []
var by_id: Dictionary = {}
var rng := RandomNumberGenerator.new()
var turn := 0
var ended := false
var persons: Dictionary = {}
var bond: Dictionary = {"sync": 0, "close": 10, "distance": 0}
var memories: Array = []
var history: Array = []
var scene: Variant = null  ## {"kind": "mirror"/"solo", "events": {"qing": id|null, "mei": id|null}}


func _init(names: Dictionary, seed_value: int, event_list: Array) -> void:
	events = event_list
	for ev in events:
		by_id[ev.id] = ev
	by_id["_ordinary"] = ordinary_event()
	rng.seed = seed_value
	for r in ROLES:
		persons[r] = {
			"name": names.get(r, r),
			"alive": true,
			"lifespan": 66 + rng.randi_range(0, 23),
			"died_at": -1,
			"stats": {
				"body": rng.randi_range(3, 6),
				"mind": rng.randi_range(3, 6),
				"charm": rng.randi_range(3, 6),
				"heart": 5,
			},
			"flags": [],
			"tags": {},
		}
	scene = _pick_scene()


static func load_events(path: String = "res://data/events.json") -> Array:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Array else []


static func ordinary_event() -> Dictionary:
	return {
		"id": "_ordinary", "kind": "solo", "stage": "childhood", "seasons": [], "weight": 1, "requires": {},
		"title": "平淡的日子", "text": "这段日子没有什么特别的事。",
		"options": [
			{"id": "rest", "text": "好好休息", "tags": ["solitude"], "effects": {"self": {"heart": 1}, "other": {}, "bond": {}, "flags": []}},
			{"id": "work", "text": "多做一点事", "tags": ["competitive"], "effects": {"self": {"mind": 1}, "other": {}, "bond": {}, "flags": []}},
			{"id": "visit", "text": "去看看 TA", "tags": ["gentle"], "effects": {"self": {}, "other": {"heart": 1}, "bond": {"close": 1}, "flags": []}},
		],
		"resonance": null, "dissonance": null,
	}


# ---------- 时间 ----------

static func time_at(t: int) -> Dictionary:
	var start := 0
	for i in STAGES.size():
		var st: Dictionary = STAGES[i]
		var turns := int(round(st.years * st.tpy))
		if t < start + turns or i == STAGES.size() - 1:
			var k := t - start
			var age := int(floor(st.from_age + k / st.tpy))
			match st.stage:
				"childhood":
					var si := k % 4
					return {"age": age, "stage": st.stage, "season": SEASONS[si], "label": "%d 岁 · %s" % [age, SEASON_LABEL[si]]}
				"teen":
					return {"age": age, "stage": st.stage, "season": null, "label": "%d 岁 · %s" % [age, "上学期" if k % 2 == 0 else "下学期"]}
				"young":
					return {"age": age, "stage": st.stage, "season": null, "label": "%d 岁" % age}
				_:
					return {"age": age, "stage": st.stage, "season": null, "label": "%d 岁那几年" % age}
		start += turns
	return {}


func now() -> Dictionary:
	return time_at(turn)


# ---------- 抽事件 ----------

static func other(role: String) -> String:
	return "mei" if role == "qing" else "qing"


func get_event(id: String) -> Dictionary:
	return by_id[id]


func _seen() -> Dictionary:
	var seen := {}
	for e in history:
		if not e.has("events"):
			continue
		for r in ROLES:
			if e.events[r] != null:
				seen[e.events[r]] = true
	return seen


func _eligible(ev: Dictionary, t: Dictionary, flags: Array, seen: Dictionary) -> bool:
	if ev.stage != t.stage or seen.has(ev.id):
		return false
	var seasons: Array = ev.get("seasons", [])
	if seasons.size() > 0 and (t.season == null or not seasons.has(t.season)):
		return false
	var rq: Dictionary = ev.get("requires", {})
	if rq.has("minAge") and t.age < rq.minAge:
		return false
	if rq.has("maxAge") and t.age > rq.maxAge:
		return false
	for f in rq.get("flags", []):
		if not flags.has(f):
			return false
	for f in rq.get("notFlags", []):
		if flags.has(f):
			return false
	return true


func _pick_weighted(items: Array) -> Variant:
	var total := 0.0
	for it in items:
		total += float(it.weight)
	if total <= 0.0:
		return null
	var x := rng.randf() * total
	for it in items:
		x -= float(it.weight)
		if x < 0.0:
			return it
	return items[items.size() - 1]


func _pick_scene() -> Variant:
	var t := now()
	var seen := _seen()
	var alive := ROLES.filter(func(r): return persons[r].alive)
	if alive.is_empty():
		return null
	if alive.size() == 2:
		var both: Array = persons.qing.flags + persons.mei.flags
		var mirrors := events.filter(func(e): return e.kind == "mirror" and _eligible(e, t, both, seen))
		var chance := 0.55 if t.stage == "childhood" else 0.4
		if not mirrors.is_empty() and rng.randf() < chance:
			var m: Dictionary = _pick_weighted(mirrors)
			return {"kind": "mirror", "events": {"qing": m.id, "mei": m.id}}
	var sc := {"kind": "solo", "events": {"qing": null, "mei": null}}
	for r in alive:
		var flags: Array = persons[r].flags
		var solos := events.filter(func(e): return e.kind == "solo" and _eligible(e, t, flags, seen))
		var pick: Variant = _pick_weighted(solos)
		sc.events[r] = pick.id if pick != null else "_ordinary"
		if pick != null:
			seen[pick.id] = true
	return sc


func required_roles() -> Array:
	if scene == null:
		return []
	return ROLES.filter(func(r): return persons[r].alive and scene.events[r] != null)


func event_for(role: String) -> Dictionary:
	return get_event(scene.events[role])


# ---------- 结算 ----------

func _find_option(ev: Dictionary, option_id: String) -> Dictionary:
	for o in ev.options:
		if o.id == option_id:
			return o
	return {}


func _apply_stats(p: Dictionary, d: Dictionary) -> void:
	for k in d:
		p.stats[k] = clampi(int(p.stats[k] + d[k]), 0, 10)


func _apply_bond(d: Dictionary) -> void:
	if d.has("sync"):
		bond.sync = clampi(int(bond.sync + d.sync), 0, 100)
	if d.has("close"):
		bond.close = clampi(int(bond.close + d.close), -20, 100)
	if d.has("distance"):
		bond.distance = clampi(int(bond.distance + d.distance), 0, 5)


func _apply_option(role: String, o: Dictionary, from_shadow: bool) -> void:
	var me: Dictionary = persons[role]
	var eff: Dictionary = o.effects
	_apply_stats(me, eff.get("self", {}))
	var them: Dictionary = persons[other(role)]
	if them.alive:
		_apply_stats(them, eff.get("other", {}))
	_apply_bond(eff.get("bond", {}))
	for f in eff.get("flags", []):
		if not me.flags.has(f):
			me.flags.append(f)
	if not from_shadow:
		for tag in o.tags:
			me.tags[tag] = me.tags.get(tag, 0) + 1


## 结算一回合，返回本回合的日志条目（可能包含死亡与终局）
func resolve(choices: Dictionary, shadow: Array = []) -> Array:
	var t := now()
	var sc: Dictionary = scene
	var out: Array = []
	var entry := {
		"turn": turn, "age": t.age, "label": t.label, "kind": sc.kind,
		"events": sc.events.duplicate(), "choices": choices.duplicate(),
		"shadow": shadow.duplicate(), "resonance": null, "text": "",
	}
	for r in required_roles():
		var ev := event_for(r)
		_apply_option(r, _find_option(ev, choices[r]), shadow.has(r))

	if sc.kind == "mirror":
		var mev := get_event(sc.events.qing)
		if choices.qing == choices.mei:
			entry.resonance = true
			var res: Variant = mev.resonance.get(choices.qing) if mev.resonance != null else null
			if res != null:
				_apply_bond(res.get("bond", {}))
				entry.text = res.text
				if res.has("memory"):
					memories.append({"title": res.memory, "event_id": mev.id, "turn": turn, "age": t.age, "vivid": 3})
			else:
				_apply_bond({"sync": 1})
				entry.text = "你们选了同一个答案。"
		else:
			entry.resonance = false
			if mev.dissonance != null:
				_apply_bond(mev.dissonance.get("bond", {}))
				entry.text = mev.dissonance.text
	out.append(entry)

	turn += 1
	for m in memories:
		if m.vivid > 0 and (turn - m.turn) % FADE_EVERY == 0:
			m.vivid -= 1

	var nt := now()
	for r in ROLES:
		var p: Dictionary = persons[r]
		if not p.alive:
			continue
		var limit: float = p.lifespan + (p.stats.body - 5) * 0.5 + (-3 if p.stats.heart < 2 else 0)
		if nt.age >= limit or nt.age >= 100:
			p.alive = false
			p.died_at = nt.age
			out.append({"turn": turn, "age": nt.age, "label": nt.label, "kind": "death", "role": r,
				"text": "%s 在 %d 岁那年离开了。" % [p.name, nt.age]})

	if not persons.qing.alive and not persons.mei.alive:
		ended = true
		scene = null
		out.append({"turn": turn, "age": nt.age, "label": nt.label, "kind": "end", "text": epitaph()})
	else:
		scene = _pick_scene()
	history.append_array(out)
	return out


func epitaph() -> String:
	var mirrors := 0
	var hits := 0
	for e in history:
		if e.kind == "mirror":
			mirrors += 1
			if e.resonance:
				hits += 1
	var rate := roundi(100.0 * hits / mirrors) if mirrors > 0 else 0
	return "你们一起走过了 %d 个回合，留下 %d 段共同回忆，默契率 %d%%。" % [turn, memories.size(), rate]
