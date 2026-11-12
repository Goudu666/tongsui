extends Node2D
## 家里的东西：红砖楼三楼两户人家屋里摆着什么（content/home.yaml，服务器 WORLD.homes）和按家境摆的陈设。
##
## 美术：res://art/home/atlas.png + sprites.json（tools/art/pixel/pxhome.py 生成，像素版；老的孔版是 tools/art/home.py）。
## 每张精灵按它在楼里那张图上的位置印好了（at = 这张图自己的坐标，左上角，落在 3×3 的点格上），这里原样贴回去，
## 贴图 1 像素 = 1 世界像素（scale 1），不缩放不翻转；梅家是另印的镜像。
## 挑哪几张（pick）和 tools/art/home.py 的 pick() 一致：
##   家境（0 清贫 1 小康 2 殷实）定陈设：布帘子和折叠床、糊好的纸盒 / 缝纫机、圆钟 / 地板革、沙发、摆钟；电视柜是木箱子、矮柜还是玻璃门柜
##   WORLD.homes 定物件：收音机、电视、游戏机、冰箱、书柜、电话、复读机、电脑、门口的牛奶箱
##   年代（era.decade）定样子：电视先是黑白小方盒、后是彩电、再后是薄的；电脑先是大脑袋罩着布，后是薄的
## 东西进门那天（WORLD 里头一回有它）慢慢印出来；只是画面，不参与结算。
## 层级：world_view 里 z -9，贴在底图（-10）上面、人和互动点下面，夜版照样压在上头。

const ATLAS := "res://art/home/atlas.png"
const META := "res://art/home/sprites.json"
const ROLES := ["qing", "mei"]
## era.decade 的年代名 → 第几个（往后的「二〇年代」「三〇年代」「很多年以后」都算 6）
const DECADES := ["六十年代", "七十年代", "八十年代", "九十年代", "千禧年头上", "一〇年代"]
## 没有年代名（老服务器）时按街景那一套猜
const LOOK_DECADE := {"childhood": 3, "teen": 4, "young": 5, "middle": 6, "old": 6}
const FADE := 0.9  ## 新进门的东西印出来要几秒

var ready_ok := false
var scene_id := "building"     ## 只在这张图上摆（sprites.json 的 scene）
var items: Dictionary = {"qing": [], "mei": []}
var wealth: Dictionary = {"qing": 1, "mei": 1}
var decade := 3
var _atlas: Texture2D
var _sprites: Dictionary = {}
var _scale := 1.0
var _keys: Array = []          ## 现在摆着的，从后往前
var _born: Dictionary = {}     ## key -> 哪一刻开始印（秒）；一进场就有的是 -INF
var _t := 0.0
var _seen := false             ## 头一回拿到 homes 之前别放动画（进门时已经有的东西直接在）


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	if not (FileAccess.file_exists(META) and ResourceLoader.exists(ATLAS)):
		return
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(META))
	if not meta is Dictionary:
		return
	_atlas = load(ATLAS)
	_sprites = meta.get("sprites", {})
	_scale = float(meta.get("scale", 1.0))
	scene_id = str(meta.get("scene", scene_id))
	ready_ok = _atlas != null and not _sprites.is_empty()
	_rebuild(false)


## 换图：只在楼里那张图上摆，位置跟着那张图在世界里的 y
func show_scene(sc: Dictionary) -> void:
	visible = str(sc.get("id", "")) == scene_id
	position = Vector2(0, float(sc.get("top", 0)))
	queue_redraw()


## WORLD.homes：{ qing: [物件 id], mei: [...] }（world_view 已经整理成两家都有的单子）
func set_items(h: Dictionary) -> void:
	var next := {}
	for r in ROLES:
		var l: Array = h.get(r, []) if h.get(r) is Array else []
		next[r] = l.duplicate()
		next[r].sort()
	if next == items:
		_seen = true
		return
	items = next
	_rebuild(_seen)
	_seen = true


