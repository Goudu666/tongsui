extends Node2D
## 一张横图的画：tools/art/scenes.py 印出来的切片 res://art/scenes/<图>_<k>.png。
##   每片横着 SLICE 世界像素、竖着从这张图的 TOP 到 BOTTOM（相对这张图的地面坐标），贴图 ART_SCALE 倍。
## 没有切片的图（还没画的），按 content/maps/<图>.yaml 的地点和地面画一张墨线草图：地点的框、名字、地面线、楼层。
## 只画眼前这一张图（换图时 show_scene），别的图不占显存。

const P := preload("res://scripts/ui/palette.gd")
const SLICE := 1024.0   ## 每片多宽（世界像素）
const TOP := -200.0     ## 切片从这张图的 y = TOP 画起（楼顶上头还有一截天）
const BOTTOM := 1000.0
const ART_SCALE := 1.25

var scene: Dictionary = {}
var zones: Array = []     ## 这张图上的地点（content.map.zones 里 scene 是它的）
var exits: Array = []
var has_art := false
var _slices: Array = []
static var _anchors: Dictionary = {}  ## anchors.json 里每张图的灯（只读一回）


func show_scene(sc: Dictionary, all_zones: Array, all_exits: Array) -> void:
	scene = sc
	zones = all_zones.filter(func(z): return str(z.scene) == str(sc.id))
	exits = all_exits.filter(func(e): return str(e.scene) == str(sc.id))
	position = Vector2(0, float(sc.top))
	for s in _slices:
		s.queue_free()
	_slices.clear()
	has_art = false
	var k := 0
	while true:
		var path := "res://art/scenes/%s_%d.png" % [sc.id, k]
		if not ResourceLoader.exists(path):
			break
		var spr := Sprite2D.new()
		spr.texture = load(path)
		spr.centered = false
		spr.scale = Vector2.ONE / ART_SCALE
		spr.position = Vector2(k * SLICE, TOP)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(spr)
		_slices.append(spr)
		has_art = true
		k += 1
	queue_redraw()


## 这张图上的灯（路灯、窗、楼道灯、摊子、远处）：坐标换成夜版自己的（从 TOP 那一行算起）
static func anchors_for(id: String) -> Dictionary:
	if _anchors.is_empty():
		var f := FileAccess.open("res://art/scenes/anchors.json", FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_anchors = d.get("scenes", {})
	var out := {}
	var src: Dictionary = _anchors.get(id, {})
	for kind in src:
		var pts: Array = []
		for p in src[kind]:
			pts.append(Vector2(float(p[0]), float(p[1]) - TOP))
		out[kind] = pts
	return out


## 这张图在世界坐标里能看见的那一截
func band() -> Rect2:
	return Rect2(0, float(scene.get("top", 0)) + TOP, float(scene.get("width", 1920)), BOTTOM - TOP)


func _draw() -> void:
	if scene.is_empty() or has_art:
		return
	var f := P.font()
	var w := float(scene.width)
	var floors: Array = scene.floors
	var top := float(scene.top)
	# 纸、远处一抹天际线
	draw_rect(Rect2(0, TOP, w, BOTTOM - TOP), P.PAPER)
	var x := 0.0
	var i := 0
	while x < w:
		var h := 120.0 + fmod(i * 73.0, 160.0)
		draw_rect(Rect2(x, float(floors[0]) - top - 380.0 - h * 0.4, 90.0 + fmod(i * 41.0, 80.0), h), Color(P.QING, 0.08))
		x += 150.0 + fmod(i * 29.0, 70.0)
		i += 1
	for fy in floors:
		var y := float(fy) - top
		draw_rect(Rect2(0, y, w, 26.0), Color(P.INK, 0.10))
		draw_line(Vector2(0, y), Vector2(w, y), P.INK, 4.0)
	for z in zones:
		var y := float(floors[int(z.floor)]) - top
		var r := Rect2(float(z.span[0]), y - 360.0, float(z.span[1]) - float(z.span[0]), 360.0)
		if z.has("owner"):
			draw_rect(r, Color(P.role_color(str(z.owner)), 0.07))
		var e := 10.0
		draw_line(Vector2(r.position.x, r.position.y - e), Vector2(r.position.x, r.end.y), Color(P.INK, 0.7), 3.0)
		draw_line(Vector2(r.end.x, r.position.y - e), Vector2(r.end.x, r.end.y), Color(P.INK, 0.7), 3.0)
		draw_line(Vector2(r.position.x - e, r.position.y), Vector2(r.end.x + e, r.position.y), Color(P.INK, 0.7), 3.0)
		draw_string(f, r.position + Vector2(24, 52), str(z.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 38, P.INK_SOFT)
	for ex in exits:
		var at := Vector2(float(ex.at[0]), float(ex.at[1]) - top)
		draw_rect(Rect2(at + Vector2(-46, -200), Vector2(92, 200)), Color(P.INK, 0.12))
		draw_rect(Rect2(at + Vector2(-46, -200), Vector2(92, 200)), P.INK, false, 3.0)