## 两家的家境（0 清贫 1 小康 2 殷实）和年代：变了才重摆（每次 WORLD 都会喂）
func set_look(p_wealth: Dictionary, decade_name: String, look: String) -> void:
	var w := {}
	for r in ROLES:
		w[r] = clampi(int(p_wealth.get(r, 1)), 0, 2)
	var d := decade_index(decade_name, look)
	if w == wealth and d == decade:
		return
	wealth = w
	decade = d
	_rebuild(false)


static func decade_index(name: String, look: String) -> int:
	var i := DECADES.find(name)
	if i >= 0:
		return i
	if name != "":
		return 6
	return int(LOOK_DECADE.get(look, 3))


## 这户人家该摆哪几张，从后往前（和 tools/art/home.py 的 pick() 一致）
static func pick(w: int, have: Array, d: int) -> Array:
	var out: Array = []
	if w == 2:
		out.append("floor_rich")
	out.append(["curtain", "sewing", "sofa"][w])
	if w == 1:
		out.append("clock_round")
	elif w == 2:
		out.append("clock_pendulum")
	var books := have.has("books")
	if books:
		out.append("bookcase")
	if have.has("radio"):
		out.append("radio_case" if books else "radio_dresser")
	out.append("cab_%d" % w)
	if w == 0:
		out.append("boxes")
	if have.has("tv"):
		var kind := "color"
		if d >= 6 or (d == 5 and w >= 1):  # 清贫人家一〇年代还看那台大脑袋彩电
			kind = "flat"
		elif d <= 2:
			kind = "color" if (w == 2 and d == 2) else "bw"
		elif w == 0 and d == 3:
			kind = "bw"
		out.append("tv_%s_%d" % [kind, w])
		if have.has("console"):
			out.append("console_%d" % w)
	if have.has("fridge"):
		out.append("fridge")
	if have.has("pc"):
		out.append("pc_lcd" if d >= 5 else "pc_crt")
	for k in ["tape", "phone", "milk"]:
		if have.has(k):
			out.append(k)
	return out


func _rebuild(animate: bool) -> void:
	if not ready_ok:
		return
	var keys: Array = []
	for r in ROLES:
		for k in pick(int(wealth[r]), items[r], decade):
			var key := "%s_%s" % [k, r]
			if _sprites.has(key):
				keys.append(key)
	var born := {}
	for key in keys:
		if _born.has(key):
			born[key] = _born[key]
		elif animate and _is_item(key):
			born[key] = _t
		else:
			born[key] = -INF
	# 换了样子（黑白换彩电）不算新进门：同一样东西的旧图在，新图就直接在
	_keys = keys
	_born = born
	set_process(animate)
	queue_redraw()


## 是「东西」而不是家境陈设：新进门才印出来（家境陈设一进场就在）
static func _is_item(key: String) -> bool:
	for p in ["radio", "tv_", "console", "fridge", "bookcase", "pc_", "tape", "phone", "milk"]:
		if key.begins_with(p):
			return true
	return false


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	for key in _keys:
		if _t - float(_born[key]) < FADE:
			return
	set_process(false)


func _draw() -> void:
	if not ready_ok or not visible:
		return
	for key in _keys:
		var sp: Dictionary = _sprites[key]
		var src := Rect2(float(sp.x), float(sp.y), float(sp.w), float(sp.h))
		var at: Array = sp.at
		var k := clampf((_t - float(_born.get(key, -INF))) / FADE, 0.0, 1.0)
		if k <= 0.0:
			continue
		# 印出来：先淡后实，往下落一点点
		var e := 1.0 - pow(1.0 - k, 3.0)
		var dst := Rect2(float(at[0]), float(at[1]) - roundf((1.0 - e) * 2.0) * 3.0, src.size.x / _scale, src.size.y / _scale)  # 落下来按整点走
		draw_texture_rect_region(_atlas, dst, src, Color(1, 1, 1, e))
